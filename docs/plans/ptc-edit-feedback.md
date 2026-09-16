# Fixing warnings from a PTC script: per-edit revert guards and structured feedback

Status: proposal, revised 2026-09-16. Nothing here is implemented yet.

## The target loop

The primary use case is a script that fixes most of a project's warnings in
one pass and leaves the rest for a manual fix:

1. Ask for the current diagnostics as data: every warning with its path, a
   `line:col-line:col` span, its code, and its message.
2. For each warning of a class the script knows how to fix, read the file
   (scripts already have workspace read access) and cut `old_string` from the
   span. `start_line` is the span's line. `new_string` comes from the message:
   a deprecation says "use `len` instead", an unused binding gets an underscore
   prefix, an unused import drops a manifest line.
3. Apply each fix with a single `edit` call that carries
   `revert_on_errors: true` and `revert_on_warnings: true`. The tool checks
   the tree before and after the write; if the edit introduced an error or a
   warning it restores the file and says so.
4. Collect the outcomes. Kept edits are done; reverted edits and warnings of
   unhandled classes are printed for the model and the human.

Single edits are the unit on purpose. Each fix is compile-checked alone,
against the tree that already contains the previous kept fixes, so a bad fix
is identified exactly and undone by the tool, with no attribution problem and
no partial batch to untangle. Line numbers never go stale because every edit
is built from the diagnostics of the tree as it is at that moment.

## What exists today

- `multi_edit` already has the post-write guard: write, `moon check`, count
  errors introduced against a baseline, restore on breach, and a report with a
  comparability verdict. `edit` has only the pre-write parse gate and appends
  moon's human one-diagnostic text after a successful write.
- `auto_check` tallies `moon check --output-json` into `CheckErrors`
  (`error_count`, `warning_count`, `errors: [ErrorSite {path, loc, code,
  message}]`, `truncated`). Warnings are counted; their sites are dropped.
- Neither tool sets `ToolOutput.data`; `web_search` does (`sources`,
  `truncated`) and is the precedent. A PTC script already receives
  `result.data : Json?` through the published SDK, so no SDK change is needed.
- A script cannot run `moon check` itself (wasm, no processes), and nothing
  returns diagnostics before the first edit.

## Work, in order

### 1. Warning sites and a diff rule (`auto_check`)

Keep warning sites in the tally (`warnings: [ErrorSite]`, capped at 200 with
`warnings_truncated`). Add `CheckErrors::to_json`. Add one pure function that
computes what a change introduced: compare the multisets of
`(path, code, message)` before and after, ignoring `loc`. This is robust to
the line shifts an edit causes below itself, and it catches a fix that
removes one warning and introduces another, which a count comparison cannot.
The same rule serves errors.

### 2. A `check` seed tool

A small read-only tool, program-callable, that runs the tally for the project
containing a path (default: the workspace root) and returns the CHECK payload
as `data` with a one-line text summary. It seeds the loop and doubles as a
progress probe without editing. The retired model-facing moon_check tool was a
different thing (raw output for the model); this one exists for scripts and
returns structured data, so it needs an explicit decision (see below).

### 3. Shared revert guard; two new `edit` flags

Move the apply, check, restore, and report machinery out of `multi_edit` into
an internal package. `edit` gains two post-write guards next to its existing
pre-write `revert_on_parse_errors`:

- `revert_on_errors` (default false): restore the file when the edit
  introduced an error.
- `revert_on_warnings` (default false): restore the file when the edit
  introduced a warning.

With either flag set the tool checks before the write and after it: two
checks per edit. `multi_edit`'s lazy baseline (check the baseline only when
the post-batch count breaches the threshold) does not pay here, because in a
warning-heavy tree the post-edit warnings are never zero, so lazy would mean
three checks with a restore in the middle. Without either flag `edit` behaves
exactly as today. `multi_edit` gets `revert_on_warnings` from the same code.

### 4. `data` payloads

One `outcome` discriminator per tool; other fields appear only for the
outcomes that produce them.

