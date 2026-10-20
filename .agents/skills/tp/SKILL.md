---
name: tp
description: "Trace a BUSFIN 8200 problem-set AI interaction with before/after Git snapshots, append-only logging, and policy checks. Use only when explicitly invoked as @TP or $tp at the beginning of a substantive request in this repository."
---

# Traceable Prompt

Use this skill only after explicit invocation. Before acting, read [references/course-ai-policy.md](references/course-ai-policy.md). The authoritative source is `Problem Sets AI Policy[57].pdf` at the repository root; if it differs from the summary, follow the source and the stricter interpretation.

## Preflight

1. Confirm this is a Git repository containing the policy PDF and `AI_INTERACTIONS.md`.
2. Identify the exact Problem Set 2 subitem (`1a` through `4e`). If unclear, ask the user before substantive work or a snapshot.
3. Read only enough student work to determine whether the request is permitted and whether the required student-authored derivation, answer, or empirical specification exists.
4. A disallowed request is still audited: create the before snapshot, decline it, log the interaction, and create the after snapshot.

## Before snapshot

Inspect `git status --short --branch`. Stop for a merge, rebase, cherry-pick, revert, detached HEAD, unresolved conflict, likely secret, or clearly unrelated material that `git add -A` would capture. Do not silently omit files.

From the repository root, run:

```bash
.agents/skills/tp/scripts/snapshot.sh before "<item>"
```

Record the full hash printed. The script creates a commit even when there are no changes. If any commit, hook, signing, identity, permission, or hash step fails, stop; do not bypass hooks, disable signing, amend, squash, reset, or push. Create only one before snapshot. If waiting for a student decision, resume from it.

## Policy boundaries

- Mathematics: check or diagnose the student's existing derivation. Never generate, continue, complete, rewrite, replace, or directly correct it. The student implements corrections.
- Economic reasoning: critique only a complete student answer already in the solution source. Never generate, rewrite, or directly edit its substance. The student makes revisions.
- Data analysis: before writing code, verify that the repository contains a sufficiently detailed student-authored specification or initial code. Implement, optimize, integrate, run, and debug only within that design. Mechanical programming choices are allowed.
- Do not decide missing mathematical, economic, empirical, or econometric choices. Name the ambiguity and ask the student to decide. For empirical work, require the student to update the specification or initial code before implementation.
- Improve formatting, grammar, exposition, or translate handwriting to LaTeX only after the substantive student work exists, without materially changing its reasoning.

Track contemporaneously: every substantive prompt and clarification verbatim; purpose; all repository files inspected and directly modified; identified errors, omissions, and ambiguities and their resolution; every substantive suggestion; and all applicable assistance categories. Include material delegated-agent work. Do not infer unsupported authorship, intent, reasoning, or understanding.

## Grouping

Do not group by default. Group only at the user's explicit request when minor debugging or formatting follow-ups concern the same exact item in the same work session. If requested before close, delay the log and after snapshot. If already closed, allow a continuation only when it is the last logical log entry with no intervening substantive interaction; append a labeled continuation without changing prior bytes, use the preceding after hash for verification, then create a new after snapshot. Otherwise start a new interaction.

## Append-only log

Append one entry to the physical end of `AI_INTERACTIONS.md`; never change, delete, reorder, combine, or reformat existing bytes. Correct an error with a new appended correction. Use `None` for empty fields and a fence longer than any backtick run in the prompt:

````markdown
## TP interaction `<item>-<before-hash-prefix>` — `<timestamp with timezone>`

- **Problem set item:** `<exact item>`
- **Substantive prompt (verbatim):**

  ```text
  <prompt after TP invocation>
  ```

- **Purpose:** `<purpose>`
- **Git commit before interaction:** `<full hash>`
- **Assistance provided:** `<complete factual description, including refusals>`
- **Files inspected:** `<repository-relative list or None>`
- **Files directly modified:** `<list including AI_INTERACTIONS.md or None>`
- **Errors, omissions, or ambiguities identified:** `<details and resolution or None>`
- **Substantive mathematical, economic, or empirical suggestions:** `<details or None>`
- **Type of assistance:** `<checking mathematics; checking economic reasoning; empirical implementation; code debugging; formatting/translation; other>`
- **Grouped minor subsequent requests:** `<No as of initial close, or the grouped prompts and assistance>`
````

Add each clarification or decision as a separate labeled verbatim block. Then run:

```bash
.agents/skills/tp/scripts/verify_log_append_only.sh "<full-before-hash>"
```

Use the preceding after hash for a valid later continuation. If verification fails, stop and repair the record without substantive work.

## After snapshot

Run:

```bash
.agents/skills/tp/scripts/snapshot.sh after "<item>"
```

This must include the appended log and all in-scope work and must succeed even if otherwise empty. Conclude with the item, full before and after hashes, log identifier, modified files, unresolved ambiguity, and whether grouped follow-ups were included.

