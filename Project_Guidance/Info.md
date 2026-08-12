# Project Journey & Troubleshooting Log — PostgreSQL RAG on MicroK8s (Jenkins + Argo CD)

This document is a **step-by-step build log** of how this project was actually implemented, including every real error faced and how it was resolved. It is written so you can walk an interviewer through the project end-to-end and answer "what went wrong and how did you fix it" for each stage.

---

## 1. Project Goal

Build a Retrieval-Augmented Generation (RAG) application that:
- Uses **PostgreSQL** as the structured data source (employee records).
- Uses an **LLM + embedding model** (OpenAI, later evaluated Ollama) to answer natural-language questions over that data.
- Is fully containerized with **Docker**.
- Is deployed to **MicroK8s** via a **Jenkins CI → Argo CD GitOps CD** pipeline — not manual `kubectl apply`.

---

## 2. Application Layer

**Stack:** Python 3.12, Streamlit UI, `app.py` (RAG logic + UI) and `main.py`, dependencies managed via `pyproject.toml` / `requirements.txt` / `uv.lock`.

**Environment configuration** — built `.env.example` for the repo and a real local `.env`:

```env
# .env.example (committed — no real values)
DB_HOST=
DB_PORT=5432
DB_NAME=
DB_USER=
DB_PASSWORD=
DB_SCHEMA=public
OPENAI_API_KEY=
```

Added `.env` to `.gitignore` immediately so real credentials never get committed.

**Why this matters for an interview:** shows awareness of the standard "template + gitignore" pattern for secrets in application repos, even before Kubernetes Secrets come into play.

---

## 3. Dockerizing the Application

