--[[
* vanalog - Main HUD overlay rendering.
--]]

require 'common';

local imgui    = require 'imgui';
local timers   = require 'core.timers';
local world    = require 'core.world';
local vanadiel = require 'core.vanadiel';
local theme    = require 'ui.theme';
local sound    = require 'ui.sound';
local settings_window = require 'ui.settings_window';

local overlay = { };

local colors = {
    header = { 1.0, 0.65, 0.26, 1.0 },
    warn   = { 0.9, 0.9, 0.0, 1.0 },
    good   = { 0.4, 0.9, 0.5, 1.0 },
};

local GUILD_STATUS_LABEL = { open = 'Open', closed = 'Closed', holiday = 'Holiday' };

-- Set at the top of overlay.render() each frame, so draw_text()/draw_plain_text() below don't
-- need `style` threaded through every single call site that uses them.
local current_style = nil;

--[[
* Drop-in replacement for imgui.TextColored(color, text) that adds a black outline around the
* text while Low Profile Mode is on (and its own "text_outline" setting too), drawn on top of
* (not instead of) the normal draw, which is what establishes the correct position/size and
* keeps ImGui's layout cursor advancing exactly as it always has. There's no real font-level
* outline available -- loading a bundled font crashed an earlier build, see README -- so this
* is simulated by drawing a black copy at each of the 8 surrounding offsets, then the real
* color on top of those, so text stays readable with no background box behind it.
--]]
local function draw_text(color, text)
    imgui.TextColored(color, text);

    local style = current_style;
    if (style == nil or not style.low_profile_mode[1] or not style.text_outline[1]) then
        return;
    end

    local x1, y1 = imgui.GetItemRectMin();
    local list = imgui.GetWindowDrawList();

    local outline_color = imgui.GetColorU32({ 0.0, 0.0, 0.0, 1.0 });
    local offsets = T{ { -1, -1 }, { 0, -1 }, { 1, -1 }, { -1, 0 }, { 1, 0 }, { -1, 1 }, { 0, 1 }, { 1, 1 } };
    for i = 1, #offsets do
        list:AddText({ x1 + offsets[i][1], y1 + offsets[i][2] }, outline_color, text);
    end

    -- Re-drawn on top last, so the readable colored text sits above the outline.
    list:AddText({ x1, y1 }, imgui.GetColorU32(color), text);
end

--[[
* Drop-in replacement for imgui.Text(text) -- see draw_text() above.
--]]
local function draw_plain_text(text)
    local style = current_style;
    draw_text((style ~= nil) and style.text_color or { 1.0, 1.0, 1.0, 1.0 }, text);
end

--[[
* Drop-in replacement for imgui.Separator() that honors Separator Thickness (Appearance ->
* Border). At the 1.0 default -- which matches ImGui's own built-in line exactly -- this is
* just imgui.Separator() itself; Separator() has no public way to draw thicker, so anything
* above that switches to a hand-drawn line in its place, sized to actually reserve that much
* vertical space (not just drawn thicker on top of the normal thin one).
--]]
local function draw_separator()
    local style = current_style;
    local thickness = (style ~= nil) and style.separator_size[1] or 1.0;
    if (thickness <= 1.0) then
        imgui.Separator();
        return;
    end

    local avail = imgui.GetContentRegionAvail();
    local x, y = imgui.GetCursorScreenPos();
    local color = imgui.GetColorU32({ style.border_color[1], style.border_color[2], style.border_color[3], style.border_opacity[1] });

    imgui.GetWindowDrawList():AddLine({ x, y + (thickness / 2) }, { x + avail, y + (thickness / 2) }, color, thickness);
    imgui.Dummy({ avail, thickness });
end

-- Set by a Delete button during the render loop below, then actually removed only after the
-- loop finishes. This is what avoids the crash the original addon had: removing an entry from
-- timers.settings.timers *during* a forward `for x = 1, #list` loop over that same list shifts
-- every later index down by one, so the loop's cached upper bound can walk past the (now
-- shorter) list and index a nil entry. Deferring the actual removal sidesteps that entirely --
-- nothing ever mutates the list while it's being iterated.
local pending_delete = nil;

-- Set by a Completed button during the render loop below, applied after it finishes, for the
-- same reason as pending_delete above (completing a note removes it from the list too).
local pending_complete = nil;

