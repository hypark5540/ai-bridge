#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# ai-bridge offline smoke test.
#
# 실행: bash tests/smoke.sh
#
# 검증 항목 (실제 tmux 세션 생성 / AI CLI 실행은 안 함):
#   1. bash -n syntax check 5개 파일
#   2. --version 출력
#   3. AI_OPEN_TERMINAL 0|1 validation
#   4. AI_TMUX_HISTORY_LIMIT integer validation
#   5. AI_TMUX_SESSION regex validation (injection 방어)
#   6. AI_BRIDGE_WORKDIR 존재 검증
#   7. AI_PRIMARY_CMD newline 거부
#   8. bridge 파일 0600 신규 생성
#   9. AI_BRIDGE_HOME resolution (wrapper.example)
#   10. install.sh wrapper/profile behavior in temp fixtures

set -uo pipefail  # 미정의 변수 + pipeline 첫 실패 catch (-e는 명시적 fail() 카운트와 충돌하므로 제외)

# GNU stat (Linux) 우선, BSD stat (macOS) fallback. 양쪽 출력이 mode 숫자인지 검증.
# stat -f는 GNU에선 filesystem info를 뜻해서 silent fail이 아니라 garbage 출력 — 명시 validation.
get_file_mode() {
    local f="$1" m
    m=$(stat -c "%a" "$f" 2>/dev/null) || true
    if [[ "$m" =~ ^[0-7]+$ ]]; then echo "$m"; return 0; fi
    m=$(stat -f "%Lp" "$f" 2>/dev/null) || true
    if [[ "$m" =~ ^[0-7]+$ ]]; then echo "$m"; return 0; fi
    echo "?"
}
PASS=0
FAIL=0
FAILED_TESTS=()

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMPDIR_TEST="$(mktemp -d)"
# 테스트 중 실수로 만든 tmux 세션 흔적 cleanup (PID-tagged → smoke- 접두)
TEST_TMUX_PREFIX="smoke-$$"
cleanup_test() {
    local rc=$?
    # 혹시 만들어졌을 smoke-* tmux 세션 강제 종료 (운영자 의도 침범 없는 격리 이름)
    if command -v tmux >/dev/null 2>&1; then
        tmux ls 2>/dev/null | awk -F: '/^smoke-/{print $1}' | while read -r s; do
            tmux kill-session -t "$s" 2>/dev/null || true
        done
    fi
    rm -rf "$TMPDIR_TEST"
    exit $rc
}
trap cleanup_test EXIT INT TERM

pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL+1)); FAILED_TESTS+=("$1"); }

# ai-bridge.sh 호출 헬퍼.
# - stdin /dev/null로 닫아 read prompt 가드 작동
# - env -i로 호출자 셸 env 격리
# - 새 tmux 세션은 smoke-$$ 접두로 격리 (실제 codex/claude session과 분리)
# - AI_BRIDGE_DRY_RUN=1 기본값 — bridge 파일 검증/생성까지만, tmux 세션 안 만듦 → CI에서도 결정적
run_core() {
    local label="$1"; shift
    env -i \
        HOME="$HOME" \
        PATH="$PATH" \
        TERM="${TERM:-dumb}" \
        AI_TMUX_SESSION="${TEST_TMUX_PREFIX}-${label}" \
        AI_BRIDGE_DRY_RUN=1 \
        "$@" \
        bash "$SCRIPT_DIR/ai-bridge.sh" </dev/null 2>&1
}

echo "── 1. syntax check ──"
for f in ai-bridge.sh install.sh claude-bridge.sh.example codex-bridge.sh.example tests/smoke.sh; do
    if bash -n "$SCRIPT_DIR/$f" 2>/dev/null; then
        pass "bash -n $f"
    else
        fail "bash -n $f"
    fi
done

echo
echo "── 2. --version 출력 ──"
out=$(bash "$SCRIPT_DIR/ai-bridge.sh" --version 2>&1)
expected="ai-bridge $(head -1 "$SCRIPT_DIR/VERSION" | tr -d '[:space:]')"
if [[ "$out" == "$expected" ]]; then
    pass "--version returns '$expected'"
