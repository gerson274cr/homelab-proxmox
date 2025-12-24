# Proxmox Homelab — Backups de Configuración del Clúster (Multi-nodo, SSH sin root)

Este repositorio contiene scripts para generar **backups de la configuración del clúster de Proxmox** (multi-nodo) de forma **segura y reutilizable**, usando un usuario dedicado **no-root** (`pvebackup`) y llaves SSH con **forced-command**.

La guía está pensada para funcionar **en cualquier lab**, solo modificando algunas variables al inicio de cada script.

---

## ¿Qué hace esto? (y qué NO hace)

### ✅ Sí hace
- Crea un usuario dedicado **`pvebackup`** en cada nodo.
- Genera una llave SSH en **node1** para que `pvebackup` se conecte a otros nodos **sin usar root por SSH**.
- En **node2/node3**, la llave queda altamente restringida con:
  - `from="<ip_node1>"`
  - `command="/usr/local/sbin/pvebackup-export.sh"` (forced-command)
  - `no-pty`, `no-agent-forwarding`, `no-port-forwarding`, `no-X11-forwarding`
- Genera en **node1** un **solo archivo comprimido** `.tar.zst` con:
  - Configuración **cluster-wide**: `/etc/pve` (capturada localmente en node1)
  - Captura **node-specific** de node1
  - Export remoto (node2/node3) por SSH usando `pvebackup` + forced-command
- Aplica **retención** configurable (por defecto: **7 días / 7 archivos**)

### ❌ NO hace
- No hace backups de discos de VMs/CTs (`vzdump` / PBS no está incluido aquí).
- No envía backups a la nube automáticamente (puedes copiar manualmente a otro destino).

---

## Scripts incluidos

### 1) `setup_pvebackup_node1.sh` (se ejecuta en node1)
- Crea el usuario `pvebackup` en node1 (si no existe)
- Genera la llave SSH para `pvebackup`
- Imprime la **public key** para pegarla en node2/node3
- (Opcional) hace pruebas de conectividad (puede fallar si aún no configuraste los remotos)

### 2) `setup_pvebackup_remote.sh` (se ejecuta en node2 y node3)
- Crea el usuario `pvebackup` (si no existe)
- Instala el exporter forced-command:
  - `/usr/local/sbin/pvebackup-export.sh`
- Configura `authorized_keys` con restricciones y forced-command

### 3) `pve-cluster-config-backup-multinode.sh` (se ejecuta en node1)
- Genera el backup final en node1 (`tar.zst`)
- “Jala” exports de node2/node3 por SSH usando `pvebackup`
- Mantiene retención (por días y por cantidad)

---

## Requisitos

- Acceso a cada nodo como **root localmente** (solo para el setup inicial)
- Conectividad entre nodos por la red de mgmt
- SSH activo en todos los nodos
- `runuser` (viene en Debian/Proxmox)
- `zstd` instalado (si no está: `apt install -y zstd`)

> Nota: No se requiere `sudo` ni `visudo`.

---

# Guía rápida (aplicable a cualquier lab)

## Paso 0 — Define roles y variables
Decide:
- Cuál será el nodo “orquestador” del backup (recomendado: **node1**)
- IP/hostname de node2 y node3
- Dónde se guardarán los backups en node1 (dataset ZFS o disco de backups)

---

## Paso 1 — Configurar node1 (generar llave)
En **node1** como root:

1) Copia `setup_pvebackup_node1.sh` a `/root/` y ejecútalo:
```bash
bash /root/setup_pvebackup_node1.sh
```

2) El script imprimirá una **PUBLIC KEY**, por ejemplo:
```text
ssh-ed25519 AAAAC3... pvebackup@node1
```

Copia **la línea completa**. La vas a pegar en el script remoto.

---

## Paso 2 — Configurar node2 y node3 (instalar exporter + llave restringida)
En **node2** como root:

1) Copia `setup_pvebackup_remote.sh` a `/root/`
2) Edita variables al inicio del script:
   - `ALLOWED_SOURCE_IP` → IP de node1 (mgmt)
   - `NODE1_PUBLIC_KEY` → pega aquí la public key completa
3) Ejecuta:
```bash
bash /root/setup_pvebackup_remote.sh
```

Repite lo mismo en **node3**.

---

## Paso 3 — Verificar que el export restringido funciona
En **node1** como root:

```bash
runuser -u pvebackup -- ssh -T \
  -o UserKnownHostsFile=/home/pvebackup/.ssh/known_hosts \
  -o StrictHostKeyChecking=accept-new \
  -o BatchMode=yes \
  -i /home/pvebackup/.ssh/id_ed25519 \
  pvebackup@<IP_NODE2> | tar -tv | head
```

