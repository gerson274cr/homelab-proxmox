output "vm_ips" {
  description = "Direcciones IP de las máquinas virtuales creadas"
  value       = { for vm in proxmox_vm_qemu.vm : vm.name => vm.default_ipv4_address }
}
