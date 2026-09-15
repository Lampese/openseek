///|
/// Run one program with a temporary, authenticated tool endpoint. The server
/// lives in a sibling task of `program`, so waiting for the child never blocks
/// servicing its requests. All handlers finish or cancel before this returns.
pub async fn run(
  tools : @agent_tool.Tools,
  program : async (Map[String, String]) -> @agent_tool.ToolAction,
  on_trace? : (Json) -> Unit = _ => (),
) -> @agent_tool.ToolAction {
  let tools = tools.program_tools()
  guard @env.rand(32) is Some(entropy) else {
    fail("PTC: secure random capability unavailable")
  }
  let token = @crypto.bytes_to_hex_string(entropy)
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let calls : Array[Json] = []
  let serial = @async.Mutex()
  fn trace() -> Json {
    { "ptc_calls": calls.to_json() }
  }
  @async.with_task_group() <| group => {
    let worker = group.spawn(no_wait=true, () => {
      server.run_forever(max_connections=4, allow_failure=true, (
        request,
        body,
        conn,
      ) => {
        defer conn.close()
        if request.meth != Post ||
          request.path != "/call" ||
          request.headers.get("Authorization") != Some("Bearer \{token}") ||
          request.headers.contains("Origin") {
          conn.send_response(403, "Forbidden")
          conn.end_response()
          return
        }
        let input = @async.with_timeout(5000, () => {
          let chunks : Array[Bytes] = []
          let mut size = 0
          while body.read_some(max_len=4096) is Some(chunk) {
            size += chunk.length()
            guard size <= 65536 else { fail("PTC request exceeds 64 KiB") }
            chunks.push(chunk)
          }
          @json.parse(
            @utf8.decode(
              Bytes::from_array(chunks.map(chunk => chunk.to_array()).flatten()),
            ),
          )
        }) catch {
          error if @async.is_being_cancelled() ||
            @async.is_cancellation_error(error) => raise error
          _ => {
            send(
              conn,
              error_result(
                "Invalid PTC request: expected UTF-8 JSON within 64 KiB and 5 seconds; no tool executed",
              ),
            )
            return
          }
        }
        guard input
          is { "version": 1, "name": String(name), "arguments": arguments, .. } else {
          send(
            conn,
            error_result("PTC requires version=1, name, and arguments"),
          )
          return
        }
        guard calls.length() < 64 else {
          send(conn, error_result("PTC run exhausted its 64-call budget"))
          return
        }
        // Reserve before the first suspension so simultaneous requests cannot
        // exceed the call budget or share a trace index.
        let index = calls.length()
        calls.push({ "name": name, "arguments": arguments, "status": "running" })
        on_trace(trace())
        let result = try {
          match tools.find(name) {
            None =>
              @agent_tool.respond(
                "PTC tool unavailable: \{@agent_tool.brief_line(name, limit=128)}",
                is_error=true,
              )
            Some(tool) =>
              @async.with_timeout(120000, () => {
                if !tool.is_concurrent_safe() {
                  serial.acquire()
                }
                defer (if !tool.is_concurrent_safe() { serial.release() })
                @agent_tool.execute_tool_call(
                  @agent_tool.AgentToolCall::from_arguments(name, arguments),
                  tools,
                )
              })
          }
        } catch {
          error if @async.is_being_cancelled() ||
            @async.is_cancellation_error(error) => {
            calls[index] = {
              "name": name,
              "arguments": arguments,
              "status": "interrupted",
            }
            on_trace(trace())
            raise error
          }
          error =>
            @agent_tool.respond("PTC tool failed: \{error}", is_error=true)
        }
        let response = match result {
          Respond(output) => output_json(output)
          Control(_) =>
            error_result("PTC tool returned unsupported loop control")
        }
        let response = if response.stringify().length() > 65536 {
          error_result(
            "Tool executed, but its result exceeded the PTC 64K character limit. Do not retry a mutation merely to retrieve output.",
          )
        } else {
          response
        }
        calls[index] = {
          "name": name,
          "arguments": arguments,
          "status": "done",
          "result": response,
        }
        on_trace(trace())
        send(conn, response)
      })
    })
    // Closing/cancelling the listener also cancels its child handlers. Joining
    // is essential: returning early could leave a handler editing files.
    defer {
      worker.cancel()
      @async.protect_from_cancel(() => worker.wait() catch { _ => () })
      on_trace(trace())
    }
    let action = program({
      "OPENSEEK_PTC": (
        {
          "version": 1,
          "url": "http://127.0.0.1:\{server.addr.port()}/call",
          "token": token,
        } : Json).stringify(),
    }) catch {
      error if @async.is_being_cancelled() ||
        @async.is_cancellation_error(error) => raise error
      error =>
        @agent_tool.respond("PTC program failed: \{error}", is_error=true)
    }
    // Stop before producing the trace, including a script that sent a request
    // and exited without waiting for its response.
    worker.cancel()
    @async.protect_from_cancel(() => worker.wait() catch { _ => () })
    let interrupted = calls.any(call => call is { "status": "interrupted", .. })
    match action {
      Respond(output) =>
        @agent_tool.respond(
          if interrupted {
            "\{output.content}\nPTC stopped unfinished tool calls; changes may have occurred. Await every call before exiting."
          } else {
            output.content
          },
          is_error=output.is_error || interrupted,
          brief?=output.brief,
          data=trace(),
        )
      Control(_) => action
    }
  }
}

///|
fn error_result(message : String) -> Json {
  { "version": 1, "content": message, "is_error": true }
}

///|
fn output_json(output : @agent_tool.ToolOutput) -> Json {
  let fields : Map[String, Json] = {
    "version": 1,
    "content": output.content.to_json(),
    "is_error": output.is_error.to_json(),
  }
  if output.data is Some(data) {
    fields["data"] = data
  }
  if output.brief is Some(brief) {
    fields["brief"] = brief.to_json()
  }
  Json::object(fields)
}

///|
async fn send(conn : @http.ServerConnection, result : Json) -> Unit {
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json",
  })
  conn.write(result)
  conn.end_response()
}
