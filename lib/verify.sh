#!/usr/bin/env bash
# =============================================================================
# verify.sh — Post-Setup Verification Module
# your-local-agent | github.com/you/your-local-agent
#
# Runs a series of checks after setup to confirm everything works end to end.
# Starts the server, sends a test prompt, reports pass/fail per check.
# Reads variables exported by detect.sh, download.sh, and configure.sh.
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

# Result tracking
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

pass() { echo "  ✅  $*"; log "PASS  $*"; (( PASS_COUNT++ )); }
fail_check() { echo "  ❌  $*"; log "FAIL  $*"; (( FAIL_COUNT++ )); }
warn_check() { echo "  ⚠️  $*"; log "WARN  $*"; (( WARN_COUNT++ )); }

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------

LLAMA_PORT=8080
LOCAL_AI_DIR="${HOME}/.local-ai"
SERVER_LOG="${LOCAL_AI_DIR}/server.log"
SERVER_STARTUP_WAIT=8    # seconds to wait for server to be ready
TEST_PROMPT="Reply with exactly three words: setup is working"

# -----------------------------------------------------------------------------
# Guard — ensure required variables are set
# -----------------------------------------------------------------------------

guard_prerequisites() {
  if [[ -z "${MODEL_PATH:-}" ]]; then
    fail "verify.sh requires MODEL_PATH from download.sh. Run the full setup first."
  fi

  if [[ -z "${CHIP_TYPE:-}" ]]; then
    fail "verify.sh requires CHIP_TYPE from detect.sh. Run the full setup first."
  fi
}

# -----------------------------------------------------------------------------
# 1. Binary checks
# -----------------------------------------------------------------------------

check_binaries() {
  section "Checking Installed Binaries"

  local binaries=("brew" "python3" "aider" "huggingface-cli")

  for binary in "${binaries[@]}"; do
    if command -v "$binary" &>/dev/null; then
      pass "${binary} found at $(command -v "$binary")"
    else
      fail_check "${binary} not found in PATH — installation may have failed"
    fi
  done

  # Check Llama.cpp binary specifically in its install dir
  local llama_bin="${HOME}/.local-ai/bin/llama-server"
  if [[ -x "$llama_bin" ]]; then
    pass "llama-server found at ${llama_bin}"
  else
    fail_check "llama-server not found at ${llama_bin} — Llama.cpp installation may have failed"
  fi
}

# -----------------------------------------------------------------------------
# 2. Model file check
# -----------------------------------------------------------------------------

check_model_file() {
  section "Checking Model File"

  if [[ ! -f "${MODEL_PATH}" ]]; then
    fail_check "Model file not found at ${MODEL_PATH}"
    return
  fi

  local size_bytes size_gb
  size_bytes="$(stat -f%z "${MODEL_PATH}" 2>/dev/null || stat -c%s "${MODEL_PATH}" 2>/dev/null)"
  size_gb=$(python3 -c "print(round(${size_bytes} / 1024 / 1024 / 1024, 2))")

  if [[ "$size_bytes" -gt 0 ]]; then
    pass "Model file exists — ${MODEL_PATH} (${size_gb}GB)"
  else
    fail_check "Model file is empty — download may have failed"
  fi
}

# -----------------------------------------------------------------------------
# 3. Aider config check
# -----------------------------------------------------------------------------