-- The overlay's own size the last time it rendered *not* collapsed, remembered so collapsing
-- (via the bottom bar) can shrink the window to just that bar's height, and expanding again can
-- restore the exact size from before -- there's no native title-bar collapse state to lean on
-- once the title bar is moved to the bottom.
local last_expanded_size = { 300, 260 };

-- One-shot, like the window-scale flags in core/timers.lua: set the frame the bottom bar's
-- collapse arrow expands the window back open, consumed (and cleared) by overlay.render() on
-- the very next Begin() so the window actually grows back to last_expanded_size instead of
-- staying stuck at the small collapsed size forever after.
local pending_expand = false;

--[[
* Toggles the visibility of the main overlay.
--]]
function overlay.toggle()
    local v = timers.settings.style.overlay_visible;
    v[1] = not v[1];
end

--[[
* Toggles whether the overlay is locked in place.
--]]
function overlay.toggle_lock()
    local l = timers.settings.style.locked;
    l[1] = not l[1];
end

--[[
* Renders a single timer/note entry within the overlay.
--]]
local function render_entry(entry, style, locked)
    imgui.PushID(('entry_%d'):fmt(entry.id));

    local category = timers.category(entry.category);
    local show_tag = style.show_categories[1] and entry.category ~= 'general';

    if (show_tag) then
        draw_text(timers.category_color(entry.category), ('[%s]'):fmt(category.name));
        imgui.SameLine();
    end

    if (entry.mode == 'timer') then
        local remaining = timers.get_remaining(entry);
        local label_color = style.text_color;

        if (remaining <= 0) then
            label_color = style.finished_color;
        elseif (remaining <= style.warn_threshold[1]) then
            label_color = style.warn_color;
        end

        local prefix = entry.paused and '[Paused] ' or '';
        draw_text(label_color, ('%s%s  -  %s'):fmt(prefix, timers.format_time(remaining), entry.name));
    else
        draw_text(style.header_color, entry.name);
    end

    if (entry.notes ~= nil and #entry.notes > 0) then
        imgui.PushTextWrapPos(imgui.GetFontSize() * 24.0);
        draw_text(style.notes_color, entry.notes);
        imgui.PopTextWrapPos();
    end

    if (entry.mode == 'note' and entry.remind_enabled) then
        if (entry.remind_fired) then
            draw_text(style.finished_color, 'Reminder fired!');
        else
            local remaining = timers.get_reminder_remaining(entry);
            draw_text(style.warn_color, ('Reminder in: %s'):fmt(timers.format_time(math.max(0, remaining))));
        end
    end

    if (not locked) then
        if (entry.mode == 'timer') then
            if (imgui.SmallButton(entry.paused and 'Resume' or 'Pause')) then
                timers.toggle_pause(entry.id);
            end
            imgui.SameLine();
            if (imgui.SmallButton('Restart')) then
                timers.restart_timer(entry.id);
            end
            imgui.SameLine();
        end

        if (entry.mode == 'note') then
            if (imgui.SmallButton('Completed')) then
                pending_complete = entry.id;
            end
            imgui.SameLine();
        end

        if (imgui.SmallButton('Edit')) then
            settings_window.edit_entry(entry);
        end
        imgui.SameLine();
        if (imgui.SmallButton('Delete')) then
            pending_delete = entry.id;
        end
    end

    imgui.PopID();
    draw_separator();
end

--[[
* Renders every entry in timers.settings.timers whose mode matches `mode_filter`. Reordering
* happens in the settings window's entry list (core.timers.swap_entries) and is reflected here
* automatically, since both read the same underlying list.
--]]
local function render_entry_list(style, locked, mode_filter, empty_message)
    local list = timers.settings.timers;
    local shown = 0;

    -- Safe to iterate forward: render_entry never mutates `list` directly, it only records
    -- `pending_delete`, applied once overlay.render()'s whole frame is done.
    for x = 1, #list do
        if (list[x].mode == mode_filter) then
            render_entry(list[x], style, locked);
            shown = shown + 1;
        end
    end

    if (shown == 0) then
        draw_text(colors.warn, empty_message);
        imgui.TextWrapped('Right-click for options, or run /vl config to add one.');
    end
end

--[[
* Renders a small, always-visible settings button, drawn as a cogwheel rather than a text label.
* This matters most when the overlay has no title bar -- either locked (which hides the native
* one) or with the title bar moved to the bottom bar below -- since the right-click menu is the
* only other way in otherwise, which isn't obvious either.
*
* By default, right-aligns itself within the remaining width of the current line (its original
* spot, top-right of the content area). Pass `auto_align = false` to instead draw at whatever
* cursor position the caller has already set up (used by the bottom bar, which lays out several
* elements on one row itself). `extra_reserve`, when auto-aligning, reserves additional width to
* its right for something else the caller will place after it (e.g. a close button).
--]]
local function render_settings_button(style, auto_align, extra_reserve)
    local size = imgui.GetFontSize() * 0.7;
    if (auto_align ~= false) then
        local avail = imgui.GetContentRegionAvail();
        imgui.SetCursorPosX(imgui.GetCursorPosX() + math.max(0, avail - size - 2 - (extra_reserve or 0)));
    end

    imgui.InvisibleButton('##tn_settings_gear', { size, size });
    local clicked = imgui.IsItemClicked();
    local hovered = imgui.IsItemHovered();

    local x1, y1 = imgui.GetItemRectMin();
    local x2, y2 = imgui.GetItemRectMax();
    local cx, cy = (x1 + x2) / 2, (y1 + y2) / 2;
    local radius = (x2 - x1) / 2;

    local list = imgui.GetWindowDrawList();

    -- Pulls straight from the active theme preset's palette (not the overlay's own editable
    -- text/header colors), so the icon always tracks whichever preset is picked -- accent
    -- normally, the same "warn" highlight the resize grip uses on hover, for one consistent
    -- accent language across the addon.
    local palette = theme.PALETTES[style.theme_preset[1]] or theme.PALETTES.phoenix;

    if (hovered) then
        list:AddCircleFilled({ cx, cy }, radius + 2,
            imgui.GetColorU32({ palette.accent[1], palette.accent[2], palette.accent[3], 0.20 }), 16);
    end

    -- A cheap, font-independent gear: a ring of small filled "teeth" circles around a solid
    -- body circle, with a small hole punched in the middle. Guaranteed to render identically
    -- everywhere, unlike a Unicode gear glyph, which the default ImGui font doesn't include.
    local gear_color = imgui.GetColorU32(hovered and palette.warn or palette.accent);
    local teeth = 8;
    local tooth_radius = radius * 0.30;
    for i = 0, teeth - 1 do
        local angle = (i / teeth) * (math.pi * 2);
        local tx = cx + math.cos(angle) * radius * 0.72;
        local ty = cy + math.sin(angle) * radius * 0.72;
        list:AddCircleFilled({ tx, ty }, tooth_radius, gear_color, 8);
    end
    list:AddCircleFilled({ cx, cy }, radius * 0.66, gear_color, 20);
    list:AddCircleFilled({ cx, cy }, radius * 0.26,
        imgui.GetColorU32({ style.bg_color[1], style.bg_color[2], style.bg_color[3], 1.0 }), 12);

    if (hovered) then
        imgui.SetTooltip('Open settings (/vl config)');
    end
    if (clicked) then
        settings_window.toggle();
    end
