# PostgreSQL RAG Chatbot — CI/CD + GitOps on Kubernetes

A production-oriented Retrieval-Augmented Generation (RAG) application that connects a Streamlit chatbot to PostgreSQL, converts relational data into documents, creates embeddings, stores vectors in FAISS, retrieves relevant rows, and generates grounded answers with an LLM.

The project is also used as an end-to-end DevOps/GitOps implementation with:

- GitHub
- Jenkins
- Kaniko
- Docker Hub
- Argo CD
- MicroK8s / Kubernetes
- Kubernetes Services and persistent storage
- Traefik / Gateway API routing
- PostgreSQL
- Streamlit
- LangChain
- FAISS
- OpenAI in the current application version

> **Current implementation note:** The application source captured in this project uses OpenAI for embeddings and chat completion. Ollama is a planned cost-free/local-model evolution, not part of the currently documented working OpenAI implementation. AWS EKS/RDS is also a planned next environment; the verified deployment path documented here is MicroK8s.

---

## 1. Project Overview

### Problem Statement

Operational and business data often exists in PostgreSQL tables, but users need a natural-language interface to ask questions about that data.

A traditional application requires users to know:

- database schema
- table names
- SQL syntax
- column names
- joins and filters

This project introduces a RAG layer between the user and PostgreSQL.

The application:

1. Connects to PostgreSQL.
2. Reads tables from a selected schema.
3. Converts database rows into LangChain `Document` objects.
4. Generates embeddings.
5. Stores embeddings in a FAISS vector index.
6. Retrieves relevant documents for each question.
7. Sends retrieved context to the LLM.
8. Returns a grounded natural-language answer through Streamlit.

---

## 2. High-Level Architecture

```text
Developer
   |
   | git push
   v
GitHub Application Repository
   |
   v
Jenkins
   |
   | CI
   | - Checkout
   | - Build Docker image
   | - Authenticate to Docker Hub
   | - Push image
   v
Docker Hub
   |
   | image tag
   v
GitOps Repository
   |
   | Kubernetes manifests
   v
Argo CD
   |
   | Sync
   v
MicroK8s / Kubernetes
   |
   +-----------------------------+
   |                             |
   v                             v
Streamlit RAG Application     PostgreSQL
   |                             |
   |                             +-- PersistentVolumeClaim
   |
   +---- FAISS vector index
   |
   +---- LLM / embeddings
          |
          +---- OpenAI
```

The project architecture also includes Traefik/Gateway API routing and an observability stack with Prometheus and Grafana in the broader MicroK8s environment.

---

## 3. RAG Workflow

```text
PostgreSQL rows
      |
      v
Table discovery
      |
      v
Rows -> LangChain Documents
      |
      v
OpenAI Embeddings
      |
      v
FAISS Vector Store
      |
      v
Retriever
      |
      v
User Question
      |
      v
Retrieve relevant rows
      |
      v
Prompt = context + question
      |
      v
ChatOpenAI
      |
      v
Answer
```

The current code uses a retriever with `k=6`.

The prompt instructs the model to use only retrieved context and say that it does not know when the answer is not present in the context.

---

# 4. Technology Stack

| Layer | Technology |
|---|---|
| Application | Python |
| UI | Streamlit |
| RAG framework | LangChain |
| Database | PostgreSQL |
| Vector store | FAISS |
| Embeddings | OpenAI Embeddings |
| LLM | OpenAI Chat model |
| Containerization | Docker |
| Image builder | Kaniko |
| Image registry | Docker Hub |
| CI | Jenkins |
| CD / GitOps | Argo CD |
| Kubernetes | MicroK8s |
| Ingress / Gateway | Traefik / Gateway API |
| Monitoring | Prometheus + Grafana |
| Source control | GitHub |

The captured application dependency set includes `streamlit`, `langchain`, `langchain-core`, `langchain-community`, `langchain-openai`, `sqlalchemy`, `psycopg2-binary`, `faiss-cpu`, and `python-dotenv`.

