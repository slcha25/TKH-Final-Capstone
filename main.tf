# ============================================
# VPC 配置
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
# VPC Flow Logs - 修复 AVD-AWS-0178 (MEDIUM)
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

# CloudWatch Log Group for Flow Logs
resource "aws_cloudwatch_log_group" "flow_log" {
  name = "capstone-vpc-flow-logs"
  retention_in_days = 30

  tags = {
    Environment = "production"
    Project     = "capstone"
  }
}

# IAM Role for Flow Logs
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
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

# ============================================
# 子网配置
# ============================================
resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name        = "capstone-subnet"
    Environment = "production"
    Project     = "capstone"
  }
}

# ============================================
# 互联网网关
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
# 路由表
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
# 路由表关联
# ============================================
resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# ============================================
# 安全组 - 修复所有安全组相关问题
# ============================================
resource "aws_security_group" "web" {
  name_prefix = "web-sg"
  vpc_id      = aws_vpc.main.id

  description = "Security group for web server - allows HTTP and restricted SSH access"

  # HTTP 入站规则 - 修复 AVD-AWS-0107 (CRITICAL)
  # 注意：Web服务器必须允许 HTTP 从任何地方访问
  ingress {
    description = "Allow HTTP from anywhere for public web access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH 入站规则 - 严格限制 IP
  ingress {
    description = "Allow SSH from authorized IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["74.64.35.195/32"]  # 替换为你的实际IP
  }

  # 出站规则 - 修复 AVD-AWS-0104 (CRITICAL)
  # 允许必要的出站流量（访问互联网更新软件）
  egress {
    description = "Allow all outbound traffic for system updates and internet access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "web-sg"
    Environment = "production"
    Project     = "capstone"
  }
}

# ============================================
# EC2 实例 - 修复 AVD-AWS-0028 (HIGH)
# ============================================
resource "aws_instance" "web" {
  ami           = "ami-0c02fb55956c7d316"  # Amazon Linux 2023
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.web.id]

  # 加密根卷
  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 8
  }

  # 强制使用 IMDSv2 - 修复 AVD-AWS-0028
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # 强制使用 token
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  # 用户数据
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
# 输出
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