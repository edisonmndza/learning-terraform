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
variable "environment" {}
variable "countnum" {}
variable "terraform_script_version" {}
variable "domain_name_label" {}

provider "azurerm" {
    version             = "1.34"

    client_id           = "${var.client_id}"
    client_secret       = "${var.client_secret}"
    tenant_id           = "${var.tenant_id}"
    subscription_id     = "${var.subscription_id}"
}

locals {
    web_server_name = "${var.environment == "production" ? "wsrv-prd" : "wsrv-dev"}"
    build_environment = "${var.environment == "production" ? "production" : "development"}"
}

# List out the location names using Azure CLI and typing in
# az account list-locations -o table^
# Note: No dependency
resource "azurerm_resource_group" "mendedi-rg" {
    name                = "${var.rg}"
    location            = "${var.location}"
    tags = {
        environment     = "${local.build_environment}"
        build-version   = "${var.terraform_script_version}"
    }
}


# Note: direct dependency 
resource "azurerm_virtual_network" "mendedi-rg-vnet" {
    name                = "${var.rg}-vnet"
    location            = "${var.location}"
    resource_group_name = "${var.rg}"
    address_space       = ["${var.address_space}"]
    depends_on          = ["azurerm_resource_group.mendedi-rg"]
}

# Note: direct dependency 
resource "azurerm_subnet" "mendedi-rg-subnet" {
    name                = "${var.rg}-subnet"
    resource_group_name = "${var.rg}"
    virtual_network_name= "${var.rg}-vnet"
    address_prefix      = "${var.address_prefix}"
    depends_on          = ["azurerm_resource_group.mendedi-rg", "azurerm_virtual_network.mendedi-rg-vnet"]
}

resource "azurerm_subnet_network_security_group_association" "mendedi-rg-nsg-association" {
    subnet_id                   = "${azurerm_subnet.mendedi-rg-subnet.id}"
    network_security_group_id   = "${azurerm_network_security_group.mendedi-rg-nsg.id}"
    count                       = "${var.countnum}" 
}

# Public IP is used to allow external access to resources
# DNS 
# Static/Dynamic
# Bound it to resources = we can bind it to our NIC whichgit  will allow us to connect through RDP
resource "azurerm_public_ip" "mendedi-rg-lb-public-ip" {
    name                = "${var.rg}-public-ip"
    location            = "${var.location}"
    resource_group_name = "${azurerm_resource_group.mendedi-rg.name}"
    # Conditionals syntax
    allocation_method   = "${var.environment == "production" ? "Static" : "Dynamic"}"
    domain_name_label   = "${var.domain_name_label}"
}

# NSG
# - Traffic control (firewall) filter source and destination addresses, protocols 
# - Default rules to allow load balancing
# - We can add our own rules

resource "azurerm_network_security_group" "mendedi-rg-nsg" {
    name                = "${var.rg}-nsg"
    location            = "${var.location}"
    resource_group_name = "${azurerm_resource_group.mendedi-rg.name}"
}

resource "azurerm_network_security_rule" "mendedi-rg-nsg-rule-http" {
    name                        = "HTTP inbound"
    priority                    = 100
    direction                   = "Inbound"
    access                      = "Allow"
    protocol                    = "TCP"
    
    source_port_range           = "*"
    destination_port_range      = "80"
    
    source_address_prefix       = "*"
    destination_address_prefix  = "*"
    resource_group_name         = "${azurerm_resource_group.mendedi-rg.name}"
    network_security_group_name = "${azurerm_network_security_group.mendedi-rg-nsg.name}"
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

# Scale sets 
# - High availability
# - identical images
# - Demand
# - Schedule
# - Updates
# delete NIC block, create count for IP
# update vm to be azurerm_virtual_machine_scale_set
resource "azurerm_virtual_machine_scale_set" "mendedi-rg-vm" {
    name                    = "${local.web_server_name}-scale-set"
    location                = "${var.location}"
    resource_group_name     = "${azurerm_resource_group.mendedi-rg.name}"
    upgrade_policy_mode     = "manual"

    sku{
        name                = "Standard_B1s"
        tier                = "Standard"
        capacity            = "${var.countnum}"
    }    

    storage_profile_image_reference{
        publisher   = "MicrosoftWindowsServer"
        offer       = "WindowsServer"
        sku         = "2016-Datacenter-Server-Core-smalldisk"
        version     = "latest"
    }

    storage_profile_os_disk {
        name                = "" #automatically named when it's a scale set
        caching             = "ReadWrite"
        create_option       = "FromImage"
        managed_disk_type   = "Standard_LRS"
    }

    # Credentials used to access the virtual machine.
    os_profile {
        computer_name_prefix= "${local.web_server_name}"
        admin_username      = "serviceaccount"
        admin_password      = "Canada1!"
    }

    os_profile_windows_config {
        # just needs to exists (?) for now...
    }

    network_profile {
        name = "${var.rg}-network-profile"
        primary = true

        ip_configuration {
            name = "${local.web_server_name}"
            primary = true
            subnet_id = "${azurerm_subnet.mendedi-rg-subnet.*.id[0]}"
            load_balancer_backend_address_pool_ids = ["${azurerm_lb_backend_address_pool.mendedi-rg-lb-backend-pool.id}"]
        }
    }
}

resource "azurerm_lb" "mendedi-rg-lb" {
    name                    = "${var.rg}-lb"
    location                = "${var.location}"
    resource_group_name     = "${azurerm_resource_group.mendedi-rg.name}"
    
    frontend_ip_configuration {
        name                = "${var.rg}-lb-frontend-ip"
        public_ip_address_id = "${azurerm_public_ip.mendedi-rg-lb-public-ip.id}"
    }
}

resource "azurerm_lb_backend_address_pool" "mendedi-rg-lb-backend-pool" {
    name                    = "${var.rg}-lb-backend-pool"
    resource_group_name     = "${azurerm_resource_group.mendedi-rg.name}"
    loadbalancer_id         = "${azurerm_lb.mendedi-rg-lb.id}"
}

resource "azurerm_lb_probe" "mendedi-rg-lb-http-probe" {
    name                    = "${var.rg}-lb-http-probe"
    resource_group_name     = "${azurerm_resource_group.mendedi-rg.name}"
    loadbalancer_id         = "${azurerm_lb.mendedi-rg-lb.id}"

    protocol                = "tcp"
    port                    = "80"
}

resource "azurerm_lb_rule" "mendedi-rg-lb-http-rule" {
    name                            = "${var.rg}-lb-http-probe"
    resource_group_name             = "${azurerm_resource_group.mendedi-rg.name}"
    loadbalancer_id                 = "${azurerm_lb.mendedi-rg-lb.id}"

    protocol                        = "tcp"
    frontend_port                   = "80"
    backend_port                    = "80"

    frontend_ip_configuration_name  = "${var.rg}-lb-frontend-ip"
    probe_id                        = "${azurerm_lb_probe.mendedi-rg-lb-http-probe.id}"
    backend_address_pool_id         = "${azurerm_lb_backend_address_pool.mendedi-rg-lb-backend-pool.id}"

}