---

# 5. Repository Structure

The project was separated into an application repository and a GitOps repository.

## Application repository

```text
postgress-rag/
└── postgress-rag/
    ├── app.py
    ├── main.py
    ├── Dockerfile
    ├── Jenkinsfile
    ├── Jenkinsfile_initial
    ├── pyproject.toml
    ├── requirements.txt
    ├── README.md
    └── uv.lock
```

## GitOps repository

```text
postgres-rag-gitops/
└── k8s/
    ├── namespace.yml
    ├── deployment.yml
    ├── service.yml
    └── argocd-application.yml
```

This separation is intentional:

- application repository = source code and CI
- GitOps repository = desired Kubernetes state and CD

---

# 6. Application Requirements

Python version specified by the project:

```text
Python >= 3.12
```

Dependencies:

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

# 7. Local Installation

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Optional environment defaults:

```bash
cp .env.example .env
```

Run the application:

```bash
streamlit run app.py
```

---

# 8. Application Configuration

The Streamlit sidebar exposes:

### PostgreSQL

```text
DB Host
DB Port
DB Name
DB User
DB Password
Schema
Rows per table to ingest
```

Default PostgreSQL port:

```text
5432
```

Default schema:

```text
public
```

Default row limit:

```text
5000
```

### OpenAI

```text
OpenAI API Key
Model
Embedding Model
```

Current defaults captured from the application:

```text
Model: gpt-4o-mini
Embedding Model: text-embedding-3-small
```

The OpenAI key is entered through the UI in the current implementation.

---

# 9. PostgreSQL Configuration

The verified MicroK8s PostgreSQL service was:

```text
postgres-rag-db
```

The Kubernetes service resolved to:

```text
10.152.183.177
```

Port:

```text
5432
```

Database:

```text
postgres_rag
```

User:

```text
postgres
```

Schema:

```text
public
```

The password is intentionally not documented here.

Never commit database passwords or API keys to Git.

---

# 10. PostgreSQL Kubernetes Deployment

The PostgreSQL deployment uses:

```text
postgres:16
```

The container listens on:

```text
5432
```

Database configuration is loaded from a Kubernetes Secret named:

```text
postgres-rag-db
```

Secret keys:

```text
POSTGRES_DB
POSTGRES_USER
POSTGRES_PASSWORD
```

Persistent storage is provided through:

```text
postgres-rag-pvc
```

The verified PVC was:

```text
postgres-rag-pvc
STATUS: Bound
CAPACITY: 5Gi
STORAGECLASS: microk8s-hostpath
```

---

# 11. PostgreSQL Data Validation

PostgreSQL was accessed using a temporary client pod.

Example:

```bash
psql -h postgres-rag-db -U postgres -d postgres_rag
```

Database/schema validation:

```sql
\dt
\dn

SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'public';
```

An empty database initially returned no relations.

Test data was then inserted into an `employees` table:

```sql
CREATE TABLE employees (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    role VARCHAR(100),
    department VARCHAR(100),
    location VARCHAR(100)
);
```

Example test data:

```sql
INSERT INTO employees (name, role, department, location)
VALUES
('Muskan Patel', 'DevOps Engineer', 'Engineering', 'India'),
('Afzal Ehsani', 'Senior DevOps Engineer', 'Platform', 'India'),
('Gulnar Khan', 'SRE Engineer', 'Infrastructure', 'India'),
('Rahul Mehta', 'DevOps Engineer', 'Engineering', 'India'),
('Neha Joshi', 'Software Engineer', 'Development', 'India');
```

Validation:

```sql
SELECT * FROM employees;
```

---

# 12. RAG Indexing Logic

The application calculates a table/row-count fingerprint.

The FAISS index is rebuilt when:

- no local index exists
- the table/row-count fingerprint changes
- a new table is detected
- data changes enough to change the fingerprint

If no documents are discovered, the application raises:

```text
No rows found in the selected schema/tables.
```

