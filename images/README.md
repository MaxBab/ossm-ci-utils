# OSSM AI Sandbox Container

A container image providing a safe, isolated environment for running Claude Code skills that interact with external systems (AWS, Kubernetes, GitHub).

> **Why a container?** Skills that execute commands against external tools must not run on the user's local machine with their full credentials and environment. The sandbox container receives only the secrets it explicitly needs, scoped to the session.

---

## Images

| Image | Base | Use case |
|-------|------|----------|
| `Dockerfile.local` | Debian Bookworm Slim | Local development and kind clusters |

Images include: **Claude Code CLI, AWS CLI, kubectl, GitHub CLI, Python 3, jq**.

Note:
For OCP clusters, use the Dockerfile definition in the https://github.com/openshift-eng/ai-helpers/blob/b71c1be628786d3dc4e13d93b6c1ac2d52565838/images/Dockerfile repository.

---

## Build

All build targets are managed via the `Makefile` inside `images/`. Run commands from the `images/` directory.

```bash
# Single-arch build (default: amd64)
make build HUB=quay.io/myorg TAG=v1.0.0

# Build and push (single-arch)
make all HUB=quay.io/myorg TAG=v1.0.0

# Multi-arch build and push (amd64 + arm64)
make multiarch HUB=quay.io/myorg TAG=v1.0.0

# Using podman instead of docker
make all HUB=quay.io/myorg TAG=v1.0.0 CONTAINER_CLI=podman
make multiarch HUB=quay.io/myorg TAG=v1.0.0 CONTAINER_CLI=podman
```

Key variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `HUB` | `quay.io/sail-dev` | Registry + org prefix |
| `TAG` | `latest` | Image tag |
| `ARCH` | `amd64` | Single-arch target (`amd64` or `arm64`) |
| `CONTAINER_CLI` | `docker` | Container runtime (`docker` or `podman`) |

---

## Authentication

Claude Code supports two authentication modes. Choose one based on your setup.

### Option A — Direct Anthropic API key

Set `ANTHROPIC_API_KEY` at runtime. Suitable for personal accounts or CI environments with a direct API key.

### Option B — Vertex AI (The current for Red Hat accounts)

Use your gcloud credentials to authenticate via Google Cloud's Vertex AI. Requires `gcloud auth application-default login` on the host beforehand.

Required environment variables:

| Variable | Description |
|----------|-------------|
| `CLAUDE_CODE_USE_VERTEX=1` | Enable Vertex AI integration |
| `CLOUD_ML_REGION` | GCP region (e.g. `us-east5`) |
| `ANTHROPIC_VERTEX_PROJECT_ID` | GCP project ID |

Mount your gcloud credentials read-only into the container:

```bash
-v ~/.config/gcloud:/home/claude/.config/gcloud:ro
```
Note: we still need to request an service account creation specifically for OSSM CI work, to avoid using personal credentials and to have better control over permissions. So, please avoid using personal accounts for this unless you are testing locally or you have clear control over the credentials being used.

---

## Run

### Locally

#### With Anthropic API key

```bash
docker run --rm -it \
  -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
  -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
  -e AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION \
  -v $HOME/.kube:/home/claude/.kube:ro \
  -v $(pwd):/workspace \
  quay.io/sail-dev/ossm-ai-local:latest
```

#### With Vertex AI (Red Hat accounts)

```bash
podman run --rm -it \
  -e CLAUDE_CODE_USE_VERTEX=$CLAUDE_CODE_USE_VERTEX \
  -e CLOUD_ML_REGION=$CLOUD_ML_REGION \
  -e ANTHROPIC_VERTEX_PROJECT_ID=$ANTHROPIC_VERTEX_PROJECT_ID \
  -v ~/.config/gcloud:/home/claude/.config/gcloud:ro \
  -v $(pwd):/workspace \
  quay.io/sail-dev/ossm-ai-local:latest
```

#### Example with podman and Vertex AI:

