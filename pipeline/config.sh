# Pipeline configuration — edit per project.
# Sourced by pipeline/scripts/*.sh and read by the /feature skill.

# ---- Codex (OpenAI) roles ---------------------------------------------------
# Check what your account has with:  codex models
CODEX_PLAN_REVIEW_MODEL="gpt-6-astra"     # step 3: plan review
CODEX_PLAN_REVIEW_EFFORT="medium"

CODEX_TESTS_MODEL="gpt-6-luna"            # step 5: test generation
CODEX_TESTS_EFFORT="xhigh"

CODEX_CODE_REVIEW_MODEL="gpt-6.1-sol"     # step 7: code review
CODEX_CODE_REVIEW_EFFORT="medium"

# Claude roles are set in .claude/agents/planner.md and implementer.md
# (frontmatter `model:` and `effort:`).

# ---- Loop limits ------------------------------------------------------------
MAX_ROUNDS=3              # plan review, red-test check and code review loops

# ---- Gates (true = stop and ask you) ----------------------------------------
GATE_PLAN_APPROVAL=true   # step 4, always on unless you really mean it
GATE_AFTER_TESTS=false    # review generated tests before implementation
GATE_BEFORE_PR=false      # review final diff before pushing / opening the PR

# ---- Git / GitHub -----------------------------------------------------------
BASE_BRANCH="main"
BRANCH_PREFIX="feature/"
# Inside the repo (git-ignored) so Claude Code can edit without extra directory permissions.
WORKTREE_ROOT=".worktrees"
OPEN_PR=true              # push branch and open a draft PR with gh at the end
PR_DRAFT=true

# ---- Tests ------------------------------------------------------------------
# TEST_RUNNER: auto | spm | xcode | both | custom
#   auto  -> spm if Package.swift exists, else xcode if a scheme is set
TEST_RUNNER="auto"

# xcodebuild settings (used by xcode / both)
XCODE_CONTAINER=""        # e.g. "-workspace App.xcworkspace" or "-project App.xcodeproj"
XCODE_SCHEME=""           # e.g. "App"
# One or more destinations, separated by ';'
XCODE_DESTINATIONS="platform=macOS;platform=iOS Simulator,name=iPhone 17"

# For C++, C#, Rust, JS/TS, Kotlin projects set TEST_RUNNER=custom, e.g.
#   cargo test | dotnet test | npm test | ./gradlew test | ctest --test-dir build
CUSTOM_TEST_CMD=""

# Paths that hold tests. After tests are committed these are frozen:
# the implementer may not change them (checked by test-guard.sh).
TEST_PATHSPECS=(':(glob)Tests/**' ':(glob)**/*Tests/**' ':(glob)**/*UITests/**')
