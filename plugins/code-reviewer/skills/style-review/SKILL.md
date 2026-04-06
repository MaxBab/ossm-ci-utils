---
name: style-review
description: Use when performing style review — enforces project conventions from the generated style guide. Only flags violations of documented rules, not personal preferences.
---

# Style Review

## Purpose

Check the code change against the project's documented style conventions. This is the "does this follow our conventions?" pass.

## When to Use

- **DO:** Use when dispatched by the `/code-reviewer:review` or `/code-reviewer:review:style` command
- **DO NOT:** Use for correctness, security, or test coverage — those have dedicated phases

## Input

You receive:
- A **unit-scoped review brief** for the specific review unit you're checking
- The project's **style guide** reference doc from `.claude/code-reviewer/reference/style-guide.md`

## Review Focus

### Documented Conventions Only
- Check **only** rules documented in the style guide
- If you spot something that should be a rule but isn't documented, note it as a **Recommendation**, not an Issue
- Reference the specific section of the style guide when flagging: e.g., "Per style-guide.md §Imports: imports should be grouped as stdlib / third-party / internal"

### What to Check
- Naming conventions (variables, functions, files, types)
- Import ordering and grouping
- Code formatting patterns (that linters wouldn't catch)
- File organization and module structure
- Language-specific idioms documented in the style guide
- Comment and documentation conventions

### What NOT to Check
- Correctness or logic (adversarial reviewer's job)
- Test coverage (testing reviewer's job)
- Personal style preferences not in the style guide
- Things linters/formatters already enforce (unless the style guide explicitly says to check them)

## Output

Use the `templates/phase-report.md` format. Tag your phase as `[style]` in each finding.

## Critical Rules

- **Only enforce documented rules.** The style guide is your authority. If it's not in there, it's not a violation.
- **Reference the rule.** Every style finding must cite the relevant section of the style guide.
- **Severity is usually Minor.** Style issues are rarely Critical. Use Important only for egregious, widespread violations. Use Critical only if a style violation causes a functional issue (e.g., wrong naming causes a routing mismatch).
- **Spot undocumented patterns.** If the code consistently follows a pattern not in the style guide, note it as a Recommendation for the engineer to consider documenting.
