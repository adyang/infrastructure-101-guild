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

resource "aws_security_group" "lb" {
  name    = "hello-lb-security-group"
  vpc_id  = aws_vpc.default.id

  ingress {
    description = "HTTP access to Load Balancer"
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

resource "aws_security_group" "ecs" {
  name    = "hello-ecs-security-group"
  vpc_id  = aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  ingress {
    description = "Load Balancer access to ECS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    security_groups = [aws_security_group.lb.id]
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

resource "aws_key_pair" "hello" {
  key_name   = "hello-key"
  public_key = file(var.ssh_public_key_path)
}

data "aws_iam_policy_document" "ecs_agent" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com", "ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_agent" {
  name               = "ecs-agent"
  assume_role_policy = data.aws_iam_policy_document.ecs_agent.json
}

resource "aws_iam_role_policy_attachment" "ecs_agent" {
  role       = aws_iam_role.ecs_agent.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_agent" {
  name = "ecs-agent"
  role = aws_iam_role.ecs_agent.name
}

resource "aws_ecs_cluster" "hello" {
  name = "hello"
}

data "aws_ami" "ecs_optimized" {
  owners = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-2.0.20200928-x86_64-ebs"]
  }
}

resource "aws_launch_configuration" "ecs" {
  name_prefix            = "hello-ecs-"
  image_id               = data.aws_ami.ecs_optimized.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.hello.key_name
  iam_instance_profile   = aws_iam_instance_profile.ecs_agent.name
  security_groups        = [aws_security_group.ecs.id]
  user_data              = <<-EOF
  #!/bin/bash
  echo 'ECS_CLUSTER=${aws_ecs_cluster.hello.name}' >>/etc/ecs/ecs.config
  EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "ecs" {
  name                  = "hello-ecs-asg"
  launch_configuration  = aws_launch_configuration.ecs.name
  min_size              = 3
  max_size              = 6
  vpc_zone_identifier   = aws_subnet.private[*].id

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key = "Name"
    value = "hello-ecs-asg"
    propagate_at_launch = true
  }
}

resource "aws_lb" "hello" {
  name               = "hello-lb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.lb.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "hello" {
  name     = "hello-tg"
  port     = 80 # Only to ensure target group can be created, will be overwritten by ECS dynamic port mappings.
  protocol = "HTTP"
  vpc_id   = aws_vpc.default.id
}

resource "aws_lb_listener" "hello" {
  load_balancer_arn = aws_lb.hello.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.hello.arn
  }
}

resource "aws_ecs_task_definition" "hello" {
  family                = "hello"
  container_definitions = file("./hello.json")
}

resource "aws_ecs_service" "hello" {
  name            = "hello-service"
  cluster         = aws_ecs_cluster.hello.id
  task_definition = aws_ecs_task_definition.hello.arn
  desired_count   = 3
  depends_on      = [aws_lb_listener.hello]

  load_balancer {
    target_group_arn = aws_lb_target_group.hello.arn
    container_name   = "hello"
    container_port   = 8080
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
