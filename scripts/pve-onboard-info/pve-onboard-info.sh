#!/usr/bin/env bash
# pve-onboard-info.sh — Inventario/diagnóstico integral para nodos Proxmox
# Modo: SOLO LECTURA. Crea un paquete .tar.gz con toda la info útil para alta/changes de nodos.
# Autor: @gerson274cr

set -euo pipefail
shopt -s nullglob

# ========= CONFIGURACIÓN BÁSICA (ajústala si cambian tus IP/hostnames) =========
# Puedes sobreescribir vía variable de entorno EXPECTED_HOSTS="IP:HOST,IP:HOST"
DEFAULT_EXPECTED_HOSTS="172.20.20.10:node1,172.20.20.11:node2,172.20.20.12:node3"
EXPECTED_HOSTS="${EXPECTED_HOSTS:-$DEFAULT_EXPECTED_HOSTS}"
IOMMU_EXPECTED="intel_iommu=on iommu=pt"   # Para Intel; en AMD: amd_iommu=on iommu=pt
# ===============================================================================

# Colores
if [ -t 1 ]; then
  GREEN='\e[32m'; YELLOW='\e[33m'; RED='\e[31m'; CYAN='\e[36m'; BOLD='\e[1m'; RESET='\e[0m'
else
  GREEN=''; YELLOW=''; RED=''; CYAN=''; BOLD=''; RESET=''
fi
hr()   { printf "\n${CYAN}=== %s ===${RESET}\n" "$*"; }
ok()   { printf "${GREEN}PASS${RESET}  - %s\n" "$*"; }
warn() { printf "${YELLOW}WARN${RESET}  - %s\n" "$*"; }
fail() { printf "${RED}FAIL${RESET}  - %s\n" "$*"; }
info() { printf "INFO  - %s\n" "$*"; }

# Estructura de salida
ts="$(date +%F_%H%M%S)"
host="$(hostname)"
base="/root/pve_onboard_${host}_${ts}"
mkdir -p "$base"/{00_summary,10_system,20_time,30_network,40_cluster,50_storage,60_disks,70_gpu_iommu,80_watchdog,90_misc}
summary="$base/00_summary/summary.txt"
exec > >(tee -a "$summary") 2>&1

printf "${BOLD}Proxmox Onboarding Report${RESET} — Host: %s — %s\n" "$host" "$ts"

# Utilidad para ejecutar y guardar a archivo sin romper el flujo si el comando falta
run() {
  local outfile="$1"; shift || true
  ( "$@" ) >"$outfile" 2>&1 || true
}

# ===== 1) VERSIONES / KERNEL / HARDWARE =====
hr "1) Versiones/Kernels/Hardware"
run "$base/10_system/pveversion.txt" pveversion -v
if command -v pveversion >/dev/null 2>&1; then
  ok "pveversion detectado. Ver detalles en 10_system/pveversion.txt"
else
  warn "pveversion no detectado (¿no es host PVE?)."
fi
kernel="$(uname -r)"; info "Kernel: $kernel"
run "$base/10_system/uname.txt" uname -a
run "$base/10_system/hostnamectl.txt" hostnamectl
run "$base/10_system/lscpu.txt" lscpu
run "$base/10_system/mem.txt" free -h
run "$base/10_system/uptime.txt" uptime

# ===== 2) HORA / NTP =====
hr "2) Hora/NTP"
run "$base/20_time/timedatectl.txt" timedatectl status
synced="$(timedatectl 2>/dev/null | awk -F': ' '/System clock synchronized/ {print $2}')"
if [[ "${synced:-no}" == "yes" ]]; then ok "Reloj sincronizado."; else warn "Reloj NO sincronizado (ver 20_time/timedatectl.txt)."; fi

