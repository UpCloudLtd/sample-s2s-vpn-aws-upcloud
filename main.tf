
resource "upcloud_network" "upcloud_backend_network" {
  name = "backend_network"
  zone = var.zone

  ip_network {
    address            = var.upcloud_network
    dhcp               = true
    dhcp_default_route = false
    family             = "IPv4"
  }
}

resource "upcloud_floating_ip_address" "fip-1" {
  zone = var.zone
}

resource "aws_vpc" "aws_backend_network" {
  cidr_block = var.aws_network
}

resource "aws_subnet" "aws_subnet" {
  vpc_id     = aws_vpc.aws_backend_network.id
  cidr_block = aws_vpc.aws_backend_network.cidr_block

}
resource "aws_customer_gateway" "gateway_upcloud_s2s" {
  bgp_asn    = 65000
  ip_address = upcloud_floating_ip_address.fip-1.ip_address
  type       = "ipsec.1"
  depends_on = [upcloud_floating_ip_address.fip-1]
}

resource "aws_vpn_gateway" "vpn_gw_to_upcloud" {
  vpc_id = aws_vpc.aws_backend_network.id
}

resource "aws_vpn_connection" "vpn_connection_upcloud" {
  vpn_gateway_id      = aws_vpn_gateway.vpn_gw_to_upcloud.id
  customer_gateway_id = aws_customer_gateway.gateway_upcloud_s2s.id
  type                = "ipsec.1"
  static_routes_only  = true
}

resource "aws_vpn_connection_route" "cloud9_network" {
  destination_cidr_block = var.upcloud_network
  vpn_connection_id      = aws_vpn_connection.vpn_connection_upcloud.id
  depends_on             = [var.upcloud_network]
}
resource "upcloud_server" "s2s_vpn_vm" {
  hostname   = "s2s-vpn-vm${count.index}-${var.zone}"
  zone       = var.zone
  count      = 2
  plan       = var.server_plan
  depends_on = [upcloud_network.upcloud_backend_network]
  template {
    storage = "Ubuntu Server 20.04 LTS (Focal Fossa)"
    size    = 25
  }
  network_interface {
    type = "public"
  }
  network_interface {
    type = "utility"
  }
  network_interface {
    type                = "private"
    network             = upcloud_network.upcloud_backend_network.id
    source_ip_filtering = false
  }

  login {
    user = "root"
    keys = [
      var.ssh_key_public,
    ]
    create_password   = false
    password_delivery = "email"
  }

  connection {
    host  = self.network_interface[0].ip_address
    type  = "ssh"
    user  = "root"
    agent = true
  }

  provisioner "remote-exec" {
    inline = [
      "apt-get update",
      "echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf",
      "echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf",
      "echo 'net.ipv4.conf.all.accept_redirects = 0' >> /etc/sysctl.conf",
      "echo 'net.ipv4.conf.all.send_redirects = 0' >> /etc/sysctl.conf",
      "sysctl -p",
      "apt-get install strongswan strongswan-pki libcharon-extra-plugins libcharon-extauth-plugins libstrongswan-extra-plugins libtss2-tcti-tabrmd-dev keepalived -y",
      "ipsec pki --gen --size 4096 --type rsa --outform pem > /etc/ipsec.d/private/ca.key.pem",
      "ipsec pki --self --in /etc/ipsec.d/private/ca.key.pem --type rsa --dn 'CN=Upcloud VPN VM CA' --ca --lifetime 3650 --outform pem > /etc/ipsec.d/cacerts/ca.cert.pem",
      "ipsec pki --gen --size 4096 --type rsa --outform pem > /etc/ipsec.d/private/server.key.pem",
      "ipsec pki --pub --in /etc/ipsec.d/private/server.key.pem --type rsa | ipsec pki --issue --lifetime 2750 --cacert /etc/ipsec.d/cacerts/ca.cert.pem --cakey /etc/ipsec.d/private/ca.key.pem --dn \"CN=${self.network_interface[0].ip_address}\" --san=${self.network_interface[0].ip_address} --san=@${self.network_interface[0].ip_address}--flag serverAuth --flag ikeIntermediate --outform pem > /etc/ipsec.d/certs/server.cert.pem",
      "echo \"${upcloud_floating_ip_address.fip-1.ip_address} ${aws_vpn_connection.vpn_connection_upcloud.tunnel1_address} : PSK \"${aws_vpn_connection.vpn_connection_upcloud.tunnel1_preshared_key}\"\" > /etc/ipsec.secrets",
      "echo \"${upcloud_floating_ip_address.fip-1.ip_address} ${aws_vpn_connection.vpn_connection_upcloud.tunnel2_address} : PSK \"${aws_vpn_connection.vpn_connection_upcloud.tunnel2_preshared_key}\"\" >> /etc/ipsec.secrets"
    ]
  }
  provisioner "file" {
    content = templatefile("configs/ipsec.conf.tftpl", {
      UPCLOUD_VM      = upcloud_floating_ip_address.fip-1.ip_address,
      REMOTE          = count.index == 0 ? aws_vpn_connection.vpn_connection_upcloud.tunnel1_address : aws_vpn_connection.vpn_connection_upcloud.tunnel2_address,
      UPCLOUD_NETWORK = var.upcloud_network,
    REMOTE_NETWORK = var.aws_network })
    destination = "/etc/ipsec.conf"
  }
  provisioner "file" {
    content = templatefile("configs/keepalived.conf.tftpl", {
    VIRTUAL_IP = var.virtual_ip })
    destination = "/etc/keepalived/keepalived.conf"
  }
  provisioner "file" {
    source      = "configs/ipsecstatus.sh"
    destination = "/etc/keepalived/ipsecstatus.sh"
  }
  provisioner "remote-exec" {
    inline = [
      "ip address add ${upcloud_floating_ip_address.fip-1.ip_address}/32 dev eth0",
      "echo \"auto eth0:1\n iface eth0:1 inet static\n address ${upcloud_floating_ip_address.fip-1.ip_address}\n netmask 255.255.255.255\n\" >> /etc/network/interfaces",
      "useradd keepalived_script",
      "chmod 700 /etc/keepalived/ipsecstatus.sh",
      "systemctl enable strongswan-starter",
      "systemctl restart strongswan-starter",
      "systemctl enable keepalived",
      "systemctl restart keepalived"
    ]
  }
  provisioner "local-exec" {
    command = count.index == 0 ? "bash attach-floating-ip.sh ${upcloud_floating_ip_address.fip-1.ip_address} ${self.network_interface[0].mac_address}" : "echo done"
  }
}

resource "upcloud_server_group" "vpn-ha-pair" {
  title         = "vpn_ha_group"
  anti_affinity = true
  labels = {
    "key1" = "vpn-ha"

  }
  members = [
    upcloud_server.s2s_vpn_vm[0].id,
    upcloud_server.s2s_vpn_vm[1].id
  ]

}