The FAISS index is saved locally.

The application then loads the index when the fingerprint has not changed.

---

# 13. RAG Chain

The current implementation uses:

```python
retriever = vectorstore.as_retriever(search_kwargs={"k": 6})
```

The LLM is currently:

```python
ChatOpenAI(
    model=model_name,
    temperature=0.0,
    api_key=api_key
)
```

The flow is:

```text
Question
   |
Retriever
   |
Relevant PostgreSQL-derived documents
   |
Prompt
   |
ChatOpenAI
   |
Answer
```

The prompt is designed to reduce hallucination by instructing the assistant to use only retrieved context.

---

# 14. Docker

The application is containerized with a Dockerfile.

The CI pipeline does not require Docker-in-Docker.

Instead, Jenkins dynamically creates a Kubernetes agent containing Kaniko.

Kaniko builds the image inside the Kubernetes environment.

This is useful because Kaniko can build container images without requiring a Docker daemon.

---

# 15. Jenkins CI

The Jenkins pipeline uses a Kubernetes dynamic agent.

The relevant Kaniko image is:

```text
gcr.io/kaniko-project/executor:v1.23.2-debug
```

The agent uses:

```yaml
hostNetwork: true
dnsPolicy: Default
```

The Kaniko container mounts:

```text
/kaniko/.docker
```

The Docker configuration is generated during the pipeline.

---

# 16. Docker Hub Authentication

Jenkins stores Docker Hub credentials under:

```text
dockerhub-creds
```

The pipeline obtains:

```text
DOCKER_USERNAME
DOCKER_PASSWORD
```

The credentials are converted into Docker Registry authentication:

```text
username:password
```

and Base64 encoded.

The resulting configuration is written to:

```text
/kaniko/.docker/config.json
```

The password is masked by Jenkins.

---

# 17. Image Build and Push

Kaniko uses:

```text
--context="$WORKSPACE"
```

and:

```text
--dockerfile="$WORKSPACE/Dockerfile"
```

The image is pushed using the Jenkins build number:

```text
docker.io/$DOCKER_USERNAME/postgres-rag:$BUILD_NUMBER
```

Example:

```text
docker.io/muskanpatel71198/postgres-rag:23
```

This makes every CI build uniquely identifiable.

---

# 18. GitOps CD

The desired Kubernetes state lives in:

```text
postgres-rag-gitops
```

Argo CD watches this repository.

The intended flow is:

```text
Application change
      |
      v
Jenkins CI
      |
      v
New Docker image
      |
      v
GitOps manifest image tag update
      |
      v
Git commit
      |
      v
Argo CD detects change
      |
      v
Argo CD sync
      |
      v
MicroK8s
```

---

# 19. Kubernetes Application

The application is deployed through a Kubernetes Deployment.

The application is exposed through a Kubernetes Service.

The verified service was:

```text
postgres-rag
```

Type:

```text
NodePort
```

Port:

```text
8501
```

NodePort:

```text
30861
```

The application can therefore be tested through the MicroK8s node address and NodePort when network access permits.

---

# 20. Kubernetes Storage

The MicroK8s cluster uses:

```text
microk8s-hostpath
```

as the default storage class.

Verified storage classes included:

```text
jenkins-pv
microk8s-hostpath
```

The PostgreSQL PVC used:

```text
microk8s-hostpath
```

and was successfully bound.

---

# 21. Argo CD

The GitOps repository contains:

```text
argocd-application.yml
```

Argo CD is responsible for:

- watching the GitOps repository
- detecting manifest changes
- comparing desired state with cluster state
- synchronizing Kubernetes resources
- maintaining Git as the declarative source of truth

---

# 22. Routing

The broader cluster environment uses Traefik and Gateway API concepts.

The architecture contains:

```text
Traefik
  |
Gateway API
  |
HTTPRoute
  |
Service
  |
Streamlit application
```

The environment also used Cloudflare Tunnel and a custom domain for external access.

---

# 23. Observability

