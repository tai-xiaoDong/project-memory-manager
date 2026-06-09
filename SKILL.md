---
name: project-memory-manager
description: |-
  Persistent project-level context manager for AI coding assistants — prevents hallucination and log bloat via dev-log rolling window, summary layer, auto-archiving, and experience extraction.
  TRIGGER — Activate when the user starts any coding task (code generation, refactoring, debugging, code review, commit). Also trigger when the user mentions "dev-log", "project memory", "log this change", "remember this decision", or "uninstall project memory".
  SKIP — Pure conversation, simple Q&A, or tasks that don't involve code file modifications.
license: Complete terms in LICENSE.txt
compatibility: Requires Claude Code CLI or VS Code extension with file system access
metadata:
  version: "2.0.0"
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
  dev-log/                  # Daily log files (one file per date, conflict-free for multi-person)
    2026-06-09.md           # Append entries to end of file (Git auto-merges tail appends)
    2026-06-08.md
  dev-log-archive/          # Historical archive (split by quarter)
    2026-Q2/                # Archived daily files moved here
```

If these files are missing, **ask the user whether to initialize**. On approval, execute the following steps **in order**:

### Init Step 1: Create File Structure

Read `./templates/` files to generate the initial structure and populate the Summary's core constraints based on the user's tech stack.

Ask the user to confirm or customize the experience extraction threshold: **"The default gotcha promotion threshold is 3 (a gotcha must appear ≥ 3 times before being suggested for promotion to Summary). Keep the default, or set a custom value?"** Store the chosen value in the Summary file as a comment: `<!-- promotion-threshold: N -->`.

### Init Step 2: Deploy Validation Script to Project Root

Copy `scripts/validate.sh` to `scripts/validate.sh` at the project root (create the `scripts/` directory if needed). This ensures all AI tools can find the script via a **tool-agnostic, project-relative path**.

### Init Step 3: Inject Rules into AI Rule Files

Ask the user: **"Which AI coding tools does your team use?"** Options:

| Tool | Rule File |
|------|-----------|
| Claude Code | `CLAUDE.md` |
| Cursor | `.cursorrules` |
| Continue | `.continue.rules` |
| GitHub Copilot | `AGENTS.md` |

For each selected tool, **append** the rule block below to the corresponding file (create if not exists). Place it at the **end** of the file, wrapped by comment delimiters for clean removal on uninstall. The injected block is a **concise reference** — the full behavioral rules are defined in Rules 1–7 of this SKILL.md and should be followed in their entirety.

```markdown
<!-- project-memory-manager BEGIN -->
## Project Memory (project-memory-manager)
**For code tasks only (skip Q&A):**
1. **Before**: read `docs/dev-log-summary.md` + 5 newest `docs/dev-log/*.md`. (If missing, ask to init before coding.)
2. **After**: append ONE entry to `docs/dev-log/YYYY-MM-DD.md` (≤500 chars). **MUST run** `date` & `git config user.name` via Bash.
3. **Sync**: If constraints/stack changed → update Summary.
4. **Maintain**: If >15 files → archive oldest 5. If >30 files → **finish current code safely**, then warn.
5. **Validate**: Run `bash scripts/validate.sh docs/dev-log/` after writes.
*Full logic: Read project-memory-manager SKILL.md Rules 1-8 when needed.*
<!-- project-memory-manager END -->
```

**IMPORTANT**:
- Confirm with the user before appending, showing the content and target file(s).
- On uninstall, remove everything between `<!-- project-memory-manager BEGIN -->` and `<!-- project-memory-manager END -->` markers (inclusive) from all injected files, and remove the copied `scripts/validate.sh`.

---

## Rule 1: Load Memory Before Tasks (Session Cache)

Before executing any task that **produces code output**:

1. **Cold start check**: If `docs/dev-log/` does not exist or is empty, ask the user whether to initialize the memory system. If declined, proceed without memory context.
2. Read `docs/dev-log-summary.md`.
3. List `docs/dev-log/` and read the **5 most recent** `YYYY-MM-DD.md` files (sorted by date descending). Reading more than 5 files wastes tokens; rely on the Summary for older context. If the directory has fewer than 5 files, read all of them.

**Cache policy**: Within the same session, reuse previously read content. Re-read only when:
- The user says "logs updated", "re-read dev-log", or similar
- The current task involves archiving or manual log editing

**Forbidden**: Do NOT read `dev-log-archive/` unless the user explicitly requests it.

---

## Rule 2: Update Log After Task Completion (Task-Level Granularity)

**Trigger**: Write a log entry when a **logical task** is completed — NOT after every individual file edit. A task boundary is:
- The user says "done", "commit", or reports completion
- You finish a multi-step change and report the result to the user
- The user explicitly asks "log this change"

During the task, **silently track** modified files in memory. At task completion:

1. **Get the real system time**: Execute `date +%Y-%m-%d` and `date +%H:%M` via Bash. On native Windows without bash, use PowerShell: `Get-Date -Format 'yyyy-MM-dd'` and `Get-Date -Format 'HH:mm'`. **Never guess the current date or time — AI models have no reliable internal clock.**
2. **Get author name**: Execute `git config user.name`. If this fails (non-git project), use the value `unknown`.
3. **Write one consolidated entry** covering the entire task, ≤ 500 characters:

```markdown
### [HH:MM] Short Title @author
- **Change**: Concise summary of the entire task (what and why, not every file touched)
- **Deps**: Added/removed packages or modules (omit if none)
- **Gotcha**: Pitfall encountered and resolution (omit if none)
- **TODO**: Follow-up tasks (omit if none)
```

   - Separate entries with a blank line.
   - Entries within the same daily file are ordered chronologically (oldest at top, newest at bottom).

4. **Sync Summary**: If the change affects core constraints, tech stack, or introduces a permanent TODO, update `docs/dev-log-summary.md`:
   - Core constraint change → update "Core Constraints" section
   - New permanent issue → add to "Known Major Issues"
   - TODO completed → mark `[x]`, remove after 7 days
   - Audit enabled (see Rule 6) → append to change history

---

## Rule 3: Auto-Maintenance & Experience Extraction (Overflow Prevention)

After each log update, count the number of `.md` files in `docs/dev-log/`:

- **≤ 15 daily files**: No action needed.
- **> 15 daily files** (meaning > 10 files beyond the 5-file read window):
  1. Identify the **5 oldest daily files** (sorted by filename).
  2. **Experience extraction (batch confirmation)**: Scan those files for "gotcha" entries. Consider two gotchas as the same if they describe the same root cause (semantic matching, not exact text match). If any gotcha appears ≥ N times across files (N = promotion threshold stored in Summary as `<!-- promotion-threshold: N -->`, default 3), or contains `⚠️` or a `#promote` tag, collect all candidates first, then present them together as one batch: "Found N recurring gotchas. Promote to Summary?" Show all candidates and let the user approve/reject each.
  3. Determine the current quarter (e.g., `2026-Q2`).
  4. Move those daily files to `docs/dev-log-archive/2026-Q2/`.
  5. Briefly report the archival result to the user.