else
    fail "--version expected '$expected', got: $out"
fi

echo
echo "── 3. AI_OPEN_TERMINAL validation ──"
out=$(run_core "open-terminal-bad" \
    AI_BRIDGE_FILE="$TMPDIR_TEST/b1.md" \
    AI_OPEN_TERMINAL="2" || true)
if echo "$out" | grep -q "AI_OPEN_TERMINAL must be 0 or 1"; then
    pass "AI_OPEN_TERMINAL=2 rejected"
else
    fail "AI_OPEN_TERMINAL=2 not rejected. Output: $out"
fi

echo
echo "── 4. AI_TMUX_HISTORY_LIMIT validation ──"
out=$(run_core "history-bad" \
    AI_BRIDGE_FILE="$TMPDIR_TEST/b2.md" \
    AI_TMUX_HISTORY_LIMIT="abc" || true)
if echo "$out" | grep -q "AI_TMUX_HISTORY_LIMIT must be"; then
    pass "AI_TMUX_HISTORY_LIMIT=abc rejected"
else
    fail "AI_TMUX_HISTORY_LIMIT=abc not rejected. Output: $out"
fi

out=$(run_core "history-low" \
    AI_BRIDGE_FILE="$TMPDIR_TEST/b3.md" \
    AI_TMUX_HISTORY_LIMIT="50" || true)
if echo "$out" | grep -q "AI_TMUX_HISTORY_LIMIT must be"; then
    pass "AI_TMUX_HISTORY_LIMIT=50 (below 100) rejected"
else
    fail "AI_TMUX_HISTORY_LIMIT=50 not rejected. Output: $out"
fi

echo
echo "── 5. AI_TMUX_SESSION regex validation (injection 방어) ──"
out=$(run_core "session-injection" \
    AI_BRIDGE_FILE="$TMPDIR_TEST/b4.md" \
    AI_TMUX_SESSION='a;rm -rf /' || true)
if echo "$out" | grep -q "AI_TMUX_SESSION must match"; then
    pass "AI_TMUX_SESSION='a;rm -rf /' rejected"
else
    fail "session injection not rejected. Output: $out"
fi

echo
echo "── 6. AI_BRIDGE_WORKDIR 존재 검증 ──"
out=$(run_core "workdir-missing" \
    AI_BRIDGE_FILE="$TMPDIR_TEST/b5.md" \
    AI_BRIDGE_WORKDIR="/tmp/definitely-does-not-exist-$$" || true)
if echo "$out" | grep -q "AI_BRIDGE_WORKDIR is not a directory"; then
    pass "missing AI_BRIDGE_WORKDIR rejected"
else
    fail "missing workdir not rejected. Output: $out"
fi

echo
echo "── 7. AI_PRIMARY_CMD newline 거부 ──"
out=$(run_core "cmd-newline" \
    AI_BRIDGE_FILE="$TMPDIR_TEST/b6.md" \
    AI_PRIMARY_CMD=$'claude\nrm -rf /' || true)
if echo "$out" | grep -q "contains control/newline characters"; then
    pass "AI_PRIMARY_CMD with newline rejected"
else
    fail "newline injection not rejected. Output: $out"
fi

echo
echo "── 8. bridge 0600 신규 생성 (DRY_RUN, tmux 의존 없음) ──"
BRIDGE_NEW="$TMPDIR_TEST/new-bridge-$$.md"
# AI_BRIDGE_DRY_RUN=1 기본값으로 bridge 파일 생성까지만 진행, tmux 세션 생성 안 함.
# 따라서 tmux 미설치 환경(CI 컨테이너 등)에서도 결정적으로 검증 가능.
out=$(run_core "bridge-create" AI_BRIDGE_FILE="$BRIDGE_NEW" || true)
if [[ ! -f "$BRIDGE_NEW" ]]; then
    fail "bridge 파일 생성 안 됨. Output: $out"
