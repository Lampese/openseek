///|
fn pdf_viewer_toolbar(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  guard active_pdf_document(state, ctx) is Some((_, document, _)) else {
    return @html.nothing
  }
  let ready = document.status is PdfReady
  let pages = document.pages.map(pages => pages.to_string()).unwrap_or("…")
  let controls = [
    @html.button(
      type_="button",
      class="office-viewer-control",
      disabled=!ready || document.page <= 1,
      title="Previous page",
      attrs=@html.Attrs::build().aria_label("Previous page"),
      on_click=dispatch(PdfPageChanged((document.page - 1).to_string())),
      "‹",
    ),
    @html.input(
      input_type=Number,
      class="pdf-page-input",
      min=1,
      value=document.page.to_string(),
      on_change=dispatch.map(value => PdfPageChanged(value)),
      attrs=@html.Attrs::build().aria_label("PDF page number").disabled(!ready),
    ),
    @html.span(class="pdf-page-total", "/ \{pages}"),
    @html.button(
      type_="button",
      class="office-viewer-control",
      disabled=!ready ||
        document.pages.map(pages => document.page >= pages).unwrap_or(true),
      title="Next page",
      attrs=@html.Attrs::build().aria_label("Next page"),
      on_click=dispatch(PdfPageChanged((document.page + 1).to_string())),
      "›",
    ),
    @html.button(
      type_="button",
      class="office-viewer-control",
      disabled=!ready,
      title="Fit page width",
      attrs=@html.Attrs::build().aria_label("Fit page width"),
      on_click=dispatch(PdfFitWidth),
      "↔",
    ),
    @html.button(
      type_="button",
      class="office-viewer-control",
      disabled=!ready,
      title="Rotate clockwise",
      attrs=@html.Attrs::build().aria_label("Rotate clockwise"),
      on_click=dispatch(PdfRotated),
      "↻",
    ),
  ]
  if !state.office_query.is_empty() {
    controls.push(
      @html.span(
        class="pdf-search-count",
        match document.search {
          Some((current, total)) => "\{current} / \{total}"
          None => "Searching…"
        },
      ),
    )
    let no_matches = !ready ||
      document.search.map(pair => pair.1 == 0).unwrap_or(true)
    controls.push(
      @html.button(
        type_="button",
        class="office-viewer-control",
        disabled=no_matches,
        title="Previous match",
        attrs=@html.Attrs::build().aria_label("Previous match"),
        on_click=dispatch(PdfFind(true)),
        "‹",
      ),
    )
    controls.push(
      @html.button(
        type_="button",
        class="office-viewer-control",
        disabled=no_matches,
        title="Next match",
        attrs=@html.Attrs::build().aria_label("Next match"),
        on_click=dispatch(PdfFind(false)),
        "›",
      ),
    )
  }
  @html.div(
    class="office-viewer-toolbar pdf-viewer-toolbar",
    attrs=@html.Attrs::build().role("group").aria_label("PDF viewer controls"),
    controls,
  )
}

///|
fn pdf_password_dialog(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  let document = active_pdf_document(state, ctx).map(tuple => tuple.1)
  let required = document
    .map(document => document.status is PdfPasswordRequired(_))
    .unwrap_or(false)
  let incorrect = document
    .map(document => document.status is PdfPasswordRequired(incorrect=true))
    .unwrap_or(false)
  @html.div(
    class=if required {
      "pdf-password-overlay"
    } else {
      "pdf-password-overlay hidden"
    },
    [
      @html.form(
        class="pdf-password-dialog",
        attrs=@html.Attrs::build()
          .role("dialog")
          .aria_modal("true")
          .aria_label("Unlock PDF")
          .on_submit(event => {
            event.prevent_default()
            dispatch(PdfPasswordSubmitted)
          }),
        [
          @html.h2("Unlock PDF"),
          @html.input(
            input_type=Password,
            value=document.map(document => document.password).unwrap_or(""),
            placeholder="Password",
            on_input=dispatch.map(value => PdfPasswordChanged(value)),
            attrs=@html.Attrs::build().aria_label("PDF password"),
          ),
          @html.div(
            class=if incorrect {
              "pdf-password-error"
            } else {
              "pdf-password-error hidden"
            },
            attrs=@html.Attrs::build().role("alert"),
            "Incorrect password.",
          ),
          @html.div(class="pdf-password-actions", [
            @html.button(
              type_="button",
              on_click=dispatch(PdfPasswordCancelled),
              "Cancel",
            ),
            @html.button(
              type_="submit",
              disabled=document
                .map(document => document.password.is_empty())
                .unwrap_or(true),
              "Unlock",
            ),
          ]),
        ],
      ),
    ],
  )
}
