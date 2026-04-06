#!/usr/bin/env bash
set -euo pipefail

TTYD_PORT="${TTYD_PORT:-7681}"
TTYD_USERNAME="${TTYD_USERNAME:-codex}"
TTYD_PASSWORD="${TTYD_PASSWORD:-change-this-password}"
CODEX_SESSION_NAME="${CODEX_SESSION_NAME:-codex}"
CODEX_WORKDIR="${CODEX_WORKDIR:-/root/codex-workspace}"
CODEX_BIN="${CODEX_BIN:-}"
INSTALL_DIR="${INSTALL_DIR:-/root/codex-workspace/scripts}"
ENV_FILE="${ENV_FILE:-/etc/codex-web.env}"
SERVICE_FILE="${SERVICE_FILE:-/etc/systemd/system/codex-web.service}"
TMUX_SCRIPT_PATH="${TMUX_SCRIPT_PATH:-$INSTALL_DIR/start-codex-tmux.sh}"

usage() {
  cat <<'EOF'
Usage:
  bash install-codex-web.sh [options]

Options:
  --username <name>         Web login username, default: codex
  --password <password>     Web login password
  --port <port>             ttyd listening port, default: 7681
  --workdir <path>          Codex working directory, default: /root/codex-workspace
  --codex-bin <path>        Codex binary path, default: auto-detect from PATH
  --session-name <name>     tmux session name, default: codex
  --install-dir <path>      Script install directory, default: /root/codex-workspace/scripts
  --help                    Show this help

Examples:
  bash install-codex-web.sh --password 'StrongPassword'
  bash install-codex-web.sh --username codex --password 'StrongPassword' --port 7681
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --username)
      TTYD_USERNAME="$2"
      shift 2
      ;;
    --password)
      TTYD_PASSWORD="$2"
      shift 2
      ;;
    --port)
      TTYD_PORT="$2"
      shift 2
      ;;
    --workdir)
      CODEX_WORKDIR="$2"
      shift 2
      ;;
    --codex-bin)
      CODEX_BIN="$2"
      shift 2
      ;;
    --session-name)
      CODEX_SESSION_NAME="$2"
      shift 2
      ;;
    --install-dir)
      INSTALL_DIR="$2"
      TMUX_SCRIPT_PATH="$INSTALL_DIR/start-codex-tmux.sh"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$TTYD_PASSWORD" || "$TTYD_PASSWORD" == "change-this-password" ]]; then
  echo "Please provide a strong password via --password" >&2
  exit 1
fi

if [[ -z "$CODEX_BIN" ]]; then
  if command -v codex >/dev/null 2>&1; then
    CODEX_BIN="$(command -v codex)"
  elif [[ -x "/root/.nvm/versions/node/v25.8.1/bin/codex" ]]; then
    CODEX_BIN="/root/.nvm/versions/node/v25.8.1/bin/codex"
  else
    echo "codex binary not found. Install Codex first or pass --codex-bin." >&2
    exit 1
  fi
fi

install_packages() {
  if command -v dnf >/dev/null 2>&1; then
    dnf -y install tmux ttyd
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y tmux ttyd
  elif command -v yum >/dev/null 2>&1; then
    yum install -y epel-release || true
    yum install -y tmux ttyd
  else
    echo "Unsupported package manager. Install tmux and ttyd manually." >&2
    exit 1
  fi
}

echo "[1/6] Installing tmux and ttyd..."
install_packages

echo "[2/6] Preparing directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$CODEX_WORKDIR"

echo "[3/6] Writing tmux launcher..."
cat > "$TMUX_SCRIPT_PATH" <<EOF
#!/usr/bin/env bash
set -euo pipefail

SESSION_NAME="\${CODEX_SESSION_NAME:-$CODEX_SESSION_NAME}"
WORKDIR="\${CODEX_WORKDIR:-$CODEX_WORKDIR}"
CODEX_BIN="\${CODEX_BIN:-$CODEX_BIN}"

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux not found" >&2
  exit 1
fi

if [ -z "\${TERM:-}" ] || [ "\${TERM}" = "dumb" ]; then
  export TERM=xterm-256color
fi

if [ ! -x "\$CODEX_BIN" ]; then
  CODEX_BIN="\$(command -v codex)"
fi

if ! tmux has-session -t "\$SESSION_NAME" 2>/dev/null; then
  tmux new-session -d -s "\$SESSION_NAME" -c "\$WORKDIR" "exec \"\$CODEX_BIN\" --no-alt-screen"
fi

tmux set-option -g mouse on >/dev/null 2>&1 || true
tmux set-option -g history-limit 200000 >/dev/null 2>&1 || true
tmux set-option -g mode-keys vi >/dev/null 2>&1 || true

exec tmux attach-session -t "\$SESSION_NAME"
EOF
chmod +x "$TMUX_SCRIPT_PATH"

echo "[4/6] Writing environment file..."
cat > "$ENV_FILE" <<EOF
TTYD_PORT=$TTYD_PORT
TTYD_CREDENTIAL=$TTYD_USERNAME:$TTYD_PASSWORD
EOF
chmod 600 "$ENV_FILE"

echo "[5/6] Writing systemd service..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Codex Web Terminal via ttyd
After=network.target

[Service]
Type=simple
WorkingDirectory=$CODEX_WORKDIR
Environment=CODEX_WORKDIR=$CODEX_WORKDIR
Environment=CODEX_SESSION_NAME=$CODEX_SESSION_NAME
Environment=CODEX_BIN=$CODEX_BIN
EnvironmentFile=-$ENV_FILE
ExecStart=/usr/bin/ttyd -i 0.0.0.0 -p \${TTYD_PORT} -c \${TTYD_CREDENTIAL} -W $TMUX_SCRIPT_PATH
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

echo "[6/6] Enabling service..."
systemctl daemon-reload
systemctl enable --now codex-web.service

if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port="${TTYD_PORT}/tcp" >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
fi

echo
echo "Codex Web Terminal is ready."
echo "Service: codex-web.service"
echo "Port: $TTYD_PORT"
echo "Username: $TTYD_USERNAME"
echo "Password: $TTYD_PASSWORD"
echo "Workdir: $CODEX_WORKDIR"
echo "Codex binary: $CODEX_BIN"
echo
echo "Check status:"
echo "  systemctl status codex-web.service"
echo "  curl -I http://127.0.0.1:$TTYD_PORT"