Salida esperada:
- `node_state.txt`
- `node_files.tar`

Repite para node3.

---

## Paso 4 — Instalar el script de backup multi-nodo en node1
En **node1**:

1) Coloca `pve-cluster-config-backup-multinode.sh` en:
```bash
/usr/local/sbin/pve-cluster-config-backup-multinode.sh
```

2) Hazlo ejecutable:
```bash
chmod +x /usr/local/sbin/pve-cluster-config-backup-multinode.sh
```

3) Edita variables dentro del script para tu lab:
- `BACKUP_DIR`
- `BACKUP_USER`
- `NODE2_TARGET`, `NODE3_TARGET`
- retención (opcional)

4) Ejecuta manualmente:
```bash
/usr/local/sbin/pve-cluster-config-backup-multinode.sh
```

---

# Formato del backup (qué contiene)

El backup se guarda en:
- `BACKUP_DIR` (ejemplo): `/vmstore/backups/pve-cluster-config`

Nombre:
- `cluster_config_multinode_YYYY-MM-DD_HHMMSS.tar.zst`

Dentro del backup:
- `cluster/etc_pve.tar` → `/etc/pve` (config del clúster)
- `cluster/cluster_state_node1.txt` → estado del clúster (node1)
- `nodes/node1/node_state.txt` + `nodes/node1/node_files.tar`
- `nodes/node2/export.tar` (stream tar remoto: `node_state.txt` + `node_files.tar`)
- `nodes/node3/export.tar` (igual)

---

# Cómo inspeccionar un backup (rápido)

En **node1**:

```bash
BACKUP="$(ls -1t /vmstore/backups/pve-cluster-config/cluster_config_multinode_*.tar.zst | head -n1)"
zstd -dc "$BACKUP" | tar -tv | head -n 40
```

Ver contenido del export de node2:
```bash
zstd -dc "$BACKUP" | tar -xOf - nodes/node2/export.tar | tar -tv | head
```

---

# Retención (por defecto: 7 días)

El script aplica dos reglas:
- Borra archivos con **más de 7 días** (mtime > 6)
- Mantiene un máximo de **7 archivos** aunque haya timestamps raros

Variables:
- `RETENTION_DAYS=7`
- `RETENTION_MAX_FILES=7`

---

# Modelo de seguridad (por qué es seguro)

- No se usa root por SSH para backups
- `pvebackup` en node2/node3 queda “enjaulado”:
  - Solo acepta conexiones desde node1 (`from="IP"`)
  - Solo ejecuta el exporter (`command="..."`)
  - Sin PTY y sin forwardings

> Nota: node1 sigue siendo un nodo de alta confianza. Si node1 es comprometido, un atacante podría ejecutar el exporter remoto, pero no ejecutar comandos arbitrarios.

---

# Adaptación a otros labs (qué variables cambiar)

### En `setup_pvebackup_node1.sh`
- `BACKUP_USER`
- `REMOTE_NODES=(...)`
- (opcional) key path/comment

### En `setup_pvebackup_remote.sh`
- `ALLOWED_SOURCE_IP`
- `EXPORTER_PATH`
- `NODE1_PUBLIC_KEY`

### En `pve-cluster-config-backup-multinode.sh`
- `BACKUP_DIR`
- `NODE2_TARGET`, `NODE3_TARGET`
- `RETENTION_DAYS`, `RETENTION_MAX_FILES`

---

# Troubleshooting

### Error: `/usr/local/sbin/pvebackup-export.sh: No such file or directory`
En el remoto:
```bash
ls -l /usr/local/sbin/pvebackup-export.sh
cat /home/pvebackup/.ssh/authorized_keys
```
Revisa que el `command="..."` apunte a la ruta exacta.

### Primer SSH: “The authenticity of host can’t be established”
Es normal la primera vez. Se guarda en:
- `/home/pvebackup/.ssh/known_hosts`

### Warning: permisos `/etc/ssh/ssh_known_hosts`
Solución: usar el known_hosts del usuario `pvebackup` (ya incluido en comandos/scripts).

---

# Siguientes pasos (opcional)
- Copiar manualmente estos `.tar.zst` a tu Mac para “offsite”
- Si luego quieres automatizar, puedes usar systemd timers o un pull desde tu Mac con `rsync`
- Para backups de VMs/CTs, configura `vzdump` aparte hacia tu `backup-nfs`

---

