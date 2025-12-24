#!/usr/bin/env bash
set -euo pipefail

### ========= VARIABLES EDITABLES =========
BACKUP_USER="pvebackup"
KEY_TYPE="ed25519"
KEY_COMMENT="pvebackup@node1"
KEY_PATH="/home/${BACKUP_USER}/.ssh/id_${KEY_TYPE}"

# Hosts remotos a los que se conectará node1 (IPs o hostnames)
REMOTE_NODES=("172.20.20.11" "172.20.20.12")

# Archivo known_hosts del usuario backup (evita permisos en /etc/ssh/ssh_known_hosts)
KNOWN_HOSTS="/home/${BACKUP_USER}/.ssh/known_hosts"
### =======================================

echo "[1/4] Creando usuario ${BACKUP_USER} (si no existe)..."
if ! id "${BACKUP_USER}" &>/dev/null; then
  adduser --disabled-password --gecos "" "${BACKUP_USER}"
fi
passwd -l "${BACKUP_USER}" >/dev/null 2>&1 || true

echo "[2/4] Preparando ~/.ssh..."
install -d -m 700 -o "${BACKUP_USER}" -g "${BACKUP_USER}" "/home/${BACKUP_USER}/.ssh"
touch "${KNOWN_HOSTS}"
chown "${BACKUP_USER}:${BACKUP_USER}" "${KNOWN_HOSTS}"
chmod 600 "${KNOWN_HOSTS}"

echo "[3/4] Generando llave SSH si no existe..."
if [[ ! -f "${KEY_PATH}" ]]; then
  runuser -u "${BACKUP_USER}" -- ssh-keygen -t "${KEY_TYPE}" -f "${KEY_PATH}" -N "" -C "${KEY_COMMENT}"
else
  echo "  - Llave ya existe: ${KEY_PATH}"
fi

echo
echo "================= PUBLIC KEY ================="
cat "${KEY_PATH}.pub"
echo "==============================================="
echo

echo "[4/4] Prueba rápida (cuando ya hayas pegado la pubkey en node2/node3)..."
for n in "${REMOTE_NODES[@]}"; do
  echo " -> Probando SSH a ${n} (puede fallar si aún no configuraste el remote):"
  set +e
  runuser -u "${BACKUP_USER}" -- ssh -T \
    -o BatchMode=yes \
    -o UserKnownHostsFile="${KNOWN_HOSTS}" \
    -o StrictHostKeyChecking=accept-new \
    -i "${KEY_PATH}" \
    "${BACKUP_USER}@${n}" true
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    echo "    (OK por ahora) Aún no está configurado el remote o falta la llave."
  else
    echo "    OK"
  fi
done

echo
echo "Listo en node1. Ahora ejecuta el script remoto en node2/node3 pegando la PUBLIC KEY arriba."