else
    perm=$(get_file_mode "$BRIDGE_NEW")
    if [[ "$perm" == "600" ]]; then
        pass "신규 bridge 파일 mode=0600 (DRY_RUN 모드)"
    else
        fail "신규 bridge 파일 mode=$perm (expected 600)"
    fi
fi

echo
echo "── 8b. 기존 bridge 파일 권한 0644 → 0600 자동 보정 ──"
BRIDGE_EXISTING="$TMPDIR_TEST/existing-bridge-$$.md"
echo "pre-existing content" > "$BRIDGE_EXISTING"
chmod 0644 "$BRIDGE_EXISTING"
out=$(run_core "bridge-chmod-fix" AI_BRIDGE_FILE="$BRIDGE_EXISTING" || true)
perm=$(get_file_mode "$BRIDGE_EXISTING")
if [[ "$perm" == "600" ]]; then
    pass "기존 0644 bridge가 0600으로 자동 보정됨"
else
    fail "기존 bridge mode=$perm (expected 600 after auto-fix). Output: $out"
fi

echo
echo "── 8c. AI_BRIDGE_DRY_RUN=1이 tmux 세션 안 만드는지 ──"
# run_core 이미 DRY_RUN=1이라 smoke-*-* 세션 존재하면 안 됨
if command -v tmux >/dev/null 2>&1 && tmux ls 2>/dev/null | grep -q "^${TEST_TMUX_PREFIX}-"; then
    fail "DRY_RUN인데 tmux 세션 생성됨: $(tmux ls 2>/dev/null | grep "^${TEST_TMUX_PREFIX}-")"
else
    pass "DRY_RUN=1로 tmux 세션 안 만들어짐"
fi

echo
echo "── 9. AI_BRIDGE_HOME resolution (wrapper.example) ──"
# wrapper.example을 source 없이 실행만 — list 모드라 cd 등 side-effect 없음
out=$(bash "$SCRIPT_DIR/claude-bridge.sh.example" list 2>&1 | head -3)
if echo "$out" | grep -qE "claude-primary|none|attached"; then
    pass "claude-bridge.sh.example list 모드 실행 OK"
else
    fail "claude-bridge.sh.example list 실패. Output: $out"
fi

out=$(bash "$SCRIPT_DIR/codex-bridge.sh.example" list 2>&1 | head -3)
if echo "$out" | grep -qE "claude-primary|none|attached"; then
    pass "codex-bridge.sh.example list 모드 실행 OK"
else
    fail "codex-bridge.sh.example list 실패. Output: $out"
fi

echo
echo "── 10. AI_BRIDGE_PAIRS_DIR override (env로 pairs 위치 변경) ──"
CUSTOM_PAIRS="$TMPDIR_TEST/custom-pairs"
mkdir -p "$CUSTOM_PAIRS"
out=$(AI_BRIDGE_PAIRS_DIR="$CUSTOM_PAIRS" bash "$SCRIPT_DIR/claude-bridge.sh.example" list 2>&1)
if echo "$out" | grep -qF "bridge files ($CUSTOM_PAIRS)"; then
    pass "AI_BRIDGE_PAIRS_DIR override가 list 출력에 반영됨"
else
    fail "AI_BRIDGE_PAIRS_DIR override 미반영. Output: $out"
fi

echo
echo "── 11. AI_TMUX_SESSION regex 회귀 (`:` 거부) ──"
# tmux session 이름에 `:` 있으면 `session:window` 형식으로 오해석 → 거부해야 함
out=$(run_core "colon-rejected" \
    AI_BRIDGE_FILE="$TMPDIR_TEST/b-colon.md" \
    AI_TMUX_SESSION="my:session" || true)
if echo "$out" | grep -q "AI_TMUX_SESSION must match"; then
    pass "AI_TMUX_SESSION='my:session' rejected (`:` 제외 회귀 가드)"
else
    fail "AI_TMUX_SESSION=':' 포함 not rejected. Output: $out"
fi

