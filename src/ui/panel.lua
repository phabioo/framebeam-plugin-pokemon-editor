-- In-game panel tab "Editor", built for about 300 px. Pure builder: panel.build(ctx) -> block.
-- ctx = { tr, state, core, names, team, box, box_count, trainer }, see app.editor.
--   state.view = "list" | "edit"; state.tab = "team" | "box" | "bag"
-- Nothing is nested deeper than list -> one edit form.
local form_mod = require("model.form")

local M = {}

M.MAX_ROWS = 30

-- Table of the non-nil arguments (a nil in a table constructor would end ipairs early).
local function K(...)
  local out = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if v then out[#out + 1] = v end
  end
  return out
end

local function label_of(id) return "#" .. tostring(id) end

local function mon_title(tr, rec)
  local name = (rec.nickname and rec.nickname ~= "") and rec.nickname or rec.species_name or label_of(rec.species)
  if rec.level then name = name .. " · " .. tr("level_short", { n = rec.level }) end
  return name
end

local function mon_sub(rec)
  if rec.nickname and rec.nickname ~= "" then return rec.species_name or label_of(rec.species) end
  return nil
end

local function banner(ctx)
  local m = ctx.state.msg
  if not m then return nil end
  return { type = "column", id = "msg", gap = 4, children = {
    { type = "badge", id = "msg-badge", text = ctx.tr("msg_" .. m.tone), tone = m.tone },
    { type = "text", id = "msg-text", text = m.text, style = "body", tone = m.tone },
    { type = "button", id = "msg-x", label = ctx.tr("dismiss"), action = "dismiss", variant = "quiet" },
  } }
end

local function gate(ctx)
  local core = ctx.core
  if core.state == "no_core" then
    return { type = "empty", id = "gate", title = ctx.tr("gate_core_title"), text = ctx.tr("gate_core_text"), tone = "danger" }
  elseif core.state == "unsupported" then
    return { type = "empty", id = "gate", title = ctx.tr("gate_game_title"), text = ctx.tr("gate_game_text") }
  elseif core.state == "no_write" then
    return { type = "empty", id = "gate", title = ctx.tr("gate_write_title"), text = ctx.tr("gate_write_text"), tone = "danger" }
  elseif core.state ~= "ready" then
    return { type = "empty", id = "gate", title = ctx.tr("gate_wait_title"), text = ctx.tr("gate_wait_text") }
  end
  return nil
end

local function team_rows(ctx, recs, action_value)
  local rows = {}
  for i, rec in ipairs(recs or {}) do
    if i > M.MAX_ROWS then break end
    rows[#rows + 1] = { id = "r" .. i, title = mon_title(ctx.tr, rec), sub = mon_sub(rec), action = "edit",
      value = action_value(rec) }
  end
  return rows
end

local function team_tab(ctx)
  local rows = team_rows(ctx, ctx.team, function(rec) return { kind = "team", slot = rec.slot } end)
  if #rows == 0 then
    return { type = "text", id = "list-empty", text = ctx.tr("team_empty"), style = "meta" }
  end
  return { type = "list", id = "list", rows = rows }
end

local function box_tab(ctx)
  local opts = {}
  for n = 1, math.min(ctx.box_count or 31, 100) do opts[#opts + 1] = { value = n, label = ctx.tr("box_n", { n = n }) } end
  local kids = { { type = "select", id = "box-select", options = opts, selected = ctx.state.box, action = "box_select" } }
  local rows = team_rows(ctx, ctx.box, function(rec) return { kind = "box", box = ctx.state.box, slot = rec.slot } end)
  if #rows == 0 then
    kids[#kids + 1] = { type = "text", id = "list-empty", text = ctx.tr("box_empty"), style = "meta" }
  else
    kids[#kids + 1] = { type = "list", id = "list", rows = rows }
  end
  return { type = "column", id = "box-col", gap = 8, children = kids }
end

local function bag_tab(ctx)
  local st = ctx.state
  local limits = ctx.core.limits
  local kids = {
    { type = "section", id = "money-sec", title = ctx.tr("money_title"), children = {
      { type = "text", id = "money-now", style = "meta",
        text = ctx.trainer and ctx.trainer.money and ctx.tr("money_now", { n = ctx.trainer.money }) or ctx.tr("money_unknown") },
      { type = "textfield", id = "money-input", action = "money_input", text = st.money or "", live = true,
        placeholder = ctx.tr("money_placeholder", { max = limits.money }), error = st.money_err and ctx.tr(st.money_err) or nil },
      { type = "button", id = "money-apply", label = ctx.tr("money_apply"), action = "money_apply", variant = "primary" },
    } },
  }
  if not ctx.core.features.edit_items then
    kids[#kids + 1] = { type = "section", id = "items-sec", title = ctx.tr("items_title"), children = {
      { type = "text", id = "items-note", text = ctx.tr("items_unsupported"), style = "meta" } } }
  end
  return { type = "column", id = "bag-col", gap = 12, children = kids }
end

local function list_view(ctx)
  local st = ctx.state
  local tabs = {
    { value = "team", label = ctx.tr("tab_team") }, { value = "box", label = ctx.tr("tab_box") },
    { value = "bag", label = ctx.tr("tab_bag") },
  }
  local content = st.tab == "box" and box_tab(ctx) or st.tab == "bag" and bag_tab(ctx) or team_tab(ctx)
  return { type = "column", id = "list-view", gap = 12, children = {
    { type = "segmented", id = "tabs", options = tabs, selected = st.tab, action = "tab" },
    content,
    { type = "text", id = "note", text = ctx.tr("note_backup"), style = "meta" },
  } }
end

-- ---- edit form ----

local function filtered_select(ctx, id, list, current, filter, action, with_none)
  local opts = form_mod.filter_options(list, filter, current, with_none and 99 or 100, label_of)
  if with_none then
    local has_zero = false
    for _, o in ipairs(opts) do if o.value == 0 then has_zero = true end end
    if not has_zero then table.insert(opts, 1, { value = 0, label = ctx.tr("none") }) end
  end
  for _, o in ipairs(opts) do if o.value == 0 and with_none then o.label = ctx.tr("none") end end
  return { type = "select", id = id, options = opts, selected = current, action = action }
end

local function stat_grid(ctx, kind, form, errs)
  local st_names = { hp = "stat_hp", atk = "stat_atk", def = "stat_def", spe = "stat_spe", spa = "stat_spa", spd = "stat_spd" }
  local cells = {}
  for _, s in ipairs(form_mod.STATS) do
    local key = (kind == "ivs" and "iv_" or "ev_") .. s
    cells[#cells + 1] = { type = "column", id = key .. "-c", gap = 2, children = {
      { type = "text", id = key .. "-l", text = ctx.tr(st_names[s]), style = "meta" },
      { type = "textfield", id = key, action = key, text = form[kind][s], live = true, error = errs[key] and ctx.tr(errs[key]) or nil },
    } }
  end
  return { type = "grid", id = kind .. "-grid", columns = 3, gap = 8, children = cells }
end

local function edit_view(ctx)
  local st = ctx.state
  local tr = ctx.tr
  local f, errs, limits = st.form, st.errors or {}, ctx.core.limits
  local names = ctx.names
  local nature_opts = {}
  for n = 0, limits.nature do
    nature_opts[#nature_opts + 1] = { value = n, label = names.nature[n] or tr("nature_n", { n = n }) }
  end
  local total = form_mod.ev_total(f)
  local ev_tone = total > limits.ev_total and "danger" or "neutral"

  local moves = {}
  for i = 1, form_mod.MOVE_SLOTS do
    moves[#moves + 1] = filtered_select(ctx, "move" .. i, names.move, f.moves[i], st.filters.move, "move_" .. i, true)
  end

  local kids = {
    { type = "row", id = "e-head", gap = 8, align = "center", children = {
      { type = "button", id = "e-back", label = tr("back"), action = "back", variant = "quiet" },
      { type = "text", id = "e-title", text = mon_title(tr, st.rec), style = "heading" },
    } },
    { type = "section", id = "sec-basic", title = tr("sec_basic"), children = {
      { type = "textfield", id = "species-filter", action = "species_filter", text = st.filters.species, live = true,
        placeholder = tr("filter_species") },
      filtered_select(ctx, "species", names.species, f.species, st.filters.species, "species", false),
      { type = "text", id = "level-l", text = tr("level"), style = "meta" },
      { type = "textfield", id = "level", action = "level", text = f.level, live = true,
        error = errs.level and tr(errs.level) or nil },
      { type = "text", id = "nature-l", text = tr("nature"), style = "meta" },
      { type = "select", id = "nature", options = nature_opts, selected = f.nature, action = "nature" },
      { type = "toggle", id = "shiny", label = tr("shiny"), checked = f.shiny, action = "shiny" },
    } },
    { type = "section", id = "sec-moves", title = tr("sec_moves"), children = K(
      { type = "textfield", id = "move-filter", action = "move_filter", text = st.filters.move, live = true,
        placeholder = tr("filter_move") },
      { type = "column", id = "moves", gap = 4, children = moves },
      errs.moves and { type = "text", id = "moves-err", text = tr(errs.moves), style = "meta", tone = "danger" } or nil,
      { type = "text", id = "moves-note", text = tr("moves_note"), style = "meta" }
    ) },
    { type = "section", id = "sec-ivs", title = tr("sec_ivs"), children = { stat_grid(ctx, "ivs", f, errs) } },
    { type = "section", id = "sec-evs", title = tr("sec_evs"), children = K(
      stat_grid(ctx, "evs", f, errs),
      { type = "text", id = "ev-total", text = tr("ev_total", { n = total, max = limits.ev_total }), style = "meta", tone = ev_tone },
      errs.ev_total and { type = "text", id = "ev-err", text = tr(errs.ev_total), style = "meta", tone = "danger" } or nil
    ) },
    { type = "section", id = "sec-item", title = tr("sec_item"), children = {
      { type = "textfield", id = "item-filter", action = "item_filter", text = st.filters.item, live = true,
        placeholder = tr("filter_item") },
      filtered_select(ctx, "item", names.item, f.item, st.filters.item, "item", true),
    } },
  }
  local msg = banner(ctx)
  if msg then kids[#kids + 1] = msg end
  kids[#kids + 1] = { type = "row", id = "e-acts", gap = 8, align = "center", children = {
    { type = "button", id = "apply", label = tr("apply"), action = "apply", variant = "primary" },
    { type = "button", id = "reset", label = tr("reset"), action = "reset", variant = "quiet" },
  } }
  return { type = "column", id = "edit-view", gap = 12, children = kids }
end

function M.build(ctx)
  local g = gate(ctx)
  local kids = {}
  if g then
    kids[1] = g
  elseif ctx.state.view == "edit" and ctx.state.form then
    kids[1] = edit_view(ctx)
  else
    local msg = banner(ctx)
    if msg then kids[#kids + 1] = msg end
    kids[#kids + 1] = list_view(ctx)
  end
  return { type = "column", id = "panel", gap = 12, children = kids }
end

return M
