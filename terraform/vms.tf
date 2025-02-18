resource "proxmox_vm_qemu" "vm" {
  for_each = {
    for vm in flatten([
      for v in var.vms : [
        for i in range(v.count) : {
          name        = "${v.name}-${i + 1}" # test-vm-1, test-vm-2...
          vmid        = v.vmid_start + i # VMID dinámico
          memory      = v.memory
          sockets     = v.sockets
          cores       = v.cores
          disk_size   = v.disk_size
          network     = v.network
          template    = v.template
          node        = v.node
        }
      ]
    ]) : vm.name => vm
  }

  name        = each.value.name
  target_node = each.value.node
  vmid        = each.value.vmid
  clone       = each.value.template
  cpu         = "host"
  sockets     = each.value.sockets
  cores       = each.value.cores
  memory      = each.value.memory

  network {
    model  = "virtio"
    bridge = each.value.network
  }

  disk {
    type    = "scsi"
    storage = "local-lvm"
    size    = each.value.disk_size
  }
  clone_wait         = 15  # Espera 60 segundos después de clonar
}
