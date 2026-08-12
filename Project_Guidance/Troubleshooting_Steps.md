# PostgreSQL RAG Project — My Complete Implementation & Interview Troubleshooting Journal

> **Purpose:** This README is my personal implementation record. It is intentionally more detailed than the public GitHub README. It records the actual path I followed, the commands I used, what worked, what failed, why it failed, and how I diagnosed it.

---

# 1. Project Goal

The goal was to build a PostgreSQL RAG chatbot and then demonstrate a complete DevOps lifecycle:

```text
Application
   |
   v
Docker
   |
   v
Jenkins CI
   |
   v
Docker Hub
   |
   v
GitOps Repository
   |
   v
Argo CD
   |
   v
MicroK8s
```

The longer-term architecture is intended to move toward:

```text
MicroK8s lab
      |
      v
Terraform
      |
      +---- AWS EKS
      |
      +---- AWS RDS PostgreSQL
```

A later cost-reduction option is:

```text
OpenAI
   |
   v
Ollama
```

The OpenAI version is the implementation documented in the application source captured here.

---

# 2. My Local Environment

Observed environment:

```text
OS: Ubuntu 24.04.4 LTS
Kernel: 7.0.0-28-generic
Laptop: Lenovo ThinkPad L14 Gen 1
CPU: Intel i5 10th Gen
RAM: 16 GB
SSD: 512 GB
Kubernetes: MicroK8s
Kubernetes version: v1.33.13
Container runtime: containerd 1.7.29
Docker: 29.1.3
```

Node:

```text
muskan-thinkpad-l14-gen-1
```

Internal IP observed:

```text
192.168.1.5
```

---

# 3. Initial Application Repository

I worked inside:

```bash
cd ~/Devops-lab/postgress-rag/postgress-rag
```

Initial files:

```bash
ls
```

Output:

```text
app.py
Dockerfile
Jenkinsfile
Jenkinsfile_initial
main.py
pyproject.toml
README.md
requirements.txt
uv.lock
```

The application is a Streamlit project.

---

# 4. Application Technology

The application uses:

```text
Python
Streamlit
LangChain
LangChain OpenAI
PostgreSQL
SQLAlchemy
psycopg2
FAISS
python-dotenv
OpenAI
```

Python requirement:

```text
>= 3.12
```

---

# 5. Original Application README

The original README described the application as:

```text
PostgreSQL RAG Chat (Streamlit + LangChain + OpenAI)
```

The application:

- connects to PostgreSQL
- reads tables
- converts rows into documents
- creates OpenAI embeddings
- stores vectors in FAISS
- refreshes the index when the database fingerprint changes
- provides a Streamlit chat UI

The original setup was:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Optional:

```bash
cp .env.example .env
```

Run:

```bash
streamlit run app.py
```

---

# 6. Application Dependencies

The dependency list captured from the project was:

```text
streamlit>=1.38.0
langchain>=0.3.0
langchain-core>=0.3.0
langchain-community>=0.3.0
langchain-openai>=0.2.0
sqlalchemy>=2.0.35
psycopg2-binary>=2.9.9
faiss-cpu>=1.8.0
python-dotenv>=1.0.1
```

---

# 7. How the RAG Application Works

The important logic is:

```text
PostgreSQL
    |
    v
Read schema/tables
    |
    v
Convert each row into Document
    |
    v
OpenAIEmbeddings
    |
    v
FAISS
    |
    v
Retriever
    |
    v
Question
    |
    v
Prompt
    |
    v
ChatOpenAI
    |
    v
Answer
```

The retriever uses:

```python
search_kwargs={"k": 6}
```

The application prompt tells the model:

```text
Use only the context below when answering.
If the answer is not in context, say you do not know.
```

This is important because the application is designed as a grounded RAG system rather than a general chatbot.

---

# 8. Initial Streamlit Fields

The application displayed:

```text
Connection

DB Host
DB Port
DB Name
DB User
DB Password
Schema
Rows per table to ingest

OpenAI

OpenAI API Key
Model
Embedding Model
```

Defaults captured:

