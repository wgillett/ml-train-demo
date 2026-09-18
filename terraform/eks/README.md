# eks

VPC + EKS cluster + CPU-only managed node group (CLAUDE.md Step 6,
stretch goal). Uses the community `terraform-aws-modules/vpc` and
`terraform-aws-modules/eks` modules rather than hand-rolled resources —
standard practice for this, and far less code/risk than wiring up
subnets, route tables, and cluster/node IAM roles by hand.

Deferred (per CLAUDE.md, all require real AWS and aren't exercised
locally): GPU node group, IRSA, Argo CD, S3/Arrow data path,
Prometheus/Grafana.

## Cost if applied

Nothing here is free once `apply`'d — unlike `terraform/bootstrap`
(IAM + a small ECR repo), this provisions hourly-billed infrastructure
that keeps costing money until destroyed, whether or not it's in use:

| Resource | Approx. cost |
|---|---|
| EKS control plane (standard support) | ~$0.10/hr (~$73/mo) |
| NAT gateway (single, shared) | ~$0.045/hr + data processing (~$32+/mo) |
| 1x t3.medium node | ~$0.04/hr (~$30/mo) |
| 1x g4dn.xlarge GPU node — only while scaled up | ~$0.53/hr (~$380/mo) |

If `var.cluster_version` falls out of AWS's *standard* support window,
EKS silently switches to "extended support" pricing — an **extra
~$0.60/hr per cluster**, roughly 6x the control plane's base cost. Check
the current EKS Kubernetes version support status before applying, not
just whether a given version number is accepted.

Call it **~$3-4/day** while it's up (standard support), plus a few cents
for CloudWatch Logs from the audit trail below — or **~$17/day with the
GPU node scaled up**, which is why that group defaults to zero nodes.
Kept as cheap as reasonably possible otherwise: single shared NAT (not
one per AZ), one small CPU node, no customer-managed KMS key for secret
encryption.

**If you do apply this, tear it down the same session**
(`terraform destroy`) rather than leaving it running between demo
sessions — nothing about this cluster benefits from staying up
unattended.

## Plan-only workflow (current default)

```sh
cd terraform/eks
terraform init
terraform plan
```

`plan` costs nothing and needs no destructive follow-up — it's a
read-only look at what *would* be created. This is the intended stopping
point per CLAUDE.md unless AWS budget/time allows going further.

## Security notes

- **The EKS API endpoint is public but CIDR-restricted.** By default the
  module would open it to `0.0.0.0/0`; `cluster_endpoint_public_access_cidrs`
  is a required variable (no default) specifically so this can never
  apply as world-open. Set it to your own IP before applying:
  ```sh
  echo 'cluster_endpoint_public_access_cidrs = ["'"$(curl -s https://checkip.amazonaws.com)"'/32"]' > terraform.tfvars
  ```
  (`terraform.tfvars` is gitignored — never commit your IP.) Reaching the
  endpoint still requires valid IAM credentials either way; this just
  stops unauthenticated internet hosts from connecting to it at all.
- **Control-plane audit logging is on** (`api`, `audit`, `authenticator`
  log types → CloudWatch, 7-day retention) — the security-relevant
  subset, omitting the higher-volume `controllerManager`/`scheduler`
  logs to keep the small added cost down.
- `enable_cluster_creator_admin_permissions = true` means whoever applies
  this (the `ml-train-demo-admin` IAM user) gets Kubernetes cluster-admin
  automatically. That user's AWS credentials are therefore also a
  Kubernetes cluster-admin credential — keep MFA on it and treat the
  access key accordingly.

## GPU node group

A second managed node group, `gpu` (`g4dn.xlarge`, `AL2023_x86_64_NVIDIA`
AMI, tainted `nvidia.com/gpu=true:NoSchedule`), exists alongside the CPU
one but is sized to **0 nodes by default** — it costs nothing until a
demo actually needs it. Full GPU walkthrough in the top-level README
("GPU on EKS"); the node-group-specific gotchas:

- **Quota.** Personal/new accounts commonly have a zero quota for
  "Running On-Demand G and VT instances" (`L-DB2E81BA`), in which case
  the node group silently never scales up. Check before applying:
  ```sh
  aws service-quotas get-service-quota --service-code ec2 --quota-code L-DB2E81BA --query Quota.Value
  ```
  Requesting an increase is a support ticket that can take hours to
  days.
- **`desired_size` is only honored at creation.** The eks module ignores
  later changes to it (so it doesn't fight autoscalers). Either apply
  fresh with `-var gpu_node_desired_size=1`, or scale an existing group
  directly:
  ```sh
  aws eks update-nodegroup-config --cluster-name ml-train-demo --nodegroup-name gpu \
    --scaling-config desiredSize=1
  ```
- **Driver / CUDA compatibility.** The image uses the CUDA 12.6 torch
  build specifically because the AMI's NVIDIA driver version isn't
  something to verify offline, and a cu130 build needs a ≥ 580 driver.
  If a future AMI ships an older driver than 12.6 needs, the job fails
  at runtime with a "driver version is insufficient" error — that's the
  signal to check the AMI's driver, not the code.
- **GPU architecture.** `g4dn` is a T4 (compute capability 7.5), the
  cheapest common choice. If a future torch build drops sm_75 kernels,
  `g6.xlarge` (L4, ~$0.80/hr) is the next step up.
- **Root disk is 50 GB** (not the 20 GB default) — the CUDA image is
  several GB uncompressed on top of the AMI's own driver stack.

## If applying

```sh
terraform apply
aws eks update-kubeconfig --region us-east-1 --name ml-train-demo
kubectl get nodes
# ... demonstrate whatever's needed ...
terraform destroy
```

Role names (`ml-train-demo-eks-cluster`, `ml-train-demo-eks-node`) and
the permissions boundary are set explicitly to match what
`terraform/bootstrap`'s `ml-train-demo-admin` IAM policy allows it to
create — see the `ScopedRoleCreate`/`ScopedRoleManagement` statements in
`terraform/bootstrap/iam.tf`. If `apply` fails with an IAM `AccessDenied`
anyway, it's almost certainly the same class of gap encountered while
bootstrapping the CI role — check what specific action was denied and
add it there the same way.
