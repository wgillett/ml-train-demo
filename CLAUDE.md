# CLAUDE.md

## Project Purpose

Demonstration project for a Senior Platform Engineer, ML Infrastructure application (Deep Genomics). Goal: show competence across the infra/MLOps seam described in that JD — Terraform, Kubernetes (EKS), GitOps, containerized ML workloads, observability, documentation discipline. Not a research project; the ML workload is a vehicle for exercising the platform.

Time budget: ~1 day for initial scope. Optimize for a working, demonstrable slice over a complete system. Prioritize local testability; anything requiring AWS GPU capacity is deferred and clearly marked.

## Target Architecture (end state, not day 1)

- **IaC**: Terraform — VPC, EKS cluster, managed node group (GPU node group added later)
- **Orchestration**: Argo Workflows (training job), Argo CD (GitOps deploy)
- **CI**: GitHub Actions — build/push container image
- **Workload**: containerized PyTorch script, DDP-capable, CPU-only fallback mode
- **Data**: S3 + Parquet/Arrow for input data access pattern
- **Observability**: Prometheus + Grafana (job status, resource utilization)
- **Docs**: README (architecture diagram) + RUNBOOK.md (operational/incident notes)

## Guiding Principles

1. **Local-first**: use `kind` or `minikube` for every component that doesn't strictly require AWS. Only EKS provisioning and GPU scheduling require real AWS.
2. **Incremental commits**: each step below should be its own commit with a working, demonstrable state. Do not let scope creep merge steps.
3. **Document as you go**: every step gets a short README/runbook note before moving to the next. This is itself a signal for the application — don't defer it to "later."
4. **CPU-only is an acceptable stopping point.** GPU scheduling is a stretch goal, not a blocker to a demonstrable result.

## Day 1 Incremental Plan

Work top to bottom. Stop at whatever step you reach — each is a coherent checkpoint, not a partial state.

### Step 1 — Repo skeleton + local cluster (30–45 min)
- Init repo, `.gitignore`, base README stub.
- Spin up `kind` cluster locally. Confirm `kubectl get nodes` works.
- Commit: "local kind cluster bootstrap"

### Step 2 — Containerized training job, CPU-only (45–60 min)
- Minimal PyTorch script: synthetic data, single-process training loop, logs metrics to stdout.
- Dockerfile. Build and run locally (`docker run`), confirm it completes.
- Commit: "CPU-only training container, runs locally"

### Step 3 — Run the job on local Kubernetes (30–45 min)
- Kubernetes `Job` manifest running the container on `kind`.
- Confirm via `kubectl logs`.
- Commit: "training job running on local k8s"

### Step 4 — Argo Workflows on local cluster (45–60 min)
- Install Argo Workflows into `kind`.
- Convert the `Job` into an Argo `Workflow` (single-step is fine for now).
- Commit: "training job orchestrated via Argo Workflows (local)"

### Step 5 — CI pipeline (30–45 min)
- GitHub Actions: build image on push, push to a registry (GHCR is simplest, no AWS dependency).
- Commit: "CI builds and pushes training image"

### Step 6 — Terraform for EKS (60–90 min, stretch)
- Terraform: VPC + EKS cluster, CPU-only managed node group. Do not apply unless AWS budget/time allows — validate with `terraform plan` if applying is out of scope for the day.
- Document in README whether this was actually applied or only plan-validated.
- Commit: "Terraform for EKS cluster (plan-validated / applied)"

### Step 7 — Documentation pass (30 min, do this regardless of how far Steps 1–6 got)
- README: what exists, what doesn't, architecture diagram (even hand-drawn/ASCII is fine).
- RUNBOOK.md: how to reproduce locally, known gaps, what "done" would look like (GPU node group, Argo CD, S3/Arrow data path, observability stack).
- Commit: "docs: status and runbook"

## Explicitly Deferred (post-day-1, requires AWS)

- GPU node group + device plugin + driver DaemonSet on EKS (cannot test locally — no local GPU)
- Multi-node DDP training on real GPUs
- Argo CD GitOps deploy against the EKS cluster
- S3 + Arrow data-access pattern (can be stubbed with local files at day-1 scope)
- Prometheus/Grafana observability stack
- IRSA setup for pod-level AWS permissions

State this list explicitly in the README rather than implying the project is more complete than it is.

## Conventions

- Commit messages: short, imperative, one checkpoint each.
- Every step ends with something runnable — no "half-wired" commits.
- Prefer boring, readable code over cleverness; this project is a demonstration of platform judgment, not novel ML work.

## Notes on the GCP → AWS Substitution

Original plan targeted GKE; this project targets EKS due to existing AWS familiarity and time constraints. Terraform, Kubernetes, Argo, and Helm patterns are cloud-agnostic. Known AWS-specific deltas to call out in README:
- IRSA replaces GCP Workload Identity for pod IAM permissions.
- GPU node groups on EKS use managed node groups + GPU AMI + device plugin, rather than GKE's more turnkey GPU node pool support.
- S3 replaces GCS for object storage.
