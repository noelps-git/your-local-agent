#!/usr/bin/env bash
# =============================================================================
# download.sh — Model Selector and Download Module
# your-local-agent | github.com/noelps-git/your-local-agent
#
# Fixes applied from live debugging:
# - Uses `hf` CLI instead of deprecated `huggingface-cli`
# - Checks if model file already exists before downloading (skip if present)
# - Clear 401 auth error message with login instructions
# - Clear 404 error if repo has moved
# - Correct repo URLs (bartowski/Qwen_Qwen3-8B-GGUF)
# - Correct filenames matching actual repo assets
# - File existence check uses flexible size tolerance
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
# Paths
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
MODELS_JSON="${REPO_ROOT}/models.json"
MODELS_DIR="${HOME}/models"

# -----------------------------------------------------------------------------
# Guard — ensure detect.sh has been sourced
# -----------------------------------------------------------------------------

guard_detect() {
  if [[ -z "${RECOMMENDED_MODEL_ID:-}" || -z "${USABLE_RAM_GB:-}" ]]; then
    fail "download.sh must be run after detect.sh."
  fi
}

guard_models_json() {
  [[ ! -f "$MODELS_JSON" ]] && \
    fail "models.json not found at ${MODELS_JSON}. Re-clone from github.com/noelps-git/your-local-agent"
}

# -----------------------------------------------------------------------------
# Parse models.json
# -----------------------------------------------------------------------------

get_model_field() {
  local model_id="$1" field="$2"
  python3 - <<EOF
import json, sys
with open("${MODELS_JSON}") as f:
    models = json.load(f)
for m in models:
    if m["id"] == "${model_id}":
        print(m.get("${field}", ""))
        sys.exit(0)
print("")
EOF
}

get_all_model_ids() {
  python3 - <<EOF
import json
with open("${MODELS_JSON}") as f:
    models = json.load(f)
for m in models:
    print(m["id"])
EOF
}

print_model_table() {
  python3 - <<EOF
import json
with open("${MODELS_JSON}") as f:
    models = json.load(f)
print(f"  {'ID':<15} {'Name':<15} {'Size':>6}  {'RAM Required':>13}  {'Speed':<15}")
print(f"  {'-'*15} {'-'*15} {'-'*6}  {'-'*13}  {'-'*15}")
for m in models:
    print(f"  {m['id']:<15} {m['name']:<15} {str(m['size_gb'])+'GB':>6}  {str(m['ram_required_gb'])+'GB min':>13}  {m['tokens_per_sec_estimate']+' tok/s':<15}")
EOF
}

# -----------------------------------------------------------------------------
# 1. Model selection
# -----------------------------------------------------------------------------

select_model() {
  section "Model Selection"

  local recommended_id="${RECOMMENDED_MODEL_ID}"
  local recommended_name recommended_size recommended_ram
  recommended_name="$(get_model_field "$recommended_id" "name")"
  recommended_size="$(get_model_field "$recommended_id" "size_gb")"
  recommended_ram="$(get_model_field "$recommended_id" "ram_required_gb")"

  echo "  Based on your system (${USABLE_RAM_GB}GB usable RAM):"
  echo ""
  echo "  Recommended → ${recommended_name}"
  echo "               ${recommended_size}GB download / ${recommended_ram}GB RAM required"
  echo ""
  echo "  Available models:"
  echo ""
  print_model_table
  echo ""
  echo "  Press Enter to use the recommended model,"
  echo "  or type a model ID from the table above to override:"
  echo ""
  printf "  > "
  read -r user_input

  # Sanitise input — alphanumeric and dash only
  user_input="$(echo "$user_input" | tr -d '[:space:]' | tr -cd 'a-zA-Z0-9-')"

  if [[ -z "$user_input" ]]; then
    SELECTED_MODEL_ID="$recommended_id"
  else
    validate_model_override "$user_input"
    SELECTED_MODEL_ID="$user_input"
  fi

  SELECTED_MODEL_NAME="$(get_model_field "$SELECTED_MODEL_ID" "name")"
  SELECTED_MODEL_REPO="$(get_model_field "$SELECTED_MODEL_ID" "repo")"
  SELECTED_MODEL_FILE="$(get_model_field "$SELECTED_MODEL_ID" "file")"
  SELECTED_MODEL_SIZE="$(get_model_field "$SELECTED_MODEL_ID" "size_gb")"
  SELECTED_MODEL_RAM="$(get_model_field "$SELECTED_MODEL_ID" "ram_required_gb")"

  ok "Selected: ${SELECTED_MODEL_NAME} (${SELECTED_MODEL_FILE})"

  export SELECTED_MODEL_ID SELECTED_MODEL_NAME SELECTED_MODEL_REPO
  export SELECTED_MODEL_FILE SELECTED_MODEL_SIZE SELECTED_MODEL_RAM
}

