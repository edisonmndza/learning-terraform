# Basic Linux Box
variable "rg" {}
variable "prefix" {}
variable "location" {}
variable "address_space" {}
variable "address_prefix" {}
variable "environment" {}

resource "azurerm_resource_group" "mendedi-rg" {
    name                = "${var.rg}"
    location            = "${var.location}"
}

resource "azurerm_virtual_network" "mendedi-linux-vnet" {
    name                = "${var.prefix}-vnet"
    location            = "${var.location}"
    resource_group_name = "${azurerm_resource_group.mendedi-rg.name}"
    address_space       = ["${var.address_space}"]
}

resource "azurerm_subnet" "mendedi-linux-subnet" {
    name                = "${var.prefix}-subnet"
    resource_group_name = "${azurerm_resource_group.mendedi-rg.name}"
    virtual_network_name= "${azurerm_virtual_network.mendedi-linux-vnet.name}"
    address_prefix      = "${var.address_prefix}"
}

resource "azurerm_subnet_network_security_group_association" "mendedi-linux-nsg-association" {
    subnet_id                   = "${azurerm_subnet.mendedi-linux-subnet.id}"
    network_security_group_id   = "${azurerm_network_security_group.mendedi-linux-nsg.id}"
}

resource "azurerm_public_ip" "mendedi-linux-public-ip" {
    name                = "${var.prefix}-public-ip"
    location            = "${var.location}"
    resource_group_name = "${azurerm_resource_group.mendedi-rg.name}"
    # Conditionals syntax
    allocation_method   = "${var.environment == "production" ? "Static" : "Dynamic"}"
}

resource "azurerm_network_security_group" "mendedi-linux-nsg" {
    name                = "${var.prefix}-nsg"
    location            = "${var.location}"
    resource_group_name = "${azurerm_resource_group.mendedi-rg.name}"
}

resource "azurerm_network_security_rule" "mendedi-linux-nsg-rule-ssh" {
    name                        = "SSH inbound"
    priority                    = 100
    direction                   = "Inbound"
    access                      = "Allow"
    protocol                    = "TCP"
    
    source_port_range           = "*"
    destination_port_range      = "22"
    
    source_address_prefix       = "*"
    destination_address_prefix  = "*"
    resource_group_name         = "${azurerm_resource_group.mendedi-rg.name}"
    network_security_group_name = "${azurerm_network_security_group.mendedi-linux-nsg.name}"
}

resource "azurerm_network_interface" "mendedi-linux-nic" {
  name                          = "${var.prefix}-nic"
  location                      = "${var.location}"
  resource_group_name           = "${azurerm_resource_group.mendedi-rg.name}"
  network_security_group_id     = "${azurerm_network_security_group.mendedi-linux-nsg.id}"

  ip_configuration {
      name                      = "${var.prefix}-nic-ipconfig"
      subnet_id                 = "${azurerm_subnet.mendedi-linux-subnet.id}"
      private_ip_address_allocation = "Dynamic"
      public_ip_address_id      = "${azurerm_public_ip.mendedi-linux-public-ip.id}"
  }
}

resource "azurerm_virtual_machine" "mendedi-linux" {
    name                    = "${var.prefix}"
    location                = "${var.location}"
    resource_group_name     = "${azurerm_resource_group.mendedi-rg.name}"
    
    network_interface_ids   = ["${azurerm_network_interface.mendedi-linux-nic.id}"]
    vm_size                 = "Standard_B1s"
    
    storage_os_disk {
        name                = "${var.prefix}-osdisk"
        caching             = "ReadWrite"
        create_option       = "FromImage"
        managed_disk_type   = "Standard_LRS"
    }

    storage_image_reference{
        publisher   = "OpenLogic"
        offer       = "CentOS"
        sku         = "7.6"
        version     = "latest"
    }

    # Credentials used to access the virtual machine.
    os_profile {
        computer_name       = "Admin"
        admin_username      = "serviceaccount"
        admin_password      = "Canada1!"
    }

    os_profile_linux_config {
        disable_password_authentication = false
    }
}

