-- Edit form of one creature: record -> form values (strings as typed), form -> changed fields for
-- pokemon.core `encode_pokemon`, and the checks that run before anything is encoded.
-- Pure: no uz access.
local M = {}

M.STATS = { "hp", "atk", "def", "spe", "spa", "spd" }
M.MOVE_SLOTS = 4

-- Limits used when the core does not report any (older core): the Gen 6 values.
M.DEFAULT_LIMITS = { species = 721, move = 617, item = 775, level = 100, iv = 31, ev = 255, ev_total = 510, nature = 24,
  money = 999999, item_count = 999 }

-- Bag pouches in display order (names as the core reports them).
M.POUCHES = { "items", "medicine", "berries", "tms", "key_items" }

--- Largest count a pouch takes: the core's per-pouch limit, else the general item count limit.
function M.pouch_max(limits, pouch)
  local p = type(limits.pouches) == "table" and limits.pouches[pouch] or nil
  return (p and p.max_count) or limits.item_count or 999
end

--- Pouches to offer: the ones the core lists in edit_limits (display order), else all known.
function M.pouches_of(limits)
  if type(limits.pouches) ~= "table" or next(limits.pouches) == nil then return M.POUCHES end
  local out = {}
  for _, n in ipairs(M.POUCHES) do if limits.pouches[n] then out[#out + 1] = n end end
  return #out > 0 and out or M.POUCHES
end

--- Rows of a pouch whose name contains the filter (case-insensitive); id as "#id" when the name is unknown.
function M.filter_rows(rows, filter)
  local f = (filter or ""):lower()
  local out = {}
  for _, r in ipairs(rows or {}) do
    local label = (r.name and r.name ~= "") and r.name or ("#" .. tostring(r.item))
    if f == "" or label:lower():find(f, 1, true) then out[#out + 1] = r end
  end
  return out
end

local function limits_of(limits)
  local out = {}
  for k, v in pairs(M.DEFAULT_LIMITS) do out[k] = v end
  for k, v in pairs(limits or {}) do out[k] = v end
  return out
end
M.limits_of = limits_of

--- Whole non-negative number typed in a field: integer, or nil when it is not one.
function M.parse_int(s)
  if math.type(s) == "integer" then return s end
  if type(s) ~= "string" then return nil end
  local t = s:match("^%s*(%d+)%s*$")
  if not t or #t > 9 then return nil end
  return tonumber(t)
end

--- A form from a pokemon.core record (team() / box() entry).
function M.from_record(rec)
  local f = {
    species = rec.species, level = rec.level and tostring(rec.level) or "", nature = rec.nature or 0,
    shiny = rec.shiny == true, item = rec.held_item or 0, ivs = {}, evs = {}, moves = {},
  }
  for _, s in ipairs(M.STATS) do
    f.ivs[s] = tostring((rec.ivs or {})[s] or 0)
    f.evs[s] = tostring((rec.evs or {})[s] or 0)
  end
  for i = 1, M.MOVE_SLOTS do f.moves[i] = (rec.moves or {})[i] or 0 end
  return f
end

--- Sum of the EVs as typed (fields that are not numbers count as 0).
function M.ev_total(form)
  local n = 0
  for _, s in ipairs(M.STATS) do n = n + (M.parse_int(form.evs[s]) or 0) end
  return n
end

local function same_moves(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

local function compact(moves)
  local out = {}
  for i = 1, M.MOVE_SLOTS do if (moves[i] or 0) ~= 0 then out[#out + 1] = moves[i] end end
  return out
end

--- Compares the form with the record it came from. Returns fields (only what changed, the table that
--- goes to encode_pokemon) and errors ({ key = message key }); errors is empty when the form is valid.
--- Error keys: field names `level`, `iv_<stat>`, `ev_<stat>`, `ev_total`, `moves`.
function M.to_fields(form, rec, limits)
  local L = limits_of(limits)
  local fields, errs = {}, {}
  local base = M.from_record(rec)

  if form.species ~= base.species then
    if math.type(form.species) ~= "integer" or form.species < 1 or form.species > L.species then
      errs.species = "err_species"
    else
      fields.species = form.species
    end
  end

  local level = M.parse_int(form.level)
  if form.level ~= base.level or (rec.level == nil and form.level ~= "") then
    if level == nil or level < 1 or level > L.level then errs.level = "err_level" else fields.level = level end
  end

  if form.nature ~= base.nature then fields.nature = form.nature end
  if form.shiny ~= base.shiny then fields.shiny = form.shiny end
  if form.item ~= base.item then
    if math.type(form.item) ~= "integer" or form.item < 0 or form.item > L.item then errs.item = "err_item"
    else fields.held_item = form.item end
  end

  for _, kind in ipairs({ "ivs", "evs" }) do
    local hi = kind == "ivs" and L.iv or L.ev
    for _, s in ipairs(M.STATS) do
      if form[kind][s] ~= base[kind][s] then
        local v = M.parse_int(form[kind][s])
        if v == nil or v > hi then
          errs[(kind == "ivs" and "iv_" or "ev_") .. s] = kind == "ivs" and "err_iv" or "err_ev"
        else
          fields[kind] = fields[kind] or {}
          fields[kind][s] = v
        end
      end
    end
  end
  if fields.evs and M.ev_total(form) > L.ev_total then errs.ev_total = "err_ev_total" end

  local moves = compact(form.moves)
  if not same_moves(moves, compact(base.moves)) then
    local seen = {}
    local bad
    for _, m in ipairs(moves) do
      if seen[m] or m < 1 or m > L.move then bad = true end
      seen[m] = true
    end
    if #moves == 0 or bad then errs.moves = "err_moves" else fields.moves = moves end
  end
  return fields, errs
end

--- True when `rec` (read back from the core) shows what `fields` asked for.
function M.matches(fields, rec)
  if fields.species and rec.species ~= fields.species then return false end
  if fields.level and rec.level ~= nil and rec.level ~= fields.level then return false end
  if fields.nature and rec.nature ~= fields.nature then return false end
  if fields.shiny ~= nil and rec.shiny ~= fields.shiny then return false end
  if fields.held_item and rec.held_item ~= fields.held_item then return false end
  for _, kind in ipairs({ "ivs", "evs" }) do
    for s, v in pairs(fields[kind] or {}) do
      if ((rec[kind] or {})[s]) ~= v then return false end
    end
  end
  if fields.moves and not same_moves(rec.moves or {}, fields.moves) then return false end
  return true
end

--- Short list of option entries { value, label } from a names list ({ {id, name}, ... }): the entries whose
--- name contains `filter` (case-insensitive), at most `max`, the entry `current` always included first.
function M.filter_options(list, filter, current, max, label_of)
  max = max or 100
  local f = (filter or ""):lower()
  local out, seen = {}, {}
  local function label(e) return e.name ~= "" and e.name or label_of(e.id) end
  if current ~= nil then
    local lbl = label_of(current)
    for _, e in ipairs(list or {}) do if e.id == current then lbl = label(e) break end end
    out[1] = { value = current, label = lbl }
    seen[current] = true
  end
  for _, e in ipairs(list or {}) do
    if #out >= max then break end
    if not seen[e.id] and (f == "" or label(e):lower():find(f, 1, true)) then
      out[#out + 1] = { value = e.id, label = label(e) }
      seen[e.id] = true
    end
  end
  return out
end

return M
