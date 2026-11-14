#!/usr/bin/env bash
# End-to-end tests for the `cadre` CLI wrapper, `cadre.sh`, and `server.py`
# against ephemeral local mock HTTP backends, real `goose-cli`, and stub binaries.
set -euo pipefail

CADRE_BIN="${1:?usage: tests/cli.sh <path-to-cadre-bin> [path-to-cadre-sh] [path-to-server-py]}"
CADRE_SCRIPT="${2:-}"
SERVER_PY="${3:-}"

work=$(mktemp -d)
pids=()
cleanup() {
  for pid in "${pids[@]:-}"; do
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  rm -rf "$work"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

export HOME="$work/home"
export XDG_CONFIG_HOME="$work/config"
export XDG_STATE_HOME="$work/state"
export CADRE_NO_OPEN=1
stubs="$work/stubs"
bash_bin=$(command -v bash)
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$stubs"

cat >"$stubs/goose" <<EOF
#!$bash_bin
printf 'CMD=goose ARGS=%s PROVIDER=%s MODEL=%s TELEMETRY=%s OLLAMA_HOST=%s\n' \
  "\$*" "\${GOOSE_PROVIDER:-}" "\${GOOSE_MODEL:-}" "\${GOOSE_TELEMETRY_OFF:-}" "\${OLLAMA_HOST:-}" >"\$STUB_OUT"
EOF

cat >"$stubs/berd" <<EOF
#!$bash_bin
printf 'CMD=berd ARGS=%s PROVIDER=%s MODEL=%s TELEMETRY=%s\n' \
  "\$*" "\${GOOSE_PROVIDER:-}" "\${GOOSE_MODEL:-}" "\${GOOSE_TELEMETRY_OFF:-}" >"\$STUB_OUT"
EOF

cat >"$stubs/buzz-app" <<EOF
#!$bash_bin
printf 'CMD=buzz-app ARGS=%s TELEMETRY=%s\n' "\$*" "\${GOOSE_TELEMETRY_OFF:-}" >"\$STUB_OUT"
EOF

chmod +x "$stubs/goose" "$stubs/berd" "$stubs/buzz-app"

# 1. Version, help output, and malformed arguments on built wrapper binary.
ver_out=$("$CADRE_BIN" --version)
[ "$ver_out" = "cadre 0.1.0" ] || fail "unexpected --version output: $ver_out"
[ "$("$CADRE_BIN" -V)" = "cadre 0.1.0" ] || fail "unexpected -V output"

help_out=$("$CADRE_BIN" --help)
grep -q "cadre ◈" <<<"$help_out" || fail "--help missing banner"
grep -q -- "--backend" <<<"$help_out" || fail "--help missing --backend"
grep -q -- "--version" <<<"$help_out" || fail "--help missing --version"

for bad in "--backend" "--model" "--port" "--port 0" "--port 70000" "--port abc" "--join-file" "--app" "--app invalid" "--unknown-flag" "bogus-cmd"; do
  rc=0
  # shellcheck disable=SC2086
  "$CADRE_BIN" $bad >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || fail "expected exit 2 for '$bad', got $rc"
done

rc=0
"$CADRE_BIN" --backend bogus >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "expected exit 2 for '--backend bogus', got $rc"

rc=0
"$CADRE_BIN" --join-file "$work/does-not-exist" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "expected exit 1 for missing --join-file, got $rc"

# 2. Missing optional desktop clients fail cleanly with exit 1.
empty_bin="$work/empty-bin"
mkdir -p "$empty_bin"
rc=0
PATH="$empty_bin" "$CADRE_BIN" chat >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "expected exit 1 when buzz is missing, got $rc"

rc=0
PATH="$empty_bin" "$CADRE_BIN" gui >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "expected exit 1 when berd is missing, got $rc"

# 3. `chat` dispatches to buzz-app on PATH with GOOSE_TELEMETRY_OFF=1 and pass-through args.
export STUB_OUT="$work/out.txt"
PATH="$stubs:$PATH" "$CADRE_BIN" chat -- --relay wss://relay.example.test
grep -q "CMD=buzz-app ARGS=--relay wss://relay.example.test TELEMETRY=1" "$STUB_OUT" ||
  fail "unexpected chat stub output: $(cat "$STUB_OUT")"

# 4. Mock MeshLLM & Ollama HTTP servers (including OpenAI /v1/chat/completions).
mesh_port=$(free_port)
python3 - "$mesh_port" <<'PY' &
import http.server, json, sys
port = int(sys.argv[1])
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path == "/v1/models":
            body = json.dumps({"data": [{"id": "Qwen3-Test-4B"}]}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()
    def do_POST(self):
        if self.path == "/v1/chat/completions":
            length = int(self.headers.get("Content-Length") or "0")
            req = json.loads(self.rfile.read(length).decode())
            user_text = req["messages"][-1]["content"]
            body = json.dumps({
                "model": req["model"],
                "choices": [{"message": {"role": "assistant", "content": f"ack:{user_text}"}}],
            }).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
pids+=("$!")

ollama_port=$(free_port)
python3 - "$ollama_port" <<'PY' &
import http.server, json, sys
port = int(sys.argv[1])
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path == "/api/tags":
            body = json.dumps({"models": [{"name": "qwen2.5-coder:7b"}]}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == "/api/ps":
            body = json.dumps({"models": [{"name": "qwen2.5-coder:7b", "size_vram": 5368709120}]}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
pids+=("$!")

for _ in $(seq 1 30); do
  curl -fsS "http://127.0.0.1:$mesh_port/v1/models" >/dev/null 2>&1 &&
    curl -fsS "http://127.0.0.1:$ollama_port/api/tags" >/dev/null 2>&1 && break
  sleep 0.1
done

# Built wrapper end-to-end with real `goose-cli` (`-- --help` exits 0 after provider discovery)
"$CADRE_BIN" --backend auto --port "$mesh_port" -- --help >/dev/null

# `serve` against already-running backends exits 0 cleanly (both command-first and option-first).
serve_mesh=$("$CADRE_BIN" serve --backend mesh --port "$mesh_port")
grep -q "already running" <<<"$serve_mesh" || fail "expected mesh already running: $serve_mesh"

serve_ollama=$("$CADRE_BIN" --backend ollama serve --port "$ollama_port")
grep -q "already running" <<<"$serve_ollama" || fail "expected ollama already running: $serve_ollama"

# `gui` against Ollama invokes berd on PATH and writes atomic 32k custom provider JSON on 127.0.0.1.
: >"$STUB_OUT"
PATH="$stubs:$PATH" "$CADRE_BIN" gui --backend ollama --port "$ollama_port" >/dev/null
grep -q "CMD=berd" "$STUB_OUT" || fail "ollama gui failed: $(cat "$STUB_OUT")"
grep -q "MODEL=qwen2.5-coder:7b" "$STUB_OUT" || fail "ollama gui model mismatch: $(cat "$STUB_OUT")"
ollama_prov="$XDG_CONFIG_HOME/goose/custom_providers/cadre-ollama.json"
[ "$(jq -r '.models[0].context_limit' "$ollama_prov")" = "32768" ] || fail "expected 32768 context_limit"
[ "$(jq -r '.base_url' "$ollama_prov")" = "http://127.0.0.1:$ollama_port/v1" ] || fail "expected 127.0.0.1 base_url"

# 5. Direct script assertions with stub `goose` and ephemeral daemon cleanup.
if [ -n "$CADRE_SCRIPT" ]; then
  : >"$STUB_OUT"
  PATH="$stubs:$PATH" "$bash_bin" "$CADRE_SCRIPT" --backend auto --port "$mesh_port" -- --resume >/dev/null
  grep -q "MODEL=Qwen3-Test-4B" "$STUB_OUT" || fail "mesh auto model discovery failed: $(cat "$STUB_OUT")"
  grep -q "TELEMETRY=1" "$STUB_OUT" || fail "telemetry off not exported: $(cat "$STUB_OUT")"

  warn_err=$({ PATH="$stubs:$PATH" "$bash_bin" "$CADRE_SCRIPT" --backend mesh --port "$mesh_port" --model NonExistentModel >/dev/null; } 2>&1)
  grep -q "Warning: model 'NonExistentModel' is not served" <<<"$warn_err" ||
    fail "expected unserved model warning, got: $warn_err"
  grep -q "MODEL=Qwen3-Test-4B" "$STUB_OUT" || fail "fallback model not selected: $(cat "$STUB_OUT")"

  : >"$STUB_OUT"
  PATH="$stubs:$PATH" "$bash_bin" "$CADRE_SCRIPT" --backend auto --port "$ollama_port" >/dev/null
  grep -q "PROVIDER=ollama MODEL=qwen2.5-coder:7b TELEMETRY=1 OLLAMA_HOST=http://127.0.0.1:$ollama_port" "$STUB_OUT" ||
    fail "ollama auto session failed: $(cat "$STUB_OUT")"

  # Ephemeral MeshLLM spawn & cleanup: starts daemon on free port and kills it on exit.
  ephem_port=$(free_port)
  ephem_pid_file="$work/ephem-mesh.pid"
  cat >"$stubs/mesh-llm" <<EOF
#!$bash_bin
printf '%s\n' "\$*" >"$work/mesh-args.txt"
exec python3 - "$ephem_port" "$ephem_pid_file" <<'PY'
import http.server, json, os, sys
port = int(sys.argv[1])
with open(sys.argv[2], "w") as f:
    f.write(str(os.getpid()))
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path == "/v1/models":
            body = json.dumps({"data": [{"id": "Ephemeral-Model"}]}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
EOF
  chmod +x "$stubs/mesh-llm"

  join_tok="$work/join.tok"
  echo "invite-secret" >"$join_tok"
  : >"$STUB_OUT"
  PATH="$stubs:$PATH" "$bash_bin" "$CADRE_SCRIPT" --backend mesh --port "$ephem_port" --join-file "$join_tok" >/dev/null
  grep -q "MODEL=Ephemeral-Model" "$STUB_OUT" || fail "ephemeral mesh model not used: $(cat "$STUB_OUT")"
  grep -q -- "--join-file $join_tok" "$work/mesh-args.txt" || fail "--join-file not forwarded: $(cat "$work/mesh-args.txt")"
  if grep -Eq -- '--(auto|publish)' "$work/mesh-args.txt"; then
    fail "mesh-llm invoked with forbidden public flag: $(cat "$work/mesh-args.txt")"
  fi
  ephem_pid=$(cat "$ephem_pid_file")
  for _ in $(seq 1 20); do
    kill -0 "$ephem_pid" 2>/dev/null || break
    sleep 0.1
  done
  if kill -0 "$ephem_pid" 2>/dev/null; then
    fail "ephemeral mesh-llm pid $ephem_pid leaked after cadre exit"
  fi
fi

# 6. `cadre web` / `server.py` serves SPA fallback, security headers, live /api/status, and loopback /api/chat.
web_port=$(free_port)
CADRE_WEB_PORT="$web_port" "$CADRE_BIN" web --backend mesh --port "$mesh_port" >"$work/web.log" 2>&1 &
web_pid=$!
pids+=("$web_pid")

web_ready=0
for _ in $(seq 1 40); do
  if curl -fsS "http://127.0.0.1:$web_port/health" 2>/dev/null | grep -q '"ok"'; then
    web_ready=1
    break
  fi
  sleep 0.1
done
[ "$web_ready" -eq 1 ] || {
  cat "$work/web.log" >&2
  fail "cadre web failed health check on port $web_port"
}

# Security headers + SPA fallback for extensionless deep routes + 404 for missing assets
headers=$(curl -fsSI "http://127.0.0.1:$web_port/")
grep -qi "content-security-policy:" <<<"$headers" || fail "missing CSP header"
grep -qi "x-content-type-options: nosniff" <<<"$headers" || fail "missing nosniff header"

curl -fsS "http://127.0.0.1:$web_port/deep/spa/route" | grep -qi '<!doctype html>' ||
  fail "SPA fallback failed on /deep/spa/route"

missing_code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$web_port/missing-asset.js")
[ "$missing_code" = "404" ] || fail "expected 404 on /missing-asset.js, got $missing_code"

# Live /api/status probes our mock MeshLLM server
status_json=$(curl -fsS "http://127.0.0.1:$web_port/api/status")
[ "$(jq -r '.activeBackend' <<<"$status_json")" = "mesh" ] || fail "unexpected activeBackend: $status_json"
[ "$(jq -r '.defaultModel' <<<"$status_json")" = "Qwen3-Test-4B" ] || fail "unexpected defaultModel: $status_json"
[ "$(jq -r '.chatEnabled' <<<"$status_json")" = "true" ] || fail "expected chatEnabled=true on loopback"

# Loopback /api/chat proxies to local MeshLLM
chat_resp=$(curl -fsS -X POST "http://127.0.0.1:$web_port/api/chat" \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"hello cadre"}]}')
[ "$(jq -r '.reply' <<<"$chat_resp")" = "ack:hello cadre" ] || fail "unexpected /api/chat reply: $chat_resp"

kill -TERM "$web_pid" 2>/dev/null || true
wait "$web_pid" 2>/dev/null || true

# 7. `server.py` security invariants: SSRF upstream guard and non-loopback /api/chat gate.
if [ -n "$SERVER_PY" ]; then
  static_stub="$work/static"
  mkdir -p "$static_stub"
  echo '<!doctype html><title>stub</title>' >"$static_stub/index.html"

  rc=0
  python3 "$SERVER_PY" --static-dir "$static_stub" --mesh-url "http://10.0.0.1:9337" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || fail "expected SSRF guard exit 2 for non-loopback --mesh-url, got $rc"

  pub_port=$(free_port)
  python3 "$SERVER_PY" \
    --host 0.0.0.0 \
    --port "$pub_port" \
    --static-dir "$static_stub" \
    --backend ollama \
    --ollama-url "http://127.0.0.1:$ollama_port" &
  pub_pid=$!
  pids+=("$pub_pid")

  for _ in $(seq 1 30); do
    curl -fsS "http://127.0.0.1:$pub_port/health" >/dev/null 2>&1 && break
    sleep 0.1
  done

  pub_status=$(curl -fsS "http://127.0.0.1:$pub_port/api/status")
  [ "$(jq -r '.activeBackend' <<<"$pub_status")" = "ollama" ] || fail "expected ollama activeBackend: $pub_status"
  [ "$(jq -r '.nodes[0].vramUsedGb' <<<"$pub_status")" = "5" ] || [ "$(jq -r '.nodes[0].vramUsedGb' <<<"$pub_status")" = "5.0" ] ||
    fail "expected 5GB VRAM from /api/ps: $pub_status"
  [ "$(jq -r '.chatEnabled' <<<"$pub_status")" = "false" ] || fail "expected chatEnabled=false on 0.0.0.0 without flag"

  pub_chat_code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$pub_port/api/chat" \
    -H 'Content-Type: application/json' \
    -d '{"messages":[{"role":"user","content":"blocked"}]}')
  [ "$pub_chat_code" = "403" ] || fail "expected 403 on 0.0.0.0 /api/chat without --enable-chat-proxy, got $pub_chat_code"

  kill -TERM "$pub_pid" 2>/dev/null || true
  wait "$pub_pid" 2>/dev/null || true
fi

echo "cli: ok"