```text
DB Port: 5432
Schema: public
Rows per table: 5000
Model: gpt-4o-mini
Embedding Model: text-embedding-3-small
```

The button was:

```text
Connect / Refresh Index
```

---

# 9. First Kubernetes Application Deployment

The application was deployed to the MicroK8s cluster.

I verified nodes:

```bash
kubectl get nodes -o wide
```

Observed:

```text
NAME                        STATUS   ROLES    AGE    VERSION
muskan-thinkpad-l14-gen-1   Ready    <none>   ...    v1.33.13
```

The node was healthy.

---

# 10. Application Service

I checked services:

```bash
kubectl get svc -n monitoring
```

The important service was:

```text
postgres-rag
```

It was:

```text
TYPE: NodePort
CLUSTER-IP: 10.152.183.210
PORT: 8501:30861/TCP
```

So the Streamlit application was exposed using NodePort `30861`.

---

# 11. GitOps Repository

I moved one directory up:

```bash
cd ..
ls
```

I saw:

```text
coredns-backup.yaml
postgres-rag-gitops
postgress-rag
terraform
```

Then:

```bash
cd postgres-rag-gitops/
ls
```

Output:

```text
k8s
```

Then:

```bash
cd k8s
ls
```

Output:

```text
argocd-application.yml
deployment.yml
namespace.yml
service.yml
```

This became the GitOps repository structure.

---

# 12. CI/CD Design

The design became:

```text
Application GitHub Repository
          |
          v
       Jenkins
          |
          v
       Kaniko
          |
          v
      Docker Hub
          |
          v
    GitOps Repository
          |
          v
       Argo CD
          |
          v
       MicroK8s
```

The important distinction:

```text
CI = Jenkins
CD = Argo CD
Desired state = GitOps repository
Runtime = Kubernetes/MicroK8s
```

---

# 13. Jenkinsfile

The Jenkins pipeline uses a Kubernetes dynamic agent.

The Kaniko container:

```text
gcr.io/kaniko-project/executor:v1.23.2-debug
```

The pod configuration uses:

```yaml
hostNetwork: true
dnsPolicy: Default
```

The Kaniko container uses:

```text
/busybox/cat
```

with:

```text
tty: true
```

A Docker configuration volume is mounted at:

```text
/kaniko/.docker
```

---

# 14. Why Kaniko Was Used

Instead of:

```text
Jenkins
  |
  +-- Docker daemon
  |
  +-- docker build
```

I used:

```text
Jenkins Kubernetes Agent
       |
       +-- Kaniko
             |
             +-- Build image
             |
             +-- Push image
```

The benefit is that I do not need Docker-in-Docker for the image build.

---

# 15. Docker Hub Credentials

In Jenkins I configured:

```text
credentialsId: dockerhub-creds
```

The pipeline obtains:

```text
DOCKER_USERNAME
DOCKER_PASSWORD
```

The pipeline then creates:

```text
/kaniko/.docker/config.json
```

The authentication is generated with:

```bash
AUTH=$(printf "%s:%s" "$DOCKER_USERNAME" "$DOCKER_PASSWORD" | base64 | tr -d '\n')
```

Then the registry configuration is written.

---

# 16. Docker Image Tagging

The image destination is:

```text
docker.io/$DOCKER_USERNAME/postgres-rag:$BUILD_NUMBER
```

One observed build generated:

```text
docker.io/muskanpatel71198/postgres-rag:23
```

This is useful because:

```text
Jenkins Build 23
        |
        v
Docker tag 23
```

So I can map a deployment back to a Jenkins build.

---

# 17. Jenkins Pipeline Verification

The Jenkins log showed:

```text
Obtained Jenkinsfile from git
```

Then a Kubernetes agent was created.

The agent pod included:

```text
jnlp
kaniko
```

The workspace was:

```text
/home/jenkins/agent/workspace/postgres-rag-ci
```

Git successfully checked out the application repository.

---

# 18. Jenkins Error — Agent Offline

I encountered:

```text
Agent ... is offline
```

and:

```text
seems to be removed or offline
```

The Jenkins Kubernetes plugin was dynamically creating agent pods.

