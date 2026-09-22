///|
/// Render the entire document before parsing HTML: a details/div opened by one
/// cmark block may close several paragraphs later. Only cmark code blocks get
/// private placeholders, so inline code and raw HTML retain GFM semantics.
fn MarkdownRender::html_nodes(
  self : MarkdownRender,
  doc : @cmark.Doc,
  source : String,
) -> Array[@html.Html] raise {
  let marker = html_code_marker(source)
  let codes : Array[@html.Html] = []
  let html = html_document(doc, marker, block => {
    let index = codes.length()
    codes.push(code_block(locale=self.locale, block))
    index
  })
  Array::from_fixed_array(
    html_fragment_nodes(
      html,
      marker,
      FixedArray::from_array(codes[:]),
      destination => {
        @js.Nullable::from_option(self.safe_destination(destination))
      },
      text => self.prose_nodes(text),
      @html.text,
      html_element,
    ),
  )
}

///|
fn html_document(
  doc : @cmark.Doc,
  marker : String,
  save_code : (@cmark.CodeBlock) -> Int,
) -> String raise {
  let overrides = @cmark_renderer.Renderer::new(
    block=fn(ctx, block) raise {
      match block {
        CodeBlock(node) | ExtMathBlock(node) => {
          ctx.string("<!--\{marker}:\{save_code(node.v)}-->")
          true
        }
        ExtTable(node) => {
          html_table(ctx, node.v)
          true
        }
        // cmark 0.4.5 treats raw h1-h6 tags at paragraph start as inline
        // HTML. Avoid adding an invalid p wrapper and empty repair paragraphs.
        Paragraph(node) if starts_with_html_heading(node.v.inline) => {
          ctx.inline(node.v.inline)
          true
        }
        // cmark's default task-list output contains input elements. Preserve
        // our read-only markers without admitting user-supplied form controls.
        List(node) if node.v.items
          .iter()
          .any(i => i.v.ext_task_marker is Some(_)) => {
          let tag = match node.v.ty {
            Ordered(start, _) => {
              ctx.string("<ol start=\"\{start}\">")
              "ol"
            }
            Unordered(_) => {
              ctx.string("<ul>")
              "ul"
            }
          }
          for item in node.v.items {
            ctx.string("<li>")
            if item.v.ext_task_marker is Some(marker) {
              ctx.string(
                match @cmark.ListTaskStatus::from_marker(marker.v) {
                  Checked => "☑ "
                  Cancelled => "☒ "
                  Unchecked | Other(_) => "☐ "
                },
              )
            }
            ctx.block(item.v.block)
            ctx.string("</li>")
          }
          ctx.string("</\{tag}>")
          true
        }
        _ => false
      }
    },
    inline=fn(ctx, inline) {
      match inline {
        // cmark rewrites unsafe autolinks to href="". Keep their destination
        // until the shared URL policy can remove it, rather than linking the PR.
        Autolink(node) => {
          let destination = if node.v.is_email {
            "mailto:" + node.v.link.v
          } else {
            node.v.link.v
          }
          ctx.string("<a href=\"\{@common.escape_html(destination)}\">")
          ctx.string(@common.escape_html(node.v.link.v))
          ctx.string("</a>")
          true
        }
        _ => false
      }
    },
  )
  @cmark_html.renderer(safe=false).compose(overrides).doc_to_string(doc)
}

///|
fn starts_with_html_heading(inline : @cmark.Inline) -> Bool {
  match inline {
    RawHtml(node) =>
      tights_text(node.v.0).view() =~ re"(?i:^</?h[1-6][[:space:]/>])"
    Inlines(node) if !node.v.is_empty() => starts_with_html_heading(node.v[0])
    _ => false
  }
}

