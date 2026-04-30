#!/usr/bin/env bash
# =============================================================================
# detect.sh — System Detection Module
# your-local-agent | github.com/you/your-local-agent
#
# Detects system properties and exports variables used by all other modules.
# Safe to run multiple times. Makes no changes to the system.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Logging helpers
# -----------------------------------------------------------------------------

LOG_FILE="${HOME}/.local-ai/setup.log"
mkdir -p "$(dirname "$LOG_FILE")"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
info() { echo "  $*"; log "INFO  $*"; }
warn() { echo "  ⚠️  $*"; log "WARN  $*"; }
fail() { echo "  ❌  $*"; log "ERROR $*"; exit 1; }
ok()   { echo "  ✅  $*"; log "OK    $*"; }

# -----------------------------------------------------------------------------
# 1. Operating System check
# -----------------------------------------------------------------------------

detect_os() {
  info "Checking operating system..."

  local os
  os="$(uname -s)"

  if [[ "$os" != "Darwin" ]]; then
    fail "your-local-agent currently supports macOS only. Linux support is on the roadmap."
  fi

  MACOS_VERSION="$(sw_vers -productVersion)"
  MACOS_MAJOR="$(echo "$MACOS_VERSION" | cut -d. -f1)"

  if [[ "$MACOS_MAJOR" -lt 12 ]]; then
    fail "macOS 12 (Monterey) or higher is required for Metal GPU support. You have macOS ${MACOS_VERSION}. Please upgrade and try again."
  fi

  # Friendly name mapping — updated for Apple new versioning (26 = Tahoe)
  local macos_name
  case "$MACOS_MAJOR" in
    12) macos_name="Monterey" ;;
    13) macos_name="Ventura" ;;
    14) macos_name="Sonoma" ;;
    15) macos_name="Sequoia" ;;
    26) macos_name="Tahoe" ;;
    *)  macos_name="Unknown" ;;
  esac

  ok "macOS ${MACOS_VERSION} (${macos_name}) detected"
  export MACOS_VERSION
  export MACOS_MAJOR
  export MACOS_NAME="${macos_name}"
}

# -----------------------------------------------------------------------------
# 2. Chip type detection
# -----------------------------------------------------------------------------

detect_chip() {
  info "Checking chip type..."

  local arch
  arch="$(uname -m)"

  if [[ "$arch" == "arm64" ]]; then
    CHIP_TYPE="apple_silicon"
    ok "Apple Silicon detected — Metal GPU acceleration supported"
  elif [[ "$arch" == "x86_64" ]]; then
    CHIP_TYPE="intel"
    warn "Intel Mac detected. Performance will be significantly slower. Apple Silicon support is recommended."
    warn "Intel Mac full support is on the roadmap. Continuing with limited performance expectations."
  else
    fail "Unknown architecture: ${arch}. Cannot continue."
  fi

  export CHIP_TYPE
}

# -----------------------------------------------------------------------------
# 3. RAM detection
# -----------------------------------------------------------------------------

detect_ram() {
  info "Checking available RAM..."

  local raw_ram ram_string
  raw_ram="$(system_profiler SPHardwareDataType 2>/dev/null | grep -i "memory:" | head -1)"

  # Handle formats: "8 GB", "16GB", "32 GB"
  ram_string="$(echo "$raw_ram" | grep -oE '[0-9]+')"

  if [[ -z "$ram_string" ]]; then
    fail "Could not detect RAM. Please check system_profiler is accessible and try again."
  fi

  DETECTED_RAM_GB="$ram_string"

  # Subtract 2GB for macOS overhead
  USABLE_RAM_GB=$(( DETECTED_RAM_GB - 2 ))

  if [[ "$USABLE_RAM_GB" -lt 2 ]]; then
    fail "Usable RAM is ${USABLE_RAM_GB}GB after OS overhead. A minimum of 4GB total RAM is required to run any supported model."
  fi

  ok "${DETECTED_RAM_GB}GB RAM detected — ${USABLE_RAM_GB}GB usable after OS overhead"
  export DETECTED_RAM_GB
  export USABLE_RAM_GB
}

# -----------------------------------------------------------------------------
# 4. Disk space detection
# -----------------------------------------------------------------------------

detect_disk() {
  info "Checking available disk space..."

  local raw_disk
  # Get available space in 1K blocks, convert to GB
  raw_disk="$(df -k "$HOME" | awk 'NR==2 {print $4}')"

  if [[ -z "$raw_disk" ]]; then
    fail "Could not detect available disk space."
  fi

  AVAILABLE_DISK_GB=$(( raw_disk / 1024 / 1024 ))

  # Minimum 6GB required: largest model we support is ~5GB + 1GB buffer
  if [[ "$AVAILABLE_DISK_GB" -lt 6 ]]; then
    fail "Only ${AVAILABLE_DISK_GB}GB available on disk. At least 6GB is required to download a model. Free up space and try again."
  fi

  ok "${AVAILABLE_DISK_GB}GB available on disk"
  export AVAILABLE_DISK_GB
}

# -----------------------------------------------------------------------------
# 5. Internet connectivity check
# -----------------------------------------------------------------------------

detect_internet() {
  info "Checking internet connectivity..."

  if curl -sfo /dev/null --max-time 5 "https://huggingface.co" 2>/dev/null; then
    ok "Internet connection confirmed"
  else
    fail "No internet connection detected. An internet connection is required to download the model. Please connect and try again."
  fi
}

# -----------------------------------------------------------------------------
# 6. Shell detection
# -----------------------------------------------------------------------------

