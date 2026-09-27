#!/usr/bin/env bash
set -Eeuo pipefail

: "${PORT:=3100}"
: "${HERMES_HOME:=/data/hermes}"
: "${PAPERCLIP_HOME:=/data/paperclip}"
: "${PAPERCLIP_INSTANCE_ID:=default}"
: "${FOUNDER_MODEL:=anthropic/claude-sonnet-4.6}"
: "${PAPERCLIP_DEPLOYMENT_MODE:=authenticated}"
: "${PAPERCLIP_DEPLOYMENT_EXPOSURE:=public}"

export HOME=/data
export PATH="/data/hermes/.local/bin:/root/.local/bin:$PATH"

mkdir -p "$HERMES_HOME"/{company,workspace,memory,logs,skills} \
         "$PAPERCLIP_HOME"

# Founder OS is immutable in the image but copied into persistent state once.
if [[ ! -f "$HERMES_HOME/company/SOUL.md" ]]; then
  cp /opt/founder/*.md "$HERMES_HOME/company/"
fi

# Install the bundled Founder skill pack once; later upgrades can be applied
# with /opt/founder-scripts/update-founder-skills.sh.
if [[ ! -f "$HERMES_HOME/skills/.founder-installed" ]]; then
  cp -R /opt/founder-skills/. "$HERMES_HOME/skills/"
  touch "$HERMES_HOME/skills/.founder-installed"
fi

# Security: public Paperclip deployments require an explicit canonical URL.
if [[ "$PAPERCLIP_DEPLOYMENT_MODE" == "authenticated" \
   && "$PAPERCLIP_DEPLOYMENT_EXPOSURE" == "public" \
   && -z "${PAPERCLIP_AUTH_PUBLIC_BASE_URL:-}" ]]; then
  echo "[founder] ERROR: PAPERCLIP_AUTH_PUBLIC_BASE_URL is required for public authenticated mode."
  echo "[founder] Example: https://founder-production.up.railway.app"
  exit 1
fi

# Configure Hermes provider/model without placing credentials in source files.
if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
  hermes config set OPENROUTER_API_KEY "$OPENROUTER_API_KEY"
  hermes config set model.provider openrouter
  hermes config set model "$FOUNDER_MODEL"
elif [[ -n "${OPENAI_API_KEY:-}" ]]; then
  hermes config set OPENAI_API_KEY "$OPENAI_API_KEY"
elif [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  hermes config set ANTHROPIC_API_KEY "$ANTHROPIC_API_KEY"
else
  echo "[founder] ERROR: Set OPENROUTER_API_KEY, OPENAI_API_KEY, or ANTHROPIC_API_KEY."
  exit 1
fi

# Generate a dedicated Hermes gateway credential if one was not supplied.
# It is persisted with the rest of the Hermes state and never printed.
if [[ -z "${API_SERVER_KEY:-}" ]]; then
  if [[ -f "$HERMES_HOME/.gateway-key" ]]; then
    API_SERVER_KEY="$(cat "$HERMES_HOME/.gateway-key")"
  else
    API_SERVER_KEY="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(48))
PY
)"
    umask 077
    printf '%s' "$API_SERVER_KEY" > "$HERMES_HOME/.gateway-key"
  fi
fi
export API_SERVER_ENABLED=true
export API_SERVER_KEY

# Configure Paperclip public server settings. Paperclip's embedded PostgreSQL
# is persistent because PAPERCLIP_HOME is mounted on the Railway volume.
export HOST=0.0.0.0
export PAPERCLIP_PORT="$PORT"

# First boot: onboard Paperclip. The command is idempotent once the config exists.
if [[ ! -f "$PAPERCLIP_HOME/instances/$PAPERCLIP_INSTANCE_ID/config.json" ]]; then
  echo "[founder] Running Paperclip onboarding..."
  paperclipai onboard --yes
fi

# Repair/check configuration before starting.
paperclipai doctor --repair || paperclipai doctor

# Start Paperclip.
echo "[founder] Starting Paperclip..."
paperclipai run >"$PAPERCLIP_HOME/paperclip.log" 2>&1 &
PAPERCLIP_PID=$!

# Wait for the documented Paperclip health endpoint.
READY=0
for _ in $(seq 1 120); do
  if curl -fsS --max-time 2 "http://127.0.0.1:${PORT}/api/health" >/dev/null 2>&1; then
    READY=1
    break
  fi
  if ! kill -0 "$PAPERCLIP_PID" 2>/dev/null; then
    echo "[founder] Paperclip exited during startup."
    tail -250 "$PAPERCLIP_HOME/paperclip.log" || true
    exit 1
  fi
  sleep 2
done

if [[ "$READY" != "1" ]]; then
  echo "[founder] Paperclip did not become ready."
  tail -250 "$PAPERCLIP_HOME/paperclip.log" || true
  exit 1
fi

# Hermes gateway is private to this container. Paperclip connects to it via
# localhost:8642 using the dedicated API_SERVER_KEY.
echo "[founder] Starting Hermes gateway..."
hermes gateway run --replace --accept-hooks >"$HERMES_HOME/logs/gateway.log" 2>&1 &
HERMES_PID=$!

# Supervise both children. Railway sees this process as the service.
cleanup() {
  kill "$HERMES_PID" 2>/dev/null || true
  kill "$PAPERCLIP_PID" 2>/dev/null || true
  wait "$HERMES_PID" 2>/dev/null || true
  wait "$PAPERCLIP_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

python3 /usr/local/bin/founder-health "$PORT" "$PORT" &
HEALTH_PID=$!

trap 'kill "$HEALTH_PID" 2>/dev/null || true; cleanup' EXIT INT TERM

echo "[founder] Founder service online."
echo "[founder] Paperclip: http://127.0.0.1:${PORT}"
echo "[founder] Hermes gateway: http://127.0.0.1:8642"
echo "[founder] Persistent state: ${HERMES_HOME} + ${PAPERCLIP_HOME}"

while true; do
  if ! kill -0 "$PAPERCLIP_PID" 2>/dev/null; then
    echo "[founder] Paperclip stopped."
    tail -250 "$PAPERCLIP_HOME/paperclip.log" || true
    exit 1
  fi
  if ! kill -0 "$HERMES_PID" 2>/dev/null; then
    echo "[founder] Hermes gateway stopped."
    tail -250 "$HERMES_HOME/logs/gateway.log" || true
    exit 1
  fi
  sleep 5
done
