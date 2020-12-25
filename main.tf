
provider "azurerm" {
  features {}
}

locals {
  tags = {
    intent = "${var.context}-001"
  }
}

# Reference existing resource group
data "azurerm_resource_group" "main" {
  name     = "${var.prefix}-rg"
}


# Create a virtual network and a subnet on that virtual network.

resource "azurerm_virtual_network" "main" {
  name                = "${var.prefix}-network"
  address_space       = ["10.0.0.0/24"]
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location

  tags = local.tags
}

resource "azurerm_subnet" "internal" {
  name                 = "${var.prefix}-subnet"
  address_prefixes     = ["10.0.0.0/24"]
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
}


# Create a Public IP

resource "azurerm_public_ip" "main" {
  name                = "UdacityProduct001PublicIp"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  allocation_method   = "Dynamic"

  tags = local.tags
}


# Create network security group. Ensure that access to other VMs on
# the subnet and denied access from the internet is explicitly defined.

resource "azurerm_network_security_group" "main" {
  name                = "${var.prefix}-ns-group"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  tags                = local.tags
}

resource "azurerm_network_security_rule" "allow-all-vms" {
  name                        = "allow-all-vms"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "TCP"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.main.name
}

resource "azurerm_network_security_rule" "allow_lb" {
  name                       = "allow-lb"
  priority                   = 110
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "TCP"
  source_port_range          = "*"
  destination_port_range     = "80"
  source_address_prefix      = "AzureLoadBalancer"
  destination_address_prefix = "*"
  resource_group_name         = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.main.name
}

resource "azurerm_network_security_rule" "deny-internet" {
  name                       = "deny-internet"
  priority                   = 120
  direction                  = "Inbound"
  access                     = "Deny"
  protocol                   = "*"
  source_port_range          = "*"
  destination_port_range     = "*"
  source_address_prefix      = "Internet"
  destination_address_prefix = "VirtualNetwork"
  resource_group_name         = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.main.name
}


# Create a network interface

resource "azurerm_network_interface" "main" {
  count               = var.virtual_machine_count
  name                = "${var.prefix}-nic-00${count.index}"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location

  ip_configuration {
    name                          = "${var.prefix}-ifconfig"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
  }

  tags = local.tags
}

resource "azurerm_network_interface_security_group_association" "main" {
  count                     = var.virtual_machine_count
  network_interface_id      = element(azurerm_network_interface.main.*.id, count.index)
  network_security_group_id = azurerm_network_security_group.main.id
}


# Create a load balancer

resource "azurerm_lb" "main" {
  name                = "${var.prefix}-load-balancer"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  frontend_ip_configuration {
    name                 = "${var.prefix}-load-balancer-public-ip"
    public_ip_address_id = azurerm_public_ip.main.id
  }

  tags = local.tags
}

resource "azurerm_lb_probe" "main" {
  resource_group_name = data.azurerm_resource_group.main.name
  loadbalancer_id     = azurerm_lb.main.id
  name                = "${var.prefix}-load-balancer-health"
  port                = 80
}

resource "azurerm_lb_rule" "main" {
  name                           = "${var.prefix}-load-balancer-rule"
  resource_group_name            = data.azurerm_resource_group.main.name
  loadbalancer_id                = azurerm_lb.main.id
  probe_id                       = azurerm_lb_probe.main.id
  backend_address_pool_id        = azurerm_lb_backend_address_pool.main.id
  frontend_ip_configuration_name = "${var.prefix}-load-balancer-public-ip"
  protocol                       = "TCP"
  frontend_port                  = 80
  backend_port                   = 80
}


# Your load balancer will need abackend address pool and address pool 
# association for the network interface and the load balancer

resource "azurerm_lb_backend_address_pool" "main" {
  name                = "${var.prefix}-backendpool"
  resource_group_name = data.azurerm_resource_group.main.name
  loadbalancer_id     = azurerm_lb.main.id
}

resource "azurerm_network_interface_backend_address_pool_association" "main" {
  ip_configuration_name   = "${var.prefix}-ifconfig"
  backend_address_pool_id = azurerm_lb_backend_address_pool.main.id
  network_interface_id    = element(azurerm_network_interface.main.*.id, count.index)
  count                   = var.virtual_machine_count

}


# Create a VM availability set

resource "azurerm_availability_set" "main" {
  name                         = "${var.prefix}-availiability-set"
  location                     = data.azurerm_resource_group.main.location
  resource_group_name          = data.azurerm_resource_group.main.name
  platform_fault_domain_count  = 2
  platform_update_domain_count = 5
  
  tags = local.tags
}


data "azurerm_image" "image" {
  resource_group_name = data.azurerm_resource_group.main.name
  name                = "azure-udacity-project-001-ubuntu-image"
}

resource "azurerm_linux_virtual_machine" "main" {
  count                           = var.virtual_machine_count
  name                            = "${var.prefix}-vm-00${count.index}"
  resource_group_name             = data.azurerm_resource_group.main.name
  location                        = data.azurerm_resource_group.main.location
  size                            = "Standard_B1s"
  admin_username                  = var.username
  admin_password                  = var.password
  disable_password_authentication = false
  network_interface_ids           = [element(azurerm_network_interface.main.*.id, count.index)]
  availability_set_id             = azurerm_availability_set.main.id
  source_image_id                 = data.azurerm_image.image.id

  os_disk {
    name                 = "${var.prefix}-os-disk-00${count.index}"
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  tags = local.tags
}

# Create managed disks for your VMs

resource "azurerm_managed_disk" "main" {
  count                = var.virtual_machine_count
  name                 = "${var.prefix}-managed-disk-00${count.index}"
  resource_group_name  = data.azurerm_resource_group.main.name
  location             = data.azurerm_resource_group.main.location
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 10
  
  tags = local.tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "main" {
  count              = var.virtual_machine_count
  managed_disk_id    = element(azurerm_managed_disk.main.*.id, count.index)
  virtual_machine_id = element(azurerm_linux_virtual_machine.main.*.id, count.index)
  lun                = "0"
  caching            = "ReadWrite"
}
