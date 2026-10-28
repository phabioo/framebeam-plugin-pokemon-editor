-- Fake `uz` for the Creature Editor tests (API 1 plus the 0.20 additions memory.write and UI blocks).
--   local m = uz_mock.new{ language = "de", core = <provider table> }
--   m.uz, m.ui.trees.panel, m.action(name, value), m.tick(n), m.writes, m.write_policy
local M = {}
local validator = require("ui_validator")

function M.read_json_flat(s)
  local out = {}
  local esc = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" }
  local pos = 1
  while true do
    local k, e = s:match('^%s*[{,]?%s*"([^"]*)"%s*:%s*()', pos)
    if not k then break end
    pos = e
    assert(s:sub(pos, pos) == '"', "flat string values only")
    pos = pos + 1
    local buf = {}
    while true do
      local c = s:sub(pos, pos)
      if c == "" then error("unterminated string") end
      if c == '"' then pos = pos + 1; break end
      if c == "\\" then
        local n = s:sub(pos + 1, pos + 1)
        if n == "u" then
          buf[#buf + 1] = utf8.char(tonumber(s:sub(pos + 2, pos + 5), 16)); pos = pos + 6
        else
          buf[#buf + 1] = assert(esc[n], "bad escape"); pos = pos + 2
        end
      else
        buf[#buf + 1] = c; pos = pos + 1
      end
    end
    out[k] = table.concat(buf)
  end
  return out
end

local function read_file(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("a"); f:close()
  return s
end

local function check_value(v, depth)
  local tv = type(v)
  if tv == "function" or tv == "userdata" or tv == "thread" then
    error("value of type " .. tv .. " cannot be passed between plugins", 3)
  end
  if tv == "table" then
    if depth > 32 then error("value too deep", 3) end
    for k, x in pairs(v) do
      if type(k) == "table" then error("table used as key", 3) end
      check_value(x, depth + 1)
    end
  end
end

local function deep_copy(v)
  if type(v) ~= "table" then return v end
  local c = {}
  for k, x in pairs(v) do c[k] = deep_copy(x) end
  return c
end
M.deep_copy = deep_copy

-- opts: language, core (provider for "pokemon.core"), no_write (older app: no uz.memory.write),
-- write_policy (function(addr, bytes) -> true | nil, reason; default accepts everything),
-- on_write (function(addr, bytes) called when a write was accepted: applies it to the fake world)
function M.new(opts)
  opts = opts or {}
  local mock = { logs = {}, events = {}, writes = {}, providers = {}, calls = {}, write_policy = opts.write_policy }
  local uz = { api = 1, plugin = { id = "uzume.creature-editor", version = "0.2.1" }, game = { language = opts.language } }
  mock.uz = uz

  uz.log = {}
  for _, level in ipairs({ "debug", "info", "warn", "error" }) do
    uz.log[level] = function(...)
      local parts = table.pack(...)
      for i = 1, parts.n do parts[i] = tostring(parts[i]) end
      mock.logs[#mock.logs + 1] = { level = level, text = table.concat(parts, "\t", 1, parts.n) }
    end
  end

  local handlers = {}
  function mock.fire_event(plugin_id, name, value)
    for _, h in ipairs(handlers) do
      if (h[1] == "*" or h[1] == plugin_id) and h[2] == name then h[3](deep_copy(value), plugin_id, name) end
    end
  end
  uz.events = {
    emit = function(name, value) check_value(value, 1); mock.events[#mock.events + 1] = { name = name, value = deep_copy(value) } end,
    on = function(plugin_id, name, fn) handlers[#handlers + 1] = { plugin_id, name, fn } end,
  }

  local tick_fn
  uz.on_tick = function(fn) tick_fn = fn end
  mock.frame = 0
  function mock.tick(n)
    for _ = 1, n or 1 do
      mock.frame = mock.frame + 1
      if tick_fn then tick_fn(mock.frame) end
    end
  end

  local dir = opts.i18n_dir or "plugin/i18n"
  local strings = M.read_json_flat(read_file(dir .. "/en.json"))
  if opts.language and opts.language ~= "en" then
    for k, v in pairs(M.read_json_flat(read_file(dir .. "/" .. opts.language .. ".json"))) do strings[k] = v end
  end
  mock.strings = strings
  uz.i18n = { t = function(key, vars)
    local s = strings[key] or key
    return (s:gsub("{([%w_]+)}", function(k) if vars and vars[k] ~= nil then return tostring(vars[k]) end end))
  end }

  if opts.core then mock.providers["pokemon.core"] = opts.core end
  function mock.set_provider(name, tbl) mock.providers[name] = tbl end
  uz.call = function(name, fn, ...)
    local p = mock.providers[name]
    if not p then error("no plugin provides " .. tostring(name), 2) end
    local f = p[fn]
    if type(f) ~= "function" then error("interface " .. name .. " has no function " .. tostring(fn), 2) end
    local args = table.pack(...)
    for i = 1, args.n do check_value(args[i], 1); args[i] = deep_copy(args[i]) end
    mock.calls[#mock.calls + 1] = { name = name, fn = fn, args = args }
    local res = table.pack(f(table.unpack(args, 1, args.n)))
    for i = 1, res.n do check_value(res[i], 1); res[i] = deep_copy(res[i]) end
    return table.unpack(res, 1, res.n)
  end

  -- uz.memory.write: contract of Uzume 0.20: true, or nil + "consent_required" | "blocked_by_run_rule" | "unmapped".
  uz.memory = {}
  if not opts.no_write then
    uz.memory.write = function(addr, bytes)
      if math.type(addr) ~= "integer" or type(bytes) ~= "string" or #bytes == 0 then error("bad write arguments", 2) end
      local ok, why = true, nil
      if mock.write_policy then ok, why = mock.write_policy(addr, bytes) end
      mock.writes[#mock.writes + 1] = { addr = addr, bytes = bytes, ok = ok and true or false, reason = why }
      if not ok then return nil, why end
      if opts.on_write then opts.on_write(addr, bytes) end
      return true
    end
  end

  local ui = { trees = {}, sets = {}, titles = {} }
  mock.ui = ui
  uz.ui = {
    set = function(slot, tree)
      if slot ~= "panel" then error("slot " .. tostring(slot) .. " not declared in manifest", 2) end
      local ok, err = validator.validate(tree)
      if not ok then error("ui tree: " .. err, 2) end
      ui.trees[slot] = deep_copy(tree)
      ui.sets[slot] = (ui.sets[slot] or 0) + 1
    end,
    clear = function(slot) ui.trees[slot] = nil end,
    title = function(slot, text) ui.titles[slot] = text end,
    on_action = function(fn) ui.handler = fn end,
  }
  function mock.action(action, value, slot) return ui.handler(action, deep_copy(value), slot or "panel") end
  function mock.find(id) return validator.find(ui.trees.panel, id) end
  function mock.texts()
    local out = {}
    local function walk(b)
      if b.text then out[#out + 1] = b.text end
      if b.title then out[#out + 1] = b.title end
      for _, c in ipairs(b.children or {}) do walk(c) end
      for _, r in ipairs(b.rows or {}) do out[#out + 1] = r.title; if r.sub then out[#out + 1] = r.sub end end
    end
    walk(ui.trees.panel)
    return table.concat(out, "\n")
  end
  return mock
end

return M
