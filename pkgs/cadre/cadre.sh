# shellcheck shell=bash
# cadre: private AI teammates on your own compute (Goose over local inference).
#
# Connects Goose, Berd (desktop GUI), or Buzz (team chat) to your local inference backend:
#   - MeshLLM (services.mesh-llm or local ephemeral node)
#   - Ollama (services.ollama or local daemon)

usage() {
  cat <<EOF
cadre ◈ private AI teammates on your own compute

Usage: cadre [COMMAND] [OPTIONS]

Commands:
  session            interactive pairing assistant in terminal (default)
  gui, desktop, berd start Berd desktop app on the local backend
  chat, buzz         open Buzz team chat application
  serve              run the local inference node without opening a client

Options:
  --backend BACKEND  inference engine: auto | mesh | ollama (default: \$CADRE_BACKEND or auto)
  --model MODEL      model to serve/use (default: \$CADRE_MODEL or \$MESH_AGENTS_MODEL or Qwen3-8B-Q4_K_M for mesh, qwen2.5-coder for ollama)
  --port PORT        API port to connect to (default: 9337 for mesh, 11434 for ollama)
  --join-file PATH   join your private mesh with the invite token in PATH (mesh backend only)
  --app APP          alternate command selector: session | gui | chat | serve
  -h, --help         show this help
EOF
}

subcommand="session"
case "${1:-}" in
  session)
    subcommand="session"
    shift
    ;;
  gui | desktop | berd)
    subcommand="gui"
    shift
    ;;
  chat | buzz)
    subcommand="chat"
    shift
    ;;
  serve)
    subcommand="serve"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
esac

backend=${CADRE_BACKEND:-auto}
model=${CADRE_MODEL:-${MESH_AGENTS_MODEL:-}}
join_file=
port=

while [ $# -gt 0 ]; do
  case $1 in
    --app)
      [ $# -ge 2 ] || {
        usage >&2
        exit 2
      }
      case "$2" in
        session | goose) subcommand="session" ;;
        gui | desktop | berd) subcommand="gui" ;;
        chat | buzz) subcommand="chat" ;;
        serve) subcommand="serve" ;;
        *)
          usage >&2
          exit 2
          ;;
      esac
      shift 2
      ;;
    --backend)
      [ $# -ge 2 ] || {
        usage >&2
        exit 2
      }
      backend=$2
      shift 2
      ;;
    --model)
      [ $# -ge 2 ] || {
        usage >&2
        exit 2
      }
      model=$2
      shift 2
      ;;
    --join-file)
      [ $# -ge 2 ] || {
        usage >&2
        exit 2
      }
      join_file=$2
      shift 2
      ;;
    --port)
      [ $# -ge 2 ] || {
        usage >&2
        exit 2
      }
      port=$2
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

# Zero telemetry leaves the machine by default.
export GOOSE_TELEMETRY_OFF=${GOOSE_TELEMETRY_OFF:-1}

# Chat subcommand launches Buzz client directly
if [ "$subcommand" = "chat" ]; then
  if command -v buzz-app >/dev/null 2>&1; then
    exec buzz-app "$@"
  elif command -v buzz >/dev/null 2>&1; then
    exec buzz "$@"
  elif command -v buzz-cli >/dev/null 2>&1; then
    exec buzz-cli "$@"
  else
    echo "Buzz is not installed; install 'buzz-app' or enable 'services.cadre.desktop.enable'." >&2
    exit 1
  fi
fi

# GUI subcommand requires Berd
if [ "$subcommand" = "gui" ]; then
  if ! command -v berd >/dev/null 2>&1; then
    echo "Berd is not installed; install 'berd' or enable 'services.cadre.desktop.enable'." >&2
    exit 1
  fi
fi

# Auto-detect running backend if not explicitly set
if [ "$backend" = "auto" ]; then
  mesh_probe_port=${port:-9337}
  ollama_probe_port=${port:-11434}
  if curl -fsS --max-time 1 "http://127.0.0.1:$mesh_probe_port/v1/models" >/dev/null 2>&1; then
    backend="mesh"
    port=$mesh_probe_port
  elif curl -fsS --max-time 1 "http://127.0.0.1:$ollama_probe_port/api/tags" >/dev/null 2>&1; then
    backend="ollama"
    port=$ollama_probe_port
  else
    backend="mesh"
  fi
fi

