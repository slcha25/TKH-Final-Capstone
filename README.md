# Secure Automated Web Architecture

*Capstone project — TKH Innovation Fellowship, Phase 2 Cybersecurity Fellow.*

## Description

This project provisions a secure, publicly accessible web server on AWS using fully automated Infrastructure as Code. A GitHub Actions pipeline acts as a DevSecOps quality gate, statically scanning every Terraform change for security misconfigurations before it's allowed to merge. The infrastructure follows least-privilege and defense-in-depth principles: a locked-down network perimeter, encrypted resources, and auditable network traffic via VPC Flow Logs.

## Tech Stack

**Infrastructure as Code**
- [Terraform](https://www.terraform.io/) (AWS provider v6.x)

**Cloud Provider & Services (AWS)**
- VPC, Subnet, Internet Gateway, Route Table — network layer
- EC2 (t2.micro, Amazon Linux 2023) — compute
- Security Groups — instance-level firewall
- IAM (Roles & Policies) — least-privilege access
- KMS — encryption key management
- CloudWatch Logs — centralized, encrypted log storage
- VPC Flow Logs — network traffic auditing

**CI/CD & Security**
- GitHub Actions — pipeline automation
- [tfsec](https://aquasecurity.github.io/tfsec/) (Aqua Security) — static analysis (SAST) for Terraform

**Application**
- Apache HTTP Server (`httpd`) on Amazon Linux 2023

## Architecture

```
Internet
   │
   ▼
Internet Gateway
   │
   ▼
Route Table (0.0.0.0/0 → IGW)
   │
   ▼
VPC (10.0.0.0/16)
   └── Public Subnet (10.0.1.0/24)
         └── EC2 Instance (t2.micro, Amazon Linux 2023)
               ├── Security Group
               │     ├── Inbound: TCP 80  from 0.0.0.0/0   (public web access)
               │     ├── Inbound: TCP 22  from <admin IP>/32 (restricted SSH)
               │     └── Outbound: all traffic (package installs/updates)
               ├── Encrypted root volume (30 GB, gp3)
               └── IMDSv2 required (instance metadata hardening)

VPC Flow Logs ──► CloudWatch Log Group ──► encrypted with a customer-managed KMS key
                                            (30-day retention)
```

**Network lockdown:** The VPC and subnet are fully private by default; only two inbound paths exist — HTTP (80) open to the internet by design (it's a public web server) and SSH (22) restricted to a single administrator IP. All other inbound traffic is implicitly denied.

**IAM least privilege:** The Flow Logs IAM role can only write to its one specific CloudWatch Log Group (scoped by ARN), not to logging resources account-wide.

**Encryption:** The root EBS volume and the CloudWatch Log Group are both encrypted — the log group with a customer-managed KMS key rather than an AWS-managed default.

**Auditability:** VPC Flow Logs capture all accepted and rejected traffic in and out of the VPC, retained for 30 days for later review.

## Repository Structure

```
.
├── main.tf                          # All infrastructure resources
├── variables.tf                     # Input variables
├── .github/workflows/
│   └── security-scan.yml            # tfsec CI pipeline
└── README.md
```
## 🎥 Video Demos

### Secure Automated Web Architecture explanation

This video explains all pipeline from scratch to deploy

<p align="center">
  <a href="https://www.youtube.com/watch?v=4dnu3NGmRkw">
    <img
      src="https://img.youtube.com/vi/4dnu3NGmRkw/maxresdefault.jpg"
      alt="Secure Automated Web Architecture"
      width="85%"
    >
  </a>
</p>

<p align="center">
  <a href="https://www.youtube.com/watch?v=4dnu3NGmRkw">
     
## Prerequisites

- An AWS account with programmatic (CLI) access configured
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [AWS CLI](https://aws.amazon.com/cli/), authenticated (`aws configure`)
- Git

## Setup & Deployment

```bash
# 1. Clone the repository
git clone https://github.com/<your-username>/TKH-Final-Capstone.git
cd TKH-Final-Capstone

# 2. Initialize Terraform (downloads the AWS provider)
terraform init

# 3. Preview the changes Terraform will make
terraform plan

# 4. Apply — provisions the VPC, EC2 instance, IAM, KMS, and logging
terraform apply -auto-approve
```

After `apply` finishes, find the instance's public IP in the AWS EC2 Console (or in Terraform's output), and visit it in a browser to confirm the web server is live:

```
http://<public-ip>
```

> Note: type the `http://` prefix explicitly — some browsers default to HTTPS on a bare IP address, which this project doesn't serve, and will appear to hang.

### Tear down

To avoid ongoing AWS charges once you're done:

```bash
terraform destroy -auto-approve
```

## CI/CD Pipeline — DevSecOps Quality Gate

Defined in `.github/workflows/security-scan.yml`, this pipeline runs automatically on every push to `main`:

| Step | Purpose |
|---|---|
| Checkout code | Pulls the repository into the runner |
| Run tfsec | Statically scans all `.tf` files for security misconfigurations |

The scan runs with **`--soft-fail=false`**, meaning any unresolved finding fails the build and blocks the pipeline — it's a hard gate, not just a warning. Results are also uploaded as a downloadable build artifact (`results.json`) for review.

### Documented exceptions

Two tfsec findings are deliberately suppressed with inline `#tfsec:ignore` comments, because they are intentional design decisions rather than bugs:

- **`aws-ec2-no-public-ingress-sgr`** — port 80 is meant to be open to the internet; this is a public web server.
- **`aws-ec2-no-public-egress-sgr`** — outbound access is required for `yum` package installs on boot.

A third finding (`aws-iam-no-policy-wildcards`, flagged on the Flow Logs IAM policy) was investigated and found to be a **false positive**: the policy is correctly scoped to one CloudWatch Log Group using the AWS-required `:*` suffix (needed to reference that group's log streams), which tfsec's wildcard check can't distinguish from a true wildcard. This is also suppressed with a documented `#tfsec:ignore` and a comment explaining why.

## Security Considerations

- SSH access is restricted to a single IP — update the `cidr_blocks` in `ssh_inbound` if your IP changes.
- The EC2 instance has no SSH key pair (`key_name`) configured by default; add one if you need direct shell access.
- All findings suppressed by tfsec are documented above with justification — nothing is silently ignored.

## About the Author

**Sok Leng Chan** is a Phase 2 Cybersecurity Fellow at the TKH Innovation Fellowship, transitioning into cybersecurity from a background in Math, Economics, and Accounting education, plus full-stack development. This capstone is part of an ongoing portfolio documenting hands-on cloud security and DevSecOps work.

- 🔗 [linkedin.com/in/sok-chan](https://linkedin.com/in/sok-chan)
- 💻 [github.com/slcha25](https://github.com/slcha25)
