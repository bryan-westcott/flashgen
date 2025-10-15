# ⚡ FlashGen

**FlashGen** is a lightweight, self-contained GenAI micro-stack for local or
small-team GenAI experiments. It runs **Ollama + Qdrant** behind a **Traefik**
reverse proxy with LAN-TLS, and includes a parallel `notebook/` folder showing
how to prompt it from Python/Jupyter like you would any LLM service.

Think of it as your **“GenAI-in-a-box”**: fast, local, secure, and easy to hack
on.

---

## 🌟 Features

- **One-command startup** — bring up Ollama, Qdrant, and Traefik with `docker compose up -d`.
- **Local TLS certificates** — script-generated `.local` certs for HTTPS and gRPC.
- **Secure proxying** — clean HTTPS endpoints for both REST and gRPC (443/8443).
- **Python-friendly** — the `notebook/` examples treat FlashGen like a remote LLM API (but it’s all local).
- **Minimal host deps** — everything runs in Docker.
- **Ollama API key** — not a native Ollama feature.
- **Extensible orchestration** — uses same Traefik reverse proxy as `k3s`/`k8s`.
- **Extensible TLS** — avoid self-signed certificates with registered domain.

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

Add `-k` only when testing self-signed certs.

### 4) Extended tests

If testing from remote client (on LAN):

- make certs subdirectory
  - `mkdir -p ./certs`
- copy `*.pem` from server to local `./certs`
- copy `.env` from server to PWD

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

5. Additional Tests

Note: tests can be run

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

## 📜 License

Apache 2.0