validate_model_override() {
  local input_id="$1"
  local valid_ids
  valid_ids="$(get_all_model_ids)"

  if ! echo "$valid_ids" | grep -qx "$input_id"; then
    fail "Unknown model ID: '${input_id}'. Please choose from the table above."
  fi

  local model_ram
  model_ram="$(get_model_field "$input_id" "ram_required_gb")"
  if [[ "$model_ram" -gt "$USABLE_RAM_GB" ]]; then
    warn "Selected model requires ${model_ram}GB RAM but you have ${USABLE_RAM_GB}GB usable."
    printf "  Continue anyway? (y/N): "
    read -r confirm
    confirm="$(echo "$confirm" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    [[ "$confirm" != "y" && "$confirm" != "yes" ]] && SELECTED_MODEL_ID="${RECOMMENDED_MODEL_ID}"
  fi
}

# -----------------------------------------------------------------------------
# 2. Check if model already exists on disk
#    Fix: checks BEFORE attempting any download or network calls
# -----------------------------------------------------------------------------

check_existing_model() {
  section "Checking Existing Downloads"

  local model_path="${MODELS_DIR}/${SELECTED_MODEL_FILE}"

  if [[ ! -f "$model_path" ]]; then
    info "No existing model found — will download"
    SKIP_DOWNLOAD=false
    export SKIP_DOWNLOAD
    return
  fi

  info "Found existing file: ${model_path}"
  local actual_size_bytes actual_gb
  actual_size_bytes="$(stat -f%z "$model_path" 2>/dev/null || stat -c%s "$model_path" 2>/dev/null)"
  actual_gb=$(python3 -c "print(round(${actual_size_bytes} / 1024 / 1024 / 1024, 2))")

  local expected_bytes tolerance lower upper
  expected_bytes=$(python3 -c "print(int(${SELECTED_MODEL_SIZE} * 1024 * 1024 * 1024))")
  tolerance=$(python3 -c "print(int(${expected_bytes} * 0.05))")
  lower=$(python3 -c "print(${expected_bytes} - ${tolerance})")
  upper=$(python3 -c "print(${expected_bytes} + ${tolerance})")

  if [[ "$actual_size_bytes" -ge "$lower" && "$actual_size_bytes" -le "$upper" ]]; then
    ok "Model already downloaded (${actual_gb}GB) — skipping download"
    SKIP_DOWNLOAD=true
    MODEL_PATH="$model_path"
    export SKIP_DOWNLOAD MODEL_PATH
    return
  fi

  warn "File size mismatch (${actual_gb}GB vs expected ${SELECTED_MODEL_SIZE}GB) — re-downloading"
  if [[ "$model_path" == "${MODELS_DIR}/"* ]]; then
    rm -f "$model_path"
  fi
  SKIP_DOWNLOAD=false
  export SKIP_DOWNLOAD
}

# -----------------------------------------------------------------------------
# 3. Pre-download checks
# -----------------------------------------------------------------------------

