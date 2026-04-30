#!/usr/bin/env bash
# =============================================================================
# setup.sh — Main Entrypoint
# your-local-agent | github.com/you/your-local-agent
#
# Run this once to set up your fully local AI coding agent.
# No cloud. No API keys. No cost.
#
# Usage:
#   bash setup.sh
#
# Or via curl (one-liner install):
#   curl -fsSL https://raw.githubusercontent.com/noelps-git/your-local-agent/main/setup.sh | bash
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------

REPO_URL="https://github.com/noelps-git/your-local-agent"
RAW_BASE="https://raw.githubusercontent.com/noelps-git/your-local-agent/main"
LOCAL_AI_DIR="${HOME}/.local-ai"
LOG_FILE="${LOCAL_AI_DIR}/setup.log"
INSTALL_DIR="${HOME}/.local-ai/repo"

# -----------------------------------------------------------------------------
# Logging helpers
# -----------------------------------------------------------------------------

mkdir -p "$LOCAL_AI_DIR"

log()     { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
info()    { echo "  $*";         log "INFO  $*"; }
warn()    { echo "  ⚠️  $*";    log "WARN  $*"; }
fail()    { echo "  ❌  $*";    log "ERROR $*"; exit 1; }
ok()      { echo "  ✅  $*";    log "OK    $*"; }
section() { echo ""; echo "▶ $*"; echo ""; log "SECTION --- $* ---"; }

# -----------------------------------------------------------------------------
# Banner
# -----------------------------------------------------------------------------

print_banner() {
  clear
  echo ""
  echo "  ╔═══════════════════════════════════════════╗"
  echo "  ║         your-local-agent  v1.0.0          ║"
  echo "  ║   Local AI assistant. No cloud. No cost.  ║"
  echo "  ╚═══════════════════════════════════════════╝"
  echo ""
  echo "  This script will:"
  echo "  1. Detect your system (RAM, chip, disk)"
  echo "  2. Install Homebrew, Llama.cpp, Node.js, Pi"
  echo "  3. Download the right AI model for your Mac"
  echo "  4. Configure everything and set up aliases"
  echo "  5. Run verification to confirm it all works"
  echo ""
  echo "  Full log: ${LOG_FILE}"
  echo ""
  echo "  Press Enter to begin or Ctrl+C to cancel."
  printf "  > "
  read -r
  echo ""
  log "====== Setup started ======"
}

# -----------------------------------------------------------------------------
# Resolve script directory
# Handles both: cloned repo (lib/ exists) and curl pipe (download libs)
# -----------------------------------------------------------------------------

resolve_lib_dir() {
  # If running from a cloned repo, lib/ should be next to setup.sh
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"

  if [[ -n "$script_dir" && -d "${script_dir}/lib" ]]; then
    LIB_DIR="${script_dir}/lib"
    MODELS_JSON="${script_dir}/models.json"
    info "Running from cloned repo at ${script_dir}"
  else
    # Running via curl pipe — download lib files to install dir
    download_lib_files
    LIB_DIR="${INSTALL_DIR}/lib"
    MODELS_JSON="${INSTALL_DIR}/models.json"
  fi

  export LIB_DIR
  export MODELS_JSON
}

# -----------------------------------------------------------------------------
# Download lib files when running via curl pipe
# -----------------------------------------------------------------------------

download_lib_files() {
  section "Downloading Setup Files"

  info "Downloading your-local-agent setup files..."
  mkdir -p "${INSTALL_DIR}/lib"

  local files=(
    "lib/detect.sh"
    "lib/install.sh"
    "lib/download.sh"
    "lib/configure.sh"
    "lib/verify.sh"
    "models.json"
  )

  for file in "${files[@]}"; do
    local url="${RAW_BASE}/${file}"
    local dest="${INSTALL_DIR}/${file}"

    mkdir -p "$(dirname "$dest")"

    if curl -fsSL "$url" -o "$dest" 2>/dev/null; then
      ok "Downloaded ${file}"
    else
      fail "Failed to download ${file} from ${url}. Check your internet connection and try again."
    fi
  done

  # Restrict permissions — scripts should not be world-writable
  chmod 750 "${INSTALL_DIR}/lib/"*.sh
  chmod 640 "${INSTALL_DIR}/models.json"

  ok "All setup files downloaded to ${INSTALL_DIR}"
}

# -----------------------------------------------------------------------------
# Source a module and run it
# Captures its exported variables into current shell
# -----------------------------------------------------------------------------

run_module() {
  local module_name="$1"
  local module_path="${LIB_DIR}/${module_name}"

  if [[ ! -f "$module_path" ]]; then
    fail "Module not found: ${module_path}. Your installation may be incomplete. Run setup again."
  fi

  chmod +x "$module_path"

  # Source so exported variables persist into this shell session
  # shellcheck source=/dev/null
  source "$module_path"
}

# -----------------------------------------------------------------------------
# Trap — catch unexpected exits and give useful message
# -----------------------------------------------------------------------------

trap_exit() {
  local exit_code=$?
  if [[ "$exit_code" -ne 0 ]]; then
    echo ""
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Setup exited unexpectedly (code: ${exit_code})"
    echo ""
    echo "  Check the log for details:"
    echo "    cat ${LOG_FILE}"
    echo ""
    echo "  Setup is safe to re-run — it will skip"
    echo "  steps that already completed successfully."
    echo ""
    echo "  Need help? Open an issue:"
    echo "    ${REPO_URL}/issues"
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log "Setup exited with code ${exit_code}"
  fi
}

trap trap_exit EXIT

# -----------------------------------------------------------------------------
# Interrupt handler — clean up server if user Ctrl+C during verify
# -----------------------------------------------------------------------------

trap_interrupt() {
  echo ""
  warn "Setup interrupted by user."
  pkill -f "llama-server" 2>/dev/null || true
  log "Setup interrupted by user"
  exit 1
}

trap trap_interrupt INT TERM

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
  print_banner

  # Resolve lib directory — cloned or curl
  resolve_lib_dir

  # Step 1 — Detect system
  section "Step 1 of 5 — System Detection"
  run_module "detect.sh"

  # Step 2 — Install dependencies
  section "Step 2 of 5 — Installing Dependencies"
  run_module "install.sh"

  # Step 3 — Download model
  section "Step 3 of 5 — Model Download"
  run_module "download.sh"

  # Step 4 — Configure
  section "Step 4 of 5 — Configuration"
  run_module "configure.sh"

  # Step 5 — Verify
  section "Step 5 of 5 — Verification"
  run_module "verify.sh"

  # Done
  echo ""
  echo "  ╔═══════════════════════════════════════════╗"
  echo "  ║           Setup Complete! 🎉              ║"
  echo "  ╚═══════════════════════════════════════════╝"
  echo ""
  echo "  Restart your terminal, then run:"
  echo ""
  echo "    local-ai-start"
  echo ""
  echo "  That's it. Your local agent is ready."
  echo ""
  echo "  Commands:"
  echo "    local-ai-start    → start server and launch Pi"
  echo "    local-ai-stop     → stop the server"
  echo "    local-ai-status   → check server health"
  echo "    local-ai-info     → show model and server info"
  echo "    local-ai-update   → update to latest version"
  echo ""
  echo "  Full log: ${LOG_FILE}"
  echo "  Repo    : ${REPO_URL}"
  echo ""
  log "====== Setup completed successfully ======"
}

main
