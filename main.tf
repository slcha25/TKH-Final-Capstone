# Create Custom VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "capstone-vpc"
    Environment = "production"
    Project     = "capstone"
  }
}

# Create Public Subnets
resource "aws_subnet" "main" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  tags = {
    Name        = "capstone-subnet"
    Environment = "production"
    Project     = "capstone"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "capstone-igw"
    Environment = "production"
    Project     = "capstone"
  }
}


# Create Route Table
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

# Associate Subnets with Route Table
resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# Web Server Security Group (It like the virtual firewall)
resource "aws_security_group" "web" {
  name_prefix = "web-sg"
  vpc_id      = aws_vpc.main.id

# HTTP access
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP web traffic - public web server access"
  }

   # SSH access (restricted) (port 22) - only allow personal IP
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["74.64.35.195/32"]  # <--your Home IP /e.g. "123.45.67.89/32"
    description = "Allow SSH from my IP only"
  }

# Outbound - only necessary ports
  egress {
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

# Auto Scaling Group (or single instance)

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

  # User Data Script - it run automatically when the Server run
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

output "public_ip" {
  value       = aws_instance.web.public_ip
  description = "Public IP address of the web server"
}

output "public_dns" {
  value       = aws_instance.web.public_dns
  description = "Public DNS of the web server"
}