check_aider_config() {
  section "Checking Pi Configuration"

  local aider_config="${HOME}/.aider/.aider.conf.yml"

  if [[ ! -f "$aider_config" ]]; then
    fail_check "Aider config not found at ${aider_config}"
    return
  fi

  # Verify endpoint is pointing to localhost
  local endpoint
  endpoint="$(python3 -c "import json; d=json.load(open('${aider_config}')); print(d.get('endpoint',''))" 2>/dev/null || echo "")"

  if [[ "$endpoint" == "http://localhost:${LLAMA_PORT}/v1" ]]; then
    pass "Aider config points to local server (${endpoint})"
  else
    fail_check "Aider config endpoint is incorrect: '${endpoint}' — expected http://localhost:${LLAMA_PORT}/v1"
  fi

  # Verify model file is referenced
  local model_file
  model_file="$(python3 -c "import json; d=json.load(open('${aider_config}')); print(d.get('model_file',''))" 2>/dev/null || echo "")"

  if [[ -n "$model_file" ]]; then
    pass "Aider config references model: ${model_file}"
  else
    warn_check "Aider config does not reference a model file"
  fi
}

# -----------------------------------------------------------------------------
# 4. Shell aliases check
# -----------------------------------------------------------------------------

check_aliases() {
  section "Checking Shell Aliases"

  local profile="${SHELL_PROFILE:-${HOME}/.zshrc}"

  if [[ ! -f "$profile" ]]; then
    fail_check "Shell profile not found at ${profile}"
    return
  fi

  local aliases=("local-ai-start" "local-ai-stop" "local-ai-status" "local-ai-info" "local-ai-update")

  for alias_name in "${aliases[@]}"; do
    if grep -q "alias ${alias_name}=" "$profile" 2>/dev/null; then
      pass "Alias '${alias_name}' found in ${profile}"
    else
      fail_check "Alias '${alias_name}' not found in ${profile}"
    fi
  done

  # Check Aider config exists
  local aider_config="${HOME}/.aider/.aider.conf.yml"
  if [[ -f "$aider_config" ]]; then
    pass "Aider config found at ${aider_config}"
  else
    fail_check "Aider config not found at ${aider_config}"
  fi
}

# -----------------------------------------------------------------------------
# 5. Port availability check
# -----------------------------------------------------------------------------

check_port() {
  section "Checking Server Port"

  if lsof -i ":${LLAMA_PORT}" &>/dev/null; then
    warn_check "Port ${LLAMA_PORT} is already in use — another process may conflict with the server"
    info "Kill the existing process with: lsof -ti :${LLAMA_PORT} | xargs kill -9"
  else
    pass "Port ${LLAMA_PORT} is free and ready"
  fi
}

# -----------------------------------------------------------------------------
# 6. Start test server
# -----------------------------------------------------------------------------

start_test_server() {
  section "Starting Test Server"

  pkill -f "llama-server" 2>/dev/null || true
  sleep 1

  local llama_bin="${HOME}/.local-ai/bin/llama-server"

  if [[ ! -x "$llama_bin" ]]; then
    fail_check "llama-server not found at ${llama_bin} — cannot start test server"
    return 1
  fi

  local gpu_layers=99
  if [[ "${CHIP_TYPE}" == "intel" ]]; then
    gpu_layers=0
  fi

  info "Starting llama-server with ${MODEL_PATH}..."
  info "This may take 10–15 seconds on first load..."

  "$llama_bin" \
    -m "${MODEL_PATH}" \
    --port "${LLAMA_PORT}" \
    -ngl "${gpu_layers}" \
    -c 512 \
    --threads 4 \
    --log-disable \
    > "${SERVER_LOG}" 2>&1 &

  SERVER_PID=$!
  export SERVER_PID

  local elapsed=0
  local max_wait=60

  while [[ "$elapsed" -lt "$max_wait" ]]; do
    if curl -sfo /dev/null "http://localhost:${LLAMA_PORT}/health" 2>/dev/null; then
      pass "Server started and healthy (PID: ${SERVER_PID})"
      return 0
    fi

    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
      fail_check "Server process died unexpectedly — check log: ${SERVER_LOG}"
      return 1
    fi

    sleep 2
    elapsed=$(( elapsed + 2 ))
    info "Waiting for server... (${elapsed}s)"
  done

  fail_check "Server did not become ready within ${max_wait}s — check log: ${SERVER_LOG}"
  return 1
}

