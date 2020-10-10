terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.7.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "~> 1.13.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
  profile = "saml"
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
}

locals {
  cluster_name = "infra101-eks"
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name                 = "${local.cluster_name}-vpc"
  cidr                 = "192.168.16.0/20"
  azs                  = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets      = ["192.168.16.0/24", "192.168.17.0/24"]
  public_subnets       = ["192.168.18.0/24", "192.168.19.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

module "eks" {
  source                         = "terraform-aws-modules/eks/aws"
  cluster_name                   = local.cluster_name
  cluster_version                = "1.17"
  cluster_endpoint_public_access = "true"

  tags = {
    environment = local.cluster_name
  }

  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.private_subnets

  worker_groups = [
    {
      autoscaling_enabled  = true
      asg_min_size         = 2
      asg_max_size         = 2
      asg_desired_capacity = 2
      instance_type        = "t3.small"
    }
  ]
}