echo
echo "── 12. symlink로 wrapper 호출시 AI_BRIDGE_HOME resolve 정확성 ──"
# wrapper.example을 symlink로 노출했을 때 AI_BRIDGE_HOME이 실제 wrapper 위치로 resolve되는지
SYMLINK_DIR="$TMPDIR_TEST/syml"
mkdir -p "$SYMLINK_DIR"
ln -sf "$SCRIPT_DIR/claude-bridge.sh.example" "$SYMLINK_DIR/claude-bridge.sh"
out=$(bash "$SYMLINK_DIR/claude-bridge.sh" list 2>&1)
# list 출력에 "claude-primary" 헤더가 있고, core script 호출 시도 시 list 모드라 exit — error 없으면 resolve 성공
if echo "$out" | grep -q "claude-primary pairs" && ! echo "$out" | grep -q "ERROR: core script not found"; then
    pass "symlink 통한 호출에서 AI_BRIDGE_HOME 올바르게 resolve됨"
else
    fail "symlink 호출시 AI_BRIDGE_HOME resolve 실패. Output: $out"
fi

echo
echo "── 13a. wrapper.example template guard (read-only commands만 우회) ──"
# `list` / `--version`은 통과, 본 흐름(no-arg)은 거부
out=$(bash "$SCRIPT_DIR/claude-bridge.sh.example" 2>&1 || true)
if echo "$out" | grep -q "is a template"; then
    pass "wrapper.example 직접 실행 (no arg) → template guard 동작"
else
    fail "wrapper.example guard 미동작. Output: $out"
fi
out=$(bash "$SCRIPT_DIR/claude-bridge.sh.example" list 2>&1 || true)
if ! echo "$out" | grep -q "is a template"; then
    pass "wrapper.example list 서브명령은 guard 우회"
else
    fail "list 명령도 guard에 걸림 (overly strict). Output: $out"
fi

echo
echo "── 13b. wrapper.example --version side-effect 차단 (codex round 3 P1 회귀) ──"
# wrapper.example --version은 core에 즉시 위임해야 함 — pair setup 경로로 진입하면 안 됨
# (이전 버전 버그: $@ 미전달로 pair 생성 + bridge 파일 side-effect)
VER_PAIRS="$TMPDIR_TEST/version-side-effect-check"
mkdir -p "$VER_PAIRS"
out=$(AI_BRIDGE_PAIRS_DIR="$VER_PAIRS" \
      bash "$SCRIPT_DIR/claude-bridge.sh.example" --version 2>&1 || true)
# (a) 정확한 version string이 떠야 함
expected_ver="ai-bridge $(head -1 "$SCRIPT_DIR/VERSION" | tr -d '[:space:]')"
if echo "$out" | grep -qF "$expected_ver"; then
    pass "wrapper.example --version이 core version 정확히 출력"
else
    fail "wrapper.example --version 출력 불일치. Expected: '$expected_ver'. Got: $out"
