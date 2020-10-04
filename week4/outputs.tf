output "lb_address" {
  value = aws_lb.hello.dns_name
}

output "bastion_ip" {
  value = aws_instance.bastion.public_ip
}

data "aws_instances" "ecs" {
  depends_on = [aws_autoscaling_group.ecs]
  instance_tags = {
    Name = "hello-ecs-asg"
  }
}

output "ecs_private_ips" {
  value = data.aws_instances.ecs.private_ips
}
