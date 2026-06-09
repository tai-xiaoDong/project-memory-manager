---
name: project-memory-manager
description: |-
  Persistent project-level context manager for AI coding assistants — prevents hallucination and log bloat via dev-log rolling window, summary layer, auto-archiving, and experience extraction.
  TRIGGER — Activate when the user starts any coding task (code generation, refactoring, debugging, code review, commit). Also trigger when the user mentions "dev-log", "project memory", "log this change", "remember this decision".
  SKIP — Pure conversation, simple Q&A, or tasks that don't involve code file modifications.
license: Complete terms in LICENSE.txt
compatibility: Requires Claude Code CLI or VS Code extension with file system access
metadata:
  version: "1.4.0"
  author: AI-Assisted Development
allowed-tools: Read Write Edit Glob Grep Bash
---

# Project Memory Manager

A self-maintaining project memory system for AI assistants. Solves context loss, hallucination, and log bloat.

## Core Asset Structure

Maintain the following structure at the project root (or monorepo sub-package):

```text
docs/
  dev-log-summary.md       # Persistent summary (core constraints, major issues, TODOs)
  dev-log.md               # Activity log (keep only the latest 15 entries, newest first)
  dev-log-archive/         # Historical archive (split by quarter)
```

If these files are missing, **ask the user whether to initialize**. On approval, read `./templates/` files to generate the initial structure and populate the Summary's core constraints based on the user's tech stack.

---

## Rule 1: Load Memory Before Tasks (Session Cache)

Before executing any task that **produces code output**:

1. Read `docs/dev-log-summary.md`.
2. Read `docs/dev-log.md`.

**Cache policy**: Within the same session, reuse previously read content. Re-read only when:
- The user says "logs updated", "re-read dev-log", or similar
- The current task involves archiving or manual log editing

**Forbidden**: Do NOT read `dev-log-archive/` unless the user explicitly requests it.

---

## Rule 2: Update Log After Code Changes

When a code change that **modifies actual files** is completed:

1. **Append a new entry** at the top of the body (after the header line), newest first. Each entry ≤ 500 characters:

```markdown
## [YYYY-MM-DD] Short Title
- **Change**: What was modified (one sentence)
- **Deps**: Added/removed packages or modules (omit if none)
- **Gotcha**: Pitfall encountered and resolution (omit if none)
- **TODO**: Follow-up tasks (omit if none)
```

2. **Sync Summary**: If the change affects core constraints, tech stack, or introduces a permanent TODO, update `docs/dev-log-summary.md`:
   - Core constraint change → update "Core Constraints" section
   - New permanent issue → add to "Known Major Issues"
   - TODO completed → mark `[x]`, remove after 7 days
   - Audit enabled (see Rule 6) → append to change history

---

## Rule 3: Auto-Maintenance & Experience Extraction (Overflow Prevention)

After each `dev-log.md` update, count entries by scanning `## [YYYY-MM-DD]` headers:

- **≤ 15 entries**: No action needed.
- **> 15 entries**:
  1. Identify the **5 oldest entries** (at the bottom of the file).
  2. **Experience extraction (requires user confirmation)**: If any "gotcha" appears ≥ 2 times, contains `⚠️`, or has a `#promote` tag, ask the user whether to promote it to the Summary.
  3. Determine the current quarter (e.g., `2026-Q2`).
  4. Move those entries to the top of `docs/dev-log-archive/2026-Q2.md` (separated by `---`).
  5. Remove the entries from `dev-log.md`.
  6. Briefly report the archival result to the user.

---

## Rule 4: Information Layering (Prevent Misplacement)

| Information Type | Location |
|-----------------|----------|
| Long-term architectural decisions | `docs/adr/` or `docs/specs/` |
| Permanent constraints / prohibitions | `docs/dev-log-summary.md` |
| Temporary details / gotchas / recent changes | `docs/dev-log.md` |
| Resolved history | `docs/dev-log-archive/` |

When the user says "remember this decision", ask: "Is this a long-term architectural decision (→ ADR) or a short-term implementation detail (→ dev-log)?"

---

## Rule 5: Circuit Breaker

If `dev-log.md` exceeds 200 lines or 30 entries (count via `## [YYYY-MM-DD]` headers):

1. **Stop generating code**.
2. Prompt the user: "Log is too long (N entries). Recommend archiving the 10 oldest entries now. Continue?"
3. On approval, execute archival (batch of 10) and re-read the trimmed log.

---

## Rule 6: Audit Trail (Optional, Default OFF)

- **Default**: Not enabled. No `## Change History` section at the bottom of Summary.
- **Enable**: User adds `## Change History` heading to Summary, or says "enable audit trail".
- **When enabled**: Append a line on every Summary modification: `- [YYYY-MM-DD] Action Type: brief description` (action types: add constraint, remove constraint, complete TODO, promote experience, etc.).

---

## Rule 7: Monorepo Support & Priority

```text
docs/
  dev-log-summary.md       # Global constraints, cross-package rules
packages/
  auth/
    docs/
      dev-log.md           # Package-specific log
      dev-log-archive/
  api/
    docs/
      dev-log.md
```

- When working in a sub-package, read both the global Summary and the current package's `dev-log.md`.
- **On conflict, the sub-package takes precedence**; inherit from global when undefined.
- Only update the current package's `dev-log.md`; update global Summary only when the change affects the entire repo.

---

## Validation

After any log write or archival operation, run the validation script to verify consistency:

```bash
bash .claude/skills/project-memory-manager/scripts/validate.sh docs/dev-log.md
```

If the script reports issues, fix them before proceeding.
