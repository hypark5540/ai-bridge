# Security Policy

ai-bridge는 두 개의 로컬 AI CLI를 tmux/파일 기반으로 연결하는 thin orchestration 도구입니다. 외부 네트워크 서비스를 호스팅하지 않으며, **사용자 로컬 머신 안에서 실행되는 신뢰된 wrapper**입니다.

다만 다음 표면에 잠재 위험이 있으므로 명시합니다:

| 표면 | 위협 | 현재 방어 |
|---|---|---|
| `AI_PRIMARY_CMD` / `AI_SECONDARY_CMD` | 신뢰되지 않은 값이 들어오면 shell injection | trusted local config 전제 + control-char/newline reject + README 경고 |
| `AI_TMUX_SESSION` | tmux target 오해석 또는 argv injection | regex 화이트리스트 `^[A-Za-z0-9_.-]+$` (콜론 제외) |
| bridge 파일 | secrets/tokens가 평문 노출 | 0600 자동 보정 + README의 "토큰/비밀번호 금지" 명시 |
| `tmux capture-pane` 결과 | 다른 pane 화면 내용에 secrets 포함 가능 | scope 최소화 권장 (`-S -10` ~ `-S -300`) + scrubbing은 호출자 책임 |
| `osascript` (macOS OPT-IN) | AppleScript injection | argv 패턴(string interpolation 금지) + AI_OPEN_TERMINAL=1 명시 opt-in |

## 신고 채널

**공개 GitHub issue로 보고하지 마세요.** 대신:

1. **GitHub Security Advisory**: `https://github.com/hypark5540/ai-bridge/security/advisories/new` (preferred)
2. 또는 이메일: maintainer 프로필의 공개 contact

신고 시 포함:
- 영향 받는 버전 (`./ai-bridge.sh --version`)
- 재현 단계 (가능하면 minimal PoC)
- 영향 범위 추정 (local exec / 정보 유출 / 권한 상승 등)

## 응답 SLA

- **acknowledge**: 7일 이내
- **fix or workaround**: 30일 이내 (심각도 별 조정)
- **public disclosure**: fix 배포 후 또는 신고자와 합의 후

## 지원 버전

`v0.1.x` (초기 릴리스) — 머지된 main만 보안 fix 백포트. tag 받은 release는 별도 지원 안내 추가 예정.

## 비고

- 이 도구는 production-grade compliance 도구가 아닙니다. 비밀번호/PII/실 운영 시크릿은 bridge 파일에 절대 쓰지 마세요.
- AI CLI 자체의 보안(Claude Code / Codex CLI 등)은 각 벤더 정책 따름.
