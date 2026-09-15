# Fix deprecation warnings with PTC

This complete example migrates `old_greet()` calls to `greet()` in a tiny MoonBit
module. The migration rule is chosen in advance; the script never interprets a
diagnostic message as executable code or guesses how to fix other deprecations.

The [script](fix-deprecations.mbtx) performs one workflow:

1. Run `moon check --output-json --warn-list +deprecated` in the selected module.
2. Collect matching compiler locations and read their current source lines.
3. Submit one `@tools.call("multi_edit", { "edits": edits })` batch. Each edit
   carries an exact old line and a one-line search range; host validation handles
   stale source and batch failure.
4. Run `moon check --deny-warn` and `moon test`, then print a short summary.

## Run it

Use an OpenSeek build with PTC (PR #1532 or a build containing it). From the
repository root, copy the fixture to a disposable workspace directory:

```sh
mkdir -p .moonagent/ptc-deprecation-demo
cp tools_sdk/examples/deprecation-demo/* .moonagent/ptc-deprecation-demo/
moon -C .moonagent/ptc-deprecation-demo check --warn-list +deprecated
```

The fixture contains two deprecated call sites. Invoke the host's `mbtx` tool
with these JSON arguments, from an OpenSeek session rooted at this checkout:

```json
{
  "filename": "tools_sdk/examples/fix-deprecations.mbtx",
  "cwd": ".moonagent/ptc-deprecation-demo",
  "ptc": true
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

## Adapt it

Replace the known diagnostic match and source transformation only after choosing
a migration for your project. This example replaces one known call per selected line, so review lines with
multiple calls, comments, strings, or more complex syntax before generalizing it. Other warnings are left untouched and the
final `--deny-warn` verification reports them. Changes to diagnostics or ambiguous
source should lead to review, not guessed replacements. File edits are one batch;
the later check/test processes are separate verification steps, not a transaction.

The host test runs this exact checked-in script through the real published SDK,
checks that only the intended lines change, verifies the recorded PTC result,
and runs it again to prove there are no further edits:

```sh
moon test agent_tool/mbtx --target native --filter '*deprecation example*'
moon test agent_tool/mbtx --target wasm --filter '*deprecation example*'
```
