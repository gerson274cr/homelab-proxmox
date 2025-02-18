# 🏠 Terraform Proxmox Home Lab 🚀

Automatización de la infraestructura de un **Home Lab en Proxmox** utilizando **Terraform**. Este proyecto permite la creación dinámica de **máquinas virtuales (VMs)** con una configuración escalable, reutilizable y segura.  

---

## 📌 **Características**

✅ **Automatización Completa**: Creación de VMs en Proxmox usando Terraform.  
✅ **Infraestructura Modular**: Configuración separada en archivos (`provider.tf`, `vms.tf`, `variables.tf`).  
✅ **Manejo de Réplicas**: Crea múltiples instancias de una VM fácilmente.  
✅ **Configuración con Variables**: Facilita la personalización sin modificar el código.  
✅ **Tiempo de Espera Optimizado**: Se usa `clone_wait` para evitar fallos en la clonación.   

---

## 📚 **Estructura del Proyecto**

```
📂 terraform/
│—— 📝 main.tf            # Archivo principal
│—— 📝 provider.tf        # Configuración del proveedor Proxmox
│—— 📝 variables.tf       # Definición de variables globales
│—— 📝 terraform.tfvars   # Valores de las variables (modificable por el usuario)
│—— 📝 vms.tf             # Configuración de las máquinas virtuales
│—— 📝 outputs.tf         # Salidas de Terraform
│—— 📝 .gitignore         # Evita subir archivos sensibles como terraform.tfstate
```

---

## 🛠️ **Configuración Inicial**

1. **Clonar el Repositorio**  
```bash
git clone https://github.com/gerson274cr/homelab-proxmox.git
cd homelab-proxmox/terraform
```

2. **Configurar `terraform.tfvars` con tus valores personalizados**  
Edita el archivo `terraform.tfvars` y reemplaza los valores según tu entorno:  

```hcl
# Credenciales de Proxmox
proxmox_url          = "El url de tu proxmox
proxmox_token_id     = "El token ID de tu proxmox"
proxmox_token_secret = "El token ID de tu proxmox"
pm_tls_insecure      = true  # Cambiar a false si se usa SSL válido

# Lista de máquinas virtuales con réplicas
vms = [
  {
    name      = "test-vm"
    vmid_start = 1001
    count     = 3
    memory    = 2048
    cores     = 2
    disk_size = "10G"
    network   = "vmbr0"
    template  = "debian-template"
    node      = "home"
  }
]
```

---

## 🚀 **Desplegar Infraestructura con Terraform**

1. **Inicializar Terraform**  
```bash
terraform init
```

2. **Planificar la Creación de VMs**  
```bash
terraform plan -var-file="terraform.tfvars"
```

3. **Aplicar los Cambios**  
```bash
terraform apply -var-file="terraform.tfvars" -auto-approve
```

---

## ❌ **Eliminar las VMs con Terraform**

```bash
terraform destroy -var-file="terraform.tfvars" -auto-approve
```

⚠️ **ADVERTENCIA:** Esto **eliminará todas las VMs creadas por Terraform**.  

---

## 📊 **Monitoreo y Debugging**

Si alguna VM falla al crearse, revisa estos pasos:

✅ **Ver logs en Terraform:**  
```bash
terraform apply -var-file="terraform.tfvars" -auto-approve
```
✅ **Ver logs en Proxmox:**  
```bash
journalctl -u pveproxy --no-pager | tail -n 50
```
✅ **Verificar Recursos Disponibles en Proxmox:**  
```bash
htop   # Uso de CPU y RAM
df -h  # Espacio en disco
```
✅ **Ejecutar Terraform con Paralelismo Reducido:**  
```bash
terraform apply -var-file="terraform.tfvars" -auto-approve -parallelism=1
```

---

## 📄 **Créditos y Licencia**

Este proyecto está bajo la **Licencia MIT**, lo que significa que puedes usarlo, modificarlo y compartirlo libremente.  

Si encuentras útil este proyecto, ¡dale ⭐ en GitHub y colabora con mejoras! 🚀  

---

##  **Contacto**

💡 ¿Tienes dudas o sugerencias? Contáctame:  
📧 Email: [gerson274cr@gmail.com](mailto:gerson274cr@gmail.com)  
🐙 GitHub: [github.com/gerson274cr](https://github.com/gerson274cr)  

---

🎉 **¡Disfruta tu infraestructura automatizada con Terraform y Proxmox!** 🚀  

