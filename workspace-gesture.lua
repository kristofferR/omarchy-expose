return function(options)
  options = options or {}

  local namespace = "expose-window-overview"
  local expose_layers = #hl.get_layers({ namespace = namespace })
  local workspace_gesture_enabled

  local function register_gesture(action)
    local gesture = {
      fingers = options.fingers or 3,
      direction = "horizontal",
      action = action,
    }
    if options.scale ~= nil then gesture.scale = options.scale end

    hl.gesture(gesture)
  end

  local function apply_gesture()
    local enabled = expose_layers == 0
    if enabled == workspace_gesture_enabled then return end

    if workspace_gesture_enabled ~= nil then register_gesture("unset") end
    workspace_gesture_enabled = enabled
    register_gesture(enabled and "workspace" or function() end)
  end

  hl.on("layer.opened", function(layer)
    if layer.namespace ~= namespace then return end

    expose_layers = expose_layers + 1
    apply_gesture()
  end)

  hl.on("layer.closed", function(layer)
    if layer.namespace ~= namespace then return end

    expose_layers = math.max(0, expose_layers - 1)
    apply_gesture()
  end)

  apply_gesture()
end
