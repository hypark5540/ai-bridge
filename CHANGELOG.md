# Changelog

All notable changes to ai-bridge are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/hypark5540/ai-bridge/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/hypark5540/ai-bridge/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/hypark5540/ai-bridge/releases/tag/v0.1.0
