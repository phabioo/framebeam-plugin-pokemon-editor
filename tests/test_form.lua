local t = require("t")
local form = require("model.form")
local fake = require("fake_core")

local REC = fake.rec(1, 25, { level = 20, nature = 3, held_item = 5, moves = { 33, 45 }, shiny = false })

t.case("from_record", function()
  local f = form.from_record(REC)
  t.eq(f.species, 25); t.eq(f.level, "20"); t.eq(f.nature, 3); t.eq(f.item, 5); t.eq(f.shiny, false)
  t.eq(f.moves, { 33, 45, 0, 0 })
  t.eq(f.ivs.hp, "10"); t.eq(f.evs.spd, "0")
  t.eq(form.from_record({ species = 1 }).level, "")
end)

t.case("an untouched form changes nothing", function()
  local fields, errs = form.to_fields(form.from_record(REC), REC)
  t.eq(fields, {}); t.eq(errs, {})
end)

t.case("only changed values go into fields", function()
  local f = form.from_record(REC)
  f.species, f.level, f.nature, f.shiny, f.item = 7, "35", 12, true, 99
  f.ivs.atk, f.evs.spa = "31", "252"
  f.moves = { 1, 0, 3, 0 }
  local fields, errs = form.to_fields(f, REC)
  t.eq(errs, {})
  t.eq(fields, { species = 7, level = 35, nature = 12, shiny = true, held_item = 99, ivs = { atk = 31 },
    evs = { spa = 252 }, moves = { 1, 3 } })
end)

t.case("validation messages", function()
  local function errs_of(change)
    local f = form.from_record(REC)
    change(f)
    return select(2, form.to_fields(f, REC))
  end
  t.eq(errs_of(function(f) f.level = "0" end), { level = "err_level" })
  t.eq(errs_of(function(f) f.level = "101" end), { level = "err_level" })
  t.eq(errs_of(function(f) f.level = "abc" end), { level = "err_level" })
  t.eq(errs_of(function(f) f.level = "" end), { level = "err_level" })
  t.eq(errs_of(function(f) f.ivs.hp = "32" end), { iv_hp = "err_iv" })
  t.eq(errs_of(function(f) f.ivs.hp = "-1" end), { iv_hp = "err_iv" })
  t.eq(errs_of(function(f) f.evs.atk = "256" end), { ev_atk = "err_ev" })
  t.eq(errs_of(function(f) f.evs.atk, f.evs.def, f.evs.hp = "255", "255", "1" end), { ev_total = "err_ev_total" })
  t.eq(errs_of(function(f) f.moves = { 0, 0, 0, 0 } end), { moves = "err_moves" })
  t.eq(errs_of(function(f) f.moves = { 5, 5, 0, 0 } end), { moves = "err_moves" })
  t.eq(errs_of(function(f) f.moves = { 618, 0, 0, 0 } end), { moves = "err_moves" })
  t.eq(errs_of(function(f) f.species = 722 end), { species = "err_species" })
  t.eq(errs_of(function(f) f.item = 776 end), { item = "err_item" })
  -- existing EVs count toward the total even if the field was not touched
  local rich = fake.rec(1, 25, { evs = { hp = 252, atk = 252, def = 0, spe = 0, spa = 0, spd = 0 } })
  local f = form.from_record(rich)
  f.evs.spa = "10"
  t.eq(select(2, form.to_fields(f, rich)), { ev_total = "err_ev_total" })
end)

t.case("a record without level: leaving the field empty sends no level", function()
  local r = fake.rec(1, 25, { level = false })
  r.level = nil
  local f = form.from_record(r)
  t.eq(form.to_fields(f, r), {})
  f.level = "12"
  t.eq(form.to_fields(f, r), { level = 12 })
end)

t.case("matches reads back fields", function()
  local rec = fake.rec(1, 7, { level = 35, nature = 12, shiny = true, held_item = 99, moves = { 1, 3 } })
  rec.ivs.atk, rec.evs.spa = 31, 252
  local fields = { species = 7, level = 35, nature = 12, shiny = true, held_item = 99, ivs = { atk = 31 },
    evs = { spa = 252 }, moves = { 1, 3 } }
  t.ok(form.matches(fields, rec))
  for _, bad in ipairs({ { species = 8 }, { level = 36 }, { nature = 1 }, { shiny = false }, { held_item = 1 },
    { ivs = { atk = 30 } }, { evs = { spa = 0 } }, { moves = { 1 } } }) do
    local f = {}
    for k, v in pairs(fields) do f[k] = v end
    for k, v in pairs(bad) do f[k] = v end
    t.ok(not form.matches(f, rec))
  end
  rec.level = nil
  t.ok(form.matches(fields, rec), "an unknown level is not a mismatch")
end)

t.case("filter_options keeps the current entry first and caps the count", function()
  local list = {}
  for i = 1, 300 do list[i] = { id = i, name = (i % 2 == 0) and ("Even" .. i) or ("Odd" .. i) } end
  local lbl = function(id) return "#" .. id end
  local all = form.filter_options(list, "", 250, 100, lbl)
  t.eq(#all, 100); t.eq(all[1], { value = 250, label = "Even250" })
  local f = form.filter_options(list, "odd1", 2, 100, lbl)
  t.eq(f[1].value, 2)
  for i = 2, #f do t.ok(f[i].label:lower():find("odd1", 1, true)) end
  t.eq(form.filter_options(nil, "x", 7, 10, lbl), { { value = 7, label = "#7" } })
  t.eq(form.filter_options(list, "zzz", nil, 10, lbl), {})
end)

t.case("parse_int", function()
  t.eq(form.parse_int("12"), 12); t.eq(form.parse_int(" 7 "), 7); t.eq(form.parse_int("1.5"), nil)
  t.eq(form.parse_int(""), nil); t.eq(form.parse_int("12345678901"), nil); t.eq(form.parse_int(5), 5)
end)
