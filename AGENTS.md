# Repository guidance

## Release workflow

- Treat `manifest.json` as the release source of truth and bump its semantic
  version for every published release.
- Validate releases with `qmllint Overview.qml`, shell syntax checks for the
  helper scripts, and `omarchy plugin validate .`.
- The README demo is a GitHub release asset, not a tracked file, so clones stay
  small. Attach replacement media to a release and update the README link.
- Keep `https://github.com/kristofferR/omarchy-expose.git` published in the
  Okomart catalog at `brianblakely/omarchy-plugins`. When adding or changing
  its catalog entry, update `plugins.txt`, regenerate the marker-owned README
  table, validate the catalog, and submit the change through the
  `kristofferR/omarchy-plugins` fork.
