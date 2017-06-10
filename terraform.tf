# Configure the DigitalOcean Provider
# Will use DIGITALOCEAN_TOKEN environment variable
provider "digitalocean" {}

variable "nb_web_servers" {
  description = "The number of web servers"
  default     = "2"
  type        = "string"
}

variable "digitalocean_datacenter" {
  #default = "nyc1"
  #default = "lon1"
  #default = "ams3"
  default = "ams2"

  description = "Digital Ocean datacenter to use"
  type        = "string"
}

# Create SSH key that can be used by droplets
resource "digitalocean_ssh_key" "ssh" {
  name       = "NDC Oslo 2017"
  public_key = "${file("yubikey_id_rsa.pub")}"
}

# Create droplet based on centos image
resource "digitalocean_droplet" "web" {
  count    = "${var.nb_web_servers}"
  image    = "centos-7-x64"
  name     = "web${count.index}"
  region   = "${var.digitalocean_datacenter}"
  size     = "512mb"
  ssh_keys = ["${digitalocean_ssh_key.ssh.id}"]

  # Install, enable and run Apache httpd right after provisioning instance
  provisioner "remote-exec" {
    inline = [
      "yum -y install httpd",
      "yum -y install mod_ssl",
      "systemctl enable httpd",
      "systemctl start httpd",
    ]
  }

  connection {
    type  = "ssh"
    user  = "root"
    agent = "true"
  }
}

output "Web IPs Digital Ocean" {
  value = "${join(", ",digitalocean_droplet.web.*.ipv4_address)}"
}

# Configure the AWS Provider
# Will use AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables
provider "aws" {
  region = "eu-central-1"
}

# Looked up manually in aws route 53 console
# Consider using aws_route53_zone resource instead
variable "dns_zone_id" {
  default     = "Z2X1UBSEPFNQNM"
  description = "DNS hosted zone id"
  type        = "string"
}

# Create DNS records for digital ocean web servers
resource "aws_route53_record" "do" {
  zone_id = "${var.dns_zone_id}"
  name    = "do.landro.io."
  type    = "A"
  ttl     = 60

  records = [
    "${digitalocean_droplet.web.*.ipv4_address}",
  ]
}

# Configure the Microsoft Azure Provider
# Will use ARM_SUBSCRIPTION_ID, ARM_CLIENT_ID, ARM_CLIENT_SECRET
# and ARM_TENANT_ID environment variables
provider "azurerm" {
  environment = "public"
}

variable "azure_region" {
  #default = "UK South"
  #default = "UK West"
  #default = "West Europe"
  default = "North Europe"

  description = "Azure region to use"
  type        = "string"
}

# Create resource group
resource "azurerm_resource_group" "default" {
  name     = "NDC-Oslo-2017"
  location = "${var.azure_region}"
}

# Create virtual network
resource "azurerm_virtual_network" "default" {
  name                = "NDC-Oslo-2017"
  address_space       = ["10.0.0.0/16"]
  location            = "${var.azure_region}"
  resource_group_name = "${azurerm_resource_group.default.name}"
}

# Create web subnet
resource "azurerm_subnet" "web" {
  name                 = "Web"
  resource_group_name  = "${azurerm_resource_group.default.name}"
  virtual_network_name = "${azurerm_virtual_network.default.name}"
  address_prefix       = "10.0.2.0/24"

  network_security_group_id = "${azurerm_network_security_group.web.id}"
}

