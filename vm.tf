provider "azurerm" {
  version = "=2.40.0"
  features {}
}

variable "worker_node_linux" {
  default = 3
}
variable "worker_node_windows" {
  default = 2
}

variable "controlplane_node_linux" {
  default = 1
}

variable "jumpbox_windows" {
  default = 1
}

locals {
  total_vms = var.worker_node_linux + var.worker_node_windows + var.controlplane_node_linux + var.jumpbox_windows
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-rancher"
  location = "southeastasia"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-rancher"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}



// NSG
resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-rancher"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_network_security_rule" "nsg-rule" {
  name                        = "remoteaccess"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["22", "3389"]
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

resource "azurerm_subnet_network_security_group_association" "nsg-assosiation" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

// NIC
resource "azurerm_network_interface" "nic-worker" {
  count               = var.worker_node_linux + var.worker_node_windows
  name                = "nic-worker${count.index}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "configuration"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = element(azurerm_public_ip.pip-worker.*.id, count.index)
  }
}

resource "azurerm_network_interface" "nic-jumpbox" {
  count               = var.jumpbox_windows
  name                = "nic-jumpbox${count.index}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "configuration"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = element(azurerm_public_ip.pip-jumpbox.*.id, count.index)
  }
}
// Public IP
resource "azurerm_public_ip" "pip-worker" {
  count               = var.worker_node_linux + var.worker_node_windows
  name                = "pip-worker${count.index}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
  allocation_method   = "Static"
}
resource "azurerm_public_ip" "pip-jumpbox" {
  count               = var.jumpbox_windows
  name                = "pip-jumpbox${count.index}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
  allocation_method   = "Static"
}

// VM worker - Linux
resource "azurerm_linux_virtual_machine" "worker-linux" {
  count               = var.worker_node_linux
  name                = "vm${count.index}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B2s"
  zone                = (count.index % 3) + 1
  admin_username      = "tsunomur"
  network_interface_ids = [
    element(azurerm_network_interface.nic-worker.*.id, count.index)
  ]

  admin_ssh_key {
    username   = "tsunomur"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "autoshutdown-worker-linux" {
  //count              = length(data.azurerm_resources.vms.resources)
  //virtual_machine_id = data.azurerm_resources.vms.resources[count.index].id
  count              = length(azurerm_linux_virtual_machine.worker-linux[*].id)
  virtual_machine_id = azurerm_linux_virtual_machine.worker-linux[count.index].id
  location           = azurerm_resource_group.rg.location
  enabled            = true

  daily_recurrence_time = "0200"
  timezone              = "Tokyo Standard Time"

  notification_settings {
    enabled = false
  }
}

// VM worker - Windows
resource "azurerm_windows_virtual_machine" "worker-windows" {
  count               = var.worker_node_windows
  name                = "vm${count.index + var.worker_node_linux}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B2s"
  zone                = (count.index % 3) + 1
  admin_username      = "tsunomur"
  admin_password      = "VYm]Yf@Tpkft"
  network_interface_ids = [
    element(azurerm_network_interface.nic-worker.*.id, count.index + var.worker_node_linux)
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }
}
resource "azurerm_dev_test_global_vm_shutdown_schedule" "autoshutdown-worker-windows" {
  //count              = length(data.azurerm_resources.vms.resources)
  //virtual_machine_id = data.azurerm_resources.vms.resources[count.index].id
  count              = length(azurerm_windows_virtual_machine.worker-windows[*].id)
  virtual_machine_id = azurerm_windows_virtual_machine.worker-windows[count.index].id
  location           = azurerm_resource_group.rg.location
  enabled            = true

  daily_recurrence_time = "0200"
  timezone              = "Tokyo Standard Time"

  notification_settings {
    enabled = false
  }
}


// VM jumpbox - Windows
resource "azurerm_windows_virtual_machine" "jumpbox-windows" {
  count               = var.jumpbox_windows
  name                = "vm-jumpbox${count.index}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B2s"
  zone                = (count.index % 3) + 1
  admin_username      = "tsunomur"
  admin_password      = "VYm]Yf@Tpkft"
  network_interface_ids = [
    element(azurerm_network_interface.nic-jumpbox.*.id, count.index)
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }
}
resource "azurerm_dev_test_global_vm_shutdown_schedule" "autoshutdown-jumpbox-windows" {
  //count              = length(data.azurerm_resources.vms.resources)
  //virtual_machine_id = data.azurerm_resources.vms.resources[count.index].id
  count              = length(azurerm_windows_virtual_machine.jumpbox-windows[*].id)
  virtual_machine_id = azurerm_windows_virtual_machine.jumpbox-windows[count.index].id
  location           = azurerm_resource_group.rg.location
  enabled            = true

  daily_recurrence_time = "0200"
  timezone              = "Tokyo Standard Time"

  notification_settings {
    enabled = false
  }
}

data "azurerm_resources" "vms" {
  type                = "Microsoft.Compute/virtualMachines"
  resource_group_name = azurerm_resource_group.rg.name
}