if [ "$backend" = "ollama" ]; then
  port=${port:-11434}
  model=${model:-qwen2.5-coder}
  api="http://127.0.0.1:$port"

  if ! curl -fsS --max-time 2 "$api/api/tags" >/dev/null 2>&1; then
    if command -v ollama >/dev/null 2>&1; then
      if [ "$subcommand" = "serve" ]; then
        echo "Starting Ollama daemon on port $port..."
        exec env OLLAMA_HOST="127.0.0.1:$port" ollama serve
      fi

      echo "Starting local Ollama daemon on port $port..."
      OLLAMA_HOST="127.0.0.1:$port" ollama serve >/dev/null 2>&1 &
      ollama_pid=$!
      trap 'kill "$ollama_pid" 2>/dev/null; wait "$ollama_pid" 2>/dev/null' EXIT

      echo "Waiting for Ollama to become ready..."
      until curl -fsS --max-time 1 "$api/api/tags" >/dev/null 2>&1; do
        if ! kill -0 "$ollama_pid" 2>/dev/null; then
          echo "Ollama stopped unexpectedly" >&2
          exit 1
        fi
        sleep 1
      done
    else
      echo "Ollama is not running on $api and 'ollama' binary was not found in PATH." >&2
      echo "Please start Ollama or specify --backend mesh." >&2
      exit 1
    fi
  fi

  if [ "$subcommand" = "serve" ]; then
    echo "Ollama is already running on $api."
    exit 0
  fi

  if [ "$subcommand" = "gui" ]; then
    providers=${XDG_CONFIG_HOME:-$HOME/.config}/goose/custom_providers
    mkdir -p "$providers"
    jq -n --arg base "http://127.0.0.1:$port/v1" --arg model "$model" '{
      name: "cadre-ollama",
      engine: "openai",
      display_name: "Ollama (cadre)",
      description: "Local inference via Ollama",
      api_key_env: "",
      base_url: $base,
      models: [{name: $model, context_limit: 4096}],
      timeout_seconds: 600,
      supports_streaming: true,
      requires_auth: false
    }' >"$providers/cadre-ollama.json"
    echo "Opening Berd on Ollama with $model..."
    export GOOSE_PROVIDER=cadre-ollama
    export GOOSE_MODEL="$model"
    berd "$@"
    exit $?
  fi

  echo "Starting cadre agent on Ollama ($model at $api)..."
  export OLLAMA_HOST="$api"
  export GOOSE_PROVIDER=ollama
  export GOOSE_MODEL="$model"
  goose session --provider ollama --model "$model"

elif [ "$backend" = "mesh" ]; then
  port=${port:-9337}
  model=${model:-Qwen3-8B-Q4_K_M}
  api="http://127.0.0.1:$port/v1"

  served_models() {
    curl -fsS --max-time 2 "$api/models" 2>/dev/null | jq -r '.data[].id' 2>/dev/null
  }

  if ! curl -fsS --max-time 2 "$api/models" >/dev/null 2>&1; then
    args=(serve --model "$model" --port "$port")
    if [ -n "$join_file" ]; then
      args+=(--join-file "$join_file")
    fi
    if [ "$subcommand" = "serve" ]; then
      echo "Starting MeshLLM node with $model on port $port..."
      exec mesh-llm "${args[@]}"
    fi

    state=${XDG_STATE_HOME:-$HOME/.local/state}/cadre
    mkdir -p "$state"
    echo "Starting a private MeshLLM node with $model (log: $state/mesh-llm.log)"
    mesh-llm "${args[@]}" >"$state/mesh-llm.log" 2>&1 &
    node=$!
    trap 'kill "$node" 2>/dev/null; wait "$node" 2>/dev/null' EXIT

    echo "Waiting for the model; the first start downloads it."
    until [ -n "$(served_models)" ]; do
      if ! kill -0 "$node" 2>/dev/null; then
        echo "MeshLLM stopped, see $state/mesh-llm.log" >&2
        exit 1
      fi
      sleep 2
    done
  fi

  if [ "$subcommand" = "serve" ]; then
    echo "MeshLLM node is already running on $api."
    exit 0
  fi

  if [ "$subcommand" = "gui" ]; then
    inventory=$(curl -fsS --max-time 5 "$api/models" 2>/dev/null || true)
    if [ -n "$inventory" ] && ! jq -e --arg m "$model" '.data[] | select(.id == $m)' <<<"$inventory" >/dev/null 2>&1; then
      first_model=$(jq -r '.data[0].id // empty' <<<"$inventory" 2>/dev/null || true)
      [ -n "$first_model" ] && model="$first_model"
    fi
    providers=${XDG_CONFIG_HOME:-$HOME/.config}/goose/custom_providers
    mkdir -p "$providers"
    jq -n --arg base "http://localhost:$port/v1" --arg model "$model" '{
      name: "mesh",
      engine: "openai",
      display_name: "mesh-llm",
      description: "Distributed LLM inference via mesh-llm",
      api_key_env: "",
      base_url: $base,
      models: [{name: $model, context_limit: 32768}],
      timeout_seconds: 600,
      supports_streaming: true,
      requires_auth: false,
      nonce_header: "x-capsule-client-nonce"
    }' >"$providers/mesh.json"
    echo "Opening Berd on MeshLLM with $model..."
    export GOOSE_PROVIDER=mesh
    export GOOSE_MODEL="$model"
    berd "$@"
    exit $?
  fi

  mesh_args=(--port "$port")
  if [ -n "$model" ]; then
    mesh_args+=(--model "$model")
  fi
  mesh-llm goose "${mesh_args[@]}"

else
  echo "Unknown backend: $backend (valid: mesh, ollama, auto)" >&2
  exit 2
fi
