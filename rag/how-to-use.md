## HOW TO USE

### 1. Generate TLS certificate

```bash
./certgen.sh
```

Creates:

- `./certs/<hostname>.local.pem` — certificate
- `./certs/<hostname>.local.key.pem` — private key
- `./certs/lan.pem` and `lan-key.pem` — symlinks for Traefik

---

### 2. Trust the certificate (optional)

**Ubuntu:**

```bash
sudo cp ./certs/lan.pem /usr/local/share/ca-certificates/lan.crt
sudo update-ca-certificates
```

**macOS:**

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ./certs/lan.pem
```

---

### 3. Start the stack

```bash
docker compose up -d
```

---

### 4. Test endpoints

**Ollama (REST):**

```bash
curl -k https://$(hostname).local/ollama/api/tags
```

**Qdrant (REST):**

```bash
curl -k https://$(hostname).local/qdrant/collections
```

**Qdrant (gRPC via HTTPS on port 443):**

```bash
grpcurl -insecure -authority $(hostname).local \
  $(hostname).local:443 qdrant.SnapshotService/List
```

**Qdrant (pure gRPC on port 8443):**

```bash
grpcurl -insecure -authority $(hostname).local \
  $(hostname).local:8443 qdrant.SnapshotService/List
```

---

### 5. Minimal working example

```bash
curl -k https://$(hostname).local/qdrant/collections
curl -k https://$(hostname).local/ollama/api/tags
```
