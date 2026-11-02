---
name: feature
description: Run the plan → Codex review → approval → Codex tests → implement → Codex review pipeline for a feature in its own git worktree. Use when the developer types /feature <description>.
disable-model-invocation: true
argument-hint: <what you want built>
---

# Feature pipeline

Request: $ARGUMENTS

You are the orchestrator. You do not plan, write tests or write code yourself — you run the steps, check results, enforce the gates and loops, and keep the developer informed in short lines. Read `pipeline/config.sh` first and honor its values (`MAX_ROUNDS`, `GATE_*`, `OPEN_PR`, `PR_DRAFT`).

Conventions:
- `REPO` = main repo root (current directory). `S` = `$REPO/pipeline/scripts`.
- Run every `codex.sh` and `test.sh` call with the Bash tool's `run_in_background` option and wait for it to finish — Codex at high effort and xcodebuild can exceed normal timeouts.
- Create a task list with one item per step below and tick them off.
- "Escalate" = stop and ask the developer with AskUserQuestion, showing the unresolved points (short), with options to continue another round, accept as-is, give direction, or abort.

## 0. Setup
1. If the request is empty or too vague to plan, ask one clarifying question first.
2. Pick a short kebab-case slug. Run `$S/worktree.sh <slug>`; the last line is `WT`. `RUN` = `$WT/.pipeline/<slug>`.
3. Write the request verbatim (plus any clarifications) to `$RUN/request.md`.

## 1–3. Plan and plan review (loop, max MAX_ROUNDS)
For round r = 1..MAX_ROUNDS:
1. Launch the `planner` agent: worktree `WT`, run folder `RUN`. Round 1: "write the plan". Later rounds: "revise the plan to address `$RUN/plan-review-r<r-1>.md`".
2. Run `$S/codex.sh plan-review "$WT" <r>`.
3. `VERDICT: APPROVE` → leave the loop. `REVISE` → next round.
After the last round still `REVISE` → escalate. A "continue" answer grants one more round.

## 4. Gate: plan approval (GATE_PLAN_APPROVAL)
Show: goal, acceptance criteria, files to change, any points the planner and reviewer agreed to disagree on, and the path to `plan.md`. Ask: Approve / Request changes / Abort.
- Request changes → write the developer's notes into `$RUN/request.md` under "Developer feedback", go back to step 1–3 with a fresh round count.
- Abort → leave the worktree, report its path, stop.

## 5. Tests first (red) (loop, max MAX_ROUNDS)
For attempt a = 1..MAX_ROUNDS:
1. Run `$S/codex.sh tests "$WT" <a>`.
2. Run `$S/test.sh "$WT"`. The run MUST fail.
3. Read the log and classify:
   - **Valid red**: failures (or compile errors) come only from the new tests / the new symbols named in the plan → leave the loop.
   - **Invalid**: tests pass (they don't test new behavior), unrelated existing tests break, production code was changed, or acceptance criteria are uncovered → write the reason to `$RUN/tests-feedback.md`, discard Codex's changes outside test paths (`git -C "$WT" checkout -- <files>`), retry.
After MAX_ROUNDS invalid attempts → escalate.
4. Freeze: `$S/test-guard.sh record "$WT"`.
5. If GATE_AFTER_TESTS → show the test list and coverage summary; ask Continue / Request changes / Abort.

## 6. Implement (green)
1. Launch the `implementer` agent: worktree `WT`, run folder `RUN`, scripts `S`, task "implement".
2. If it reports BLOCKED (e.g. believes a test is wrong) → escalate with its reason.
3. Verify yourself: `$S/test-guard.sh check "$WT"` passes and `$S/test.sh "$WT"` exits 0. If the guard fails, revert the test changes (`git -C "$WT" checkout <TESTS_SHA> -- <files>`) and send the implementer back once; if it happens again → escalate.

## 7. Code review (loop, max MAX_ROUNDS)
For round r = 1..MAX_ROUNDS:
1. Run `$S/codex.sh code-review "$WT" <r>`.
2. `APPROVE` → leave the loop.
3. `REVISE` → launch `implementer` with "address `$RUN/code-review-r<r>.md`", then re-verify as in 6.3.
After the last round still `REVISE` → escalate.

## 8. Finish
1. If GATE_BEFORE_PR → show `git -C "$WT" diff --stat <BASE_SHA>...HEAD` and ask to continue.
2. If OPEN_PR: `git -C "$WT" push -u origin <BRANCH>`, then `gh pr create` from `$WT` (add `--draft` if PR_DRAFT) with title from the goal and a body containing: goal, acceptance criteria, test summary, review rounds used (plan / tests / code), and remaining "Should consider" items.
3. Report in a few lines: PR link (or branch), worktree path, rounds used per loop, anything escalated or not applied.
Remove the worktree only if the developer asks (`git worktree remove "$WT"`).
