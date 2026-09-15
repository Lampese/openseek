# Programmatic tool calls

Call `mbtx` with `ptc: true` to allow a MoonBit script to call host tools through the published SDK. It invokes the same registered executors as direct tool calls, including
edit validation, rollback checks, and the session's shared `FileStateMap`.
Direct `edit`, `multi_edit`, and `multi_edit(edits_file=...)` remain available.

For example, pass this as `source` with `ptc: true`:

```mbtx
import { "bobzhang/openseek_tools@0.1.0" @tools }

async fn main {
  let result = @tools.edit(path="note.txt", start_line=1,
    old_string="before", new_string="after")
  if result.is_error { fail(result.content) }
  println(result.content)
}
```

The SDK is an ordinary version-pinned package import. The host passes only the
run-scoped connection capability; it does not insert imports, globals, helper
functions, or types into the source. Saved source and compiler line numbers are
unchanged. Publish `bobzhang/openseek_tools@0.1.0` before enabling this dependency
in the release. See `tools_sdk/README.mbt.md` for the release order.

## Results and search

All calls return `@tools.CallResult { content : String, is_error : Bool, data : Json? }`.
Tool errors are values. Transport failures raise `@tools.TransportError`: the tool
may already have executed, so never automatically retry a mutation.

- `@tools.edit(path~, old_string~, new_string~, start_line~, end_line?, revert_on_parse_errors?)`
- `@tools.multi_edit(edits : Array[Json], revert_when_errors_above?, revert_on_parse_errors?)`
- `@tools.web_search(query : String)` when the host has registered web search
- `@tools.call(name : String, arguments : Json)` for the complete tool schema

For search, `data` is `{sources: [{url, title?, snippet?, published_at?}],
truncated: Bool}`. Optional source fields are absent when unavailable.

```mbtx
import { "bobzhang/openseek_tools@0.1.0" @tools }

async fn main {
  let result = @tools.web_search("MoonBit async task groups")
  if result.is_error { fail(result.content) }
  guard result.data is Some({ "sources": Array(sources), .. }) else {
    fail("search did not return structured sources")
  }
  for source in sources[:sources.length().min(3)] {
    println(source.stringify())
  }
}
```

Only printed output enters the next model request. Nested arguments and results
are stored as metadata on the outer result and displayed as nested Desktop tool
cards. Print the information the model needs, retaining source URLs for citations.
A program can branch, compute arguments, and filter results; return to the model
when the next step requires its judgment.

## Lifetime and deadlock prevention

```text
agent loop -> await mbtx
                 |-- await child script -> await HTTP reply
                 `-- sibling RPC task -> leaf tool executor -> reply
```

The loop's wait does not block the RPC task. The RPC task calls leaf executors
directly; it never asks the waiting agent loop to dispatch another tool. The outer
`mbtx` invocation holds no file-operation lock while waiting. Direct and nested
file tools share one lock covering validation, writes, checks, and rollback.
Stateful RPC calls serialize; concurrent-safe calls can overlap. Callers may use
ordinary MoonBit task groups for independent searches.

Only definitions that explicitly set `program_callable=true` are exposed.
Definitions marked `control` are excluded even if marked callable. The initial registry exposes
edit, multi_edit, and (when configured) web_search. Recursive mbtx, finish, goal,
plan, and job control are unavailable. Future callable executors must remain
leaves: they must not wait for agent-loop work or reacquire the file gate.

PTC runs stay foreground, normally for at most 300 seconds, with no automatic
background handoff. `subrun`, `escalated`, and non-wasm targets cannot combine
with PTC. Normal mbtx background behavior is unchanged. On completion, timeout,
or cancellation, the host closes and joins the RPC service and its handlers
before returning. Interrupted calls remain in the trace and make the outer call
report an error, including a script that exits without awaiting its requests. Cancellation does not
promise rollback of already completed mutations.

## Protocol and bounds

The host supplies an `OPENSEEK_PTC` environment handoff containing a version,
loopback URL, and random per-run bearer capability. Unauthenticated requests and
browser-origin requests are rejected. Credentials used by individual tools stay
in the host. No RPC traffic uses stdout or stderr.

Version 1 accepts `{version: 1, name, arguments}` and returns
`{version: 1, content, is_error, data?, brief?}`. Limits per run:

- 64 tool requests, at most four connections in flight.
- 64 KiB request body, read within five seconds.
- 120 seconds per tool call, including queueing; 125 seconds client timeout.
- 64K characters per serialized result. Oversized output becomes an explicit
  error saying execution occurred; the host does not retry it.

The trace therefore has bounded entries and payloads. RPC errors remain separate
from script failures. The SDK import pins an immutable version; the host explicitly checks wire protocol version 1.
