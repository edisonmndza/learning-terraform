variable "client_id" {}
variable "client_secret" {}
variable "tenant_id" {}
variable "subscription_id" {}

variable "rg" {}
variable "prefix" {}
variable "environment" {}

provider "azurerm" {
    version         = "1.34"

    client_id       = "${var.client_id}"
    client_secret   = "${var.client_secret}"
    tenant_id       = "${var.tenant_id}"
    subscription_id = "${var.subscription_id}"
}

# module "centos-01"{
#     source          = "./centos"
#     location        = "canadacentral"
#     rg              = "${var.rg}-01"
#     prefix          = "${var.prefix}-01"
#     address_space   = "10.0.0.0/22"
#     address_prefix  = "10.0.1.0/24"
#     environment     = "${var.environment}"
# }

# module "centos-02"{
#     source          = "./centos"
#     location        = "canadacentral"
#     rg              = "${var.rg}-02"
#     prefix          = "${var.prefix}-02"
#     address_space   = "20.0.0.0/22"
#     address_prefix  = "20.0.1.0/24"
#     environment     = "${var.environment}"
# }
