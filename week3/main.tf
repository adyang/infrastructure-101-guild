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
  region  = var.aws_region
}

resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "hello"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = {
    Name = "hello-public"
  }
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags = {
    Name = "hello-private"
  }
}

resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id
  tags = {
    Name = "hello-igw"
  }
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.default.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.default.id
}

resource "aws_eip" "nat" {
  vpc  = true
  tags = {
    Name = "nat-eip"
  }
}

resource "aws_nat_gateway" "default" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [aws_internet_gateway.default]
  tags = {
    Name = "hello-nat"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.default.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.default.id
  }
  tags = {
    Name = "hello-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  route_table_id = aws_route_table.private.id
  subnet_id      = aws_subnet.private.id
}

resource "aws_security_group" "elb" {
  name    = "hello-elb-security-group"
  vpc_id  = aws_vpc.default.id

  ingress {
    description = "HTTP access to ELB"
    from_port   = 80
    to_port     = 80
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

resource "aws_security_group" "hello" {
  name    = "hello-security-group"
  vpc_id  = aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  ingress {
    description = "hello server port"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "bastion" {
  name    = "hello-bastion-security-group"
  vpc_id  = aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
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

resource "aws_elb" "hello" {
  name            = "hello-elb"
  subnets         = [aws_subnet.public.id]
  security_groups = [aws_security_group.elb.id]
  instances       = [aws_instance.hello.id]

  listener {
    instance_port     = 5000
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
}

resource "aws_key_pair" "hello" {
  key_name   = "hello-key"
  public_key = file(var.ssh_public_key_path)
}

resource "aws_instance" "hello" {
  ami                    = var.aws_debian_buster_amis[var.aws_region]
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.hello.key_name
  vpc_security_group_ids = [aws_security_group.hello.id]
  subnet_id              = aws_subnet.private.id
  user_data              = file("./install")
  depends_on             = [aws_route_table_association.private]
  tags = {
    Name = "hello"
  }
}

resource "aws_instance" "bastion" {
  ami                    = var.aws_debian_buster_amis[var.aws_region]
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.hello.key_name
  vpc_security_group_ids = [aws_security_group.bastion.id]
  subnet_id              = aws_subnet.public.id
  tags = {
    Name = "hello-bastion"
  }
}
