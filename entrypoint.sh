#!/usr/bin/env bash
set -Eeuo pipefail

: "${HERMES_HOME:=/opt/data}"
: "${API_SERVER_PORT:=8642}"
: "${PORT:=8642}"

mkdir -p "$HERMES_HOME"/{logs,workspace,memory,skills,company}

# Install the founder operating system into persistent storage on first boot.
if [[ ! -f "$HERMES_HOME/company/SOUL.md" ]]; then
  cp /opt/founder/SOUL.md "$HERMES_HOME/company/SOUL.md"
  cp /opt/founder/COMPANY.md "$HERMES_HOME/company/COMPANY.md"
  cp /opt/founder/DELEGATION.md "$HERMES_HOME/company/DELEGATION.md"
  cp /opt/founder/OPERATING_RULES.md "$HERMES_HOME/company/OPERATING_RULES.md"
  cp /opt/founder/FOUNDER_ROLES.md "$HERMES_HOME/company/FOUNDER_ROLES.md"
fi

# Preserve environment-backed secrets without putting them in the image.
python3 - <<'PY'
import os
from pathlib import Path
home=Path(os.environ.get("HERMES_HOME","/opt/data"))
p=home/"founder.env"
vals={}
if p.exists():
    for line in p.read_text().splitlines():
        if "=" in line and not line.startswith("#"):
            k,v=line.split("=",1); vals[k]=v
for k in ("OPENROUTER_API_KEY","OPENAI_API_KEY","ANTHROPIC_API_KEY","API_SERVER_KEY"):
    if os.environ.get(k):
        vals[k]=os.environ[k]
p.write_text("".join(f"{k}={v}\n" for k,v in vals.items()))
PY

# Optional curated skill bootstrap. It is idempotent and opt-in.
if [[ "${INSTALL_FOUNDER_SKILLS:-true}" == "true" ]] && command -v hermes >/dev/null 2>&1; then
  /opt/founder/install-skills.sh || true
fi

echo "[founder] starting Hermes gateway"
hermes gateway run --replace >"$HERMES_HOME/logs/hermes.log" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT INT TERM

for _ in $(seq 1 90); do
  if curl -fsS --max-time 2 "http://127.0.0.1:${API_SERVER_PORT}/health" >/dev/null 2>&1; then
    break
  fi
  kill -0 "$PID" 2>/dev/null || { tail -200 "$HERMES_HOME/logs/hermes.log"; exit 1; }
  sleep 2
done

curl -fsS --max-time 2 "http://127.0.0.1:${API_SERVER_PORT}/health" >/dev/null \
  || { tail -200 "$HERMES_HOME/logs/hermes.log"; exit 1; }

# Railway must see a listener on $PORT. Keep Hermes private and expose only
# an authenticated proxy.
cat >/tmp/proxy.py <<'PY'
import os, http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT=int(os.environ["PORT"])
UP=int(os.environ.get("API_SERVER_PORT","8642"))
KEY=os.environ.get("API_SERVER_KEY","")

class H(BaseHTTPRequestHandler):
    protocol_version="HTTP/1.1"
    def _go(self):
        if self.path != "/health" and KEY:
            if self.headers.get("Authorization","") != "Bearer "+KEY:
                self.send_response(401); self.send_header("Content-Length","0"); self.end_headers(); return
        n=int(self.headers.get("Content-Length","0"))
        body=self.rfile.read(n) if n else None
        c=http.client.HTTPConnection("127.0.0.1",UP,timeout=600)
        try:
            hs={k:v for k,v in self.headers.items()
                if k.lower() not in ("host","content-length","connection")}
            if body is not None: hs["Content-Length"]=str(len(body))
            c.request(self.command,self.path,body=body,headers=hs)
            r=c.getresponse(); data=r.read()
            self.send_response(r.status,r.reason)
            for k,v in r.getheaders():
                if k.lower() not in ("connection","transfer-encoding","content-length"):
                    self.send_header(k,v)
            self.send_header("Content-Length",str(len(data)))
            self.end_headers(); self.wfile.write(data)
        finally: c.close()
    do_GET=_go; do_POST=_go; do_PUT=_go; do_PATCH=_go; do_DELETE=_go
    def log_message(self,f,*a): print("[proxy]",f%a,flush=True)

ThreadingHTTPServer(("0.0.0.0",PORT),H).serve_forever()
PY

exec python3 /tmp/proxy.py
