# Office Viewer Fonts

This directory is the desktop packaging fallback for the font programs used by
`moonbit-community/office-viewer`. They are copied from its `public/fonts/`
export so the Office SVG renderer and browser use the same metrics. The build
prefers a sibling viewer checkout and falls back to this copy for a standalone
OpenSeek checkout.

The files under `fonts/LICENSES/` are shipped with the corresponding font
programs and must remain beside them in packaged distributions.
