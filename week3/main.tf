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
  count = var.public_subnets_total

  vpc_id                  = aws_vpc.default.id
  cidr_block              = cidrsubnet(aws_vpc.default.cidr_block, var.subnet_prefix_newbits, count.index)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name = "hello-public-${count.index}"
  }
}

locals {
  private_subnet_offset = pow(2, var.subnet_prefix_newbits) / 2
}

resource "aws_subnet" "private" {
  count = var.private_subnets_total

  vpc_id                  = aws_vpc.default.id
  cidr_block              = cidrsubnet(aws_vpc.default.cidr_block, var.subnet_prefix_newbits, local.private_subnet_offset + count.index)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "hello-private-${count.index}"
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
  for_each = toset(data.aws_availability_zones.available.names)

  vpc  = true
  tags = {
    Name = "nat-eip-${each.value}"
  }
}

resource "aws_nat_gateway" "default" {
  for_each = toset(data.aws_availability_zones.available.names)

  allocation_id = aws_eip.nat[each.value].id
  subnet_id     = [for subnet in aws_subnet.public : subnet.id if subnet.availability_zone == each.value][0]
  depends_on    = [aws_internet_gateway.default]
  tags = {
    Name = "hello-nat-${each.value}"
  }
}

resource "aws_route_table" "private" {
  for_each = toset(data.aws_availability_zones.available.names)

  vpc_id = aws_vpc.default.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.default[each.value].id
  }
  tags = {
    Name = "hello-private-rt-${each.value}"
  }
}

resource "aws_route_table_association" "private" {
  count = var.private_subnets_total

  route_table_id = aws_route_table.private[aws_subnet.private[count.index].availability_zone].id
  subnet_id      = aws_subnet.private[count.index].id
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
  subnets         = [for subnet in aws_subnet.public : subnet.id]
  security_groups = [aws_security_group.elb.id]

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

resource "aws_launch_configuration" "hello" {
  name_prefix            = "hello-"
  image_id               = var.aws_debian_buster_amis[var.aws_region]
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.hello.key_name
  security_groups        = [aws_security_group.hello.id]
  user_data              = file("./install")

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "hello" {
  name                  = "hello-asg"
  launch_configuration  = aws_launch_configuration.hello.name
  min_size              = 3
  max_size              = 6
  vpc_zone_identifier   = [for subnet in aws_subnet.private : subnet.id]
  load_balancers        = [aws_elb.hello.name]
  wait_for_elb_capacity = 3
  # Ensure NAT Gateway and routing are up for internet access during instance user-data bootstrap
  depends_on            = [aws_route_table_association.private]

  lifecycle {
    create_before_destroy = true
  }
  
  tag {
    key = "Name"
    value = "hello-asg"
    propagate_at_launch = true
  }
}

resource "aws_instance" "bastion" {
  ami                    = var.aws_debian_buster_amis[var.aws_region]
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.hello.key_name
  vpc_security_group_ids = [aws_security_group.bastion.id]
  subnet_id              = aws_subnet.public[0].id
  tags = {
    Name = "hello-bastion"
  }
}
