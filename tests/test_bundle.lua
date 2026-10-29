local t = require("t")
local mock = require("uz_mock")
local fake_core = require("fake_core")

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("a")
  f:close()
  return s
end

t.case("plugin/main.lua is up to date", function()
  local p = assert(io.popen("lua5.4 tools/bundle.lua --check 2>&1"))
  local out = p:read("a")
  local ok = p:close()
  t.ok(ok, out)
end)

-- Run plugin/main.lua in a sandbox like the app: no require/load/io/os.
t.case("older app with only the global fb still starts", function()
  local core = fake_core.new()
  local m = mock.new({ language = "de", core = core.provider, on_write = core.commit })
  local env = { fb = m.uz }
  for _, n in ipairs({ "assert", "error", "getmetatable", "ipairs", "next", "pairs", "pcall", "select",
    "setmetatable", "tonumber", "tostring", "type", "xpcall", "rawequal", "rawget", "rawlen", "rawset",
    "string", "table", "math", "utf8", "coroutine" }) do
    env[n] = _G[n]
  end
  local chunk = assert(loadfile("plugin/main.lua", "t", env))
  chunk()
  t.eq(m.logs[1].text, "Kreatureneditor 0.3.0 geladen.")
  t.ok(m.ui.trees.panel)
end)

t.case("bundled plugin runs in a sandbox and draws the panel", function()
  local core = fake_core.new()
  local m = mock.new({ language = "de", core = core.provider, on_write = core.commit })
  local env = { uz = m.uz }
  for _, n in ipairs({ "assert", "error", "getmetatable", "ipairs", "next", "pairs", "pcall", "select",
    "setmetatable", "tonumber", "tostring", "type", "xpcall", "rawequal", "rawget", "rawlen", "rawset",
    "string", "table", "math", "utf8", "coroutine" }) do
    env[n] = _G[n]
  end
  local chunk = assert(loadfile("plugin/main.lua", "t", env))
  chunk()
  t.eq(m.logs[1].text, "Kreatureneditor 0.3.0 geladen.")
  t.ok(m.ui.trees.panel)
  m.action("edit", { kind = "team", slot = 1 })
  m.action("level", "33")
  m.action("apply")
  m.tick(5)
  t.eq(core.world.team[1].level, 33)
end)

t.case("sources use no sandbox-forbidden globals", function()
  local p = assert(io.popen("ls src/*.lua src/*/*.lua"))
  for path in p:lines() do
    local src = read(path)
    for _, bad in ipairs({ "io%.", "os%.", "package%.", "debug%.", "dofile", "loadstring", "[^%w_]load%(" }) do
      t.ok(not src:find(bad), path .. " uses " .. bad)
    end
  end
  p:close()
end)

t.case("manifest", function()
  local s = read("plugin/manifest.json")
  for _, needle in ipairs({
    '"id": "uzume.creature-editor"', '"name": "Creature Editor"', '"version": "0.3.0"', '"api": 1', '"replaces": ["uzume.monster-editor"]',
    '"uzume.soullink-core": ">=0.5.0"', '"000400000011C400"', '"000400000011C500"',
    '"permissions": [', '"memory.write"', '"entry": "main.lua"', '"min_player": "0.20.0"', '"title": "Editor"',
  }) do
    t.ok(s:find(needle, 1, true), "manifest lacks " .. needle)
  end
  t.ok(not s:find("memory.read", 1, true), "reads go through the core")
end)

t.case("i18n: German has exactly the keys of English, placeholders agree", function()
  local en = mock.read_json_flat(read("plugin/i18n/en.json"))
  local de = mock.read_json_flat(read("plugin/i18n/de.json"))
  for k, v in pairs(en) do
    t.ok(de[k] ~= nil, "de lacks " .. k)
    local a, b = {}, {}
    for ph in v:gmatch("{(%w+)}") do a[#a + 1] = ph end
    for ph in (de[k] or ""):gmatch("{(%w+)}") do b[#b + 1] = ph end
    table.sort(a); table.sort(b)
    t.eq(a, b, "placeholders of " .. k)
  end
  for k in pairs(de) do t.ok(en[k] ~= nil, "en lacks " .. k) end
end)

t.case("every i18n key used in src exists", function()
  local en = mock.read_json_flat(read("plugin/i18n/en.json"))
  local p = assert(io.popen("ls src/*/*.lua"))
  for path in p:lines() do
    for key in read(path):gmatch('tr%("([%w_]+)"[,%)]') do t.ok(en[key] ~= nil, path .. ": missing key " .. key) end
  end
  p:close()
  for _, tone in ipairs({ "ok", "info", "warning", "danger" }) do t.ok(en["msg_" .. tone]) end
  for _, s in ipairs({ "hp", "atk", "def", "spe", "spa", "spd" }) do t.ok(en["stat_" .. s]) end
  for _, k in ipairs({ "err_species", "err_level", "err_iv", "err_ev", "err_ev_total", "err_moves", "err_item", "err_money",
    "err_core_not_ready", "err_growth", "err_unsupported", "err_empty_slot", "warn_pp", "warn_ability", "warn_stats",
    "warn_exp", "msg_consent", "msg_blocked", "msg_unmapped" }) do
    t.ok(en[k], k)
  end
end)

t.case("no game names in UI strings", function()
  local en = read("plugin/i18n/en.json") .. read("plugin/i18n/de.json")
  for _, bad in ipairs({ "Pok[eé]mon", "Nintendo", "Omega", "Alpha" }) do t.ok(not en:find(bad), bad) end
end)
