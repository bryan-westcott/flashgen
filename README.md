# ⚡ FlashGen

**FlashGen** is a lightweight, self-contained GenAI micro-stack for local or
small-team GenAI experiments. It runs **Ollama + Qdrant** behind a **Traefik**
reverse proxy with LAN-TLS, and includes a parallel `notebook/` folder showing
how to prompt it from Python/Jupyter like you would any LLM service.

Think of it as your **“GenAI-in-a-box”**: fast, local, secure, and easy to hack
on.

---

## 🌟 Features

### Core system
- **One-command startup** — bring up Ollama, Qdrant, and Traefik with `docker compose up -d`.
- **Everything runs locally** — no external dependencies; fully self-contained in Docker.
- **Local TLS certificates** — script-generated `.local` certs for HTTPS and gRPC.

### Structured-query + API compatibility
- **Structured-Query Backend (OpenAI-compatible)** — exposes Ollama through an OpenAI-style `/v1` API, enabling structured queries, function calling, tools, and agentic workflows locally.
- **Drop-in for OpenAI/Gemini clients** — usable through the `openai` Python package via `OpenAI(base_url=...)`, making FlashGen behave like a self-hosted LLM endpoint for RAG pipelines, agents, and tool-calling integrations.
- **Python-friendly notebooks** — the `notebook/` folder demonstrates how to call FlashGen exactly like a hosted LLM service (chat, embeddings, functions, etc.).

### Security + routing
- **Secure proxying** — clean HTTPS endpoints for both REST and gRPC (443/8443), fronted by Traefik.
- **Ollama API key support** — implemented via Traefik authentication (not natively supported by Ollama).
- **Extensible TLS** — supports swapping `.local` certs for real domain certificates.

### Orchestration + extensibility
- **Extensible orchestration** — Traefik layout matches patterns used in `k3s` / `k8s`, making migration easy.
- **Minimal host dependencies** — Docker + Compose is all you need.

---

## 🤔 Why FlashGen instead of Ollama alone or third-party services?

- **Secure, production-like API surface** — FlashGen layers TLS, API keys, and a clean OpenAI-style `/v1` endpoint over Ollama. This enables structured queries, function calling, and agent workflows that plain Ollama cannot support.

- **Local RAG stack included** — Qdrant is bundled and exposed securely, giving you embeddings, search, and retrieval without external services.

- **Cost, privacy, and control** — Everything runs on your LAN, avoiding cloud usage fees, rate limits, and data leakage concerns.

- **Faster iteration** — Local inference + local vector DB = minimal latency and full reproducibility.

- **Easy to extend or scale** — The stack is fully containerized and uses Traefik patterns compatible with `k3s`/`k8s`, allowing seamless growth from a single-node lab setup to multi-service or cluster deployments.


---

## 🚀 Quickstart

### 1) Generate a local TLS certificate (do this once per server)

```bash
./certgen.sh
```

Creates:

- `./certs/<hostname>.local.pem` — certificate
- `./certs/<hostname>.local.key.pem` — private key
- `./certs/lan.pem` and `lan-key.pem` — Traefik symlinks

---

### 1) Generate OLLAMA and QDRANT API Keys (do this once per server)

```bash
./authgen.sh
```

Writes to (`.env`):

- `OLLAMA_API_KEY` - API key used to access Ollama (authenticated by Traefik)
- `QDRANT_API_KEY` - API key used to access Qdrant
- `SERVER_FQDN` - the server name used (e.g., `<my_flashgen_server>.local`
- `./certs/<hostname>.local.pem` — certificate
- `./certs/<hostname>.local.key.pem` — private key
- `./certs/lan.pem` and `lan-key.pem` — Traefik symlinks

Note: Ollama does not support API keys, so this is authenticated via
Traefik and transport-protected via TLS.

---

### 2) Start the stack

```bash
docker compose up -d
```

You’ll have:

- Ollama: `https://<hostname>.local/ollama/api/`
- Qdrant: `https://<hostname>.local/qdrant/`
- gRPC over TLS: 443 and 8443

---

### 3) Smoke test

```bash
curl -k https://$(hostname).local/ollama/api/tags
curl -k https://$(hostname).local/qdrant/collections
```

---

Add `-k` only when testing self-signed certs.

### 4) Extended tests

```bash
./test_stack.sh
```

---

### 5) Python call (without global trust on local LAN)

**NOTE:** In most cases it is **not** necessary to install and trust the CA
bundle system-wide. A more secure local approach is to verify with a specific
CA bundle per client (e.g., `<my_flashgen_server>.local`):

```python
def self_signed_client(ollama_api_key: str, flashgen_server_name: str, ollama_port: int=4443) -> OpenAI:
    import httpx
    from openai import OpenAI
    ca_bundle = f'{flashgen_server_name}.crt'
    base_url = f'{flashgen_server_name}:{ollama_port}/ollama/v1/'
    http_client = httpx.Client(verify=ca_bundle)
    ollama_client = OpenAI(
            api_key=ollama_api_key,
            base_url=base_url,
            http_client=http_client
    return ollama_client
)
```

This pattern pins your client to the exact certificate/CA you intend to trust
for this service, avoiding broad OS-level trust.

---

## 📓 Using from Python/Jupyter

See the `notebook/` folder for examples that:

- Create an HTTPS client pinned to your FlashGen cert
- Call the Ollama-compatible API as if it were a hosted LLM
- Store/query vectors in Qdrant for RAG workflows

To start the notebook:

- Activate the environment (and register Jupiter kernel) with:
  - `source dev-scripts/dev-init.sh`
- Start Jupiter
  - `uv run --with notebook jupyter lab`
- Select the `flashgen` kernel (registered by dev-init):
  - Note: you may have to click on file are due to Jupiter bug

---

## 🧠 What’s inside

- **Ollama** — lightweight local LLM runtime (pull, run, and manage models)
- **Qdrant** — vector DB (embeddings, similarity search, RAG context)
- **Traefik** — reverse proxy (HTTPS routes, cert handling, clean paths)

Together they provide a production-like dev environment for building and testing RAG pipelines.

---

## 💡 Tips & gotchas

- Use the same `hostname.local` everywhere so cert CN/SANs match.
- Resolving `<hostname>.local` requires mDNS, check it with ping
- For LAN-wide use, generate one cert/CA and distribute only the needed client bundle(s).

---

## ✅ Requirements

- Docker + Docker Compose v2
- Linux or macOS (Windows via WSL2 not tested)
- A resolvable `<hostname>.local` on your LAN

---

## ⚠️ Responsible Use of Generative AI

This project includes tools that may generate text, code, images, or other outputs using machine-learning models.  
Generated outputs may be inaccurate, biased, unsafe, or inappropriate for production use without careful human review.

You are responsible for independently evaluating, validating, and verifying all outputs before any use or deployment.  
Do not rely on generated content for decisions that could cause harm, violate laws, infringe rights, or create unsafe conditions.

We encourage all users to follow responsible and ethical AI practices, consistent with guidelines published by major AI research organizations.  
In particular, users should avoid using this software or generated outputs to:

- cause harm to people, property, or the environment  
- enable deception, misinformation, or malicious manipulation  
- engage in illegal activity or support abusive or exploitative behavior  
- perform high-risk or critical tasks (e.g., medical, financial, legal, safety-critical systems) where errors could lead to serious consequences  

This project does not provide any warranties regarding the accuracy, safety, reliability, or suitability of generated content for any purpose.


---

## 📜 License

Apache 2.0, see LICENSE and NOTICE files.
