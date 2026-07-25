#!/usr/bin/env bash
#
# hostinger-ssh.sh — connect to a Hostinger server over SSH, or run a
# remote command, without having to remember the port/user every time.
#
# Configuration is read (in order of precedence) from:
#   1. command-line flags
#   2. environment variables
#   3. a config file: ./.hostinger.env, ~/.hostinger.env
#
# Recognised settings (env var / config key):
#   HOSTINGER_HOST      SSH IP or hostname            (required)
#   HOSTINGER_USER      SSH username (e.g. uXXXXXXXXX or root)   (required)
#   HOSTINGER_PORT      SSH port (default: 65002 for shared, 22 for vps)
#   HOSTINGER_KEY       path to private key (default: ~/.ssh/hostinger)
#
# Examples:
#   ./scripts/hostinger-ssh.sh                       # interactive shell
#   ./scripts/hostinger-ssh.sh -- uptime             # run a remote command
#   ./scripts/hostinger-ssh.sh --vps                 # use root@host:22 defaults
#   ./scripts/hostinger-ssh.sh --host 1.2.3.4 --user u123456789
#   ./scripts/hostinger-ssh.sh --print               # show the ssh command only
#
set -euo pipefail

PROG=$(basename "$0")

# ---- defaults ---------------------------------------------------------------
HOST="${HOSTINGER_HOST:-}"
USER_NAME="${HOSTINGER_USER:-}"
PORT="${HOSTINGER_PORT:-}"
KEY="${HOSTINGER_KEY:-$HOME/.ssh/hostinger}"
MODE="shared"        # shared -> default port 65002, vps -> default port 22
PRINT_ONLY=0
REMOTE_ARGS=()

# ---- load config file -------------------------------------------------------
load_config() {
    local f
    for f in "./.hostinger.env" "$HOME/.hostinger.env"; do
        if [[ -f "$f" ]]; then
            # shellcheck disable=SC1090
            set -a; source "$f"; set +a
            HOST="${HOST:-${HOSTINGER_HOST:-}}"
            USER_NAME="${USER_NAME:-${HOSTINGER_USER:-}}"
            PORT="${PORT:-${HOSTINGER_PORT:-}}"
            KEY="${KEY:-${HOSTINGER_KEY:-$HOME/.ssh/hostinger}}"
            break
        fi
    done
}

usage() {
    sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

# ---- parse args -------------------------------------------------------------
load_config
while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)  HOST="$2"; shift 2 ;;
        --user)  USER_NAME="$2"; shift 2 ;;
        --port)  PORT="$2"; shift 2 ;;
        --key)   KEY="$2"; shift 2 ;;
        --vps)   MODE="vps"; shift ;;
        --print) PRINT_ONLY=1; shift ;;
        -h|--help) usage 0 ;;
        --)      shift; REMOTE_ARGS=("$@"); break ;;
        *)       echo "$PROG: unknown option: $1" >&2; usage 1 ;;
    esac
done

# ---- fill in mode-dependent defaults ---------------------------------------
if [[ -z "$PORT" ]]; then
    if [[ "$MODE" == "vps" ]]; then PORT=22; else PORT=65002; fi
fi
if [[ -z "$USER_NAME" && "$MODE" == "vps" ]]; then
    USER_NAME="root"
fi

# ---- validate ---------------------------------------------------------------
missing=()
[[ -z "$HOST" ]]      && missing+=("host (--host or HOSTINGER_HOST)")
[[ -z "$USER_NAME" ]] && missing+=("user (--user or HOSTINGER_USER)")
if [[ ${#missing[@]} -gt 0 ]]; then
    echo "$PROG: missing required setting(s):" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    echo "" >&2
    echo "Set them via flags, env vars, or a .hostinger.env file. See --help." >&2
    exit 2
fi

# ---- build the ssh command --------------------------------------------------
SSH_CMD=(ssh -p "$PORT" -o ServerAliveInterval=60)
if [[ -n "$KEY" && -f "$KEY" ]]; then
    SSH_CMD+=(-i "$KEY" -o IdentitiesOnly=yes)
elif [[ -n "$KEY" && ! -f "$KEY" ]]; then
    echo "$PROG: note: key '$KEY' not found; falling back to agent/password auth." >&2
fi
SSH_CMD+=("${USER_NAME}@${HOST}")
[[ ${#REMOTE_ARGS[@]} -gt 0 ]] && SSH_CMD+=("${REMOTE_ARGS[@]}")

# ---- run or print -----------------------------------------------------------
if [[ "$PRINT_ONLY" -eq 1 ]]; then
    printf '%q ' "${SSH_CMD[@]}"; echo
    exit 0
fi

echo "→ Connecting to ${USER_NAME}@${HOST}:${PORT} ..." >&2
exec "${SSH_CMD[@]}"