# ===== 3) RED =====
hr "3) Red (IP/Interfaces/Bridges/Routes)"
run "$base/30_network/ip_addr.txt"     ip -br a
run "$base/30_network/ip_link.txt"     ip link
run "$base/30_network/ip_route.txt"    ip route
run "$base/30_network/interfaces.txt"  bash -lc '[[ -f /etc/network/interfaces ]] && cat /etc/network/interfaces || true'
run "$base/30_network/bridge_link.txt" bash -lc 'command -v bridge >/dev/null && bridge link show || true'
run "$base/30_network/bridge_vlan.txt" bash -lc 'command -v bridge >/dev/null && bridge -c vlan show || true'
ok "Config de red recolectada (30_network/*)."

# ===== 4) CLUSTER / COROSYNC =====
hr "4) Cluster/Corosync"
run "$base/40_cluster/pvecm_status.txt"     pvecm status
run "$base/40_cluster/corosync_conf.txt"    bash -lc '[[ -f /etc/pve/corosync.conf ]] && cat /etc/pve/corosync.conf || true'
run "$base/40_cluster/corosync_journal.txt" journalctl -u corosync -n 300 --no-pager
ok "Estado de cluster recolectado (40_cluster/*)."

# ===== 5) STORAGE (PVE + LVM + ZFS) =====
hr "5) Storage (storage.cfg, pvesm, LVM, ZFS, lsblk)"
run "$base/50_storage/storage_cfg.txt"   bash -lc '[[ -f /etc/pve/storage.cfg ]] && cat /etc/pve/storage.cfg || true'
run "$base/50_storage/pvesm_status.txt"  pvesm status
run "$base/50_storage/lsblk.txt"         bash -lc 'lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL | sed "s/ \+/ /g"'
run "$base/50_storage/lvm.txt"           bash -lc 'command -v pvs >/dev/null && { pvs; vgs; lvs; } || true'
# ZFS si existe
if command -v zpool >/dev/null 2>&1; then
  run "$base/50_storage/zpool_status.txt"  zpool status -v
  run "$base/50_storage/zpool_list.txt"    zpool list -v
  if command -v zfs >/dev/null 2>&1; then
    # Propiedades esenciales
    run "$base/50_storage/zfs_props.txt" bash -lc 'for p in $(zpool list -H -o name 2>/dev/null); do echo "== $p =="; zfs get -H -o property,value compression,atime,xattr,dnodesize "$p" 2>/dev/null; done'
  fi
fi
ok "Inventario de storage recolectado (50_storage/*)."

