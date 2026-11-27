-- Keeps workspace swipes from changing the desktop behind Exposé. Loaded from
-- ~/.config/hypr/input.lua, as the README shows.
--
--   helper()                              Omarchy's three-finger swipe, paused
--                                         while Exposé is open
--   helper({ fingers = 4, scale = 0.5 })  Hyprland's workspace swipe, which
--                                         follows the fingers, paused likewise
--
-- Where Omarchy has no gestures of its own (before 4.6, or with
-- omarchy_default_gestures = false), helper() sets up Hyprland's swipe on
-- three fingers.
return function(options)
  options = options or {}

  local namespace = "expose-window-overview"
  local expose_layers = #hl.get_layers({ namespace = namespace })
  local omarchy_gestures = package.loaded["default.hypr.gestures"] ~= nil
  local swipe = options.fingers ~= nil or options.scale ~= nil or not omarchy_gestures
  local fingers = options.fingers or 3
  local swipe_enabled

  local function unset_omarchy_pair(count)
    hl.gesture({ fingers = count, direction = "left", action = "unset" })
    hl.gesture({ fingers = count, direction = "right", action = "unset" })
  end

  -- As Omarchy's own swipe in default/hypr/gestures.lua, but idle while Exposé
  -- is open.
  local function switch_workspace(workspace)
    return function()
      if expose_layers == 0 then hl.dispatch(hl.dsp.focus({ workspace = workspace })) end
    end
  end

  local function register_swipe(action)
    local gesture = {
      fingers = fingers,
      direction = "horizontal",
      action = action,
    }
    if options.scale ~= nil then gesture.scale = options.scale end

    hl.gesture(gesture)
  end

  -- Hyprland's swipe is a built-in action, so pausing it means swapping it for
  -- a gesture that does nothing.
  local function apply_swipe()
    local enabled = expose_layers == 0
    if not swipe or enabled == swipe_enabled then return end

    if swipe_enabled ~= nil then register_swipe("unset") end
    swipe_enabled = enabled
    register_swipe(enabled and "workspace" or function() end)
  end

  -- Hyprland runs the first gesture that matches a swipe, and Omarchy's come
  -- first: its workspace swipe on three fingers, and a window move on four.
  -- Those in the way are removed. Removing a gesture that is not there is a
  -- config error, so this happens only where Omarchy loaded its gestures.
  if omarchy_gestures then
    unset_omarchy_pair(3)
    if swipe and fingers == 4 then unset_omarchy_pair(4) end
    if not (swipe and fingers == 3) then
      hl.gesture({ fingers = 3, direction = "left", action = switch_workspace("r-1") })
      hl.gesture({ fingers = 3, direction = "right", action = switch_workspace("r+1") })
    end
  end

  hl.on("layer.opened", function(layer)
    if layer.namespace ~= namespace then return end

    expose_layers = expose_layers + 1
    apply_swipe()
  end)

  hl.on("layer.closed", function(layer)
    if layer.namespace ~= namespace then return end

    expose_layers = math.max(0, expose_layers - 1)
    apply_swipe()
  end)

  apply_swipe()
end
