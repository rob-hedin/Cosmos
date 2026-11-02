# Project conventions

Shared by Claude Code (via CLAUDE.md) and Codex. Edit per project.

## Project
- Platforms: macOS 27.0, iOS 27.0
- Language: Swift 6.4, strict concurrency on
- Build: `pipeline/scripts/test.sh <worktree>` (settings in `pipeline/config.sh`)

## Workflow
- Feature work goes through `/feature` in its own git worktree under `.worktrees/<slug>`.
- Strict test-first: tests are written and committed failing before implementation, then frozen. Implementation never edits them.
- Run artifacts (plan, reviews, logs) live in `.pipeline/<slug>/` (git-ignored).

## Testing
- Swift Testing (`import Testing`, `@Test`, `@Suite`, `#expect`, `#require`) for unit and integration tests.
- XCTest only for UI tests (XCUITest) and performance tests (`measure`). Never mix frameworks in one file.
- Deterministic tests: inject clocks, network and file system; no sleeps.
- Prefer parameterized tests (`@Test(arguments:)`) over copy-pasted cases.

## Code style
- Prefer value types; actors for shared mutable state; `@MainActor` for UI.
- No force-unwraps or `try!` outside tests.
- Public API gets doc comments.
