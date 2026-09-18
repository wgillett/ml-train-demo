# ml-train-demo

Minimal ML training demo built as a vehicle for exercising the
infra/MLOps platform seam — Terraform, Kubernetes, GitOps-style
orchestration, CI, containerized ML workloads. The training script
itself is intentionally trivial (see [Training job](#training-job));
the point is the platform around it, not the model.

See `RUNBOOK.md` for how to reproduce everything locally, known gaps,
and troubleshooting notes from things that broke while building this.

## Status

- [x] Step 1 — local `kind` cluster
- [x] Step 2 — containerized training job (CPU-only)
- [x] Step 3 — training job on local Kubernetes
- [x] Step 4 — Argo Workflows (local)
- [x] Step 5 — CI image build/push
- [x] Step 6 — Terraform for EKS (stretch; applied once, verified, destroyed — not left running)
- [ ] Post-day-1 — GPU training job on an EKS GPU node group (branch `gpu`: code complete, pending a live run)

## Architecture

```
Local (kind)
  Argo Workflow -> Job Pod -> container
                              (CPU-only PyTorch, synthetic data)

GitHub
  push to main -> GitHub Actions (ci.yml) -> OIDC AssumeRoleWithWebIdentity -+
                                                                              |
AWS                                                                          v
  IAM: bootstrap user, CI role, OIDC provider  (terraform/bootstrap)
  ECR: ml-train-demo image repo                (image pushed by CI)
  VPC + EKS + CPU node group                   (terraform/eks — applied +
                                                 destroyed per demo, never
                                                 left running; cost notes in
                                                 terraform/eks/README.md)
    + GPU node group, scale-to-zero            (g4dn.xlarge, EKS NVIDIA AMI,
      + NVIDIA device plugin                     tainted; k8s/gpu/)
      -> GPU training Job                       (same image, TORCH_VARIANT=gpu)
```

Explicitly deferred (require real AWS, not exercised here — see
`CLAUDE.md` for the full list): multi-node DDP training, IRSA, Argo CD
GitOps deploy, S3/Arrow data path, Prometheus/Grafana.

## Local cluster

Bootstrapped with [kind](https://kind.sigs.k8s.io/):

```sh
kind create cluster
kubectl get nodes
```

Requires Docker Desktop (or another Docker-compatible daemon) running first.

## Training job

Minimal CPU-only PyTorch training loop, fits a small MLP to synthetic
linear-regression data and logs loss per epoch to stdout. Not a real ML
workload — a vehicle for exercising the container/k8s/Argo platform.

```sh
uv run train                       # local
docker build -t ml-train-demo .
docker run --rm ml-train-demo      # containerized
```

`torch` comes from one of two mutually exclusive dependency groups:
`cpu` (the default — CPU-only wheels, so the local image doesn't pull in
CUDA/NVIDIA dependencies it can't use) or `gpu` (CUDA 12.6 build). The
Dockerfile's `TORCH_VARIANT` build arg picks one; `docker build .` is
the CPU image, `--build-arg TORCH_VARIANT=gpu` the GPU one (see
[GPU on EKS](#gpu-on-eks)). The script itself is device-agnostic and
logs which it got: `device=cpu device_name='cpu'` vs
`device=cuda device_name='Tesla T4'`.

## Running on local Kubernetes

```sh
docker build -t ml-train-demo:local .
kind load docker-image ml-train-demo:local
kubectl apply -f k8s/training-job.yaml
kubectl logs job/ml-train-demo
kubectl delete -f k8s/training-job.yaml
```

`kind` runs its own containerd, separate from the host Docker image store,
so a locally built image must be loaded into the cluster with
`kind load docker-image` before a `Job` can reference it.

## Running as an Argo Workflow

The `k8s/training-job.yaml` `Job` is also expressed as a single-step Argo
`Workflow` (`k8s/training-workflow.yaml`) — same container, orchestrated
by Argo instead of the plain Job controller.

Install Argo Workflows (quick-start, minimal):

```sh
kubectl create namespace argo
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.6.5/quick-start-minimal.yaml
```

The quick-start bundle ships a demo MinIO artifact store and httpbin
deployment that aren't needed here and aren't reliably schedulable on a
minimal `kind` node; remove them and the default artifact-repository
config (which forces log archiving to that MinIO) so workflows don't
hang waiting for it:

```sh
kubectl -n argo delete configmap artifact-repositories
kubectl -n argo delete deploy/minio deploy/httpbin service/minio service/httpbin \
  secret/my-minio-cred secret/my-httpbin-cred
```

Run the workflow:

```sh
docker build -t ml-train-demo:local .
kind load docker-image ml-train-demo:local
kubectl create -f k8s/training-workflow.yaml
kubectl -n argo get wf
kubectl -n argo logs -l workflows.argoproj.io/workflow=<workflow-name> -c main
```

Note: the container's `command` is specified explicitly in the workflow
template — Argo's executor otherwise tries to look up the entrypoint by
pulling the image from Docker Hub, which fails for a local-only image.

## AWS bootstrap (Terraform)

`terraform/bootstrap` provisions the AWS-side prerequisites for CI/EKS: a
least-privilege personal IAM user, the ECR repo for the training image,
the GitHub OIDC provider, and the IAM role GitHub Actions assumes to push
images (scoped to `push` on `main` in this one repo, permitted only to
push to this one ECR repo, capped by a `PowerUserAccess` permissions
boundary). See `terraform/bootstrap/README.md` for first-apply
instructions (it needs an initial admin credential, since Terraform can't
create its own).

Outputs (ECR URL, OIDC/role ARNs, IAM user name) are available via
`terraform output` in that directory rather than copied here, so this
stays correct as the account evolves. The values the CI workflow needs
are set as GitHub repo variables (`ECR_REPOSITORY_URL`,
`AWS_GITHUB_ACTIONS_ROLE_ARN`).

## CI (GitHub Actions → ECR)

`.github/workflows/ci.yml` builds the training image and pushes it to
ECR on every push to `main`, tagged by commit SHA. Authenticates via
OIDC (`aws-actions/configure-aws-credentials`, assuming the role from
`terraform/bootstrap`) — no static AWS keys stored in GitHub.

## EKS (Terraform, stretch)

`terraform/eks` provisions a VPC + EKS cluster + CPU-only managed node
group, using the `terraform-aws-modules/vpc` and `.../eks` community
modules. Unlike `terraform/bootstrap`, this is hourly-billed
infrastructure — **`terraform plan` is the default, cost-free stopping
point**:

```sh
cd terraform/eks
terraform init
terraform plan
```

See `terraform/eks/README.md` for the full cost breakdown (~$3-4/day if
applied) and the apply-then-destroy-same-session workflow if you do want
to see it actually running. This repo's own history: applied once,
verified with `kubectl get nodes`, destroyed immediately after — not
left running between sessions.

## GPU on EKS

The same training script on a single NVIDIA GPU. Everything local stays
CPU-only and unchanged; the GPU path is purely additive:

- **Image**: `--build-arg TORCH_VARIANT=gpu` on the same Dockerfile
  (CUDA 12.6 torch, ~3.8 GB vs ~1.2 GB). Built on demand, not on every
  push: the CI workflow's "Run workflow" button (`workflow_dispatch`,
  run from `main` — the CI role's trust is pinned there) pushes
  `gpu-<sha>` to ECR.
- **Node group**: `gpu` in `terraform/eks` — `g4dn.xlarge` (one T4),
  the EKS NVIDIA AMI (driver + container toolkit included), tainted
  `nvidia.com/gpu=true:NoSchedule`, scale-to-zero by default.
- **Device plugin**: `k8s/gpu/nvidia-device-plugin.yaml` (vendored
  v0.20.0, pinned to the GPU node group) advertises `nvidia.com/gpu`
  to the scheduler; `k8s/gpu/training-job.yaml` requests one.

Before anything else, check the account's quota for G instances — new
and personal accounts commonly have it at **zero**, and the node group
would just never come up:

```sh
aws service-quotas get-service-quota --service-code ec2 --quota-code L-DB2E81BA \
  --query Quota.Value   # in vCPUs; g4dn.xlarge needs 4
```

Then, with the GPU node the hourly rate roughly quadruples (see
`terraform/eks/README.md`), so same-session teardown matters more:

```sh
cd terraform/eks
terraform apply -var gpu_node_desired_size=1
aws eks update-kubeconfig --region us-east-1 --name ml-train-demo
kubectl apply -f ../../k8s/gpu/nvidia-device-plugin.yaml
kubectl get nodes -L accelerator                                   # gpu node Ready
kubectl get node -l accelerator=nvidia-gpu -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}'   # 1

ECR_IMAGE="$(cd ../bootstrap && terraform output -raw ecr_repository_url):gpu-<sha>"
sed "s|ECR_IMAGE|$ECR_IMAGE|" ../../k8s/gpu/training-job.yaml | kubectl apply -f -
kubectl logs job/ml-train-demo-gpu -f     # device=cuda device_name='Tesla T4'
terraform destroy
```

Building the GPU image locally instead of via CI works too, but it must
target the nodes' architecture (an Apple-silicon Mac builds arm64 by
default): `docker build --platform linux/amd64 --build-arg
TORCH_VARIANT=gpu -t <ecr-url>:gpu-local .`, then
`aws ecr get-login-password | docker login --username AWS
--password-stdin <ecr-url>` and push.