detect_shell() {
  info "Detecting shell environment..."

  local shell_name
  shell_name="$(basename "$SHELL")"

  case "$shell_name" in
    zsh)
      SHELL_TYPE="zsh"
      SHELL_PROFILE="${HOME}/.zshrc"
      ;;
    bash)
      SHELL_TYPE="bash"
      # macOS bash uses .bash_profile for login shells
      SHELL_PROFILE="${HOME}/.bash_profile"
      ;;
    fish)
      SHELL_TYPE="fish"
      SHELL_PROFILE="${HOME}/.config/fish/config.fish"
      warn "Fish shell detected. Automatic alias setup is not yet supported for Fish. You will be given manual instructions at the end of setup."
      ;;
    *)
      SHELL_TYPE="other"
      SHELL_PROFILE="${HOME}/.profile"
      warn "Unrecognised shell: ${shell_name}. Will attempt to write to ~/.profile — you may need to set aliases manually."
      ;;
  esac

  ok "Shell: ${SHELL_TYPE} — profile: ${SHELL_PROFILE}"
  export SHELL_TYPE
  export SHELL_PROFILE
}

# -----------------------------------------------------------------------------
# 7. Existing installs detection
# -----------------------------------------------------------------------------

detect_existing_installs() {
  info "Checking for existing installations..."

  # Homebrew
  if command -v brew &>/dev/null; then
    HAS_HOMEBREW=true
    ok "Homebrew found at $(command -v brew)"
  else
    HAS_HOMEBREW=false
    info "Homebrew not found — will install"
  fi

  # Llama.cpp
  if command -v llama-server &>/dev/null; then
    HAS_LLAMA=true
    ok "Llama.cpp found at $(command -v llama-server)"
  else
    HAS_LLAMA=false
    info "Llama.cpp not found — will install"
  fi

  # Node.js — detect manager first to avoid conflicts
  if command -v node &>/dev/null; then
    HAS_NODE=true

    if [[ -d "${HOME}/.nvm" ]]; then
      NODE_MANAGER="nvm"
      ok "Node.js found via nvm — will use existing installation"
    elif command -v asdf &>/dev/null && asdf current nodejs &>/dev/null 2>&1; then
      NODE_MANAGER="asdf"
      ok "Node.js found via asdf — will use existing installation"
    else
      NODE_MANAGER="brew"
      ok "Node.js found at $(command -v node)"
    fi
  else
    HAS_NODE=false
    NODE_MANAGER="none"
    info "Node.js not found — will install via Homebrew"
  fi

  # Aider agent
  if command -v aider &>/dev/null; then
    HAS_AIDER=true
    ok "Aider found at $(command -v aider)"
  else
    HAS_AIDER=false
    info "Aider not found — will install"
  fi

  export HAS_HOMEBREW
  export HAS_LLAMA
  export HAS_NODE
  export NODE_MANAGER
  export HAS_AIDER
}

# -----------------------------------------------------------------------------
# 8. Model recommendation
# -----------------------------------------------------------------------------

recommend_model() {
  info "Selecting recommended model based on ${USABLE_RAM_GB}GB usable RAM..."

  if [[ "$USABLE_RAM_GB" -ge 30 ]]; then
    RECOMMENDED_MODEL_ID="qwen3-32b"
  elif [[ "$USABLE_RAM_GB" -ge 22 ]]; then
    RECOMMENDED_MODEL_ID="qwen3-14b"
  elif [[ "$USABLE_RAM_GB" -ge 14 ]]; then
    RECOMMENDED_MODEL_ID="qwen3-8b"
  elif [[ "$USABLE_RAM_GB" -ge 4 ]]; then
    RECOMMENDED_MODEL_ID="qwen3-4b"
  else
    fail "Usable RAM (${USABLE_RAM_GB}GB) is too low to run any supported model. Minimum 4GB usable RAM required."
  fi

  ok "Recommended model: ${RECOMMENDED_MODEL_ID}"
  export RECOMMENDED_MODEL_ID
}

# -----------------------------------------------------------------------------
# 9. Summary output
# -----------------------------------------------------------------------------

print_summary() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  System Detection Summary"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  macOS Version     : ${MACOS_VERSION}"
  echo "  Chip              : ${CHIP_TYPE}"
  echo "  RAM               : ${DETECTED_RAM_GB}GB total / ${USABLE_RAM_GB}GB usable"
  echo "  Disk Available    : ${AVAILABLE_DISK_GB}GB"
  echo "  Shell             : ${SHELL_TYPE} (${SHELL_PROFILE})"
  echo "  Homebrew          : ${HAS_HOMEBREW}"
  echo "  Llama.cpp         : ${HAS_LLAMA}"
  echo "  Node.js           : ${HAS_NODE} (manager: ${NODE_MANAGER})"
  echo "  Aider             : ${HAS_AIDER}"
  echo "  Recommended Model : ${RECOMMENDED_MODEL_ID}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  log "Detection summary: OS=${MACOS_VERSION} CHIP=${CHIP_TYPE} RAM=${DETECTED_RAM_GB}GB DISK=${AVAILABLE_DISK_GB}GB SHELL=${SHELL_TYPE} MODEL=${RECOMMENDED_MODEL_ID}"
}

# -----------------------------------------------------------------------------
# Main — run all detections in order
# -----------------------------------------------------------------------------

main() {
  echo ""
  echo "🔍 Running system detection..."
  echo ""

  detect_os
  detect_chip
  detect_ram
  detect_disk
  detect_internet
  detect_shell
  detect_existing_installs
  recommend_model
  print_summary
}

main
