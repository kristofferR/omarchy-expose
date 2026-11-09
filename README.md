# Exposé for Omarchy

macOS-style Exposé for Omarchy: one key or a hot corner shows every open window as a live preview. Type to search, press Space to Quick Look, press Enter to launch. Hot corners work the way they do on a Mac, with All windows, App windows, and Desktop actions.

[![Exposé demo](https://github.com/kristofferR/omarchy-expose/releases/download/v5.5.0/demo.webp)](https://github.com/kristofferR/omarchy-expose/releases/download/v5.5.0/demo.mp4)

## Highlights

- **Live previews.** Cards are real screencopy views, so videos keep playing and terminals keep scrolling. The Omarchy desktop behind the grid stays live too.
- **Quick Look.** Space enlarges any preview and restores it again. Shift+Space does it in slow motion, like the classic macOS Easter egg.
- **Search.** Just start typing to filter windows by title or application.
- **Workspace scope.** Press Tab to switch between every window and windows on the current workspace, and pick which of the two the overview opens with. Each display uses its own active workspace in the current-workspace scope. Workspaces are numbered 1-10 on every monitor, as in the bar, and windows minimized to the dock show as **Minimized**; picking one brings it back to the current workspace.
- **Workspace strip.** Thumbnails of the display's workspaces sit above the windows; turn it off in settings if you prefer. Click one or press 1-9 and 0 to switch, drag a window onto one to move it there, and add an empty one with **+**.
- **Multi-monitor layouts.** Every display blurs and dims. All displays puts every window in one grid on the opening display; This display limits that grid to its own windows; Each display opens a separate grid of its own windows on every display.
- **Built for Omarchy.** Runs inside Omarchy Shell, follows the active theme, and adds no packages, services, or daemons.
- **Hot corners, the macOS way.** Give each screen corner its own action, as in macOS **Desktop & Dock → Hot Corners**: **All windows** (Mission Control), **App windows** (Application Windows: just the focused app's windows, minimized ones included), or **Desktop** (Show Desktop). Uses the outermost display by default, with an option for all displays.

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

That's it: the top-left hot corner works right away. Choose an action for each corner under **Settings → Hot corners**, or see [Hot corners](#hot-corners). Optionally, bind keys in `~/.config/hypr/bindings.lua`, then run `hyprctl reload`:

```lua
o.bind("SUPER + A", "Exposé", hl.dsp.event("expose.window-overview:toggle"))
-- macOS-style: Ctrl+Up, Ctrl+Down, and F11 there
o.bind("SUPER + CTRL + UP", "Exposé: all windows", "omarchy-shell expose toggle")
o.bind("SUPER + CTRL + DOWN", "Exposé: app windows", "omarchy-shell expose toggleApplication")
o.bind("SUPER + F11", "Show desktop", "omarchy-shell expose toggleDesktop")
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
| Arrow keys | Move selection between windows, including across displays in Each display mode |
| Any character | Search by title or application |
| Space | Quick Look the hovered or selected preview (enlarge or restore) |
| Shift+Space | Quick Look in slow motion |
| Tab | Toggle all windows or the current workspace |
| 1-9, 0 | With the workspace strip on and no filter typed: switch to that workspace of the display |
| Shift+Q | Close the selected window |
| Enter | Activate the selected window |
| Escape | Restore an enlarged preview; press again to close |

Clicking a card activates it; middle-clicking closes it, as does its ✕ button when that setting is on. With the workspace strip on, dragging a card onto a workspace thumbnail, or onto **+** for a new workspace, moves the window there and keeps Exposé open; Escape or dropping anywhere else cancels. Activation moves the pointer to the chosen window by default; this is a setting, not a change to Hyprland's global cursor behavior.

Every display gets the same background blur and dim. With **All displays**, one grid on the opening display shows every window. With **This display**, that grid shows only windows already on that display. With **Each display**, every display shows a grid of its own windows. Keyboard input and Settings stay on the opening display, while arrow keys select windows across displays. Cards on every display can also be clicked. Search applies to all grids, and the current-workspace scope uses each display's active workspace. Clicking empty space dismisses Exposé without clicking through to the desktop.

## Hot corners

Each corner runs one action, chosen independently, as on macOS:

| Action | macOS name | What it does |
| --- | --- | --- |
| All windows | Mission Control | Opens Exposé with every window |
| App windows | Application Windows | Opens Exposé with the focused app's windows only, minimized ones included. The search field names the app |
| Desktop | Show Desktop | Moves windows aside to show the desktop |
| Off | – | Nothing |

They behave like their macOS counterparts:

- A corner, or its key, opens its mode and closes it again. With Exposé open in the other mode, it switches in place: App windows to All windows and back.
- App windows matches windows by app id, never by title, so a window titled after another app does not join its group. With no window to take an app from, it shows all windows.
- Desktop is a temporary peek. Triggering it again brings the windows back, and so does anything that needs a window: opening or focusing one, picking one in Exposé or the dock, or switching workspace. Windows return to their own workspace in their own place. Triggering Desktop with Exposé open closes Exposé and shows the desktop.
- Desktop minimizes windows with Omarchy's own command, so it works on floating workspaces, where the dock brings windows back. On a tiled workspace it leaves the layout alone and says so once. Pinned, fullscreen, and grouped windows stay put, and a window you minimized yourself is never brought back by it. If Omarchy Shell restarts during a peek, the windows come back.
- Every corner shares one latch: after a corner fires, none fires again until the pointer has left it, so resting in a corner never repeats an action.

Hot corners default to the outermost display: left corners use the leftmost display, and right corners use the rightmost. If displays share that edge, the topmost or bottommost one wins according to the corner. Enable **Hot corners → Use on all displays** to use every corner on every display. Avoid giving a corner to Exposé and to another hot-corner plugin at once.

Settings saved by older versions keep working: the one corner chosen there opens all windows until you change any corner.

## Settings

Open **Settings** from the footer while the overview is open. It is fully keyboard driven: 1-6 jump to a section, Up/Down move between controls, Left/Right adjust sliders and choices, Space or Enter flip toggles and press buttons, Escape closes. Changes apply immediately. Settings are grouped into **Appearance**, **Windows**, **Window labels**, **Workspaces**, **Hot corners**, and **Motion**, with explanatory text beneath the controls:

- Opening animation: Original (default), Fade, Zoom, or Slide. With Omarchy's animations off (`omarchy toggle animations`), the overview appears and disappears at once
- Animation duration saved per mode, linked for in/out by default or expandable to separate timings
- Slide direction: left (default), right, up, or down. Splitting in/out splits both speed and direction
- Background: Desktop (default) or Wallpaper, with blur (0–20) and dim (0–90)
- Selection highlight: outline (default) or lift, which raises and lights only the window Enter opens and marks the current one with a dot
- Quick Look position: in-place or centered
- Opens with: all workspaces (default) or the current workspace; Tab still switches either way
- Workspace names: full (default) or slot only, which prints just the trailing slot of names like `<monitor description>:3` that per-monitor workspace plugins produce
- Window footer style: floating, integrated, overlay, or centered
- Workspace strip: on (default) or off. Each display shows its own numbered workspaces with live previews of their windows, and a **+** tile that adds an empty workspace to the strip without closing Exposé. Dragging windows onto the strip can be turned off separately
- Windows to include: All displays (one grid with every window), This display (one grid with that display's windows), or Each display (one grid of local windows per display)
- Bottom text visibility. Hiding it requires confirmation and removes the Settings link
- Hot corners on/off, an action for each corner (All windows, App windows, Desktop, or Off; top left opens all windows by default), All displays (off by default), and activation delay (0–1000 ms of pointer dwell before it fires; 0 is instant)
- Move cursor to the activated window on/off
- Close button: off (default) or on, a ✕ on the window under the pointer that closes it, in its top right (default) or top left corner

**Wallpaper** covers the original desktop windows with the current Omarchy
wallpaper on every display, cropped to fill each screen. It follows background
changes while the overview is open, and shows a video wallpaper as the same
still the lock screen uses. Blur and dim apply to the wallpaper; Desktop
keeps the existing translucent backdrop. If the wallpaper is missing or cannot
be loaded, Wallpaper uses a solid theme background instead.

Every reversible setting is also scriptable:

```sh
omarchy-shell expose toggle                      # all windows; also: open, close
omarchy-shell expose toggleApplication           # the focused app's windows; also: openApplication
omarchy-shell expose toggleDesktop               # show the desktop, or bring the windows back
omarchy-shell expose desktop show                # show | hide | toggle | state
omarchy-shell expose settings toggle             # also: open, close
omarchy-shell expose animationStyle original     # original | fade | zoom | slide
omarchy-shell expose animationDuration original 190    # linked in/out, 100-800 ms
omarchy-shell expose animationDurationIn original 190  # separate opening speed
omarchy-shell expose animationDurationOut original 190 # separate closing speed
omarchy-shell expose slideDirection left         # left | right | up | down, both halves
omarchy-shell expose slideDirectionIn left       # separate opening side, also splits slide timing
omarchy-shell expose slideDirectionOut right     # separate closing side, also splits slide timing
omarchy-shell expose backgroundMode wallpaper    # desktop | wallpaper
omarchy-shell expose backgroundBlur 4            # 0-20
omarchy-shell expose backgroundDim 6             # 0-90
omarchy-shell expose previewPlacement in-place   # in-place | centered
omarchy-shell expose windowFooterStyle floating  # floating | integrated | overlay | centered
omarchy-shell expose selectionStyle outline      # outline | lift
omarchy-shell expose multiMonitorMode mirrored   # mirrored | per-monitor
omarchy-shell expose hotCorner on                # on | off, every corner
omarchy-shell expose hotCornerAction bottom-left app-windows  # corner: off | all-windows | app-windows | desktop
omarchy-shell expose hotCorners                  # JSON: every corner's action
omarchy-shell expose hotCornerPosition top-left  # older form: that corner opens all windows, alone
omarchy-shell expose hotCornerAllDisplays off    # off: outermost display (default) | on: every display
omarchy-shell expose hotCornerDelay 0            # 0-1000 ms of dwell before it fires
omarchy-shell expose moveCursorToWindow on       # on | off
omarchy-shell expose initialWorkspaceScope all   # all | current
omarchy-shell expose workspaceLabelStyle full    # full | slot
omarchy-shell expose workspaceStrip on           # on | off
omarchy-shell expose workspaceDrag on            # on | off, with the strip on
omarchy-shell expose showFooter on               # on | off
omarchy-shell expose closeButton off             # off | on
omarchy-shell expose closeButtonSide right       # left | right
```

Scripts can also read state and drive an open overview the way its keys do:

```sh
omarchy-shell expose state                       # JSON: opened, mode, app, scope, filter, windows, selection (and address), preview, desktop
omarchy-shell expose get backgroundBlur          # any setting above by its stored name
omarchy-shell expose move right                  # left | right | up | down
omarchy-shell expose filter term                 # answers the number of matching windows
omarchy-shell expose preview                     # toggle Quick Look on the selection
omarchy-shell expose activate                    # open the selected window
```

After hiding the bottom text, you can restore it while Settings remains open. If you close Settings first, run `omarchy-shell expose showFooter on`.

## Security and system changes

Exposé runs unsandboxed inside Omarchy Shell with your user's permissions.

- Its blur helper is plain Bash calling `hyprctl`, `jq`, `flock`, and `timeout`. Window focus goes through Omarchy Shell's own Hyprland connection.
- It reads window, workspace, and monitor state from Quickshell's native Hyprland model, activates or closes the windows you select, and temporarily raises Hyprland's blur while open, restoring the previous value on close.
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