---

## Rule 4: Information Layering (Prevent Misplacement)

| Information Type | Location |
|-----------------|----------|
| Long-term architectural decisions | `docs/adr/` or `docs/specs/` |
| Permanent constraints / prohibitions | `docs/dev-log-summary.md` |
| Temporary details / gotchas / recent changes | `docs/dev-log/` (daily files) |
| Resolved history | `docs/dev-log-archive/` |

When the user says "remember this decision", ask: "Is this a long-term architectural decision (→ ADR) or a short-term implementation detail (→ dev-log)?"

---

## Rule 5: Circuit Breaker

If today's `docs/dev-log/YYYY-MM-DD.md` exceeds 200 lines, warn the user and suggest splitting or archiving. If the total number of daily files in `docs/dev-log/` exceeds 30:

1. **Do NOT interrupt ongoing code generation** — always complete the current file modification safely.
2. Before reporting task completion, halt and prompt the user: "Too many daily log files (N files). Recommend archiving the 10 oldest files now. Continue?"
3. On approval, execute archival (batch of 10 files) and re-list the directory.

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
      dev-log/             # Package-specific daily logs
      dev-log-archive/
  api/
    docs/
      dev-log/
```

- **Initialization in monorepo**: Initialize the global `docs/dev-log-summary.md` and `docs/dev-log/` at the repo root only. Each sub-package's `dev-log/` is created on first use when the user works within that package.
- When working in a sub-package, read both the global Summary and the current package's daily logs in `dev-log/`.
- **Priority**: Global Summary (`docs/dev-log-summary.md`) is the **authoritative hard constraint** layer (e.g., "do not use X library"). Sub-package logs only provide **additional context** specific to that package.
- **On conflict**: If a sub-package log contradicts a global Summary constraint, **warn the user** and follow the global Summary. Sub-package precedence applies only to implementation details (e.g., preferred patterns, local gotchas), never to hard constraints.
- Only update the current package's `dev-log/` daily files; update global Summary only when the change affects the entire repo.

---

## Rule 8: Uninstall

When the user says "uninstall project memory" or "remove project memory manager":

1. Remove everything between `<!-- project-memory-manager BEGIN -->` and `<!-- project-memory-manager END -->` markers (inclusive) from all injected rule files (`CLAUDE.md`, `.cursorrules`, `.continue.rules`, `AGENTS.md`, etc.).
2. Remove the deployed `scripts/validate.sh` from the project root.
3. **Do NOT delete** `docs/dev-log/`, `docs/dev-log-summary.md`, or `docs/dev-log-archive/` — these contain the user's data. Ask the user separately whether to remove them.

---

## Validation

After any log write or archival operation, run the validation script to verify consistency:

```bash
bash scripts/validate.sh docs/dev-log/
```

If bash is unavailable (e.g., native Windows without Git Bash), use Glob and Read tools to manually verify: (1) filenames match `YYYY-MM-DD.md` pattern, (2) each file has `### [HH:MM]` headers with `**Change**` fields, (3) no single file exceeds 200 lines.

If the script reports issues, fix them before proceeding.
