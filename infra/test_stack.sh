#!/usr/bin/env bash
# Basic end-to-end tests for Traefik + Qdrant + Ollama fronted over HTTPS.
# Exits non-zero if any test fails.

# Note: to test remotely, add HOSTNAME_LOCAL=<server>.local in .env

set -u -o pipefail

source .env

# -------- Config --------
HOSTNAME_LOCAL="${HOSTNAME_LOCAL:-$(hostname).local}"  # can ovverride in .env
CURRENT_HOST="$(hostname).local"
PORT="${PORT:-4443}"
BASE="https://${HOSTNAME_LOCAL}:${PORT}"
CERT_DIR="./certs"
CERT_PATH="${CERT:-${CERT_DIR}/${HOSTNAME_LOCAL}.pem}"
KEY_PATH="${KEY:-${CERT_DIR}/${HOSTNAME_LOCAL}.key.pem}"

# Header names/values
QDRANT_HEADER_FIELD_NAME_OPENAI="api-key"
QDRANT_API_KEY="${QDRANT_API_KEY:-}"
OLLAMA_HEADER_FIELD_NAME_OPENAI="Authorization"
OLLAMA_HEADER_FIELD_VALUE_PREFIX="Bearer "
OLLAMA_API_KEY="${OLLAMA_API_KEY:-}"
OLLAMA_HEADER_FIELD_NAME_AZURE="api-key"

# curl flags (self-signed)
CURL_COMMAND='curl -sS -k -o /dev/null -w %{http_code}'

# Pretty output
GREEN=$'\e[32m'; RED=$'\e[31m'; NC=$'\e[0m'
pass() { echo "${GREEN}PASS${NC}  $*"; }
fail() { echo "${RED}FAIL${NC}  $*"; FAILED=1; }

# Assume server if HOSTNAME_LOCAL matches CURRENT_HOST, else assume client
IS_SERVER=false
if [[ "$CURRENT_HOST" == "$HOSTNAME_LOCAL" ]]; then
  IS_SERVER=true
fi

FAILED=0

# -------- Show the environment -------
echo "== CONFIGURATION =="
echo "HOSTNAME_LOCAL: ${HOSTNAME_LOCAL}"
echo "CURRENT_HOST: ${CURRENT_HOST}"
echo "IS_SERER=${IS_SERVER}"
echo "PORT=${PORT}"
echo "BASE=${BASE}"
echo "CERT_DIR=${CERT_DIR}"
echo

# -------- Show the environment -------
echo "== Environment (from .env) =="
echo "OLLAMA_API_KEY: ${OLLAMA_API_KEY}"
echo "QDRANT_API_KEY: ${QDRANT_API_KEY}"
echo

# -------- Expected directories -------
echo "== Expected Paths =="
echo "CERT_DIR: ${CERT_DIR}"
echo "CERT_PATH: ${CERT_PATH}"
echo "KEY_PATH: ${KEY_PATH}"
echo

# -------- Authentication formats -------
echo "== Authentication Header Formats =="
echo "qdrant: {${QDRANT_HEADER_FIELD_NAME_OPENAI}: ${OLLAMA_API_KEY}}"
echo "ollama (openapi): {${OLLAMA_HEADER_FIELD_NAME_OPENAI}: ${OLLAMA_HEADER_FIELD_VALUE_PREFIX}${OLLAMA_API_KEY}}"
echo "ollama (azure): {${OLLAMA_HEADER_FIELD_NAME_AZURE}: ${OLLAMA_API_KEY}}"
echo


# -------- Precheck (env + certs) --------
echo "== Precheck =="
if [[ -z "${OLLAMA_API_KEY}" ]]; then
  fail "OLLAMA_API_KEY not set. Run ./authgen.sh"
else
  pass "OLLAMA_API_KEY present"
fi

if [[ -z "${QDRANT_API_KEY}" ]]; then
  fail "QDRANT_API_KEY not set. Run ./authgen.sh"
else
  pass "QDRANT_API_KEY present"
fi

if [[ -f "${CERT_PATH}" ]]; then
  pass "Cert present: ${CERT_PATH}"
else
  fail "Missing cert: ${CERT_PATH}. Run ./certgen.sh"
fi

# Private cert key should exist on server and should not exist on client
if $IS_SERVER; then
  if [[ -f "$KEY_PATH" ]]; then
    pass "Server cert key present: ${KEY_PATH}"
  else
    fail "Server missing cert key: ${KEY_PATH}. Run ./certgen.sh"
  fi
else
  if [[ -f "$KEY_PATH" ]]; then
    fail "Client should NOT have cert key: ${KEY_PATH} (security violation)"
  else
    pass "Client has no cert key (expected)"
  fi
fi
# -------- Helpers --------

# Add quotes to args for printing purposes (since $var[*] collapses them)
quote_args() {
  local out=()
  for arg in "$@"; do
    # Add single quotes around each arg, escaping any single quotes inside
    out+=("'${arg//\'/\'\\\'\'}'")
  done
  printf '%s ' "${out[@]}"
}

