# Vendored Office Viewer Package

This directory contains the reusable `viewer` package from
`moonbit-community/office-viewer`, vendored for the OpenSeek desktop workspace.
It keeps the upstream module name and public API so the standalone viewer and
the embedded file panel use the same reader, layout, surface, and selection
workflow.

The source snapshot is maintained from the `office-viewer` repository. The
standalone shell, browser assets, and font files remain in that repository;
OpenSeek owns its application shell and its checked-in font fallback.