# -----------------------------------------------------------------------------
# 7. Health endpoint check
# -----------------------------------------------------------------------------

check_health_endpoint() {
  section "Checking Server Health Endpoint"

  local response
  response="$(curl -s --max-time 5 "http://localhost:${LLAMA_PORT}/health" 2>/dev/null || echo "")"

  if [[ -n "$response" ]]; then
    pass "Health endpoint responding: ${response}"
  else
    fail_check "Health endpoint not responding at http://localhost:${LLAMA_PORT}/health"
  fi
}

# -----------------------------------------------------------------------------
# 8. Test prompt
# -----------------------------------------------------------------------------

send_test_prompt() {
  section "Sending Test Prompt"

  info "Sending: \"${TEST_PROMPT}\""

  local response
  response="$(curl -s --max-time 30 \
    "http://localhost:${LLAMA_PORT}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"local\",
      \"messages\": [{\"role\": \"user\", \"content\": \"${TEST_PROMPT}\"}],
      \"max_tokens\": 20,
      \"temperature\": 0
    }" 2>/dev/null || echo "")"

  if [[ -z "$response" ]]; then
    fail_check "No response from model — server may not be running correctly"
    return
  fi

  # Extract text from response
  local model_reply
  model_reply="$(python3 - <<EOF
import json, sys
try:
    d = json.loads('''${response}''')
    print(d["choices"][0]["message"]["content"].strip())
except Exception as e:
    print("")
EOF
)"

  if [[ -n "$model_reply" ]]; then
    pass "Model responded: \"${model_reply}\""
  else
    fail_check "Could not parse model response — raw: ${response}"
  fi
}

# -----------------------------------------------------------------------------
# 9. Stop test server
# -----------------------------------------------------------------------------

stop_test_server() {
  section "Stopping Test Server"

  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    pass "Test server stopped (PID: ${SERVER_PID})"
  else
    # Fallback — kill any llama-server process
    pkill -f "llama-server" 2>/dev/null || true
    pass "Test server stopped"
  fi
}

# -----------------------------------------------------------------------------
# 10. Final report
# -----------------------------------------------------------------------------

print_verification_report() {
  local total=$(( PASS_COUNT + FAIL_COUNT + WARN_COUNT ))

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Verification Report"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Checks run     : ${total}"
  echo "  Passed         : ${PASS_COUNT}"
  echo "  Warnings       : ${WARN_COUNT}"
  echo "  Failed         : ${FAIL_COUNT}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  if [[ "$FAIL_COUNT" -eq 0 ]]; then
    echo "  🎉 Setup complete. Everything is working."
    echo ""
    echo "  To start your local agent:"
    echo ""
    echo "    source ${SHELL_PROFILE:-~/.zshrc}"
    echo "    ai-start"
    echo ""
    echo "  Full log: ${LOG_FILE}"
    log "Verification passed — ${PASS_COUNT} checks passed, ${WARN_COUNT} warnings"
  else
    echo "  ⚠️  Setup completed with ${FAIL_COUNT} failure(s)."
    echo ""
    echo "  Check the log for details:"
    echo "    cat ${LOG_FILE}"
    echo ""
    echo "  Common fixes:"
    echo "    → Restart terminal and run: source ${SHELL_PROFILE:-~/.zshrc}"
    echo "    → Re-run setup: bash setup.sh"
    echo "    → Open an issue: github.com/you/your-local-agent/issues"
    echo ""
    log "Verification completed with failures — ${FAIL_COUNT} failed, ${PASS_COUNT} passed, ${WARN_COUNT} warnings"
  fi

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
  echo ""
  echo "🔬 Running verification checks..."
  echo ""

  guard_prerequisites
  check_binaries
  check_model_file
  check_aider_config
  check_aliases
  check_port
  start_test_server
  check_health_endpoint
  send_test_prompt
  stop_test_server
  print_verification_report
}

main