```bash
podman run --rm -it \
  -e CLAUDE_CODE_USE_VERTEX=$CLAUDE_CODE_USE_VERTEX \
  -e CLOUD_ML_REGION=$CLOUD_ML_REGION \
  -e ANTHROPIC_VERTEX_PROJECT_ID=$ANTHROPIC_VERTEX_PROJECT_ID \
  -v ~/.config/gcloud:/home/claude/.config/gcloud:ro \
  -v $(pwd):/workspace \
  quay.io/frherrer/ossm-ai-local --print "Tell me the context of this repository and the list of skills and claude commands available"
```

The output will be something like:

```
## Repository Context

**ci-utils** - OpenShift Service Mesh (OSSM) Team CI/CD Utilities

This is a **Claude Code skills marketplace** that provides shared utilities to standardize build, test, and deployment pipelines for the OSSM team. The repository contains:

- **Report Portal Integration** - Centralized script for sending JUnit test results
- **Test Configuration** - YAML configs controlling which Istio tests run/skip across CI streams
- **AWS & Prow Scripts** - Standalone tools for resource scanning and metrics collection
- **AI Helpers** - Confidence scoring configs for release validation
- **Claude Code Plugin** - The `ossm-ci` plugin with AI-powered CI utilities
- **Container Images** - Safe, isolated environments for running skills

**Current Branch:** `example-branch` (clean working directory)

---

## Claude Code Skills (Available with `/` prefix)

These are user-invocable skills from the Skill tool:

- **`/update-config`** - Configure Claude Code via settings.json (permissions, env vars, hooks)
- **`/simplify`** - Review changed code for quality, reuse, and efficiency
- **`/loop`** - Run a prompt/command on recurring interval (e.g., `/loop 5m /foo`)
- **`/claude-api`** - Build apps with the Claude API or Anthropic SDK
- **`/help`** - Get help with using Claude Code

---

## OSSM-CI Plugin Commands

Install with: `/plugin install ossm-ci@ci-utils`

### `/ossm-ci:confidence`
Calculates data-driven release confidence score (1–10) for OSSM builds by analyzing Report Portal test results. Determines test scope (FULL/CORE/BASIC), validates matrix coverage, provides GO/NO-GO recommendation. Still under development, but will be a key tool for release validation and risk assessment.
- **Requires:** Report Portal MCP server

### `/ossm-ci:generate-e2e-tests`
Generates production-ready Go E2E tests using BDD Ginkgo from documentation. Validates docs quality (7/10 minimum), extracts hidden tags for retry/timeout logic. Still in early stages, but aims to automate test creation and maintenance from living documentation.
- **Usage:** Run from target project root

### `/ossm-ci:aws-scan`
Inventories AWS resources across all regions. Shows dangling resources and complete inventory in clean tables.
- **Requires:** AWS CLI with valid credentials

### `/ossm-ci:prow-metrics`
Collects Prow CI execution data for OSSM repos (istio, proxy, sail-operator, ztunnel). Shows stats, median times, infrastructure usage, exports TSV.
- **Requires:** `python3` in PATH

---
```

This confirms that the container is running correctly and has access to the expected tools and credentials.

---

## Security model

- **No secrets baked in.** All credentials (API keys, gcloud tokens, AWS keys) are injected at runtime and exist only for the duration of the session.
- **Non-root user** (`claude`, UID 1000, GID 0) — compatible with both OpenShift's random UID policy and standard Kubernetes.
- **Minimal surface.** Only the tools explicitly needed for OSSM CI skills are installed.
- **Read-only kubeconfig.** Mount kubeconfig as `:ro` — the container only needs to read cluster state.
- **Scoped credentials.** Pass only the AWS keys needed for the task (prefer read-only IAM roles).

---

## Tools available inside the container

| Tool | Purpose |
|------|---------|
| `claude` | Claude Code CLI — entry point |
| `aws` | AWS CLI for resource scanning |
| `kubectl` | Kubernetes cluster inspection |
| `gh` | GitHub CLI for PR/issue operations |
| `python3` | Prow metrics script |
| `jq` | JSON processing |
| `aws-scan-audited.sh` | Pre-installed at `/opt/ci-utils/scripts/` and on PATH |
