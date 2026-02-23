resource "aws_security_group" "public_http" {
  name        = "06-resources-ec2-nginx-public-http"
  description = "Allow HTTP and HTTPS inbound traffic from the internet"
  vpc_id      = aws_vpc.vpc.id

  tags = merge(local.common_tags, {
    Name = "06-ec2-nginx-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.public_http.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
  description       = "Allow HTTP from internet"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.public_http.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
  description       = "Allow HTTPS from internet"
}