terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.7.0"
    }
  }
}

provider "aws" {
  profile = "saml"
  region  = "ap-southeast-1"
}

resource "aws_security_group" "hello" {
  name = "hello-security-group"
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "hello server port"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "hello" {
  key_name   = "hello-key"
  public_key = file("../.ssh/infra101.pub")
}

resource "aws_instance" "hello" {
  ami                    = "ami-0003a0dda9240a8da"
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.hello.key_name
  vpc_security_group_ids = [aws_security_group.hello.id]
  user_data              = file("./install")
  tags = {
    Name = "hello"
  }
}

resource "aws_eip" "ip" {
  instance = aws_instance.hello.id
  vpc      = true
}

output "ip" {
  value = aws_eip.ip.public_ip
}
