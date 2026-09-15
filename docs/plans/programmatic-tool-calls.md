# SDK-first programmatic tool calls

Replace the source-injecting implementation in #1516 with four reviewable steps.
The SDK is a normal package import; host execution, presentation, and prompt
behavior are separate concerns.

## 1. SDK — #1518

Independent module `bobzhang/openseek_tools@0.1.0` under `tools_sdk/` exposes
`@tools.call`, `@tools.edit`, `@tools.multi_edit`, and `@tools.web_search`, plus
`CallResult` and `TransportError`. It depends only on async/core libraries and
speaks wire protocol v1. No agent implementation or shared mutable host state
is pulled into the SDK. No SDK source is appended to user scripts.

Native and wasm tests cover capability/response validation, structured results,
HTTP authentication/schema, no retries, and cancellation. Both targets pass six
tests, and packaging succeeds. A dedicated CI job checks the SDK independently.

**Release boundary:** merge and publish the SDK, run `moon update`, then verify a pinned import in
a fresh `.mbtx` process. The package has not been published by this task.

## 2. Host bridge — #1519

`mbtx(ptc=true)` supplies a run-scoped connection capability in `OPENSEEK_PTC`.
The script imports the published SDK explicitly. No source, import, namespace,
or line-number rewriting occurs. PTC initially stays foreground and cannot be
combined with subrun, escalation, or another target.

The RPC service runs beside the child-process wait and calls leaf executors
directly. The waiting agent loop is not asked to dispatch another call. The
outer mbtx wait holds no file-operation gate; direct and nested file operations
share a gate covering validation, writes, checks, and rollback. No enabled leaf
may reacquire that gate or wait for agent-loop work.

The endpoint uses a per-run capability, at most four connections and 64 calls,
64 KiB requests, bounded results, and per-call deadlines. Cancellation and exit
close the endpoint and join handlers before returning. Unfinished requests stay
in the trace and make the outer result an error. Transport failure does not
prove a mutation was rolled back and never triggers automatic retry.

Only explicitly enabled leaf tools are exposed. Recursive mbtx and loop/job
controls remain unavailable. Direct tools and `edits_file` stay available.
Structured search sources and nested traces persist as metadata; only printed
output enters the next model request.

Eight bridge tests and the real-script namespace/source-preservation test pass.
Native/JS checks and builds pass. Actual SDK-import integration tests remain
pending publication; the tests are retained, not skipped or given an injection
fallback. A direct pinned import currently reports a missing registry module.

## 3. Desktop — #1520

Carry optional structured result metadata into Desktop's explicit JSON codec,
decode bounded child calls, and render existing tool cards and edit diffs.
Interrupted calls and nested results survive reload. No prompt changes belong
in this step.

Validation: 76 native protocol tests, 40 JS transcript tests, browser build,
and the PTC reload/diff browser test pass.

## 4. Prompt guidance and capability evaluation

Document the explicit version-pinned `@tools` import, ordinary MoonBit async
calls, error handling, joined tasks, and the printed-output boundary. Preserve
direct calls for simple work and batch validation for related edits.

After SDK publication and green host integration tests, compare two binaries:
SDK-only baseline (#1518, original host tools) versus the host-bridge candidate.
Use the **same prompt**, model, fixture bytes, limits, and free tool choice.
The evaluation runner accepts `--baseline-engine` and records both binary hashes
and equal prompt hashes. Do not force PTC in a capability comparison. Separately
exercise explicit PTC as an execution smoke test.

The prior 48-trial experiment is preserved as historical prompt-only evidence:
both sides already had PTC and used the injected client. It neither measures
PTC versus no PTC nor validates the new SDK import. It found no file-content
failures, mixed prompt efficiency, and weak search provenance. Do not reuse
those numbers as SDK or PTC performance claims.

## Merge order

1. Merge/release SDK, verify registry import.
2. Run full host integration suite and merge bridge.
3. Merge Desktop integration after host.
4. Run capability A/B against the released SDK; review prompt/eval changes last.

Keep dependent PRs draft until their release prerequisites and required checks
are satisfied. No publication, merge, or release is performed by splitting PRs.

### SDK argument convention

Named calls (`@tools.edit(arguments)`, `@tools.multi_edit(arguments)`, and
`@tools.web_search(arguments)`) take one JSON object identical to the direct
tool's arguments. The SDK forwards it unchanged, including optional fields;
the host owns validation and defaults. `@tools.call(name, arguments)` remains
the escape hatch for other enabled tools. Results remain typed `CallResult`.
