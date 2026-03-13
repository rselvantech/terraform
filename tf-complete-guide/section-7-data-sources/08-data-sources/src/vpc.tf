data "aws_vpc" "prod" {
  tags = {
    Env = "prod"
  }
}