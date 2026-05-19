#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: ./install.sh [options]

Sets up ai-bridge for local use:
  - copies claude-bridge.sh.example -> claude-bridge.sh when missing
  - copies codex-bridge.sh.example  -> codex-bridge.sh when missing
  - chmod +x on runnable scripts
  - adds common AI CLI install paths to your shell profile
  - checks tmux, claude, and codex; optionally installs missing tools

Options:
  -y, --yes       install missing dependencies without prompts
      --no-install
                  never install missing dependencies; still set up wrappers and PATH
      --force     overwrite existing local wrapper copies
      --no-path-edit
                  do not edit shell profile PATH
  -h, --help      show this help

Environment:
  AI_BRIDGE_INSTALL_YES=1       same as --yes
  AI_BRIDGE_INSTALL_NO_DEPS=1   same as --no-install
  AI_BRIDGE_NO_PATH_EDIT=1      same as --no-path-edit
EOF
}

YES="${AI_BRIDGE_INSTALL_YES:-0}"
NO_INSTALL="${AI_BRIDGE_INSTALL_NO_DEPS:-0}"
FORCE=0
NO_PATH_EDIT="${AI_BRIDGE_NO_PATH_EDIT:-0}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes) YES=1 ;;
        --no-install) NO_INSTALL=1 ;;
        --force) FORCE=1 ;;
        --no-path-edit) NO_PATH_EDIT=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
OS="$(uname -s 2>/dev/null || echo unknown)"

# Make freshly installed tools visible in this process too.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

info() { printf '==> %s\n' "$*"; }
ok() { printf 'OK: %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

confirm() {
    local prompt="$1"
    if [[ "$NO_INSTALL" == "1" ]]; then
        return 1
    fi
    if [[ "$YES" == "1" ]]; then
        return 0
    fi
    if [[ ! -t 0 ]]; then
        return 1
    fi
    local reply
    read -r -p "$prompt [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

run_or_warn() {
    local label="$1"; shift
    info "$label"
    if "$@"; then
        ok "$label"
    else
        warn "$label failed"
        return 1
    fi
}

run_shell_or_warn() {
    local label="$1"
    local command="$2"
    info "$label"
    if bash -lc "$command"; then
        ok "$label"
    else
        warn "$label failed"
        return 1
    fi
}

profile_file() {
    if [[ "${SHELL:-}" == *zsh ]]; then
        printf '%s\n' "$HOME/.zshrc"
    elif [[ "${SHELL:-}" == *bash ]]; then
        if [[ "$OS" == "Darwin" ]]; then
            printf '%s\n' "$HOME/.bash_profile"
        else
            printf '%s\n' "$HOME/.bashrc"
        fi
    elif [[ "$OS" == "Darwin" ]]; then
        printf '%s\n' "$HOME/.zshrc"
    else
        printf '%s\n' "$HOME/.profile"
    fi
}

ensure_path_profile() {
    if [[ "$NO_PATH_EDIT" == "1" ]]; then
        warn "Skipping shell profile PATH edit"
        return 0
    fi

    local profile marker
    profile="$(profile_file)"
    marker="# >>> ai-bridge PATH >>>"
    mkdir -p "$(dirname "$profile")"
    touch "$profile"

    if grep -qF "$marker" "$profile"; then
        ok "PATH block already present in $profile"
        return 0
    fi

    cat >>"$profile" <<'EOF'

# >>> ai-bridge PATH >>>
for ai_bridge_path in "/usr/local/bin" "/opt/homebrew/bin" "$HOME/.local/bin"; do
    case ":$PATH:" in
        *":$ai_bridge_path:"*) ;;
        *) export PATH="$ai_bridge_path:$PATH" ;;
    esac
done
unset ai_bridge_path
# <<< ai-bridge PATH <<<
EOF
    ok "Added AI CLI PATH block to $profile"
}

copy_wrapper() {
    local src="$1" dst="$2"
    if [[ -e "$dst" && "$FORCE" != "1" ]]; then
        ok "Preserved existing $(basename "$dst")"
    else
        install -m 0755 "$src" "$dst"
        ok "Installed $(basename "$dst")"
    fi
}

