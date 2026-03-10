---
name: skill-eval
version: 1.0.0
description: |
  Evaluate an OpenClaw skill or prompt against the skill-eval methodology:
  deterministic structure checks (frontmatter, progressive disclosure, file
  layout) followed by a qualitative LLM rubric (discovery, logic, edge cases,
  architecture). Outputs a scored verdict with pass rate framing and ranked
  findings. Use when validating new skills, auditing edits for regressions, or
  comparing a skill before and after a rewrite.
  Do not use for evaluating non-skill files, Ansible playbooks, or arbitrary
  code. For Ansible, use ansible-review instead.
allowed-tools:
  - Read
  - Grep
  - Glob
---

Evaluate the skill or prompt at the path given in $ARGUMENTS against the
skill-eval two-tier methodology. If no path is provided, list all skills found
under `.claude/commands/` and `prompts/` and ask which to evaluate.

## Tier 1 — Deterministic Checks

Run every check below. Record PASS or FAIL for each. A single FAIL in a
mandatory check sets the overall verdict to FAIL.

### 1.1 Frontmatter (mandatory)

- `name` present, 1–64 chars, kebab-case, matches filename without extension
- `description` present, ≤1,024 chars, third-person, includes at least one
  negative trigger ("Do not use for…")
- `version` present in semver format
- `allowed-tools` lists only tools the skill actually uses

### 1.2 File Length (mandatory)

- Main skill file is <500 lines
- If >500 lines, identify which content should move to `references/`

### 1.3 Progressive Disclosure (mandatory)

- Bulk context (templates, long examples, schemas) lives in `references/` or
  `assets/`, not inline
- Flat subdirectory structure only — no nested subdirs (e.g. `references/db/v1/`)
- No `README.md`, `CHANGELOG.md`, or other cruft inside the skill directory

### 1.4 Instructions Style (mandatory)

- Steps use numbered sequences with explicit decision branches
- Voice is third-person imperative ("Extract the text…" not "You should…")
- One term per concept — no synonym drift

### 1.5 Argument Handling (advisory)

- `$ARGUMENTS` placeholder present if the skill accepts runtime input
- Skill degrades gracefully when `$ARGUMENTS` is empty (fallback behavior
  described)

---

## Tier 2 — Qualitative Rubric

Score each dimension 0–10. Weight and sum to produce a composite score.

| Dimension | Weight | What to assess |
|-----------|--------|----------------|
| **Discovery** | 25% | Frontmatter triggers skill on correct inputs; negative triggers prevent false matches |
| **Logic** | 30% | Steps are unambiguous; no forced guesses; decision branches cover all forks |
| **Edge Cases** | 25% | Failure states handled; missing inputs have fallbacks; error paths explicit |
| **Architecture** | 20% | Progressive disclosure enforced; references used JIT; no premature abstraction |

Composite = (Discovery × 0.25) + (Logic × 0.30) + (Edge Cases × 0.25) + (Architecture × 0.20)

---

## Output Format

### 1. Verdict

State one of:
- **PASS** — all mandatory checks pass, composite ≥ 7.0
- **PASS WITH RISKS** — all mandatory checks pass, composite 5.0–6.9
- **FAIL** — one or more mandatory checks fail, or composite < 5.0

Include pass rate framing:
- **pass@3** (can the skill solve its stated goal at least once in 3 trials?): YES / NO / UNCERTAIN
- **pass^3** (does the skill succeed every time in 3 trials?): YES / NO / UNCERTAIN

### 2. Deterministic Results

List each Tier 1 check with PASS / FAIL and a one-line note on any failure.

### 3. Rubric Scores

Show the score and rationale for each dimension. Show composite.

### 4. Top Findings

List the 5 most important issues, sorted by severity:
- **blocker** — prevents the skill from functioning
- **high** — significantly degrades reliability or discovery
- **medium** — reduces clarity or increases false-match rate
- **low** — style or minor completeness gaps

For each finding:
- Severity:
- Location (file:line if applicable):
- Issue:
- Why it matters:
- Minimal fix:

### 5. Normalized Gain Estimate

If the skill was recently edited, estimate:
`normalized_gain = (score_after − score_before) / (10 − score_before)`

State "insufficient baseline" if no prior version is available for comparison.

### 6. Recommendation

One of:
- **Ship** — ready for production use
- **Revise** — address high/blocker findings before shipping
- **Rewrite** — fundamental structural issues; incremental fixes insufficient

Include the exact minimal changes needed to move from current verdict to PASS.

---

## Constraints

- Do not invent file contents. If a referenced file does not exist, note it as
  a missing artifact finding.
- Separate definite violations from subjective suggestions.
- Do not restate the skill content verbatim. Report issues only.
- Grade outcomes: does the skill reliably produce the right result? Not whether
  every word is perfect.

$ARGUMENTS
