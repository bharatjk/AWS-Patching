# Enterprise EC2 OS Patching Blueprint

This operational repository houses the infrastructure-as-code required to manage automated **Mutable OS Patching**, audit centralization, and dynamic alerting inside an AWS enterprise infrastructure ecosystem.

## 📋 Architectural Strategy Summary
* **Least-Privilege Isolation:** Prevents wide-scope visibility blocks. EC2 instances can exclusively `PutObject` logs into a localized path, while SSM holds explicit publishing execution access directly to encrypted SNS.
* **Environmental Velocity Gating:** Throttles baseline criteria safely. Dev clusters take patches after a single day, whereas production instances observe a hard 7-day stabilization block.
* **Audit Aggregation:** Pipes standard out console streams into an isolated S3 bucket featuring strict server-side encryption enforcement, explicit public access blocking, and dynamic Glacier archiving workflows.

## 🗂️ Existing Workspace Assumptions
To deploy seamlessly, this script maps cleanly around an infrastructure design assuming the following pieces:
1. **Network Layer Connectivity:** Running target EC2 instances reside inside subnets equipped with a route to an internet gateway, or have attached **VPC Endpoints** mapped for SSM (`ssm`, `ssmmessages`, `ec2messages`) and S3.
2. **Pre-Existing Host Nodes:** Targets must run the SSM agent natively (pre-installed on Amazon Linux 2023) and carry the following specific tracking tag key-pair value:
   * **Key:** `PatchGroup` 
   * **Value:** `dev-patch-group` OR `prod-patch-group` (Must strictly match the targeted deployment tier).

## 🚀 Execution & Command Orchestration

### Step 1: Initialize Workspace Infrastructure
```bash
terraform init
```

### Step 2: Validate Environmental Targets (Dev Pipeline)
```bash
terraform plan -var-file="dev.tfvars"
```

### Step 3: Run Deployments Against Target (Dev Pipeline)
```bash
terraform apply -var-file="dev.tfvars" --auto-approve
```

### Step 4: Promote and Secure Production State
```bash
terraform plan -var-file="prod.tfvars"
terraform apply -var-file="prod.tfvars"
```