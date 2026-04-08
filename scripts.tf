terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "project_prefix" {
  description = "Prefix used for naming AWS resources"
  type        = string
  default     = "reportes"
}

variable "vpc_id" {
  description = "Optional VPC where the infrastructure will be deployed"
  type        = string
  default     = null
  nullable    = true
}

variable "subnet_ids" {
  description = "Optional subnet IDs used by the ALB, EC2 instances, and RDS"
  type        = list(string)
  default     = null
  nullable    = true
}

variable "app_instance_type" {
  description = "Instance type for application services"
  type        = string
  default     = "t3.small"
}

variable "broker_instance_type" {
  description = "Instance type for the RabbitMQ broker"
  type        = string
  default     = "t2.nano"
}

variable "worker_instance_type" {
  description = "Instance type for the analysis worker"
  type        = string
  default     = "t3.medium"
}

variable "database_instance_class" {
  description = "Instance class for PostgreSQL RDS databases"
  type        = string
  default     = "db.t3.micro"
}

variable "database_allocated_storage" {
  description = "Allocated storage in GB for each PostgreSQL database"
  type        = number
  default     = 20
}

variable "database_username" {
  description = "Master username for the PostgreSQL databases"
  type        = string
  default     = "postgresadmin"
}

variable "database_password" {
  description = "Master password for the PostgreSQL databases"
  type        = string
  default     = "Arquisoft2026!"
  sensitive   = true
}

provider "aws" {
  region = var.region
}

locals {
  project_name = "${var.project_prefix}-arquisoft"
  active_vpc_id = coalesce(var.vpc_id, data.aws_vpc.default.id)
  active_subnet_ids = var.subnet_ids != null ? var.subnet_ids : data.aws_subnets.default.ids

  common_tags = {
    Project   = local.project_name
    ManagedBy = "Terraform"
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "alb_public" {
  name        = "${var.project_prefix}-alb-public"
  description = "Allow public HTTP traffic to the application load balancer"
  vpc_id      = local.active_vpc_id

  ingress {
    description = "HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-alb-public"
  })
}

resource "aws_security_group" "ssh_access" {
  name        = "${var.project_prefix}-ssh-access"
  description = "Allow SSH access to the virtual machines"
  vpc_id      = local.active_vpc_id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-ssh-access"
  })
}

resource "aws_security_group" "reportes_service" {
  name        = "${var.project_prefix}-reportes-service"
  description = "Allow traffic from the ALB to the report handlers"
  vpc_id      = local.active_vpc_id

  ingress {
    description     = "HTTP from the ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_public.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-reportes-service"
  })
}

resource "aws_security_group" "internal_services" {
  name        = "${var.project_prefix}-internal-services"
  description = "Allow internal application traffic between backend services"
  vpc_id      = local.active_vpc_id

  ingress {
    description = "Internal application traffic"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-internal-services"
  })
}

resource "aws_security_group" "rabbitmq_service" {
  name        = "${var.project_prefix}-rabbitmq-service"
  description = "Allow AMQP traffic to RabbitMQ"
  vpc_id      = local.active_vpc_id

  ingress {
    description = "AMQP from application services"
    from_port   = 5672
    to_port     = 5672
    protocol    = "tcp"
    security_groups = [
      aws_security_group.reportes_service.id,
      aws_security_group.internal_services.id,
    ]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-rabbitmq-service"
  })
}

resource "aws_security_group" "database_service" {
  name        = "${var.project_prefix}-database-service"
  description = "Allow PostgreSQL traffic from backend services"
  vpc_id      = local.active_vpc_id

  ingress {
    description = "PostgreSQL from application services"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [
      aws_security_group.reportes_service.id,
      aws_security_group.internal_services.id,
    ]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-database-service"
  })
}

resource "aws_lb" "alb_reportes" {
  name               = "${var.project_prefix}-alb-reportes"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_public.id]
  subnets            = local.active_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-alb-reportes"
  })
}

resource "aws_lb_target_group" "tg_backend_reportes" {
  name     = "${var.project_prefix}-tg-reportes"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = local.active_vpc_id

  health_check {
    path                = "/health/"
    protocol            = "HTTP"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-tg-reportes"
  })
}

resource "aws_lb_listener" "http_frontend" {
  load_balancer_arn = aws_lb.alb_reportes.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_backend_reportes.arn
  }
}