The MicroK8s environment contains:

- Prometheus
- Grafana
- Alertmanager
- kube-state-metrics
- node exporter

These can be used to monitor:

- Kubernetes resources
- node health
- application availability
- resource utilization
- alerts

---

# 24. Security

Recommended controls:

1. Never commit API keys.
2. Never commit PostgreSQL passwords.
3. Store registry credentials in Jenkins Credentials.
4. Store database credentials in Kubernetes Secrets.
5. Use least-privilege credentials.
6. Use private registries where appropriate.
7. Restrict PostgreSQL network access.
8. Do not expose PostgreSQL directly to the public Internet.
9. Use HTTPS for external application access.
10. Rotate credentials regularly.
11. Avoid putting secrets into Docker images.
12. Use non-root application containers where supported.
13. Scan container images before production deployment.

---

# 25. Production Considerations

The current project is a strong DevOps lab / portfolio implementation, but a production deployment should additionally consider:

- managed PostgreSQL such as AWS RDS
- Kubernetes production cluster such as EKS
- highly available PostgreSQL
- external persistent storage
- centralized vector storage
- secret manager integration
- image vulnerability scanning
- automated tests
- resource requests/limits
- HPA
- PodDisruptionBudgets
- network policies
- TLS automation
- centralized logging
- distributed tracing
- backup and disaster recovery
- GitOps promotion between environments

---

# 26. Planned Cloud Migration

The project roadmap discussed includes:

```text
MicroK8s
   |
   v
Terraform
   |
   +-- AWS VPC
   +-- EKS
   +-- PostgreSQL RDS
```

The verified work in this documentation should not be confused with a completed EKS/RDS production migration.

---

# 27. Planned Ollama Migration

The current application calls OpenAI directly.

A cost-conscious future architecture can replace the external OpenAI dependency with Ollama:

```text
Streamlit
   |
   v
Ollama Service
   |
   +-- Local LLM
   |
   +-- Local embedding model
```

This requires both:

1. changing the model
2. changing the method used to call the model

It is not sufficient to replace only the model name because the current code uses OpenAI-specific LangChain classes.

---

# 28. Troubleshooting

## PostgreSQL hostname not resolving

Error:

```text
could not translate host name " postgres-rag-db" to address
```

Cause:

An extra leading space was entered in the DB Host field.

Correct:

```text
postgres-rag-db
```

Not:

```text
 postgres-rag-db
```

---

## PostgreSQL database does not exist

Error:

```text
FATAL: database "postgres-rag" does not exist
```

Cause:

The application was configured with the wrong database name.

The actual database created by the Kubernetes Secret was:

```text
postgres_rag
```

Fix:

```text
DB Name = postgres_rag
```

Validate:

```bash
kubectl get secret postgres-rag-db -n monitoring \
  -o jsonpath='{.data.POSTGRES_DB}' | base64 -d
```

---

## No rows found

Error:

```text
No rows found in the selected schema/tables.
```

Cause:

The database/schema was reachable, but there were no tables/rows to ingest.

Fix:

Create a table and insert data.

Example:

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'public';

