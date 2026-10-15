-- ui-prompt.lua
local PROMPT = {}

function PROMPT.input(title, is_password, default)
  local value, event = ya.input({
    title = title,
    value = default or "",
    obscure = is_password or false,
    pos = { "center", y = 3, w = 60 },
  })
  return event == 1 and value or nil
end

function PROMPT.password(title)
  return PROMPT.input(title, true)
end

return PROMPT
