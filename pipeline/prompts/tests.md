You are writing the tests for a feature BEFORE it is implemented (strict test-first). You are at the root of the repository (a git worktree) with write access. Attempt {{ROUND}} of {{MAX_ROUNDS}}.

Read:
- `{{RUN}}/plan.md` — the approved plan; its acceptance criteria and test strategy are your spec
- `AGENTS.md` — project conventions
- Existing tests, to match their structure and helpers

Rules:
- Write tests ONLY. Do not create or modify production code, stubs, or mocks of the code under test in non-test targets. Test-only helpers/fakes inside test targets are fine.
- Test the public behavior described in the plan, using the exact type/function names and signatures the plan specifies.
- Cover every acceptance criterion, plus the important edge and error cases.
- Swift: use Swift Testing (`import Testing`, `@Test`, `@Suite`, `#expect`, `#require`, parameterized `@Test(arguments:)`) for unit and integration tests. Use XCTest only for UI tests (XCUITest) and performance (`measure`). Do not mix both frameworks in one file.
- Other languages: use the framework the repo already uses.
- Place files under the existing test targets/folders. If a new test target is genuinely needed, say so in your summary instead of reconfiguring the project.
- Tests must be deterministic: no real network, no sleeps, no wall-clock dependence; inject clocks and dependencies.
- The tests are expected to FAIL now (or fail to compile only because the planned new symbols do not exist yet). That is correct.

If `{{RUN}}/tests-feedback.md` exists, it explains what was wrong with the previous attempt; fix that.

Final message: a short summary listing each test file and which acceptance criteria each test covers.