The pod contained:

```text
jnlp
kaniko
```

The issue was agent/controller communication or pod lifecycle instability.

### Diagnosis

I checked:

```bash
kubectl get pods -n monitoring
```

Then:

```bash
kubectl describe pod <agent-pod> -n monitoring
```

And:

```bash
kubectl logs <agent-pod> -n monitoring -c jnlp
```

The Jenkins log repeatedly showed the agent going offline and returning online.

### Interview answer

> "The Jenkins Kubernetes plugin creates ephemeral agents. When the agent becomes unavailable, Jenkins reports the agent as offline. I diagnose it from the Kubernetes pod state, JNLP container logs, scheduling events, and controller-agent connectivity."

---

# 19. Jenkins Warning — Git Installation

I also saw:

```text
Selected Git installation does not exist. Using Default
The recommended git tool is: NONE
```

However, Git operations succeeded:

```text
git version 2.47.3
```

and the repository was successfully cloned.

### Conclusion

This was a Jenkins Git-tool configuration warning, not the direct cause of the successful checkout failure.

### Interview answer

> "The configured Git installation was not found, so Jenkins fell back to the default Git executable. Because Git was available on the agent, checkout still worked."

---

# 20. Successful Kaniko Build

The pipeline reached:

```text
Build Docker Image
```

Then:

```text
Starting Kaniko build...
```

and executed:

```text
/kaniko/executor
```

with:

```text
--context=/home/jenkins/agent/workspace/postgres-rag-ci
--dockerfile=/home/jenkins/agent/workspace/postgres-rag-ci/Dockerfile
--destination=docker.io/muskanpatel71198/postgres-rag:23
```

Docker Hub authentication was masked by Jenkins.

This confirmed that CI image creation was working.

---

# 21. PostgreSQL Requirement

The RAG application cannot work with an empty database.

I created PostgreSQL inside MicroK8s.

The PostgreSQL deployment used:

```text
postgres:16
```

The application service was:

```text
postgres-rag-db
```

Port:

```text
5432
```

---

# 22. PostgreSQL PVC

Initially I checked:

```bash
kubectl get pvc -A | grep -i postgres
```

There was no PostgreSQL PVC at that point.

I then created the PostgreSQL PVC.

Afterward:

```bash
kubectl get pvc -n monitoring
```

showed:

```text
postgres-rag-pvc
STATUS: Bound
CAPACITY: 5Gi
STORAGECLASS: microk8s-hostpath
```

This confirmed persistent storage was successfully provisioned.

---

# 23. PostgreSQL Pod Was Initially ContainerCreating

I checked:

```bash
kubectl get pods -n monitoring | grep postgres -w
```

Initially:

```text
postgres-rag-db-758d86f4b5-hnht9   0/1   ContainerCreating
```

I checked events.

The events showed:

```text
Successfully assigned ...
Pulling image "postgres:16"
Successfully pulled image "postgres:16"
Created container: postgres
Started container: postgres
```

The image was approximately 160 MB and took about two minutes to pull.

After that:

```text
postgres-rag-db-758d86f4b5-hnht9   1/1   Running
```

### Interview answer

> "The PostgreSQL pod was initially in ContainerCreating because Kubernetes was pulling the PostgreSQL image. I checked pod events instead of assuming a storage or scheduling problem. The events showed successful image pull and container startup."

---

# 24. PostgreSQL Logs

The PostgreSQL logs showed:

```text
PostgreSQL 16.14
listening on IPv4 address "0.0.0.0", port 5432
listening on IPv6 address "::", port 5432
database system is ready to accept connections
```

This confirmed PostgreSQL was healthy.

---

# 25. PostgreSQL Deployment Validation

I ran:

```bash
kubectl get deployment postgres-rag-db -n monitoring -o yaml
```

Important configuration:

```text
replicas: 1
```

Container:

```text
image: postgres:16
```

Environment variables came from:

```text
Secret: postgres-rag-db
```

Keys:

```text
POSTGRES_DB
POSTGRES_USER
POSTGRES_PASSWORD
```

Volume:

