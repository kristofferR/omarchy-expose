Run `./validate` for the Qt 6 unit tests, QML lint, shell checks, and manifest
validation, including lint of the assembled runtime fixture.
`./tests/check-blur-lock` checks the blur helper with a temporary runtime directory
and fake `hyprctl`: planted symlinks and invalid lock paths cannot damage files or
change compositor settings, and concurrent sessions serialize through restoration.
`./tests/check-settings-runtime` additionally runs Quickshell with a
temporary config and the installed Omarchy host's actual `PluginShellApi`,
`applyShellConfig`, `persistShellConfig`, and `updateEntryInline` implementations.
It creates no windows and does not access the live user's shell.json. Pass a shell
source directory as its argument to check another host version.

The runtime check covers saved settings, 203 rapid edits, nested animation
settings, preservation of unknown fields and other entries, atomic file watching,
and external edits/deletions. Unit tests deterministically exercise delayed
snapshots, startup reads, no-op writes, rejection, and malformed configuration.

## Settings contract checked against source

- [Omarchy at 31bd80d](https://github.com/omacom/omarchy/blob/31bd80daa4613ffdee995ac27467fce5a2990806/shell/shell.qml):
  the asynchronous panel loader injects the scoped API after component creation;
  `updateEntryInline` replaces the complete matching entry; `false` also means
  unchanged; persistence updates host memory before the asynchronous disk write.
- [PluginShellApi](https://github.com/omacom/omarchy/blob/31bd80daa4613ffdee995ac27467fce5a2990806/shell/services/PluginShellApi.qml):
  no readable settings property. The host restricts `mutateShellConfig` to bar
  capabilities, so it cannot patch an overlay's settings.
- [Quickshell 0.3.1 FileView](https://github.com/quickshell-mirror/quickshell/blob/v0.3.1/src/io/fileview.cpp):
  reads and writes complete asynchronously, `reload()` can reuse an existing read,
  and `loaded` is emitted before that read job is cleared. Reloads and subsequent
  writes therefore run after the callback, via `Qt.callLater`.
- [Omadock at d2d355c](https://github.com/thepathless/omadock/blob/d2d355c58d229ab82d9e9bcf116a620a3c736617/Dock.qml):
  uses FileView for its own files. Exposé borrows the watched read pattern, but
  leaves shared shell.json writes with the host.

The store permits one unconfirmed replacement at a time, with newer edits kept
locally until disk acknowledgement. An unconfirmed write gets a fresh read after
two seconds; if it still differs, local edits are discarded and disk settings
are restored with a warning. This is not a disk-success acknowledgement from the
host, which the current API does not provide.
