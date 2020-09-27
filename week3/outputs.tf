output "address" {
  value = aws_elb.hello.dns_name
}

output "bastion_ip" {
  value = aws_instance.bastion.public_ip
}

data "aws_instances" "hello" {
  depends_on = [aws_autoscaling_group.hello]
  instance_tags = {
    Name = "hello-asg"
  }
}

output "hello_private_ips" {
  value = data.aws_instances.hello.private_ips
}