# Create security group
resource "azurerm_network_security_group" "web" {
  name                = "web"
  location            = "${var.azure_region}"
  resource_group_name = "${azurerm_resource_group.default.name}"

  security_rule {
    name                   = "ssh"
    description            = "Allow SSH management traffic from trusted IP ranges"
    priority               = 101
    direction              = "Inbound"
    access                 = "Allow"
    protocol               = "Tcp"
    source_port_range      = "*"
    destination_port_range = "22"

    # TODO SECURITY limit this to your trusted IP range
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "http"
    description                = "Allow HTTP traffic from entire Internet"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "https"
    description                = "Allow HTTPS traffic from entire Internet"
    priority                   = 103
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "all"
    description                = "Deny everything else"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Create public IP
resource "azurerm_public_ip" "default" {
  count                        = "${var.nb_web_servers}"
  name                         = "ip${count.index}"
  location                     = "${var.azure_region}"
  resource_group_name          = "${azurerm_resource_group.default.name}"
  public_ip_address_allocation = "static"
}

# Create network interface
resource "azurerm_network_interface" "default" {
  count               = "${var.nb_web_servers}"
  name                = "interface${count.index}"
  location            = "${var.azure_region}"
  resource_group_name = "${azurerm_resource_group.default.name}"

  network_security_group_id = "${azurerm_network_security_group.web.id}"

  ip_configuration {
    name                          = "ip-config${count.index}"
    subnet_id                     = "${azurerm_subnet.web.id}"
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = "${element(azurerm_public_ip.default.*.id, count.index)}"
  }
}

# Create managed availability set
resource "azurerm_availability_set" "default" {
  name                = "ndc-oslo-2017"
  location            = "${var.azure_region}"
  resource_group_name = "${azurerm_resource_group.default.name}"
  managed             = true
}

# Create virtual machine with managed OS disk storage
resource "azurerm_virtual_machine" "web" {
  count                            = "${var.nb_web_servers}"
  name                             = "web${count.index}"
  location                         = "${var.azure_region}"
  resource_group_name              = "${azurerm_resource_group.default.name}"
  network_interface_ids            = ["${element(azurerm_network_interface.default.*.id, count.index)}"]
  vm_size                          = "Standard_A2"
  availability_set_id              = "${azurerm_availability_set.default.id}"
  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  depends_on = ["azurerm_network_interface.default"]

  storage_image_reference {
    publisher = "OpenLogic"
    offer     = "CentOS"
    sku       = "7.2"
    version   = "latest"
  }

  storage_os_disk {
    name              = "web${count.index}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "web${count.index}"
    admin_username = "landro"

    # Read password from file
    admin_password = "${file("password.txt")}"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path     = "/home/landro/.ssh/authorized_keys"
      key_data = "${file("yubikey_id_rsa.pub")}"
    }
  }

  # Install, enable and run Apache httpd right after provisioning instance
  provisioner "remote-exec" {
    inline = [
      "sudo yum -y install httpd",
      "sudo yum -y install mod_ssl",
      "sudo systemctl enable httpd",
      "sudo systemctl start httpd",
    ]
  }

  # Connect using SSH when provisioning
  connection {
    type  = "ssh"
    user  = "landro"
    host  = "${element(azurerm_public_ip.default.*.ip_address, count.index)}"
    agent = "true"
  }
}

# Create DNS records for azure web servers
resource "aws_route53_record" "azure" {
  zone_id = "${var.dns_zone_id}"
  name    = "azure.landro.io."
  type    = "A"
  ttl     = 60

  records = [
    "${azurerm_public_ip.default.*.ip_address}",
  ]
}

output "Web IPs azure" {
  value = "${join(", ",azurerm_public_ip.default.*.ip_address)}"
}

# Create DNS CNAME record for azure vms in order to support DNS routing policy
resource "aws_route53_record" "azure-alias" {
  zone_id = "${var.dns_zone_id}"
  name    = "azure-alias.landro.io."
  type    = "CNAME"
  ttl     = 60

  records = [
    "${aws_route53_record.azure.fqdn}",
  ]
}

# Create DNS record with weighted routing policy and health checking targeting azure
resource "aws_route53_record" "azure-www" {
  zone_id = "${var.dns_zone_id}"
  name    = "www.landro.io."
  type    = "CNAME"

  weighted_routing_policy {
    weight = "${var.nb_web_servers}"
  }

  set_identifier = "azure"

  alias {
    name                   = "${aws_route53_record.azure-alias.fqdn}"
    zone_id                = "${aws_route53_record.azure.zone_id}"
    evaluate_target_health = true
  }

  health_check_id = "${aws_route53_health_check.azure.id}"
}

# Create health check targeting Apache httpd running in Azure
resource "aws_route53_health_check" "azure" {
  fqdn          = "${aws_route53_record.azure.fqdn}"
  port          = 80
  type          = "HTTP"
  resource_path = "/images/poweredby.png"

  # TODO Adjust this for production use
  failure_threshold = "1"
  request_interval  = "10"
}

# Create DNS CNAME record for digital ocean vms in order to support DNS routing policy
resource "aws_route53_record" "do-alias" {
  zone_id = "${var.dns_zone_id}"
  name    = "do-alias.landro.io."
  type    = "CNAME"
  ttl     = 60

  records = [
    "${aws_route53_record.do.fqdn}",
  ]
}

# Create DNS record with weighted routing policy and health checking targeting digital ocean
resource "aws_route53_record" "do-www" {
  zone_id = "${var.dns_zone_id}"
  name    = "www.landro.io."
  type    = "CNAME"

  weighted_routing_policy {
    weight = "${var.nb_web_servers}"
  }

  set_identifier = "digitalocean"

  alias {
    name                   = "${aws_route53_record.do-alias.fqdn}"
    zone_id                = "${aws_route53_record.do.zone_id}"
    evaluate_target_health = true
  }

  health_check_id = "${aws_route53_health_check.do.id}"
}

# Create health check targeting Apache httpd running in digital ocean
resource "aws_route53_health_check" "do" {
  fqdn          = "${aws_route53_record.do.fqdn}"
  port          = 80
  type          = "HTTP"
  resource_path = "/images/poweredby.png"

  # TODO Adjust this for production use
  failure_threshold = "1"
  request_interval  = "10"
}
