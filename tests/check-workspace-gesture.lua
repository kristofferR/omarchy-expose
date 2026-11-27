-- Checks workspace-gesture.lua against a model of Hyprland's gesture table and
-- the installed Omarchy's default gestures. The model follows Hyprland 0.57
-- (TrackpadGestures.cpp): a swipe runs the first gesture that matches it, a new
-- gesture is refused when an earlier one on its axis shadows it, and removing a
-- gesture that is not there is an error.
--
-- Usage: lua tests/check-workspace-gesture.lua [omarchy-dir]

local root = arg[0]:match("^(.*)/tests/[^/]+$") or "."
local omarchy_gestures = (arg[1] or "/usr/share/omarchy") .. "/default/hypr/gestures.lua"
local namespace = "expose-window-overview"
local axis_of = { left = "horizontal", right = "horizontal", up = "vertical", down = "vertical" }

local function hyprland(open_layers)
  local state = { gestures = {}, errors = {}, dispatched = {}, handlers = {}, layers = open_layers or 0 }
  local hl = { dsp = { window = {} } }

  function hl.dsp.focus(target) return "focus " .. tostring(target.workspace) end
  function hl.dsp.window.move(target) return "move " .. tostring(target.workspace) end
  function hl.dsp.global(name) return "global " .. name end
  function hl.dispatch(what) table.insert(state.dispatched, what) end

  function hl.get_layers()
    local layers = {}
    for index = 1, state.layers do layers[index] = { namespace = namespace } end
    return layers
  end

  function hl.on(event, handler)
    state.handlers[event] = state.handlers[event] or {}
    table.insert(state.handlers[event], handler)
  end

  function hl.gesture(spec)
    local scale = spec.scale or 1
    local name = spec.fingers .. " fingers " .. spec.direction
    if spec.action == "unset" then
      for index, gesture in ipairs(state.gestures) do
        if gesture.fingers == spec.fingers and gesture.direction == spec.direction and gesture.scale == scale then
          table.remove(state.gestures, index)
          return
        end
      end
      table.insert(state.errors, "removed a gesture that is not there: " .. name)
      return
    end

    local axis = axis_of[spec.direction] or spec.direction
    for _, gesture in ipairs(state.gestures) do
      if gesture.fingers == spec.fingers and (gesture.direction == axis or gesture.direction == spec.direction) then
        table.insert(state.errors, "shadowed by an earlier gesture: " .. name)
        return
      end
    end
    table.insert(state.gestures, { fingers = spec.fingers, direction = spec.direction, scale = scale, action = spec.action })
  end

  -- What a swipe does: a built-in action's name, what a function dispatched,
  -- "nothing" for a function that dispatched nothing, or "unmatched".
  function state.swipe(fingers, direction)
    state.dispatched = {}
    for _, gesture in ipairs(state.gestures) do
      if gesture.fingers == fingers and (gesture.direction == direction or gesture.direction == axis_of[direction]) then
        if type(gesture.action) ~= "function" then return gesture.action end
        gesture.action()
        return state.dispatched[1] or "nothing"
      end
    end
    return "unmatched"
  end

  function state.expose(event)
    state.layers = state.layers + (event == "opened" and 1 or -1)
    for _, handler in ipairs(state.handlers["layer." .. event] or {}) do handler({ namespace = namespace }) end
  end

  state.hl = hl
  return state
end

local function expect(actual, expected, what)
  if actual ~= expected then
    error(what .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

-- Loads the helper as input.lua would, after Omarchy's gestures when the
-- scenario has them. `check` gets the model and what Omarchy's own three-finger
-- swipes did before the helper loaded.
local function scenario(with_omarchy, options, check, open_layers)
  local state = hyprland(open_layers)
  local omarchy = {}
  _G.hl = state.hl
  package.loaded["default.hypr.gestures"] = nil
  if with_omarchy then
    dofile(omarchy_gestures)
    package.loaded["default.hypr.gestures"] = true
    omarchy.left, omarchy.right = state.swipe(3, "left"), state.swipe(3, "right")
    omarchy.move = state.swipe(4, "left")
  end

  dofile(root .. "/workspace-gesture.lua")(options)
  check(state, omarchy)
  expect(table.concat(state.errors, "; "), "", "config errors")
end

local function check_hyprland_swipe(state, fingers)
  expect(state.swipe(fingers, "left"), "workspace", "swipe with Exposé closed")
  state.expose("opened")
  expect(state.swipe(fingers, "left"), "nothing", "swipe with Exposé open")
  expect(state.swipe(fingers, "right"), "nothing", "swipe with Exposé open")
  state.expose("closed")
  expect(state.swipe(fingers, "right"), "workspace", "swipe after Exposé closed")
end

-- Without Omarchy's gestures: Hyprland's swipe, as chosen or on three fingers.
scenario(false, { fingers = 4, scale = 0.5 }, function(state) check_hyprland_swipe(state, 4) end)
scenario(false, nil, function(state) check_hyprland_swipe(state, 3) end)

-- A config reload while Exposé is open starts paused.
scenario(false, nil, function(state)
  expect(state.swipe(3, "left"), "nothing", "swipe when loaded with Exposé open")
  state.expose("closed")
  expect(state.swipe(3, "left"), "workspace", "swipe after Exposé closed")
end, 1)

local file = io.open(omarchy_gestures)
if not file then
  print("workspace gesture check: no " .. omarchy_gestures .. ", so only the checks without Omarchy's gestures ran")
  return
end
file:close()

-- Omarchy's own swipe keeps doing what Omarchy defined, except behind Exposé.
scenario(true, nil, function(state, omarchy)
  expect(state.swipe(3, "left"), omarchy.left, "Omarchy's swipe left")
  expect(state.swipe(3, "right"), omarchy.right, "Omarchy's swipe right")
  state.expose("opened")
  expect(state.swipe(3, "left"), "nothing", "Omarchy's swipe with Exposé open")
  expect(state.swipe(3, "right"), "nothing", "Omarchy's swipe with Exposé open")
  state.expose("closed")
  expect(state.swipe(3, "left"), omarchy.left, "Omarchy's swipe after Exposé closed")
  expect(state.swipe(4, "left"), omarchy.move, "Omarchy's four-finger swipe")
end)

-- Hyprland's swipe on four fingers takes over Omarchy's window move there, and
-- Omarchy's three-finger swipe is paused along with it.
scenario(true, { fingers = 4, scale = 0.5 }, function(state, omarchy)
  expect(state.swipe(3, "left"), omarchy.left, "Omarchy's swipe left")
  check_hyprland_swipe(state, 4)
  state.expose("opened")
  expect(state.swipe(3, "left"), "nothing", "Omarchy's swipe with Exposé open")
end)

-- On three fingers it replaces Omarchy's swipe, leaving four fingers alone.
scenario(true, { fingers = 3 }, function(state, omarchy)
  check_hyprland_swipe(state, 3)
  expect(state.swipe(4, "left"), omarchy.move, "Omarchy's four-finger swipe")
end)

print("workspace gesture check: all checks passed")
