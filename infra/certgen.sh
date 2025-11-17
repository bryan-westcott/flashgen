#!/usr/bin/env bash
# Generate a self-signed cert for <hostname>.local into ./certs (or $OUT)
# Usage: CERT_DAYS=365 OUT=./certs ./certgen.sh

set -Eeuo pipefail

# 0) prerequisites
command -v openssl >/dev/null 2>&1 || { echo "[certgen] ERROR: openssl not found in PATH"; exit 1; }

# 1) inputs
SERVER_HOSTNAME="$(hostname)"             # get simple hostname
SERVER_FQDN="${SERVER_HOSTNAME?}.local"   # the fqdn when using mDNS (hostname.local)
CN="${CN:-"${SERVER_FQDN}"}"              # Common Name + SAN (default: host mDNS)
OUT="${OUT:-"./certs"}"                   # Output directory
DAYS="${CERT_DAYS:-1095}"                 # Validity in days

echo "[certgen] SERVER_HOSTNAME=${SERVER_HOSTNAME?} SERVER_FQDN=${SERVER_FQDN?}"
echo "[certgen] CN=${CN?} OUT=${OUT?} DAYS=${DAYS?}"

# 2) prepare
umask 077                                  # private perms by default
mkdir -p "${OUT}"

# 3a) upsert SERVER_FQDN to .env
#
touch .env
# delete any existing SERVER_FQDN (handles optional leading "export" + spaces)
sed -i.bak -E '/^[[:space:]]*(export[[:space:]]+)?SERVER_FQDN[[:space:]]*=/d' .env
# append the new value (quoted for safety)
printf 'SERVER_FQDN="%s"\n' "$SERVER_FQDN" >> .env

# 3b) generate key + cert (RSA 2048; adjust below if you prefer ECDSA)
KEY="${OUT}/${CN}.key.pem"
CRT="${OUT}/${CN}.pem"

echo "[certgen] KEY=${KEY?} CRT=${CRT?}"

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "${KEY}" \
  -out "${CRT}" \
  -days "${DAYS}" \
  -subj "/CN=${CN}" \
  -addext "subjectAltName=DNS:${CN}"

# 4) verify
openssl x509 -in "${CRT}" -noout -subject -enddate -ext subjectAltName

echo "[certgen] Validation passed"

# 5) optional convenience symlinks (Traefik defaults)
#    If you want stable filenames, uncomment these:
ln -sf "$(basename "${CRT}")" "${OUT}/lan.pem"
ln -sf "$(basename "${KEY}")" "${OUT}/lan-key.pem"

echo "[certgen] Wrote:"
echo "  cert: ${CRT}"
echo "  key : ${KEY}"
