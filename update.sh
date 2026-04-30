#!/usr/bin/env bash
# =============================================================================
# update.sh — Update Module
# your-local-agent | github.com/you/your-local-agent
#
# Updates scripts and checks if a better model is available for your RAM.
# Run via: local-ai-update
# Or directly: curl -fsSL https://raw.githubusercontent.com/noelps-git/your-local-agent/main/update.sh | bash
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------

RAW_BASE="https://raw.githubusercontent.com/noelps-git/your-local-agent/main"
REPO_URL="https://github.com/noelps-git/your-local-agent"
LOCAL_AI_DIR="${HOME}/.local-ai"
INSTALL_DIR="${LOCAL_AI_DIR}/repo"
LOG_FILE="${LOCAL_AI_DIR}/setup.log"
STATE_FILE="${LOCAL_AI_DIR}/state.json"
MODELS_DIR="${HOME}/models"

# -----------------------------------------------------------------------------
# Logging helpers
# -----------------------------------------------------------------------------

mkdir -p "$LOCAL_AI_DIR"

log()     { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
info()    { echo "  $*";      log "INFO  $*"; }
warn()    { echo "  ⚠️  $*";  log "WARN  $*"; }
fail()    { echo "  ❌  $*";  log "ERROR $*"; exit 1; }
ok()      { echo "  ✅  $*";  log "OK    $*"; }
section() { echo ""; echo "▶ $*"; echo ""; log "SECTION $*"; }

# -----------------------------------------------------------------------------
# Banner
# -----------------------------------------------------------------------------

print_banner() {
  echo ""
  echo "  ╔═══════════════════════════════════════════╗"
  echo "  ║       your-local-agent — Update           ║"
  echo "  ╚═══════════════════════════════════════════╝"
  echo ""
  log "====== Update started ======"
}

# -----------------------------------------------------------------------------
# 1. Read current state
# -----------------------------------------------------------------------------

read_state() {
  section "Reading Current Installation State"

  if [[ ! -f "$STATE_FILE" ]]; then
    fail "No installation state found at ${STATE_FILE}. Run setup.sh first before updating."
  fi

  CURRENT_MODEL_ID="$(python3 -c "import json; d=json.load(open('${STATE_FILE}')); print(d.get('model_id',''))" 2>/dev/null || echo "")"
  CURRENT_MODEL_FILE="$(python3 -c "import json; d=json.load(open('${STATE_FILE}')); print(d.get('model_file',''))" 2>/dev/null || echo "")"
  CURRENT_MODEL_PATH="$(python3 -c "import json; d=json.load(open('${STATE_FILE}')); print(d.get('model_path',''))" 2>/dev/null || echo "")"
  CURRENT_RAM_GB="$(python3 -c "import json; d=json.load(open('${STATE_FILE}')); print(d.get('ram_gb',''))" 2>/dev/null || echo "")"
  CURRENT_CHIP="$(python3 -c "import json; d=json.load(open('${STATE_FILE}')); print(d.get('chip_type',''))" 2>/dev/null || echo "")"
  INSTALLED_AT="$(python3 -c "import json; d=json.load(open('${STATE_FILE}')); print(d.get('installed_at',''))" 2>/dev/null || echo "")"

  if [[ -z "$CURRENT_MODEL_ID" ]]; then
    fail "Could not read model_id from state file. State may be corrupt. Re-run setup.sh."
  fi

  ok "Current model  : ${CURRENT_MODEL_ID} (${CURRENT_MODEL_FILE})"
  ok "Installed at   : ${INSTALLED_AT}"
  ok "System         : ${CURRENT_CHIP} / ${CURRENT_RAM_GB}GB RAM"
}

# -----------------------------------------------------------------------------
# 2. Update script files
# -----------------------------------------------------------------------------

update_scripts() {
  section "Updating Setup Scripts"

  mkdir -p "${INSTALL_DIR}/lib"

  local files=(
    "setup.sh"
    "update.sh"
    "models.json"
    "lib/detect.sh"
    "lib/install.sh"
    "lib/download.sh"
    "lib/configure.sh"
    "lib/verify.sh"
  )

  local updated=0
  local failed=0

  for file in "${files[@]}"; do
    local url="${RAW_BASE}/${file}"
    local dest="${INSTALL_DIR}/${file}"

    mkdir -p "$(dirname "$dest")"

    if curl -fsSL "$url" -o "$dest" 2>/dev/null; then
      ok "Updated ${file}"
      (( updated++ ))
    else
      warn "Failed to update ${file} — keeping existing version"
      (( failed++ ))
    fi
  done

  chmod +x "${INSTALL_DIR}/setup.sh" 2>/dev/null || true
  chmod +x "${INSTALL_DIR}/update.sh" 2>/dev/null || true
  chmod +x "${INSTALL_DIR}/lib/"*.sh 2>/dev/null || true

  info "Scripts updated: ${updated} / $(( updated + failed ))"
}

# -----------------------------------------------------------------------------
# 3. Check if a better model is available
# -----------------------------------------------------------------------------

check_model_update() {
  section "Checking for Model Updates"

  local models_json="${INSTALL_DIR}/models.json"

  if [[ ! -f "$models_json" ]]; then
    warn "models.json not found — skipping model check"
    return
  fi

  # Re-calculate recommended model based on current RAM
  local usable_ram=$(( CURRENT_RAM_GB - 2 ))
  local recommended_id=""

  if [[ "$usable_ram" -ge 30 ]]; then
    recommended_id="qwen3-32b"
  elif [[ "$usable_ram" -ge 22 ]]; then
    recommended_id="qwen3-14b"
  elif [[ "$usable_ram" -ge 14 ]]; then
    recommended_id="qwen3-8b"
  elif [[ "$usable_ram" -ge 4 ]]; then
    recommended_id="qwen3-4b"
  fi

  if [[ -z "$recommended_id" ]]; then
    warn "Could not determine recommended model — skipping model update check"
    return
  fi

  if [[ "$recommended_id" == "$CURRENT_MODEL_ID" ]]; then
    ok "You already have the recommended model for your system (${CURRENT_MODEL_ID})"
    MODEL_UPDATE_NEEDED=false
    return
  fi

  # Different model recommended
  local new_model_name new_model_size
  new_model_name="$(python3 -c "
import json
with open('${models_json}') as f:
    models = json.load(f)
for m in models:
    if m['id'] == '${recommended_id}':
        print(m['name'])
")"

  new_model_size="$(python3 -c "
import json
with open('${models_json}') as f:
    models = json.load(f)
for m in models:
    if m['id'] == '${recommended_id}':
        print(m['size_gb'])
")"

  info "A different model is now recommended for your system:"
  echo ""
  echo "    Current   : ${CURRENT_MODEL_ID}"
  echo "    Recommended: ${recommended_id} (${new_model_name}, ${new_model_size}GB)"
  echo ""
  printf "  Download the recommended model? (y/N): "
  read -r confirm
  confirm="$(echo "$confirm" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"

  if [[ "$confirm" == "y" || "$confirm" == "yes" ]]; then
    MODEL_UPDATE_NEEDED=true
    NEW_MODEL_ID="$recommended_id"
    NEW_MODEL_SIZE="$new_model_size"
  else
    info "Keeping current model: ${CURRENT_MODEL_ID}"
    MODEL_UPDATE_NEEDED=false
  fi

  export MODEL_UPDATE_NEEDED
  export NEW_MODEL_ID
  export NEW_MODEL_SIZE
}

# -----------------------------------------------------------------------------
# 4. Download new model if needed
# -----------------------------------------------------------------------------

download_new_model() {
  if [[ "${MODEL_UPDATE_NEEDED:-false}" != "true" ]]; then
    return
  fi

  section "Downloading New Model: ${NEW_MODEL_ID}"

  local models_json="${INSTALL_DIR}/models.json"

  local new_repo new_file
  new_repo="$(python3 -c "
import json
with open('${models_json}') as f:
    models = json.load(f)
for m in models:
    if m['id'] == '${NEW_MODEL_ID}':
        print(m['repo'])
")"

  new_file="$(python3 -c "
import json
with open('${models_json}') as f:
    models = json.load(f)
for m in models:
    if m['id'] == '${NEW_MODEL_ID}':
        print(m['file'])
")"

  local new_model_path="${MODELS_DIR}/${new_file}"

  info "Downloading ${new_file} (${NEW_MODEL_SIZE}GB)..."
  info "This may take 5–20 minutes depending on your internet speed."

  huggingface-cli download "${new_repo}" \
    "${new_file}" \
    --local-dir "${MODELS_DIR}" \
    --resume-download \
    || fail "Model download failed. Run local-ai-update again to resume."

  ok "New model downloaded: ${new_model_path}"

  # Remove old model to free disk space
  # Guard: path must be non-empty, inside ~/models, and different from new path
  if [[ -n "${CURRENT_MODEL_PATH}" && \
        "${CURRENT_MODEL_PATH}" == "${MODELS_DIR}/"* && \
        "${CURRENT_MODEL_PATH}" != "${new_model_path}" && \
        -f "${CURRENT_MODEL_PATH}" ]]; then
    info "Removing old model to free disk space: ${CURRENT_MODEL_PATH}"
    rm -f "${CURRENT_MODEL_PATH}"
    ok "Old model removed"
  else
    warn "Skipping old model removal — path guard failed (safe, no files deleted)"
  fi

  # Update aliases to point to new model
  update_aliases_for_new_model "$new_model_path" "$new_file"

  # Update state file
  update_state_file "$new_model_path" "$new_file"
}

# -----------------------------------------------------------------------------
# 5. Update aliases to point to new model
# -----------------------------------------------------------------------------

update_aliases_for_new_model() {
  local new_path="$1"
  local new_file="$2"

  local shell_profile
  shell_profile="$(python3 -c "import json; d=json.load(open('${STATE_FILE}')); print(d.get('shell_profile',''))" 2>/dev/null || echo "${HOME}/.zshrc")"

  if [[ ! -f "$shell_profile" ]]; then
    warn "Shell profile not found at ${shell_profile} — aliases not updated"
    return
  fi

  # Replace old model path in local-ai-start alias
  local old_path="${CURRENT_MODEL_PATH}"

  if grep -q "$old_path" "$shell_profile" 2>/dev/null; then
    # Use python3 for safe in-place replacement (avoids sed -i portability issues)
    python3 - <<EOF
content = open("${shell_profile}").read()
content = content.replace("${old_path}", "${new_path}")
open("${shell_profile}", "w").write(content)
EOF
    ok "Updated local-ai-start alias to use new model"
  else
    warn "Could not locate old model path in ${shell_profile} — you may need to update local-ai-start manually"
  fi
}

# -----------------------------------------------------------------------------
# 6. Update state file
# -----------------------------------------------------------------------------

update_state_file() {
  local new_path="$1"
  local new_file="$2"

  python3 - <<EOF
import json
from datetime import datetime, timezone

with open("${STATE_FILE}") as f:
    state = json.load(f)

state["model_id"] = "${NEW_MODEL_ID}"
state["model_file"] = "${new_file}"
state["model_path"] = "${new_path}"
state["updated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

with open("${STATE_FILE}", "w") as f:
    json.dump(state, f, indent=2)
EOF

  ok "State file updated"
}

# -----------------------------------------------------------------------------
# 7. Update Aider
# -----------------------------------------------------------------------------

update_aider() {
  section "Updating Aider"

  if ! command -v pipx &>/dev/null; then
    warn "pipx not found — skipping Aider update"
    return
  fi

  pipx upgrade aider-chat 2>/dev/null && \
    ok "Aider updated to $(aider --version 2>/dev/null | head -1)" || \
    ok "Aider is already up to date"
}

# -----------------------------------------------------------------------------
# 8. Update Llama.cpp via GitHub releases
# -----------------------------------------------------------------------------

update_llama() {
  section "Updating Llama.cpp"

  local llama_bin="${HOME}/.local-ai/bin/llama-server"
  local version_file="${HOME}/.local-ai/.llama_version"
  local current_version="unknown"

  if [[ -f "$version_file" ]]; then
    current_version="$(cat "$version_file")"
  fi

  info "Current Llama.cpp version: ${current_version}"
  info "Checking GitHub for latest release..."

  local chip_type
  chip_type="$(python3 -c "import json; d=json.load(open('${STATE_FILE}')); print(d.get('chip_type','apple_silicon'))" 2>/dev/null || echo "apple_silicon")"

  local asset_pattern
  if [[ "$chip_type" == "apple_silicon" ]]; then
    asset_pattern="macos-arm64"
  else
    asset_pattern="macos-x86_64"
  fi

  local release_json
  release_json="$(curl -fsSL --max-time 15 "https://api.github.com/repos/ggerganov/llama.cpp/releases/latest" 2>/dev/null)" || {
    warn "Could not reach GitHub API — skipping Llama.cpp update"
    return
  }

  local latest_tag download_url
  latest_tag="$(python3 -c "import json; d=json.loads('''${release_json}'''); print(d.get('tag_name',''))" 2>/dev/null || echo "")"
  download_url="$(python3 - <<EOF
import json, sys
data = json.loads("""${release_json}""")
for asset in data.get("assets", []):
    name = asset.get("name", "")
    if "${asset_pattern}" in name and name.endswith(".zip") and "llama" in name.lower():
        print(asset["browser_download_url"])
        sys.exit(0)
print("")
EOF
)"

  if [[ -z "$latest_tag" || -z "$download_url" ]]; then
    warn "Could not determine latest Llama.cpp release — skipping update"
    return
  fi

  if [[ "$current_version" == "$latest_tag" ]]; then
    ok "Llama.cpp is already up to date (${current_version})"
    return
  fi

  info "Updating Llama.cpp: ${current_version} → ${latest_tag}"

  # Detect archive format from URL
  local tmp_archive
  if [[ "$download_url" == *.tar.gz ]]; then
    tmp_archive="$(mktemp).tar.gz"
  else
    tmp_archive="$(mktemp).zip"
  fi
  chmod 600 "$tmp_archive"

  curl -fsSL --max-time 120 "$download_url" -o "$tmp_archive" || {
    warn "Download failed — keeping existing Llama.cpp version"
    rm -f "$tmp_archive"
    return
  }

  local llama_bin_dir="${HOME}/.local-ai/bin"
  mkdir -p "$llama_bin_dir"
  if [[ "$tmp_archive" == *.tar.gz ]]; then
    tar -xzf "$tmp_archive" -C "$llama_bin_dir" || { warn "Extract failed"; rm -f "$tmp_archive"; return; }
  else
    unzip -q "$tmp_archive" -d "$llama_bin_dir" || { warn "Extract failed"; rm -f "$tmp_archive"; return; }
  fi
  rm -f "$tmp_archive"

  # Promote binaries from nested dir if needed
  local nested_server
  nested_server="$(find "$llama_bin_dir" -name "llama-server" -not -path "$llama_bin_dir/llama-server" | head -1)"
  if [[ -n "$nested_server" ]]; then
    mv "$(dirname "$nested_server")"/* "$llama_bin_dir/" 2>/dev/null || true
    rmdir "$(dirname "$nested_server")" 2>/dev/null || true
  fi

  chmod +x "${llama_bin_dir}"/llama-* 2>/dev/null || true
  echo "$latest_tag" > "$version_file"

  ok "Llama.cpp updated to ${latest_tag}"
}

# -----------------------------------------------------------------------------
# 9. Summary
# -----------------------------------------------------------------------------

print_update_summary() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Update Complete"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [[ "${MODEL_UPDATE_NEEDED:-false}" == "true" ]]; then
    echo "  Model updated  : ${CURRENT_MODEL_ID} → ${NEW_MODEL_ID}"
    echo ""
    echo "  Restart your terminal then run: local-ai-start"
  else
    echo "  Model          : ${CURRENT_MODEL_ID} (no change)"
    echo ""
    echo "  Run local-ai-start to launch your agent."
  fi

  echo ""
  echo "  Log: ${LOG_FILE}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  log "====== Update completed ======"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
  print_banner
  read_state
  update_scripts
  check_model_update
  download_new_model
  update_aider
  update_llama
  print_update_summary
}

main
