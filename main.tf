# ============================================
# use a data source to dynamically look up the latest Amazon Linux 2023 AMI instead of hardcoding it.
# ============================================

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
# ============================================
# VPC
# ============================================
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "capstone-vpc"
    Environment = "production"
    Project     = "capstone"
  }
}

# ============================================
# KMS Key for CloudWatch Encryption
# ============================================
resource "aws_kms_key" "cloudwatch" {
  description             = "KMS key for CloudWatch Log Group encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Environment = "production"
    Project     = "capstone"
  }
}

resource "aws_kms_alias" "cloudwatch" {
  name          = "alias/capstone-cloudwatch"
  target_key_id = aws_kms_key.cloudwatch.key_id
}

# ============================================
# CloudWatch Log Group (加密)
# ============================================
resource "aws_cloudwatch_log_group" "flow_log" {
  name              = "capstone-vpc-flow-logs"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.cloudwatch.arn

  tags = {
    Environment = "production"
    Project     = "capstone"
  }
}

# ============================================
# IAM Role for Flow Logs
# ============================================
resource "aws_iam_role" "flow_log_role" {
  name = "capstone-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = "production"
    Project     = "capstone"
  }
}

# IAM Policy - 限制资源范围
# NOTE: The trailing ":*" is required by AWS to scope this policy to log
# streams within this specific log group (arn:...:log-group:name:*).
# This is not a true wildcard — it's the documented AWS pattern for
# CloudWatch Logs least-privilege scoping. See AWS docs Example 3:
# https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/permissions-reference-cwl.html
#tfsec:ignore:aws-iam-no-policy-wildcards
resource "aws_iam_role_policy" "flow_log_policy" {
  name = "capstone-flow-log-policy"
  role = aws_iam_role.flow_log_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "${aws_cloudwatch_log_group.flow_log.arn}:*"
      }
    ]
  })
}

# ============================================
# Subnet (不自动分配公网IP)
# ============================================
resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = false

  tags = {
    Name        = "capstone-subnet"
    Environment = "production"
    Project     = "capstone"
  }
}

# ============================================
# Internet Gateway
# ============================================
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "capstone-igw"
    Environment = "production"
    Project     = "capstone"
  }
}

# ============================================
# Route Table
# ============================================
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "capstone-route-table"
    Environment = "production"
    Project     = "capstone"
  }
}

# ============================================
# Route Table Association
# ============================================
resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# ============================================
# VPC Flow Logs
# ============================================
resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.flow_log_role.arn
  log_destination = aws_cloudwatch_log_group.flow_log.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id

  tags = {
    Name        = "capstone-flow-logs"
    Environment = "production"
    Project     = "capstone"
  }
}

# ============================================
# Security Group
# ============================================
resource "aws_security_group" "web" {
  name_prefix = "web-sg"
  vpc_id      = aws_vpc.main.id
  description = "Security group for web server"

  tags = {
    Name        = "web-sg"
    Environment = "production"
    Project     = "capstone"
  }
}

# Security Group Rules
# tfsec:ignore:aws-ec2-no-public-ingress-sgr
resource "aws_security_group_rule" "http_inbound" {
  type              = "ingress"
  description       = "Allow HTTP from anywhere for public web access"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web.id
}

resource "aws_security_group_rule" "ssh_inbound" {
  type              = "ingress"
  description       = "Allow SSH from authorized IP only"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["74.64.35.195/32"]
  security_group_id = aws_security_group.web.id
}

#tfsec:ignore:aws-ec2-no-public-egress-sgr
resource "aws_security_group_rule" "all_outbound" {
  type              = "egress"
  description       = "Allow all outbound traffic for system updates"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web.id
}

# ============================================
# EC2 Instance
# ============================================
resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.web.id]
  
  associate_public_ip_address = true

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 8
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "<h1>Hello from Capstone Project!</h1>" > /var/www/html/index.html
  EOF

  tags = {
    Name        = "capstone-web-server"
    Environment = "production"
    Project     = "capstone"
  }
}

# ============================================
# Outputs
# ============================================
output "public_ip" {
  value       = aws_instance.web.public_ip
  description = "Public IP address of the web server"
}

output "public_dns" {
  value       = aws_instance.web.public_dns
  description = "Public DNS of the web server"
}

output "vpc_id" {
  value       = aws_vpc.main.id
  description = "VPC ID"
}