SELECT * FROM employees;
```

---

## DNS failure while downloading tiktoken data

Error:

```text
HTTPSConnectionPool(host='openaipublic.blob.core.windows.net',
port=443): Max retries exceeded
...
NameResolutionError
```

Cause:

The application container could not resolve the external OpenAI tokenizer host.

This is a cluster/container DNS or external network-resolution problem, not a PostgreSQL problem.

Troubleshooting should include:

```bash
kubectl get pods -n kube-system
kubectl get svc -n kube-system
kubectl logs -n kube-system <coredns-pod>
```

and external DNS connectivity checks from the application pod.

---

## OpenAI 429 quota error

Error:

```text
Error code: 429
insufficient_quota
credit_balance_exhausted
```

Cause:

The OpenAI account had no remaining API credits.

This is an API billing/quota issue, not a Kubernetes issue.

Possible architectural response:

- add API credits
- use an alternative model provider
- migrate to a locally hosted model such as Ollama

---

## Jenkins agent offline

Observed messages included:

```text
Agent ... is offline
```

and:

```text
seems to be removed or offline
```

The Kubernetes Jenkins plugin dynamically creates agent pods. Agent availability depends on successful JNLP/WebSocket communication between the agent and Jenkins controller.

Troubleshooting:

```bash
kubectl get pods -n monitoring
kubectl describe pod <jenkins-agent-pod> -n monitoring
kubectl logs <jenkins-agent-pod> -n monitoring -c jnlp
```

---

## Jenkins Git tool warning

Observed:

```text
Selected Git installation does not exist. Using Default
The recommended git tool is: NONE
```

In the captured run, Jenkins still successfully executed Git operations.

This was therefore a configuration warning rather than the immediate cause of the pipeline failure.

---

# 29. Useful Validation Commands

## Nodes

```bash
kubectl get nodes -o wide
```

## Pods

```bash
kubectl get pods -n monitoring
```

## PostgreSQL pods

```bash
kubectl get pods -n monitoring | grep postgres
```

## Services

```bash
kubectl get svc -n monitoring
```

## PVCs

```bash
kubectl get pvc -n monitoring
```

## Storage classes

```bash
kubectl get storageclass
```

## PostgreSQL deployment

```bash
kubectl get deployment postgres-rag-db -n monitoring -o yaml
```

## PostgreSQL logs

```bash
kubectl logs deployment/postgres-rag-db -n monitoring
```

## DNS resolution from application

```bash
kubectl exec -it <app-pod> -n monitoring -- sh
getent hosts postgres-rag-db
```

Python DNS check:

```bash
kubectl exec <app-pod> -n monitoring -- \
python -c "import socket; print(socket.gethostbyname('postgres-rag-db'))"
```

---

# 30. End-to-End Verification Checklist

```text
[ ] GitHub repository exists
[ ] Application builds locally
[ ] Dockerfile works
[ ] PostgreSQL is running
[ ] PostgreSQL Secret exists
[ ] PostgreSQL PVC is Bound
[ ] PostgreSQL service resolves
[ ] Database exists
[ ] Tables exist
[ ] Tables contain rows
[ ] Application connects to PostgreSQL
[ ] Embeddings can be generated
[ ] FAISS index is created
[ ] RAG retrieval works
[ ] LLM responds
[ ] Jenkins checks out code
[ ] Kaniko builds image
[ ] Image is pushed to Docker Hub
[ ] GitOps repository contains manifests
[ ] Argo CD detects desired state
[ ] Argo CD synchronizes
[ ] Application pod is Ready
[ ] Service exposes Streamlit
[ ] External routing works
[ ] Monitoring is available
```

---

# 31. Interview Summary

A concise interview explanation:

> "I built a PostgreSQL-backed RAG chatbot using Streamlit and LangChain. The application reads relational data from PostgreSQL, converts rows into documents, creates embeddings, stores them in a FAISS vector index, retrieves relevant context, and generates grounded answers using an LLM. I containerized the application and implemented CI using Jenkins with dynamic Kubernetes agents and Kaniko to build and push Docker images without Docker-in-Docker. For CD, I separated the Kubernetes manifests into a GitOps repository and used Argo CD to synchronize the desired state into MicroK8s. I also integrated Kubernetes persistent storage for PostgreSQL and worked through real production-style issues involving DNS, PostgreSQL database configuration, empty datasets, Jenkins agent connectivity, image builds, and LLM API quota."

---

# 32. Project Outcome

The project demonstrates:

- application development
- RAG architecture
- PostgreSQL integration
- containerization
- Kubernetes
- persistent storage
- Jenkins CI
- Kaniko image builds
- Docker Registry
- GitOps
- Argo CD
- MicroK8s
- Traefik/Gateway API
- Prometheus/Grafana
- troubleshooting
- production-oriented DevOps practices