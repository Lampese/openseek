# Fix deprecation warnings with PTC

This example takes two arguments, `OLD` and `NEW`, and migrates deprecated
symbols with that exact spelling. The included fixture uses `old_greet` →
`greet`, but neither name nor diagnostic message is hardcoded in the script.
The caller chooses the migration; the script never guesses a replacement.

The [script](fix-deprecations.mbtx) performs one workflow:

1. Run `moon check --output-json --warn-list +deprecated` in the selected module.
2. Read warning-20 locations and select source spans exactly equal to `OLD`.
   Group them by line and replace from right to left, so multiple calls and
   different replacement lengths work without shifting the remaining locations.
3. Submit one `@tools.call("multi_edit", { "edits": edits })` batch. Each edit
   carries an exact old line and a one-line search range; host validation handles
   stale source and batch failure.
4. Run `moon check --deny-warn` and `moon test`, then print a short summary.

## Run it

Use an OpenSeek build with PTC (PR #1532 or a build containing it). From the
repository root, copy the fixture to a disposable workspace directory:

```sh
mkdir -p .moonagent/ptc-deprecation-demo
cp agent_tool/ptc/examples/deprecation-demo/* .moonagent/ptc-deprecation-demo/
moon -C .moonagent/ptc-deprecation-demo check --warn-list +deprecated
```

The fixture contains two deprecated call sites. Invoke the host's `mbtx` tool
with these JSON arguments, from an OpenSeek session rooted at this checkout:

```json
{
  "filename": "agent_tool/ptc/examples/fix-deprecations.mbtx",
  "cwd": ".moonagent/ptc-deprecation-demo",
  "ptc": true,
  "args": ["old_greet", "greet"]
}
```

Expected final output:

```text
Fixed 2 deprecated call-site lines; check and tests passed.
```

A longer invocation may return a background job ID. Read its result with
`job_output`; the same PTC registration stays active after handoff. Running the
script again prints `Fixed 0 ...` and issues no edit calls. Inspect the source
before retrying after a transport error, because an edit may already have run.

The script pins published SDK `0.1.0`, whose `call` API is identical to the
prepared `0.2.0`. It needs a host-provided `OPENSEEK_PTC` capability: ordinary
`moon run` cannot perform the PTC edit outside an OpenSeek invocation.

## Use another migration

Set `args` to `["your_deprecated_symbol", "its_replacement"]` and set `cwd` to
the module you want to check. Use the exact spelling underlined by the compiler:
for the fixture this is `old_greet`, **without parentheses**. Both arguments must
be nonempty, distinct, single-line strings. Missing or invalid arguments fail
before checking the target module or calling a host tool.

Only deprecated symbol spans matching `OLD` are changed. Identical text in
strings/comments and deprecated symbols with another spelling are left alone.
Compiler character columns are converted to MoonBit string offsets, including
Unicode before the call. Other warnings remain visible: the final `--deny-warn`
check fails if any are left. Migrations requiring argument reshaping or other
semantic changes still need a tailored script or model review.

File edits are one batch. The later check/test processes are separate verification
steps, not a transaction; a failed verification does not undo completed edits.

The host test runs this exact checked-in script through the real published SDK,
covers two old/new pairs, Unicode, symbols at end of line, repeated calls on one
line, and identical text
in strings/comments. It verifies the recorded PTC result, runs again to check
idempotence, and tests that invalid arguments fail before any tool call:

```sh
moon test agent_tool/mbtx --target native --filter '*deprecation example*'
moon test agent_tool/mbtx --target wasm --filter '*deprecation example*'
```