Wrote a `Dockerfile` using `python:3.12-slim` as the base (matches the app's `python >= 3.12` requirement):

```dockerfile
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --default-timeout=300 --retries=10 -r requirements.txt
COPY app.py .
COPY main.py .
EXPOSE 8501
CMD ["streamlit", "run", "app.py", "--server.address=0.0.0.0", "--server.port=8501"]
```

### ❗ Issue: `docker build` / `pip install` appeared to hang
**Symptom:** Terminal sat idle for a long time during the build with no visible progress.
**Root cause:** Not actually stuck — large dependency resolution + slow network causes `pip install` to appear frozen, and pip's default timeout (15s) can cause failures on slow connections.
**Fix:** Added `--default-timeout=300 --retries=10` to the `pip install` command so it waits and retries instead of failing/hanging silently. Confirmed it was a network speed issue, not a Docker/container issue, by checking that the process was still active (not zeroed CPU) and that it eventually completed.

### ❗ Issue: slow `git push`
**Symptom:** After committing changes to the GitOps repo, `git push` appeared slow.
**Root cause:** Confirmed to be local network speed, not a Git/repo corruption issue — verified the push did eventually complete and the remote showed the correct commit hash range (`2d96099..2be32d3 main -> main`).
**Fix:** No code fix needed; verified with `git branch --show-current` and a subsequent `git log`/remote check rather than assuming failure.

---

## 4. Infrastructure — Terraform / AWS Provider

Set up base Terraform provider config for AWS resources (including RDS):

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

### ❗ Issue: RDS resource block showing multiple errors ("+9 errors")
**Symptom:** `terraform plan`/`validate` reported multiple errors against the RDS resource block.
**Root cause (general pattern for this class of error):** With AWS provider `~> 6.0`, several RDS argument names and required fields changed/were deprecated compared to older provider versions (e.g. argument renames, newly-required fields like `manage_master_user_password`, `db_subnet_group_name`, `vpc_security_group_ids` needing to reference actual resource attributes instead of hardcoded values, or missing `engine_version`/`instance_class`). A block of ~9 errors from one `aws_db_instance` resource is typically **one root cause repeated across many argument lines** — one missing/misnamed required argument cascades into several downstream "unsupported argument" or "missing required argument" errors.
**Fix approach used:**
1. Ran `terraform validate` to get the exact argument names flagged (not just the count).
2. Cross-checked each flagged argument against the Terraform AWS provider `~> 6.0` docs for `aws_db_instance`, since several argument names changed between major provider versions.
3. Fixed required fields (subnet group, security group references via `.id`, `engine`/`engine_version`, `instance_class`) one at a time and re-ran `terraform validate` after each fix to isolate the cascade.
4. Confirmed `terraform plan` produced a clean plan before applying.

**Interview talking point:** "A wall of Terraform errors is rarely nine separate bugs — it's usually one missing or renamed required argument causing a cascade. I fix the first flagged error, re-validate, and repeat rather than trying to fix all nine blind."

---

## 5. Kubernetes / MicroK8s — Jenkins Investigation

### ❗ Issue: `jenkins-0` pod stuck in `Init:CrashLoopBackOff` (105 days old, 12,775 restarts)
**Symptom:**
```
default   jenkins-0   0/1   Init:CrashLoopBackOff   12775 (4m17s ago)   105d
```
**Root cause:** This was a **stale/orphaned Jenkins StatefulSet in the `default` namespace**, separate from the actually-used Jenkins deployment running correctly in the `monitoring` namespace. Its init container was failing repeatedly — an old, abandoned resource, not the active pipeline.
**Fix / diagnosis steps:**
```bash
k get pods -A | grep -i jenkins
k get svc -A | grep -i jenkins
k get deployments -A | grep -i jenkins
```
Confirmed the **working** Jenkins was:
```
monitoring   jenkins-6ddc56d9db-drdqp   1/1   Running   51   13d
monitoring   jenkins-agent-584dfbf7d4-5tn7k   1/1   Running   43   12d
```
**Resolution:** Left the broken `default` namespace StatefulSet identified as legacy/unused (candidate for cleanup) and continued working with the healthy `monitoring` namespace Jenkins deployment — confirmed via `k get pods -n monitoring -l app=jenkins -o wide`.

**Interview talking point:** "Before debugging a broken pod, I always check whether it's actually the resource in use — `k get pods -A | grep` across all namespaces to avoid chasing a dead/duplicate deployment."

---

## 6. Jenkins Pipeline — Agent vs Built-In Node

### ❗ Question that came up: "Why can't we just use the built-in node?"
**Explanation given and implemented:**
- **Built-in node** = the Jenkins controller itself. Running builds there means Docker/Kaniko build steps execute directly on the Jenkins master.
- Risks: no isolation between builds, the controller can be resource-starved, and the controller often lacks the build tooling (Docker socket access, correct image) that a build actually needs.
- **Dedicated agent** = a separate pod (`jenkins-agent`), spun up on demand, with its own environment for building/pushing Docker images. Keeps the controller stable and build environments reproducible/isolated.
- **Decision:** used a labeled agent (`agent { label ... }` / Kubernetes `podTemplate`) for the Docker build stage instead of `agent any`, to keep the pipeline correct and not just "fast for now."

---

## 7. RBAC — Jenkins Service Account Permissions

To confirm Jenkins had permission to dynamically provision agent pods:

```bash
k auth can-i create pods \
  --as=system:serviceaccount:monitoring:jenkins \
  -n monitoring
# → yes
```

### ❗ Issue: `serviceAccountName` returned empty
**Symptom:**
```bash
k get deployment jenkins -n monitoring -o jsonpath='{.spec.template.spec.serviceAccountName}{"\n"}'
# → (empty output)
```
**Root cause:** No `serviceAccountName` explicitly set on the Jenkins deployment spec — meaning it was running under the **`default`** service account for that namespace rather than a dedicated `jenkins` service account, even though the `k auth can-i` check (run explicitly `--as=...jenkins`) returned `yes` for that named SA.
**Why this matters:** `k auth can-i --as=X` only tells you whether SA *X* **would** have permission — it does not confirm the pod is actually **running as** that SA. These are two separate checks and both are needed:
1. Does the intended SA have the RBAC permission? (`k auth can-i --as=...`)
2. Is the pod actually configured to use that SA? (`.spec.template.spec.serviceAccountName`)
**Fix:** Identified the gap and flagged that `serviceAccountName: jenkins` needed to be explicitly set on the deployment spec so the running pod actually uses the intended, permissioned service account rather than silently falling back to `default`.

**Interview talking point:** "RBAC debugging isn't just `can-i` — you also have to confirm the workload is actually running as the service account you tested. I caught a case where the deployment had no `serviceAccountName` set at all, so the `can-i` check, while technically true, wasn't testing what was actually in effect."

---

## 8. LLM Backend — OpenAI Integration and Quota Issue

Initial implementation used OpenAI:
- Model: `gpt-4.1-mini`
- Embedding model: `text-embedding-3-small`

### ❗ Issue: `credit_balance_exhausted`
**Symptom:** API calls failed with an explicit `credit_balance_exhausted` error.
**Root cause:** OpenAI API access is **billed separately from ChatGPT** and requires prepaid credit — a new API key does not come with free credits.
**Fix considered:** Purchase minimum $5 prepaid credit and disable auto-recharge to avoid unexpected charges.
**Decision actually made:** Instead of paying, migrated the LLM/embedding backend to **Ollama** (see below) to keep the project fully free and self-hosted — while documenting the OpenAI path as a valid, supported alternative for anyone with budget for it.

---

## 9. Migration Decision — OpenAI → Ollama (Self-Hosted)

**Why:** No OpenAI billing required; runs fully offline after models are pulled; no per-request cost.

**New architecture:**
```
RAG App → http://ollama:11434 → llama3.2:3b (LLM)
                               → nomic-embed-text (embeddings)
```

### ❗ Key clarification from mentor: "You need to change the model AND the method of calling"
This was initially misunderstood as "just swap the model name." Correct understanding:
- **Model change:** `gpt-4.1-mini` → `llama3.2:3b`; `text-embedding-3-small` → `nomic-embed-text`.
- **Calling-method change:** OpenAI and Ollama are **different client APIs**. Swapping the model string alone does nothing — the actual client classes making the HTTP calls change:
  - `OpenAI(...)` / `OpenAIEmbeddings(...)` → `ChatOllama(model=..., base_url="http://ollama:11434")` / `OllamaEmbeddings(model=..., base_url="http://ollama:11434")`
- **Fix:** Planned to deploy Ollama as its own pod + `ClusterIP` service in-cluster, pull both models inside it, and update `app.py`'s LLM/embedding client instantiation to the Ollama classes pointed at the in-cluster service DNS name — without changing the Jenkins/Argo CD pipeline itself, since only the application layer changes.

**Interview talking point:** "This taught me that migrating an LLM provider isn't a config value change — it's a client-library/API-contract change. I made sure to separate 'which model' from 'how we call it' as two distinct changes when explaining the migration."

---

## 10. Verification Data

Seeded a Postgres `employees` table with 5 rows to validate the RAG pipeline end-to-end:
```
Muskan Patel     DevOps Engineer
Afzal Ehsani     Senior DevOps Engineer
Gulnar Khan      SRE Engineer
Rahul Mehta      DevOps Engineer
Neha Joshi       Software Engineer
```
Confirmed with test queries such as "Who is the Senior DevOps Engineer?" and "How many employees are in the Engineering department?" that the pipeline correctly retrieved and reasoned over the Postgres data before considering it stable enough to sit behind CI/CD.

---

## 11. Summary — What This Project Demonstrates

| Area | What was done |
|---|---|
| App | Streamlit RAG app over PostgreSQL, Python 3.12 |
| Containerization | Custom Dockerfile, resolved slow-build/timeout issue |
| IaC | Terraform AWS provider setup, diagnosed and fixed a cascading RDS argument error |
| CI | Jenkins pipeline, correct use of dedicated agents vs built-in node |
| Security/RBAC | Diagnosed a real gap between "SA has permission" and "pod uses that SA" |
| CD | GitOps repo + Argo CD auto-sync, separate app/deploy repos |
| Debugging | Identified and ruled out a stale, unrelated CrashLoopBackOff pod before debugging the real Jenkins instance |
| Cost engineering | Diagnosed OpenAI billing/quota limitation and re-architected to a free, self-hosted Ollama backend |

**One-line project summary for interviews:**
> "I built a PostgreSQL-backed RAG application, containerized it, and deployed it to MicroK8s using Jenkins for CI and Argo CD for GitOps-based CD. Along the way I debugged a stale CrashLoopBackOff Jenkins pod, fixed an RBAC gap between service-account permissions and actual pod configuration, resolved a cascading Terraform RDS provider error, and migrated the LLM backend from OpenAI to a self-hosted Ollama deployment after hitting API billing limits — which required changing both the model and the client-calling method, not just a config value."