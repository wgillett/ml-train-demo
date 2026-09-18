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

If `var.cluster_version` falls out of AWS's *standard* support window,
EKS silently switches to "extended support" pricing — an **extra
~$0.60/hr per cluster**, roughly 6x the control plane's base cost. Check
the current EKS Kubernetes version support status before applying, not
just whether a given version number is accepted.

Call it **~$3-4/day** while it's up (standard support). Kept as cheap as reasonably
possible: single shared NAT (not one per AZ), one small node, no
customer-managed KMS key for secret encryption, no control-plane log
export to CloudWatch.

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
