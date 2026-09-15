///|
/// Serialize updates with the app-server owner, including requests from other
/// connected frontends. The actor tears down its old child before updating.
pub async fn Actor::update_cli(self : Actor) -> Json {
  guard !self.updating else {
    raise CodexError::Unavailable("Codex CLI update is already running")
  }
  self.updating = true
  let reply : @async.Queue[Result[Json, CodexError]] = Queue(kind=Blocking(1))
  self.inputs.put(UpdateCli(reply))
  self.signal()
  match reply.get() {
    Ok(value) => value
    Err(error) => raise error
  }
}

///|
fn Actor::record_activity(
  self : Actor,
  method_ : String,
  params : Json,
) -> Unit {
  if params is { "threadId": String(id), .. } {
    match method_ {
      "turn/started" => self.active_threads[id] = true
      "turn/completed" => self.active_threads.remove(id)
      "thread/status/changed" =>
        if params is { "status": { "type": String("active"), .. }, .. } {
          self.active_threads[id] = true
        } else {
          self.active_threads.remove(id)
        }
      _ => ()
    }
  }
}

///|
/// Reuse the same command and login-shell environment as app-server launch.
/// EOF stdin prevents a GUI update from waiting indefinitely for a prompt.
async fn CodexSettings::update_cli(self : CodexSettings) -> Json {
  @async.with_timeout(300000, () => {
    let env = match self.home {
      Some(home) => Map([("CODEX_HOME", home.to_string())])
      None => Map([])
    }
    // Older CLIs may interpret an unknown bare word as an interactive prompt.
    // The explicit help subcommand fails safely when update is unsupported.
    let (command, args) = cli_launch(
      self.command,
      ["help", "update"],
      windows=@platform.win32 || @platform.win64,
    )
    let (code, _, stderr) = @processx.collect_output_no_stdin(
      command,
      args,
      extra_env=env,
    )
    guard code == 0 else {
      raise RequestFailed(
        method_="cli/update",
        detail="Could not verify Codex CLI update support. If this CLI is too old, update it manually with its original installer. \{stderr.text()}",
      )
    }
    let (command, args) = cli_launch(
      self.command,
      ["update"],
      windows=@platform.win32 || @platform.win64,
    )
    let (code, stdout, stderr) = @processx.collect_output_no_stdin(
      command,
      args,
      extra_env=env,
    )
    guard code == 0 else {
      raise RequestFailed(
        method_="cli/update",
        detail="codex update exited with code \{code}:\n\{stderr.text()}\n\{stdout.text()}",
      )
    }
    let (command, args) = cli_launch(
      self.command,
      ["--version"],
      windows=@platform.win32 || @platform.win64,
    )
    let (code, stdout, stderr) = @processx.collect_output_no_stdin(
      command,
      args,
      extra_env=env,
    )
    guard code == 0 else {
      raise RequestFailed(
        method_="cli/update",
        detail="Update completed, but reading the CLI version failed: \{stderr.text()}",
      )
    }
    let version = stdout.text().trim().to_owned()
    guard !version.is_empty() else {
      raise RequestFailed(
        method_="cli/update",
        detail="Update completed, but the CLI returned an empty version",
      )
    }
    { "version": Json(version) }
  })
}
