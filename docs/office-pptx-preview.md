# PowerPoint preview

Desktop opens `.pptx` files in the shared read-only Office surface. Each slide
retains selectable SVG text and embedded fonts. Search, zoom, slide thumbnails
and visual region annotations use the existing Office controls. Region context
includes the original file identity, slide number and normalized geometry.
PowerPoint comments and logical Word/Excel selectors are unavailable.

The static drawing support and explicit unsupported-feature errors come from
`office.mbt`'s `pagelayout/pptx` renderer. Font replacement warnings remain visible.
The renderer's MPL-2.0 MTX decoder license and source notice are staged alongside
the viewer's runtime assets in both browser and packaged Desktop builds.

## Development dependencies

This draft depends on the unreleased source APIs in
[office.mbt#654](https://github.com/moonbitlang/office.mbt/pull/654) and the
`feat/pptx-preview` branch of `moonbit-community/office-viewer` at `12c9643`.
That branch retains the `Lampese/office-viewer` module identity currently consumed
by Desktop; the canonical upstream change is
[office-viewer#12](https://github.com/moonbit-community/office-viewer/pull/12).
Those dependencies
must be released and the module pins updated before this change can merge.
No package release is performed by this branch.

To reproduce before those releases, check out those branches beside OpenSeek,
then append their module paths to the local `moon.work` members:

```toml
  "../office-viewer",
  "../office.mbt/pagelayout",
```

Keep the development paths local. The packager also needs the matching viewer's
runtime assets:

```sh
OPENSEEK_OFFICE_VIEWER_SOURCE="$PWD/../office-viewer" moon run desktop/package/browser --target native
OPENSEEK_OFFICE_VIEWER_SOURCE="$PWD/../office-viewer" moon run desktop/package/macos --target native -- --no-open
```

Use an absolute environment path because the package script runs from `desktop/`.

The public two-slide fixture in `desktop/e2e/fixtures/office` is independently
generated; its generator and provenance are included. The private reference deck
and its embedded fonts are never committed.
