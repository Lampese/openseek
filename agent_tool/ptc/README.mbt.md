# Programmatic tool calls

PTC defaults on for supported wasm runs in the standard host. Set `ptc: false`
to opt out. Scripts call host tools through the published SDK. It invokes the
same registered executors as direct tool calls, including
edit validation, rollback checks, and the session's shared `FileStateMap`.
Direct `edit`, `multi_edit`, and `multi_edit(edits_file=...)` remain available.

For example, pass this as `source` to mbtx:

```mbtx
import { "bobzhang/openseek_tools@0.1.0" @tools, "moonbitlang/async" }

async fn main {
  let result = @tools.edit({
    "path": "note.txt", "start_line": 1,
    "old_string": "before", "new_string": "after",
  })
  if result.is_error { fail(result.content) }
  println(result.content)
}
```

The SDK is an ordinary version-pinned package import. The host passes only the
run-scoped connection capability; it does not insert imports, globals, helper
functions, or types into the source. Saved source and compiler line numbers are
unchanged. `bobzhang/openseek_tools@0.1.0` is published on Mooncakes and the
integration tests exercise this exact registry import.

## Results and search

All calls return `@tools.CallResult { content : String, is_error : Bool, data : Json? }`.
Tool errors are values. Transport failures raise `@tools.TransportError`: the tool
may already have executed, so never automatically retry a mutation.

Each named function accepts the same JSON arguments as its direct host tool.
The SDK forwards arguments unchanged; validation and defaults stay in the host.

- `@tools.edit(arguments : Json)`
- `@tools.multi_edit(arguments : Json)`, e.g. `{ "edits": edits }` or `{ "edits_file": "edits.json" }`
- `@tools.web_search(arguments : Json)`, e.g. `{ "query": query }`, when registered
- `@tools.call(name : String, arguments : Json)` for other enabled tools

For search, `data` is `{sources: [{url, title?, snippet?, published_at?}],
truncated: Bool}`. Optional source fields are absent when unavailable.

```mbtx
import { "bobzhang/openseek_tools@0.1.0" @tools, "moonbitlang/async" }

async fn main {
  let result = @tools.web_search({ "query": "MoonBit async task groups" })
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

The OpenSeek session owns one loopback HTTP server. Every script receives its
own capability, active-call set, and trace. The listener calls existing leaf
executors directly, independently of the agent loop's wait for mbtx. The outer
mbtx wait never holds the file gate. Direct and RPC file operations share that
gate across validation, writes, checks, and rollback.

Normal mbtx background handoff is preserved. After adoption, the job owns the
script registration; the server stays in OpenSeek. Calls after handoff update
the job's durable metadata, never the foreground tool trace. job_output returns
that trace as structured metadata. Job completion, job_stop, and session shutdown
revoke capabilities, cancel and join active calls, then report completion. Close
never holds the file gate. Already completed mutations are not rolled back by
cancellation. A script that exits successfully with unfinished calls records an
explicit cleanup error rather than silently claiming success.

Only definitions with program_callable=true and no loop control are exposed.
Recursive mbtx, finish, goal, plan, and job controls are unavailable. New callable
executors must remain leaves and must not reacquire the same file gate.

Default activation applies when a session service exists and the selected mode
is wasm without subrun or escalation. Explicit ptc=true in an incompatible mode
errors; omitted ptc leaves those modes unchanged. Standalone definitions without
a session service may still use the foreground-only run bracket.

## Protocol and bounds

The host supplies an `OPENSEEK_PTC` environment handoff containing a version,
loopback URL, and random per-run bearer capability. Unauthenticated requests and
browser-origin requests are rejected. Credentials used by individual tools stay
in the host. No RPC traffic uses stdout or stderr.

Version 1 accepts `{version: 1, name, arguments}` and returns
`{version: 1, content, is_error, data?, brief?}`. Limits per run:

- 64 tool requests and four active calls per script; 16 connections per session
  and at most 64 active script registrations.
- 64 KiB request body, read within five seconds.
- 120 seconds per tool call, including queueing; 125 seconds client timeout.
- 64K characters per serialized result. Oversized output becomes an explicit
  error saying execution occurred; the host does not retry it.
- 512 KiB retained trace plus JSON framing. Full results still reach the client;
  omitted retained results carry an explicit truncation marker. Requests that
  cannot reserve trace space are rejected before tool execution.

The trace therefore has bounded entries and payloads. RPC errors remain separate
from script failures. The SDK import pins an immutable version; the host explicitly checks wire protocol version 1.