///|
/// Use semantic table sections and alignment attributes: cmark's default
/// renderer expresses alignment as classes, which the input allowlist strips.
fn html_table(
  ctx : @cmark_renderer.Context,
  table : @cmark.Table,
) -> Unit raise {
  let mut alignment : Array[@cmark.TableAlign?] = []
  for (row, _) in table.rows {
    if row.v is Sep(cells) {
      alignment = cells.iter().map(cell => cell.v.0.0).to_array()
      break
    }
  }
  ctx.string("<table>")
  let mut section : String? = None
  for (row, _) in table.rows {
    let (next_section, tag, cells) = match row.v {
      Header(cells) => ("thead", "th", cells)
      Data(cells) => ("tbody", "td", cells)
      Sep(_) => continue
    }
    if section != Some(next_section) {
      if section is Some(previous) {
        ctx.string("</\{previous}>")
      }
      ctx.string("<\{next_section}>")
      section = Some(next_section)
    }
    ctx.string("<tr>")
    for i in 0..<table.col_count {
      ctx.string("<\{tag}")
      if alignment.get(i) is Some(Some(align)) {
        let value = match align {
          Left => "left"
          Center => "center"
          Right => "right"
        }
        ctx.string(" align=\"\{value}\"")
      }
      ctx.string(">")
      if i < cells.length() {
        ctx.inline(cells[i].0)
      }
      ctx.string("</\{tag}>")
    }
    ctx.string("</tr>")
  }
  if section is Some(previous) {
    ctx.string("</\{previous}>")
  }
  ctx.string("</table>")
}

///|
/// Dynamic attributes enter Rabbita only here, after the allowlist and URL
/// policy below. They remain attributes, never event handlers or properties.
fn html_element(
  tag : String,
  attributes : Array[Array[String]],
  children : Array[@html.Html],
) -> @html.Html {
  let attrs = @html.Attrs::build()
  let raw = html_attribute_map(attrs)
  for pair in attributes {
    raw[pair[0]] = pair[1]
  }
  @html.node(tag, attrs, children)
}

///|
// Rabbita 0.16.2 has a generic node constructor but no public raw-attribute
// setter. Attrs wraps Props; bridge only its string attribute map (never the
// property/event maps). This preserves percent dimensions and legacy HTML
// attributes that its typed helpers cannot represent.
extern "js" fn html_attribute_map(attrs : @html.Attrs) -> Map[String, String] =
  #| attrs => attrs.attrs

///|
/// Comments don't decode entities. A fresh marker absent from the source
/// cannot be authored by that source, even using character references. It is
/// consumed in the inert fragment and never appears in the live DOM.
extern "js" fn html_code_marker(source : String) -> String =
  #| source => {
  #|   let marker;
  #|   do {
  #|     marker = "seekmoon-code-" + crypto.randomUUID();
  #|   } while (source.includes(marker));
  #|   return marker;
  #| }

