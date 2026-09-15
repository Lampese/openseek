///|
/// Nested calls are display metadata, not synthetic assistant tool calls.
/// Reuse normal tool cards so editing arguments retain their diff views.
fn program_calls(data : Json?, parent : String) -> Array[ToolCall] {
  guard data is Some({ "ptc_calls": Array(entries), .. }) else { return [] }
  let calls : Array[ToolCall] = []
  for index, entry in entries[:entries.length().min(64)] {
    guard entry
      is {
        "name": String(name),
        "arguments": arguments,
        "status": String(status),
        ..
      } else {
      continue
    }
    let outcome = match entry {
      {
        "result": {
          "content": String(content),
          "is_error": True
          | False as flag,
          ..
        } as result,
        ..
      } if status == "done" => {
        let brief = match result {
          { "brief": String(value), .. } => Some(value)
          _ => None
        }
        Done(content~, is_error=flag == true, brief~)
      }
      _ =>
        Done(
          content="Program call interrupted; changes may have occurred.",
          is_error=true,
          brief=None,
        )
    }
    calls.push({
      call_id: "\{parent}/ptc/\{index}",
      name,
      arguments: Some(arguments.stringify()),
      outcome,
      children: [],
    })
  }
  calls
}

///|
test "program calls retain edit arguments and interruption state" {
  let calls = program_calls(
    Some({
      "ptc_calls": [
        {
          "name": "edit",
          "arguments": { "path": "a.mbt" },
          "status": "done",
          "result": { "content": "ok", "is_error": false },
        },
        { "name": "multi_edit", "arguments": {}, "status": "interrupted" },
      ],
    }),
    "outer",
  )
  assert_eq(calls.length(), 2)
  assert_eq(calls[0].call_id, "outer/ptc/0")
  assert_true(calls[0].outcome is Done(is_error=false, ..))
  assert_true(calls[1].outcome is Done(is_error=true, ..))
  assert_true(program_calls(None, "outer").is_empty())
}
