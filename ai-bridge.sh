#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# ai-bridge core script — see README.md for the full operational protocol.
# AI 교차 검증 환경 원터치 셋업
#
# 사용:
#   bash ai-bridge.sh
#   또는: chmod +x ai-bridge.sh && ./ai-bridge.sh
#
# 환경변수 (선택):
#   AI_BRIDGE_FILE       bridge 메시지박스 파일 경로 (기본: ~/ai-bridge.md)
#   AI_SECONDARY_CMD     tmux 안에서 실행할 보조 AI CLI 명령. *Trusted local config only.*
#                        AI 출력 / bridge 내용 / tmux capture 결과를 절대 이 값으로 만들지 말 것.
#   AI_TMUX_SESSION      tmux 세션 이름 (기본: ai-secondary). 정규식 ^[A-Za-z0-9_.-]+$ 통과 필수 (콜론 제외 — tmux target 오해석 차단).
#   AI_OPEN_TERMINAL     1 = macOS Terminal.app 새 창 자동 열어 tmux attach (OPT-IN, default OFF).
#                        Non-macOS에서는 warn + manual attach 안내.
#   AI_PRIMARY_CMD       현재 터미널에서 마지막에 exec할 주 AI 명령. *Trusted local config only.*
#                        bash -lc로 실행. 미설정 시 attach prompt로 fallback.
#   AI_PRIMARY_MEMORY    주 AI 글로벌 지침 파일 (옵션, 정보 표시용)
#   AI_SECONDARY_MEMORY  보조 AI 글로벌 지침 파일 (옵션)
#   AI_TMUX_HISTORY_LIMIT  scrollback 한도 (기본: 10000)
#   AI_BRIDGE_WORKDIR    tmux 새 세션 default-path 및 primary AI 실행 cwd (기본: $HOME).
#                        호출 위치(PWD)에 관계없이 일정한 작업 디렉토리 보장.
#                        기존 세션 재사용 시에는 pane_current_path와 비교해 warn만.
#
# 안전:
#   AI_PRIMARY_CMD / AI_SECONDARY_CMD는 trusted local config로만 다룬다.
#   AI 출력, bridge 내용, tmux capture-pane 결과를 이 값으로 만들지 말 것 — shell injection 위험.

# VERSION 단일 source: 같은 디렉토리의 VERSION 파일이 진실. 없으면 unknown.
_AI_BRIDGE_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ -f "$_AI_BRIDGE_SELF_DIR/VERSION" ]]; then
    AI_BRIDGE_VERSION="$(head -1 "$_AI_BRIDGE_SELF_DIR/VERSION" | tr -d '[:space:]')"
else
    AI_BRIDGE_VERSION="unknown"
fi
readonly AI_BRIDGE_VERSION
unset _AI_BRIDGE_SELF_DIR

# ── --version / -V 분기 (env 검증 전에 처리) ──────────────
if [[ "${1:-}" == "--version" || "${1:-}" == "-V" ]]; then
    echo "ai-bridge $AI_BRIDGE_VERSION"
    exit 0
fi

set -euo pipefail

# ── 환경변수 + 기본값 ────────────────────────────────────
BRIDGE_FILE="${AI_BRIDGE_FILE:-$HOME/ai-bridge.md}"
SECONDARY_CMD="${AI_SECONDARY_CMD:-}"
TMUX_SESSION="${AI_TMUX_SESSION:-ai-secondary}"
OPEN_TERMINAL="${AI_OPEN_TERMINAL:-0}"
PRIMARY_CMD="${AI_PRIMARY_CMD:-}"
PRIMARY_MEMORY="${AI_PRIMARY_MEMORY:-}"
SECONDARY_MEMORY="${AI_SECONDARY_MEMORY:-}"
TMUX_HISTORY_LIMIT="${AI_TMUX_HISTORY_LIMIT:-10000}"
BRIDGE_WORKDIR="${AI_BRIDGE_WORKDIR:-$HOME}"
# AI_BRIDGE_DRY_RUN=1 → bridge 파일 검증/생성까지만 하고 tmux 세션 생성 직전에 exit.
# smoke test / CI 용도. 운영에서는 사용 금지.
DRY_RUN="${AI_BRIDGE_DRY_RUN:-0}"