end

--[[
* Renders the custom bottom bar that stands in for the native title bar when "Move title bar to
* bottom" is on: a collapse arrow, the "VanaLog" label, the settings gear, and a close button,
* all on one row. Clicking the arrow toggles style.collapsed, which overlay.render() uses to
* shrink the whole window down to just this bar (and back).
--]]
local function render_bottom_bar(style, collapsed)
    draw_separator();

    if (imgui.SmallButton((collapsed and '>' or 'v') .. '##vl_bottom_collapse')) then
        if (collapsed) then
            pending_expand = true;
        end
        style.collapsed[1] = not collapsed;
    end
    imgui.SameLine();
    draw_text(style.header_color, 'VanaLog');

    imgui.SameLine();
    -- Reserves room for the close button to its right, same trick render_settings_button
    -- normally uses just for itself. The gear still works while collapsed (opens settings
    -- without needing to expand the overlay first).
    render_settings_button(style, true, imgui.GetFontSize() + 16);
    imgui.SameLine();
    if (imgui.SmallButton('X##vl_bottom_close')) then
        style.overlay_visible[1] = false;
    end
end

--[[
* Draws a stroked ring (outline circle) as a series of short line segments, since drawing with
* arbitrary icons/images isn't an option here (same reasoning as the settings cogwheel above --
* a bundled icon font crashed on at least one tester's system; see README). Used by the tab
* icons below for the clock face and globe outline.
--]]
local function draw_ring(list, cx, cy, r, color, thickness, segments)
    segments = segments or 20;
    local prev_x, prev_y = cx + r, cy;
    for i = 1, segments do
        local angle = (i / segments) * (math.pi * 2);
        local x, y = cx + math.cos(angle) * r, cy + math.sin(angle) * r;
        list:AddLine({ prev_x, prev_y }, { x, y }, color, thickness);
        prev_x, prev_y = x, y;
    end
