#!/usr/bin/env bash
# =============================================================================
# install.sh — Dependency Installation Module
# your-local-agent | github.com/noelps-git/your-local-agent
#
# Installs Homebrew, Llama.cpp (via GitHub releases binary),
# Python 3.11, pipx, and Aider coding agent.
#
# Fixes applied from live debugging:
# - Uses GitHub releases binary for Llama.cpp (not Homebrew)
# - Handles .tar.gz macOS assets (not .zip)
# - Uses mktemp + mv for extension (macOS mktemp limitation)
# - Uses python@3.11 pinned (Python 3.14 breaks numpy/aider)
# - Uses pipx for Aider (avoids externally-managed-environment error)
# - Uses `hf` CLI instead of deprecated `huggingface-cli`
# - Handles ggml-org GitHub API URL correctly
# - Skips install steps if already present (idempotent)
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Logging helpers
# -----------------------------------------------------------------------------

LOG_FILE="${HOME}/.local-ai/setup.log"
mkdir -p "$(dirname "$LOG_FILE")"

log()     { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
info()    { echo "  $*";      log "INFO  $*"; }
warn()    { echo "  ⚠️  $*";  log "WARN  $*"; }
fail()    { echo "  ❌  $*";  log "ERROR $*"; exit 1; }
ok()      { echo "  ✅  $*";  log "OK    $*"; }
section() { echo ""; echo "▶ $*"; echo ""; log "SECTION $*"; }

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------

LOCAL_AI_DIR="${HOME}/.local-ai"
LLAMA_BIN_DIR="${LOCAL_AI_DIR}/bin"
LLAMA_RELEASES_API="https://api.github.com/repos/ggml-org/llama.cpp/releases/latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN=""

# -----------------------------------------------------------------------------
# Guard — ensure detect.sh has been sourced
# -----------------------------------------------------------------------------

guard_detect() {
  if [[ -z "${CHIP_TYPE:-}" || -z "${USABLE_RAM_GB:-}" ]]; then
    fail "install.sh must be run after detect.sh. Required variables are missing."
  fi
}

# -----------------------------------------------------------------------------
# 1. Xcode Command Line Tools
# -----------------------------------------------------------------------------

install_xcode_clt() {
  section "Xcode Command Line Tools"

  if xcode-select -p &>/dev/null; then
    ok "Xcode Command Line Tools already installed"
    return
  fi

  info "Installing Xcode Command Line Tools..."
  info "A system dialog will appear — click Install and wait for it to finish."
  xcode-select --install 2>/dev/null || true

  local elapsed=0
  while ! xcode-select -p &>/dev/null; do
    sleep 5
    elapsed=$(( elapsed + 5 ))
    [[ "$elapsed" -ge 300 ]] && fail "Xcode CLT install timed out. Run: xcode-select --install"
    info "Waiting for Xcode CLT... (${elapsed}s)"
  done

  ok "Xcode Command Line Tools installed"
}

# -----------------------------------------------------------------------------
# 2. Homebrew
# -----------------------------------------------------------------------------

install_homebrew() {
  section "Homebrew"

  if [[ "${HAS_HOMEBREW}" == "true" ]]; then
    info "Homebrew already installed — checking for updates..."
    brew update --quiet 2>/dev/null && ok "Homebrew up to date" || warn "brew update failed — continuing"
    return
  fi

  info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || \
    fail "Homebrew installation failed."

  configure_homebrew_path
  ok "Homebrew installed"
}

configure_homebrew_path() {
  local brew_path=""
  if [[ "${CHIP_TYPE}" == "apple_silicon" ]]; then
    brew_path="/opt/homebrew/bin/brew"
  else
    brew_path="/usr/local/bin/brew"
  fi

  if [[ ! -x "$brew_path" ]]; then
    fail "Homebrew binary not found at: ${brew_path}"
  fi

  if [[ "$brew_path" != "/opt/homebrew/bin/brew" && "$brew_path" != "/usr/local/bin/brew" ]]; then
    fail "Unexpected Homebrew path: ${brew_path}"
  fi

  local shellenv_line="eval \"\$(${brew_path} shellenv)\""
  if ! grep -qF "$shellenv_line" "${SHELL_PROFILE}" 2>/dev/null; then
    echo "" >> "${SHELL_PROFILE}"
    echo "# Homebrew" >> "${SHELL_PROFILE}"
    echo "$shellenv_line" >> "${SHELL_PROFILE}"
  fi

  eval "$("$brew_path" shellenv)"
  ok "Homebrew PATH configured"
}

# -----------------------------------------------------------------------------
# 3. Llama.cpp — via GitHub releases binary
#    Always fetches latest pre-built Apple Silicon binary.
#    Installs to ~/.local-ai/bin/
#    Fix: uses ggml-org API (repo moved from ggerganov)
#    Fix: handles .tar.gz (macOS assets are no longer .zip)
#    Fix: uses mktemp + mv (macOS mktemp doesn't support extensions)
# -----------------------------------------------------------------------------

install_llama() {
  section "Llama.cpp"

  mkdir -p "$LLAMA_BIN_DIR"

  # Check if already installed
  if [[ -x "${LLAMA_BIN_DIR}/llama-server" ]]; then
    local current_version
    current_version="$("${LLAMA_BIN_DIR}/llama-server" --version 2>&1 | grep -oE 'b[0-9]+' | head -1 || echo "unknown")"
    ok "Llama.cpp already installed (${current_version})"
    add_llama_to_path
    return
  fi

  info "Fetching latest Llama.cpp release from GitHub..."
  download_llama_binary
}

get_latest_llama_release() {
  local release_json tmp_json
  release_json="$(curl -fsSL --max-time 15 "$LLAMA_RELEASES_API" 2>/dev/null)" || \
    fail "Could not reach GitHub API. Check your internet connection."

  # Write to temp file — avoids shell heredoc escaping and Python 3.14 JSON issues
  tmp_json="$(mktemp)"
  chmod 600 "$tmp_json"
  printf "%s" "$release_json" > "$tmp_json"

  local asset_pattern
  if [[ "${CHIP_TYPE}" == "apple_silicon" ]]; then
    asset_pattern="macos-arm64"
  else
    asset_pattern="macos-x86_64"
  fi

  # Use python3.11 if available — avoids Python 3.14 strict JSON parser issues
  local py_bin="${PYTHON_BIN:-}"
  if [[ -z "$py_bin" ]] || ! command -v "$py_bin" &>/dev/null; then
    py_bin="$(command -v python3.11 || command -v python3 || echo "")"
  fi

  [[ -z "$py_bin" ]] && { rm -f "$tmp_json"; fail "Python not found. Install: brew install python@3.11"; }

  local parser_script="${SCRIPT_DIR}/parse_release.py"
  [[ ! -f "$parser_script" ]] && { rm -f "$tmp_json"; fail "parse_release.py not found. Re-clone the repo."; }

  "$py_bin" "$parser_script" "$tmp_json" "$asset_pattern"
  local exit_code=$?
  rm -f "$tmp_json"
  return $exit_code
}

download_llama_binary() {
  local release_info download_url release_tag
  release_info="$(get_latest_llama_release)" || \
    fail "Could not find Llama.cpp release. Check github.com/ggml-org/llama.cpp/releases"

  download_url="$(echo "$release_info" | head -1)"
  release_tag="$(echo "$release_info" | tail -1)"

  [[ -z "$download_url" ]] && fail "Could not determine Llama.cpp download URL."

  info "Downloading Llama.cpp ${release_tag}..."

  # Fix: create temp file first, then rename with extension
  # macOS mktemp does not support custom extensions directly
  local tmp_base tmp_archive
  tmp_base="$(mktemp)"
  chmod 600 "$tmp_base"

  if [[ "$download_url" == *.tar.gz ]]; then
    tmp_archive="${tmp_base}.tar.gz"
  else
    tmp_archive="${tmp_base}.zip"
  fi
  mv "$tmp_base" "$tmp_archive"

  curl -fsSL -L --max-time 120 "$download_url" -o "$tmp_archive" || \
    fail "Download failed. Check your internet connection."

  info "Extracting to ${LLAMA_BIN_DIR}..."
  if [[ "$tmp_archive" == *.tar.gz ]]; then
    tar -xzf "$tmp_archive" -C "$LLAMA_BIN_DIR" || fail "Extraction failed."
  else
    unzip -q "$tmp_archive" -d "$LLAMA_BIN_DIR" || fail "Extraction failed."
  fi
  rm -f "$tmp_archive"

  # Promote binaries from nested subdirectory if needed
  local nested_server
  nested_server="$(find "$LLAMA_BIN_DIR" -name "llama-server" -not -path "${LLAMA_BIN_DIR}/llama-server" 2>/dev/null | head -1)"
  if [[ -n "$nested_server" ]]; then
    mv "$(dirname "$nested_server")"/* "$LLAMA_BIN_DIR/" 2>/dev/null || true
    rmdir "$(dirname "$nested_server")" 2>/dev/null || true
  fi

  chmod +x "${LLAMA_BIN_DIR}"/llama-* 2>/dev/null || true
  add_llama_to_path

  [[ ! -x "${LLAMA_BIN_DIR}/llama-server" ]] && fail "llama-server not found after installation."

  echo "$release_tag" > "${LOCAL_AI_DIR}/.llama_version"
  ok "Llama.cpp ${release_tag} installed"
}

add_llama_to_path() {
  if ! grep -qF "$LLAMA_BIN_DIR" "${SHELL_PROFILE}" 2>/dev/null; then
    echo "" >> "${SHELL_PROFILE}"
    echo "# Llama.cpp binaries" >> "${SHELL_PROFILE}"
    echo "export PATH=\"${LLAMA_BIN_DIR}:\$PATH\"" >> "${SHELL_PROFILE}"
  fi
  export PATH="${LLAMA_BIN_DIR}:${PATH}"
}

# -----------------------------------------------------------------------------
# 4. Hugging Face CLI
#    Fix: installs `hf` (new CLI) not deprecated `huggingface-cli`
#    Fix: checks for both `hf` and `huggingface-cli` command names
# -----------------------------------------------------------------------------

install_hf_cli() {
  section "Hugging Face CLI"

  # Check for new `hf` command first
  if command -v hf &>/dev/null; then
    ok "Hugging Face CLI (hf) already installed"
    export HF_CMD="hf"
    return
  fi

  # Check for legacy huggingface-cli
  if command -v huggingface-cli &>/dev/null; then
    warn "Legacy huggingface-cli found — upgrading to hf..."
  fi

  info "Installing Hugging Face CLI..."
  brew install huggingface-cli 2>/dev/null || true

  # Try pip install if brew fails
  if ! command -v hf &>/dev/null && ! command -v huggingface-cli &>/dev/null; then
    local py_bin="${PYTHON_BIN:-python3.11}"
    "$py_bin" -m pip install huggingface_hub[cli] --quiet --break-system-packages 2>/dev/null || true
  fi

  # Set HF_CMD to whichever is available
  if command -v hf &>/dev/null; then
    HF_CMD="hf"
    ok "Hugging Face CLI (hf) installed"
  elif command -v huggingface-cli &>/dev/null; then
    HF_CMD="huggingface-cli"
    ok "Hugging Face CLI installed (legacy)"
  else
    warn "Hugging Face CLI not found — model download may fail. Install manually: brew install huggingface-cli"
    HF_CMD="hf"
  fi

  export HF_CMD
}

# -----------------------------------------------------------------------------
# 5. Python 3.11
#    Fix: pinned to 3.11 — Python 3.12+ breaks numpy/aider dependencies
#    Fix: Python 3.14 (macOS 26 default) causes ImpImporter errors with pip
# -----------------------------------------------------------------------------

install_python() {
  section "Python 3.11"

  # Check if brew's python@3.11 already installed
  if brew list python@3.11 &>/dev/null 2>&1; then
    PYTHON_BIN="$(brew --prefix python@3.11)/bin/python3.11"
    ok "Python 3.11 already installed (${PYTHON_BIN})"
    export PYTHON_BIN
    return
  fi

  if command -v python3.11 &>/dev/null; then
    PYTHON_BIN="$(command -v python3.11)"
    ok "Python 3.11 found at ${PYTHON_BIN}"
    export PYTHON_BIN
    return
  fi

  info "Installing Python 3.11 (pinned — newer versions break Aider dependencies)..."
  brew install python@3.11 || fail "Python 3.11 installation failed."

  PYTHON_BIN="$(brew --prefix python@3.11)/bin/python3.11"

  if [[ ! -x "$PYTHON_BIN" ]]; then
    PYTHON_BIN="$(find /opt/homebrew /usr/local -name "python3.11" -type f 2>/dev/null | head -1)"
    [[ -z "$PYTHON_BIN" ]] && fail "python3.11 not found after install. Try: brew install python@3.11"
  fi

  ok "Python 3.11 installed at ${PYTHON_BIN}"
  export PYTHON_BIN
}

# -----------------------------------------------------------------------------
# 6. pipx
#    Fix: avoids externally-managed-environment error on macOS
#    Fix: uses python3.11 explicitly to avoid system Python conflicts
# -----------------------------------------------------------------------------

install_pipx() {
  section "pipx"

  if command -v pipx &>/dev/null; then
    ok "pipx already installed"
    return
  fi

  [[ -z "${PYTHON_BIN:-}" ]] && fail "PYTHON_BIN not set — install_python must run first"

  info "Installing pipx using Python 3.11..."
  "$PYTHON_BIN" -m pip install pipx --quiet 2>/dev/null || \
  "$PYTHON_BIN" -m pip install pipx --quiet --break-system-packages 2>/dev/null || \
    fail "pipx install failed. Try: python3.11 -m pip install pipx"

  "$PYTHON_BIN" -m pipx ensurepath --force 2>/dev/null || true

  local pipx_bin="${HOME}/.local/bin"
  if [[ -d "$pipx_bin" ]]; then
    export PATH="${pipx_bin}:${PATH}"
    if ! grep -qF ".local/bin" "${SHELL_PROFILE}" 2>/dev/null; then
      echo "" >> "${SHELL_PROFILE}"
      echo "# pipx" >> "${SHELL_PROFILE}"
      echo "export PATH=\"\${HOME}/.local/bin:\$PATH\"" >> "${SHELL_PROFILE}"
    fi
  fi

  command -v pipx &>/dev/null || fail "pipx not found after install. Restart terminal and try again."
  ok "pipx installed"
}

# -----------------------------------------------------------------------------
# 7. Aider coding agent
#    Fix: installed via pipx + python3.11 (not pip directly)
#    Fix: avoids numpy build failures and Python version conflicts
# -----------------------------------------------------------------------------

install_aider() {
  section "Aider Coding Agent"

  if command -v aider &>/dev/null; then
    info "Aider already installed — checking for updates..."
    pipx upgrade aider-chat --quiet 2>/dev/null && \
      ok "Aider updated to $(aider --version 2>/dev/null | head -1)" || \
      ok "Aider already up to date"
    return
  fi

  [[ -z "${PYTHON_BIN:-}" ]] && fail "PYTHON_BIN not set — install_python must run first"

  info "Installing Aider via pipx (Python 3.11)..."
  "$PYTHON_BIN" -m pipx install aider-chat || \
    fail "Aider install failed. Try manually: python3.11 -m pipx install aider-chat"

  # Ensure aider is in PATH
  if ! command -v aider &>/dev/null; then
    export PATH="${HOME}/.local/bin:${PATH}"
    command -v aider &>/dev/null || \
      fail "aider not found after install. Run: source ${SHELL_PROFILE}"
  fi

  ok "Aider $(aider --version 2>/dev/null | head -1) installed"
}

# -----------------------------------------------------------------------------
# 8. Models directory
# -----------------------------------------------------------------------------

create_models_dir() {
  section "Models Directory"

  local models_dir="${HOME}/models"
  mkdir -p "$models_dir"
  ok "Models directory ready at ${models_dir}"
  export MODELS_DIR="$models_dir"
}

# -----------------------------------------------------------------------------
# 9. Summary
# -----------------------------------------------------------------------------

print_install_summary() {
  local llama_version aider_version
  llama_version="$("${LLAMA_BIN_DIR}/llama-server" --version 2>&1 | head -1 || echo "installed")"
  aider_version="$(aider --version 2>/dev/null | head -1 || echo "installed")"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Installation Summary"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Homebrew      : $(brew --version | head -1)"
  echo "  Llama.cpp     : ${llama_version}"
  echo "  Llama bin dir : ${LLAMA_BIN_DIR}"
  echo "  HF CLI        : ${HF_CMD}"
  echo "  Python        : $("${PYTHON_BIN}" --version 2>/dev/null)"
  echo "  pipx          : $(pipx --version 2>/dev/null | head -1)"
  echo "  Aider         : ${aider_version}"
  echo "  Models dir    : ${MODELS_DIR}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  log "Installation complete"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
  echo ""
  echo "📦 Installing dependencies..."
  echo ""

  guard_detect
  install_xcode_clt
  install_homebrew
  install_llama
  install_hf_cli
  install_python
  install_pipx
  install_aider
  create_models_dir
  print_install_summary
}

main
