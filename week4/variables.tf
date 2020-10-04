variable "ssh_public_key_path" {
  description = "Path to SSH public key for authentication. E.g. ~/.ssh/infra101.pub"
}

variable "aws_region" {
  description = "AWS region to launch servers."
  default     = "ap-northeast-1"
}

variable "aws_debian_buster_amis" {
  default = {
    ap-northeast-1 = "ami-0c8a2bdcc1d1b2c68"
    ap-northeast-2 = "ami-0cfac5615120abb29"
    ap-south-1 = "ami-0bed823f39b8d9828"
    ap-southeast-1 = "ami-0003a0dda9240a8da"
    ap-southeast-2 = "ami-08638c72b63ff353b"
  }
}

variable "subnet_prefix_newbits" {
  description = "Additional prefix bits to add to vpc prefix to form the subnet. This determines size of each subnet, e.g. 2 ^ (32 - vpc_prefix - subnet_prefix_newbits). Also used to derive private subnet offset."
  default = 8
}

variable "public_subnets_total" {
  default = 3
}

variable "private_subnets_total" {
  default = 3
}
