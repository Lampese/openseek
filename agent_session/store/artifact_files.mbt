///|
/// Prospective output path inside the session's existing scratch directory.
/// No extra storage root or session-directory mapping is required. Reads do
/// not create it; mbtx creates it when preparing an execution environment.
pub async fn SessionStore::artifact_dir(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> String {
  self.scratch_dir(id) + "/artifact"
}

///|
async fn validate_artifact_directory(
  scratch : String,
  directory : String,
) -> Unit {
  guard @fs.kind(scratch, follow_symlink=false) is Directory &&
    @fs.kind(directory, follow_symlink=false) is Directory else {
    fail("artifact directory must stay inside this conversation's scratch")
  }
}

///|
/// Resolve only a regular file inside this session's scratch/artifact subtree.
/// A symlink cannot redirect a reference into another conversation's files.
pub async fn SessionStore::artifact_file(
  self : SessionStore,
  id : @agent_session.SessionId,
  reference : String,
) -> String {
  guard @workspace_file_ref.artifact_path(reference) is Some(relative) else {
    fail("invalid artifact reference")
  }
  let directory = self.artifact_dir(id)
  validate_artifact_directory(self.scratch_dir(id), directory)
  let root = @fs.realpath(directory)
  let target = @fs.realpath("\{root}/\{relative}")
  guard target.has_prefix(root + "/") || target.has_prefix(root + "\\") else {
    fail("artifact reference escapes its conversation")
  }
  guard @fs.kind(target) is Regular else {
    fail("artifact is not a regular file")
  }
  target
}

///|
async fn copy_artifact_tree(source : String, destination : String) -> Unit {
  for name in @fs.readdir(source, include_hidden=true) {
    let from = "\{source}/\{name}"
    let to = "\{destination}/\{name}"
    match @fs.kind(from, follow_symlink=false) {
      Directory => {
        @fs.mkdir(to)
        copy_artifact_tree(from, to)
      }
      Regular => @fs.write_file(to, @fs.read_file(from), create_mode=CreateNew)
      _ =>
        fail(
          "cannot fork an artifact bundle containing a symlink or special file",
        )
    }
  }
}
