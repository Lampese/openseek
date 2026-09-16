///|
/// Where a bundled resource root sits inside an installation, relative to the
/// executable's own directory and to each of its ancestors. The first is a
/// plain install — a `share/` beside the `bin/` directory holding the binary.
/// The rest are the packaged desktop tree, where each platform's MoonBit
/// toolchain carries the resources in its own `share/`, so moving the bundle or
/// relaunching an AppImage cannot strand a recorded path.
let resource_root_relatives : Array[String] = [
  "share", "toolchains/moonbit/macos-arm64/share", "toolchains/moonbit/linux-x64/share",
  "toolchains/moonbit/windows-x64/share",
]

///|
/// The read-only bundled resource root (**`share/`**: `doc/moonbit/` and
/// `workflow/`) of the installation `exe_dir` belongs to, or `None` when this
/// executable ships no bundled resources — a source build, or a bare CLI
/// install.
///
/// The nearest ancestor of `exe_dir` holding a complete root wins. One walk
/// covers every layout an executable can be installed in: a plain prefix
/// install keeps `share/` beside `bin/`, the packaged desktop app keeps it in
/// its per-platform toolchain, and a source checkout develops against the
/// repository's own `share/` several levels above the tested artifact.
async fn root_for_exe_dir(exe_dir : String) -> String? {
  for relative in resource_root_relatives {
    let candidate = @workspace_path.join_child(exe_dir, relative)
    if is_resource_root(candidate) {
      return Some(candidate)
    }
  }
  match @workspace_path.parent_dir(exe_dir) {
    Some(parent) if parent != exe_dir => root_for_exe_dir(parent)
    _ => None
  }
}

///|
/// Whether `directory` is a complete bundled resource root. The documentation
/// and the workflows ship together, so a directory holding only one of them
/// belongs to someone else — a MoonBit toolchain's own `share/`, for instance —
/// and must not be advertised as this installation's resources.
async fn is_resource_root(directory : String) -> Bool {
  @fs.exists(@workspace_path.join_child(directory, "doc/moonbit")) &&
  @fs.exists(@workspace_path.join_child(directory, "workflow"))
}

///|
/// The running installation's bundled resource root, or `None` when it ships
/// none. This is the one answer to "where are the bundled references", shared
/// by the system prompt that names the directory and the `@builtin/` scripts
/// that read from it.
///
/// Resolved from the executable itself, never from the environment: the
/// resources travel with the binary the engine runs as, so a moved, updated, or
/// freshly mounted installation is followed instead of a path that outlives it.
pub async fn root() -> String? {
  let exe_dir = @exe.current_exe_dir() catch { _ => return None }
  root_for_exe_dir(exe_dir)
}
