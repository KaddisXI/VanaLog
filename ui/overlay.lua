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

-- Set by a Delete button during the render loop below, then actually removed only after the
-- loop finishes. This is what avoids the crash the original addon had: removing an entry from
-- timers.settings.timers *during* a forward `for x = 1, #list` loop over that same list shifts
-- every later index down by one, so the loop's cached upper bound can walk past the (now
-- shorter) list and index a nil entry. Deferring the actual removal sidesteps that entirely --
-- nothing ever mutates the list while it's being iterated.
local pending_delete = nil;

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

    if (entry.mode == 'timer') then
        local remaining = timers.get_remaining(entry);
        local label_color = style.text_color;

        if (remaining <= 0) then
            label_color = style.finished_color;
        elseif (remaining <= style.warn_threshold[1]) then
            label_color = style.warn_color;
        end

        local prefix = entry.paused and '[Paused] ' or '';
        imgui.TextColored(label_color, ('%s%s  -  %s'):fmt(prefix, timers.format_time(remaining), entry.name));
    else
        imgui.TextColored(style.header_color, entry.name);
    end

    if (style.show_categories[1] and entry.category ~= 'general') then
        imgui.SameLine();
        imgui.TextColored(category.color, ('[%s]'):fmt(category.name));
    end

    if (entry.notes ~= nil and #entry.notes > 0) then
        imgui.PushTextWrapPos(imgui.GetFontSize() * 24.0);
        imgui.TextColored(style.notes_color, entry.notes);
        imgui.PopTextWrapPos();
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

        if (imgui.SmallButton('Edit')) then
            settings_window.edit_entry(entry);
        end
        imgui.SameLine();
        if (imgui.SmallButton('Delete')) then
            pending_delete = entry.id;
        end
    end

    imgui.PopID();
    imgui.Separator();
end

--[[
* Renders every entry in timers.settings.timers whose mode matches `mode_filter`.
--]]
local function render_entry_list(style, locked, mode_filter, empty_message)
    local list = timers.settings.timers;
    local shown = 0;

    -- Safe to iterate forward: render_entry never mutates `list` directly, it only records
    -- `pending_delete`, which is applied once overlay.render()'s whole frame is done.
    for x = 1, #list do
        if (list[x].mode == mode_filter) then
            render_entry(list[x], style, locked);
            shown = shown + 1;
        end
    end

    if (shown == 0) then
        imgui.TextColored(colors.warn, empty_message);
        imgui.TextWrapped('Right-click for options, or run /vl config to add one.');
    end
end

--[[
* Renders a small, always-visible settings button in the top-right corner of the overlay's
* content area, drawn as a cogwheel rather than a text label. This matters most when the
* overlay is locked, since locking hides the native title bar entirely
* (ImGuiWindowFlags_NoTitleBar) and the right-click menu is the only other way in -- which
* isn't obvious either. Shown regardless of lock state for consistency.
--]]
local function render_settings_button(style)
    local size = imgui.GetFontSize() * 0.7;
    local avail = imgui.GetContentRegionAvail();
    imgui.SetCursorPosX(imgui.GetCursorPosX() + math.max(0, avail - size - 2));

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
* Renders the pinned "Active RSE" line above the tab bar, if enabled.
--]]
local function render_active_rse(style)
    local w = timers.settings.world;
    if (not w.enabled[1] or not w.show_in_overlay[1]) then
        return;
    end

    local ok, info = pcall(world.overview, w);
    if (not ok) then
        return;
    end

    imgui.TextColored(style.header_color, 'Active RSE:');
    imgui.SameLine();
    imgui.TextColored(colors.good, ('%s @ %s'):fmt(info.active_rse.race_name, info.active_rse.location));
    imgui.SameLine();
    imgui.TextColored(style.notes_color, ('(%s left)'):fmt(vanadiel.format_countdown(info.active_rse.ends_in_seconds)));
    imgui.Separator();
end

