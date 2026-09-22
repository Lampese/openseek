///|
test "HTML conversion preserves code objects and escapes inline code" {
  let doc = @cmark.Doc::from_string(
    "<details>\n<summary>Code</summary>\n\n```mbt\nlet n = 42\n```\n\n`<script>literal</script>`\n\n```mermaid\nflowchart LR\nA --> B\n```\n\n</details>",
    strict=false,
  )
  let blocks : Array[@cmark.CodeBlock] = []
  let rendered = html_document(doc, "private-marker", block => {
    blocks.push(block)
    blocks.length() - 1
  })
  assert_eq(blocks.length(), 2)
  assert_eq(lines_text(blocks[0].code), "let n = 42")
  assert_eq(lines_text(blocks[1].code), "flowchart LR\nA --> B")
  assert_true(blocks[1].layout is Fenced({ closing_fence: Some(_), .. }))
  assert_true(rendered.contains("<!--private-marker:0-->"))
  assert_true(rendered.contains("<!--private-marker:1-->"))
  assert_true(
    rendered.contains("<code>&lt;script&gt;literal&lt;/script&gt;</code>"),
  )
  assert_false(rendered.contains("let n = 42"))
}

///|
test "HTML conversion emits valid headings and semantic aligned tables" {
  let doc = @cmark.Doc::from_string(
    "<h1>Title</h1>\n\n| Left | Right |\n| :-- | --: |\n| one | two |",
    strict=false,
  )
  let blocks : Array[@cmark.CodeBlock] = []
  let rendered = html_document(doc, "unused", block => {
    blocks.push(block)
    blocks.length() - 1
  })
  assert_eq(blocks.length(), 0)
  assert_true(rendered.has_prefix("<h1>Title</h1>"))
  assert_true(
    rendered.contains(
      "<table><thead><tr><th align=\"left\">Left</th><th align=\"right\">Right</th></tr></thead><tbody><tr><td align=\"left\">one</td><td align=\"right\">two</td></tr></tbody></table>",
    ),
  )
}

///|
test "HTML conversion preserves task statuses without admitting form controls" {
  let doc = @cmark.Doc::from_string("- [x] done\n- [ ] pending", strict=false)
  let blocks : Array[@cmark.CodeBlock] = []
  let rendered = html_document(doc, "unused", block => {
    blocks.push(block)
    blocks.length() - 1
  })
  assert_eq(blocks.length(), 0)
  assert_true(rendered.contains("☑ "))
  assert_true(rendered.contains("☐ "))
  assert_false(rendered.contains("<input"))
}
