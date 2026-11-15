#!/usr/bin/env bash
# cadre: private AI teammates on your own compute (Goose & ACP over local inference).
set -euo pipefail

VERSION="@version@"
VERSION="${VERSION/@version@/0.1.0}"
DEFAULT_WEB_DIR="@webDir@"
DEFAULT_SERVER_PY="@serverPy@"

usage() {
  cat <<'EOF'
cadre ◈ private AI teammates on your own compute

Usage: cadre [COMMAND] [OPTIONS] [-- CLIENT_ARGS...]

Commands:
  session            interactive pairing assistant in terminal (default)
  web                open Cadre web dashboard in your browser
  gui, desktop, berd start Berd desktop app on the local backend
  chat, buzz         open Buzz team chat application
  review             run local LLM code review (block-review) over git changes
  rules              manage cross-agent instructions and skills (ai-rules)
  agents             list declarative AI teammates configured on this host
  doctor, status     check local inference, ACP harnesses, tools, and MCP readiness
  serve              run the local inference node without opening a client

Options:
  --agent ID         select a declarative teammate by id or @handle (session)
  --backend BACKEND  inference engine: auto | mesh | ollama (default: $CADRE_BACKEND or auto)
  --model MODEL      model to serve/use (default: $CADRE_MODEL or Qwen3-8B-Q4_K_M / qwen2.5-coder)
  --port PORT        API port to connect to (default: 9337 for mesh, 11434 for ollama)
  --join-file PATH   join your private mesh with the invite token in PATH (mesh backend only)
  --app APP          alternate command selector: session | web | gui | chat | review | rules | agents | doctor | serve
  -V, --version      print version and exit
  -h, --help         show this help
EOF
}

validate_port() {
  local val="$1"
  local label="$2"
  if [[ ! "$val" =~ ^[0-9]+$ ]] || ((10#$val < 1 || 10#$val > 65535)); then
    echo "Invalid $label: '$val' (expected 1..65535)" >&2
    exit 2
  fi
}

parse_subcommand() {
  case "$1" in
    session | goose) echo "session" ;;
    web) echo "web" ;;
    gui | desktop | berd) echo "gui" ;;
    chat | buzz) echo "chat" ;;
    review) echo "review" ;;
    rules) echo "rules" ;;
    agents) echo "agents" ;;
    doctor | status) echo "doctor" ;;
    serve) echo "serve" ;;
    *) return 1 ;;
  esac
}

require_arg() {
  [ "$1" -ge 2 ] || {
    usage >&2
    exit 2
  }
}

resolve_agents_file() {
  local xdg_cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
  local candidate
  for candidate in "${CADRE_AGENTS_FILE:-}" "$xdg_cfg/cadre/agents.json" "/etc/cadre/agents.json"; do
    if [ -n "$candidate" ] && [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

resolve_server_py() {
  local script_dir
  script_dir="$(dirname "$(readlink -f "$0")")"
  local server_py="$DEFAULT_SERVER_PY"
  if [[ "$server_py" == "@serverPy@" ]] || [ ! -f "$server_py" ]; then
    if [ -f "$(dirname "$script_dir")/libexec/cadre/server.py" ]; then
      server_py="$(dirname "$script_dir")/libexec/cadre/server.py"
    elif [ -f "$script_dir/server.py" ]; then
      server_py="$script_dir/server.py"
    fi
  fi
  [ -f "$server_py" ] && echo "$server_py"
}

subcommand=""
agent_id=""
backend=${CADRE_BACKEND:-auto}
backend_explicit=0
model=${CADRE_MODEL:-}
model_explicit=${model:+1}
join_file=""
port=""
extra_args=()

while [ $# -gt 0 ]; do
  case "$1" in
    -V | --version)
      echo "cadre $VERSION"
      exit 0
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --app)
      require_arg $#
      subcommand=$(parse_subcommand "$2") || {
        usage >&2
        exit 2
      }
      shift 2
      ;;
    --agent | --as)
      require_arg $#
      agent_id="$2"
      shift 2
      ;;
    --backend)
      require_arg $#
      backend="$2"
      backend_explicit=1
      shift 2
      ;;
    --model)
      require_arg $#
      model="$2"
      model_explicit=1
      shift 2
      ;;
    --join-file)
      require_arg $#
      join_file="$2"
      shift 2
      ;;
    --port)
      require_arg $#
      validate_port "$2" "--port"
      port="$2"
      shift 2
      ;;
    --)
      shift
      extra_args+=("$@")
      break
      ;;
    -*)
      echo "Unknown option: $1 (pass '--' before client arguments)" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [ -z "$subcommand" ] && parsed=$(parse_subcommand "$1"); then
        subcommand="$parsed"
      else
        echo "Unexpected argument: $1 (pass '--' before client arguments)" >&2
        usage >&2
        exit 2
      fi
      shift
      ;;
  esac