end

--[[
* Minimal stopwatch/clock glyph: a ring, a top stem (the stopwatch's button), and two hands.
--]]
local function draw_icon_clock(list, cx, cy, r, color)
    draw_ring(list, cx, cy, r, color, 1.6, 20);
    list:AddLine({ cx, cy - r }, { cx, cy - r * 1.3 }, color, 1.6);
    list:AddLine({ cx, cy }, { cx, cy - r * 0.55 }, color, 1.6);
    list:AddLine({ cx, cy }, { cx + r * 0.45, cy + r * 0.30 }, color, 1.6);
end

--[[
* Minimal notepad glyph: a rectangle outline with a few ruled lines inside.
--]]
local function draw_icon_notepad(list, cx, cy, r, color)
    local w, h = r * 1.3, r * 1.7;
    local x1, y1 = cx - w / 2, cy - h / 2;
    local x2, y2 = cx + w / 2, cy + h / 2;

    list:AddLine({ x1, y1 }, { x2, y1 }, color, 1.6);
    list:AddLine({ x2, y1 }, { x2, y2 }, color, 1.6);
    list:AddLine({ x2, y2 }, { x1, y2 }, color, 1.6);
    list:AddLine({ x1, y2 }, { x1, y1 }, color, 1.6);

    for i = 1, 3 do
        local ly = y1 + (h * i / 4);
        list:AddLine({ x1 + w * 0.18, ly }, { x2 - w * 0.18, ly }, color, 1.3);
    end
end

--[[
* Minimal globe glyph: a ring, an equator, and a pair of meridian lines.
--]]
local function draw_icon_globe(list, cx, cy, r, color)
    draw_ring(list, cx, cy, r, color, 1.6, 22);
    list:AddLine({ cx - r, cy }, { cx + r, cy }, color, 1.2);
    list:AddLine({ cx, cy - r }, { cx, cy + r }, color, 1.2);
    list:AddLine({ cx - r * 0.5, cy - r * 0.87 }, { cx - r * 0.5, cy + r * 0.87 }, color, 1.0);
    list:AddLine({ cx + r * 0.5, cy - r * 0.87 }, { cx + r * 0.5, cy + r * 0.87 }, color, 1.0);
end

--[[
* Renders a tab bar item with a hand-drawn icon in place of a text label -- the label is a few
* blank spaces (so the tab still gets a sensible width) plus a unique ##id; the icon is drawn on
* top of that blank area afterward, straight from the active theme preset's palette (accent
* while open/hovered, muted otherwise) so it always tracks whichever preset is picked, the same
* as the settings cogwheel above.
*
* @param {string} id - A unique ##-prefixed identifier for this tab.
* @param {function} icon_fn - function(list, cx, cy, r, color) that draws the icon.
* @param {string} tooltip - Shown on hover, since the tab itself carries no visible text.
* @param {table} style - timers.settings.style.
* @return {boolean} Whether this tab is the currently active one (same as imgui.BeginTabItem).
--]]
local function render_icon_tab(id, icon_fn, tooltip, style)
    local open = imgui.BeginTabItem(('      %s'):fmt(id));
    local hovered = imgui.IsItemHovered();

    local x1, y1 = imgui.GetItemRectMin();
    local x2, y2 = imgui.GetItemRectMax();
    local cx, cy = (x1 + x2) / 2, (y1 + y2) / 2;
    local r = math.min(x2 - x1, y2 - y1) * 0.30;

    local palette = theme.PALETTES[style.theme_preset[1]] or theme.PALETTES.phoenix;
    local color = imgui.GetColorU32((open or hovered) and palette.accent or palette.muted);

    icon_fn(imgui.GetWindowDrawList(), cx, cy, r, color);

    if (hovered) then
        imgui.SetTooltip(tooltip);
    end

    return open;