///|
extern "js" fn html_fragment_nodes(
  html : String,
  marker : String,
  codes : FixedArray[@html.Html],
  destination : (String) -> @js.Nullable[String],
  prose : (String) -> Array[@html.Html],
  text : (String) -> @html.Html,
  element : (String, Array[Array[String]], Array[@html.Html]) -> @html.Html,
) -> FixedArray[@html.Html] =
  #| (html, marker, codes, destination, prose, text, element) => {
  #|   // GFM 6.11 tagfilter runs before the HTML parser, including end tags.
  #|   // Code spans are already escaped; fenced/indented code is a placeholder.
  #|   const filtered = html.replace(/<(\/?)(title|textarea|style|xmp|iframe|noembed|noframes|script|plaintext)(?=[\t\n\f\r />])/gi, "&lt;$1$2");
  #|   const template = document.createElement("template");
  #|   template.innerHTML = filtered;
  #|   const allowed = new Set("h1 h2 h3 h4 h5 h6 p div span br hr b i strong em tt ins del s strike sup sub mark pre code kbd q samp var blockquote ul ol li dl dt dd table thead tbody tfoot tr th td ruby rt rp details summary a img picture source video relative-time".split(" "));
  #|   // Observed GitHub Markdown API rules; fixtures record the upstream
  #|   // output independently. No input class/style/events or data attributes.
  #|   const global = new Set(["id", "name", "title", "lang", "dir", "align", "width", "height", "valign", "nowrap", "hspace", "color", "itemprop"]);
  #|   const local = {
  #|     a: ["href", "hreflang", "type"],
  #|     img: ["src", "alt", "width", "height", "hspace", "longdesc"],
  #|     source: ["srcset", "media", "type", "width", "height"],
  #|     video: ["src", "width", "height", "controls", "muted"],
  #|     details: ["open"],
  #|     "relative-time": ["datetime"],
  #|     table: ["width", "height", "cellpadding", "cellspacing", "summary"],
  #|     thead: ["valign"], tbody: ["valign"], tfoot: ["valign"], tr: ["valign"],
  #|     th: ["colspan", "rowspan", "headers", "scope", "abbr", "width", "height", "valign", "nowrap"],
  #|     td: ["colspan", "rowspan", "headers", "width", "height", "valign", "nowrap"],
  #|     ol: ["start", "type"], ul: ["type"], li: ["value"],
  #|     q: ["cite"], blockquote: ["cite"],
  #|     ins: ["cite", "datetime"], del: ["cite", "datetime"]
  #|   };
  #|   const safeURL = value => {
  #|     const resolved = destination(value);
  #|     if (resolved === null) return null;
  #|     // Also cover HTML callers without web_source. The browser removes
  #|     // control characters from schemes after cmark's string-level check.
  #|     try {
  #|       return ["http:", "https:", "mailto:"].includes(new URL(resolved, document.baseURI).protocol) ? resolved : null;
  #|     } catch (_) { return null; }
  #|   };
  #|   const mediaURL = value => {
  #|     if (!value.trim()) return null;
  #|     const resolved = safeURL(value);
  #|     return resolved && /^https?:\/\//i.test(resolved) ? resolved : null;
  #|   };
  #|   const srcset = value => {
  #|     // Only HTTP(S) media are accepted. Commas in URLs must be percent
  #|     // encoded; data URLs never reach the browser's candidate selector.
  #|     const candidates = [];
  #|     for (const candidate of value.split(",")) {
  #|       const parts = candidate.trim().split(/\s+/);
  #|       if (parts.length > 2 || (parts[1] && !/^(?:[1-9]\d*w|(?:\d+(?:\.\d+)?|\.\d+)x)$/.test(parts[1]))) continue;
  #|       const url = mediaURL(parts[0]);
  #|       if (url) candidates.push(url + (parts[1] ? " " + parts[1] : ""));
  #|     }
  #|     return candidates.length ? candidates.join(", ") : null;
  #|   };
  #|   function children(parent, literal) {
  #|     return Array.from(parent.childNodes).flatMap(node => convert(node, literal));
  #|   }
  #|   function convert(node, literal) {
  #|     if (node.nodeType === 3) return literal ? [text(node.data)] : prose(node.data);
  #|     if (node.nodeType === 8) {
  #|       const prefix = marker + ":";
  #|       if (!node.data.startsWith(prefix)) return [];
  #|       const index = node.data.slice(prefix.length);
  #|       return /^(0|[1-9]\d*)$/.test(index) && Number(index) < codes.length ? [codes[Number(index)]] : [];
  #|     }
  #|     if (node.nodeType !== 1) return [];
  #|     const tag = node.localName;
  #|     const content = children(tag === "template" ? node.content : node,
  #|       literal || ["a", "pre", "code", "relative-time"].includes(tag));
  #|     if (node.namespaceURI !== "http://www.w3.org/1999/xhtml" || !allowed.has(tag)) return content;
  #|     const attrs = [];
  #|     for (const {name, value} of node.attributes) {
  #|       if (!global.has(name) && !(local[tag] || []).includes(name)) continue;
  #|       let clean = value;
  #|       if (name === "id" || name === "name") clean = "user-content-" + value;
  #|       else if (name === "href" || name === "cite" || name === "longdesc") clean = safeURL(value);
  #|       else if (name === "src") clean = mediaURL(value);
  #|       else if (name === "srcset") clean = srcset(value);
  #|       if (clean !== null) attrs.push([name, clean]);
  #|     }
  #|     if (tag === "a") attrs.push(["target", "_blank"], ["rel", "noopener noreferrer"]);
  #|     if (tag === "video") {
  #|       if (!attrs.some(([name]) => name === "controls")) attrs.push(["controls", ""]);
  #|       attrs.push(["preload", "metadata"]);
  #|     }
  #|     return [element(tag, attrs, content)];
  #|   }
  #|   return children(template.content, false);
  #| }
