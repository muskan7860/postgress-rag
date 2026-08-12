# PostgreSQL RAG Application — GitOps CI/CD Pipeline

A Retrieval-Augmented Generation (RAG) application built with **Streamlit** and **PostgreSQL**, deployed on **MicroK8s** using a full **Jenkins CI → Argo CD GitOps CD** pipeline. Supports both **OpenAI** and **Ollama (self-hosted, local LLM)** as the inference backend.

---

## Table of Contents

1. [Architecture](#architecture)
2. [Tech Stack](#tech-stack)
3. [Repository Structure](#repository-structure)
4. [Prerequisites](#prerequisites)
5. [Local Setup (Run Without Kubernetes)](#local-setup-run-without-kubernetes)
6. [Environment Variables](#environment-variables)
7. [Docker Setup](#docker-setup)
8. [Kubernetes / MicroK8s Setup](#kubernetes--microk8s-setup)
9. [CI — Jenkins Pipeline](#ci--jenkins-pipeline)
10. [CD — Argo CD (GitOps)](#cd--argo-cd-gitops)
11. [Choosing an LLM Backend: OpenAI vs Ollama](#choosing-an-llm-backend-openai-vs-ollama)
12. [Verifying the Deployment](#verifying-the-deployment)
13. [Troubleshooting](#troubleshooting)
14. [Security Notes](#security-notes)

---

## Architecture

```
 GitHub (app repo)                 GitHub (GitOps repo)
        │                                   │
        ▼                                   │
    Jenkins CI                              │
   (build + test)                           │
        │                                   │
        ▼                                   │
   Docker Image                             │
   pushed to registry                       │
        │                                   │
        └──────► updates image tag ─────────┘
                  in GitOps repo
                        │
                        ▼
                    Argo CD
              (watches GitOps repo)
                        │
                        ▼
                    MicroK8s
        ┌───────────────┼────────────────┐
        │               │                │
        ▼               ▼                ▼
  RAG Application   PostgreSQL       Ollama (optional)
   (Streamlit)         16 DB          llama3.2 + nomic-embed-text
        │                                    │
        └───────────── RAG Pipeline ─────────┘
                        │
                        ▼
                  Browser / UI (port 8501)
```

**Flow summary:**
- Developer pushes code to the **application repo**.
- **Jenkins** checks out the code, builds a Docker image, and pushes it to the registry.
- Jenkins (or a follow-up step) updates the image tag in the **GitOps repo**.
- **Argo CD** detects the change in the GitOps repo and syncs it to the **MicroK8s** cluster.
- The app connects to **PostgreSQL** for data and to either **OpenAI** or a **self-hosted Ollama** pod for LLM/embedding inference.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Application | Python 3.12, Streamlit |
| Database | PostgreSQL 16 |
| LLM / Embeddings | OpenAI API (`gpt-4.1-mini`, `text-embedding-3-small`) **or** Ollama (`llama3.2:3b`, `nomic-embed-text`) |
| Containerization | Docker |
| Orchestration | Kubernetes (MicroK8s) |
| CI | Jenkins |
| CD | Argo CD (GitOps) |
| Dependency management | `uv` / `pyproject.toml` / `requirements.txt` |

---

## Repository Structure

This project is split across **two repositories**, which is standard GitOps practice (application code is separated from deployment manifests):

```
postgres-rag/                     # Application repo
├── app.py                        # Streamlit UI + RAG logic
├── main.py                       # Entry point / helper logic
├── pyproject.toml
├── requirements.txt
├── uv.lock
├── Dockerfile
├── Jenkinsfile
├── .env.example
└── README.md

postgres-rag-gitops/               # GitOps / deployment repo
└── k8s/
    ├── namespace.yml
    ├── deployment.yml
    ├── service.yml
    └── argocd-application.yml
```

---

## Prerequisites

Before you begin, make sure you have:

- Python **3.12+**
- Docker
- MicroK8s (or any Kubernetes cluster) with `kubectl` alias `k` configured
- Jenkins installed (in-cluster or external) with a Docker/Kaniko-capable agent
- Argo CD installed on the cluster
- A PostgreSQL instance (in-cluster or external)
- **Either** an OpenAI API key **or** Ollama installed/deployable in the cluster

---

## Local Setup (Run Without Kubernetes)

```bash
# 1. Clone the repo
git clone https://github.com/<your-username>/postgres-rag.git
cd postgres-rag

# 2. Create and activate a virtual environment
python3.12 -m venv .venv
source .venv/bin/activate

# 3. Install dependencies
pip install -r requirements.txt
# (or, if using uv)
uv sync

# 4. Copy environment template and fill in real values
cp .env.example .env

# 5. Run the app
streamlit run app.py --server.address=0.0.0.0 --server.port=8501
```

The app will be available at `http://localhost:8501`.

---

## Environment Variables

Create your local `.env` from `.env.example`. **Never commit `.env` with real values** — only `.env.example` (with blanks) should be committed.

`.env.example`:
```env
# Database configuration
DB_HOST=
DB_PORT=5432
DB_NAME=
DB_USER=
DB_PASSWORD=
DB_SCHEMA=public

# OpenAI API key
# Leave empty if the application accepts the key through the UI,
# or if you are using the Ollama backend instead.
OPENAI_API_KEY=
```

Local `.env` example (values for your own machine only):
```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=postgres_rag
DB_USER=postgres
DB_PASSWORD=your_password
DB_SCHEMA=public
OPENAI_API_KEY=
```

Add this to `.gitignore`:
```
.env
```

---

## Docker Setup

**Dockerfile:**
```dockerfile
# Use Python 3.12 because the application requires python >= 3.12
FROM python:3.12-slim

# Prevent Python from creating .pyc files
# and make python output appear immediately in Docker logs
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Application directory inside the container
WORKDIR /app

COPY requirements.txt .

# Install Python dependencies
RUN pip install \
    --no-cache-dir \
    --default-timeout=300 \
    --retries=10 \
    -r requirements.txt

# Copy application source code
COPY app.py .
COPY main.py .

# Streamlit default port
EXPOSE 8501

# Start the Streamlit application
CMD ["streamlit", "run", "app.py", "--server.address=0.0.0.0", "--server.port=8501"]
```

Build and run locally:
```bash
docker build -t postgres-rag:local .
docker run -p 8501:8501 --env-file .env postgres-rag:local
```

> If the build seems to hang at the `pip install` step, it's usually a slow network / large dependency resolution — not a stuck process. The `--default-timeout=300 --retries=10` flags exist specifically to make this reliable rather than failing at the default 15s timeout.

---

## Kubernetes / MicroK8s Setup

Deployment manifests live in the **GitOps repo** (`postgres-rag-gitops/k8s/`):

- `namespace.yml` — namespace for the app
- `deployment.yml` — Deployment spec for the RAG app pod
- `service.yml` — ClusterIP/NodePort service exposing port 8501
- `argocd-application.yml` — Argo CD `Application` resource pointing at this repo/path

Apply manually (for first-time bootstrap only — after that, Argo CD manages sync):
```bash
k apply -f k8s/namespace.yml
k apply -f k8s/argocd-application.yml
```

Check status:
```bash
k get pods -n <namespace>
k get svc -n <namespace>
```

---

## CI — Jenkins Pipeline

Jenkins runs the CI stage: checkout → build image → push image → (optionally) bump image tag in the GitOps repo.

**Jenkins agent vs "Built-In Node":**
- The **Built-In Node** is the controller itself running the pipeline steps directly on the Jenkins master. It's fine for lightweight scripting but is **not recommended for Docker builds** — the controller may not have Docker/Kaniko available or isolated, and tying up the controller with build workloads hurts stability and security.
- A **dedicated agent** (e.g. `jenkins-agent` pod) is a separate, disposable pod spun up specifically to run the build. It has its own environment (Docker-in-Docker or Kaniko, correct tooling versions), is isolated from the controller, and can be scaled independently.
- **Rule of thumb:** use `agent { label 'your-agent-label' }` (or a `podTemplate`) for any Docker/Kubernetes build step. Reserve `agent any` / built-in node only for trivial, non-build steps.

**RBAC check** (confirms the Jenkins service account can create pods for dynamic agents):
```bash
k auth can-i create pods \
  --as=system:serviceaccount:monitoring:jenkins \
  -n monitoring
# → yes
```

---

## CD — Argo CD (GitOps)

Argo CD continuously watches the `postgres-rag-gitops` repo. Any change to the manifests (e.g. a new image tag pushed by Jenkins) is automatically detected and synced to the cluster — no manual `kubectl apply` needed after initial bootstrap.

```bash
# Check sync status
argocd app get postgres-rag

# Force a manual sync (if auto-sync is off)
argocd app sync postgres-rag
```

---

## Choosing an LLM Backend: OpenAI vs Ollama

This project supports two interchangeable inference backends. **Only the LLM/embedding client code differs — the rest of the architecture (Postgres, Jenkins, Argo CD, MicroK8s) stays identical.**

| | OpenAI | Ollama (self-hosted) |
|---|---|---|
| Cost | Pay-as-you-go (prepaid credit, min ~$5) | Free, runs locally |
| Internet required at inference time | Yes | No (after model pull) |
| Models used | `gpt-4.1-mini`, `text-embedding-3-small` | `llama3.2:3b`, `nomic-embed-text` |
| Runs as | External API call | Kubernetes pod (`ollama` service on port `11434`) |
| Client code | `OpenAI(...)`, `OpenAIEmbeddings(...)` | `ChatOllama(model=..., base_url="http://ollama:11434")`, `OllamaEmbeddings(model=..., base_url="http://ollama:11434")` |

**Switching to Ollama is not just a config change** — it requires changing *both* the model name **and** the calling method (a different client class making calls to a different endpoint), since the two are different APIs entirely.

To deploy Ollama in-cluster:
1. Deploy an `ollama` pod + `ClusterIP` service in the same namespace as the app.
2. Pull the required models inside the pod: `ollama pull llama3.2:3b` and `ollama pull nomic-embed-text`.
3. Point the app at `http://ollama:<namespace>.svc.cluster.local:11434` (or short DNS name `http://ollama:11434` if in the same namespace).
4. Update `app.py` to use `ChatOllama` / `OllamaEmbeddings` instead of the OpenAI classes.

---

## Verifying the Deployment

```bash
# Confirm pods are running
k get pods -n <namespace>

# Confirm the service is reachable
k get svc -n <namespace>

# Port-forward to test locally
k port-forward svc/postgres-rag 8501:8501 -n <namespace>
```

Sample test query flow (using the seeded employees table):
- *"Who is the Senior DevOps Engineer?"* → should return the correct name from Postgres.
- *"How many employees are in the Engineering department?"* → should return the correct count.

---

## Troubleshooting

See **`PROJECT_JOURNEY_AND_TROUBLESHOOTING.md`** in this repo for the full list of real errors encountered during setup (Jenkins CrashLoopBackOff, RBAC failures, OpenAI quota exhaustion, Terraform provider errors, etc.) with root causes and exact fixes — written for both day-to-day debugging and interview prep.

---

## Security Notes

- Never commit real credentials — only `.env.example` with blank values goes into version control.
- `.env` is git-ignored.
- API keys and DB passwords should ultimately be managed via a **Kubernetes Secret**, not hardcoded into `deployment.yml`.
- Do not use publicly shared/"free" API keys — they are a security and reliability risk.

---

## License

Add your preferred license here (e.g. MIT).
