# Contributing to ai-bridge

ai-bridge에 기여해주셔서 감사합니다. 이 문서는 PR을 보내기 전에 따라야 할 흐름을 정리합니다.

## 작업 흐름

1. **Issue 먼저** — 큰 변경(공개 API, env var 추가, core 로직)은 issue로 의도를 먼저 공유해주세요. 작은 fix(typo, 명확한 버그)는 곧장 PR도 OK.
2. **Fork & branch** — `main`에서 분기. branch 이름은 `fix/...`, `feat/...`, `docs/...`, `test/...` 중 하나.
3. **로컬 검증**:
   ```bash
   bash tests/smoke.sh        # 모든 케이스 pass 확인
   bash -n ai-bridge.sh install.sh claude-bridge.sh.example codex-bridge.sh.example tests/smoke.sh
   shellcheck *.sh tests/*.sh # 있다면
   ```
4. **PR 생성** — `.github/PULL_REQUEST_TEMPLATE.md` 양식을 채워주세요.
5. **CI 통과 확인** — GitHub Actions가 4개 job 돌립니다:
   - `smoke (ubuntu-latest)` / `smoke (macos-latest)` — bash -n + tests/smoke.sh + --version 동작 + wrapper side-effect 가드 (matrix)
   - `macOS /bin/bash 3.2 compat` — macOS 기본 bash 3.2로 syntax 검증 (README 호환성 주장 검증)
   - `shellcheck (warning+)` — shellcheck severity ≥ warning이면 fail (strict)
   - `markdown link check` — README/CHANGELOG/docs 외부 link 깨짐 advisory
6. **리뷰 대응** — 코멘트 반영 후 force-push 대신 추가 commit. 머지 직전 squash는 maintainer 재량.

## PR 라벨 정책 (maintainer 작업)

`.github/release.yml`은 라벨 기반으로 release notes를 자동 분류합니다. 머지 직전 maintainer가 PR에 다음 중 하나(또는 복수)를 부여:

| 라벨 | release notes 섹션 |
|---|---|
| `breaking` | ⚠️ Breaking Changes |
| `feature` / `feat` / `enhancement` | ✨ Features |
| `fix` / `bug` / `bugfix` | 🐛 Fixes |
| `security` | 🔒 Security |
| `docs` / `documentation` | 📚 Documentation |
| `test` / `tests` | 🧪 Tests |
| `ci` / `tooling` / `chore` | 🤖 CI / Tooling |
| (없거나 위 외) | 🧹 Other |
| `skip-changelog` | (release notes 제외) |

Conventional commits 메시지는 commit history용이고 GitHub generated release notes의 카테고리화에는 **PR 라벨**이 입력. 잊지 말고 부여할 것 — dependabot author는 release.yml에서 자동 제외됨.

## 커밋 메시지

Conventional Commits를 권장합니다:

```
<type>: <subject>

<optional body>

<optional footer>
```

- `type`: `feat`, `fix`, `docs`, `test`, `chore`, `refactor`, `perf`, `ci`
- subject: 50자 이내, 명령형 ("add X", "fix Y"). 한국어/영어 자유.

예시:
```
feat: AI_BRIDGE_PAIRS_DIR env override 추가

기본 ~/ai-bridge-pairs/ 외 다른 위치(XDG state dir 등)에 두고 싶은
사용자를 위해 env var override 제공. 미설정 시 기존 동작 유지.
```

## 코드 스타일

- shell: `#!/usr/bin/env bash` + `set -euo pipefail`. macOS bash 3.2 호환 유지(`BASH_SOURCE`, `[[ ... ]]`, `${!var}`는 OK; associative array 사용 금지).
- 들여쓰기 4-space.
- 함수는 소문자 + underscore. 변수도 동일하되 export하는 환경변수는 `AI_BRIDGE_*` prefix.
- 외부 입력(env, argv, 파일 내용)은 regex 화이트리스트 또는 control-char reject로 검증. shell injection 방지.

## 보안 이슈

vuln 신고는 [SECURITY.md](SECURITY.md) 참고. 공개 issue로 보고하지 마세요.

## 리뷰 기준 (maintainer가 PR을 머지하는 기준)

- [ ] CI green (`bash -n` + `tests/smoke.sh` × Ubuntu+macOS)
- [ ] CHANGELOG.md에 변경 한 줄 추가 (breaking change면 명시)
- [ ] 새 env var/flag 추가 시 README + wrapper.example 코멘트 동기화
- [ ] 보안 관련 변경은 SECURITY.md 검토 + 테스트 케이스 추가

## 질문/논의

- GitHub Issues / Discussions
- 한국어/영어 모두 환영
