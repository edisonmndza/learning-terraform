# Saved in Environment
#     client_id       = "46e6b8bc-9481-406b-925a-aad0b5d9bcd8"
#     client_secret   = "/ZQF6?Y.c*GZWMk2DiXeC4dtskukbnX4"
#     tenant_id       = "26c5ea8d-25b4-4030-9b78-afffa5bc4403"
#     subscription_id = "7b9bb5a0-79c7-4ce1-a100-1801e8f05013"

# INTERPOLATION using environment variables 

# The following variables are pulled from environment variables
# which scans for vars with the prefix TF_VAR_<name>.
# To add an environment variable *PERMANENTLY* in linux,
# add the variable to the /etc/environment file
# Example: TF_VAR_client_id="blahblah"
# Note: a restart is necessary to apply these changes
variable "client_id" {}
variable "client_secret" {}
variable "tenant_id" {}
variable "subscription_id" {}

# The following are pulled from the .tfvars file. 
# By default terraform looks for terraform.tfvars or terraform.tf
# unless specified by a -var-file tag when performing the command
# Example: terraform plan -var-file "vars.tfvars"
variable "location"{}
variable "rg" {}
variable "address_space" {}
variable "address_prefix" {}
variable "environment" {
  
}

provider "azurerm" {
    version             = "1.34"

    client_id           = "${var.client_id}"
    client_secret       = "${var.client_secret}"
    tenant_id           = "${var.tenant_id}"
    subscription_id     = "${var.subscription_id}"
}
# List out the location names using Azure CLI and typing in
# az account list-locations -o table^
# Note: No dependency
resource "azurerm_resource_group" "mendedi_rg" {
    name                = "${var.rg}"
    location            = "${var.location}"
}
# Note: direct dependency 
resource "azurerm_virtual_network" "mendedi_rg_vnet" {
    name                = "${var.rg}_vnet"
    location            = "${var.location}"
    resource_group_name = "${var.rg}"
    address_space       = ["${var.address_space}"]
    depends_on          = ["azurerm_resource_group.mendedi_rg"]
}

# Note: direct dependency 
resource "azurerm_subnet" "mendedi_rg_subnet" {
    name                = "${var.rg}_subnet"
    resource_group_name = "${var.rg}"
    virtual_network_name= "${var.rg}_vnet"
    address_prefix      = "${var.address_prefix}"
    depends_on          = ["azurerm_resource_group.mendedi_rg", "azurerm_virtual_network.mendedi_rg_vnet"]
}

# Note: inderect dependency
# because we are interpolating resource group name from (azurerm_resource_group)
resource "azurerm_network_interface" "mendedi_rg_nic" {
    name                = "${var.rg}_nic"
    location            = "${var.location}"
    resource_group_name = "${azurerm_resource_group.mendedi_rg.name}"
    network_security_group_id = "${azurerm_network_security_group.mendedi_rg_nsg.id}"
    
    ip_configuration{
        name            = "${var.rg}_ip"
        subnet_id       = "${azurerm_subnet.mendedi_rg_subnet.id}"
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id = "${azurerm_public_ip.mendedi_rg_public_ip.id}"
    }
}

# Public IP is used to allow external access to resources
# DNS 
# Static/Dynamic
# Bound it to resources = we can bind it to our NIC which will allow us to connect through RDP
resource "azurerm_public_ip" "mendedi_rg_public_ip" {
    name                = "${var.rg}_public_ip"
    location            = "${var.location}"
    resource_group_name = "${azurerm_resource_group.mendedi_rg.name}"
    # Conditionals syntax
    allocation_method   = "${var.environment == "production" ? "Static" : "Dynamic"}"
}

# NSG
# - Traffic control (firewall) filter source and destination addresses, protocols 
# - Default rules to allow load balancing
# - We can add our own rules

resource "azurerm_network_security_group" "mendedi_rg_nsg" {
    name                = "${var.rg}_nsg"
    location            = "${var.location}"
    resource_group_name = "${azurerm_resource_group.mendedi_rg.name}"
}

resource "azurerm_network_security_rule" "mendedi_rg_nsg_rule_rdp" {
    name                        = "RDP inbound"
    priority                    = 100
    direction                   = "Inbound"
    access                      = "Allow"
    protocol                    = "TCP"
    
    source_port_range           = "*"
    destination_port_range      = "3389"
    
    source_address_prefix       = "*"
    destination_address_prefix  = "*"
    resource_group_name         = "${azurerm_resource_group.mendedi_rg.name}"
    network_security_group_name = "${azurerm_network_security_group.mendedi_rg_nsg.name}"
}

# State
# - Map and track resources
# - Terraform config vs what's in Azure
# - Only tracks what's in scope of what's been configured in terraform
# - stored in terraform.tfstate and terraform.tfstate.backup
# - State file can be stored locally and remotely. team may share states
# - There is potential for sensitive data to be store in the file
# - Not reccomended to edit the state file but you can import from it
# Note: resources.azure.com may be useful when debugging or editting a state

# In order to create a VM, there are a couple of things needed
# - Hardware Model
# - Image
# - Networking
# -- NIC (which will have an IP for external connection)
# - Disks
# - Availability and Scale Sets

# Pricing Calculator
# https://azure.microsoft.com/en-ca/pricing/calculator/?&ef_id=CjwKCAjw2qHsBRAGEiwAMbPoDFqrya42OhXOLLUq9LiaD3kGQVa4xWfW28_-vL0PUW05Z6VIMdEohxoCB6UQAvD_BwE:G:s&OCID=AID2000061_SEM_Ed5Eh6kO&MarinID=Ed5Eh6kO_324561722335_azure%20pricing%20calculator_e_c__63148327173_kwd-310354828215&lnkd=Google_Azure_Brand&dclid=CjgKEAjw2qHsBRCos_vw1Pzim2sSJAAsWMU3aE8CFAOtevqDt-WAru3jxHXXUd8Fui28UiRmcFnvwPD_BwE
resource "azurerm_virtual_machine" "mendedi_rg_vm" {
    name                    = "${var.rg}_vm"
    location                = "${var.location}"
    resource_group_name     = "${azurerm_resource_group.mendedi_rg.name}"
    network_interface_ids   = ["${azurerm_network_interface.mendedi_rg_nic.id}"]
    # Azure VM sizes 
    # https://docs.microsoft.com/en-us/azure/virtual-machines/windows/sizes
    # az vm list-sizes -l canadacentral -o table
    vm_size = "Standard_B1s"

    storage_image_reference{
        # List publishers in your location
        # - az vm image list-publishers -l canadacentral -o table
        publisher   = "MicrosoftWindowsServer"
        
        # List publishers in your location
        # - az vm image list-publishers -l canadacentral -o table
        offer       = "WindowsServer"
        
        # List skus
        # - az vm image list-skus -l canadacentral -p <publisher> -f <offer> -o table
        sku         = "2016-Datacenter-Server-Core-smalldisk"

        version     = "latest"
    }

    storage_os_disk {
        name                = "${var.rg}_OS"
        caching             = "ReadWrite"
        create_option       = "FromImage"
        managed_disk_type   = "Standard_LRS"
    }

    # Credentials used to access the virtual machine.
    os_profile {
        computer_name       = "WindowsServer"
        admin_username      = "serviceaccount"
        admin_password      = "Canada1!"
    }

    os_profile_windows_config {
        # just needs to exists (?) for now...
    }
}






