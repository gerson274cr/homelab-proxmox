# Variables de conexión a Proxmox
variable "proxmox_url" {
  description = "URL del servidor Proxmox"
  type        = string
}

variable "proxmox_token_id" {
  description = "ID del API Token de Proxmox"
  type        = string
  sensitive   = true
}

variable "proxmox_token_secret" {
  description = "Secreto del API Token de Proxmox"
  type        = string
  sensitive   = true
}

variable "pm_tls_insecure" {
  description = "Permitir conexión insegura (true si no hay certificados válidos)"
  type        = bool
  default     = true
}

# Variable para las máquinas virtuales
variable "vms" {
  description = "Lista de máquinas virtuales a crear"
  type = list(object({
    name        = string
    vmid_start  = number
    count       = number
    memory      = number
    sockets     = number
    cores       = number
    disk_size   = string
    network     = string
    template    = string
    node        = string
  }))
}
