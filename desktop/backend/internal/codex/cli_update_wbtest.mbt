///|
#cfg(not(platform="windows"))
async test "CLI update closes old server, preserves home, and reconnects" {
  let root = @fs.tmpdir(prefix="seekmoon-codex-update-")
  defer @fs.rmdir(root, recursive=true)
  let script = root + "/codex"
  let source =
    #|#!/usr/bin/env python3
    #|import json, os, sys
    #|root = os.path.dirname(os.path.abspath(__file__))
    #|assert os.environ.get("CODEX_HOME") == root
    #|with open(root + "/calls", "a") as log:
    #|    log.write(" ".join(sys.argv[1:]) + "\n")
    #|if sys.argv[1:] == ["help", "update"]:
    #|    sys.exit(0)
    #|if sys.argv[1:] == ["update"]:
    #|    assert not os.path.exists(root + "/server-live"), "old server still alive"
    #|    if os.path.exists(root + "/fail-update"):
    #|        print("fixture installer failed", file=sys.stderr)
    #|        sys.exit(7)
    #|    open(root + "/updated", "w").close()
    #|    sys.exit(0)
    #|if sys.argv[1:] == ["--version"]:
    #|    print("codex-cli fixture-new")
    #|    sys.exit(0)
    #|assert sys.argv[1:] == ["app-server"]
    #|import signal
    #|def stopped(*args):
    #|    if os.path.exists(root + "/server-live"):
    #|        os.unlink(root + "/server-live")
    #|    sys.exit(0)
    #|signal.signal(signal.SIGTERM, stopped)
    #|open(root + "/server-live", "w").close()
    #|for line in sys.stdin:
    #|    msg = json.loads(line)
    #|    if "id" not in msg:
    #|        continue
    #|    if msg.get("method") in ["test/start", "test/finish"]:
    #|        event = "turn/started" if msg["method"] == "test/start" else "turn/completed"
    #|        print(json.dumps({"method": event, "params": {"threadId": "background-thread"}}), flush=True)
    #|    result = {"updated": os.path.exists(root + "/updated")}
    #|    print(json.dumps({"id": msg["id"], "result": result}), flush=True)
    #|stopped()
  @fs.write_file(script, source, permission=0o700)
  @async.with_timeout(15000, () => {
    @async.with_task_group(group => {
      let actor = Actor(CodexSettings(command=script, home=Some(Path(root))))
      group.spawn_bg(no_wait=true, () => actor.run((_, _) => ()))
      let before = actor.call(method_="model/list", params=Json::empty_object())
      assert_true(before is { "updated": false, .. })
      ignore(actor.call(method_="test/start", params=Json::empty_object()))
      let blocked = try {
        ignore(actor.update_cli())
        false
      } catch {
        CodexError::Unavailable(message) =>
          message.contains("Finish running Codex tasks")
        _ => false
      }
      assert_true(blocked)
      assert_false(@fs.exists(root + "/updated"))
      ignore(actor.call(method_="test/finish", params=Json::empty_object()))
      @fs.write_file(root + "/fail-update", "fail")
      let failed = try {
        ignore(actor.update_cli())
        false
      } catch {
        error => error.to_string().contains("fixture installer failed")
      }
      assert_true(failed)
      let recovered = actor.call(
        method_="model/list",
        params=Json::empty_object(),
      )
      assert_true(recovered is { "updated": false, .. })
      @fs.remove(root + "/fail-update")
      let updated = actor.update_cli()
      assert_true(updated is { "version": "codex-cli fixture-new", .. })
      let after = actor.call(method_="model/list", params=Json::empty_object())
      assert_true(after is { "updated": true, .. })
      assert_eq(
        @fs.read_file(root + "/calls").text(),
        "app-server\nhelp update\nupdate\napp-server\nhelp update\nupdate\n--version\napp-server\n",
      )
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "unsupported CLI update never runs a bare update prompt" {
  let root = @fs.tmpdir(prefix="seekmoon-codex-old-")
  defer @fs.rmdir(root, recursive=true)
  let script = root + "/codex"
  let source =
    #|#!/bin/sh
    #|if [ "$1" = help ] && [ "$2" = update ]; then
    #|  echo 'unknown subcommand update' >&2
    #|  exit 2
    #|fi
    #|echo 'unexpected command' >&2
    #|exit 99
  @fs.write_file(script, source, permission=0o700)
  let result = try {
    ignore(CodexSettings(command=script, home=None).update_cli())
    None
  } catch {
    error => Some(error.to_string())
  }
  assert_true(
    result is Some(message) &&
    message.contains("Could not verify Codex CLI update support"),
  )
}

///|
test "CLI update follows platform command resolution" {
  assert_eq(
    cli_launch("codex", ["update"], windows=true),
    ("cmd.exe", ["/d", "/c", "codex", "update"]),
  )
  assert_eq(
    cli_launch("/custom/codex", ["update"], windows=false),
    ("/custom/codex", ["update"]),
  )
}

///|
#cfg(not(platform="windows"))
async test "CLI update returns command failure output" {
  let root = @fs.tmpdir(prefix="seekmoon-codex-failed-")
  defer @fs.rmdir(root, recursive=true)
  let script = root + "/codex"
  let source =
    #|#!/bin/sh
    #|if [ "$1" = help ]; then exit 0; fi
    #|echo 'installer output'
    #|echo 'permission denied' >&2
    #|exit 7
  @fs.write_file(script, source, permission=0o700)
  let error = try {
    ignore(CodexSettings(command=script, home=None).update_cli())
    None
  } catch {
    error => Some(error.to_string())
  }
  assert_true(
    error is Some(message) &&
    message.contains("code 7") &&
    message.contains("permission denied") &&
    message.contains("installer output"),
  )
}
