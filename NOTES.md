# eks-arc: cluster notes

Training project: a Terraform-managed EKS cluster running GitHub Actions runners (ARC) with Karpenter node scaling. Not for production use.

- Repo: https://github.com/israserg/eks-arc
- AWS: new AWS experience, FREE plan ($100 credits), default profile, selected Region **eu-north-1**
- Cluster: `arc-training`, Kubernetes 1.37
- Status: everything applied and tested (small and medium runner tiers, build and push to ECR).

## How to run Terraform

```bash
cd ~/work/eks-arc
source scripts/run.sh                     # sets AWS_PROFILE=tf, region, and checks the identity
export TF_VAR_github_token='<your PAT>'   # never commit it
terraform plan -no-color -out=tfplan 2>&1 | tee plan.log
terraform apply -no-color tfplan 2>&1 | tee apply.log
```

- `aws login` gives 15-minute STS credentials. Terraform reads them through the `[profile tf]` entry in `~/.aws/config`, which uses `credential_process` to call `aws configure export-credentials`. Always use `AWS_PROFILE=tf` and unset exported `AWS_*` variables (`scripts/run.sh` does both).
- If you see `ExpiredToken` or "refreshed credentials are still expired", run `aws login --profile default` again.
- State: S3 bucket `tfstate-eks-34b96d0a`, key `eks-arc/terraform.tfstate`, native locking (`use_lockfile`). State is written during apply, not only at the end.
- If an apply dies with a state upload error, Terraform leaves `errored.tfstate`. Recover it with `terraform state push errored.tfstate`.
- `terraform destroy` when you are done. The NAT gateway, the EKS control plane, and the nodes cost credits while they exist.

## Layout

```
Internet
  |
GitHub  <--long poll--  ARC listener pods (arc-systems)
                                 |
VPC 2 AZs, public + private subnets, one NAT gateway
  |
EKS control plane (managed)
  |
  +-- System node (managed node group "training", 1 x t3.small, fixed)
  |     CoreDNS, kube-proxy, vpc-cni, pod-identity-agent,
  |     Karpenter controller, ARC controller, ARC listeners
  |
  +-- Karpenter NodePool "runners" (small tier)     tainted dedicated=runners
  |     t3.small / c7i-flex.large / m7i-flex.large, 20 GiB disk (default)
  |     runs pods of scale set "arc-runners"
  |
  +-- Karpenter NodePool "medium" (medium tier)     tainted dedicated=runners
        c7i-flex.large / m7i-flex.large, 50 GiB gp3 disk
        runs pods of scale set "arc-medium"
```

## Terraform files

| File | What it builds |
|---|---|
| `versions.tf` | Terraform and provider versions, S3 backend |
| `providers.tf` | aws, kubernetes, kubectl (alekc), helm providers (EKS token via `aws eks get-token`) |
| `variables.tf` | Region, cluster name, instance types, runner limits, GitHub URL and token |
| `vpc.tf` | VPC, subnets, single NAT. Private subnets carry the `karpenter.sh/discovery` tag |
| `eks.tf` | EKS cluster, add-ons, the fixed system node group |
| `karpenter.tf` | Karpenter IAM and queue, Helm release, EC2NodeClass `default`, NodePool `runners` |
| `arc.tf` | ARC controller, `arc-runners` namespace, GitHub secret, scale set `arc-runners`, LimitRange |
| `arc-medium.tf` | EC2NodeClass `medium`, NodePool `medium`, scale set `arc-medium` with explicit pod sizing |
| `ecr.tf` | ECR repo `eks-arc-demo`, IAM role for runner pods, service account `arc-runner`, Pod Identity association |
| `outputs.tf` | Cluster name, endpoint, ECR URL, kubeconfig command |

## Runner tiers

Choose a tier with the `runs-on` label. The label is the Helm release name.

| Label | Pod requests | Node types | Max pods | Disk |
|---|---|---|---|---|
| `arc-runners` | about 0.5 vCPU / 1 GiB (chart default dind, LimitRange 250m/512Mi per container) | t3.small, c7i-flex.large, m7i-flex.large | `runner_max` = 2 | 20 GiB |
| `arc-medium` | about 1.5 vCPU / 3 GiB (dind 1 vCPU / 2 GiB, runner 0.5 vCPU / 1 GiB) | c7i-flex.large, m7i-flex.large | `runner_medium_max` = 2 | 50 GiB |

- Both scale sets use `minRunners = 0`. A runner pod exists only while a job is queued or running, and each runner takes one job (ephemeral).
- Both use Docker-in-Docker, so jobs can run `docker build`, `run`, and `push`.
- Cold start for a job (new node plus image pulls) is typically about 1.5 to 3 minutes. It was not measured precisely.
- Empty runner nodes are removed about 1 minute after the last pod finishes (`consolidateAfter: 1m`, `WhenEmpty`). Nodes also expire after 24 hours.
- Each NodePool has a safety cap of 4 vCPU in total.

## Isolation: taint and node selector

- Runner nodes carry the taint `dedicated=runners:NoSchedule`. Only runner pods, which tolerate it, can land there.
- Without the taint, CoreDNS or the ARC listener could land on a runner node. `WhenEmpty` would then never remove that node.
- System pods stay on the system node. Runner pods are pinned to their own pool by `nodeSelector: karpenter.sh/nodepool=runners` or `=medium`.

## Free plan constraints

- Only Free Tier eligible EC2 types work in eu-north-1: `t3.micro`, `t4g.micro`, `t3.small`, `t4g.small`, `c7i-flex.large` (2 vCPU / 4 GiB), `m7i-flex.large` (2 vCPU / 8 GiB). `t3.medium` is rejected.
- All Regional resources must stay in eu-north-1. No cross-Region resources, no Lambda@Edge.
- If operations suddenly fail with Access Denied, check for a spend limit in AWS Settings > Billing.

## ECR push from runners

- ECR repository: `eks-arc-demo` (immutable tags, scan on push, `force_delete` on destroy).
- Runner pods use the service account `arc-runner` in `arc-runners`. EKS Pod Identity links it to the IAM role `arc-training-arc-runner`, which can push to that repo only.
- No access keys are stored anywhere. Pod Identity provides short-lived credentials.

## Workflows

- `.github/workflows/arc-smoke-test.yml`: runs on both labels (matrix) and prints OS, cgroup limits, tools, `df -h`, and filtered environment variables.
- `.github/workflows/build-push.yml`: on `arc-runners`, builds `app/Dockerfile` (nginx), runs it and checks it with `curl`, then pushes to ECR as `1.0.<run number>-<short sha>`.

## Useful commands

```bash
aws eks update-kubeconfig --name arc-training --region eu-north-1   # also in terraform output kubeconfig_command
k9s                                          # then :nodes, :nodeclaims, :pods
kubectl get nodeclaims                       # nodes Karpenter currently owns
kubectl get pods -A
kubectl delete nodeclaim <name>              # force-remove a stuck Karpenter node
```

## Known sharp edges

- Pasting multiline bash with `\` into the WSL terminal can break. Prefer single-line commands.
- `.terraform.lock.hcl` should be committed. It pins provider versions.
- `github_token` is a personal access token with `repo` scope, which is fine for training only. A GitHub App is the better choice for real use.
- The system node is small (2 GiB). Adding more system workloads, for example ArgoCD, will need a bigger `node_instance_type`, such as `m7i-flex.large`, or a Karpenter node.
