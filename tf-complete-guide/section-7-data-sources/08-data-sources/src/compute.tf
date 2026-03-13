# Dynamically resolves the latest Ubuntu 24.04 LTS (Noble) AMI
# for the current provider region — no hardcoded AMI ID needed
data "aws_ami" "ubuntu" {
  # OPTIONAL — when multiple AMIs match, return the most recently created
  # Without this, Terraform errors if more than one result is found
  most_recent = true

  # MANDATORY — at least one owner required
  # "099720109477" is Canonical's AWS account ID (publisher of Ubuntu AMIs)
  # Using the account ID is more reliable than the alias "canonical"
  owners = ["099720109477"]

  # Filter by AMI name pattern — wildcards (*) match any characters
  # hvm-ssd-gp3 = HVM virtualization, gp3 EBS root volume (current gen)
  # ubuntu-noble-24.04 = Ubuntu 24.04 LTS
  # amd64 = x86_64 architecture (required for t3.micro)
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  # Ensures we only get HVM (hardware virtual machine) images
  # HVM is required for current-generation instance types (t3, m5, etc.)
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Same AMI but in us-east-1 (uses aliased provider)
data "aws_ami" "ubuntu_us_east_1" {
  provider    = aws.us-east-1 # explicit provider assignment
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_instance" "web" {
  # AMI resolved dynamically from the data source above
  # No region-specific AMI ID hardcoded here
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  tags = {
    Name      = "08-data-sources-web"
    ManagedBy = "Terraform"
    Project   = "08-data-sources"
  }
}
