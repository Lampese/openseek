///|
/// One session-owned listener. Every program has an independent capability.
struct Service {
  server : @http.Server
  tools : @agent_tool.Tools
  programs : Map[String, Program]
  serial : @async.Mutex
  spawn : (async () -> Json) -> @async.Task[Json]
  mut stop : (async () -> Unit)?
  mut closed : Bool
}

///|
/// A script's capability and trace, retained by its job after background handoff.
struct Program {
  environment : Map[String, String]
  calls : Array[Json]
  reservations : Array[Int]
  mut trace_bytes : Int
  active : Map[Int, @async.Task[Json]]
  serial : @async.Mutex
  revoke : () -> Unit
  mut closed : Bool
  mut on_trace : async (Json) -> Unit
}

///|
/// Start a listener on the existing session task group. No agent-loop dispatch
/// or file lock is held while the listener waits for requests.
pub async fn[X] Service::start(
  group : @async.TaskGroup[X],
  tools : @agent_tool.Tools,
) -> Service {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let service : Service = {
    server,
    tools: tools.program_tools(),
    programs: Map([]),
    serial: Mutex(),
    spawn: operation => group.spawn(operation, no_wait=true, allow_failure=true),
    stop: None,
    closed: false,
  }
  let worker = group.spawn(no_wait=true, () => {
    server.run_forever(max_connections=16, allow_failure=true, (
      request,
      body,
      conn,
    ) => {
      defer conn.close()
      let program = match request.headers.get("Authorization") {
        Some(header) if header is [.. "Bearer ", .. token] =>
          service.programs.get(token.to_owned())
        _ => None
      }
      guard request.meth == Post &&
        request.path == "/call" &&
        !request.headers.contains("Origin") &&
        program is Some(program) else {
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
      // Recheck after the body read: close may have revoked this capability
      // while the request was suspended. Registration and reservation never yield.
      guard !program.closed else {
        send(conn, error_result("PTC program has ended; no tool executed"))
        return
      }
      guard input
        is { "version": 1, "name": String(name), "arguments": arguments, .. } else {
        send(conn, error_result("PTC requires version=1, name, and arguments"))
        return
      }
      guard program.calls.length() < 64 && program.active.length() < 4 else {
        send(
          conn,
          error_result(
            "PTC program exhausted its 64-call or four-active-call budget",
          ),
        )
        return
      }
      let index = program.calls.length()
      let entry : Json = {
        "name": name,
        "arguments": arguments,
        "status": "running",
      }
      // Leave space for terminal status and an explicit omitted-result marker.
      let reservation = @utf8.encode(entry.stringify()).length() + 1024
      guard program.trace_bytes + reservation <= 524288 else {
        send(conn, error_result("PTC trace budget exhausted; no tool executed"))
        return
      }
      program.calls.push(entry)
      program.reservations.push(reservation)
      program.trace_bytes += reservation
      let task = (service.spawn)(() => {
        program.execute(service.tools, index, name, arguments)
      })
      program.active[index] = task
      defer program.active.remove(index)
      // Cancellation of this HTTP handler must not orphan its executor.
      errdefer {
        task.cancel()
        @async.protect_from_cancel(() => ignore(task.wait()) catch { _ => () })
      }
      send(conn, task.wait())
    })
  })
  service.stop = Some(() => {
    worker.cancel()
    @async.protect_from_cancel(() => worker.wait() catch { _ => () })
  })
  group.add_defer(() => service.close())
  service
}

///|
/// Register a fresh capability without changing the script's source.
pub fn Service::register(
  self : Service,
  on_trace? : (Json) -> Unit = _ => (),
) -> Program raise {
  guard !self.closed else { fail("PTC service is closed") }
  guard self.programs.length() < 64 else {
    fail("PTC session has 64 active programs")
  }
  guard @env.rand(32) is Some(entropy) else {
    fail("PTC: secure random capability unavailable")
  }
  let token = @crypto.bytes_to_hex_string(entropy)
  let program : Program = {
    environment: {
      "OPENSEEK_PTC": (
        {
          "version": 1,
          "url": "http://127.0.0.1:\{self.server.addr.port()}/call",
          "token": token,
        } : Json).stringify(),
    },
    calls: [],
    reservations: [],
    trace_bytes: 0,
    active: Map([]),
    serial: self.serial,
    revoke: () => self.programs.remove(token),
    closed: false,
    on_trace: data => on_trace(data),
  }
  self.programs[token] = program
  program
}

///|
/// Revoke all capabilities and join their executors before closing the listener.
pub async fn Service::close(self : Service) -> Unit {
  self.closed = true
  @async.protect_from_cancel(() => {
    let programs = self.programs.values().to_array()
    for program in programs {
      program.closed = true
    }
    self.programs.clear()
    for program in programs {
      program.close()
    }
    if self.stop is Some(stop) {
      self.stop = None
      stop()
    }
    self.server.close()
  })
}

///|
/// Guest environment for this script only.
pub fn Program::env(self : Program) -> Map[String, String] {
  self.environment.copy()
}

///|
/// Immutable bounded trace, without credentials or transport details.
pub fn Program::trace(self : Program) -> Json {
  { "ptc_calls": self.calls.to_json() }
}

///|
/// Replace the foreground observer when the execution becomes a job.
pub fn Program::observe(
  self : Program,
  observer : async (Json) -> Unit,
) -> Unit {
  if !self.closed {
    self.on_trace = observer
  }
}

///|
/// True when execution ended with unfinished calls; changes may have occurred.
pub fn Program::interrupted(self : Program) -> Bool {
  self.calls.any(call => call is { "status": "interrupted", .. })
}

///|
/// Revoke before the first suspension, then cancel and join without holding a
/// file gate. Idempotent callers all wait for the same active calls to finish.
pub async fn Program::close(self : Program) -> Unit {
  self.closed = true
  (self.revoke)()
  @async.protect_from_cancel(() => {
    // Release the job observer (which captures the runtime) after final data.
    defer {
      self.on_trace = _ => ()
    }
    let tasks = self.active.values().to_array()
    for task in tasks {
      task.cancel()
    }
    for task in tasks {
      ignore(task.wait()) catch {
        _ => ()
      }
    }
    // A task cancelled before it started never entered its exception handler.
    for i, call in self.calls {
      if call
        is { "name": name, "arguments": arguments, "status": "running", .. } {
        self.calls[i] = {
          "name": name,
          "arguments": arguments,
          "status": "interrupted",
        }
      }
    }
    self.active.clear()
    (self.on_trace)(self.trace())
  })
}

///|
async fn Program::execute(
  self : Program,
  tools : @agent_tool.Tools,
  index : Int,
  name : String,
  arguments : Json,
) -> Json {
  let result = try {
    (self.on_trace)(self.trace())
    match tools.find(name) {
      None =>
        @agent_tool.respond(
          "PTC tool unavailable: \{@agent_tool.brief_line(name, limit=128)}",
          is_error=true,
        )
      Some(tool) =>
        @async.with_timeout(120000, () => {
          if !tool.is_concurrent_safe() {
            self.serial.acquire()
          }
          defer (if !tool.is_concurrent_safe() { self.serial.release() })
          @agent_tool.execute_tool_call(
            @agent_tool.AgentToolCall::from_arguments(name, arguments),
            tools,
          )
        })
    }
  } catch {
    error if @async.is_being_cancelled() || @async.is_cancellation_error(error) => {
      self.calls[index] = {
        "name": name,
        "arguments": arguments,
        "status": "interrupted",
      }
      @async.protect_from_cancel(() => (self.on_trace)(self.trace()))
      raise error
    }
    error => @agent_tool.respond("PTC tool failed: \{error}", is_error=true)
  }
  let response = match result {
    Respond(output) => output_json(output)
    Control(_) => error_result("PTC tool returned unsupported loop control")
  }
  let response = if response.stringify().length() > 65536 {
    error_result(
      "Tool executed, but its result exceeded the PTC 64K character limit. Do not retry a mutation merely to retrieve output.",
    )
  } else {
    response
  }
  let entry : Json = {
    "name": name,
    "arguments": arguments,
    "status": "done",
    "result": response,
  }
  let size = @utf8.encode(entry.stringify()).length()
  if self.trace_bytes - self.reservations[index] + size <= 524288 {
    self.trace_bytes += size - self.reservations[index]
    self.reservations[index] = size
    self.calls[index] = entry
  } else {
    // The client still receives the full bounded response. Retained job
    // metadata must fit the existing 1 MiB durable-record reader.
    self.calls[index] = {
      "name": name,
      "arguments": arguments,
      "status": "done",
      "result": {
        "version": 1,
        "content": "Result omitted from retained trace: trace size limit reached",
        "is_error": match response {
          { "is_error": value, .. } => value
          _ => true
        },
        "trace_truncated": true,
      },
    }
  }
  (self.on_trace)(self.trace())
  response
}

///|
/// Foreground-only bracket used by standalone hosts without a session service.
pub async fn run(
  tools : @agent_tool.Tools,
  program : async (Map[String, String]) -> @agent_tool.ToolAction,
  on_trace? : (Json) -> Unit = _ => (),
) -> @agent_tool.ToolAction {
  @async.with_task_group(group => {
    let service = Service::start(group, tools)
    let registration = service.register(on_trace~)
    defer registration.close()
    let action = program(registration.env()) catch {
      error if @async.is_being_cancelled() ||
        @async.is_cancellation_error(error) => raise error
      error =>
        @agent_tool.respond("PTC program failed: \{error}", is_error=true)
    }
    registration.close()
    match action {
      Respond(output) =>
        @agent_tool.respond(
          if registration.interrupted() {
            "\{output.content}\nPTC stopped unfinished tool calls; changes may have occurred. Await every call before exiting."
          } else {
            output.content
          },
          is_error=output.is_error || registration.interrupted(),
          brief?=output.brief,
          data=registration.trace(),
        )
      Control(_) => action
    }
  })
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
  @async.with_timeout(5000, () => {
    conn.send_response(200, "OK", extra_headers={
      "Content-Type": "application/json",
    })
    conn.write(result)
    conn.end_response()
  })
}