# ===== 6) DISKS / SMART =====
hr "6) Discos SMART (salud básica)"
if command -v smartctl >/dev/null 2>&1; then
  disks=(/dev/sd? /dev/nvme?n?)
  if [ ${#disks[@]} -eq 0 ]; then
    info "No se detectaron /dev/sdX o /dev/nvmeX."
  fi
  report="$base/60_disks/smart_summary.txt"
  : > "$report"
  for d in "${disks[@]}"; do
    {
      echo "-- $d --"
      smartctl -i "$d" 2>/dev/null | egrep -i 'Model|Serial|Capacity|Total NVM Capacity|User Capacity' || true
      if smartctl -H "$d" 2>/dev/null | grep -qi 'PASSED'; then
        echo "SMART: PASSED"
      else
        echo "SMART: !ATENCIÓN! (no PASSED)"
      fi
      smartctl -A "$d" 2>/dev/null | egrep -i 'Reallocated|Uncorrect|Current_Pending|CRC|CRC_Error_Count' || true
      echo
    } >> "$report"
  done
  ok "SMART recopilado (60_disks/smart_summary.txt)."
else
  warn "smartctl no instalado. Instala: apt -y install smartmontools (luego re-ejecuta)."
fi

# ===== 7) GPU / IOMMU / VFIO =====
hr "7) GPU/IOMMU/Passthrough"
run "$base/70_gpu_iommu/lspci_gpu.txt" bash -lc 'lspci -nnk | grep -A3 -E "VGA|3D|Display"'
run "$base/70_gpu_iommu/dev_dri.txt"   bash -lc 'ls -l /dev/dri 2>/dev/null || true'
run "$base/70_gpu_iommu/lsmod_gpu.txt" bash -lc 'lsmod | egrep "i915|amdgpu|nvidia|nouveau" || true'
cmdline="$(cat /proc/cmdline 2>/dev/null || true)"
echo "$cmdline" > "$base/70_gpu_iommu/cmdline.txt"
# Resumen rápido en pantalla
if echo "$cmdline" | grep -q 'iommu=pt' && echo "$cmdline" | grep -Eq 'intel_iommu=on|amd_iommu=on'; then
  ok "IOMMU en cmdline detectado."
else
  warn "IOMMU incompleto en cmdline. Recomendado: $IOMMU_EXPECTED (ver 70_gpu_iommu/cmdline.txt)."
fi
iommu_groups="$(find /sys/kernel/iommu_groups -type l 2>/dev/null | wc -l || true)"
info "Grupos IOMMU detectados: ${iommu_groups}"

# ===== 8) WATCHDOG / HA =====
hr "8) Watchdog/HA"
run "$base/80_watchdog/dev_watchdog.txt" bash -lc 'ls -l /dev/watchdog* 2>/dev/null || true'
if systemctl is-active --quiet watchdog 2>/dev/null; then
  ok "Servicio watchdog ACTIVO."
else
  warn "Servicio watchdog NO activo."
fi
run "$base/80_watchdog/watchdog_status.txt" systemctl status watchdog
run "$base/80_watchdog/watchdog_modules.txt" bash -lc 'lsmod | egrep "iTCO_wdt|ipmi_watchdog|softdog" || true'
run "$base/80_watchdog/pve_ha_manager.txt" bash -lc '[[ -f /etc/default/pve-ha-manager ]] && cat /etc/default/pve-ha-manager || true'

# ===== 9) /etc/hosts y validaciones =====
hr "9) /etc/hosts y validación"
run "$base/90_misc/etc_hosts.txt" bash -lc '[[ -f /etc/hosts ]] && cat /etc/hosts || true'
missing=0
IFS=',' read -r -a pairs <<< "$EXPECTED_HOSTS"
for pair in "${pairs[@]}"; do
  ip="${pair%%:*}"; hn="${pair##*:}"
  if grep -Eq "^[[:space:]]*$ip[[:space:]]+$hn(\s|$)" /etc/hosts 2>/dev/null; then
    ok "/etc/hosts contiene: $ip  $hn"
  else
    missing=1
    warn "Falta '$ip  $hn' en /etc/hosts"
  fi
done
echo "Validación sugerida: getent hosts ${pairs[*]/*:}" >> "$base/90_misc/etc_hosts.txt"

# ===== 10) INVENTARIO VMs y CTs (útil para plan de replicación/HA) =====
hr "10) Inventario de VMs/CTs"
run "$base/90_misc/qm_list.txt" bash -lc 'command -v qm >/dev/null && qm list || true'
run "$base/90_misc/pct_list.txt" bash -lc 'command -v pct >/dev/null && pct list || true'

# ===== 11) EMPAQUE =====
hr "11) Paquete para exportar"
tarball="${base}.tar.gz"
tar -C "$(dirname "$base")" -czf "$tarball" "$(basename "$base")"
ok "Paquete generado: $tarball"
echo "Para copiarlo desde macOS: scp root@${host}:${tarball} ."

# ===== 12) RESUMEN FINAL EN CLARO =====
hr "Resumen final (acciones sugeridas)"
echo "- Si viste WARN de IOMMU: edita /etc/default/grub y añade: $IOMMU_EXPECTED ; luego update-grub y reboot."
echo "- Si viste WARN de watchdog: configura y activa watchdog para HA."
echo "- Si faltan líneas en /etc/hosts: añádelas con nano y valida con getent."
echo "- Revisa 50_storage/* y 60_disks/* antes de decidir ZFS/LVM."
echo
echo "Listo. Sube el .tar.gz o pégame cualquier WARN/FAIL y lo corregimos."