# ── 세션명 injection 방지 (regex 화이트리스트) ──────────
# 콜론(`:`) 제외 — tmux는 `session:window` 형식이라 허용 시 target 오해석 위험.
if ! [[ "$TMUX_SESSION" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "ERROR: AI_TMUX_SESSION must match ^[A-Za-z0-9_.-]+$ (got: '$TMUX_SESSION')" >&2
    exit 1
fi

# ── workdir 검증 (tmux new-session -c / primary cd 대상) ──
if [[ ! -d "$BRIDGE_WORKDIR" ]]; then
    echo "ERROR: AI_BRIDGE_WORKDIR is not a directory: $BRIDGE_WORKDIR" >&2
    exit 1
fi

# ── AI_OPEN_TERMINAL 0|1 검증 ──────────────────────────
if [[ "$OPEN_TERMINAL" != "0" && "$OPEN_TERMINAL" != "1" ]]; then
    echo "ERROR: AI_OPEN_TERMINAL must be 0 or 1 (got: '$OPEN_TERMINAL')" >&2
    exit 1
fi

# ── AI_TMUX_HISTORY_LIMIT 정수 검증 ─────────────────────
if ! [[ "$TMUX_HISTORY_LIMIT" =~ ^[0-9]+$ ]] || [[ "$TMUX_HISTORY_LIMIT" -lt 100 ]]; then
    echo "ERROR: AI_TMUX_HISTORY_LIMIT must be a positive integer >= 100 (got: '$TMUX_HISTORY_LIMIT')" >&2
    exit 1
fi

# ── AI_PRIMARY_CMD / AI_SECONDARY_CMD newline/control char 거부 ──
# trusted local config 전제 위에서도 multi-line 주입을 한 번 더 차단.
# grep은 newline을 line separator로 봐서 못 잡으므로 bash regex 사용.
for var_name in PRIMARY_CMD SECONDARY_CMD; do
    var_value="${!var_name}"
    if [[ -n "$var_value" && "$var_value" =~ [[:cntrl:]] ]]; then
        echo "ERROR: AI_${var_name} contains control/newline characters — reject for safety" >&2
        exit 1
    fi
done
unset var_name var_value

# ── 컬러 (옵션) ──────────────────────────────────────────
if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; CYAN=$'\033[36m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
    BOLD=""; CYAN=""; GREEN=""; YELLOW=""; RED=""; DIM=""; RESET=""
fi

header() { echo ""; echo "${BOLD}${CYAN}═══ $1 ═══${RESET}"; }
ok()     { echo "  ${GREEN}✓${RESET} $1"; }
warn()   { echo "  ${YELLOW}⚠${RESET}  $1"; }
fail()   { echo "  ${RED}✗${RESET} $1"; }
info()   { echo "    ${DIM}$1${RESET}"; }

# ── 1. 정책 파일 위치 (tmux 의존 없음 — DRY_RUN/CI에서도 작동) ──
header "1. 정책 파일"

# Mode 조회 — GNU stat(`stat -c %a`) 우선, BSD/macOS(`stat -f %Lp`) fallback.
# 양쪽 모두 mode 숫자 형식(`^[0-7]+$`)인지 검증. 다른 platform의 stat이 다른 옵션으로
# silent하게 다른 출력(예: Linux GNU stat의 -f는 filesystem 정보)을 내는 회귀 차단.
get_file_mode() {
    local f="$1" m
    m=$(stat -c "%a" "$f" 2>/dev/null) || true
    if [[ "$m" =~ ^[0-7]+$ ]]; then echo "$m"; return 0; fi
    m=$(stat -f "%Lp" "$f" 2>/dev/null) || true
    if [[ "$m" =~ ^[0-7]+$ ]]; then echo "$m"; return 0; fi
    echo "?"
}

if [[ -f "$BRIDGE_FILE" ]]; then
    lines=$(awk 'END{print NR}' "$BRIDGE_FILE")
    ok "bridge: $BRIDGE_FILE (${lines}줄)"
    perm=$(get_file_mode "$BRIDGE_FILE")
    if [[ "$perm" == "600" ]]; then
        info "권한 chmod 0600 ✓"
    else
        warn "권한 $perm — chmod 0600으로 강제 (다른 프로세스 평문 읽기 방지)"
        if ! chmod 0600 "$BRIDGE_FILE" 2>/dev/null; then
            fail "chmod 0600 실패 — 파일 소유자/권한 확인 필요. bridge 보안 보장 불가능 → 중단"
            exit 1
        fi
        info "권한 0600으로 변경 완료"
    fi
else
    # umask 의존 없이 0600으로 먼저 생성. AI가 첫 append 전에 권한 보장.
    info "bridge 파일 신규 생성: $BRIDGE_FILE (mode 0600)"
    if ! mkdir -p "$(dirname "$BRIDGE_FILE")"; then
        fail "bridge 디렉토리 생성 실패: $(dirname "$BRIDGE_FILE")"
        exit 1
    fi
    if ! (umask 0177 && : > "$BRIDGE_FILE") || ! chmod 0600 "$BRIDGE_FILE"; then
        fail "bridge 파일 생성 또는 chmod 0600 실패 — 이후 로직 중단"
        exit 1
    fi
    ok "bridge 파일 생성 + chmod 0600 완료"
fi

if [[ -n "$PRIMARY_MEMORY" ]]; then
    if [[ -s "$PRIMARY_MEMORY" ]]; then
        ok "주 AI 메모리: $PRIMARY_MEMORY"
    else
        warn "주 AI 메모리 파일 비어있거나 없음: $PRIMARY_MEMORY"
    fi
fi

if [[ -n "$SECONDARY_MEMORY" ]]; then
    if [[ -s "$SECONDARY_MEMORY" ]]; then
        ok "보조 AI 메모리: $SECONDARY_MEMORY"
    else
        warn "보조 AI 메모리 파일 비어있거나 없음: $SECONDARY_MEMORY"
    fi
fi

# ── DRY_RUN 종료 지점 (bridge 파일 검증/생성까지 완료) ──
# DRY_RUN은 tmux 의존성 회피가 명시 목적 — tmux check도 이 뒤로 둠.
if [[ "$DRY_RUN" == "1" ]]; then
    info "AI_BRIDGE_DRY_RUN=1 — tmux 세션 생성 직전 종료"
    exit 0
fi

# ── 2. tmux 필수 도구 검증 (DRY_RUN 이후에만) ────────────
header "2. 필수 도구 검증"

if command -v tmux >/dev/null 2>&1; then
    ok "tmux: $(tmux -V)"
else
    fail "tmux 없음. 설치 필요 (macOS: brew install tmux, Linux: apt/yum install tmux)"
    exit 1
fi

# ── 3. tmux 세션 셋업 (신규 세션에만 send-keys — race 방지) ──
header "3. tmux 세션 '$TMUX_SESSION'"

# 경로 정규화 — readlink 미지원 환경 fallback. `~/x` vs `/Users/y/x` equivalence 검출.
norm_path() {
    local p="${1:-}"
    [[ -z "$p" ]] && { echo ""; return; }
    if [[ -d "$p" ]]; then
        (cd "$p" 2>/dev/null && pwd -P) || echo "$p"
    else
        echo "$p"
    fi
}

NEW_SESSION=0
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    pane_cmd=$(tmux list-panes -t "$TMUX_SESSION" -F "#{pane_current_command}" 2>/dev/null | head -1)
    pane_cwd=$(tmux list-panes -t "$TMUX_SESSION" -F "#{pane_current_path}" 2>/dev/null | head -1)
    ok "세션 이미 존재 (pane current command: $pane_cmd)"
    pane_cwd_norm="$(norm_path "$pane_cwd")"
    bridge_workdir_norm="$(norm_path "$BRIDGE_WORKDIR")"
    if [[ -n "$pane_cwd_norm" && "$pane_cwd_norm" != "$bridge_workdir_norm" ]]; then
        warn "기존 세션 cwd '$pane_cwd' ≠ 기대 workdir '$BRIDGE_WORKDIR' — tmux는 기존 pane cwd를 변경하지 않음"
        info "원하면 세션을 죽이고 다시 띄우거나, attach 후 'cd $BRIDGE_WORKDIR' 수동 실행"
    fi
    if [[ -n "$SECONDARY_CMD" ]] && [[ "$pane_cmd" == "zsh" || "$pane_cmd" == "bash" ]]; then
        warn "보조 AI CLI 실행 안 됨. attach 후 직접 실행: $SECONDARY_CMD"
        info "기존 세션엔 자동 재발송하지 않음 (사용자 의도 침범 방지)"
    fi
else
    info "세션 생성 중... (cwd=$BRIDGE_WORKDIR)"
    tmux new-session -d -s "$TMUX_SESSION" -c "$BRIDGE_WORKDIR"
    tmux set-option -t "$TMUX_SESSION" history-limit "$TMUX_HISTORY_LIMIT" 2>/dev/null || true
    NEW_SESSION=1
    if [[ -n "$SECONDARY_CMD" ]]; then
        tmux send-keys -t "$TMUX_SESSION" "$SECONDARY_CMD" Enter
        ok "tmux 세션 생성 + '$SECONDARY_CMD' 시작 명령 전송"
        info "attach가 live state catch-up (sleep 불필요)"
    else
        ok "tmux 세션 생성 (AI_SECONDARY_CMD 미설정 — attach 후 직접 실행)"
    fi
fi

# ── 4. 트리거 워딩 cheatsheet ────────────────────────────
header "4. 트리거 워딩 (Cheatsheet)"

echo ""
echo "  ${BOLD}주 AI 창에서:${RESET}"
echo "    \"[보조 AI]한테 리뷰 요청\"             → bridge에 작성 + 클립보드 복사 + 안내"
echo "    \"[보조 AI] 응답 확인\" / \"bridge 확인\"  → capture-pane으로 응답 읽기"
echo "    \"[X] 후 [외부 시스템] 업데이트해줘\"     → Review-first/Batch 모드 진입"
echo "    \"백그라운드 모니터링 켜줘\"              → bounded read-only observer subagent"
echo "    \"핑퐁 회의 시작: <안건>\"               → 회의 모드 (round 1 자동, 이후 paste)"
echo ""
echo "  ${BOLD}보조 AI 창에서:${RESET}"
echo "    \"[주 AI]한테 리뷰 요청\"                → bridge에 작성 + 안내"
echo "    \"bridge 확인\" / \"[주 AI] 답변 확인\"     → 최신 항목 읽기"
echo "    \"APPROVE WRITE target=... scope=...\"  → batch 승인"
echo ""
echo "  ${BOLD}외부 시스템 변경 흐름:${RESET}"
echo "    ${GREEN}✓${RESET} 사용자 직접 요청 (사용자 → 한 AI 단일 turn) — 가능"
echo "    ${RED}✗${RESET} AI 사이 자동 위임 — 분류기에 차단됨"
echo ""
echo "  ${BOLD}금지:${RESET}"
echo "    - bridge에 실제 토큰/비밀번호 적기"
echo "    - 자동 승인 / YOLO 모드 (--yes, auto-approve, Ctrl+Y)"
echo "    - observer subagent에 send-keys/write 권한"
echo "    - 한 subagent에 observer + executor 합치기"
echo "    - AI 출력/bridge 내용을 AI_PRIMARY_CMD/AI_SECONDARY_CMD에 끼우기"
echo ""
echo "  ${DIM}자세한 정책: README.md 참조${RESET}"

# ── 5. macOS Terminal auto-open (OPT-IN) ────────────────
if [[ "$OPEN_TERMINAL" == "1" ]]; then
    header "5. macOS Terminal auto-open"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        ok "macOS 감지 — 새 Terminal 창 열어 'tmux attach -t $TMUX_SESSION' 실행"
        # osascript safe pattern: 명령을 argv로 전달, AppleScript에서 'item of argv'로 받음
        # (string interpolation 사용 금지 — injection 차단)
        /usr/bin/osascript - "tmux attach -t $TMUX_SESSION" <<'APPLESCRIPT'
on run argv
    set theCommand to item 1 of argv
    tell application "Terminal"
        activate
        do script theCommand
    end tell
end run
APPLESCRIPT
        ok "새 Terminal 창 열림"
    else
        warn "AI_OPEN_TERMINAL=1이지만 macOS 아님 ($OSTYPE) — auto open skip"
        echo "    수동 attach: ${BOLD}tmux attach -t $TMUX_SESSION${RESET}"
        info "Linux/WSL에서는 별도 터미널 창에서 위 명령 수동 실행"
    fi
fi

# ── 6. 다음 액션 / Primary exec ──────────────────────────
header "6. 다음 액션"

echo ""
echo "  보조 AI 창 attach:  ${BOLD}tmux attach -t $TMUX_SESSION${RESET}"
echo "  bridge 보기:        ${BOLD}tail -50 $BRIDGE_FILE${RESET}"
echo ""

if [[ -n "$PRIMARY_CMD" ]]; then
    info "AI_PRIMARY_CMD 설정됨 — 현재 터미널을 다음 명령으로 전환 (cwd=$BRIDGE_WORKDIR):"
    info "  $PRIMARY_CMD"
    sleep 1
    cd "$BRIDGE_WORKDIR" || { echo "ERROR: cd $BRIDGE_WORKDIR 실패" >&2; exit 1; }
    exec bash -lc "$PRIMARY_CMD"
fi

if [[ ! -t 0 ]]; then
    info "stdin이 TTY가 아님 — attach prompt 생략. 'tmux attach -t $TMUX_SESSION'로 직접 진입."
    exit 0
fi

read -p "지금 tmux '$TMUX_SESSION' 세션에 attach할까요? [y/N] " -r REPLY
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    exec tmux attach -t "$TMUX_SESSION"
else
    echo "  Tip: ${BOLD}tmux attach -t $TMUX_SESSION${RESET}로 언제든 진입 가능"
fi
