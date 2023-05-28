terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

resource "aws_lightsail_key_pair" "ovpn_server" {
  name       = "ovpn_server_key_pair"
  public_key = file("~/.ssh/ovpn_server.pub")
}

resource "aws_lightsail_instance" "ovpn_server" {
  depends_on = [aws_lightsail_key_pair.ovpn_server]
  name              = "ovpn_server_instance"
  availability_zone = "ap-northeast-1c"
  blueprint_id      = "ubuntu_22_04"
  bundle_id         = "nano_2_0"
  key_pair_name     = "ovpn_server_key_pair"
}

resource "aws_lightsail_instance_public_ports" "ssh" {
  instance_name = aws_lightsail_instance.ovpn_server.name

  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
}
  }

resource "aws_lightsail_instance_public_ports" "openvpn_udp" {
  instance_name = aws_lightsail_instance.ovpn_server.name

  port_info {
    protocol  = "udp"
    from_port = 1194
    to_port   = 1194
  }
}

resource "aws_lightsail_instance_public_ports" "openvpn_tcp" {
  instance_name = aws_lightsail_instance.ovpn_server.name

  port_info {
    protocol  = "tcp"
    from_port = 1194
    to_port   = 1194
  }
}

resource "null_resource" "ansible_exec" {
    depends_on = [aws_lightsail_instance.ovpn_server]
    provisioner "local-exec" {
		working_dir = "${path.module}"
        command = <<EOF
			set -x

			export ovpn_user=${aws_lightsail_instance.ovpn_server.username}
			export ovpn_ip=${aws_lightsail_instance.ovpn_server.public_ip_address}

			export ANSIBLE_PERSISTENT_CONNECT_TIMEOUT=9999
			export ANSIBLE_PERSISTENT_COMMAND_TIMEOUT=9999
			export ANSIBLE_HOST_KEY_CHECKING=False 

			rm -f inventory client.ovpn

            echo "ovpn_server ansible_port=22 ansible_host=$ovpn_ip ansible_user=$ovpn_user ansible_ssh_private_key_file=~/.ssh/ovpn_server" > inventory
            
			while ! ssh -o StrictHostKeyChecking=accept-new -i ~/.ssh/ovpn_server $ovpn_user@$ovpn_ip whoami;
			do
				sleep 1s
			done

			unset ovpn_user
			unset ovpn_ip

            ansible-playbook -i inventory playbook.yaml -v

			unset ANSIBLE_PERSISTENT_CONNECT_TIMEOUT
			unset ANSIBLE_PERSISTENT_COMMAND_TIMEOUT
			unset ANSIBLE_HOST_KEY_CHECKING

			set +x
        EOF
    }
}

