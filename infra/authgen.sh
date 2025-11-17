#!/usr/bin/env bash
# Create or update auth tokens

#!/usr/bin/env bash
set -Eeuo pipefail

ENV_FILE=".env"

# Generate a secure 32-byte base64 token
generate_token() {
  head -c 32 /dev/urandom | base64 | tr -d '\n'
}

# Create .env if missing
if [ ! -f "$ENV_FILE" ]; then
  echo "[authgen] Creating new .env"
  touch "$ENV_FILE"
fi

# Helper to update or insert a key in-place
update_or_insert() {
  local key="$1"
  local current_val
  current_val=$(grep -E "^${key}=" "$ENV_FILE" | cut -d= -f2- || true)

  if [ -n "$current_val" ]; then
    echo "[authgen] $key is already set."
    read -rp "  Overwrite? (y/N) " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      new_val=$(generate_token)
      sed -i "s|^${key}=.*|${key}=${new_val}|" "$ENV_FILE"
      echo "[authgen] $key updated."
    else
      echo "[authgen] Skipped $key."
    fi
  else
    new_val=$(generate_token)
    echo "${key}=${new_val}" >> "$ENV_FILE"
    echo "[authgen] $key added."
  fi
}

# Prompt + set
update_or_insert "OLLAMA_API_KEY"
update_or_insert "QDRANT_API_KEY"

echo "[authgen] Done. .env is up to date ✅"
