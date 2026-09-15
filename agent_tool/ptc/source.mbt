///|
/// Add the bundled client. Existing import blocks retain their line count;
/// scripts without imports gain one import line. Helpers follow user code.
/// The aliases are reserved only in ptc=true scripts.
pub fn prepare_source(source : String) -> String {
  let at = skip_trivia(source, 0)
  let brace = if source.clamped_view(start=at).has_prefix("import") {
    let brace = skip_trivia(source, at + 6)
    if source.get_char(brace) is Some('{') {
      Some(brace)
    } else {
      None
    }
  } else {
    None
  }
  let aliases = match brace {
    Some(pos) => import_aliases(source, pos + 1)
    None => Map([])
  }
  let imports = StringBuilder()
  let mut client = client_source()
  for
    (path, reserved) in [
      ("moonbitlang/async", "ptc_async"),
      ("moonbitlang/async/http", "ptc_http"),
      ("moonbitlang/core/env", "ptc_env"),
      ("moonbitlang/core/json", "ptc_json"),
    ] {
    match aliases.get(path) {
      Some(local_name) =>
        client = client.replace_all(old="@\{reserved}.", new="@\{local_name}.")
      None => imports.write_string("\"\{path}\" @\{reserved}, ")
    }
  }
  let source = match brace {
    Some(pos) =>
      "\{source.clamped_view(end=pos + 1)} \{imports}\{source.clamped_view(start=pos + 1)}"
    None => "import { \{imports} }\n\{source}"
  }
  "\{source}\n\n\{client}"
}

///|
/// Read only the front-matter import list. The compiler remains responsible
/// for validating syntax. Respect user aliases rather than importing a package
/// twice: moon's single-file resolver retains only one alias per package.
fn import_aliases(source : String, start : Int) -> Map[String, String] {
  let aliases : Map[String, String] = Map([])
  for pos = start; pos < source.length(); {
    let pos = skip_trivia(source, pos)
    if source.get_char(pos) is Some(',') {
      continue pos + 1
    }
    guard source.get_char(pos) is Some('"') else { break }
    guard source.clamped_view(start=pos + 1).find("\"") is Some(length) else {
      break
    }
    let path = source
      .clamped_view(start=pos + 1, end=pos + 1 + length)
      .to_owned()
    let after = skip_trivia(source, pos + length + 2)
    let end = if source.get_char(after) is Some('@') {
      for end = after + 1; end < source.length(); end = end + 1 {
        guard source.get_char(end)
          is Some('a'..='z' | 'A'..='Z' | '0'..='9' | '_') else {
          break end
        }
      } nobreak {
        source.length()
      }
    } else {
      after
    }
    // Version suffixes belong to the module, before any package path.
    let path = match path.find("@") {
      Some(version) => {
        let tail = path.clamped_view(start=version)
        match tail.find("/") {
          Some(slash) =>
            "\{path.clamped_view(end=version)}\{tail.clamped_view(start=slash)}"
          None => path.clamped_view(end=version).to_owned()
        }
      }
      None => path
    }
    let local_name = if end > after {
      source.clamped_view(start=after + 1, end~).to_owned()
    } else {
      path
      .split("/")
      .to_array()
      .last()
      .map(view => view.to_owned())
      .unwrap_or(path)
    }
    aliases[path] = local_name
    continue end
  }
  aliases
}

///|
fn skip_trivia(source : String, start : Int) -> Int {
  for pos = start; pos < source.length(); {
    match source.get_char(pos) {
      Some(' ' | '\t' | '\r' | '\n') => continue pos + 1
      Some('/') if source.clamped_view(start=pos).has_prefix("//") => {
        let tail = source.clamped_view(start=pos)
        match tail.find("\n") {
          Some(end) => continue pos + end + 1
          None => break source.length()
        }
      }
      _ => break pos
    }
  } nobreak {
    source.length()
  }
}

///|
test "client injection preserves user lines and import aliases" {
  let source = "///|\nimport {\n  \"moonbitlang/async/fs\" @files,\n}\nasync fn main { println(1) }"
  let prepared = prepare_source(source)
  assert_true(prepared.contains("\"moonbitlang/async/fs\" @files,"))
  assert_eq(prepared.split("\n").to_array()[4], "async fn main { println(1) }")
  assert_true(prepare_source("fn main {}").has_prefix("import {"))
}
