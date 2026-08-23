# Exposé

Exposé is a native Omarchy Shell overview for every open Hyprland window. It uses Quickshell's foreign-toplevel and screencopy integrations for live, clickable previews without launching a separate UI process.

![Exposé demo](assets/demo.gif)

> The plugin manifest includes a privacy-safe static preview of the same interface.

## Features

- Live thumbnails for windows across all workspaces
- Adaptive, collision-free Exposé composition that uses the full available screen
- Application icons, titles, and workspace names
- Pointer hover and keyboard-selection highlighting
- Type-to-filter by application ID or title
- Arrow-key navigation and Enter activation
- Space-bar Quick Look with in-place and centered preview placement
- Live compositor-backed background blur and adjustable dimming
- Centered settings editor for every Exposé option
- Live updates as windows open, close, move, or change title
- Native Omarchy colors, spacing, typography, and rounded corners
- Theme-aware fallback when a screencopy frame is unavailable
- `expose toggle` shell IPC endpoint

## Requirements

- Omarchy Quattro with the native shell plugin system
- Quickshell with `ToplevelManager` and `ScreencopyView`
- Hyprland with `wlr-foreign-toplevel-management` and toplevel-export screencopy support
- Bash and `hyprctl` (included with Omarchy and Hyprland)
- `jq`
- GNU `sleep` and `timeout` (included with `coreutils`)

## Install

From a published Git repository:

```sh
omarchy plugin add https://github.com/kristofferR/omarchy-expose.git --enable
```

For local development, use the same command with the URL of your fork. Omarchy clones the repository and validates its manifest before enabling the plugin.

Add a Hyprland binding to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + A", "Exposé", "omarchy-shell expose toggle")
```

Choose any unused chord if `SUPER + A` is already bound. Run `hyprctl reload` afterward.

## Update

```sh
omarchy plugin update expose.window-overview --yes
```

## Remove

Remove the Exposé lines from `~/.config/hypr/bindings.lua`, then run:

```sh
omarchy plugin remove expose.window-overview --yes
hyprctl reload
```

Removal unloads the plugin before deleting its Git checkout. Exposé does not install packages, services, hooks, or files outside its plugin directory and its entry in `~/.config/omarchy/shell.json`.

## Keyboard controls

| Key | Action |
| --- | --- |
| Arrow keys | Move selection |
| Space | Enlarge or restore the hovered or selected window preview |
| Shift+Space | Enlarge or restore the preview in exaggerated slow motion |
| Enter | Activate the selected window |
| Escape | Restore an enlarged preview; press again to close the overview |
| Letters, numbers, and punctuation | Filter by title or application |
| Backspace | Remove a filter character |
| Ctrl+Backspace | Remove a filter word |
| Ctrl+U | Clear the filter |

Mouse users can click a card to activate it.

## Configuration

The plugin reads Omarchy's current `Color` and `Style` tokens. Window previews keep their real aspect ratios and adapt their relative scale before spreading across the available screen area. Window ordering and aspect ratios stay fixed while Exposé is open, so metadata updates do not reshuffle the composition.

Open **Settings** from the footer to edit background blur and dimming, hot-corner behavior, preview placement, window labels, and pointer movement. Changes apply immediately and persist inline on the plugin's entry in `~/.config/omarchy/shell.json`.

Background blur is rendered by Hyprland behind Exposé, so videos and other desktop content remain live without recursive screen capture. The chosen blur strength is applied only while Exposé is visible, then the previous compositor blur setting is restored.

Space previews expand in place by default. Preview placement can be set to in-place or centered.

Window identity can float below the preview, sit in an integrated rail, overlay the image, or use a centered Exposé-style label. Floating identity is the default.

The hot corner is enabled at the top left by default. It opens Exposé when it is closed and closes Exposé when it is open. It re-arms only after the pointer leaves the corner, avoiding close/reopen loops. Choose any screen corner and enable or disable it in Settings or with the IPC commands below. Disable the matching corner in any other hot-corner plugin to avoid overlapping input surfaces.

Window activation moves the pointer to the chosen window by default, matching Hyprland's normal focus behavior. This can be disabled per Exposé activation without changing the global Hyprland cursor setting.

External tools can toggle, open, or close the overview:

```sh
omarchy-shell expose toggle
omarchy-shell expose open # Run again to close with the reverse animation
omarchy-shell expose close
omarchy-shell expose settings open
omarchy-shell expose settings close
omarchy-shell expose settings toggle
omarchy-shell expose backgroundBlur 4
omarchy-shell expose backgroundDim 6
omarchy-shell expose previewPlacement in-place
omarchy-shell expose previewPlacement centered
omarchy-shell expose windowFooterStyle floating
omarchy-shell expose windowFooterStyle integrated
omarchy-shell expose windowFooterStyle overlay
omarchy-shell expose windowFooterStyle centered
omarchy-shell expose hotCorner on
omarchy-shell expose hotCorner off
omarchy-shell expose hotCornerPosition top-left
omarchy-shell expose hotCornerPosition top-right
omarchy-shell expose hotCornerPosition bottom-left
omarchy-shell expose hotCornerPosition bottom-right
omarchy-shell expose moveCursorToWindow on
omarchy-shell expose moveCursorToWindow off
```

The Hyprland shortcut is user configuration and can be changed to any unused combination.

## Security and system changes

Like every Omarchy shell plugin, Exposé runs unsandboxed inside the long-running shell with the current user's permissions. Review the repository before installing it.

- The bundled helpers use Bash, `hyprctl`, `jq`, `sleep`, and `timeout`. Exposé does not use `sudo` or `pkexec`, access the network, install packages, create services, or run remote builds.
- Exposé reads Hyprland's window metadata and activates the window selected by the user.
- Background blur temporarily changes the live Hyprland blur settings while Exposé is visible and restores the previous values when it closes or its helper exits.
- The only persistent writes are explicit settings changes made in Exposé's Settings panel. They update this plugin's existing entry in `~/.config/omarchy/shell.json`.
- `keepLoaded` keeps the overlay and hot corner inside the existing Omarchy shell process. Exposé does not start another Quickshell instance or a background service.

## Preview assets

`preview.png` is the privacy-reviewed static marketplace image. `assets/demo.gif` is the animated README demo. Both were captured for this repository and contain no personal data. They include Retro 82 and Last Horizon theme artwork distributed with the MIT-licensed Omarchy package; the Exposé icon and interface capture are distributed under this repository's MIT license.

## Troubleshooting

- **No thumbnails:** verify that Hyprland exposes toplevel-export support and that no screen-capture policy blocks Quickshell. Cards remain usable with fallback labels.
- **Workspace says “—”:** Exposé matches foreign-toplevel objects to `hyprctl clients -j`. Very short-lived windows or multiple identical title/class pairs can briefly be ambiguous.
- **Plugin is not listed:** run `omarchy plugin validate .`, then `omarchy-shell shell rescanPlugins`.
- **Shortcut does nothing:** run `hyprctl reload`, inspect `hyprctl configerrors`, and test `omarchy-shell expose toggle` directly.
- **Standalone Super:** Hyprland modifier-only bindings are not reliably distinguishable from the start of normal Super shortcuts in current configurations. A chord such as Super+Tab avoids delayed or accidental activation.

## License

MIT
