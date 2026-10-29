-- Fake `pokemon.core` (contract v0.6: write helpers incl. bag/encode_item) with synthetic data only. Names are made up by code.
--   local core = fake_core.new{ ... }       core.provider -> mock.set_provider("pokemon.core", core.provider)
--   core.commit(addr, bytes)                 the mock's on_write hook: applies an encoded change to the world
--   core.world.hold = true                   accepted writes are not applied (simulates "game keeps old values")
local F = {}

local STATS = { "hp", "atk", "def", "spe", "spa", "spd" }

local function rec(slot, species, over)
  local r = { slot = slot, species = species, species_name = "Sp" .. species, nickname = "", level = 20, nature = 3,
    shiny = false, held_item = 0, moves = { 33, 45 }, ivs = {}, evs = {}, exp = 8000 }
  for _, s in ipairs(STATS) do r.ivs[s] = 10; r.evs[s] = 0 end
  for k, v in pairs(over or {}) do r[k] = v end
  return r
end
F.rec = rec

local function copy(v)
  if type(v) ~= "table" then return v end
  local c = {}
  for k, x in pairs(v) do c[k] = copy(x) end
  return c
end

function F.new(over)
  local w = {
    supported = true, edit = true,
    team = { rec(1, 25, { nickname = "Zap" }), rec(2, 7) },
    boxes = { [1] = { rec(1, 133), rec(4, 150) }, [2] = {} },
    money = 5000,
    old_core = false,   -- true: no bag()/encode_item(), features edit_items/bag off (core < 0.7.0)
    bag = {
      items = { { slot = 1, item = 4, count = 5 }, { slot = 2, item = 17, count = 30 }, { slot = 3, item = 9, count = 1 } },
      key_items = { { slot = 1, item = 500, count = 1 } },
      tms = {}, medicine = {}, berries = {},
    },
    limits = { species = 721, move = 617, item = 775, ability = 191, nature = 24, level = 100, iv = 31, ev = 255, ev_total = 510,
      money = 999999, item_count = 999,
      pouches = { items = { slots = 400, max_count = 999 }, key_items = { slots = 96, max_count = 1 }, tms = { slots = 108, max_count = 1 },
        medicine = { slots = 64, max_count = 999 }, berries = { slots = 72, max_count = 999 } },
      team_slots = 6, boxes = 31, box_slots = 30 },
    names_ready = true,
    off = {},       -- function name -> reason ("not_ready", ...)
    encode_error = nil,
    warnings = {},
    calls = {},
  }
  for k, v in pairs(over or {}) do w[k] = v end
  local self = { world = w, pending = {} }

  local function guard(fn, f)
    return function(...)
      w.calls[fn] = (w.calls[fn] or 0) + 1
      if w.off[fn] then return nil, w.off[fn] end
      return f(...)
    end
  end

  local function name_of(kind, id)
    if kind == "species" then return "Sp" .. id end
    if kind == "move" then return "Mv" .. id end
    if kind == "item" then return "It" .. id end
    if kind == "nature" then return "Nat" .. id end
  end

  local function list_of(kind, max, first)
    local out = {}
    for i = first or 1, max do out[#out + 1] = { id = i, name = name_of(kind, i) } end
    return out
  end

  local function find(list, slot)
    for _, r in ipairs(list) do if r.slot == slot then return r end end
  end

  local p = {}
  p.info = guard("info", function()
    return { game_id = "pokemon_omega_ruby", supported = w.supported, language = "en", features = {
      team = true, box = true, trainer = true, names = true, edit_pokemon = w.edit, edit_money = w.edit, edit_items = not w.old_core, bag = not w.old_core,
      name_lists = true } }
  end)
  p.edit_limits = guard("edit_limits", function() return copy(w.limits) end)
  p.team = guard("team", function() return copy(w.team) end)
  p.box_count = guard("box_count", function() return 31 end)
  p.box = guard("box", function(n) return copy(w.boxes[n] or {}) end)
  p.trainer = guard("trainer", function() return { name = "Tester", money = w.money } end)
  p.name = guard("name", function(kind, id) return name_of(kind, id) end)
  p.names_list = guard("names_list", function(kind)
    if not w.names_ready then return nil, "not_ready" end
    if kind == "species" then return list_of("species", 721) end
    if kind == "move" then return list_of("move", 617) end
    if kind == "item" then return list_of("item", 775) end
    return nil, "unknown_kind"
  end)

  local function apply_fields(r, f)
    for _, k in ipairs({ "species", "level", "nature", "shiny", "held_item" }) do
      if f[k] ~= nil then r[k == "held_item" and "held_item" or k] = f[k] end
    end
    if f.species then r.species_name = "Sp" .. f.species end
    for _, kind in ipairs({ "ivs", "evs" }) do
      for s, v in pairs(f[kind] or {}) do r[kind][s] = v end
    end
    if f.moves then r.moves = copy(f.moves) end
  end

  p.encode_pokemon = guard("encode_pokemon", function(loc, fields)
    if w.encode_error then return nil, w.encode_error end
    local r, addr
    if loc.kind == "team" then
      r = find(w.team, loc.slot); addr = 0x1000 + loc.slot * 0x200
    elseif loc.kind == "box" then
      r = find(w.boxes[loc.box] or {}, loc.slot); addr = 0x100000 + (loc.box * 30 + loc.slot) * 0x100
    else
      return nil, "invalid_location"
    end
    if not r then return nil, "empty_slot" end
    local bytes = string.format("PK:%d:%s", addr, tostring(#self.pending))
    self.pending[addr] = { bytes = bytes, apply = function() apply_fields(r, fields) end }
    local ops = { { addr = addr, bytes = bytes } }
    if w.two_ops then ops[2] = { addr = addr + 0x158, bytes = "EXT" } end
    return { addr = addr, bytes = bytes, ops = ops, warnings = copy(w.warnings) }
  end)
  p.encode_money = guard("encode_money", function(value)
    if math.type(value) ~= "integer" or value < 0 or value > w.limits.money then return nil, "invalid_money" end
    local bytes = string.pack("<I4", value)
    self.pending[0x9000] = { bytes = bytes, apply = function() w.money = value end }
    return { addr = 0x9000, bytes = bytes, ops = { { addr = 0x9000, bytes = bytes } }, warnings = {} }
  end)

  local function bag_rows()
    local out = {}
    for pouch, rows in pairs(w.bag) do
      out[pouch] = {}
      for i, r in ipairs(rows) do out[pouch][i] = { slot = i, item = r.item, count = r.count, name = "It" .. r.item } end
    end
    return out
  end
  if not w.old_core then
    p.bag = guard("bag", function() return bag_rows() end)
    p.encode_item = guard("encode_item", function(pouch, item, count, slot)
      local rows = w.bag[pouch]
      local lim = w.limits.pouches[pouch]
      if not rows then return nil, "unknown_pouch" end
      if math.type(item) ~= "integer" or item < 1 or item > w.limits.item then return nil, "invalid_item" end
      if math.type(count) ~= "integer" or count < 0 or count > lim.max_count then return nil, "invalid_count" end
      local idx = slot
      if idx == nil then for i, r in ipairs(rows) do if r.item == item then idx = i end end end
      if idx == nil then
        if count == 0 then return nil, "invalid_item" end
        if #rows >= lim.slots or w.pouch_full then return nil, "pouch_full" end
        idx = #rows + 1
      end
      if idx < 1 or idx > #rows + 1 then return nil, "invalid_slot" end
      local bytes = string.format("IT:%s:%d:%d:%d", pouch, idx, item, count)
      local ops = { { addr = 0xA000 + idx * 4, bytes = bytes } }
      if count == 0 and idx < #rows then ops[2] = { addr = 0xB000 + idx * 4, bytes = "SHIFT" } end
      self.pending[ops[1].addr] = { bytes = bytes, apply = function()
        if count == 0 then table.remove(rows, idx) elseif rows[idx] then rows[idx] = { item = item, count = count }
        else rows[idx] = { item = item, count = count } end
      end }
      return { addr = ops[1].addr, bytes = bytes, ops = ops, warnings = {}, pouch = pouch, slot = idx }
    end)
  end

  self.provider = p
  function self.commit(addr, bytes)
    local e = self.pending[addr]
    if e and e.bytes == bytes and not w.hold then e.apply() end
  end
  return self
end

return F
