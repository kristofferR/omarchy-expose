# Exposé for Omarchy

macOS-style Exposé for Omarchy: one key or a hot corner shows every open window as a live preview. Type to search, press Space to Quick Look, press Enter to launch.

![Exposé demo](https://github.com/kristofferR/omarchy-expose/releases/download/v4.0.0/demo.gif)

## Highlights

- **Live previews.** Cards are real screencopy views, so videos keep playing and terminals keep scrolling. The Omarchy desktop behind the grid stays live too.
- **Quick Look.** Space enlarges any preview and restores it again. Shift+Space does it in slow motion, like the classic macOS Easter egg.
- **Search.** Just start typing to filter windows by title or application.
- **Workspace scope.** Press Tab to switch between every window and windows on the current workspace, and pick which of the two the overview opens with. Per-monitor mode evaluates the current workspace of the selected display.
- **Workspace strip (optional).** Turn it on to see each workspace above the window grid. Click a tile to switch to it, or drag a window onto a tile to move it there. Each part of this is its own setting.
- **Multi-monitor layouts.** Every display blurs and dims, with one grid on the focused display (or the display whose hot corner was used). All displays shows every window there; This display keeps that display's own windows.
- **Built for Omarchy.** Runs inside Omarchy Shell, follows the active theme, and adds no packages, services, or daemons.
- **Hot corner.** Toggle the overview by flinging the pointer into a corner. Uses the outermost display by default, with an option for all displays.

Everything is tunable from the built-in Settings panel and over IPC, and changes apply instantly.

## ❤️ Support the project

Enjoying Exposé for Omarchy? Sponsoring its development is a lovely way to say thanks and help keep the project growing.

[![Sponsor on GitHub](https://img.shields.io/badge/Sponsor_on_GitHub-%E2%99%A1-ec6cb9?style=for-the-badge)](https://github.com/sponsors/kristofferR)

## Requirements

- Omarchy Quattro with the native shell plugin system
- `jq`

The underlying Quickshell, Hyprland, Bash, and coreutils support ships with Omarchy, so no separate compositor setup is needed.

## Install

```sh
omarchy plugin add https://github.com/kristofferR/omarchy-expose.git --enable
```

That's it: the top-left hot corner works right away. Optionally, bind a key in `~/.config/hypr/bindings.lua`, then run `hyprctl reload`:

```lua
o.bind("SUPER + A", "Exposé", hl.dsp.event("expose.window-overview:toggle"))
```

Any unused chord works. Avoid modifier-only bindings such as standalone Super; Hyprland cannot reliably distinguish them from the start of normal Super shortcuts.

To keep workspace swipes from changing the desktop behind Exposé, replace your workspace gesture in `~/.config/hypr/input.lua` with:

```lua
local expose_gesture_path = os.getenv("HOME") .. "/.config/omarchy/plugins/expose.window-overview/workspace-gesture.lua"
local expose_gesture_loader = loadfile(expose_gesture_path)
if expose_gesture_loader then
  expose_gesture_loader()({ fingers = 4, scale = 0.5 })
else
  hl.gesture({ fingers = 4, direction = "horizontal", scale = 0.5, action = "workspace" })
end
```

Adjust `fingers` and `scale` to match your preferred gesture. Only the workspace gesture is swallowed while Exposé is open; media keys and other compositor shortcuts keep working.

### Update

```sh
omarchy plugin update expose.window-overview --yes
```

### Remove

Delete the Exposé binding from `~/.config/hypr/bindings.lua`, then:

```sh
omarchy plugin remove expose.window-overview --yes
hyprctl reload
```

Removal leaves nothing behind: Exposé keeps no files outside its plugin directory and its entry in `~/.config/omarchy/shell.json`.

## Controls

| Key | Action |
| --- | --- |
| Arrow keys | Move selection |
| Any character | Search by title or application |
| Space | Quick Look the hovered or selected preview (enlarge or restore) |
| Shift+Space | Quick Look in slow motion |
| Tab | Toggle between the current workspace and all workspaces |
| Shift+Q | Close the selected window |
| Enter | Activate the selected window |
| Escape | Restore an enlarged preview; press again to close |

Clicking a card activates it; middle-clicking closes it. Activation moves the pointer to the chosen window by default; this is a setting, not a change to Hyprland's global cursor behavior.

The workspace strip is off by default; enable it under **Settings → Workspaces**. Click a tile to switch to that workspace. With dragging on, drop a card on a tile to move that window; by default Exposé then follows the window to its new workspace and closes, or choose **Stay here** to keep the overview open. The optional **New workspace** tile uses the first available positive workspace number. **Close numbering gaps** (off by default) shifts later numbered workspaces down when a move empties one. A highlighted tile is a valid drop target. Drop outside the strip or press Escape to cancel. Pinned windows cannot be moved this way. In **This display** mode, the strip lists that display's workspaces. In **All displays** mode, it lists workspaces from all displays and labels each tile with its monitor.

The window grid stays on the display where Exposé opened. Every display gets the same background blur and dim; clicking any backdrop dismisses Exposé without clicking through to the desktop. With **All displays**, the grid shows every window. With **This display**, it shows only windows that already belong to that display; when showing the current workspace, it uses the one active on that display.

Hot corners default to the outermost display: left corners use the leftmost display, and right corners use the rightmost. If displays share that edge, the topmost or bottommost one wins according to the chosen corner. Enable **Hot corner → Use on all displays** to use the chosen corner on every display.

## Settings

Open **Settings** from the footer while the overview is open. It is fully keyboard driven: 1-6 jump to a section, Up/Down move between controls, Left/Right adjust sliders and choices, Space or Enter flip toggles and press buttons, Escape closes. Changes apply immediately. Settings are grouped into **Appearance**, **Windows**, **Window labels**, **Workspaces**, **Hot corner**, and **Motion**, with explanatory text beneath each control:

- Opening animation: Original (default), Fade, Zoom, or Slide
- Animation duration saved per mode, linked for in/out by default or expandable to separate timings
- Slide direction: left (default), right, up, or down. Splitting in/out splits both speed and direction
- Background blur (0–20) and dim (0–90)
- Quick Look position: in-place or centered
- Opens with: all workspaces (default) or the current workspace; Tab still switches either way
- Workspace names: full (default) or slot only, which prints just the trailing slot of names like `<monitor description>:3` that per-monitor workspace plugins produce
- Window footer style: floating, integrated, overlay, or centered
- Windows to include: All displays (windows from every display) or This display (only that display's windows)
- Bottom text visibility. Hiding it requires confirmation and removes the Settings link
- Hot corner on/off, position (disable the same corner in other hot-corner plugins to avoid overlap), All displays (off by default), and activation delay (0–1000 ms of pointer dwell before it fires; 0 is instant)
- Move cursor to the activated window on/off
- Recover off-screen windows: center a floating window that sits outside every display when you activate it (off by default)
- Workspace strip (off by default), dragging windows onto it (on), after a move follow the window or stay (follow), the New workspace tile (on), and closing workspace numbering gaps (off)

Every reversible setting is also scriptable:

```sh
omarchy-shell expose toggle                      # also: open, close
omarchy-shell expose settings toggle             # also: open, close
omarchy-shell expose animationStyle original     # original | fade | zoom | slide
omarchy-shell expose animationDuration original 190    # linked in/out, 100-800 ms
omarchy-shell expose animationDurationIn original 190  # separate opening speed
omarchy-shell expose animationDurationOut original 190 # separate closing speed
omarchy-shell expose slideDirection left         # left | right | up | down, both halves
omarchy-shell expose slideDirectionIn left       # separate opening side, also splits slide timing
omarchy-shell expose slideDirectionOut right     # separate closing side, also splits slide timing
omarchy-shell expose backgroundBlur 4            # 0-20
omarchy-shell expose backgroundDim 6             # 0-90
omarchy-shell expose previewPlacement in-place   # in-place | centered
omarchy-shell expose windowFooterStyle floating  # floating | integrated | overlay | centered
omarchy-shell expose multiMonitorMode mirrored   # mirrored | per-monitor
omarchy-shell expose hotCorner on                # on | off
omarchy-shell expose hotCornerPosition top-left  # top-left | top-right | bottom-left | bottom-right
omarchy-shell expose hotCornerAllDisplays off    # off: outermost display (default) | on: every display
omarchy-shell expose hotCornerDelay 0            # 0-1000 ms of dwell before it fires
omarchy-shell expose moveCursorToWindow on       # on | off
omarchy-shell expose recoverOffscreenWindows off # on | off
omarchy-shell expose workspaceStrip off          # on | off
omarchy-shell expose workspaceDrag on            # on | off
omarchy-shell expose afterWorkspaceMove follow   # follow | stay
omarchy-shell expose newWorkspaceTile on         # on | off
omarchy-shell expose closeWorkspaceGaps off      # on | off
```

After hiding the bottom text, you can restore it while Settings remains open. If you close Settings first, edit `~/.config/omarchy/shell.json` and set `"showFooter": true` in the `expose.window-overview` plugin entry.

## Security and system changes

Exposé runs unsandboxed inside Omarchy Shell with your user's permissions.

- Its helpers are plain Bash calling `hyprctl`, `jq`, `sleep`, and `timeout`.
- It reads window, workspace, and monitor state from Quickshell's native Hyprland model, activates, closes, or moves the windows you select, and temporarily raises Hyprland's blur while open, restoring the previous value on close.
- Settings writes touch only the plugin's entry in `~/.config/omarchy/shell.json`.
- No network, no privilege escalation, no package installs, no services.

## Troubleshooting

- **No thumbnails:** verify Hyprland exposes toplevel-export support and no screen-capture policy blocks Quickshell. Cards stay usable with fallback labels.
- **Workspace says “—”:** the native Hyprland model has not associated that Wayland toplevel yet. Very short-lived windows can briefly appear this way; restart Omarchy Shell if a normal window remains unassociated.
- **Plugin not listed:** run `omarchy plugin validate .`, then `omarchy-shell shell rescanPlugins`.
- **Shortcut does nothing:** run `hyprctl reload`, check `hyprctl configerrors`, and test `hyprctl dispatch 'hl.dsp.event("expose.window-overview:toggle")'` directly.

## Credits

Based on [Bird's Eye](https://github.com/harel/omarchy-birdseye) by Harel Malka.

## License

MIT
