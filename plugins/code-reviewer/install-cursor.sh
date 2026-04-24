#!/usr/bin/env bash
#
# Transforms Claude Code plugin files into Cursor-compatible format and
# installs them into a target project's .cursor/ directory.
#
# Usage: install-cursor.sh <target-project-dir>
#
# Source of truth: the Claude files in this repo (commands/, agents/, skills/, templates/).
# This script derives Cursor-compatible versions from them — no manual
# cursor/ mirror directory is needed.
#
# Idempotent: safe to re-run at any time. Overwrites previously installed
# files with identical output; does not touch files it didn't create.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 1 ]]; then
    cat <<'USAGE'
Usage: install-cursor.sh <target-project-dir>

Installs code-reviewer plugin files into a Cursor project by transforming
the Claude Code source files into Cursor-compatible format.

Example:
  ./install-cursor.sh ~/projects/my-app
USAGE
    exit 1
fi

if [[ ! -d "$1" ]]; then
    echo "Error: '$1' is not a directory."
    exit 1
fi

TARGET="$(cd "$1" && pwd)"

if [[ ! -f "$SCRIPT_DIR/commands/review.md" ]]; then
    echo "Error: Cannot find plugin source files. Ensure this script is in the code-reviewer plugin directory alongside commands/, agents/, skills/, and templates/."
    exit 1
fi

if [[ "$TARGET" == "$SCRIPT_DIR" ]]; then
    echo "Error: Cannot install into the plugin repo itself."
    echo "Specify a target project directory."
    exit 1
fi

echo "Installing code-reviewer for Cursor into: $TARGET"
echo ""

# Create directory structure
mkdir -p "$TARGET/.cursor/rules"
mkdir -p "$TARGET/.cursor/code-reviewer/agents"
mkdir -p "$TARGET/.cursor/code-reviewer/skills/triage"
mkdir -p "$TARGET/.cursor/code-reviewer/skills/consolidation"
mkdir -p "$TARGET/.cursor/code-reviewer/skills/doc-update"
mkdir -p "$TARGET/.cursor/code-reviewer/templates"

# ============================================================
# Templates — straight copy (identical between Claude/Cursor)
# ============================================================

cp "$SCRIPT_DIR/templates/review-brief.md" "$TARGET/.cursor/code-reviewer/templates/"
cp "$SCRIPT_DIR/templates/phase-report.md" "$TARGET/.cursor/code-reviewer/templates/"

echo "  templates/review-brief.md  →  .cursor/code-reviewer/templates/"
echo "  templates/phase-report.md  →  .cursor/code-reviewer/templates/"

# ============================================================
# Agents — strip Claude-specific frontmatter, adjust tool refs
# ============================================================

