# Programmatic tool calls

## Objective

Let a MoonBit script compute arguments, call the host's existing tools, inspect
structured results, and continue without a model turn at each boundary. Keep
direct `edit`, `multi_edit`, and `edits_file` support.

## Initial scope and execution contract

- `mbtx(ptc=true)` supplies a `tools` client with `call`, `edit`, `multi_edit`,
  and `web_search` methods. Generic calls use the same registered definitions.
- Only explicitly program-callable definitions are exposed. Start with edit,
  multi_edit, and web_search. Do not expose mbtx, finish, goal, plan, or job
  control. Missing registrations remain unavailable.
- One shared execution gate protects stateful operations from direct and PTC
  callers. Concurrent-safe searches may overlap, with bounded connections.
- PTC programs initially have a bounded foreground lifetime (the existing
  standalone foreground timeout). Ordinary mbtx programs retain automatic
  background handoff. Background PTC can later adopt the service along with
  the process; it is not needed to establish the request/result contract.
- A run-scoped loopback service handles requests while mbtx asynchronously
  waits for its child. The service calls leaf tool executors. Neither the
  outer mbtx wait nor request reception holds the execution gate. Therefore
  there is no path from a leaf executor back to the waiting mbtx invocation.
- Cancellation closes the service and cancels its handlers before returning;
  no detached request may continue editing after the call ends. A tool error
  is a result; transport failure is an exception and never triggers a retry.

## Data and observability

- Add optional structured data to tool output without changing model-facing
  text. Web search returns its existing bounded normalized sources as data.
- Use versioned JSON requests/results, a random per-run capability, strict
  payload bounds, a call-count budget, and bounded result/trace retention.
- Keep RPC separate from stdout/stderr. Credentials stay in host executors.
- Preserve nested arguments and outcomes in a bounded trace attached to the
  outer result as non-model metadata. Persist this alongside the tool result
  and expose it in Desktop. On failures/cancellation, retain completed and
  interrupted call records rather than presenting an empty successful trace.

## SDK delivery

Single-file MoonBit imports resolve published packages. Bundle the small
client source with the host and inject it only for ptc scripts, reusing
user import aliases and leaving the program body unchanged. This makes the
feature usable and testable before an SDK release. Scripts use ordinary MoonBit syntax; no evaluator or custom
language is introduced. Generated client and protocol stay in one versioned
host build.

## Implementation stages

1. Structured results and explicit program-callability; retain direct-call
   semantics and test normalized search data.
2. Run-scoped service, bundled client, mbtx wiring, and shared state access.
3. Durable nested-call metadata and Desktop rendering, examples and prompts.
4. Exercise real scripts and scripted agent turns; run integration gates.

Use reviewable commits; split into stacked PRs only if it improves review.

## Required verification

- Real mbtx -> edit -> reply -> script exit completes under a short timeout.
- Generated multi_edit retains validation, rollback, and shared provenance.
- An allowed concurrent-safe tool overlaps; stateful calls do not overlap.
- Unknown, unregistered, control, and recursive mbtx calls are rejected before
  execution. Invalid credentials and malformed/oversized payloads do no work.
- A cancelled/expired run closes pending requests and releases execution gates.
- Tool failures remain distinguishable from transport failures; no retry.
- Structured data survives the client round trip and persistence without
  being injected into model context. Trace limits are explicit.
- Ordinary mbtx foreground/background behavior remains unchanged.
- Run `just check`, `just test`, `just build`, relevant Desktop checks,
  then `moon info && moon fmt` and review generated interface diffs.

## Completed

- Implemented the bridge, bundled client, shared state access, structured search
  output, durable traces, Desktop cards, and English/Chinese prompt guidance.
- Kept the work in one PR with separate runtime and Desktop/documentation commits.
- Unfinished requests are joined on exit and make the outer call report an error.

## Validation (2026-09-15)

- `just check`: native/JS warning checks, bundled workflows, generated prompt,
  and formatting passed. Generated interfaces reviewed after `moon info`.
- `just test`: 3,138 native and 3,243 JS tests passed; all 38 cram cases,
  real CLI lifecycle checks, and offline workflow checks passed.
- `just build`: native and JS passed.
- 13 focused PTC tests passed. The nine bridge/source tests were rerun after
  the final unfinished-request error handling change and passed.
- Desktop browser PTC reload/diff test and both OpenSeek tool-status tests
  passed; the rendered nested diff and interruption message were inspected.
- The existing Codex tool-status browser fixture has an order-sensitive failure
  at a disabled Send button, before tool execution. It passes in isolation.
  Reproduced the failure on unmodified base `d818b71b1` after loading/reloading
  the same session fixture in a separate worktree. This is recorded separately
  from the passing PTC/OpenSeek browser checks.

## Prompt A/B follow-up (2026-09-15)

- Compared expanded and compact PTC guidance against fresh baselines in 48
  real Flash trials, with three repetitions per variant/task and separate
  free-choice and explicitly requested PTC cohorts.
- All 36 file-edit trials passed final byte and preservation checks. The compact
  prompt reduced steps/errors on free-choice edits; forced PTC needed more
  repairs. Search provenance remained weak. No general speedup is claimed.
- Retained the compact English guidance and synchronized its Chinese translation.
  No change to the default `ptc` value. Reproducible runner, complete metrics,
  rejected candidate, and limitations are in
  [the A/B report](../../eval/ptc_prompt/results-2026-09-15.md).