```text
postgres-rag-pvc
```

Mounted at:

```text
/var/lib/postgresql/data
```

---

# 26. PostgreSQL Secret Validation

I checked the database name:

```bash
kubectl get secret postgres-rag-db -n monitoring \
  -o jsonpath='{.data.POSTGRES_DB}' | base64 -d
echo
```

Output:

```text
postgres_rag
```

I checked the user:

```bash
kubectl get secret postgres-rag-db -n monitoring \
  -o jsonpath='{.data.POSTGRES_USER}' | base64 -d
echo
```

Output:

```text
postgres
```

I did not expose the password in documentation.

---

# 27. PostgreSQL DNS Test

From the application pod:

```bash
kubectl exec -it postgres-rag-cb6c8d6-c7g59 -n monitoring -- sh
```

Then:

```bash
getent hosts postgres-rag-db
```

Result:

```text
10.152.183.177 postgres-rag-db.monitoring.svc.cluster.local
```

I also tested DNS from Python:

```bash
kubectl exec postgres-rag-cb6c8d6-c7g59 -n monitoring \
  -- python -c "import socket; print(socket.gethostbyname('postgres-rag-db'))"
```

Result:

```text
10.152.183.177
```

### Conclusion

Kubernetes Service DNS was working.

---

# 28. First Application Database Error

The application initially produced:

```text
could not translate host name " postgres-rag-db" to address
```

### Root cause

There was a leading space in the DB Host value.

Incorrect:

```text
 postgres-rag-db
```

Correct:

```text
postgres-rag-db
```

After removing the leading space, DNS resolution worked.

### Interview answer

> "The database service itself was healthy and DNS resolution worked from the pod. The application error was caused by whitespace in the hostname entered through the UI."

---

# 29. Second Database Error

After fixing the hostname, I received:

```text
connection to server at "postgres-rag-db" (10.152.183.177),
port 5432 failed:
FATAL: database "postgres-rag" does not exist
```

### Root cause

The configured DB name was wrong.

I had entered:

```text
postgres-rag
```

But Kubernetes Secret showed:

```text
postgres_rag
```

### Correct configuration

```text
DB Host: postgres-rag-db
DB Port: 5432
DB Name: postgres_rag
DB User: postgres
DB Password: <the configured secret value>
Schema: public
```

---

# 30. Third Application Error — Empty Database

After the database connection worked, I got:

```text
No rows found in the selected schema/tables.
```

This was a good sign.

It meant:

```text
Application
   |
   v
DNS
   |
   v
PostgreSQL Service
   |
   v
PostgreSQL
```

was working.

The remaining problem was data.

---

# 31. PostgreSQL Client Pod

I used a PostgreSQL client pod to connect:

```bash
psql -h postgres-rag-db -U postgres -d postgres_rag
```

The connection succeeded.

Then:

```sql
\dt
```

returned:

```text
Did not find any relations.
```

Then:

```sql
\dn
```

returned:

```text
public
```

I checked tables:

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'public';
```

Result:

```text
0 rows
```

### Root cause

The database was empty.

---

# 32. Test Table

I created an `employees` table.

Then inserted five records:

```sql
INSERT INTO employees (name, role, department, location)
VALUES
('Muskan Patel', 'DevOps Engineer', 'Engineering', 'India'),
('Afzal Ehsani', 'Senior DevOps Engineer', 'Platform', 'India'),
('Gulnar Khan', 'SRE Engineer', 'Infrastructure', 'India'),
('Rahul Mehta', 'DevOps Engineer', 'Engineering', 'India'),
('Neha Joshi', 'Software Engineer', 'Development', 'India');
```

The insert returned:

```text
INSERT 0 5
```

Validation:

```sql
SELECT * FROM employees;
```

returned five rows.

This proved the PostgreSQL backend now had data for RAG ingestion.

---

# 33. OpenAI DNS Error

During indexing I encountered:

```text
HTTPSConnectionPool(host='openaipublic.blob.core.windows.net',
port=443): Max retries exceeded
```

with:

```text
NameResolutionError
Failed to resolve 'openaipublic.blob.core.windows.net'
```

### Root cause

The application could not resolve the external OpenAI tokenizer endpoint.

This was not a PostgreSQL problem.

It was an external DNS/network-resolution issue from the application environment.

### Diagnostic principle

When an external hostname fails:

```text
Check application pod
        |
        +-- DNS
        +-- CoreDNS
        +-- network
        +-- external connectivity
