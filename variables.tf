
variable "zone" {
  type = string
}

variable "server_plan" {
  type = string
}

variable "upcloud_network" {
  type = string
}

variable "virtual_ip" {
  type = string
}
variable "ssh_key_public" {
  type    = string
  default = ""
}

variable "aws_network" {
  type    = string
  default = ""
}

variable "our_tunnel1_psk" {
  type    = string
  default = ""
}
variable "our_tunnel2_psk" {
  type    = string
  default = ""
}
variable "aws_tunnel1_ip" {
  type    = string
  default = ""
}
variable "aws_tunnel2_ip" {
  type    = string
  default = ""
}