# check curl response for expected code
expect_code() {
  local test_name="$1" # test description
  local expected_codes_csv="$2" # HTTP code(s) expected, comma separated
  shift 2
  local curl_args=("$@") # curl arguments (including URLs, headers, etc.)

  local http_response="" # what curl printed on exit code 0
  local exit_code=0      # curls own exit code (may be 0 even if auth fails)
  local curl_command_print="" # what is actually printed, including line breaks/delimiters, for easy copy/paste
  local quiet_mode=0 # if true, do not print the command

  # Run curl: with -w "%{http_code}" this prints the status code
  http_response="$($CURL_COMMAND "${curl_args[@]}" 2>/dev/null)"
  exit_code=$?

  # optional and careful printing of exact curl command for copy/paste or validation
  if [[ $quiet_mode -eq 0 ]]; then
      local curl_args_quoted="" # a print-friendly version of curl args
      local curl_command_full="" # full command run
      local curl_command_delimiter=" :: " # simple inline
      # ensure args to curl are properly quoted for printing
      curl_args_quoted="$(quote_args "${curl_args[@]}")"
      # construct full command, without eating spaces
      printf -v curl_command_full '%s %s' "${CURL_COMMAND}" "${curl_args_quoted}"
      #curl_command_full="$(printf '%s %s' ${CURL_COMMAND} ${curl_args_quoted})"
      # delimiter with newline
      # Warning: this is done carefully to keep it working with printf
      curl_command_delimiter=$', command:\n    '
      # curl_command_full should already be a single string (e.g., from quote_args)
      # Build the printable block WITHOUT word-splitting/globbing:
      printf -v curl_command_print '%s%s' "$curl_command_delimiter" "$curl_command_full"
  else
      # Print nothing
      curl_command_print=""
  fi

  if [[ $exit_code -eq 0 ]]; then
    # curl process did not fail → compare HTTP response code
    if [[ ",${expected_codes_csv}," == *",$http_response,"* ]]; then
      pass "${test_name} (HTTP ${http_response})${curl_command_print}"
    else
      fail "${test_name} (got HTTP ${http_response}, expected ${expected_codes_csv})${curl_command_print}"
    fi
  else
    # curl process failed (no HTTP response produced)
    fail "${test_name} (curl exit ${exit_code}, no HTTP response)${curl_command_print}"

  fi
}


echo
echo "== Connectivity & Auth =="
# 6) Qdrant readyz (PUBLIC): expect 200 WITHOUT header
expect_code "Qdrant /readyz (no header, should be public 200)" "200" \
  "${BASE}/qdrant/readyz"

# 7) Qdrant auth ENFORCEMENT: use /collections (NOT /readyz)
#    - Without key: 401
#    - With wrong key: 401
#    - With correct key: 200 (empty DB => {"collections":[]})
expect_code "Qdrant /collections (no header, expect 401)" "401" \
  "${BASE}/qdrant/collections"

expect_code "Qdrant /collections (bad key, expect 401)" "401" \
  -H "${QDRANT_HEADER_FIELD_NAME_OPENAI}: BADKEY" \
  "${BASE}/qdrant/collections"

expect_code "Qdrant /collections (valid key, expect 200)" "200" \
  -H "${QDRANT_HEADER_FIELD_NAME_OPENAI}: ${QDRANT_API_KEY}" \
  "${BASE}/qdrant/collections"

# 8) Ollama behind Traefik with Qdrant-style api-key on router:
#    - Without key: router should NOT match -> 404 (Traefik)
#    - With bad key: still no match -> 404 (Traefik)
#    - With correct key: 200
expect_code "Ollama /api/tags (no header, expect 404)" "404" \
  "${BASE}/ollama/api/tags"

expect_code "Ollama /api/tags (bad key, expect 404)" "404" \
  -H "${OLLAMA_HEADER_FIELD_NAME_OPENAI}: Bearer BADKEY" \
  "${BASE}/ollama/api/tags"

# The openapi format {Authorization: Bearer OLLAMA_API_KEY} should work
expect_code "Ollama /api/tags (openapi format, valid key, expect 200)" "200" \
  -H "${OLLAMA_HEADER_FIELD_NAME_OPENAI}: ${OLLAMA_HEADER_FIELD_VALUE_PREFIX}${OLLAMA_API_KEY}" \
  "${BASE}/ollama/api/tags"
# The azure format {api-key: OLLAMA_API_KEY} should work too
expect_code "Ollama /api/tags (azure format, valid key, expect 200)" "200" \
  -H "${OLLAMA_HEADER_FIELD_NAME_AZURE}: ${OLLAMA_API_KEY}" \
  "${BASE}/ollama/api/tags"

# Pull ollama model
expect_code "Ollama /api/pull qwen2.5:1.5b-instruct (expect 200)" "200" \
  -H "Authorization: Bearer ${OLLAMA_API_KEY?}" \
  -H "Content-Type: application/json" \
  -X POST "https://storage.local:4443/ollama/api/pull" \
  -d '{"name":"qwen2.5:1.5b-instruct","stream":false}'

# Perform ollama query
expect_code "Ollama /v1/chat/completions inference (expect 200)" "200" \
  -H "${OLLAMA_HEADER_FIELD_NAME_OPENAI}: ${OLLAMA_HEADER_FIELD_VALUE_PREFIX}${OLLAMA_API_KEY}" \
  -H "Content-Type: application/json"   \
  -X POST "https://storage.local:4443/ollama/v1/chat/completions"  \
  -d '{"model":"qwen2.5:1.5b-instruct","messages":[{"role":"user","content":"Say hello from Ollama."}], "stream": false}'

echo
if [[ $FAILED -ne 0 ]]; then
  echo "${RED}One or more checks FAILED.${NC}"
  exit 1
else
  echo "${GREEN}All checks passed.${NC}"
  exit 0
fi
