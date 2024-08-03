#!/bin/bash -e

set -x

TF_OUTPUTS=$(terraform output -json)
ASG_NAME=$(jq -r '.asg_name.value' <<< ${TF_OUTPUTS})
AWS_REGION=$(jq -r '.aws_region.value' <<< ${TF_OUTPUTS})
aws --region=${AWS_REGION} autoscaling set-desired-capacity --auto-scaling-group-name ${ASG_NAME} --desired-capacity 1