```

---

# 34. OpenAI Quota Error

After DNS was resolved, the application reached OpenAI but failed with:

```text
Error code: 429
```

and:

```text
insufficient_quota
credit_balance_exhausted
```

### Root cause

The OpenAI account had no remaining API credits.

This was not:

- PostgreSQL
- Kubernetes
- Jenkins
- Docker
- Argo CD

It was an external API billing/quota issue.

---

# 35. Why I Considered Ollama

Because the external API required credits, I considered a local model.

The alternative architecture is:

```text
Streamlit
   |
   v
Ollama Service
   |
   +---- LLM
   |
   +---- Embedding model
```

For Kubernetes:

```text
Ollama Deployment
       |
       v
Ollama Service :11434
       |
       v
RAG Application
```

Important lesson from the mentor:

> "Change the model and method of calling."

This means I cannot simply change:

```text
gpt-4o-mini
```

to an Ollama model name.

The current source uses:

```python
ChatOpenAI(...)
```

and:

```python
OpenAIEmbeddings(...)
```

Therefore, the integration classes/API method also need to change.

The Ollama implementation is a planned next step, not part of the verified OpenAI implementation recorded above.

---

# 36. Current PostgreSQL Verification

The following command was useful:

```bash
kubectl get pods -n monitoring | grep postgres -w
```

Expected healthy result:

```text
postgres-rag-db-...   1/1   Running
```

PVC:

```bash
kubectl get pvc -n monitoring
```

Expected:

```text
postgres-rag-pvc   Bound   5Gi   RWO   microk8s-hostpath
```

Service:

```bash
kubectl get svc -n monitoring
```

Expected database service:

```text
postgres-rag-db
```

---

# 37. Application Verification

Application:

```bash
kubectl get deployment postgres-rag -n monitoring
```

Pod:

```bash
kubectl get pods -n monitoring | grep postgres-rag
```

Service:

```bash
kubectl get svc postgres-rag -n monitoring
```

The verified service:

```text
NodePort
8501:30861
```

---

# 38. CI Verification

Check Jenkins agents:

```bash
kubectl get pods -n monitoring
```

Look for:

```text
postgres-rag-ci-...
```

Check Jenkins job output.

Important successful messages:

```text
Obtained Jenkinsfile from git
```

```text
Checking out Revision ...
```

```text
Starting Kaniko build...
```

```text
/kaniko/executor ...
```

and a Docker Hub destination similar to:

```text
docker.io/muskanpatel71198/postgres-rag:<BUILD_NUMBER>
```

---

# 39. CD Verification

The GitOps repository contains:

```text
k8s/
├── argocd-application.yml
├── deployment.yml
├── namespace.yml
└── service.yml
```

Argo CD should show:

```text
Synced
Healthy
```

The conceptual flow is:

```text
GitOps Git repository
        |
        v
     Argo CD
        |
        v
    MicroK8s
