#!/usr/bin/env bash
set -euo pipefail

### ========= VARIABLES EDITABLES =========
BACKUP_USER="pvebackup"

# IP/host del nodo que se permite conectar (node1)
ALLOWED_SOURCE_IP="172.20.20.10"

# Ruta del script forced-command
EXPORTER_PATH="/usr/local/sbin/pvebackup-export.sh"

# PEGA AQUÍ la llave pública generada en node1 (UNA SOLA LÍNEA completa)
# Ejemplo: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... pvebackup@node1
NODE1_PUBLIC_KEY="PEGAR_AQUI_LA_PUBLIC_KEY_DE_NODE1"
### =======================================

if [[ "${NODE1_PUBLIC_KEY}" == "PEGAR_AQUI_LA_PUBLIC_KEY_DE_NODE1" ]]; then
  echo "ERROR: Debes pegar la PUBLIC KEY de node1 en la variable NODE1_PUBLIC_KEY."
  exit 1
fi

echo "[1/5] Creando usuario ${BACKUP_USER} (si no existe)..."
if ! id "${BACKUP_USER}" &>/dev/null; then
  adduser --disabled-password --gecos "" "${BACKUP_USER}"
fi
passwd -l "${BACKUP_USER}" >/dev/null 2>&1 || true

echo "[2/5] Instalando exporter forced-command..."
cat > "${EXPORTER_PATH}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

{
  echo "=== timestamp ==="; date
  echo
  echo "=== hostname ==="; hostname
  echo
  echo "=== pveversion -v ==="; pveversion -v 2>/dev/null || true
  echo
  echo "=== ip -br a ==="; ip -br a 2>/dev/null || true
  echo
  echo "=== ip route ==="; ip route 2>/dev/null || true
  echo
  echo "=== zpool status ==="; zpool status 2>/dev/null || true
  echo
  echo "=== zfs list ==="; zfs list 2>/dev/null || true
} > "$TMP/node_state.txt"

tar -C / -cf "$TMP/node_files.tar" \
  etc/network \
  etc/hosts \
  etc/fstab \
  etc/resolv.conf \
  etc/apt \
  etc/sysctl.conf \
  etc/sysctl.d \
  etc/modprobe.d \
  etc/modules \
  etc/default \
  2>/dev/null || true

tar -C "$TMP" -cf - node_state.txt node_files.tar
EOF

chmod 755 "${EXPORTER_PATH}"
chown root:root "${EXPORTER_PATH}"

echo "[3/5] Configurando ~/.ssh/authorized_keys con restricciones..."
install -d -m 700 -o "${BACKUP_USER}" -g "${BACKUP_USER}" "/home/${BACKUP_USER}/.ssh"
AUTH_KEYS="/home/${BACKUP_USER}/.ssh/authorized_keys"

LINE="from=\"${ALLOWED_SOURCE_IP}\",command=\"${EXPORTER_PATH}\",no-port-forwarding,no-agent-forwarding,no-pty,no-X11-forwarding ${NODE1_PUBLIC_KEY}"

# Reemplaza todo el authorized_keys por esta única llave (más seguro/limpio)
printf "%s\n" "${LINE}" > "${AUTH_KEYS}"

chown "${BACKUP_USER}:${BACKUP_USER}" "${AUTH_KEYS}"
chmod 600 "${AUTH_KEYS}"

echo "[4/5] Permisos finales..."
chown -R "${BACKUP_USER}:${BACKUP_USER}" "/home/${BACKUP_USER}/.ssh"
chmod 700 "/home/${BACKUP_USER}/.ssh"

echo "[5/5] Validación local..."
ls -l "${EXPORTER_PATH}"
echo "authorized_keys:"
cat "${AUTH_KEYS}"

echo
echo "Listo. Ahora prueba desde node1 con:"
echo "runuser -u ${BACKUP_USER} -- ssh -T -i /home/${BACKUP_USER}/.ssh/id_ed25519 ${BACKUP_USER}@$(hostname -I | awk '{print $1}') | tar -tv | head"
