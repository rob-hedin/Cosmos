@AGENTS.md

## Claude Code notes
- Start feature work with `/feature <description>`. The pipeline and its gates are defined in `.claude/skills/feature/SKILL.md`; models, loop limits and gates in `pipeline/config.sh`.
- Never edit test files frozen by a pipeline run (see `pipeline/scripts/test-guard.sh`).
