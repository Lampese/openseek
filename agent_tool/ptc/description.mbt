///|
/// Script-facing API and execution constraints, appended only by a host that
/// can actually serve programmatic calls.
pub fn description() -> String {
  (
    #|
    #|
    #|## Programmatic tool calls (PTC)
    #|
    #|Set ptc=true to get a bundled `tools` client in the script. No SDK import
    #|is needed. Keep your normal imports. Use ordinary MoonBit async functions:
    #|
    #|  let result = tools.edit(path="note.txt", start_line=1,
    #|    old_string="before", new_string="after")
    #|  if result.is_error { fail(result.content) }
    #|
    #|`tools.multi_edit(edits)` takes an Array[Json] with the usual per-edit
    #|file, old_string, new_string, start_line, optional end_line fields.
    #|`tools.web_search(query)` returns structured sources in result.data when
    #|web_search is registered. `tools.call(name, arguments)` accepts the same
    #|JSON arguments as the named tool and supports explicitly PTC-enabled
    #|tools only. edit, multi_edit, and web_search are initially enabled.
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
    #|model judgment. Keep PtcTools, PtcResult, PtcTransportError, tools, and
    #|the ptc_* import aliases free for the injected client.
  )
}
