resource "aws_instance" "web" {
  ami                         = "ami-0155a797954ec1cde"
#  ami                         = "ami-07db84a20169e03e0"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.public_http.id]

  root_block_device {
    volume_size           = 10
    volume_type           = "gp3"
    delete_on_termination = true
  }

  lifecycle {
    create_before_destroy = true
     ignore_changes        = [tags]
  }

  tags = merge(local.common_tags, {
    Name = "06-ec2-nginx-web"
#    Environment = "demo"
  })

}