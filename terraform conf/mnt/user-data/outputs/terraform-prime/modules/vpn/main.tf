# ── Latest Amazon Linux 2023 AMI ─────────────────────────────────────────────
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── EC2 Instance (WireGuard VPN Gateway) ─────────────────────────────────────
resource "aws_instance" "vpn" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = var.key_pair_name

  associate_public_ip_address = true

  # Bootstrap script — installs WireGuard and generates server keys on first boot
  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Install WireGuard
    dnf install wireguard-tools -y

    # Enable IP forwarding permanently
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    echo 'net.ipv4.conf.all.src_valid_mark=1' >> /etc/sysctl.conf
    sysctl -p

    # Generate server keys
    mkdir -p /etc/wireguard
    wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
    chmod 600 /etc/wireguard/server_private.key

    SERVER_PRIVATE=$(cat /etc/wireguard/server_private.key)
    SERVER_PUBLIC=$(cat /etc/wireguard/server_public.key)

    # Write server config
    cat > /etc/wireguard/wg0.conf << WGEOF
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = $SERVER_PRIVATE
PostUp   = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
WGEOF

    # Enable and start WireGuard
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0

    # Save server public key to a readable location for easy retrieval
    echo "$SERVER_PUBLIC" > /home/ec2-user/server_public.key
    chown ec2-user:ec2-user /home/ec2-user/server_public.key

    echo "WireGuard setup complete. Server public key: $SERVER_PUBLIC" >> /var/log/wireguard-setup.log
  EOF

  tags = {
    Name        = "${var.project}-vpn-gateway"
    Environment = var.environment
    Project     = var.project
  }
}

# ── Elastic IP (keeps the VPN endpoint stable across reboots) ─────────────────
resource "aws_eip" "vpn" {
  instance = aws_instance.vpn.id
  domain   = "vpc"

  tags = {
    Name        = "${var.project}-vpn-eip"
    Environment = var.environment
  }
}