done

subcommand=${subcommand:-session}

case "$backend" in
  auto | mesh | ollama) ;;
  *)
    echo "Unknown backend: $backend (valid: mesh, ollama, auto)" >&2
    exit 2
    ;;
esac

if [ -n "$join_file" ] && [ ! -r "$join_file" ]; then
  echo "Join token file is missing or unreadable: $join_file" >&2
  exit 1
fi

# Zero telemetry leaves the machine by default.
export GOOSE_TELEMETRY_OFF=${GOOSE_TELEMETRY_OFF:-1}

agent_system_prompt=""
if [ -n "$agent_id" ]; then
  agents_file=$(resolve_agents_file || true)
  if [ -z "$agents_file" ]; then
    echo "No declarative teammates configured (looked in \$CADRE_AGENTS_FILE, ~/.config/cadre/agents.json, /etc/cadre/agents.json)." >&2
    exit 1
  fi
  lookup_norm="${agent_id#@}"
  matched_json=$(jq -c --arg q "$agent_id" --arg qn "$lookup_norm" '
    map(select(.id == $q or .id == $qn or .handle == $q or .handle == ("@" + $qn))) | first // empty
  ' "$agents_file")
  if [ -z "$matched_json" ]; then
    echo "Unknown teammate '$agent_id'. Run 'cadre agents' to list configured teammates." >&2
    exit 1
  fi
  if [ "$backend_explicit" -eq 0 ]; then
    agent_backend=$(jq -r '.backend // empty' <<<"$matched_json")
    [ -n "$agent_backend" ] && backend="$agent_backend"
  fi
  if [ -z "$model_explicit" ]; then
    agent_model=$(jq -r '.model // empty' <<<"$matched_json")
    if [ -n "$agent_model" ]; then
      model="$agent_model"
      model_explicit=1
    fi
  fi
  agent_system_prompt=$(jq -r '.systemPrompt // empty' <<<"$matched_json")
fi

if [ "$subcommand" = "agents" ]; then
  agents_file=$(resolve_agents_file || true)
  if [ -z "$agents_file" ]; then
    echo "No declarative teammates configured on this host."
    echo "Declare teammates under 'services.cadre.agents' in NixOS or Home Manager."
    exit 0
  fi
  jq -r '.[] | "\(.handle)\t\(.name)\t[\(.harness // "goose") · \(.backend // "mesh") · \(if (.model // "") != "" then .model else "auto" end)]\t\(.role)"' "$agents_file"
  exit 0
fi

if [ "$subcommand" = "rules" ]; then
  if ! command -v ai-rules >/dev/null 2>&1; then
    echo "ai-rules is not installed; install 'ai-rules' or enable 'services.cadre.tools.enable'." >&2
    exit 1
  fi
  exec ai-rules "${extra_args[@]}"
fi

if [ "$subcommand" = "chat" ]; then
  for client in buzz-app buzz buzz-cli; do
    if command -v "$client" >/dev/null 2>&1; then
      exec "$client" "${extra_args[@]}"
    fi
  done
  echo "Buzz is not installed; install 'buzz-app' or enable 'services.cadre.desktop.enable'." >&2
  exit 1
fi

if [ "$subcommand" = "gui" ] && ! command -v berd >/dev/null 2>&1; then
  echo "Berd is not installed; install 'berd' or enable 'services.cadre.desktop.enable'." >&2
  exit 1
fi

if [ "$subcommand" = "review" ] && ! command -v review >/dev/null 2>&1; then
  echo "block-review is not installed; install 'block-review' or enable 'services.cadre.tools.enable'." >&2
  exit 1
fi

daemon_pid=""
cleanup() {
  local sig="${1:-EXIT}"
  if [ -n "$daemon_pid" ] && kill -0 "$daemon_pid" 2>/dev/null; then
    kill "$daemon_pid" 2>/dev/null || true
    for _ in $(seq 1 30); do
      kill -0 "$daemon_pid" 2>/dev/null || break
      sleep 0.1
    done
    kill -9 "$daemon_pid" 2>/dev/null || true
    wait "$daemon_pid" 2>/dev/null || true
  fi
  if [ "$sig" != "EXIT" ]; then
    trap - "$sig" EXIT
    kill "-$sig" $$ 2>/dev/null || exit 1
  fi
}
trap 'cleanup INT' INT
trap 'cleanup TERM' TERM
trap 'cleanup EXIT' EXIT

backend_endpoint() {
  if [ "$1" = "ollama" ]; then
    echo "http://127.0.0.1:$2/api/tags"
  else
    echo "http://127.0.0.1:$2/v1/models"
  fi
}

backend_alive() {
  curl -fsS --max-time 1 "$(backend_endpoint "$1" "$2")" >/dev/null 2>&1
}

probe_models() {
  local eng="$1"
  local p="$2"
  local raw
  raw=$(curl -fsS --max-time 2 "$(backend_endpoint "$eng" "$p")" 2>/dev/null) || return 0
  if [ "$eng" = "ollama" ]; then
    jq -r '.models[]?.name // empty' <<<"$raw" 2>/dev/null || true
  else
    jq -r '.data[]?.id // empty' <<<"$raw" 2>/dev/null || true
  fi
}

if [ "$subcommand" = "doctor" ]; then
  mesh_check_port=${port:-9337}
  ollama_check_port=${port:-11434}
  echo "cadre $VERSION ◈ local readiness"
  echo ""
  echo "Inference:"
  if backend_alive mesh "$mesh_check_port"; then
    mesh_first=$(probe_models mesh "$mesh_check_port" | head -n1)
    echo "  mesh-llm   [ready]   http://127.0.0.1:$mesh_check_port/v1 (${mesh_first:-no models loaded})"
  elif command -v mesh-llm >/dev/null 2>&1; then
    echo "  mesh-llm   [standby] installed ($(command -v mesh-llm))"
  else
    echo "  mesh-llm   [missing] not in PATH"
  fi
  if backend_alive ollama "$ollama_check_port"; then
    ollama_first=$(probe_models ollama "$ollama_check_port" | head -n1)
    echo "  ollama     [ready]   http://127.0.0.1:$ollama_check_port/v1 (${ollama_first:-no models loaded})"
  elif command -v ollama >/dev/null 2>&1; then
    echo "  ollama     [standby] installed ($(command -v ollama))"
  else
    echo "  ollama     [missing] not in PATH"
  fi

  echo ""
  echo "ACP Harnesses:"
  for h in goose buzz-agent pi-acp amp-acp; do
    if command -v "$h" >/dev/null 2>&1; then
      printf '  %-10s [ready]   %s\n' "$h" "$(command -v "$h")"
    else
      printf '  %-10s [missing]\n' "$h"
    fi
  done

  echo ""
  echo "Builder Toolkit:"
  for tool in review ai-rules braindump berd buzz-app buzz; do
    if command -v "$tool" >/dev/null 2>&1; then
      printf '  %-10s [ready]   %s\n' "$tool" "$(command -v "$tool")"
    else
      printf '  %-10s [missing]\n' "$tool"
    fi
  done

  server_py=$(resolve_server_py || true)
  goose_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/goose/config.yaml"
  if [ -n "$server_py" ] && [ -f "$goose_cfg" ]; then
    echo ""
    echo "Goose MCP Extensions ($goose_cfg):"
    python3 - "$server_py" "$goose_cfg" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("cadre_server", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
exts = mod.scan_goose_extensions(sys.argv[2])
if not exts:
    print("  (none configured)")
else:
    for ext in exts:
        state = "ready" if ext.get("enabled", True) else "disabled"
        print(f"  {ext['id']:<14} [{state}] ({ext['type']})")
PY
  fi
  exit 0
fi

write_custom_provider() {
  local filename="$1"
  local name="$2"
  local display="$3"
  local desc="$4"
  local base_url="$5"
  local mdl="$6"
  local nonce="${7:-}"
  local providers="${XDG_CONFIG_HOME:-$HOME/.config}/goose/custom_providers"
  local target="$providers/$filename"

  mkdir -p "$providers"
  [ -L "$target" ] && return 0

  local tmp
  tmp=$(mktemp "$providers/.cadre-provider.XXXXXX")
  jq -n \
    --arg name "$name" \
    --arg display "$display" \
    --arg desc "$desc" \
    --arg base "$base_url" \
    --arg model "$mdl" \
    --arg nonce "$nonce" \
    '{
      name: $name,
      engine: "openai",
      display_name: $display,
      description: $desc,
      api_key_env: "",
      base_url: $base,
      models: [{name: $model, context_limit: 32768}],
      timeout_seconds: 600,
      supports_streaming: true,
      requires_auth: false
    } + (if $nonce != "" then {nonce_header: $nonce} else {} end)' >"$tmp"
  chmod 0644 "$tmp"
  mv -f "$tmp" "$target"
}

run_client() {
  if [ -z "$daemon_pid" ]; then
    exec "$@"
  else
    "$@"
  fi
}

if [ "$backend" = "auto" ]; then
  mesh_probe=${port:-9337}
  ollama_probe=${port:-11434}
  if backend_alive mesh "$mesh_probe"; then
    backend="mesh"
    port="$mesh_probe"
  elif backend_alive ollama "$ollama_probe"; then
    backend="ollama"
    port="$ollama_probe"
  else
    backend="mesh"
  fi
fi

if [ "$backend" = "ollama" ]; then
  port=${port:-11434}
  default_model="qwen2.5-coder"
else
  port=${port:-9337}
  default_model="Qwen3-8B-Q4_K_M"
fi

if [ "$subcommand" = "web" ]; then
  if [ -z "$model_explicit" ]; then
    first_served=""
    IFS= read -r first_served < <(probe_models "$backend" "$port") || true
    model=${first_served:-$default_model}
  fi
  model=${model:-$default_model}

  web_host=${CADRE_WEB_HOST:-127.0.0.1}
  web_port=${CADRE_WEB_PORT:-8384}
  validate_port "$web_port" "CADRE_WEB_PORT"

  script_dir="$(dirname "$(readlink -f "$0")")"
  web_dir="${CADRE_WEB_DIR:-}"
  if [ -z "$web_dir" ]; then
    if [[ "$DEFAULT_WEB_DIR" != "@webDir@" ]] && [ -d "$DEFAULT_WEB_DIR" ]; then
      web_dir="$DEFAULT_WEB_DIR"
    elif [ -d "$(dirname "$script_dir")/share/cadre/web" ]; then
      web_dir="$(dirname "$script_dir")/share/cadre/web"
    elif [ -d "$script_dir/../../web/build" ]; then
      web_dir="$script_dir/../../web/build"
    fi
  fi

  server_py=$(resolve_server_py || true)
  if [ -z "$web_dir" ] || [ ! -d "$web_dir" ] || [ -z "$server_py" ]; then
    echo "Cadre Web assets not found. Build with 'nix build .#web' or 'npm --prefix web run build'." >&2
    exit 1
  fi

  mesh_port=$([ "$backend" = "mesh" ] && echo "$port" || echo "9337")
  ollama_port=$([ "$backend" = "ollama" ] && echo "$port" || echo "11434")
  echo "Serving Cadre Web on http://$web_host:$web_port (backend: $backend, model: $model)..."

  if [ -z "${CADRE_NO_OPEN:-}" ] && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }; then
    if command -v xdg-open >/dev/null 2>&1; then
      xdg-open "http://127.0.0.1:$web_port" >/dev/null 2>&1 &
    fi
  fi

  server_args=(
    --host "$web_host"
    --port "$web_port"
    --static-dir "$web_dir"
    --backend "$backend"
    --default-model "$model"
    --mesh-url "http://127.0.0.1:$mesh_port"
    --ollama-url "http://127.0.0.1:$ollama_port"
  )
  agents_file=$(resolve_agents_file || true)
  if [ -n "$agents_file" ]; then
    server_args+=(--agents-file "$agents_file")
  fi
  exec python3 "$server_py" "${server_args[@]}"