fi
# (b) bridge/pair 파일 side-effect 없어야 함
created=$(find "$VER_PAIRS" -mindepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
if [[ "$created" == "0" ]]; then
    pass "wrapper.example --version으로 pair/bridge 파일 생성 0건 (side-effect 차단)"
else
    fail "wrapper.example --version이 $created개 파일 생성 (side-effect 발생): $(find "$VER_PAIRS" -mindepth 1)"
fi

echo
echo "── 13. chmod 실패 시 fail-fast (read-only dir에서 bridge 생성 시도) ──"
# bridge 부모 디렉토리를 read-only로 만들고 그 안에 bridge 만들려고 하면 mkdir 또는 chmod 단계에서 fail
RO_DIR="$TMPDIR_TEST/readonly"
mkdir -p "$RO_DIR"
chmod 0555 "$RO_DIR"   # r-x only — 신규 파일 생성 불가
out=$(run_core "bridge-create-blocked" \
    AI_BRIDGE_FILE="$RO_DIR/bridge-blocked.md" 2>&1 || true)
# 어떤 에러든 명시적 ERROR/fail이 떠야 함 (silent success 금지)
if echo "$out" | grep -qE "(생성 실패|실패|ERROR|중단)"; then
    pass "read-only dir에서 bridge 생성 시 fail-fast"
else
    fail "read-only dir에서 silent fail. Output: $out"
fi
chmod 0755 "$RO_DIR"  # cleanup용 권한 복구

echo
echo "── 14. install.sh fixture tests ──"
make_install_fixture() {
    local fixture="$1"
    mkdir -p "$fixture"
    cp "$SCRIPT_DIR/install.sh" \
       "$SCRIPT_DIR/ai-bridge.sh" \
       "$SCRIPT_DIR/claude-bridge.sh.example" \
       "$SCRIPT_DIR/codex-bridge.sh.example" \
       "$fixture/"
}

INSTALL_FIXTURE="$TMPDIR_TEST/install-fixture"
INSTALL_HOME="$TMPDIR_TEST/install-home"
make_install_fixture "$INSTALL_FIXTURE"
mkdir -p "$INSTALL_HOME"
out=$(HOME="$INSTALL_HOME" SHELL="/bin/zsh" \
      bash "$INSTALL_FIXTURE/install.sh" --no-install 2>&1 || true)
if [[ -x "$INSTALL_FIXTURE/claude-bridge.sh" && -x "$INSTALL_FIXTURE/codex-bridge.sh" ]]; then
    pass "install.sh creates executable wrapper copies"
else
    fail "install.sh did not create executable wrapper copies. Output: $out"
fi
marker_count=$(grep -cF "# >>> ai-bridge PATH >>>" "$INSTALL_HOME/.zshrc" 2>/dev/null || true)
if [[ "$marker_count" == "1" ]]; then
    pass "install.sh writes one PATH profile block"
else
    fail "install.sh PATH profile block count=$marker_count (expected 1). Output: $out"
fi

INSTALL_FIXTURE_REAL="$(cd "$INSTALL_FIXTURE" && pwd -P)"
out=$(cd "$INSTALL_FIXTURE" && env -i HOME="$INSTALL_HOME" SHELL="/bin/zsh" PATH="$PATH" TERM="${TERM:-dumb}" \
      AI_BRIDGE_DRY_RUN=1 AI_OPEN_TERMINAL=0 bash ./claude-bridge.sh 2>&1 || true)
if echo "$out" | grep -qF "Review\\ Flow" && echo "$out" | grep -qF "sequential\\ coordinator" && echo "$out" | grep -qF "independent\\ parallel\\ reviews" && echo "$out" | grep -qF "not\\ one-shot" && echo "$out" | grep -qF "Confidence\\ \\>=\\ 90" && echo "$out" | grep -qF "round\\ 5" && echo "$out" | grep -qF "workdir: $INSTALL_FIXTURE_REAL"; then
    pass "installed claude wrapper injects startup guide and defaults workdir to launch cwd"
else
    fail "installed claude wrapper did not expose startup guide/workdir. Output: $out"
fi
if echo "$out" | grep -qF "codex -m gpt-5.5 -c model_reasoning_effort=xhigh"; then
    pass "installed claude wrapper starts secondary Codex with gpt-5.5 xhigh"
else
    fail "installed claude wrapper did not set secondary Codex gpt-5.5 xhigh. Output: $out"
fi

out=$(cd "$INSTALL_FIXTURE" && env -i HOME="$INSTALL_HOME" SHELL="/bin/zsh" PATH="$PATH" TERM="${TERM:-dumb}" \
      AI_BRIDGE_DRY_RUN=1 AI_OPEN_TERMINAL=0 bash ./codex-bridge.sh 2>&1 || true)
if echo "$out" | grep -qF "Review\\ Flow" && echo "$out" | grep -qF "sequential\\ coordinator" && echo "$out" | grep -qF "independent\\ parallel\\ reviews" && echo "$out" | grep -qF "not\\ one-shot" && echo "$out" | grep -qF "Confidence\\ \\>=\\ 90" && echo "$out" | grep -qF "round\\ 5" && echo "$out" | grep -qF "workdir: $INSTALL_FIXTURE_REAL"; then
    pass "installed codex wrapper injects startup guide and defaults workdir to launch cwd"
else
    fail "installed codex wrapper did not expose startup guide/workdir. Output: $out"
fi
if echo "$out" | grep -qF "codex -m gpt-5.5 -c model_reasoning_effort=xhigh"; then
    pass "installed codex wrapper starts primary Codex with gpt-5.5 xhigh"
else
    fail "installed codex wrapper did not set primary Codex gpt-5.5 xhigh. Output: $out"
fi
unset INSTALL_FIXTURE_REAL

printf '%s\n' '# local claude wrapper' > "$INSTALL_FIXTURE/claude-bridge.sh"
chmod +x "$INSTALL_FIXTURE/claude-bridge.sh"
out=$(HOME="$INSTALL_HOME" SHELL="/bin/zsh" \
      bash "$INSTALL_FIXTURE/install.sh" --no-install 2>&1 || true)
if grep -qF "# local claude wrapper" "$INSTALL_FIXTURE/claude-bridge.sh"; then
    pass "install.sh preserves existing wrappers without --force"
else
    fail "install.sh overwrote existing wrapper without --force. Output: $out"
fi
marker_count=$(grep -cF "# >>> ai-bridge PATH >>>" "$INSTALL_HOME/.zshrc" 2>/dev/null || true)
if [[ "$marker_count" == "1" ]]; then
    pass "install.sh PATH profile block is idempotent"
else
    fail "install.sh PATH profile block count after rerun=$marker_count (expected 1). Output: $out"
fi

out=$(HOME="$INSTALL_HOME" SHELL="/bin/zsh" \
      bash "$INSTALL_FIXTURE/install.sh" --force --no-install --no-path-edit 2>&1 || true)
if cmp -s "$INSTALL_FIXTURE/claude-bridge.sh.example" "$INSTALL_FIXTURE/claude-bridge.sh"; then
    pass "install.sh --force refreshes wrapper from template"
else
    fail "install.sh --force did not refresh wrapper from template. Output: $out"
fi

BASH_PROFILE_FIXTURE="$TMPDIR_TEST/install-bash-profile-fixture"
BASH_PROFILE_HOME="$TMPDIR_TEST/install-bash-profile-home"
make_install_fixture "$BASH_PROFILE_FIXTURE"
mkdir -p "$BASH_PROFILE_HOME"
out=$(HOME="$BASH_PROFILE_HOME" SHELL="/bin/bash" \
      bash "$BASH_PROFILE_FIXTURE/install.sh" --no-install 2>&1 || true)
if [[ "$(uname -s 2>/dev/null || echo unknown)" == "Darwin" ]]; then
    expected_profile="$BASH_PROFILE_HOME/.bash_profile"
    unexpected_profile="$BASH_PROFILE_HOME/.bashrc"
else
    expected_profile="$BASH_PROFILE_HOME/.bashrc"
    unexpected_profile="$BASH_PROFILE_HOME/.bash_profile"
fi
marker_count=$(grep -cF "# >>> ai-bridge PATH >>>" "$expected_profile" 2>/dev/null || true)
if [[ "$marker_count" == "1" && ! -e "$unexpected_profile" ]]; then
    pass "install.sh chooses bash profile for this OS"
else
    fail "install.sh bash profile selection wrong. expected=$expected_profile marker_count=$marker_count unexpected=$unexpected_profile exists=$([[ -e "$unexpected_profile" ]] && echo yes || echo no). Output: $out"
fi
unset expected_profile unexpected_profile

NO_PATH_FIXTURE="$TMPDIR_TEST/install-no-path-fixture"
NO_PATH_HOME="$TMPDIR_TEST/install-no-path-home"
make_install_fixture "$NO_PATH_FIXTURE"
mkdir -p "$NO_PATH_HOME"
out=$(HOME="$NO_PATH_HOME" SHELL="/bin/zsh" AI_BRIDGE_INSTALL_NO_DEPS=1 AI_BRIDGE_NO_PATH_EDIT=1 \
      bash "$NO_PATH_FIXTURE/install.sh" 2>&1 || true)
if [[ ! -e "$NO_PATH_HOME/.zshrc" ]]; then
    pass "AI_BRIDGE_NO_PATH_EDIT=1 avoids creating shell profile"
else
    fail "AI_BRIDGE_NO_PATH_EDIT=1 created shell profile unexpectedly. Output: $out"
fi

echo
echo "── 15. force-set: wrapper가 AI_PRIMARY_CMD/SECONDARY_CMD를 무조건 결정 ──"
# wrapper.example을 .sh로 cp (template guard 우회) — private wrapper는 gitignored라 CI에 없음.
FORCESET_DIR="$TMPDIR_TEST/forceset"
mkdir -p "$FORCESET_DIR"
cp "$SCRIPT_DIR/codex-bridge.sh.example" "$FORCESET_DIR/codex-bridge.sh"
cp "$SCRIPT_DIR/ai-bridge.sh" "$FORCESET_DIR/ai-bridge.sh"
cp "$SCRIPT_DIR/VERSION" "$FORCESET_DIR/VERSION"
chmod +x "$FORCESET_DIR/codex-bridge.sh" "$FORCESET_DIR/ai-bridge.sh"

# (가) 깨끗한 env → wrapper default(codex) 적용
out=$(env -i HOME="$HOME" PATH="$PATH" TERM=dumb AI_BRIDGE_DRY_RUN=1 \
      AI_BRIDGE_PAIRS_DIR="$FORCESET_DIR/pairs" \
      bash "$FORCESET_DIR/codex-bridge.sh" </dev/null 2>&1 || true)
if echo "$out" | grep -q "primary: codex"; then
    pass "force-set: 깨끗한 env에서 wrapper default(codex) 적용"
else
    fail "force-set 깨끗한 env 실패. Output: $out"
fi

# (나) AI_PRIMARY_CMD 오염 + override 없음 → fail-fast
out=$(env -i HOME="$HOME" PATH="$PATH" TERM=dumb AI_BRIDGE_DRY_RUN=1 \
      AI_BRIDGE_PAIRS_DIR="$FORCESET_DIR/pairs" \
      AI_PRIMARY_CMD="claude" \
      bash "$FORCESET_DIR/codex-bridge.sh" </dev/null 2>&1 || true)
if echo "$out" | grep -q "v0.2.0부터 무시/거부"; then
    pass "force-set: 오염된 AI_PRIMARY_CMD env → fail-fast"
else
    fail "force-set fail-fast 미발동. Output: $out"
fi

# (다) AI_BRIDGE_PRIMARY_CMD_OVERRIDE → 오염 무시하고 override 적용
out=$(env -i HOME="$HOME" PATH="$PATH" TERM=dumb AI_BRIDGE_DRY_RUN=1 \
      AI_BRIDGE_PAIRS_DIR="$FORCESET_DIR/pairs" \
      AI_PRIMARY_CMD="claude" \
      AI_BRIDGE_PRIMARY_CMD_OVERRIDE="codex --smoke-override-marker" \
      bash "$FORCESET_DIR/codex-bridge.sh" </dev/null 2>&1 || true)
if echo "$out" | grep -q "smoke-override-marker"; then
    pass "force-set: AI_BRIDGE_PRIMARY_CMD_OVERRIDE 적용 (오염 무시)"
else
    fail "force-set override 미적용. Output: $out"
fi

echo
echo "════════════════════════════════════════"
echo "  Pass: $PASS"
echo "  Fail: $FAIL"
echo "════════════════════════════════════════"
if [[ $FAIL -gt 0 ]]; then
    echo "Failed tests:"
    for t in "${FAILED_TESTS[@]}"; do echo "  - $t"; done
    exit 1
fi
exit 0
