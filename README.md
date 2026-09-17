# ml-train-demo
Experiment with creating a minimal ML training demo

## Status

- [x] Step 1 — local `kind` cluster
- [ ] Step 2 — containerized training job (CPU-only)
- [ ] Step 3 — training job on local Kubernetes
- [ ] Step 4 — Argo Workflows (local)
- [ ] Step 5 — CI image build/push
- [ ] Step 6 — Terraform for EKS (stretch)

See `CLAUDE.md` for the full plan and explicitly deferred items (GPU node
group, multi-node DDP, Argo CD, S3/Arrow data path, Prometheus/Grafana,
IRSA — all require AWS and are out of scope for the local demo).

## Local cluster

Bootstrapped with [kind](https://kind.sigs.k8s.io/):

```sh
kind create cluster
kubectl get nodes
```

Requires Docker Desktop (or another Docker-compatible daemon) running first.
