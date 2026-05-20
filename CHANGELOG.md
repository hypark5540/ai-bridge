# Changelog

All notable changes to ai-bridge are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `AGENTS.md` — AI 코딩 어시스턴트용 repo 가이드 (project context, 검증 명령, bridge pingpong 규칙, safety 규칙).

## [0.2.0] — 2026-05-20

### ⚠️ Breaking Changes
- **Direction wrappers force-set `AI_PRIMARY_CMD` / `AI_SECONDARY_CMD`.** 이 두 변수는 wrapper의 정체성(코드bridge=codex primary)이라 매 invocation마다 wrapper가 무조건 결정한다. 기존 `${AI_PRIMARY_CMD:-default}` override 패턴 제거.
  - **이유**: `${VAR:-}` 패턴은 nested 실행(ai-bridge로 띄운 AI 내부 셸에서 wrapper 재실행) 시 부모 env의 `AI_PRIMARY_CMD`를 상속 → wrapper의 의도된 명령(YOLO 등)이 silent하게 무시됨.
  - **마이그레이션**: `AI_PRIMARY_CMD` / `AI_SECONDARY_CMD`를 env로 직접 설정해 customize하던 사용자는 신규 `AI_BRIDGE_PRIMARY_CMD_OVERRIDE` / `AI_BRIDGE_SECONDARY_CMD_OVERRIDE`로 이전. 구 변수가 외부에서 set인데 override 변수가 없으면 **fail-fast** (silent 오염 방지).

### Added
- `AI_BRIDGE_PRIMARY_CMD_OVERRIDE` / `AI_BRIDGE_SECONDARY_CMD_OVERRIDE` — pair-scoped 실행 명령을 의도적으로 customize하는 명시 변수. nested env 상속과 구분됨.
- core `ai-bridge.sh` — `AI_PRIMARY_CMD`에 YOLO/bypass 패턴(`--dangerously-bypass-approvals-and-sandbox` / `danger-full-access` / `-a never`) 감지 시 exec 직전 ⚠️ 경고 배너 (실제 command 문자열 포함).
- smoke.sh force-set 회귀 케이스 3건 (깨끗한 env default / 오염 env fail-fast / override 변수 적용).
- `install.sh` bootstrapper for first-time local setup: wrapper copy/chmod, shell profile PATH block, dependency checks, and optional tmux/Codex/Claude install prompts.
- Smoke fixture coverage for installer wrapper preservation, `--force`, PATH block idempotency, `--no-path-edit`, and shell profile selection.
- Direction wrappers now inject a one-line ai-bridge startup guide into the default Claude/Codex commands so first-run review/pingpong requests follow the bridge rules without separate global AI memory setup.
- Startup guidance now states that review requests are pingpong rounds, not one-shot handoffs; the requester must read reviewer findings and either continue the round or conclude.
- Pingpong termination is now explicit: conclude only when both Claude and Codex report Confidence >= 90 with satisfied/matching Conclusions, otherwise continue up to round 5 and then ask the user.
- Codex defaults now start with `gpt-5.5` and `model_reasoning_effort=xhigh` in both codex-primary and claude-primary wrappers.
- Review orchestration guidance now makes the primary AI a sequential coordinator: produce local findings, hand them to the reviewer, wait for the reviewer response, reconcile, then continue or conclude instead of emitting parallel independent finals.

### Changed
- Direction wrappers now default `AI_OPEN_TERMINAL=1`, so macOS users get the secondary tmux session in a new Terminal window by default. Set `AI_OPEN_TERMINAL=0` to keep single-window behavior.
- Direction wrappers now default `AI_BRIDGE_WORKDIR` to the launch cwd instead of `$HOME`, so repo-local README/CONTRIBUTING/AGENTS/CLAUDE guidance is visible from the first run. Set `AI_BRIDGE_WORKDIR=$HOME` to keep the old behavior.
- `ai-bridge.sh` cheatsheet — "금지: YOLO 모드" 절을 별도 "주의 (YOLO/bypass)" 절로 톤 조정. 절대 금지가 아니라 "신뢰된 개인 throwaway 환경에서만, bridge 자동 paste 결합 시 위험 가중"의 조건부 경고. codex CLI의 의도적 `--dangerously-bypass` 사용(개인 private wrapper)과 충돌하지 않도록.

### Fixed
- Installer documentation now distinguishes dependency installation from wrapper/PATH setup for `--no-install`.
- Installer documentation now states that `--yes` also auto-confirms remote installer prompts.
- macOS bash users get the PATH block in `~/.bash_profile` instead of `~/.bashrc`.
- Ignore accidental nested `ai-bridge/` clones inside the repo root.

## [0.1.2] — 2026-05-19

### Added
- **신규 CI job `secret-scan` (gitleaks)** — bridge 파일·wrapper template에 토큰/키/AWS 자격이 commit되는 걸 사전 차단. fetch-depth 0으로 과거 commit history도 스캔. GitHub Marketplace gitleaks-action v2 사용 (public/personal repo 무료).
- **README badges** — smoke CI status, latest release, license. 첫 화면에서 repo 건강도 한눈 확인.

