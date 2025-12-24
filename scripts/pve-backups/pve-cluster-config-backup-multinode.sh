#!/usr/bin/env bash
set -euo pipefail

### ========= VARIABLES EDITABLES (ADAPTABLE A OTROS LABS) =========

# Carpeta donde se guardan los backups en node1 (tu HDD ZFS + NFS backup path)
BACKUP_DIR="/vmstore/backups/pve-cluster-config"

# Prefijo del archivo final
BACKUP_PREFIX="cluster_config_multinode"

# Usuario dedicado para backup (NO root)
BACKUP_USER="pvebackup"

# Targets remotos (IPs o hostnames)
NODE2_TARGET="172.20.20.11"
NODE3_TARGET="172.20.20.12"

# SSH del usuario de backup en node1
SSH_KEY="/home/${BACKUP_USER}/.ssh/id_ed25519"
KNOWN_HOSTS="/home/${BACKUP_USER}/.ssh/known_hosts"

# Retención (días / cantidad)
RETENTION_DAYS=7
RETENTION_MAX_FILES=7

# Compresión zstd
ZSTD_LEVEL=19

### ===============================================================


TS="$(date +%F_%H%M%S)"
WORK="${BACKUP_DIR}/.work_${TS}"
OUT="${BACKUP_DIR}/${BACKUP_PREFIX}_${TS}.tar.zst"

mkdir -p "${BACKUP_DIR}"
mkdir -p "${WORK}/cluster" "${WORK}/nodes/node1" "${WORK}/nodes/node2" "${WORK}/nodes/node3"

# --- Helpers ---
as_backup_user() {
  runuser -u "${BACKUP_USER}" -- "$@"
}

ssh_backup_user() {
  local target="$1"
  as_backup_user ssh -T \
    -o BatchMode=yes \
    -o UserKnownHostsFile="${KNOWN_HOSTS}" \
    -o StrictHostKeyChecking=accept-new \
    -i "${SSH_KEY}" \
    "${BACKUP_USER}@${target}"
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

# --- Prechecks ---
id "${BACKUP_USER}" >/dev/null 2>&1 || fail "No existe el usuario ${BACKUP_USER} en node1."
[[ -f "${SSH_KEY}" ]] || fail "No existe SSH key: ${SSH_KEY}"

install -d -m 700 -o "${BACKUP_USER}" -g "${BACKUP_USER}" "/home/${BACKUP_USER}/.ssh"
touch "${KNOWN_HOSTS}"
chown "${BACKUP_USER}:${BACKUP_USER}" "${KNOWN_HOSTS}"
chmod 600 "${KNOWN_HOSTS}"

# --- 1) Cluster-wide config: /etc/pve (se toma local en node1) ---
tar --xattrs --acls -C / -cf "${WORK}/cluster/etc_pve.tar" etc/pve 2>/dev/null

# Estado cluster (node1)
{
  echo "=== timestamp ==="; date
  echo
  echo "=== node === node1"
  echo "=== hostname ==="; hostname
  echo
  echo "=== pveversion -v ==="; pveversion -v 2>/dev/null || true
  echo
  echo "=== pvecm status ==="; pvecm status 2>/dev/null || true
  echo
  echo "=== pvesm status ==="; pvesm status 2>/dev/null || true
} > "${WORK}/cluster/cluster_state_node1.txt"

# --- 2) Node1 node-specific snapshot ---
{
  echo "=== timestamp ==="; date
  echo
  echo "=== node === node1"
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
} > "${WORK}/nodes/node1/node_state.txt"

tar -C / -cf "${WORK}/nodes/node1/node_files.tar" \
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

# --- 3) Remotos: node2 y node3 via forced-command (export.tar es stream tar) ---
ssh_backup_user "${NODE2_TARGET}" > "${WORK}/nodes/node2/export.tar"
ssh_backup_user "${NODE3_TARGET}" > "${WORK}/nodes/node3/export.tar"

# --- 4) Empaquetar todo ---
tar -C "${WORK}" -cf - . | zstd -T0 -"${ZSTD_LEVEL}" -o "${OUT}"

# Limpieza temporal
rm -rf "${WORK}"

# --- 5) Retención ---
# A) por días (ej. 7 días => borra > 6 días)
find "${BACKUP_DIR}" -type f -name "${BACKUP_PREFIX}_*.tar.zst" -mtime +"$((RETENTION_DAYS-1))" -delete

# B) por cantidad (máx 7 archivos)
ls -1t "${BACKUP_DIR}/${BACKUP_PREFIX}_"*.tar.zst 2>/dev/null | tail -n +"$((RETENTION_MAX_FILES+1))" | xargs -r rm -f

echo "OK -> ${OUT}"