end

--[[
* Renders the pinned "Active RSE" line above the tab bar, if enabled. Requires RSE to actually
* be Followed, not just "Pin above tabs" checked on its own -- otherwise this could show up
* pinned even though RSE isn't followed (and so isn't shown in the World tab at all), which was
* exactly the confusing, inconsistent behavior this addon used to have.
--]]
local function render_active_rse(style)
    local w = timers.settings.world;
    if (not w.enabled[1] or not w.follow.rse[1] or not w.show_in_overlay[1]) then
        return;
    end

    local ok, info = pcall(world.overview, w);
    if (not ok) then
        return;
    end

    draw_text(style.header_color, 'Active RSE:');
    imgui.SameLine();
    draw_text(colors.good, ('%s @ %s'):fmt(info.active_rse.race_name, info.active_rse.location));
    imgui.SameLine();
    draw_text(style.notes_color, ('(%s left)'):fmt(vanadiel.format_countdown(info.active_rse.ends_in_seconds)));
    draw_separator();
end

--[[
* Renders one collapsible, color-coded section (the same fixed yellowish-orange used for major
* section labels elsewhere in the addon, independent of the active theme, so these stay easy to
* pick out at a glance), running `body_fn` while it's open. Used by both the World tab and the
* combined Timers/Reminders tab below. ImGui tracks each header's collapsed/expanded state on
* its own, so it persists for the session without needing a settings entry.
--]]
local function render_collapsible_section(title, body_fn)
    imgui.PushStyleColor(ImGuiCol_Text, colors.header);
    local open = imgui.CollapsingHeader(title, ImGuiTreeNodeFlags_DefaultOpen);
    imgui.PopStyleColor();

    if (open) then
        body_fn();
    end
end

