#!/bin/bash

# Prep dev environment
# 1. check if sourcing
# 2. check for uv
# 3. check for pyproject.toml
# 4. check for active venv that matches project_root (not other repo)
# 5. create venv if it doesn't exist
# 6. activate venv if not already active
# 7. register environment as jupyter kernel

# This script must be sourced, so these checks are invalid
# shellcheck disable=SC2317,SC1091

# Ensure script is sourced, not executed
(return 0 2>/dev/null) || {
  echo "❌ This script must be sourced, not executed."
  echo "   Run it like this:  source dev-init.sh"
  exit 1
}

# Note: this has to be a subshell better trap error in the dev script itself
dev_init() {

  # Temporarily disable interactive history & file appends to avoid pollution
  set +o history

  # Save current options
  local old_opts
  old_opts=$(set +o)

  # Safely remove traps
  # Always restore options and history recording when this function exits
  # Note: will handle even if old_opts is unset (which can leave stale
  #       traps in bash otherwise)
  trap 'set +u; trap - RETURN ERR; [ "${old_opts+x}" ] && eval "$old_opts"; set -o history' RETURN

  # Set temp options
  # -u (nounset): treat unset variables as an error
  #   Example: echo "$FOO" when FOO is not set → causes immediate failure
  #   Helps catch typos and missing env vars early.
  set -u
  # -o pipefail: makes a pipeline fail if *any* command in it fails
  #   Default in Bash: only the *last* command in a pipeline matters.
  #   Example:
  #     false | true
  #   Without pipefail → exit code 0 (because 'true' succeeded).
  #   With pipefail   → exit code 1 (because 'false' failed).
  #
  #   This is useful when chaining commands with | where every stage matters.
  set -o pipefail

  # trap errors (assume sourced) to indicate dev-init problems
  # Note: trap persist until function succeeds and runs bottom "trap - ERR"
  trap 'echo "❌ Error in dev-init.sh at line $LINENO"; return 1' ERR

  # Resolve directory of this script, then its parent (the project root)
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  cd "$PROJECT_ROOT" || {
    echo "❌ Could not cd to $PROJECT_ROOT" >&2
    return 1 2>/dev/null || true
  }

  # Check for pyproject.toml
  PYPROJECT_FILE="${PROJECT_ROOT?}/pyproject.toml"
  if [ ! -f "$PYPROJECT_FILE" ]; then
    echo "❌ No pyproject.toml found in $PROJECT_ROOT, expected a minimal skeleton" >&2
    { return 1 2>/dev/null; } || exit 1
  fi


  # -- Check for notebook ---

  # check if notebook section in pyproject.toml
  if grep -q '^[[:space:]]*notebook[[:space:]]*=' "$PYPROJECT_FILE"; then
    echo "📓 Detected 'notebook' group in $PYPROJECT_FILE"
    HAS_NOTEBOOK=1
  else
    echo "ℹ️  No 'notebook' group found in $PYPROJECT_FILE; skipping Jupyter setup."
    HAS_NOTEBOOK=0
  fi

  # -- Initialize ---

  echo "📦 Dev init (create venv and/or sync as needed)"
  REPO_VENV=".venv"
  if [[ ! -d "$REPO_VENV" ]]; then
    echo "...❄️ No venv found at $REPO_VENV — cold start"
    if [[ ! -f "uv.lock" ]]; then
      echo "...🆕 No uv.lock found — creating venv first"
      # (Note: there's no '--dev' flag for 'uv venv'; dev/test deps are handled during 'uv sync')
      if ! uv venv "$REPO_VENV"; then
        echo "❌ Failed to create $REPO_VENV" >&2
        { return 1 2>/dev/null; } || exit 1
      fi
    else
      echo "...🔒 uv.lock found — will let 'uv sync' create venv implicitly"
    fi

    # One sync pass to populate venv (frozen if lock exists)
    UV_SYNC_ARGS=()
    [[ "${HAS_NOTEBOOK:-0}" -eq 1 ]] && UV_SYNC_ARGS+=(--group notebook)
    [[ -f uv.lock ]] && UV_SYNC_ARGS+=(--frozen)
    echo "🔄 Syncing with args: ${UV_SYNC_ARGS[*]}"
    uv sync "${UV_SYNC_ARGS[@]}"
    echo "...✅ Sync successful"

  else
    echo "...♻️  Venv exists at $REPO_VENV — reusing existing venv without syncing"
  fi

  # --- Activation phase ---
  #
  echo "⚡ Activating venv (if needed)"
  if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    # If a venv is already active, it must be the project .venv
    if [ "$(readlink -f -- "$VIRTUAL_ENV")" != "$(readlink -f -- "$REPO_VENV")" ]; then
      echo "❌ Active VIRTUAL_ENV differs from project .venv" >&2
      echo "    active: $VIRTUAL_ENV" >&2
      echo "    expect: $REPO_VENV" >&2
      { return 1 2>/dev/null; } || exit 1
    else
      echo "...🟢 Already active: $VIRTUAL_ENV"
    fi
  else
    if ! source "$REPO_VENV/bin/activate"; then
      echo "❌ Failed to activate $REPO_VENV" >&2
      { return 1 2>/dev/null; } || exit 1
    fi
    echo "...✅ Activated: $VIRTUAL_ENV"
  fi

  # --- Register jupyter notebook ---

  # register jupyter kernel, but only if notebook in pyproject.toml
  if [ "$HAS_NOTEBOOK" -eq 1 ]; then
    KERNEL_NAME="$(basename "$PROJECT_ROOT")"
    echo "🧠 Registering Jupyter kernel: ${KERNEL_NAME?}..."
    if ! uv run ipython kernel install \
          --user \
          --env VIRTUAL_ENV "$PROJECT_ROOT/.venv" \
          --name "${KERNEL_NAME?}" \
          --display-name "${KERNEL_NAME?}"
    then
      echo "❌ Kernel registration failed — possibly missing ipykernel or misconfigured .venv" >&2
      echo "   Try: uv sync --dev --group notebook" >&2
      { return 1 2>/dev/null; } || true  # prevent killing ssh if sourced
    fi
    echo "Warning: kernels persist outside of uv in '~/.local/share/jupyter/kernels/'"
    echo "Warning: kernels may collide if same project is initialized elsewhere"
    echo "Launch with: "
    echo "    uv run --with notebook jupyter lab"
    echo "Choose: '${KERNEL_NAME}' kernel"
    echo "Warning: jupyter bug may require click in file browser before kernel can be selected"
    echo "...✅ Registered jupyter kernel ${KERNEL_NAME}"
  else
    echo "...ℹ️  No notebook group detected — no kernel to add or register."
  fi

  # ---- Done ----

  echo "✅ Dev environment ready"
  # Note: trap will restore old opts and history recording

}

dev_init "$@"
