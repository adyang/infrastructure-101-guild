output "address" {
  value = aws_elb.hello.dns_name
}

output "bastion_ip" {
  value = aws_instance.bastion.public_ip
}

output "hello_private_ip" {
  value = aws_instance.hello.private_ip
}
