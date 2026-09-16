///|
/// Lay a complete bundled resource root — documentation and workflows — at
/// `directory`.
async fn write_resource_root(directory : String) -> Unit {
  @fs.mkdir(
    @workspace_path.join_child(directory, "doc/moonbit"),
    recursive=true,
  )
  @fs.mkdir(@workspace_path.join_child(directory, "workflow"), recursive=true)
}

///|
async test "a share directory beside the binaries is the resource root" {
  let tmp = @fs.tmpdir(prefix="openseek-references-install-")
  defer (@fs.rmdir(tmp, recursive=true) catch { _ => () })
  let share = @workspace_path.join_child(tmp, "share")
  write_resource_root(share)
  let bin = @workspace_path.join_child(tmp, "bin")
  @fs.mkdir(bin)
  assert_eq(root_for_exe_dir(bin), Some(share))
}

///|
async test "the packaged app finds the per-platform toolchain share" {
  let tmp = @fs.tmpdir(prefix="openseek-references-bundle-")
  defer (@fs.rmdir(tmp, recursive=true) catch { _ => () })
  let seekmoon = @workspace_path.join_child(tmp, "seekmoon")
  let share = @workspace_path.join_child(
    seekmoon, "toolchains/moonbit/macos-arm64/share",
  )
  write_resource_root(share)
  let bin = @workspace_path.join_child(seekmoon, "bin")
  @fs.mkdir(bin, recursive=true)
  // The bundle root holds no `share/` of its own, and the platform directory
  // packaging chose must not matter: every candidate is probed.
  assert_eq(root_for_exe_dir(bin), Some(share))
}

///|
async test "the nearest resource root wins" {
  let tmp = @fs.tmpdir(prefix="openseek-references-nearest-")
  defer (@fs.rmdir(tmp, recursive=true) catch { _ => () })
  let outer = @workspace_path.join_child(tmp, "share")
  let inner = @workspace_path.join_child(tmp, "nested/share")
  write_resource_root(outer)
  write_resource_root(inner)
  let bin = @workspace_path.join_child(tmp, "nested/bin")
  @fs.mkdir(bin, recursive=true)
  assert_eq(root_for_exe_dir(bin), Some(inner))
}

///|
async test "an incomplete share directory is not a resource root" {
  let tmp = @fs.tmpdir(prefix="openseek-references-partial-")
  defer (@fs.rmdir(tmp, recursive=true) catch { _ => () })
  // Documentation without workflows is some other `share/` tree — a MoonBit
  // toolchain's own, for instance — not this installation's resources.
  let partial = @workspace_path.join_child(tmp, "share")
  @fs.mkdir(@workspace_path.join_child(partial, "doc/moonbit"), recursive=true)
  assert_false(is_resource_root(partial))
  let bin = @workspace_path.join_child(tmp, "bin")
  @fs.mkdir(bin)
  assert_true(root_for_exe_dir(bin) is None)
}
