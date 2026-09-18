# RUNBOOK

Operational notes: how to reproduce this project locally, what's
deferred and why, and troubleshooting notes from things that actually
broke while building it — kept here rather than fixed silently, since
they're the kind of thing that'll happen again on the next AWS-facing
project.

## Reproduce locally

Everything except the AWS/Terraform sections runs with no AWS account
needed.

### 1. Local cluster

```sh
kind create cluster
kubectl get nodes
```

Requires Docker Desktop (or another Docker-compatible daemon) running.

### 2. Training container

```sh
uv run train                       # local, no container
docker build -t ml-train-demo:local .
docker run --rm ml-train-demo:local
```

### 3. On local Kubernetes, as a plain Job

```sh
kind load docker-image ml-train-demo:local
kubectl apply -f k8s/training-job.yaml
kubectl logs job/ml-train-demo
kubectl delete -f k8s/training-job.yaml
```

`kind` runs its own containerd, separate from the host Docker image
store — a locally built image has to be `kind load docker-image`'d in
before a `Job`/`Workflow` can reference it.

### 4. On local Kubernetes, as an Argo Workflow

```sh
kubectl create namespace argo
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.6.5/quick-start-minimal.yaml

# Remove quick-start's demo MinIO/httpbin and the default
# artifact-repository config — not needed here, and archiveLogs:true
# against a MinIO that doesn't reliably schedule on a minimal kind node
# makes workflows hang. See "Argo Workflow stuck on log archiving" below.
kubectl -n argo delete configmap artifact-repositories
kubectl -n argo delete deploy/minio deploy/httpbin service/minio service/httpbin \
  secret/my-minio-cred secret/my-httpbin-cred

kind load docker-image ml-train-demo:local
kubectl create -f k8s/training-workflow.yaml
kubectl -n argo get wf
kubectl -n argo logs -l workflows.argoproj.io/workflow=<workflow-name> -c main
```

### 5. AWS bootstrap (Terraform)

Only needed once per AWS account. See `terraform/bootstrap/README.md`
for the full first-apply flow (it needs a temporary admin credential,
since Terraform can't create its own). Creates: a least-privilege
personal IAM user, the ECR repo, the GitHub OIDC provider, and the CI
role GitHub Actions assumes. All either free or a few cents/month —
nothing here is hourly-billed.

### 6. CI

Push to `main` — `.github/workflows/ci.yml` builds and pushes the image
to ECR automatically, authenticated via OIDC (no static AWS keys in
GitHub). Nothing to run manually.

### 7. EKS (stretch, costs real money if applied)

```sh
cd terraform/eks
terraform init
terraform plan     # read-only, costs nothing — the default stopping point
```

If actually applying: control plane + NAT gateway + one node run
**~$3-4/day** while up (see `terraform/eks/README.md` for the full
breakdown, including a nasty surprise about EKS "extended support"
pricing — see below). `terraform destroy` in the same session; don't
leave it running between demo sessions.

## What "done" would look like

Everything below requires real AWS and isn't exercised by this repo —
stubbed, plan-validated, or left as a documented gap instead:

- **GPU node group** — managed node group on a GPU AMI + NVIDIA device
  plugin DaemonSet. No local GPU to test against.
- **Multi-node DDP training** — the training script is single-process;
  real distributed data-parallel training needs actual GPU nodes to be
  worth exercising.
- **IRSA** — pod-level AWS IAM permissions via a cluster OIDC provider.
  Deliberately disabled in `terraform/eks` (`enable_irsa = false`) since
  nothing in this repo needs AWS API access from inside a pod yet.
- **Argo CD GitOps deploy** — nothing here is deployed by Argo CD; the
  Argo *Workflow* (training job orchestration) is a different piece
  from Argo *CD* (deploy automation), and only the former is built.
- **S3 + Arrow data path** — training data is synthetic, generated
  in-process. A real data path would read Parquet/Arrow from S3 instead.
- **Prometheus/Grafana** — no observability stack; job status/resource
  usage is read via `kubectl`/`kubectl logs` only.

## Troubleshooting notes (things that actually broke)

### IAM permissions boundary condition silently denied unrelated actions

`terraform/bootstrap/iam.tf`'s bootstrap-user policy originally combined
`iam:CreateRole` with `GetRole`/`AttachRolePolicy`/etc. in one statement,
guarded by an `iam:PermissionsBoundary` condition. That condition key
only exists in `CreateRole`'s request context — on every other action in
that statement, the missing key made the condition evaluate false and
silently denied them too, not just `CreateRole`. Fix: split any
statement with a condition scoped to one specific action's request
context into its own statement (see `ScopedRoleCreate` vs
`ScopedRoleManagement`, and the same pattern later for
`EksNodegroupServiceLinkedRoleCreate` vs `...Read`).

### GitHub OIDC `sub` claim format changed

The classic `repo:org/repo:ref:refs/heads/branch` trust-policy match
stopped working — GitHub's `sub` claim now embeds immutable numeric
owner/repo IDs (`repo:org@123/repo@456:ref:...`). Matching individual
`repository`/`ref` claims instead worked logically but was rejected
outright: AWS requires a GitHub OIDC trust policy to condition on `sub`
or `job_workflow_ref` specifically. Used `job_workflow_ref` — it pins
trust to one exact workflow file *and* branch, which is what we wanted
anyway. Diagnosed by temporarily decoding the OIDC token's payload in
CI (never the raw token) — see git history on `.github/workflows/ci.yml`
for the debug step, since removed.

### EKS: service-linked role check needs its own IAM grant

Creating the first managed node group in an account, EKS checks whether
`AWSServiceRoleForAmazonEKSNodegroup` (an AWS-owned service-linked role,
not one of ours) already exists — that check needs `iam:GetRole` on that
specific role, outside anything a `ml-train-demo-*`-scoped policy
covers. Needed a narrow, separately-scoped grant
(`EksNodegroupServiceLinkedRoleRead`/`...Create` in `iam.tf`).

### EKS minor version upgrades are sequential only

Tried bumping `cluster_version` from 1.31 to 1.34 in one `apply` against
an already-created cluster — rejected outright
(`Unsupported Kubernetes minor version update from 1.31 to 1.34`). EKS
only allows one minor version at a time (1.31→1.32→1.33→1.34). Not an
issue for a *fresh* cluster create (goes straight to the target
version), only for upgrading an existing one.

### EKS "extended support" pricing

A cluster running a Kubernetes minor version past AWS's *standard*
support window is silently billed an extra **~$0.60/hr** ("extended
support"), on top of the normal ~$0.10/hr control plane cost — roughly
6x the base price. `terraform/eks`'s `cluster_version` default is kept
current for this reason; check AWS's current EKS version support status
before applying, not just whether a version number is accepted.

### Argo Workflow stuck trying to archive logs to MinIO

The Argo Workflows quick-start bundle wires up a demo MinIO as the
default artifact repository with `archiveLogs: true`. On a minimal
`kind` node, that MinIO pod doesn't reliably schedule, so any workflow
hangs waiting to archive its logs to it. Removed the demo MinIO/httpbin
and the `artifact-repositories` configmap entirely — not needed for a
workflow that has no real artifacts, just log output already visible
via `kubectl logs`.

### Argo executor can't infer a local-only image's entrypoint

Argo's emissary executor normally looks up a container's entrypoint by
pulling the image's manifest — for a `kind`-local image with no remote
registry, that pull fails (tries Docker Hub, gets `UNAUTHORIZED`). Fix:
specify `command` explicitly in the Workflow template instead of relying
on the image's built-in entrypoint.
