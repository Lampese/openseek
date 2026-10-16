///|
const OfficePagesId = "openseek-office-pages"

///|
fn office_pages_view(
  locale~ : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  let pages = if ctx.active_history_diff is None &&
    ctx.active_file is Some(path) {
    match state.docs.get(path) {
      Some({ state: TabOffice(document~, ..), .. }) if document.kind == Word =>
        Some(document.item_count)
      Some({ state: TabPdf(document~, ..), .. }) if document.status == PdfReady =>
        document.pages
      _ => None
    }
  } else {
    None
  }
  @html.div(
    id=OfficePagesId,
    class=if state.office_pages_open && pages is Some(_) {
      "office-page-rail"
    } else {
      "office-page-rail hidden"
    },
    attrs=@html.Attrs::build()
      .role("navigation")
      .aria_label(ui(locale, OfficePages))
      .data_set("page-label", ui(locale, OfficePageLabel))
      .data_set("unavailable-label", ui(locale, OfficePageUnavailable)),
    [
      @html.div(class="office-page-heading", [
        @html.span(
          class="office-page-count",
          ui(locale, OfficePageCount).replace(
            old="{count}",
            new=pages.map(value => value.to_string()).unwrap_or("…"),
          ),
        ),
        @html.button(
          type_="button",
          class="office-viewer-control",
          title=ui(locale, OfficeClosePages),
          attrs=@html.Attrs::build().aria_label(ui(locale, OfficeClosePages)),
          on_click=dispatch(OfficePagesToggled),
          @icons.icon(@icons.icon_layout_sidebar_left),
        ),
      ]),
      // The module owns only this empty subtree; the main document stays put.
      @html.div(class="office-page-list", ([] : Array[@html.Html])),
    ],
  )
}

///|
fn office_pages_command(
  state : State,
  config : @office_viewer.SurfaceConfig,
  signature : String,
) -> @cmd.Cmd {
  let kind = match config.kind {
    Some(Word) => "word"
    Some(Pdf) => "pdf"
    _ => return dispose_office_pages()
  }
  @cmd.custom_cmd(
    _ => {
      install_office_pages(
        OfficeSurfaceId,
        OfficePagesId,
        kind,
        config.document_file +
        "|" +
        signature +
        "|" +
        state.request_epoch.to_string(),
        state.office_pages_open,
        state.office_prefer_system_fonts,
      )
    },
    kind=@cmd.after_render,
  )
}

///|
fn refresh_office_pages(state : State, ctx : Ctx) -> @cmd.Cmd {
  guard ctx.active_history_diff is None && ctx.active_file is Some(path) else {
    return dispose_office_pages()
  }
  match state.docs.get(path) {
    Some({ state: TabOffice(document~, sig~), .. }) =>
      office_pages_command(
        state,
        office_surface_config(state, path, document),
        sig,
      )
    Some({ state: TabPdf(document~, ..), .. }) if document.status == PdfReady =>
      office_pages_command(
        state,
        pdf_surface_config(state, path),
        document.generation.to_string(),
      )
    _ => dispose_office_pages()
  }
}

///|
fn dispose_office_pages() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => retire_office_pages(OfficeSurfaceId),
    kind=@cmd.after_render,
  )
}

///|
extern "js" fn install_office_pages(
  surface_id : String,
  rail_id : String,
  kind : String,
  key : String,
  open : Bool,
  system_fonts : Bool,
) =
  #| (surfaceId, railId, kind, key, open, systemFonts) => {
  #|   const host = document.getElementById(surfaceId), rail = document.getElementById(railId);
  #|   if (!host || !rail) return;
  #|   const request = host.__openSeekPagesRequest = (host.__openSeekPagesRequest || 0) + 1;
  #|   import(new URL('./office-pages.mjs', document.baseURI).href).then(module => {
  #|     if (host.isConnected && rail.isConnected && host.__openSeekPagesRequest === request) {
  #|       module.install(host, rail, {kind, key, open, systemFonts});
  #|     }
  #|   }).catch(() => {
  #|     if (host.__openSeekPagesRequest === request && rail.isConnected) {
  #|       rail.querySelector('.office-page-list').textContent = rail.dataset.unavailableLabel;
  #|     }
  #|   });
  #| }

///|
extern "js" fn retire_office_pages(surface_id : String) =
  #| id => {
  #|   const host = document.getElementById(id);
  #|   if (!host) return;
  #|   host.__openSeekPagesRequest = (host.__openSeekPagesRequest || 0) + 1;
  #|   host.__openSeekPages?.dispose();
  #| }
