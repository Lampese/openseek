///|
#deprecated("Use greet instead")
pub fn old_greet() -> String {
  greet()
}

///|
fn greet() -> String {
  "hello"
}

///|
test "greeting" {
  assert_eq(old_greet(), "hello")
  assert_eq(old_greet(), "hello")
}
