///|
/// The session this run records to: the explicit `--session` id, a generated
/// `cli-<stamp>-<salt>` id by default, or `None` under `--no-session`.
///
/// One-shot runs record by default because "what did the agent actually do?"
/// is asked after the run, when an unrecorded answer is gone for good; the
/// recording is a small JSONL directory under --session-root, and the
/// deferred first write means a run that fails before its first event still
/// leaves nothing behind. `--no-session` restores the ephemeral behavior for
/// callers that must not write to the workspace; combining it with an
/// explicit `--session` is a contradiction that command validation rejects up front
/// for every mode (this helper repeats the check as defense in depth).
///
/// The generated id carries a random salt: two timestamp-only ids collide
/// when a parallel driver launches two bare CLI runs in the same
/// millisecond under one session root, and the colliding runs would append
/// to each other's conversation (Codex review).
pub async fn resolved_session_id(
  matches : @argparse.Matches,
) -> @agent_session.SessionId? {
  let (session, no_session) = match matches {
    {
      values: {
        "session"? : Some([session, ..])
        | (Some([]) | None with session = ""),
        ..
      },
      flags: {
        "no-session"? : Some(no_session)
        | (None with no_session = false),
        ..
      },
      ..
    } => (session.trim(), no_session)
  }
  let session_id = match session {
    "" => None
    session => Some(@agent_session.SessionId("\{session}"))
  }
  match (session_id, no_session) {
    (Some(_), true) =>
      fail("--no-session contradicts --session; pick one behavior")
    (Some(id), false) => Some(id)
    (None, true) => None
    (None, false) =>
      Some(
        @agent_session.SessionId::generated(
          prefix="cli",
          now_ms=@env.now().reinterpret_as_int64(),
          salt=random_salt(),
        ),
      )
  }
}

///|
/// A short random token, or "" where none can be produced (the timestamp
/// alone then still names the session, as before).
///
/// The entropy comes from `mkdtemp` via `@fs.tmpdir`: the kernel arbitrates
/// the random suffix to be unique across concurrent processes — exactly the
/// guarantee two same-millisecond launches need — and the async runtime
/// cannot read `/dev/urandom` directly (character devices are not
/// pollable). The probe directory is removed immediately, and the suffix is
/// filtered to alphanumerics (platforms decorate it with pid and dots).
pub async fn random_salt() -> String {
  let prefix = "openseek-salt-"
  let dir = @fs.tmpdir(prefix~) catch { _ => return "" }
  @fs.rmdir(dir) catch {
    _ => ()
  }
  // Locate the prefix instead of splitting on a path separator: Windows
  // paths use backslashes, and a `/`-only basename split would drop the
  // salt there entirely (Codex review).
  guard dir.rev_split_once(prefix) is Some((_, suffix)) else { return "" }
  let salt = StringBuilder()
  for ch in suffix {
    if ch is ('0'..='9' | 'a'..='z' | 'A'..='Z') {
      salt <+ "\{ch}"
    }
  }
  salt.to_string()
}

///|
/// Resolve the configured session store relative to the workspace, rejecting an empty path.
pub fn session_root(
  matches : @argparse.Matches,
  workspace_root? : String = ".",
) -> String raise {
  let root = match matches {
    { values: { "session-root": [root, ..], .. }, .. } => root.trim().to_owned()
    _ => fail("missing parsed argument: session-root")
  }
  guard !root.is_empty() else { fail("--session-root must not be empty") }
  @workspace_path.resolve(workspace_root, root)
}

///|
/// Load a durable session or prepare a fresh one without writing until its first append.
pub async fn load_or_new_session(
  store : @store.SessionStore,
  id : @agent_session.SessionId,
  matches : @argparse.Matches,
  model : @deepseek.Model,
  workspace_root? : String = ".",
) -> @agent_session.Session {
  // The prompt is built only when actually creating a fresh session: a
  // re-load must not read prompt files again.
  async fn fresh() -> @agent_session.Session {
    Session(
      id,
      system_prompt=configured_system_prompt(matches, model, workspace_root~),
    )
  }

  if store.exists(id) {
    store.load(id) catch {
      @os_error.OSError(_) as error if error.is_ENOENT() => fresh()
      error => raise error
    }
  } else {
    fresh()
  }
}

///|
/// Keeps a session's durable settings (`settings.json`, beside its
/// transcript) in step with what this process actually runs with — today the
/// model. Every durable append goes through it: after the append it reads
/// the settings back and writes only the keys whose value differs from what
/// this process wants. A session already in step costs no writes; a session
/// another process configured differently is corrected by the process
/// running it; and the very first append of a new session, which creates the
/// record, is immediately followed by its settings — there is no earlier
/// moment, since settings need a record to sit beside.
///
/// The read is one small file per append, dwarfed by the append's own
/// fdatasync, and it is what lets this hold no state of its own: whether a
/// write is due is asked of the disk, not remembered.
struct SettingsUpdater {
  store : @store.SessionStore
  desired : Map[String, Json]
}

///|
/// An updater that holds the session at `desired` — the settings keys this
/// process is the authority on. Keys it does not name are never touched.
pub fn SettingsUpdater::SettingsUpdater(
  store : @store.SessionStore,
  desired : Map[String, Json],
) -> SettingsUpdater {
  { store, desired, }
}

///|
/// The settings a run with `model` is the authority on: `model`, as its
/// wire name — the same string the desktop's chip parses.
pub fn run_settings(model : @deepseek.Model) -> Map[String, Json] {
  { "model": Json("\{model}") }
}

///|
/// Append one event durably, then bring the settings into step. A failed
/// settings read or write is reported as a session error and never fails
/// the append it followed — the transcript is the substance.
pub async fn SettingsUpdater::append(
  self : SettingsUpdater,
  session : @agent_session.Session,
  item : @agent_session.SessionItem,
) -> @agent_session.Session {
  let next = self.store.append(session, item)
  self.sync(next.id()) catch {
    error if @async.is_being_cancelled() || @async.is_cancellation_error(error) =>
      raise error
    error =>
      @emit.emit(
        SessionError(error="failed to update the session settings: \{error}"),
      )
  }
  next
}

///|
async fn SettingsUpdater::sync(
  self : SettingsUpdater,
  id : @agent_session.SessionId,
) -> Unit {
  let current = self.store.settings(id)
  for key, value in self.desired {
    if current.get(key) != Some(value) {
      self.store.set_setting(id, key, value)
    }
  }
}
