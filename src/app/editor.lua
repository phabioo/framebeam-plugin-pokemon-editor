-- Controller of the Creature Editor: reads through the `pokemon.core` interface, keeps the panel state,
-- turns "Apply" into encode_pokemon / encode_money calls and writes the returned operations with
-- fb.memory.write (permission memory.write; consent, the save snapshot and the run rules belong to the app).
-- After a write the creature is read back and compared before the editor says "applied".
local form_mod = require("model.form")
local panel = require("ui.panel")

local M = {}

M.CORE_ID = "uzume.soullink-core"
M.CHECK_EVERY = 5   -- ticks between read-back attempts
M.CHECK_MAX = 12    -- attempts before "not confirmed"
M.RETRY_EVERY = 30  -- ticks between retries of the core and the name lists
M.REFRESH_EVERY = 90

local NAME_KINDS = { "species", "move", "item" }

function M.start(fb)
  local function tr(key, vars) return fb.i18n.t(key, vars) end

  local S = {
    view = "list", tab = "team", box = 1, filters = { species = "", move = "", item = "" }, money = "", errors = {},
  }
  local core = { state = "wait", features = {}, limits = form_mod.limits_of(nil) }
  local names = { species = nil, move = nil, item = nil, nature = {} }
  local team, box, trainer, box_count = {}, {}, nil, 31
  local ticks = 0

  local self = { state = S, core = core, names = names }

  -- ---- core access ----

  -- fb.call into pokemon.core; returns the results, or nil, "call_failed" when the call itself raised.
  local function call(fn, ...)
    local res = table.pack(pcall(fb.call, "pokemon.core", fn, ...))
    if not res[1] then return nil, "call_failed" end
    return res[2], res[3]
  end

  local function can_write()
    return type(fb.memory) == "table" and type(fb.memory.write) == "function"
  end

  local function load_names()
    local missing = false
    for _, kind in ipairs(NAME_KINDS) do
      if not names[kind] then
        local l = call("names_list", kind)
        if type(l) == "table" and #l > 0 then names[kind] = l else missing = true end
      end
    end
    local count = 0
    for _ in pairs(names.nature) do count = count + 1 end
    if count <= core.limits.nature then
      for n = 0, core.limits.nature do
        if not names.nature[n] then
          local nm = call("name", "nature", n)
          if type(nm) == "string" and nm ~= "" then names.nature[n] = nm else missing = true end
        end
      end
    end
    names.ready = not missing
  end

  local function refresh_data()
    team = call("team") or {}
    if S.tab == "box" or S.view == "edit" then box = call("box", S.box) or {} end
    local n = call("box_count")
    if math.type(n) == "integer" and n >= 1 then box_count = n end
    trainer = call("trainer")
  end

  local function init()
    local info = call("info")
    if type(info) ~= "table" then core.state = "no_core"; return end
    core.features = info.features or {}
    if not info.supported or not core.features.edit_pokemon then core.state = "unsupported"; return end
    if not can_write() then core.state = "no_write"; return end
    local lim = call("edit_limits")
    if type(lim) == "table" then core.limits = form_mod.limits_of(lim) end
    core.state = "ready"
    load_names()
    refresh_data()
  end

  -- ---- rendering ----

  local function render()
    local ok, tree = pcall(panel.build, {
      tr = tr, state = S, core = core, names = names, team = team, box = box, box_count = box_count, trainer = trainer,
    })
    if not ok then fb.log.error("panel build failed: " .. tostring(tree)); return end
    local set_ok, err = pcall(fb.ui.set, "panel", tree)
    if not set_ok then fb.log.error("ui.set failed: " .. tostring(err)) end
  end
  self.render = render

  local function say(tone, text) S.msg = { tone = tone, text = text } end

  -- ---- writing ----

  local WRITE_MSG = { consent_required = "msg_consent", blocked_by_run_rule = "msg_blocked", unmapped = "msg_unmapped" }

  local function write_error(reason, partial)
    local key = WRITE_MSG[reason]
    local text
    if key then
      text = tr(key)
    elseif reason == "permission" then
      text = tr("msg_no_permission")
    else
      local code = type(reason) == "string" and reason:gsub("[^%w_ ]", ""):sub(1, 40) or "unknown"
      text = tr("msg_write_failed", { code = code })
    end
    if partial then text = text .. " " .. tr("msg_partial") end
    return text
  end

  -- Writes every op in order. Returns true, or false + message.
  local function write_ops(ops)
    for i, op in ipairs(ops) do
      local res = table.pack(pcall(fb.memory.write, op.addr, op.bytes))
      if not res[1] then return false, write_error("permission", i > 1) end
      if res[2] ~= true then return false, write_error(res[3], i > 1) end
    end
    return true
  end

  local CORE_ERR = { not_ready = "err_core_not_ready", empty_slot = "err_empty_slot", growth_unavailable = "err_growth",
    ev_total = "err_ev_total", invalid_location = "err_empty_slot", unsupported = "err_unsupported",
    invalid_money = "err_money" }

  local function core_error(why)
    local key = CORE_ERR[why]
    if key then return tr(key) end
    if type(why) == "string" and why:match("^invalid_") then return tr("err_invalid_field", { field = why:sub(9) }) end
    return tr("err_core", { code = type(why) == "string" and why:gsub("[^%w_:]", ""):sub(1, 40) or "unknown" })
  end

  local WARN = { pp_unknown = "warn_pp", ability_unchanged = "warn_ability", stats_stale = "warn_stats",
    exp_unchanged = "warn_exp" }

  local function warning_text(warnings)
    local out = {}
    for _, w in ipairs(warnings or {}) do
      if WARN[w] then out[#out + 1] = tr(WARN[w]) end
    end
    return table.concat(out, " ")
  end

  local function find_slot(list, slot)
    for _, r in ipairs(list or {}) do if r.slot == slot then return r end end
    return nil
  end

  local function current_record(target)
    if target.kind == "team" then return find_slot(call("team"), target.slot) end
    return find_slot(call("box", target.box), target.slot)
  end

  local function finish_pending(ok)
    local p = S.pending
    S.pending = nil
    if p.kind == "pokemon" then
      if ok then
        local rec = current_record(p.target)
        if rec and S.target and S.target.kind == p.target.kind and S.target.slot == p.target.slot
          and S.target.box == p.target.box then
          S.rec, S.form, S.errors = rec, form_mod.from_record(rec), {}
        end
        say("ok", (tr("msg_applied") .. " " .. warning_text(p.warnings)):gsub("%s+$", ""))
      else
        say("warning", tr("msg_unconfirmed"))
      end
    else
      if ok then say("ok", tr("msg_money_applied", { n = p.value })) else say("warning", tr("msg_unconfirmed")) end
    end
    refresh_data()
    render()
  end

  local function check_pending()
    local p = S.pending
    p.tries = p.tries + 1
    local ok = false
    if p.kind == "pokemon" then
      local rec = current_record(p.target)
      ok = rec ~= nil and form_mod.matches(p.fields, rec)
    else
      local t = call("trainer")
      ok = type(t) == "table" and t.money == p.value
    end
    if ok or p.tries >= M.CHECK_MAX then finish_pending(ok) end
  end

  -- ---- actions ----

  local H = {}

  function H.tab(v)
    if v ~= "team" and v ~= "box" and v ~= "bag" then return end
    S.tab, S.msg = v, nil
    refresh_data()
  end

  function H.box_select(v)
    if math.type(v) ~= "integer" or v < 1 or v > box_count then return end
    S.box = v
    box = call("box", v) or {}
  end

  function H.edit(v)
    if type(v) ~= "table" then return end
    local rec
    if v.kind == "team" then
      team = call("team") or team
      rec = find_slot(team, v.slot)
    elseif v.kind == "box" then
      box = call("box", v.box) or box
      rec = find_slot(box, v.slot)
    end
    if not rec then
      say("warning", tr("err_empty_slot"))
      return
    end
    S.target = { kind = v.kind, slot = v.slot, box = v.box }
    S.rec, S.form, S.errors, S.msg = rec, form_mod.from_record(rec), {}, nil
    S.filters = { species = "", move = "", item = "" }
    S.view = "edit"
  end

  function H.back() S.view, S.form, S.msg, S.pending = "list", nil, nil, nil; refresh_data() end
  function H.dismiss() S.msg = nil end
  function H.reset() if S.rec then S.form, S.errors, S.msg = form_mod.from_record(S.rec), {}, nil end end

  local function revalidate()
    local _, errs = form_mod.to_fields(S.form, S.rec, core.limits)
    S.errors = errs
  end

  function H.species(v) S.form.species = v; revalidate() end
  function H.species_filter(v) S.filters.species = tostring(v or "") end
  function H.move_filter(v) S.filters.move = tostring(v or "") end
  function H.item_filter(v) S.filters.item = tostring(v or "") end
  function H.level(v) S.form.level = tostring(v or ""); revalidate() end
  function H.nature(v) S.form.nature = v; revalidate() end
  function H.shiny(v) S.form.shiny = v == true; revalidate() end
  function H.item(v) S.form.item = v; revalidate() end

  function H.apply()
    if not S.form or S.pending then return end
    local fields, errs = form_mod.to_fields(S.form, S.rec, core.limits)
    S.errors = errs
    if next(errs) then say("warning", tr("msg_fix_fields")); return end
    if next(fields) == nil then say("info", tr("msg_nothing")); return end
    local target = { kind = S.target.kind, slot = S.target.slot, box = S.target.box }
    local loc = target.kind == "team" and { kind = "team", slot = target.slot }
      or { kind = "box", box = target.box, slot = target.slot }
    local res, why = call("encode_pokemon", loc, fields)
    if not res then say("danger", core_error(why)); return end
    local ok, text = write_ops(res.ops or { { addr = res.addr, bytes = res.bytes } })
    if not ok then say("danger", text); return end
    S.pending = { kind = "pokemon", target = target, fields = fields, tries = 0, warnings = res.warnings }
    say("info", tr("msg_sent"))
  end

  function H.money_input(v) S.money, S.money_err = tostring(v or ""), nil end

  function H.money_apply()
    if S.pending then return end
    local n = form_mod.parse_int(S.money)
    if n == nil or n > core.limits.money then S.money_err = "err_money"; return end
    local res, why = call("encode_money", n)
    if not res then say("danger", core_error(why)); return end
    local ok, text = write_ops(res.ops or { { addr = res.addr, bytes = res.bytes } })
    if not ok then say("danger", text); return end
    S.pending = { kind = "money", value = n, tries = 0 }
    say("info", tr("msg_sent"))
  end

  local function on_action(action, value)
    local handler = H[action]
    if handler then
      handler(value)
    else
      local kind, stat = action:match("^(%a+)_(%a+)$")
      if kind == "iv" or kind == "ev" then
        if S.form then
          S.form[kind == "iv" and "ivs" or "evs"][stat] = tostring(value or "")
          revalidate()
        end
      elseif action:match("^move_%d$") and S.form then
        local i = tonumber(action:sub(6))
        if i >= 1 and i <= form_mod.MOVE_SLOTS then S.form.moves[i] = value; revalidate() end
      end
    end
    render()
  end

  -- ---- start ----

  fb.ui.on_action(function(action, value, slot)
    if slot ~= "panel" then return end
    local ok, err = pcall(on_action, action, value)
    if not ok then
      fb.log.error("action " .. tostring(action) .. " failed: " .. tostring(err))
      say("danger", tr("err_internal"))
      render()
    end
  end)

  fb.on_tick(function()
    ticks = ticks + 1
    if S.pending and ticks % M.CHECK_EVERY == 0 then check_pending() end
    if ticks % M.RETRY_EVERY == 0 then
      if core.state ~= "ready" then
        init()
        render()
      elseif not names.ready then
        load_names()
        if names.ready then render() end
      end
    end
    if core.state == "ready" and S.view == "list" and not S.pending and ticks % M.REFRESH_EVERY == 0 then
      refresh_data()
      render()
    end
  end)

  pcall(fb.events.on, M.CORE_ID, "team.changed", function()
    if core.state == "ready" and S.view == "list" and not S.pending then
      refresh_data()
      render()
    end
  end)

  fb.log.info(tr("loaded", { version = fb.plugin.version }))
  init()
  render()
  return self
end

return M
