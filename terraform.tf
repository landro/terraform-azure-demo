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
  public_key = "${file("ndc_id_rsa.pub")}"
}

# Create droplet based on centos image
resource "digitalocean_droplet" "web" {
  count    = "${var.nb_web_servers}"
  image    = "centos-7-x64"
  name     = "web${count.index}"
  region   = "${var.digitalocean_datacenter}"
  size     = "512mb"
  ssh_keys = ["${digitalocean_ssh_key.ssh.id}"]
}
