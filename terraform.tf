# Configure the DigitalOcean Provider
# Will use DIGITALOCEAN_TOKEN environment variable
provider "digitalocean" {}

# Create SSH key that can be used by droplets
resource "digitalocean_ssh_key" "ssh" {
  name       = "NDC Oslo 2017"
  public_key = "${file("ndc_id_rsa.pub")}"
}

# Create droplet based on centos image
resource "digitalocean_droplet" "web" {
  image    = "centos-7-x64"
  name     = "web"
  region   = "ams2"
  size     = "512mb"
  ssh_keys = ["${digitalocean_ssh_key.ssh.id}"]
}
