# AGENTS.md

Guidance for AI coding assistants working in this repository.

## Project Context

`ai-bridge` is a shell-based workflow for running two terminal AI CLIs side by side
with a shared markdown bridge file. Keep changes portable across macOS/Linux where
possible, and preserve macOS `/bin/bash` 3.2 compatibility.

Primary files:

- `ai-bridge.sh`: core bridge orchestration.
- `claude-bridge.sh.example` / `codex-bridge.sh.example`: public wrapper templates.
- `install.sh`: local installer/bootstrapper.
- `tests/smoke.sh`: main regression suite.

## Commands

Before finishing code changes, run:

```bash
bash tests/smoke.sh
bash -n ai-bridge.sh install.sh claude-bridge.sh.example codex-bridge.sh.example tests/smoke.sh
```

If available, also run:

```bash
shellcheck *.sh tests/*.sh
```

## Bridge Review Behavior

When the user asks for Claude review, Claude validation, Claude cross-check, or uses
wording like "Claude한테 리뷰", "Claude한테도 리뷰좀", "Claude랑 리뷰해줘",
treat it as a pingpong meeting seed, not a one-shot handoff.

1. Summarize the current work/review context into one bridge entry.
2. Append it to the active bridge file. Prefer `$AI_BRIDGE_FILE` when set.
3. Include this marker near the top of the body:

   ```markdown
   [PINGPONG MEETING — round 1/5]
   ```

4. End the entry with:

   ```markdown
   ## Score
   | Dimension     | Score       | Note |
   |---------------|-------------|------|
   | Correctness   | x/10 or N/A |      |
   | Safety        | x/10 or N/A |      |
   | Verification  | x/10 or N/A |      |
   | Design Fit    | x/10 or N/A |      |
   | Clarity       | x/10 or N/A |      |
   | Reversibility | x/10 or N/A |      |

   ---
   **Score:** <average of non-N/A dimensions, 0-10>
   **Confidence:** <0-100>
   **Conclusion:** <one-line current conclusion or review ask>
   ```

5. Tell the user only that the pingpong meeting request was written. Do not ask the
   user to type "bridge 확인" in the Claude window.

If the user explicitly asks for simple sharing only, such as "전달만", "공유만",
or "리뷰 말고 전달만", append a normal bridge entry without the meeting marker.
Still do not ask the user to manually type bridge commands unless they request
manual operation guidance.

## Pingpong Meeting Rules

When a message contains `[PINGPONG MEETING — round N/5]` or
`[AI 회의 — 라운드 N/5]`, the response is text-only:

- Do not edit files, run shell commands, or perform external writes during the meeting.
- Give review/decision input only.
- Include file paths and short line references when useful; do not dump full files.
- If user approval or a product decision is needed, say:
  `USER DECISION NEEDED: <reason>`.
- End every meeting response with:

  ```markdown
  ## Score
  | Dimension     | Score       | Note |
  |---------------|-------------|------|
  | Correctness   | x/10 or N/A |      |
  | Safety        | x/10 or N/A |      |
  | Verification  | x/10 or N/A |      |
  | Design Fit    | x/10 or N/A |      |
  | Clarity       | x/10 or N/A |      |
  | Reversibility | x/10 or N/A |      |

  ---
  **Score:** <average of non-N/A dimensions, 0-10>
  **Confidence:** <0-100>
  **Conclusion:** <one-line conclusion>
  ```

The meeting can stop when both sides converge at **Confidence >= 90 AND
Score >= 9.0 AND matching conclusions**, at round 5, on deadlock, or when the
user stops it.

## Score Rubric

Score each dimension 0–10, or `N/A` if irrelevant to the artifact under review.
Final `Score` = arithmetic mean of non-N/A dimensions.

- **Correctness** — logic, edge cases, spec conformance.
- **Safety** — secrets, permissions, injection, external-write risk.
- **Verification** — tests exist, reproducible, verification path is clear.
- **Design Fit** — architectural consistency, scope/YAGNI, dependency hygiene.
- **Clarity** — readability, naming, documentation; a fresh reader understands in 5 minutes.
- **Reversibility** — rollback path, blast radius, irreversibility risk.

`Score` and `Confidence` are independent:

- `Score` = quality of the artifact under review.
- `Confidence` = your own conviction in the score you just gave.

`Score 9.0 + Confidence 60` means "looks good but I haven't covered everything" —
termination condition is not met. `Score 6.0 + Confidence 95` means "definitely
not ready" — termination condition is not met either. Both numbers must clear
the bar independently.

Projects may append extra dimensions (SDK compliance, performance, API
compatibility, cost, etc.) directly under the table. Extras participate in the
mean with equal weight unless the project specifies its own weighting.

## Safety

- Never put secrets, tokens, passwords, OAuth codes, JWTs, or private env values in
  bridge entries.
- Do not turn AI output, bridge content, or tmux capture output into shell commands.
- Use `tmux load-buffer` + `tmux paste-buffer` + `tmux send-keys Enter` for multiline
  prompt transfer; do not interpolate raw user/AI text into `tmux send-keys`.
- Keep autonomous/no-approval modes out of the default workflow. The bridge is meant
  to preserve review-first and explicit approval behavior.