install_tmux() {
    if have tmux; then
        ok "tmux found: $(command -v tmux)"
        return 0
    fi

    warn "tmux not found"
    if [[ "$OS" == "Darwin" ]] && have brew; then
        if confirm "Install tmux with Homebrew?"; then
            run_or_warn "brew install tmux" brew install tmux && return 0
        else
            warn "Skipping tmux install"
        fi
    elif have apt-get; then
        if confirm "Install tmux with apt-get? sudo may ask for your password."; then
            run_shell_or_warn "apt-get install tmux" "sudo apt-get update && sudo apt-get install -y tmux" && return 0
        else
            warn "Skipping tmux install"
        fi
    elif have dnf; then
        if confirm "Install tmux with dnf? sudo may ask for your password."; then
            run_shell_or_warn "dnf install tmux" "sudo dnf install -y tmux" && return 0
        else
            warn "Skipping tmux install"
        fi
    elif have yum; then
        if confirm "Install tmux with yum? sudo may ask for your password."; then
            run_shell_or_warn "yum install tmux" "sudo yum install -y tmux" && return 0
        else
            warn "Skipping tmux install"
        fi
    fi

    warn "Install tmux manually, then rerun ./install.sh"
    warn "  macOS: brew install tmux"
    warn "  Debian/Ubuntu: sudo apt-get install tmux"
}

install_codex() {
    if have codex; then
        ok "codex found: $(command -v codex)"
        return 0
    fi

    warn "codex not found"
    if have npm; then
        if confirm "Install OpenAI Codex CLI with npm?"; then
            run_or_warn "npm install -g @openai/codex" npm install -g @openai/codex || return 0
        else
            warn "Skipping codex install"
        fi
    elif have brew; then
        if confirm "npm is missing. Install Codex CLI with Homebrew instead?"; then
            run_or_warn "brew install codex" brew install codex || return 0
        else
            warn "Skipping codex install"
        fi
    else
        warn "Install Node.js/npm first, then run: npm install -g @openai/codex"
        warn "On macOS with Homebrew: brew install node && npm install -g @openai/codex"
    fi
}

install_claude() {
    if have claude; then
        ok "claude found: $(command -v claude)"
        return 0
    fi

    warn "claude not found"
    if have curl; then
        if confirm "Install Claude Code with Anthropic's native installer?"; then
            run_shell_or_warn "curl -fsSL https://claude.ai/install.sh | bash" "curl -fsSL https://claude.ai/install.sh | bash" || return 0
        else
            warn "Skipping claude install"
        fi
    else
        warn "curl is missing. Install curl, then run: curl -fsSL https://claude.ai/install.sh | bash"
    fi
}

show_version() {
    local tool="$1"
    if have "$tool"; then
        "$tool" --version 2>/dev/null || true
    fi
}

info "Installing ai-bridge from $SCRIPT_DIR"

copy_wrapper "$SCRIPT_DIR/claude-bridge.sh.example" "$SCRIPT_DIR/claude-bridge.sh"
copy_wrapper "$SCRIPT_DIR/codex-bridge.sh.example" "$SCRIPT_DIR/codex-bridge.sh"
chmod +x "$SCRIPT_DIR/ai-bridge.sh" "$SCRIPT_DIR/claude-bridge.sh" "$SCRIPT_DIR/codex-bridge.sh"

ensure_path_profile

install_tmux
install_codex
install_claude

echo
info "Verification"
if have tmux; then ok "tmux: $(command -v tmux)"; else warn "tmux still missing"; fi
if have codex; then ok "codex: $(command -v codex) $(show_version codex | head -1)"; else warn "codex still missing"; fi
if have claude; then ok "claude: $(command -v claude) $(show_version claude | head -1)"; else warn "claude still missing"; fi

echo
info "Next steps"
echo "  1. Restart your terminal or run: source $(profile_file)"
echo "  2. Authenticate the CLIs once:"
echo "       claude"
echo "       codex"
echo "  3. Start either bridge:"
echo "       $SCRIPT_DIR/claude-bridge.sh"
echo "       $SCRIPT_DIR/codex-bridge.sh"
echo
echo "Tip: pass --force to refresh local wrappers from the templates."