fi

if ! backend_alive "$backend" "$port"; then
  start_model=${model:-$default_model}
  if [ "$backend" = "ollama" ]; then
    if ! command -v ollama >/dev/null 2>&1; then
      echo "Ollama is not running on http://127.0.0.1:$port and 'ollama' was not found in PATH." >&2
      echo "Start Ollama or pass --backend mesh." >&2
      exit 1
    fi
    if [ "$subcommand" = "serve" ]; then
      echo "Starting Ollama daemon on port $port..."
      exec env OLLAMA_HOST="127.0.0.1:$port" ollama serve
    fi
    echo "Starting local Ollama daemon on port $port..."
    OLLAMA_HOST="127.0.0.1:$port" ollama serve >/dev/null 2>&1 &
    daemon_pid=$!
    echo "Waiting for Ollama to become ready..."
    until backend_alive ollama "$port"; do
      if ! kill -0 "$daemon_pid" 2>/dev/null; then
        echo "Ollama stopped unexpectedly" >&2
        exit 1
      fi
      sleep 1
    done
  else
    if ! command -v mesh-llm >/dev/null 2>&1; then
      echo "MeshLLM is not running on http://127.0.0.1:$port and 'mesh-llm' was not found in PATH." >&2
      echo "Install 'mesh-llm' or pass --backend ollama." >&2
      exit 1
    fi
    serve_args=(serve --model "$start_model" --port "$port")
    if [ -n "$join_file" ]; then
      serve_args+=(--join-file "$join_file")
    fi
    if [ "$subcommand" = "serve" ]; then
      echo "Starting MeshLLM node with $start_model on port $port..."
      exec mesh-llm "${serve_args[@]}"
    fi
    state="${XDG_STATE_HOME:-$HOME/.local/state}/cadre"
    mkdir -p "$state"
    echo "Starting a private MeshLLM node with $start_model (log: $state/mesh-llm.log)"
    mesh-llm "${serve_args[@]}" >"$state/mesh-llm.log" 2>&1 &
    daemon_pid=$!
    echo "Waiting for the model; the first start downloads it."
    until [ -n "$(probe_models mesh "$port")" ]; do
      if ! kill -0 "$daemon_pid" 2>/dev/null; then
        echo "MeshLLM stopped, see $state/mesh-llm.log" >&2
        exit 1
      fi
      sleep 2
    done
  fi