```

---

# 40. Important Kubernetes Commands I Used

Nodes:

```bash
kubectl get nodes -o wide
```

All resources:

```bash
kubectl get all -A
```

PostgreSQL resources:

```bash
kubectl get all -A | grep -i postgres
```

Pods:

```bash
kubectl get pods -n monitoring
```

Services:

```bash
kubectl get svc -n monitoring
```

PVC:

```bash
kubectl get pvc -n monitoring
```

Storage:

```bash
kubectl get storageclass
```

Deployment YAML:

```bash
kubectl get deployment postgres-rag-db -n monitoring -o yaml
```

Pod events:

```bash
kubectl describe pod <pod-name> -n monitoring
```

Logs:

```bash
kubectl logs <pod-name> -n monitoring
```

Execute shell:

```bash
kubectl exec -it <pod-name> -n monitoring -- sh
```

---

# 41. Error-to-Solution Interview Table

| Error | Root Cause | Solution |
|---|---|---|
| `could not translate host name " postgres-rag-db"` | Leading whitespace in hostname | Enter `postgres-rag-db` without space |
| `database "postgres-rag" does not exist` | Wrong DB name | Use `postgres_rag` |
| `No rows found in selected schema/tables` | PostgreSQL database had no data | Create table and insert rows |
| `NameResolutionError` for OpenAI blob host | External DNS resolution failure | Diagnose CoreDNS/network/external DNS |
| `429 insufficient_quota` | OpenAI credits exhausted | Add quota or move to local/alternative model |
| Jenkins agent offline | Ephemeral Kubernetes agent/controller communication issue | Inspect pod events and JNLP logs |
| `Selected Git installation does not exist` | Jenkins Git tool configuration mismatch | Jenkins falls back to default Git if available |
| PostgreSQL pod `ContainerCreating` | Image was being pulled | Inspect events; wait for pull/start |
| No PostgreSQL PVC initially | Storage resource had not yet been created | Create PVC and verify Bound state |

---

# 42. My Debugging Method

When something failed, I learned not to immediately change YAML.

I followed:

```text
1. Read the exact error
        |
2. Identify the failing layer
        |
3. Check Kubernetes resource state
        |
4. Check logs/events
        |
5. Test connectivity independently
        |
6. Validate configuration values
        |
7. Fix only the failing layer
        |
8. Retest
```

Example:

```text
Application cannot connect to PostgreSQL
            |
            v
Check DNS
            |
            v
DNS works
            |
            v
Check DB name
            |
            v
Wrong DB name found
            |
            v