resource "aws_instance" "manejador_reportes" {
  count = 2

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.app_instance_type
  subnet_id                   = local.active_subnet_ids[count.index % length(local.active_subnet_ids)]
  associate_public_ip_address = true
  vpc_security_group_ids = [
    aws_security_group.reportes_service.id,
    aws_security_group.internal_services.id,
    aws_security_group.ssh_access.id,
  ]

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-manejador-reportes-${count.index + 1}"
    Role = "manejador-reportes"
  })
}

resource "aws_lb_target_group_attachment" "attach_backend" {
  count            = 2
  target_group_arn = aws_lb_target_group.tg_backend_reportes.arn
  target_id        = aws_instance.manejador_reportes[count.index].id
  port             = 8000
}

resource "aws_instance" "rabbitmq" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.broker_instance_type
  subnet_id                   = local.active_subnet_ids[0]
  associate_public_ip_address = true
  vpc_security_group_ids = [
    aws_security_group.rabbitmq_service.id,
    aws_security_group.ssh_access.id,
  ]

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-rabbitmq"
    Role = "broker"
  })
}

resource "aws_instance" "analysis_worker" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.worker_instance_type
  subnet_id                   = local.active_subnet_ids[0]
  associate_public_ip_address = true
  vpc_security_group_ids = [
    aws_security_group.internal_services.id,
    aws_security_group.ssh_access.id,
  ]

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-analysis-worker"
    Role = "analysis-worker"
  })
}

resource "aws_instance" "manejador_cloud" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.app_instance_type
  subnet_id                   = local.active_subnet_ids[0]
  associate_public_ip_address = true
  vpc_security_group_ids = [
    aws_security_group.internal_services.id,
    aws_security_group.ssh_access.id,
  ]

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-manejador-cloud"
    Role = "manejador-cloud"
  })
}

resource "aws_instance" "manejador_usuarios" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.app_instance_type
  subnet_id                   = local.active_subnet_ids[0]
  associate_public_ip_address = true
  vpc_security_group_ids = [
    aws_security_group.internal_services.id,
    aws_security_group.ssh_access.id,
  ]

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-manejador-usuarios"
    Role = "manejador-usuarios"
  })
}

resource "aws_instance" "manejador_empresa" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.app_instance_type
  subnet_id                   = local.active_subnet_ids[0]
  associate_public_ip_address = true
  vpc_security_group_ids = [
    aws_security_group.internal_services.id,
    aws_security_group.ssh_access.id,
  ]

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-manejador-empresa"
    Role = "manejador-empresa"
  })
}

resource "aws_db_subnet_group" "databases" {
  name       = "${var.project_prefix}-databases"
  subnet_ids = local.active_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-databases"
  })
}

resource "aws_db_instance" "bd_auth" {
  identifier             = "${var.project_prefix}-bd-auth"
  engine                 = "postgres"
  instance_class         = var.database_instance_class
  allocated_storage      = var.database_allocated_storage
  db_name                = "bdauth"
  username               = var.database_username
  password               = var.database_password
  db_subnet_group_name   = aws_db_subnet_group.databases.name
  vpc_security_group_ids = [aws_security_group.database_service.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false
  storage_type           = "gp3"

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-bd-auth"
    Role = "database-auth"
  })
}

resource "aws_db_instance" "bd_negocio" {
  identifier             = "${var.project_prefix}-bd-negocio"
  engine                 = "postgres"
  instance_class         = var.database_instance_class
  allocated_storage      = var.database_allocated_storage
  db_name                = "bdnegocio"
  username               = var.database_username
  password               = var.database_password
  db_subnet_group_name   = aws_db_subnet_group.databases.name
  vpc_security_group_ids = [aws_security_group.database_service.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false
  storage_type           = "gp3"

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-bd-negocio"
    Role = "database-negocio"
  })
}

output "alb_reportes_dns" {
  description = "DNS name of the public load balancer for the report service"
  value       = aws_lb.alb_reportes.dns_name
}

output "manejadores_reportes_public_ips" {
  description = "Public IPs of the report handler instances"
  value       = aws_instance.manejador_reportes[*].public_ip
}

output "backend_private_ips" {
  description = "Private IPs of the internal virtual machines"
  value = {
    rabbitmq           = aws_instance.rabbitmq.private_ip
    analysis_worker    = aws_instance.analysis_worker.private_ip
    manejador_cloud    = aws_instance.manejador_cloud.private_ip
    manejador_usuarios = aws_instance.manejador_usuarios.private_ip
    manejador_empresa  = aws_instance.manejador_empresa.private_ip
  }
}

output "database_endpoints" {
  description = "Connection endpoints for the PostgreSQL RDS instances"
  value = {
    bd_auth    = aws_db_instance.bd_auth.address
    bd_negocio = aws_db_instance.bd_negocio.address
  }
}