install_agent() {
    local name="$1"
    local src="$SCRIPT_DIR/agents/${name}.md"
    local dst="$TARGET/.cursor/code-reviewer/agents/${name}.md"

    local desc
    desc=$(awk '
        /^description:/ { found=1; next }
        found && /^  [A-Z]/ { sub(/^  /, ""); print; exit }
    ' "$src")

    {
        printf '%s\n' "---"
        printf '%s\n' "description: >-"
        printf '%s\n' "  ${desc}"
        printf '%s\n' "---"

        awk '
            BEGIN { fm=0; body=0 }
            !body && /^---$/ { fm++; if (fm == 2) body=1; next }
            !body { next }
            { print }
        ' "$src"
    } | sed \
        's/only `git log`, `git diff`, `git show`, `cat`, `grep`, etc\./only `git log`, `git diff`, `git show`, read and search operations/' \
      > "$dst"

    echo "  agents/${name}.md  →  .cursor/code-reviewer/agents/"
}

for agent in adversarial-reviewer style-reviewer testing-reviewer; do
    install_agent "$agent"
done

# ============================================================
# Skills — path substitutions, template path updates
# ============================================================
# Only the three orchestration skills are needed in Cursor.
# The phase-specific review skills (adversarial-review, style-review,
# testing-review) are not installed because Cursor dispatches agents
# via the Task tool using the agent .md files directly.

install_skill() {
    local name="$1"
    local src="$SCRIPT_DIR/skills/${name}/SKILL.md"
    local dst="$TARGET/.cursor/code-reviewer/skills/${name}/SKILL.md"

    sed \
        -e 's|\.claude/|.cursor/|g' \
        -e 's|`templates/review-brief\.md`|`.cursor/code-reviewer/templates/review-brief.md`|g' \
        -e 's|`templates/phase-report\.md`|`.cursor/code-reviewer/templates/phase-report.md`|g' \
        -e 's|`/code-reviewer:review` or `/code-reviewer:review:\*`|`/code-reviewer:review` or phase-specific review|' \
        -e 's|`/code-reviewer:review:style` separately|`/code-reviewer:review:style` separately|' \
        "$src" > "$dst"

    echo "  skills/${name}/SKILL.md  →  .cursor/code-reviewer/skills/${name}/"
}

for skill in triage consolidation doc-update; do
    install_skill "$skill"
done

# ============================================================
# Review rule — commands/review.md → .cursor/rules/
#
# Transforms:
#   - Frontmatter: Claude command metadata → Cursor rule metadata
#   - Step 0: add natural-language triggers
#   - Step 3: Agent tool dispatch → Task tool dispatch
#   - Paths: .claude/ → .cursor/
#   - Wording: "invoke skill" → "follow skill"
# ============================================================

install_review_rule() {
    local src="$SCRIPT_DIR/commands/review.md"
    local dst="$TARGET/.cursor/rules/code-reviewer-review.mdc"

    {
        cat <<'FRONTMATTER'
---
description: "Activated when the user says /code-reviewer:review or asks to run the code review pipeline. Supports phase-specific variants: /code-reviewer:review:adversarial, /code-reviewer:review:style, /code-reviewer:review:testing."
globs:
alwaysApply: false
---
FRONTMATTER

        awk '
            BEGIN { fm=0; state="skip_fm" }

            state == "skip_fm" && /^---$/ {
                fm++
                if (fm == 2) state = "body"
                next
            }
            state == "skip_fm" { next }

            # ── Replace Step 0 ──
            state == "body" && /^## Step 0: Parse Arguments/ {
                print
                print ""
                print "Check the user'\''s message for a specific phase request:"
                print "- `/code-reviewer:review` or \"run code review\" — run all three phases"
                print "- `/code-reviewer:review:adversarial` or \"run adversarial review\" — run adversarial phase only"
                print "- `/code-reviewer:review:style` or \"run style review\" — run style phase only"
                print "- `/code-reviewer:review:testing` or \"run testing review\" — run testing phase only"
                state = "skip_step0"
                next
            }
            state == "skip_step0" && /^## Step 1:/ { state = "body"; print "" }
            state == "skip_step0" { next }

            # ── Replace Step 3 (Agent tool → Task tool) ──
            state == "body" && /^## Step 3: Dispatch Review Subagents/ {
                print
                print ""
                print "Based on the parsed argument from Step 0, dispatch review agents using the **Task tool**."
                print ""
                print "For each agent dispatch:"
                print "1. Read the agent prompt template from `.cursor/code-reviewer/agents/<agent-name>.md`"
                print "2. Combine the agent instructions with the appropriate review brief and reference doc contents"
                print "3. Call the Task tool with `subagent_type: \"generalPurpose\"` and `readonly: true`"
                print "4. Pass the combined content as the `prompt` parameter"
                print ""
                print "**If all phases (default):**"
                print "Launch all three Task calls **in a single message** for parallel execution:"
                print "- **adversarial-reviewer**: prompt = agent instructions + full-scope brief + all reference doc contents"
                print "- **style-reviewer**: prompt = agent instructions + unit-scoped brief + style guide content"
                print "- **testing-reviewer**: prompt = agent instructions + unit-scoped brief + testing practices content"
                print ""
                print "For multiple review units, dispatch one style-reviewer and one testing-reviewer **per unit**, all in parallel alongside the single adversarial-reviewer."
                print ""
                print "**If `/code-reviewer:review:adversarial`:**"
                print "Dispatch only the adversarial-reviewer with the full-scope brief."
                print ""
                print "**If `/code-reviewer:review:style`:**"
                print "For each review unit, dispatch the style-reviewer with the unit-scoped brief."
                print ""
                print "**If `/code-reviewer:review:testing`:**"
                print "For each review unit, dispatch the testing-reviewer with the unit-scoped brief."
                state = "skip_step3"
                next
            }
            state == "skip_step3" && /^## Step 4:/ { state = "body"; print "" }
            state == "skip_step3" { next }

            state == "body" { print }
        ' "$src"
    } | sed \
        -e 's|\.claude/|.cursor/|g' \
        -e 's|Invoke the \([a-z-]*\) skill|Read and follow the \1 skill (`.cursor/code-reviewer/skills/\1/SKILL.md`)|g' \
        -e 's|invoke the \([a-z-]*\) skill|read and follow the \1 skill (`.cursor/code-reviewer/skills/\1/SKILL.md`)|g' \
        -e 's|re-run `/code-reviewer:review` to verify|re-run `/code-reviewer:review` to verify|' \
      > "$dst"

    echo "  commands/review.md  →  .cursor/rules/code-reviewer-review.mdc"
}

install_review_rule

# ============================================================
# Setup rule — commands/setup.md → .cursor/rules/
#
# Transforms:
#   - Frontmatter: Claude command metadata → Cursor rule metadata
#   - Discovery: add .cursor/rules/ to scanned locations
#   - Paths: .claude/ → .cursor/
# ============================================================

install_setup_rule() {
    local src="$SCRIPT_DIR/commands/setup.md"
    local dst="$TARGET/.cursor/rules/code-reviewer-setup.mdc"

    {
        cat <<'FRONTMATTER'
---
description: "Activated when the user says /code-reviewer:setup or asks to onboard a project for code review"
globs:
alwaysApply: false
---
FRONTMATTER

        awk '
            BEGIN { fm=0; body=0 }
            !body && /^---$/ { fm++; if (fm == 2) body=1; next }
            !body { next }

            # Add .cursor/rules/ to the discovery list
            /^- `.editorconfig`/ {
                print
                print "- `.cursor/rules/` — Cursor rule files"
                next
            }
            { print }
        ' "$src"
    } | sed \
        -e 's|\.claude/|.cursor/|g' \
        -e 's|run `/code-reviewer:review` to review|run `/code-reviewer:review` to review|' \
      > "$dst"

    echo "  commands/setup.md  →  .cursor/rules/code-reviewer-setup.mdc"
}

install_setup_rule

# ============================================================
# Summary
# ============================================================

echo ""
echo "Installation complete. Installed files:"
echo ""
echo "  .cursor/rules/"
echo "    code-reviewer-review.mdc   (review pipeline orchestration)"
echo "    code-reviewer-setup.mdc    (project onboarding)"
echo ""
echo "  .cursor/code-reviewer/"
echo "    agents/                    (review subagent prompt templates)"
echo "    skills/                    (triage, consolidation, doc-update)"
echo "    templates/                 (review-brief, phase-report)"
echo ""
echo "Next steps:"
echo "  1. Open the project in Cursor"
echo "  2. Run /code-reviewer:setup to onboard your project"
echo "  3. Run /code-reviewer:review to review your changes"