elif [ "$subcommand" = "serve" ]; then
  label="MeshLLM node"
  [ "$backend" = "ollama" ] && label="Ollama"
  echo "$label is already running on http://127.0.0.1:$port."
  exit 0
fi

served=()
while IFS= read -r line; do
  [ -n "$line" ] && served+=("$line")
done < <(probe_models "$backend" "$port")
if [ "${#served[@]}" -gt 0 ]; then
  if [ -z "$model_explicit" ]; then
    model="${served[0]}"
  elif [ "$backend" = "mesh" ]; then
    found=0
    for m in "${served[@]}"; do
      [ "$m" = "$model" ] && found=1 && break
    done
    if [ "$found" -eq 0 ]; then
      echo "Warning: model '$model' is not served on http://127.0.0.1:$port/v1; using '${served[0]}' instead." >&2
      model="${served[0]}"
    fi
  fi
fi
model=${model:-$default_model}

session_sys_args=()
if [ -n "$agent_system_prompt" ]; then
  session_sys_args=(--system "$agent_system_prompt")
fi

run_review() {
  if [ "${#extra_args[@]}" -eq 0 ] || [[ "${extra_args[0]}" == -* ]]; then
    run_client review review "${extra_args[@]}"
  else
    run_client review "${extra_args[@]}"
  fi
}

