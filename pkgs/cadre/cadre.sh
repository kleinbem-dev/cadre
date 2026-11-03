# shellcheck shell=bash
# cadre: private AI teammates on your own compute (Goose over local inference).
#
# Connects Goose to your local inference backend:
#   - MeshLLM (services.mesh-llm or local ephemeral node)
#   - Ollama (services.ollama or local daemon)

usage() {
  cat <<EOF
cadre ◈ private AI teammates on your own compute

Usage: cadre [OPTIONS]

Options:
  --backend BACKEND  inference engine: auto | mesh | ollama (default: \$CADRE_BACKEND or auto)
  --model MODEL      model to serve/use (default: \$CADRE_MODEL or Qwen3-8B-Q4_K_M for mesh, qwen2.5-coder for ollama)
  --port PORT        API port to connect to (default: 9337 for mesh, 11434 for ollama)
  --join-file PATH   join your private mesh with the invite token in PATH (mesh backend only)
  -h, --help         show this help
EOF
}

backend=${CADRE_BACKEND:-auto}
model=${CADRE_MODEL:-}
join_file=
port=

while [ $# -gt 0 ]; do
  case $1 in
    --backend) backend=$2; shift 2 ;;
    --model) model=$2; shift 2 ;;
    --join-file) join_file=$2; shift 2 ;;
    --port) port=$2; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

# Zero telemetry leaves the machine by default.
export GOOSE_TELEMETRY_OFF=${GOOSE_TELEMETRY_OFF:-1}

# Auto-detect running backend if not explicitly set
if [ "$backend" = "auto" ]; then
  if curl -fsS --max-time 1 "http://127.0.0.1:9337/v1/models" >/dev/null 2>&1; then
    backend="mesh"
  elif curl -fsS --max-time 1 "http://127.0.0.1:11434/api/tags" >/dev/null 2>&1; then
    backend="ollama"
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
      echo "Starting local Ollama daemon on port $port..."
      OLLAMA_HOST="127.0.0.1:$port" ollama serve >/dev/null 2>&1 &
      ollama_pid=$!
      trap 'kill "$ollama_pid" 2>/dev/null; wait "$ollama_pid" 2>/dev/null' EXIT
      sleep 2
    else
      echo "Ollama is not running on $api and 'ollama' binary was not found in PATH." >&2
      echo "Please start Ollama or specify --backend mesh." >&2
      exit 1
    fi
  fi

  echo "Starting cadre agent on Ollama ($model at $api)..."
  export OLLAMA_HOST="$api"
  export GOOSE_PROVIDER=ollama
  export GOOSE_MODEL="$model"
  exec goose session --provider ollama --model "$model"

elif [ "$backend" = "mesh" ]; then
  port=${port:-9337}
  model=${model:-Qwen3-8B-Q4_K_M}
  api="http://127.0.0.1:$port/v1"

  served_models() {
    curl -fsS --max-time 2 "$api/models" 2>/dev/null | jq -r '.data[].id' 2>/dev/null
  }

  if ! curl -fsS --max-time 2 "$api/models" >/dev/null 2>&1; then
    state=${XDG_STATE_HOME:-$HOME/.local/state}/cadre
    mkdir -p "$state"
    args=(serve --model "$model" --port "$port")
    if [ -n "$join_file" ]; then
      args+=(--join-file "$join_file")
    fi
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

  exec mesh-llm goose --port "$port"

else
  echo "Unknown backend: $backend (valid: mesh, ollama, auto)" >&2
  exit 2
fi
