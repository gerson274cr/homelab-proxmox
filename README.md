# homelab-proxmox
## 🚀 Integración con GitHub Actions

Este repositorio cuenta con un **workflow de GitHub Actions** que valida automáticamente el código Terraform en cada Pull Request.

### 🔹 Validaciones Implementadas:
✔️ `terraform fmt -check` → Verifica que el código tenga el formato correcto.  
✔️ `terraform validate` → Comprueba que la sintaxis y configuración de Terraform sean correctas.  

### 🔹 Cómo Funciona:
1. Cada vez que se crea o actualiza un **Pull Request** hacia `main`, el workflow se ejecuta.
2. Si las validaciones pasan ✅, se puede proceder a hacer `terraform apply` manualmente.
3. Si las validaciones fallan ❌, GitHub mostrará errores en la pestaña **"Actions"**.

### 🔹 Archivo del Workflow:
📄 `.github/workflows/terraform-ci.yml`