### Changed
- `actions/checkout` v4 → v6 (dependabot PR #1, merge `84547da`). Node 24 runtime + credentials separate file. 우리 use case는 checkout 뒤 git push/Docker credential handoff 없어서 호환성 영향 없음. Node 20 deprecation warning 해소 보너스.

### Notes
- v0.1.1 PR #1 dependabot이 stale base(`6ff618c`) 위에 빌드되어 shellcheck strict job fail. `@dependabot rebase` 코멘트로 main의 shellcheck fix 끌어와 머지. 다음부터는 dependabot이 자동으로 최신 main에 rebase하므로 같은 패턴 안 생김.

## [0.1.1] — 2026-05-19

### Fixed
- Linux GNU stat 호환성 — `stat -f "%Lp"`가 Linux에서 filesystem 정보로 해석되는 platform 분기 차이로 CI Ubuntu runner에서 mode display가 garbage 출력되던 회귀 수정. `get_file_mode()` helper로 GNU(`stat -c %a`) 우선 + BSD(`stat -f %Lp`) fallback + 결과 `^[0-7]+$` validation. 실제 `chmod 0600` 강제는 정상 동작했으나 display + smoke #8/#8b가 깨졌음. (ai-bridge.sh, tests/smoke.sh) — commit `e6106a7`
- Shellcheck strict 도입 후 3건 violation 정리 — `NEW_SESSION` dead code 제거 (ai-bridge.sh SC2034), `ls | grep` 패턴에 inline `shellcheck disable=SC2010` + safety 주석 (wrapper `.example` × 2 + private wrapper × 2 동기화). — commit `2e4cffc`

### Added (CI / DX 강화)
- **smoke.yml concurrency guard** — 같은 ref에서 새 push면 in-flight run cancel (quota 절약).
- **신규 job `macos-bash-3-compat`** — macOS 기본 `/bin/bash` (3.2)로 syntax 검증. README "bash 3.2 호환" 주장을 CI level enforce.
- **신규 job `links`** — lychee-action markdown link check (advisory, `fail: false`).
- **wrapper `--version` side-effect 검증 step** — CI level 이중 가드 (smoke #13b 외 별도 step).
- **shellcheck strict** — `continue-on-error` 제거. severity `warning` 이상 fail.
- **`.github/release.yml`** — GitHub native Release Notes 자동 카테고리화 (Breaking/Features/Fixes/Security/Docs/Tests/CI/Other) + dependabot author 제외.
- **`.github/dependabot.yml`** — actions 버전 주간 PR (Asia/Seoul Mon 09:00, minor+patch 그룹화, max 5 PR).

### Changed (문서)
- **README** — 첫 문단 직후 `## 시작 진입점` 신설. `./claude-bridge.sh` / `./codex-bridge.sh` 두 wrapper 비교표 + 실행 한 줄 + anchor link로 readers의 첫 진입 흐름 개선. 영어 quick-start도 양방향 모두 노출.
- **CONTRIBUTING** — CI 4 job 구조 (smoke matrix + bash3-compat + shellcheck strict + links) + PR label 정책 표 (release.yml 자동 카테고리화 연동) 명시.
- **CHANGELOG**: 이 entry.

### Notes
- v0.1.0 (commit `cba3465`)은 push 직후 CI fail 상태로 박혀 있었음. v0.1.1이 처음으로 모든 CI green 도달한 release. 외부 사용자는 v0.1.1 이상 권장.

## [0.1.0] — 2026-05-19

### Added
- Initial public release of ai-bridge — Claude Code ↔ Codex CLI 교차 검증 환경 셋업 도구.
- Core script `ai-bridge.sh`: env validation, bridge file lifecycle (auto-create + chmod 0600 강제), tmux session orchestration, macOS Terminal opt-in.
- Direction wrappers `claude-bridge.sh.example` / `codex-bridge.sh.example`:
  - PID-paired isolation (`bridge-claude-<PID>.md` / `bridge-codex-<PID>.md`).
  - Dynamic `AI_BRIDGE_HOME` resolution with pure-bash readlink fallback (macOS BSD readlink 미지원 환경 포함).
  - `AI_BRIDGE_PAIRS_DIR` env override (기본 `$HOME/ai-bridge-pairs`).
  - Bidirectional `list` mode showing both `claude-primary` and `codex-primary` pair groups.
- `tests/smoke.sh` offline regression suite (24 cases): syntax × 4 파일, env validation, bridge perm lifecycle, AI_BRIDGE_HOME resolution, symlink-invoke resolve, PAIRS_DIR override, regex `:` rejection 회귀, template guard pass/fail, `--version` side-effect 차단, read-only dir fail-fast.
- `.github/workflows/smoke.yml`: Ubuntu + macOS matrix CI (bash -n + smoke + optional shellcheck).
- README, CONTRIBUTING, SECURITY, LICENSE (MIT), Issue / PR templates.

### Security
- `AI_TMUX_SESSION` regex 화이트리스트 강화 — 콜론(`:`) 제외해 tmux `session:window` 오해석 차단.
- `AI_PRIMARY_CMD` / `AI_SECONDARY_CMD` control-char/newline reject.
- bridge 파일 신규 생성 시 `umask 0177` + 명시적 `chmod 0600`. 기존 파일도 자동 보정.
- `osascript` 호출 argv 패턴 — string interpolation 차단.

### Documentation
- README에 install-time dependency 없음 명시 (`$HOME/ai-bridge-pairs/`는 wrapper의 `mkdir -p`로 runtime 자동 생성).
- 환경변수 표 정리: `AI_BRIDGE_FILE`, `AI_TMUX_SESSION`, `AI_OPEN_TERMINAL`, `AI_BRIDGE_WORKDIR`, `AI_BRIDGE_HOME`, `AI_BRIDGE_PAIRS_DIR`, `AI_BRIDGE_DRY_RUN`, etc.

### Notes
- First commit. Tag `v0.1.0` 추정.
- Breaking change 없음 (이전 버전 없음).

[Unreleased]: https://github.com/hypark5540/ai-bridge/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/hypark5540/ai-bridge/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/hypark5540/ai-bridge/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/hypark5540/ai-bridge/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/hypark5540/ai-bridge/releases/tag/v0.1.0
