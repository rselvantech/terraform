# Fetches all availability zones in the current region
# state = "available" — excludes impaired or unavailable AZs
data "aws_availability_zones" "available" {
  state = "available"
}