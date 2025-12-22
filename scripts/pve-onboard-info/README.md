# pve-onboard-info.sh

Script de **inventario/diagnóstico** de nodos Proxmox VE para *homelabs* y clústeres
ligeros. Recolecta toda la información relevante (versión de PVE, kernel, red,
corosync, storage, SMART, GPU/IOMMU, watchdog, etc.), genera un **resumen con
PASS/WARN/FAIL** y empaqueta todo en un **.tar.gz** listo para subir/archivar.

> ✅ **Modo solo lectura**: no modifica configuración ni escribe fuera de su carpeta de salida.

---

## ¿Para qué sirve?

- **Onboarding de nodos** nuevos o modificados antes de unirlos al clúster.
- **Auditoría rápida** cuando algo “no cuadra” (latencia de corosync, MTU, reloj).
- **Trazabilidad**: snapshot de estado que puedes versionar en Git.

---

## Requisitos

- Sistema base: Proxmox VE (Debian).
- Usuario: `root` (o privilegios equivalentes).
- Paquetes **opcionales** (el script continúa si faltan):
  - `smartmontools` (para SMART)
  - `zfsutils-linux` (si usas ZFS)

Instalación opcional:
```bash
apt update
apt -y install smartmontools zfsutils-linux