```
edit:       { "outcome": "applied" | "reverted" | "rejected" | "preview" | "not_found" | "error",
              "path", "lines": { "start", "end" },
              "check": CHECK,                                   // applied, reverted
              "introduced": { "errors": [site], "warnings": [site] },   // reverted
              "parse_errors": [{ "loc", "message" }],           // rejected
              "edits": [{ "file", "old_string", "new_string", "start_line" }] }   // preview

multi_edit: { "outcome": "applied" | "reverted" | "rejected" | "failed",
              "files": [{ "path", "edits": n }], "edit_count": n,
              "failures": [{ "file", "index", "range", "message" }],        // failed
              "parse_errors": { "<path>": [{ "loc", "message" }] },         // rejected
              "check": CHECK, "introduced": { "errors": [site], "warnings": [site] },
              "threshold": n,
              "verdict": "over_match" | "breakage" | "inconclusive"
                       | "certified_reach" | "plausible_reach", "verdict_reason",
              "new_in_edited": [site], "new_breaking": [site], "new_in_dependents": [site],
              "new_independent": n, "reissue_with": n, "restore_failures": [path] }

CHECK:      { "error_count", "warning_count", "truncated",
              "errors":   [{ "path", "loc", "code", "message" }],
              "warnings": [{ "path", "loc", "code", "message" }], "warnings_truncated" }
```

`edit` comes first (it is the loop's unit), `multi_edit` second. The
model-facing text of `multi_edit` is unchanged. For `edit`, the trailing check
line after a successful write becomes the same one-line status `multi_edit`
prints (`moon check: ok — 0 errors, N warning(s)`, or the error count plus the
first errors) instead of moon's raw one-diagnostic output, because the JSON
tally is the only way `edit` gets structured diagnostics without a second
check.

### 5. Docs and the SDK example

One paragraph in `agent_tool/ptc/description.mbt` naming `outcome`, `check`,
and `introduced`, the way it names the search shape; the two tool READMEs; the
warning-fix loop as the canonical SDK README example, run as a fixture through
the wasm host like the existing `agent_tool/mbtx/ptc_test.mbt` cases.

### 6. Eval case

A fixture with a few dozen deprecation and unused-binding warnings across
several files, plus a couple of fixes that would introduce a warning or an
error so the guards have something to revert. Baseline is the current tools;
candidate is items 1 to 5. Measure rounds, nested-call counts, how many
warnings remain, and whether `moon check --deny-warn` passes afterwards.

## Bounds

- A PTC script may make 64 calls, so one run fixes about sixty warnings. For
  larger backlogs the script runs again, or the per-script call budget is
  raised (the 512 KiB trace budget remains the hard bound on retained data;
  edit results are small). See decisions.
- A PTC reply is capped at 64 K characters including `data`, the retained
  trace at 512 KiB per job, the durable record at 1 MiB. Cap `errors` and
  `warnings` at 200 each and every site list at 50; if a payload would still
  exceed 24 K characters, drop `warnings`, then `errors` beyond the first 10,
  and set `truncated`. Text stays complete.
- `moon check` skips the dependents of a failing package, so the warnings list
  is complete only when the error count is zero. The script fixes errors
  first, or accepts that later rounds surface more warnings as the build
  reaches further.

## Deferred

- `dry_run` (matching plus parse gate, no `moon check`) on both tools. The
  per-edit loop does not need it: a non-matching `old_string` already fails
  before any write, and the loop rebuilds edits from fresh diagnostics each
  round. Worth adding later for batch-oriented scripts.
- Batch-oriented loops on `multi_edit` (preview, filter, apply; branch on the
  revert verdict). The payload above supports them; they are not the first
  use case.
- A full compile dry-run that always restores: rejected. `revert_on_*` already
  gives "keep only if clean", and always-restore would only add a transient
  tree visible to background jobs and the editor.

## PR split

1. `auto_check`: warning sites, `to_json`, the introduced-diff rule.
2. The `check` seed tool.
3. Shared revert guard; `edit` gains `revert_on_errors` and
   `revert_on_warnings`; `multi_edit` gains `revert_on_warnings`.
4. `edit` payload and check-line alignment; preview `data.edits`.
5. `multi_edit` payload.
6. Descriptions, READMEs, SDK example, eval case.

## Decisions

1. Add the read-only `check` seed tool (recommended: yes; the loop has no
   other way to start).
2. Defaults for `revert_on_errors` and `revert_on_warnings` on `edit`
   (recommended: both off at first, revisit after the eval; on would also
   protect direct model edits the way `multi_edit` already does).
3. Accept the `edit` check-line change in item 4 (recommended: yes).
4. Raise the per-script call budget from 64 (for example to 256) so one run
   covers a larger backlog, or keep 64 and run the script more than once.
