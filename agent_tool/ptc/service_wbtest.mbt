///|
async test "session listener reuses its port with isolated revocable capabilities" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let tool = @agent_tool.AgentToolDefinition(
        name="echo",
        description="echo",
        schema=JsonSchema({}),
        program_callable=true,
        concurrent_safe=true,
        execute=Sync(arguments => @agent_tool.respond("ok", data=arguments)),
      )
      let service = Service::start(group, Tools([tool]))
      let foreground : Array[Json] = []
      let background : Array[Json] = []
      let first = service.register(on_trace=data => foreground.push(data))
      let second = service.register()
      guard @json.parse(first.env()["OPENSEEK_PTC"])
        is { "url": String(url), "token": String(token), .. } else {
        fail("first capability")
      }
      guard @json.parse(second.env()["OPENSEEK_PTC"])
        is { "url": String(other_url), "token": String(other_token), .. } else {
        fail("second capability")
      }
      assert_eq(url, other_url)
      assert_true(token != other_token)
      ignore(request(first.env(), "echo", { "owner": "first" }))
      let foreground_count = foreground.length()
      first.observe(data => background.push(data))
      ignore(request(first.env(), "echo", { "owner": "background" }))
      ignore(request(second.env(), "echo", { "owner": "second" }))
      assert_eq(foreground.length(), foreground_count)
      assert_eq(background.length(), 2)
      assert_true(
        first.trace()
        is {
          "ptc_calls": [_, { "arguments": { "owner": "background", .. }, .. }],
          ..
        },
      )
      assert_true(
        second.trace()
        is { "ptc_calls": [{ "arguments": { "owner": "second", .. }, .. }], .. },
      )
      first.close()
      let (response, body) = @http.post(url, ({} : Json), headers={
        "Authorization": "Bearer \{token}",
      })
      ignore(body.text())
      assert_eq(response.code, 403)
      assert_true(
        request(second.env(), "echo", {}) is { "is_error": false, .. },
      )
      second.close()
      assert_true(service.programs.is_empty())
    })
  })
}

///|
async test "closing queued and running RPC calls does not deadlock the shared file gate" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let state = @agent_tool.FileStateMap()
      let entered : @async.Queue[Unit] = Queue(kind=Unbounded)
      let release : @async.Queue[Unit] = Queue(kind=Unbounded)
      let journal : Array[String] = []
      let tool = state.serialize(
        AgentToolDefinition(
          name="edit",
          description="file gate probe",
          schema=JsonSchema({}),
          program_callable=true,
          execute=Async(arguments => {
            guard arguments is { "id": String(id), .. } else {
              fail("missing id")
            }
            journal.push(id)
            if id == "running" {
              entered.put(())
              release.get()
            }
            @agent_tool.respond("done")
          }),
        ),
      )
      let tools = @agent_tool.Tools([tool])
      let service = Service::start(group, tools)
      let running = service.register()
      let queued = service.register()
      let first = group.spawn(
        () => request(running.env(), "edit", { "id": "running" }),
        allow_failure=true,
      )
      entered.get()
      let second = group.spawn(
        () => request(queued.env(), "edit", { "id": "queued" }),
        allow_failure=true,
      )
      while queued.calls.is_empty() {
        @async.sleep(1)
      }
      queued.close()
      assert_true(queued.interrupted())
      let direct = group.spawn(() => {
        @agent_tool.execute_tool_call(
          @agent_tool.AgentToolCall::from_arguments("edit", { "id": "direct" }),
          tools,
        )
      })
      running.close()
      assert_true(running.interrupted())
      assert_true(direct.wait() is Respond({ is_error: false, .. }))
      ignore(first.wait()) catch {
        _ => ()
      }
      ignore(second.wait()) catch {
        _ => ()
      }
      assert_eq(journal, ["running", "direct"])
    })
  })
}

///|
async test "session teardown joins active calls and revokes all registrations" {
  let stopped = Ref(false)
  let retained : Ref[Program?] = Ref(None)
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let entered : @async.Queue[Unit] = Queue(kind=Unbounded)
      let tool = @agent_tool.AgentToolDefinition(
        name="block",
        description="block",
        schema=JsonSchema({}),
        program_callable=true,
        execute=Async(_ => {
          defer {
            stopped.val = true
          }
          entered.put(())
          @async.sleep(60000)
          @agent_tool.respond("unexpected")
        }),
      )
      let service = Service::start(group, Tools([tool]))
      let program = service.register()
      retained.val = Some(program)
      group.spawn_bg(
        () => ignore(request(program.env(), "block", {})),
        no_wait=true,
        allow_failure=true,
      )
      entered.get()
    })
  })
  assert_true(stopped.val)
  assert_true(
    retained.val is Some(program) && program.closed && program.interrupted(),
  )
}

///|
async test "retained trace stays within job record bounds without truncating client replies" {
  @async.with_task_group(group => {
    let text = "x".repeat(50000)
    let tool = @agent_tool.AgentToolDefinition(
      name="large",
      description="large",
      schema=JsonSchema({}),
      program_callable=true,
      execute=Sync(_ => @agent_tool.respond(text)),
    )
    let service = Service::start(group, Tools([tool]))
    let program = service.register()
    for _ in 0..<16 {
      assert_true(
        request(program.env(), "large", {})
        is { "content": String(content), .. } &&
        content == text,
      )
    }
    let trace = program.trace()
    assert_true(@utf8.encode(trace.stringify()).length() < 530000)
    guard trace is { "ptc_calls": Array(calls), .. } else {
      fail("missing calls")
    }
    assert_eq(calls.length(), 16)
    assert_true(
      calls.any(call => {
        call is { "result": { "trace_truncated": true, .. }, .. }
      }),
    )
    program.close()
  })
}