--[[
* Renders the compact World Info tab: active RSE, a few upcoming pops for your race, and a
* short look at the day/element calendar. The full, configurable version lives in the
* settings window's World Info tab; this is a glanceable HUD-sized summary of the same data.
--]]
local function render_world_tab(style)
    local w = timers.settings.world;

    local ok, info = pcall(world.overview, w);
    if (not ok) then
        imgui.TextColored(colors.warn, 'Could not compute World Info this frame.');
        return;
    end

    imgui.TextColored(style.header_color, 'Active RSE Now');
    imgui.TextColored(colors.good, ('%s @ %s'):fmt(info.active_rse.race_name, info.active_rse.location));
    imgui.TextColored(style.notes_color, ('Rotates in: %s'):fmt(vanadiel.format_countdown(info.active_rse.ends_in_seconds)));

    imgui.Separator();
    imgui.TextColored(style.header_color, ('Upcoming for %s'):fmt(vanadiel.RSE_RACES[info.race_index + 1]));
    for x = 1, math.min(3, #info.race_schedule) do
        local row = info.race_schedule[x];
        imgui.TextColored(style.text_color, ('%s - %s'):fmt(os.date('%b %d, %H:%M', row.starts), row.location));
    end

    imgui.Separator();
    imgui.TextColored(style.header_color, 'Day Calendar');
    for x = 1, math.min(3, #info.day_schedule) do
        local row = info.day_schedule[x];
        imgui.TextColored(row.color, row.name);
        imgui.SameLine();
        imgui.TextColored(style.notes_color, ('- %s (%s)'):fmt(row.weak_element, os.date('%b %d', row.begins)));
    end

    imgui.Separator();
    imgui.TextColored(style.header_color, 'Moon Phase');
    imgui.TextColored(style.text_color, ('%s (%d%%)'):fmt(info.moon.name, info.moon.percent));
    local now = os.time();
    if (info.moon_events.next_new_starts ~= nil) then
        local until_new = info.moon_events.next_new_starts - now;
        imgui.TextColored(style.notes_color, until_new <= 0
            and ('New Moon active (%s left)'):fmt(vanadiel.format_countdown(info.moon_events.next_new_ends - now))
            or ('Next New Moon: %s'):fmt(vanadiel.format_countdown(until_new)));
    end
    if (info.moon_events.next_full_starts ~= nil) then
        local until_full = info.moon_events.next_full_starts - now;
        imgui.TextColored(style.notes_color, until_full <= 0
            and ('Full Moon active (%s left)'):fmt(vanadiel.format_countdown(info.moon_events.next_full_ends - now))
            or ('Next Full Moon: %s'):fmt(vanadiel.format_countdown(until_full)));
    end

    imgui.Separator();
    imgui.TextColored(style.notes_color, 'More detail and settings in /vl config.');
end

--[[
* Renders a single reminder's live countdown line for the overlay's Reminders tab.
--]]
local function render_reminder_line(style, entry)
    local now = os.time();
    local detail = '';
    if (entry.extra ~= nil) then
        if (entry.extra.location ~= nil) then
            detail = ' @ ' .. entry.extra.location;
        elseif (entry.extra.weak_element ~= nil) then
            detail = (' - %s (%s)'):fmt(entry.extra.day_name, entry.extra.weak_element);
        end
    end

    imgui.TextColored(style.header_color, entry.label .. detail);
    if (entry.active) then
        imgui.TextColored(colors.good, ('Active now (ends in %s)'):fmt(vanadiel.format_countdown(entry.ends - now)));
    else
        imgui.TextColored(style.text_color, ('In: %s'):fmt(vanadiel.format_countdown(entry.starts - now)));
    end
end

--[[
* Renders the overlay's Reminders tab: a live, glanceable countdown for every reminder
* category you've enabled in the settings window's Reminders tab.
--]]
local function render_reminders_tab(style)
    local ok, status = pcall(world.reminder_status, timers.settings);
    if (not ok) then
        imgui.TextColored(colors.warn, 'Could not compute reminders this frame.');
        return;
    end

    if (#status == 0) then
        imgui.TextColored(colors.warn, 'No reminders enabled.');
        imgui.TextWrapped('Turn some on in /vl config -> Reminders.');
        return;
    end

    for x = 1, #status do
        render_reminder_line(style, status[x]);
        imgui.Separator();
    end
end

--[[
* Renders the main overlay window.
--]]
function overlay.render()
    local style = timers.settings.style;

    if (not style.overlay_visible[1]) then
        return;
    end

    pending_delete = nil;

    local finished = timers.tick();
    if (style.sound_enabled[1] and style.sound_file[1] ~= '' and #finished > 0) then
        pcall(sound.play, style.sound_file[1], style.sound_volume[1]);
    end

    local locked = style.locked[1];
    -- No ImGuiWindowFlags_NoCollapse here: the overlay can be collapsed to just its title bar,
    -- the same as the settings window, by clicking the arrow next to its title.
    local flags = 0;
    if (locked) then
        flags = bit.bor(flags, ImGuiWindowFlags_NoMove, ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoScrollbar);
    end

    local border_size = imgui.GetStyle().WindowBorderSize;
    imgui.GetStyle().WindowBorderSize = style.show_border[1] and style.border_size[1] or 0.0;

    -- Full theme skin first (buttons, tabs, headers, etc. all match the Appearance tab's
    -- chosen preset), then layer the overlay's own finer-grained overrides (custom opacity,
    -- border thickness, and the individually-editable text colors) on top of it.
    local preset_id = style.theme_preset[1];
    local theme_colors, theme_vars = theme.push_window_style(preset_id);

    imgui.PushStyleColor(ImGuiCol_WindowBg, { style.bg_color[1], style.bg_color[2], style.bg_color[3], style.bg_opacity[1] });
    imgui.PushStyleColor(ImGuiCol_Border, { style.border_color[1], style.border_color[2], style.border_color[3], style.border_opacity[1] });
    imgui.PushStyleColor(ImGuiCol_Text, style.text_color);

    imgui.SetNextWindowSize({ 300, 260 }, ImGuiCond_FirstUseEver);
    if (imgui.Begin('VanaLog', style.overlay_visible, flags)) then
        imgui.PushFont(nil, imgui.GetFontSize() * style.text_scale[1]);

        render_settings_button(style);
        render_active_rse(style);

        local tab_bar_flags = bit.bor(ImGuiTabBarFlags_NoCloseWithMiddleMouseButton, ImGuiTabBarFlags_Reorderable);
        if (imgui.BeginTabBar('##tn_overlay_tabs', tab_bar_flags)) then
            if (imgui.BeginTabItem('Timers')) then
                render_entry_list(style, locked, 'timer', 'No timers yet.');
                imgui.EndTabItem();
            end
            if (imgui.BeginTabItem('Notes')) then
                render_entry_list(style, locked, 'note', 'No notes yet.');
                imgui.EndTabItem();
            end
            if (timers.settings.world.enabled[1]) then
                if (imgui.BeginTabItem('World')) then
                    render_world_tab(style);
                    imgui.EndTabItem();
                end
                if (imgui.BeginTabItem('Reminders')) then
                    render_reminders_tab(style);
                    imgui.EndTabItem();
                end
            end
            imgui.EndTabBar();
        end

        if (imgui.BeginPopupContextWindow()) then
            if (imgui.MenuItem('Add Timer / Note...')) then
                settings_window.new_entry();
            end
            imgui.Separator();
            if (imgui.MenuItem(locked and 'Unlock Overlay' or 'Lock Overlay')) then
                style.locked[1] = not locked;
            end
            if (imgui.MenuItem('Settings...')) then
                settings_window.toggle();
            end
            imgui.Separator();
            if (imgui.MenuItem('Clear All')) then
                imgui.OpenPopup('###VanaLogClearAll');
            end
            imgui.EndPopup();
        end

        switch(imgui.DisplayPopup('Are you sure?', 'VanaLogClearAll', function ()
            imgui.Text('This will remove all timers and notes.');
            imgui.NewLine();
            imgui.TextColored(colors.warn, 'This cannot be undone!');
        end, PopupButtonsOkCancel), {
            [PopupResultOk] = function ()
                timers.clear_all();
            end
        });

        imgui.PopFont();
    end
    imgui.End();

    imgui.PopStyleColor(3);
    theme.pop_window_style(theme_colors, theme_vars);

    imgui.GetStyle().WindowBorderSize = border_size;

    if (pending_delete ~= nil) then
        timers.remove_timer(pending_delete);
        pending_delete = nil;
    end
end

return overlay;