pre_download_checks() {
  section "Pre-Download Checks"

  if [[ "${SKIP_DOWNLOAD}" == "true" ]]; then
    return
  fi

  # Disk space check
  local required_gb
  required_gb=$(python3 -c "import math; print(math.ceil(${SELECTED_MODEL_SIZE} + 1))")
  if [[ "${AVAILABLE_DISK_GB}" -lt "$required_gb" ]]; then
    fail "Not enough disk space. Need ${required_gb}GB, have ${AVAILABLE_DISK_GB}GB."
  fi
  ok "Disk space OK (need ${required_gb}GB, have ${AVAILABLE_DISK_GB}GB)"

  # Check Hugging Face reachability and auth status
  info "Checking Hugging Face availability..."
  local hf_status
  hf_status="$(curl -sI --max-time 10 "https://huggingface.co/${SELECTED_MODEL_REPO}" 2>/dev/null | head -1 | grep -oE '[0-9]{3}' || echo "")"

  if [[ -z "$hf_status" ]]; then
    fail "Cannot reach Hugging Face. Check your internet connection."
  fi

  if [[ "$hf_status" == "401" ]]; then
    echo ""
    warn "Hugging Face requires authentication for this repo."
    info "Fix in 3 steps:"
    info "  1. Go to: huggingface.co/settings/tokens"
    info "  2. Create a free Read token"
    info "  3. Run: hf auth login"
    info "  Then re-run setup."
    fail "Authentication required."
  fi

  if [[ "$hf_status" == "404" ]]; then
    fail "Repo not found: ${SELECTED_MODEL_REPO}. Check github.com/noelps-git/your-local-agent for updates."
  fi

  ok "Hugging Face reachable (HTTP ${hf_status})"
}

# -----------------------------------------------------------------------------
# 4. Download model
#    Fix: uses `hf` CLI (not deprecated huggingface-cli)
#    Fix: falls back to huggingface-cli if hf not available
# -----------------------------------------------------------------------------

download_model() {
  section "Downloading ${SELECTED_MODEL_NAME}"

  if [[ "${SKIP_DOWNLOAD}" == "true" ]]; then
    ok "Model already on disk — skipping download"
    return
  fi

  mkdir -p "$MODELS_DIR"

  # Determine which HF CLI to use
  local hf_cmd="${HF_CMD:-}"
  if [[ -z "$hf_cmd" ]]; then
    if command -v hf &>/dev/null; then
      hf_cmd="hf"
    elif command -v huggingface-cli &>/dev/null; then
      hf_cmd="huggingface-cli"
    else
      fail "Hugging Face CLI not found. Install: brew install huggingface-cli"
    fi
  fi

  info "Downloading ${SELECTED_MODEL_FILE} (${SELECTED_MODEL_SIZE}GB)..."
  info "This may take 5–20 minutes depending on your internet speed."
  info "Download will resume if interrupted."
  echo ""

  "$hf_cmd" download "${SELECTED_MODEL_REPO}" \
    "${SELECTED_MODEL_FILE}" \
    --local-dir "${MODELS_DIR}" \
    || fail "Download failed. Run setup again to resume."

  # Verify after download
  local model_path="${MODELS_DIR}/${SELECTED_MODEL_FILE}"
  if [[ ! -f "$model_path" ]]; then
    fail "Model file not found after download: ${model_path}"
  fi

  ok "Download complete"
  MODEL_PATH="$model_path"
  export MODEL_PATH
}

# -----------------------------------------------------------------------------
# 5. Set MODEL_PATH if skipped download
# -----------------------------------------------------------------------------

set_model_path() {
  if [[ -z "${MODEL_PATH:-}" ]]; then
    MODEL_PATH="${MODELS_DIR}/${SELECTED_MODEL_FILE}"
    export MODEL_PATH
  fi
}

# -----------------------------------------------------------------------------
# 6. Summary
# -----------------------------------------------------------------------------

print_download_summary() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Download Summary"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Model    : ${SELECTED_MODEL_NAME}"
  echo "  File     : ${SELECTED_MODEL_FILE}"
  echo "  Location : ${MODEL_PATH}"
  echo "  Size     : ${SELECTED_MODEL_SIZE}GB"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  log "Model ready: ${MODEL_PATH}"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
  echo ""
  echo "🤖 Selecting and downloading model..."
  echo ""

  guard_detect
  guard_models_json
  select_model
  check_existing_model
  pre_download_checks
  download_model
  set_model_path
  print_download_summary
}

main
