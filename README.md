# Persistent AWS Spot Instance

AWS Spot Instances are a cost-effective way to access powerful but expensive resources, such as GPU instances, but they come with the risk of termination by AWS at any time. Additionally, Spot Instances cannot be stopped and restarted; any attached storage is lost when the instance is terminated.

This project provides a solution to these issues using Terraform to create a Spot Instance with persistent storage and network configuration. By utilizing an _Auto Scaling Group (ASG)_, this setup ensures that a Spot Instance is created with the following features:

- **Persistent EBS Volume**: An Elastic Block Store (EBS) volume is attached and mounted at `/data`. The home directory for the `ubuntu` user is relocated to this volume, ensuring that user files are preserved across Spot Instance terminations.
- **Persistent Elastic IP**: An Elastic IP (EIP) is associated with the instance to provide a consistent public IP address.

## Features

- **Auto Scaling Group**: Manages the lifecycle of Spot Instances, ensuring automatic replacement if terminated.
- **Persistent Storage**: EBS volume maintains data across instance terminations.
- **Consistent IP Address**: Elastic IP provides a stable external IP for the instance.
- **Auto shut-down**: The instance is automatically shut down after working hours to save costs. Use the included script `asg-start-stop.sh start` to spin up a new instance in the ASG when needed. Likewise `asg-start-stop.sh stop` can be used to shut it down before the scheduled time to save more costs.

## Setup

1. **Install Terraform**: Make sure you have Terraform installed. You can download it from [Terraform's official website](https://www.terraform.io/downloads.html).

2. **Clone the Repository and initialize Terraform**:
    ```sh
    git clone https://github.com/mludvig/aws-spot-instance.git
    cd aws-spot-instance
    terraform init
    ```

3. **Configure the Variables**:
    - Copy the `terraform.tfvars.example` file to `terraform.tfvars` and edit it to set the desired values.

4. **Create the Resources using Terraform**:
    ```sh
    terraform apply
    ```

The ASG will be created with **0 instances**. Use the `asg-start-stop.sh start` script to start the instance.

## Usage

- **Data Persistence**: Any data stored in the `/data` directory will be retained across Spot Instance terminations.
- **Instance Termination**: Be aware that any changes outside of the `/data` directory will be lost when the Spot Instance is terminated.
- **First start**: Format the data disk with `sudo mkfs.ext4 /dev/nvme1n1` and mount it with `sudo mount /dev/nvme1n1 /data`. Next copy the home directory to the data disk with `sudo rsync -a /home/ubuntu /data/`. This is a one-time setup, the data will be retained across instance terminations.

## Credits

Created by Michael Ludvig under a MIT License. Feel free to use, modify, and distribute this code as you see fit.