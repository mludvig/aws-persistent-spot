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
  ami_id       = try(coalesce(var.ami_id, try(nonsensitive(data.aws_ssm_parameter.ami_id[0].value), null)), null)
  vpc_id       = try(coalesce(var.vpc_id, try(data.aws_vpc.default[0].id, null)), null)
  subnet_id    = try(coalesce(var.subnet_id, try(data.aws_subnet.default[0].id, null)), null)
}

# === Data ===

data "aws_ssm_parameter" "ami_id" {
  count = var.ami_id == null ? 1 : 0
  name  = var.ami_id_ssm
}

data "aws_vpc" "default" {
  count = var.vpc_id == null ? 1 : 0
  default = true
  # filter {
  #   name   = "cidr"
  #   values = ["172.31.0.0/16"]
  # }
}

data "aws_subnet" "default" {
  count = var.subnet_id == null ? 1 : 0
  vpc_id = local.vpc_id
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
  vpc_id = local.vpc_id
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
  name               = local.project_name
  assume_role_policy = <<EOF
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
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonEC2FullAccess",
  ]
  #   inline_policy {
  #     policy = <<EOF
  # {
  #     "Version": "2012-10-17",
  #     "Statement": [
  #         {
  #             "Effect": "Allow",
  #             "Action": [
  #                 "ec2:AttachVolume",
  #                 "ec2:DettachVolume",
  #                 "ec2:DescribeVolumes",
  #                 "ec2:AssociateAddress",
  #                 "ec2:DisassociateAddress",
  #                 "ec2:DescribeAddresses",
  #                 "ec2:DescribeInstances"
  #             ],
  #             "Resource": "*"
  #         }
  #     ]
  # }
  # EOF
  #   }
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
  image_id               = local.ami_id
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
  vpc_zone_identifier = [local.subnet_id]
  dynamic "tag" {
    # Needed to propagate tags to the instances
    for_each = var.default_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

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
  type = string
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
    # Must have at least 'Name' tag
    Name = "spot-instance"
  }
}

variable "ebs_size" {
  type    = number
  default = 150
}

variable "ami_id" {
  type    = string
  default = null
}

variable "ami_id_ssm" {
  type    = string
  default = null
}

variable "prefix_list_id" {
  type = string
}

variable "vpc_id" {
  type = string
  default = null
}

variable "subnet_id" {
  type = string
  default = null
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
