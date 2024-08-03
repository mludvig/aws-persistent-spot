// aws infrastructure, with ASG

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = var.default_tags
  }
}

locals {
  project_name = var.default_tags["Name"]
}

# === Data ===

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet" "default" {
  vpc_id = data.aws_vpc.default.id
  filter {
    name   = "availability-zone"
    values = [var.az_name]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# === Resources ===

resource "aws_security_group" "main" {
  name = local.project_name
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    prefix_list_ids = [var.prefix_list_id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "main" {
  name                = local.project_name
  assume_role_policy  = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
  managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
  inline_policy {
    policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AttachVolume",
                "ec2:DettachVolume",
                "ec2:DescribeVolumes",
                "ec2:AssociateAddress",
                "ec2:DisassociateAddress",
                "ec2:DescribeAddresses",
                "ec2:DescribeInstances"
            ],
            "Resource": "*"
        }
    ]
}
EOF
  }
}

resource "aws_iam_instance_profile" "main" {
  name = local.project_name
  role = aws_iam_role.main.name
}

resource "aws_eip" "main" {
}

resource "aws_ebs_volume" "main" {
  availability_zone = var.az_name
  size              = var.ebs_size
  type              = "gp3"
  tags = {
    Name = "${local.project_name}-data"
  }
}

resource "aws_launch_template" "main" {
  image_id               = var.ami_id
  instance_type          = var.instance_type
  name                   = local.project_name
  vpc_security_group_ids = [aws_security_group.main.id]
  key_name               = var.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.main.name
  }
  instance_market_options {
    market_type = "spot"
  }
  user_data = base64encode(templatefile("userdata.sh.template", {
    VOLUME_ID         = aws_ebs_volume.main.id,
    EIP_ALLOCATION_ID = aws_eip.main.id,
  }))
}

resource "aws_autoscaling_group" "main" {
  name = local.project_name
  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }
  min_size            = 0
  max_size            = 1
  desired_capacity    = 0
  vpc_zone_identifier = [data.aws_subnet.default.id]
  tag {
    key                 = "Name"
    value               = local.project_name
    propagate_at_launch = true
  }
}

// schedule asg to terminate at night
resource "aws_autoscaling_schedule" "main" {
  scheduled_action_name  = "${local.project_name}-shutdown"
  min_size               = 0
  max_size               = 1
  desired_capacity       = 0
  recurrence             = var.asg_shutdown_cron
  time_zone              = var.asg_shutdown_tz
  autoscaling_group_name = aws_autoscaling_group.main.name
}

# === Variables ===

variable "instance_type" {
  type    = string
  default = "inf2.8xlarge"
}

variable "aws_region" {
  type = string
}

variable "az_name" {
  type = string
}

variable "default_tags" {
  type = map(any)
  default = {
    Name = "inf2"
  }
}

variable "ebs_size" {
  type    = number
  default = 150
}

variable "ami_id" {
  type = string
}

variable "prefix_list_id" {
  type = string
}

variable "key_name" {
  type = string
}

variable "asg_shutdown_cron" {
  type    = string
  default = "0 21 * * *"
}

variable "asg_shutdown_tz" {
  type    = string
  default = "Pacific/Auckland"
}

# === Outputs ===
output "aws_region" {
  value = var.aws_region
}

output "eip" {
  value = aws_eip.main.public_ip
}

output "asg_name" {
  value = aws_autoscaling_group.main.name
}