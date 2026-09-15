///|
/// Script-facing API and execution constraints, appended only by a host that
/// can actually serve programmatic calls.
pub fn description() -> String {
  (
    #|
    #|
    #|## Programmatic tool calls (PTC)
    #|
    #|Set ptc=true to allow host tool calls for this foreground run. Explicitly
    #|import the published SDK in the script; the host does not rewrite source:
    #|
    #|  import { "bobzhang/openseek_tools@0.1.0" @tools }
    #|
    #|Use ordinary MoonBit async functions, with no await keyword:
    #|
    #|  let result = @tools.edit({
    #|    "path": "note.txt", "start_line": 1,
    #|    "old_string": "before", "new_string": "after",
    #|  })
    #|  if result.is_error { fail(result.content) }
    #|
    #|Named calls take the same JSON arguments as their direct host tools:
    #|`@tools.edit(arguments)`, `@tools.multi_edit({ "edits": edits })`, and
    #|`@tools.web_search({ "query": query })`. Arguments are forwarded unchanged;
    #|validation and defaults stay in the host. multi_edit also accepts edits_file.
    #|`@tools.call(name, arguments)` supports other explicitly PTC-enabled tools.
    #|edit, multi_edit, and web_search (when registered) are initially enabled.
    #|
    #|Results have content : String, is_error : Bool, data : Json?. Tool errors
    #|are results; transport failures raise and MUST NOT automatically retry a
    #|mutation because its outcome may be unknown. Search data is
    #|{sources:[{url,title?,snippet?,published_at?}],truncated:Bool}. Missing
    #|fields are absent, not empty strings. Keep selected URLs when printing
    #|sources so the final answer can cite them.
    #|
    #|PTC scripts stay foreground up to the run timeout (normally 300s). They
    #|do not auto-detach, and cannot combine with subrun, escalated, or another
    #|target. Up to 64 calls per script, 64 KiB per request, 64K characters per
    #|result, and four requests in flight. Stateful calls serialize; independent
    #|searches can overlap using a MoonBit task group. Batch related edits with
    #|multi_edit to retain its validation and rollback semantics. finish, goal,
    #|plan, job controls, and recursive mbtx calls are unavailable.
    #|
    #|Nested calls are recorded as metadata under this mbtx result; only the
    #|script's printed output returns to model context. Print concise selected
    #|results, handle is_error explicitly, and stop when further steps require
    #|model judgment.
  )
}
