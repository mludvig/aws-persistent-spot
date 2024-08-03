#!/bin/bash -e

if [ "$1" = "start" ]; then
    echo "Starting ASG"
    DESIRED_CAPACITY=1
elif [ "$1" = "stop" ]; then
    echo "Stopping ASG"
    DESIRED_CAPACITY=0
else
    echo "Retrieving current state..."
    CURRENT_STATE=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${ASG_NAME})
    DESIRED_CAPACITY=$(jq -r '.AutoScalingGroups[0].DesiredCapacity' <<< ${CURRENT_STATE})
    echo "Desired capacity: ${DESIRED_CAPACITY}"
    RUNNING_INSTANCES=$(jq -r 'if (.AutoScalingGroups[0].Instances | length) == 0 then "0" else [.AutoScalingGroups[0].Instances[].InstanceType] | group_by(.) | map("\(length)x \(.[0])") | .[] end' <<< ${CURRENT_STATE})
    echo "Running instances: ${RUNNING_INSTANCES}"
    echo "=="
    echo "Please use '$0 start' or '$0 stop' to change"
    exit
fi

TF_OUTPUTS=$(terraform output -json)
ASG_NAME=$(jq -r '.asg_name.value' <<< ${TF_OUTPUTS})
AWS_REGION=$(jq -r '.aws_region.value' <<< ${TF_OUTPUTS})

set -x
aws --region=${AWS_REGION} autoscaling set-desired-capacity --auto-scaling-group-name ${ASG_NAME} --desired-capacity ${DESIRED_CAPACITY}