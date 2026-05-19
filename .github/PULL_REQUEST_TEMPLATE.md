## 변경 요약

<!-- 한두 줄로 무엇을, 왜 -->

## 변경 유형

- [ ] bug fix (breaking change 아님)
- [ ] new feature (breaking change 아님)
- [ ] breaking change (기존 wrapper/env 동작 변경)
- [ ] documentation only
- [ ] CI / tooling

## 셀프 리뷰 체크리스트

### 기능
- [ ] 핵심 happy path 동작 확인 (`./claude-bridge.sh` 또는 `./codex-bridge.sh` 실제 실행)
- [ ] env 미설정 / 누락 시 합리적인 fallback 또는 명시적 에러

### 테스트
- [ ] `bash tests/smoke.sh` 전체 pass
- [ ] 새 동작에 대한 smoke 케이스 추가 (또는 기존 케이스 강화)
- [ ] regression test: 이전 PR이 잡은 case가 회귀 안 함

### 보안
- [ ] 새 입력 surface(env, argv, 파일 내용)에 regex/control-char validation
- [ ] secrets/tokens 새로 bridge 파일에 쓰지 않음
- [ ] `tmux send-keys` / `osascript` 신규 추가 시 injection 방어

### 성능
- [ ] startup 추가 비용 측정 (해당 시)
- [ ] 추가된 외부 명령 호출은 정당화

### 아키텍처
- [ ] core / wrapper / wrapper.example 동기화 확인
- [ ] 새 env var는 `AI_BRIDGE_*` prefix + README + wrapper.example 동기화

### 코드 품질
- [ ] `set -euo pipefail` 유지 (smoke.sh는 `set -uo pipefail`)
- [ ] `bash -n` × 5 파일 통과
- [ ] shellcheck (가능 시) warning 미증가
- [ ] 들여쓰기 4-space + 함수 소문자

### OSS 준비도
- [ ] CHANGELOG.md에 한 줄 추가 (breaking이면 ⚠️ 명시)
- [ ] 새 공개 API/flag → README + CONTRIBUTING 갱신
- [ ] LICENSE/SECURITY 영향 없음 확인

### 이식성
- [ ] macOS bash 3.2 호환 (associative array 사용 X)
- [ ] GNU vs BSD 차이 있는 명령(`stat`, `readlink`, `mktemp`)은 fallback 패턴
- [ ] Linux + macOS 양쪽에서 동작 확인 (CI matrix가 잡지만 로컬에서도)

### 문서 정확성
- [ ] script 안 Usage 코멘트와 README 가이드가 일치
- [ ] 새 env 기본값을 정확히 명시

### UX/에러
- [ ] 에러 메시지가 "왜" + "어떻게 고치는지"까지 안내
- [ ] 한국어/영어 일관성 (혼재해도 OK이지만 본인 의도 명확)

## 테스트 결과

```
# bash tests/smoke.sh 마지막 줄(예: "Pass: 20 / Fail: 0") 붙여넣기
```

## 관련 이슈

Fixes #
