---
name: headless-setup
description: Non-interactive project onboarding for CI environments. Delegates to the setup command logic but auto-accepts all conventions without engineer confirmation.
---

# Headless Setup — Non-Interactive Project Onboarding

## Purpose

Generate project reference docs autonomously for CI. This is the setup command (`commands/setup.md`) running in non-interactive mode.

## When to Use

- **DO:** Use when `/code-reviewer:ci-review` detects that `.claude/code-reviewer/reference/` does not exist or contains no `.md` files
- **DO NOT:** Use in interactive sessions — use `/code-reviewer:setup` instead

## Workflow

Follow the same process as `commands/setup.md` with these overrides:

- **Skip Step 0** — Do not ask "Refresh or Start fresh?". Always generate fresh.
- **Run Step 1 (Discovery)** — Identical to the setup command. No changes.
- **Run Step 2 (Draft Generation)** — Identical to the setup command. No changes.
- **Skip Step 3 (Interactive Confirmation)** — Auto-accept all discovered conventions. Generate all applicable docs. Do not prompt.
- **Modify Step 4 (Write & Store)** — Write all generated docs and config. Skip the `.gitignore` prompt.

## Critical Rules

- **Never prompt the user.** Every decision is automatic.
- **Generate all applicable docs.** Unlike interactive setup, do not skip docs — generate everything that has content. Exception: skip security posture and API conventions docs if there is no clear evidence of security-sensitive code or API definitions.
- All other rules from `commands/setup.md` (no duplication, reference doc structure, changelog format) still apply.