--[[
* Renders the compact World Info tab: only whatever you've chosen to Follow (settings window's
* World Info tab -> each section's own Follow checkbox, or per-entry for Guilds/Airships) shows
* up here -- nobody's forced to see RSE/Day/Moon/Guilds/Airships they don't care about. The
* full, always-visible reference view lives in the settings window's World Info tab.
--]]
local function render_world_tab(style)
    local w = timers.settings.world;

    local ok, info = pcall(world.overview, w);
    if (not ok) then
        draw_text(colors.warn, 'Could not compute World Info this frame.');
        return;
    end

    local followed_guilds = T{ };
    for x = 1, #info.guilds do
        local g = info.guilds[x];
        local flag = w.follow.guilds[g.key];
        if (flag ~= nil and flag[1]) then
            followed_guilds:insert(#followed_guilds + 1, g);
        end
    end

    local followed_routes = T{ };
    for x = 1, #info.airships do
        local a = info.airships[x];
        local flag = w.follow.airships[a.name];
        if (flag ~= nil and flag[1]) then
            followed_routes:insert(#followed_routes + 1, a);
        end
    end

    local any_followed = w.follow.rse[1] or w.follow.day[1] or w.follow.moon[1] or w.follow.ferry[1]
        or #followed_guilds > 0 or #followed_routes > 0;

    if (not any_followed) then
        draw_text(colors.warn, 'Nothing followed yet.');
        imgui.TextWrapped('Pick what to show here in /vl config -> World Info -- every section (and, for Guilds/Airships, every entry) has its own Follow checkbox.');
        return;
    end

    if (w.follow.rse[1]) then
        render_collapsible_section('RSE', function ()
            draw_text(style.notes_color, 'Active Now:');
            draw_text(colors.good, ('%s @ %s'):fmt(info.active_rse.race_name, info.active_rse.location));
            draw_text(style.notes_color, ('Rotates in: %s'):fmt(vanadiel.format_countdown(info.active_rse.ends_in_seconds)));

            draw_separator();
            draw_text(style.notes_color, ('Upcoming for %s:'):fmt(vanadiel.RSE_RACES[info.race_index + 1]));
            for x = 1, math.min(3, #info.race_schedule) do
                local row = info.race_schedule[x];
                draw_text(style.text_color, ('%s - %s'):fmt(os.date('%b %d, %H:%M', row.starts), row.location));
            end
        end);
    end

    if (w.follow.day[1]) then
        render_collapsible_section('Day Calendar', function ()
            for x = 1, math.min(3, #info.day_schedule) do
                local row = info.day_schedule[x];
                draw_text(row.color, row.name);
                imgui.SameLine();
                draw_text(style.notes_color, ('- %s (%s)'):fmt(row.weak_element, os.date('%b %d', row.begins)));
            end
        end);
    end

    if (w.follow.moon[1]) then
        render_collapsible_section('Moon Phase', function ()
            draw_text(style.text_color, ('%s (%d%%, %s)'):fmt(info.moon.name, info.moon.percent, info.moon.waxing and 'waxing' or 'waning'));
            local now = os.time();
            if (info.moon_events.next_new_starts ~= nil) then
                local until_new = info.moon_events.next_new_starts - now;
                draw_text(style.notes_color, until_new <= 0
                    and ('New Moon active (%s left)'):fmt(vanadiel.format_countdown(info.moon_events.next_new_ends - now))
                    or ('Next New Moon: %s'):fmt(vanadiel.format_countdown(until_new)));
            end
            if (info.moon_events.next_full_starts ~= nil) then
                local until_full = info.moon_events.next_full_starts - now;
                draw_text(style.notes_color, until_full <= 0
                    and ('Full Moon active (%s left)'):fmt(vanadiel.format_countdown(info.moon_events.next_full_ends - now))
                    or ('Next Full Moon: %s'):fmt(vanadiel.format_countdown(until_full)));
            end
        end);
    end

    if (#followed_guilds > 0) then
        render_collapsible_section('Guilds', function ()
            for x = 1, #followed_guilds do
                local g = followed_guilds[x];
                local status_color = (g.status == 'open') and colors.good or (g.status == 'holiday') and style.warn_color or style.notes_color;
                draw_text(style.text_color, g.name);
                imgui.SameLine();
                draw_text(status_color, GUILD_STATUS_LABEL[g.status] or g.status);
                imgui.SameLine();
                draw_text(style.notes_color, ('- %s in %s'):fmt(g.next_label, vanadiel.format_countdown(g.countdown_seconds)));
            end
        end);
    end

    if (#followed_routes > 0 or w.follow.ferry[1]) then
        render_collapsible_section('Airship / Boats', function ()
            for x = 1, #followed_routes do
                local a = followed_routes[x];
                draw_text(style.text_color, a.name);
                imgui.SameLine();
                draw_text(a.color, a.day_name);
                imgui.SameLine();
                draw_text(style.notes_color, ('departs in %s'):fmt(vanadiel.format_countdown(a.departs_in)));
            end
            if (w.follow.ferry[1] and info.ferries[1] ~= nil) then
                local f = info.ferries[1];
                draw_text(style.text_color, 'Ferry:');
                imgui.SameLine();
                draw_text(f.depart_color, ('%s %s'):fmt(f.depart_day, f.depart_label));
                imgui.SameLine();
                draw_text(style.notes_color, ('(departs in %s)'):fmt(vanadiel.format_countdown(f.departs_in)));
            end
        end);
    end

    draw_separator();
    draw_text(style.notes_color, 'More detail and settings in /vl config.');
end

--[[
* Renders a single reminder's live countdown line for the overlay's Reminders tab.
--]]
local function render_reminder_line(style, entry)
    local now = os.time();
    local label = entry.label;
    local detail = '';
    if (entry.extra ~= nil) then
        if (entry.extra.location ~= nil) then
            -- e.g. "Mithra RSE" instead of a bare "RSE" -- otherwise this line never actually
            -- says which race's pop it's counting down, even though it's always your own race's.
            if (entry.extra.race_name ~= nil) then
                label = entry.extra.race_name .. ' ' .. label;
            end
            detail = ' @ ' .. entry.extra.location;
        elseif (entry.extra.weak_element ~= nil) then
            detail = (' - %s (%s)'):fmt(entry.extra.day_name, entry.extra.weak_element);
        elseif (entry.extra.guild_name ~= nil) then
            detail = ' - ' .. entry.extra.guild_name;
        end
    end

    draw_text(style.header_color, label .. detail);
    if (entry.completed) then
        draw_text(colors.good, ('Completed for today (resets in %s)'):fmt(vanadiel.format_countdown(entry.ends - now)));
    elseif (entry.active) then
        draw_text(colors.good, ('Active now (ends in %s)'):fmt(vanadiel.format_countdown(entry.ends - now)));
    else
        draw_text(style.text_color, ('In: %s'):fmt(vanadiel.format_countdown(entry.starts - now)));
    end
end

--[[
* Renders the overlay's Reminders tab: a live, glanceable countdown for every reminder
* category you've enabled in the settings window's Reminders tab.
--]]
local function render_reminders_tab(style)
    local ok, status = pcall(world.reminder_status, timers.settings);
    if (not ok) then
        draw_text(colors.warn, 'Could not compute reminders this frame.');
        return;
    end

    if (#status == 0) then
        draw_text(colors.warn, 'No reminders enabled.');
        imgui.TextWrapped('Turn some on in /vl config -> Reminders.');
        return;
    end

    for x = 1, #status do
        render_reminder_line(style, status[x]);
        draw_separator();
    end
end

--[[
* Renders the overlay's right-click menu (Add Timer/Note, Lock, Settings, Clear All).
--]]
local function render_context_menu(style, locked)
    if (imgui.BeginPopupContextWindow()) then
        if (imgui.MenuItem('Add Timer / Note...')) then
            settings_window.new_entry();
        end
        draw_separator();
        if (imgui.MenuItem(locked and 'Unlock Overlay' or 'Lock Overlay')) then
            style.locked[1] = not locked;
        end
        if (imgui.MenuItem('Settings...')) then
            settings_window.toggle();
        end
        draw_separator();
        if (imgui.MenuItem('Clear All')) then
            imgui.OpenPopup('###VanaLogClearAll');
        end
        imgui.EndPopup();
    end
end

--[[
* Renders the main overlay window.
--]]
function overlay.render()
    local style = timers.settings.style;
    current_style = style;

    if (not style.overlay_visible[1]) then
        return;
    end

    pending_delete = nil;
    pending_complete = nil;

    local finished = timers.tick();
    if (style.sound_enabled[1] and style.sound_file[1] ~= '' and #finished > 0) then
        pcall(sound.play, style.sound_file[1], style.sound_volume[1]);
    end

    local locked = style.locked[1];
    local bottom_bar = style.title_bar_bottom[1];
    local collapsed = bottom_bar and style.collapsed[1];

    -- No ImGuiWindowFlags_NoCollapse here: with the native title bar, the overlay can be
    -- collapsed to just that bar, the same as the settings window, by clicking the arrow next to
    -- its title. With the title bar moved to the bottom, `collapsed` is a fully custom stand-in
    -- for that -- see render_bottom_bar() and the size handling below.
    local flags = 0;
    if (locked) then
        flags = bit.bor(flags, ImGuiWindowFlags_NoMove, ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoScrollbar);
    elseif (bottom_bar) then
        flags = bit.bor(flags, ImGuiWindowFlags_NoTitleBar);
    end
    if (collapsed) then
        flags = bit.bor(flags, ImGuiWindowFlags_NoResize);
    end

    local low_profile = style.low_profile_mode[1];

    local border_size = imgui.GetStyle().WindowBorderSize;
    imgui.GetStyle().WindowBorderSize = style.show_border[1] and style.border_size[1] or 0.0;

    -- Full theme skin first (buttons, tabs, headers, etc. all match the Appearance tab's
    -- chosen preset), then layer the overlay's own finer-grained overrides (custom opacity,
    -- border thickness, and the individually-editable text colors) on top of it.
    local preset_id = style.theme_preset[1];
    local theme_colors, theme_vars = theme.push_window_style(preset_id);

    imgui.PushStyleColor(ImGuiCol_WindowBg, { style.bg_color[1], style.bg_color[2], style.bg_color[3], low_profile and 0.0 or style.bg_opacity[1] });
    imgui.PushStyleColor(ImGuiCol_Border, { style.border_color[1], style.border_color[2], style.border_color[3], low_profile and 0.0 or style.border_opacity[1] });
    imgui.PushStyleColor(ImGuiCol_Text, style.text_color);

    -- Low Profile Mode: on top of the above, flatten every "header-ish" background (the native
    -- title bar and the CollapsingHeader section headers used throughout the overlay) to fully
    -- transparent too, for a true see-through HUD -- without touching the theme preset itself,
    -- so re-enabling it later looks exactly like it did before.
    local low_profile_colors = 0;
    if (low_profile) then
        local transparent = { 0.0, 0.0, 0.0, 0.0 };
        imgui.PushStyleColor(ImGuiCol_TitleBg, transparent);
        imgui.PushStyleColor(ImGuiCol_TitleBgActive, transparent);
        imgui.PushStyleColor(ImGuiCol_Header, transparent);
        imgui.PushStyleColor(ImGuiCol_HeaderHovered, transparent);
        imgui.PushStyleColor(ImGuiCol_HeaderActive, transparent);
        low_profile_colors = 5;
    end

    if (collapsed) then
        imgui.SetNextWindowSize({ last_expanded_size[1], imgui.GetFrameHeightWithSpacing() + 8 }, ImGuiCond_Always);
    elseif (pending_expand) then
        imgui.SetNextWindowSize(last_expanded_size, ImGuiCond_Always);
        pending_expand = false;
    elseif (timers.overlay_scale_dirty) then
        local scale = style.window_scale[1] / 100.0;
        imgui.SetNextWindowSize({ 300 * scale, 260 * scale }, ImGuiCond_Always);
        timers.overlay_scale_dirty = false;
    else
        imgui.SetNextWindowSize({ 300, 260 }, ImGuiCond_FirstUseEver);
    end
    if (imgui.Begin('VanaLog', style.overlay_visible, flags)) then
        imgui.PushFont(nil, imgui.GetFontSize() * style.text_scale[1]);

        if (not bottom_bar) then
            render_settings_button(style);
        end
        if (not collapsed) then
            render_active_rse(style);
        end

        if (not collapsed) then
            local tab_bar_flags = bit.bor(ImGuiTabBarFlags_NoCloseWithMiddleMouseButton, ImGuiTabBarFlags_Reorderable);
            if (imgui.BeginTabBar('##tn_overlay_tabs', tab_bar_flags)) then
                -- Timers and (world) Reminders share one tab, Timers on top -- Timers isn't tied
                -- to World Info being enabled, so this tab is always shown even when Reminders
                -- itself has nothing to say yet.
                if (render_icon_tab('##remindertab', draw_icon_clock, 'Timers & Reminders', style)) then
                    render_collapsible_section('Timers', function ()
                        render_entry_list(style, locked, 'timer', 'No timers yet.');
                    end);
                    render_collapsible_section('Reminders', function ()
                        render_reminders_tab(style);
                    end);
                    imgui.EndTabItem();
                end
                if (render_icon_tab('##notestab', draw_icon_notepad, 'Notes', style)) then
                    render_entry_list(style, locked, 'note', 'No notes yet.');
                    imgui.EndTabItem();
                end
                if (timers.settings.world.enabled[1]) then
                    if (render_icon_tab('##worldtab', draw_icon_globe, 'World Info', style)) then
                        render_world_tab(style);
                        imgui.EndTabItem();
                    end
                end
                imgui.EndTabBar();
            end

            local size_x, size_y = imgui.GetWindowSize();
            last_expanded_size = { size_x, size_y };
        end

        if (bottom_bar) then
            render_bottom_bar(style, collapsed);
        end

        render_context_menu(style, locked);

        switch(imgui.DisplayPopup('Are you sure?', 'VanaLogClearAll', function ()
            draw_plain_text('This will remove all timers and notes.');
            imgui.NewLine();
            draw_text(colors.warn, 'This cannot be undone!');
        end, PopupButtonsOkCancel), {
            [PopupResultOk] = function ()
                timers.clear_all();
            end
        });

        imgui.PopFont();
    end
    imgui.End();

    imgui.PopStyleColor(3 + low_profile_colors);
    theme.pop_window_style(theme_colors, theme_vars);

    imgui.GetStyle().WindowBorderSize = border_size;

    if (pending_delete ~= nil) then
        timers.remove_timer(pending_delete);
        pending_delete = nil;
    end
    if (pending_complete ~= nil) then
        timers.complete_note(pending_complete);
        pending_complete = nil;
    end
end

return overlay;
