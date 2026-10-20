# BUSFIN 8200 problem-set AI policy: operational summary

The authoritative source is `Problem Sets AI Policy[57].pdf` in the repository root. This summary does not replace it; follow the source and the stricter interpretation if there is uncertainty.

## Substantive work and audit trail

A substantive request asks AI to check, critique, generate, revise, explain, debug, format, translate, summarize, or otherwise assist with problem-set answers, derivations, empirical design, code, interpretation, or submission. It must begin with explicit TP invocation and receive before/after Git commits plus an append-only `AI_INTERACTIONS.md` record. Problem Set 2 items are `1a`–`1e`, `2a`–`2e`, `3a`–`3e`, and `4a`–`4e`.

Administrative navigation, command explanations, clarifying an earlier answer without new work, and environment setup that does not affect problem-set substance need no TP snapshots. Routine autocomplete, spelling, grammar, or formatting suggestions need no separate entry unless deliberately requested for substantive work.

For every substantive interaction: identify the exact item; commit all non-ignored state before assistance (empty commit if needed); provide only permitted help; append the complete interaction record without altering prior entries; and commit afterward (empty if needed). Stop if any audit step fails. Closely related minor debugging or formatting may be grouped only at the student's explicit request for the same item in the same session. `AI_USAGE.md` is a separate final task based on the log and Git evidence.

## Mathematics

The student first develops the derivation. AI may check it, identify a possible error, explain why a specific step is wrong, or diagnose a specific problem in attempted work. AI may not continue, generate, rewrite, complete, replace, or directly correct the derivation; the student decides and implements corrections. After the substantive work exists, AI may improve exposition, grammar, or LaTeX formatting without changing the reasoning. Handwriting-to-LaTeX translation is permitted and logged as translation.

## Economic reasoning

The student first completes the substantive answer in the solution source. AI may then identify and explain errors, omissions, or inconsistencies, but may not generate, rewrite, or directly edit substantive reasoning. The student decides and revises. Later exposition, grammar, and LaTeX improvements may not materially change the reasoning.

## Data analysis

The empirical design must be student-authored. Before AI writes code, the repository must contain a sufficiently detailed plain-language specification or initial student code covering relevant data sources, sample restrictions, variable definitions, timing, transformations, econometric specifications, standard errors, and outputs. AI may implement, optimize, organize, run, and debug within that design and choose non-substantive programming details.

AI may not silently resolve missing economically or econometrically meaningful choices such as restrictions, timing, missing-value treatment, definitions, winsorization, regression specifications, or standard errors. It must identify the ambiguity; the student decides and updates the specification or code before implementation.