if [ "$backend" = "ollama" ]; then
  if [ "$subcommand" = "gui" ]; then
    write_custom_provider \
      "cadre-ollama.json" \
      "cadre-ollama" \
      "Ollama (cadre)" \
      "Local inference via Ollama" \
      "http://127.0.0.1:$port/v1" \
      "$model"
    echo "Opening Berd on Ollama with $model..."
    export GOOSE_PROVIDER=cadre-ollama
    export GOOSE_MODEL="$model"
    run_client berd "${extra_args[@]}"
    exit $?
  fi

  export OLLAMA_HOST="http://127.0.0.1:$port"
  export GOOSE_PROVIDER=ollama
  export GOOSE_MODEL="$model"
  if [ "$subcommand" = "review" ]; then
    run_review
    exit $?
  fi
  echo "Starting cadre agent on Ollama ($model at http://127.0.0.1:$port)..."
  run_client goose session --provider ollama --model "$model" "${session_sys_args[@]}" "${extra_args[@]}"
else
  write_custom_provider \
    "mesh.json" \
    "mesh" \
    "mesh-llm" \
    "Distributed LLM inference via mesh-llm" \
    "http://127.0.0.1:$port/v1" \
    "$model" \
    "x-capsule-client-nonce"

  export GOOSE_PROVIDER=mesh
  export GOOSE_MODEL="$model"
  if [ "$subcommand" = "gui" ]; then
    echo "Opening Berd on MeshLLM with $model..."
    run_client berd "${extra_args[@]}"
  elif [ "$subcommand" = "review" ]; then
    # block-review gives each pass a fresh GOOSE_PATH_ROOT, so use Goose's built-in openai provider.
    export GOOSE_PROVIDER=openai
    export OPENAI_HOST="http://127.0.0.1:$port"
    export OPENAI_BASE_PATH="v1/chat/completions"
    export OPENAI_API_KEY="${OPENAI_API_KEY:-cadre-local}"
    run_review
  else
    echo "Starting cadre agent on MeshLLM ($model at http://127.0.0.1:$port/v1)..."
    run_client goose session --provider mesh --model "$model" "${session_sys_args[@]}" "${extra_args[@]}"
  fi
fi
