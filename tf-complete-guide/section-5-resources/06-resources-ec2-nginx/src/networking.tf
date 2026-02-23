locals {
  common_tags = {
    ManagedBy  = "Terraform"
    Project    = "06-resources-ec2-nginx"
    CostCenter = "1234"
  }
}

resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"

  tags = merge(local.common_tags, {
    Name = "06-ec2-nginx-vpc"
  })
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = "10.0.0.0/24"
  tags = merge(local.common_tags, {
    Name = "06-ec2-nginx-public"
  })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = merge(local.common_tags, {
    Name = "06-ec2-nginx-igw"
  })
}

resource "aws_route_table" "public-rtb" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(local.common_tags, {
    Name = "06-ec2-nginx-public-rtb"
  })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public-rtb.id
}