Fix DB name
```

---

# 43. Interview Question — Explain the Project

Answer:

> "I built a PostgreSQL RAG chatbot using Streamlit and LangChain. PostgreSQL is the source of structured data. The application converts rows into documents and creates embeddings using OpenAI. FAISS stores the vectors locally. For a user query, LangChain retrieves the most relevant documents and passes them as context to the chat model. I containerized the application and built images using Jenkins with dynamic Kubernetes agents and Kaniko. Images are pushed to Docker Hub. Kubernetes manifests are maintained separately in a GitOps repository, and Argo CD synchronizes those manifests into MicroK8s."

---

# 44. Interview Question — Why Separate GitOps Repository?

Answer:

> "I separated application source code from Kubernetes desired state. Jenkins owns CI and image creation, while the GitOps repository represents the desired cluster state. Argo CD continuously reconciles the cluster with that repository. This provides versioning, auditability, rollback capability, and a clean separation between build and deployment."

---

# 45. Interview Question — Why Kaniko?

Answer:

> "I used Kaniko because the Jenkins build runs inside Kubernetes and I wanted to build container images without requiring a Docker daemon or Docker-in-Docker. Kaniko builds the image from the Dockerfile and can push it directly to the registry."

---

# 46. Interview Question — Why Argo CD?

Answer:

> "Argo CD provides GitOps-based continuous delivery. Git becomes the source of truth for Kubernetes configuration. Argo CD detects differences between Git and the cluster and reconciles the cluster to the desired state."

---

# 47. Interview Question — How Did You Debug PostgreSQL?

Answer:

> "First I checked the pod and deployment status, then the PostgreSQL logs, service, PVC, and Kubernetes DNS. I verified the service hostname from the application pod using getent and Python socket resolution. I then connected using psql and checked the database, schema, tables, and rows. This helped me distinguish DNS, database-name, and empty-data problems."

---

# 48. Interview Question — What Did You Learn From the Empty Database Error?

Answer:

> "The error `No rows found in the selected schema/tables` actually confirmed that the application had progressed beyond basic connectivity. PostgreSQL was reachable, but the selected schema contained no relations. I validated it with `\\dt` and `information_schema.tables`, then created an employees table and inserted test data."

---

# 49. Interview Question — What Did You Learn From the 429 Error?

Answer:

> "The 429 response was an external provider quota problem. The application had successfully reached OpenAI, but the account had exhausted its available credits. It was therefore important not to troubleshoot Kubernetes or PostgreSQL for an API billing error."

---

# 50. Interview Question — Why Ollama?

Answer:

> "I considered Ollama because I wanted a local model path without depending on paid external inference. However, moving from OpenAI to Ollama requires both changing the model integration and changing the client/API method. The current application uses OpenAI-specific LangChain integrations, so this is an application-layer migration rather than simply changing a model string."

---

# 51. Current State

The verified parts are:

```text
[✓] MicroK8s cluster
[✓] Kubernetes application deployment
[✓] Streamlit service
[✓] PostgreSQL Deployment
[✓] PostgreSQL Service
[✓] PostgreSQL PVC
[✓] PostgreSQL Secret
[✓] PostgreSQL DNS
[✓] PostgreSQL database
[✓] PostgreSQL test table
[✓] PostgreSQL test rows
[✓] Jenkins CI
[✓] Kubernetes Jenkins dynamic agent
[✓] Kaniko build
[✓] Docker Hub push
[✓] GitOps repository structure
[✓] Argo CD based deployment design
```

The following were discussed/planned rather than fully verified in the captured implementation:

```text
[ ] Complete EKS migration
[ ] Complete AWS RDS migration
[ ] Complete Terraform production infrastructure
[ ] Complete Ollama migration
```

---

# 52. Final End-to-End Picture

```text
                    DEVELOPER
                        |
                        | git push
                        v
                  +-------------+
                  |   GitHub    |
                  +-------------+
                        |
                        v
                  +-------------+
                  |   Jenkins   |
                  |     CI      |
                  +-------------+
                        |
                        v
                  +-------------+
                  |   Kaniko    |
                  | Docker Build|
                  +-------------+
                        |
                        v
                  +-------------+
                  | Docker Hub  |
                  +-------------+
                        |
                        v
              +----------------------+
              | GitOps Repository    |
              | Kubernetes Manifests |
              +----------------------+
                        |
                        v
                  +-------------+
                  |   Argo CD   |
                  |     CD      |
                  +-------------+
                        |
                        v
              +----------------------+
              |       MicroK8s       |
              |      Kubernetes      |
              +----------------------+
                   |            |
                   v            v
             +---------+   +-----------+
             |Streamlit|   | PostgreSQL|
             |  RAG    |   | 16        |
             +---------+   +-----------+
                   |
                   +--------+
                            |
                            v
                     +-------------+
                     | FAISS       |
                     | Vector Index|
                     +-------------+
                            |
                            v
                       OpenAI API
```

---

# 53. One-Minute Interview Summary

> "This project combines an AI application with an enterprise-style DevOps delivery model. The application is a PostgreSQL RAG chatbot built with Streamlit and LangChain. PostgreSQL data is transformed into documents, embedded, stored in FAISS, retrieved using similarity search, and passed to an LLM with a grounded prompt. I containerized it and implemented Jenkins CI using ephemeral Kubernetes agents and Kaniko to build and push images to Docker Hub. I separated Kubernetes manifests into a GitOps repository and used Argo CD for continuous delivery into MicroK8s. During implementation I debugged real issues including Kubernetes agent instability, Git tool configuration warnings, PostgreSQL image startup, persistent volumes, Kubernetes DNS, incorrect database names, empty schemas, external DNS resolution, and OpenAI quota exhaustion. The next evolution is moving infrastructure to Terraform-managed AWS EKS/RDS and optionally replacing paid OpenAI inference with an Ollama-based local model."

---

# 54. Important Reminder

Do not memorize only commands.

For interviews, memorize the **reasoning chain**:

```text
Symptom
   |
   v
Layer identification
   |
   v
Evidence
   |
   v
Root cause
   |
   v
Fix
   |
   v
Validation
```

For example:

```text
"Database connection failed"
        |
        v
DNS test
        |
        v
DNS worked
        |
        v
Check database name
        |
        v
Wrong database name
        |
        v
Correct postgres_rag
        |
        v
Application connects
```

That is the strongest way to explain this project in a DevOps interview.