--[[
* vanalog - Settings / editor window: Timers & Notes, World Info, Appearance, About.
--]]

require 'common';

local chat     = require 'chat';
local imgui    = require 'imgui';
local timers   = require 'core.timers';
local world    = require 'core.world';
local vanadiel = require 'core.vanadiel';
local theme    = require 'ui.theme';
local sound    = require 'ui.sound';

local settings_window = { };

local colors = {
    header = { 1.0, 0.65, 0.26, 1.0 },
    warn   = { 0.9, 0.9, 0.0, 1.0 },
    good   = { 0.4, 0.9, 0.5, 1.0 },
    info   = { 0.45, 0.65, 1.0, 1.0 },
    muted  = { 0.75, 0.75, 0.80, 1.0 },
};

local GUILD_STATUS_LABEL = T{ open = 'Open', closed = 'Closed', holiday = 'Holiday' };
local GUILD_STATUS_COLOR = T{ open = colors.good, closed = colors.muted, holiday = colors.info };

local state = {
    is_config_open = { false },
    selected_id    = -1,

    form = {
        editing_id    = nil,
        name          = { '' },
        name_size     = 128,
        notes         = { '' },
        notes_size    = 2048,
        duration      = { '' },
        duration_size = 32,
        mode          = { 0 }, -- 0 = Timer, 1 = Note
        category      = { 0 }, -- index into timers.CATEGORIES
        repeating     = { false },

        -- Note-only "remind me" alert: a one-shot countdown, separate from a Timer's own
        -- countdown, since Notes otherwise have no time dimension at all.
        remind_enabled  = { false },
        remind_duration = { '' },
        remind_duration_size = 32,
        remind_sound    = { '' },
    },

    world_race_override = { 0 },
};

-- Null-joined combo strings, built once.
local MODE_COMBO = 'Timer\0Note\0\0';

local CATEGORY_COMBO = (function ()
    local parts = T{ };
    for x = 1, #timers.CATEGORIES do
        parts:insert(#parts + 1, timers.CATEGORIES[x].name);
    end
    return parts:concat('\0') .. '\0\0';
end)();

local RACE_COMBO = (function ()
    local parts = T{ };
    for x = 1, #vanadiel.RSE_RACES do
        parts:insert(#parts + 1, vanadiel.RSE_RACES[x]);
    end
    return parts:concat('\0') .. '\0\0';
end)();

local RACE_MODE_COMBO = 'Auto-detect\0Manual\0\0';
local race_mode_choice = { 0 };

local GUILD_COMBO = (function ()
    local parts = T{ };
    for x = 1, #vanadiel.GUILDS do
        parts:insert(#parts + 1, vanadiel.GUILDS[x].name);
    end
    return parts:concat('\0') .. '\0\0';
end)();
local guild_points_choice = { 0 };

local SOUND_NONE_LABEL = '(none)';

--[[
* Renders a "None + every file in the sounds folder" picker bound to a single reminder's (or
* note's) sound setting. Local playback only (ui/sound.lua) -- never sends a chat message.
--]]
local function render_sound_picker(id_suffix, sound_setting)
    local files = sound.list_files();
    local current_label = (sound_setting[1] == '') and SOUND_NONE_LABEL or sound_setting[1];

    imgui.PushItemWidth(200);
    if (imgui.BeginCombo('Sound' .. id_suffix, current_label)) then
        if (imgui.Selectable(SOUND_NONE_LABEL, sound_setting[1] == '')) then
            sound_setting[1] = '';
            timers.save();
        end
        for x = 1, #files do
            if (imgui.Selectable(files[x], files[x] == sound_setting[1])) then
                sound_setting[1] = files[x];
                timers.save();
            end
        end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();

    if (sound_setting[1] ~= '') then
        imgui.SameLine();
        if (imgui.Button('Test' .. id_suffix)) then
            pcall(sound.play, sound_setting[1], timers.settings.style.sound_volume[1]);
        end
    end
    if (#files == 0) then
        imgui.ShowHelp(('No sound files found. Drop .wav/.mp3 files into: %s'):fmt(sound.FOLDER));
    end
end

local THEME_COMBO = (function ()
    local parts = T{ };
    for x = 1, #theme.PRESETS do
        parts:insert(#parts + 1, theme.PRESETS[x].name);
    end
    return parts:concat('\0') .. '\0\0';
end)();
local theme_choice = { 0 };

--[[
* Resets the add/edit form back to a blank 'new entry' state.
--]]
local function reset_form()
    state.form.editing_id = nil;
    state.form.name[1] = '';
    state.form.notes[1] = '';
    state.form.duration[1] = '';
    state.form.mode[1] = 0;
    state.form.category[1] = 0;
    state.form.repeating[1] = false;
    state.form.remind_enabled[1] = false;
    state.form.remind_duration[1] = '';
    state.form.remind_sound[1] = '';
end

--[[
* Loads the given entry into the add/edit form for editing.
--]]
local function load_form(entry)
    state.form.editing_id = entry.id;
    state.form.name[1] = entry.name or '';
    state.form.notes[1] = entry.notes or '';
    state.form.duration[1] = entry.mode == 'timer' and timers.format_time(entry.duration) or '';
    state.form.mode[1] = entry.mode == 'note' and 1 or 0;
    state.form.repeating[1] = entry.repeating or false;

    state.form.remind_enabled[1] = entry.remind_enabled or false;
    state.form.remind_duration[1] = (entry.remind_enabled and entry.remind_seconds ~= nil)
        and timers.format_time(entry.remind_seconds) or '';
    state.form.remind_sound[1] = entry.remind_sound or '';

    state.form.category[1] = 0;
    for x = 1, #timers.CATEGORIES do
        if (timers.CATEGORIES[x].id == (entry.category or 'general')) then
            state.form.category[1] = x - 1;
            break;
        end
    end
end

--[[
* Syncs the theme-preset combo's selection from the saved preset. Only called when the window
* is opened (not every frame) so it never clobbers a selection the player is mid-way through
* making but hasn't clicked "Apply Preset Colors" for yet.
--]]
local function sync_theme_choice()
    local current = timers.settings.style.theme_preset[1];
    for x = 1, #theme.PRESETS do
        if (theme.PRESETS[x].id == current) then
            theme_choice[1] = x - 1;
            return;
        end
    end
end

function settings_window.toggle()
    state.is_config_open[1] = not state.is_config_open[1];
    if (state.is_config_open[1]) then
        sync_theme_choice();
    end
end

function settings_window.new_entry()
    state.selected_id = -1;
    reset_form();
    state.is_config_open[1] = true;
    sync_theme_choice();
end

function settings_window.edit_entry(entry)
    state.selected_id = entry.id;
    load_form(entry);
    state.is_config_open[1] = true;
    sync_theme_choice();
end

--[[
* Renders the 'Timers' tab of the settings/editor window.
--]]
local function render_tab_timers()
    -- Reserves enough room below both panes for the Category Colors section (a header row, a
    -- line of help text, and one row per category) to always render fully visible, without
    -- needing to scroll the window -- rather than the single frame-height gap used elsewhere,
    -- which left it clipped off the bottom of the tab.
    local category_colors_reserve = imgui.GetFrameHeightWithSpacing() * (2 + #timers.CATEGORIES);

    imgui.BeginGroup();
        imgui.TextColored(colors.header, 'Tracked Timers & Notes');
        imgui.ShowHelp('Click and drag an entry up or down to reorder it.');
        imgui.BeginChild('tn_leftpane', { 240, -category_colors_reserve }, ImGuiChildFlags_Borders);
            local list = timers.settings.timers;
            local pending_swap = nil;
            for x = 1, #list do
                local entry = list[x];
                local label = entry.mode == 'timer'
                    and ('[%s] %s##%d'):fmt(timers.format_time(timers.get_remaining(entry)), entry.name, entry.id)
                    or  ('[Note] %s##%d'):fmt(entry.name, entry.id);

                imgui.PushStyleColor(ImGuiCol_Text, timers.category_color(entry.category));
                if (imgui.Selectable(label, state.selected_id == entry.id)) then
                    state.selected_id = entry.id;
                    load_form(entry);
                end
                imgui.PopStyleColor(1);

                -- Click-and-drag reordering: once the mouse has moved a Selectable's-height
                -- worth past the row while held down, swap it with its neighbor in that
                -- direction and reset the drag distance so each further swap needs its own
                -- fresh drag. Deferred (pending_swap) rather than applied immediately, so the
                -- list being iterated right now is never mutated mid-loop.
                if (imgui.IsItemActive() and not imgui.IsItemHovered()) then
                    local dx, dy = imgui.GetMouseDragDelta(0);
                    local target = x + (dy < 0 and -1 or 1);
                    if (target >= 1 and target <= #list) then
                        pending_swap = T{ a = entry.id, b = list[target].id };
                        imgui.ResetMouseDragDelta(0);
                    end
                end
            end
            if (pending_swap ~= nil) then
                timers.swap_entries(pending_swap.a, pending_swap.b);
            end
        imgui.EndChild();

        if (imgui.Button('New')) then
            state.selected_id = -1;
            reset_form();
        end
        imgui.SameLine();
        if (imgui.Button('Delete Selected')) then
            if (state.selected_id ~= -1) then
                timers.remove_timer(state.selected_id);
                state.selected_id = -1;
                reset_form();
            end
        end
    imgui.EndGroup();
    imgui.SameLine();

    imgui.BeginGroup();
        imgui.TextColored(colors.header, state.form.editing_id ~= nil and 'Edit Entry' or 'New Entry');
        imgui.BeginChild('tn_rightpane', { 0, -category_colors_reserve }, ImGuiChildFlags_Borders);
            imgui.PushItemWidth(240);
            imgui.InputText('Name', state.form.name, state.form.name_size);

            imgui.Combo('Type', state.form.mode, MODE_COMBO);
            imgui.ShowHelp('Timer - counts down and can repeat.\nNote - a pinned reminder with no countdown.');

            imgui.Combo('Category', state.form.category, CATEGORY_COMBO);
            imgui.ShowHelp('Purely organizational - colors the entry in the overlay and list.');

            if (state.form.mode[1] == 0) then
                imgui.InputText('Duration', state.form.duration, state.form.duration_size);
                imgui.ShowHelp('Format: hh:mm:ss, mm:ss, or plain seconds. Example: 5:00 = 5 minutes.');
                imgui.Checkbox('Repeat when finished', state.form.repeating);
            end
            imgui.PopItemWidth();

            if (state.form.mode[1] == 1) then
                imgui.Checkbox('Remind me', state.form.remind_enabled);
                imgui.ShowHelp('A one-shot alert for this note -- prints to chat (and optionally plays a sound) once the time below elapses.');
                if (state.form.remind_enabled[1]) then
                    imgui.Indent();
                        imgui.PushItemWidth(240);
                        imgui.InputText('Remind in', state.form.remind_duration, state.form.remind_duration_size);
                        imgui.ShowHelp('Format: hh:mm:ss, mm:ss, or plain seconds. Example: 5:00 = 5 minutes from when you save this note.');
                        imgui.PopItemWidth();
                        render_sound_picker('##noteremind', state.form.remind_sound);
                    imgui.Unindent();
                end
            end

            imgui.InputTextMultiline('Notes', state.form.notes, state.form.notes_size, { -1, 100 });

            imgui.NewLine();
            if (imgui.Button(state.form.editing_id ~= nil and 'Save Changes' or 'Add', { 120, 0 })) then
                local name = state.form.name[1]:trim('\0'):trim();
                if (#name == 0) then
                    print(chat.header(addon.name):append(chat.error('A name is required.')));
                else
                    local mode = state.form.mode[1] == 1 and 'note' or 'timer';
                    local duration = 0;
                    local remind_seconds = nil;

                    if (mode == 'timer') then
                        duration = timers.parse_duration(state.form.duration[1]);
                        if (duration == nil or duration <= 0) then
                            print(chat.header(addon.name):append(chat.error('Invalid duration. Use hh:mm:ss, mm:ss, or seconds.')));
                            imgui.EndChild();
                            imgui.EndGroup();
                            return;
                        end
                    elseif (mode == 'note' and state.form.remind_enabled[1]) then
                        remind_seconds = timers.parse_duration(state.form.remind_duration[1]);
                        if (remind_seconds == nil or remind_seconds <= 0) then
                            print(chat.header(addon.name):append(chat.error('Invalid "Remind in" duration. Use hh:mm:ss, mm:ss, or seconds.')));
                            imgui.EndChild();
                            imgui.EndGroup();
                            return;
                        end
                    end

                    local opts = T{
                        name           = name,
                        notes          = state.form.notes[1]:trim('\0'),
                        mode           = mode,
                        category       = timers.CATEGORIES[state.form.category[1] + 1].id,
                        duration       = duration,
                        repeating      = state.form.repeating[1],
                        remind_enabled = (mode == 'note') and state.form.remind_enabled[1] or false,
                        remind_sound   = state.form.remind_sound[1],
                    };
                    if (remind_seconds ~= nil) then
                        opts.remind_seconds = remind_seconds;
                    end

                    if (state.form.editing_id ~= nil) then
                        timers.update_timer(state.form.editing_id, opts);
                    else
                        state.selected_id = timers.add_timer(opts);
                    end

                    reset_form();
                end
            end
            imgui.SameLine();
            if (imgui.Button('Clear Form', { 120, 0 })) then
                state.selected_id = -1;
                reset_form();
            end
        imgui.EndChild();
    imgui.EndGroup();

    if (imgui.CollapsingHeader('Category Colors', ImGuiTreeNodeFlags_DefaultOpen)) then
        imgui.TextColored(timers.settings.style.notes_color, 'Pick a color for each category -- it\'s used for that category\'s tag and list entries in the overlay.');
        local colors_setting = timers.settings.category_colors;
        for x = 1, #timers.CATEGORIES do
            local cat = timers.CATEGORIES[x];
            imgui.ColorEdit4(cat.name .. '##catcolor' .. cat.id, colors_setting[cat.id]);
        end
    end
end

--[[
* Renders a compact upcoming-RSE/day-calendar table.
--]]
local function render_table(id, headers, rows, cell_fn)
    if (imgui.BeginTable(id, #headers, ImGuiTableFlags_SizingFixedFit)) then
        for x = 1, #headers do
            imgui.TableSetupColumn(headers[x]);
        end
        imgui.TableHeadersRow();
        for x = 1, #rows do
            imgui.TableNextRow();
            cell_fn(rows[x], x);
        end
        imgui.EndTable();
    end
end

--[[
* Renders the 'World Info' tab: active RSE, race-specific upcoming RSE, and the day/element
* calendar. All computed locally from core/vanadiel.lua -- no network access.
--]]
local function render_tab_world()
    local w = timers.settings.world;

    imgui.Checkbox('Enable World Info', w.enabled);
    if (not w.enabled[1]) then
        return;
    end

    local ok, info = pcall(world.overview, w);
    if (not ok) then
        imgui.TextColored(colors.warn, 'Could not compute World Info this frame.');
        return;
    end

    if (imgui.CollapsingHeader('Vana\'diel Clock', ImGuiTreeNodeFlags_DefaultOpen)) then
        imgui.Text(('%s  %04d-%02d-%02d  %02d:%02d:%02d'):fmt(
            vanadiel.VANA_DAYS[info.vana_time.weekday + 1], info.vana_time.year, info.vana_time.month,
            info.vana_time.day, info.vana_time.hour, info.vana_time.min, info.vana_time.sec));
        imgui.Text(('Weak element today: %s'):fmt(vanadiel.WEAK_ELEMENT[info.vana_time.weekday + 1]));
    end

    if (imgui.CollapsingHeader('Moon Phase', ImGuiTreeNodeFlags_DefaultOpen)) then
        imgui.ShowHelp('Moon phase affects certain fish bites and gardening crop quality in-game. New Moon and Full Moon are the two phases that matter -- everything else is just the moon passing between them.');
        imgui.Checkbox('Follow (show in Overlay)##followmoon', w.follow.moon);
        imgui.Text(('Current: %s (%d%%, %s)'):fmt(info.moon.name, info.moon.percent, info.moon.waxing and 'waxing' or 'waning'));

        if (info.moon_events.next_new_starts ~= nil) then
            local until_new = info.moon_events.next_new_starts - os.time();
            if (until_new <= 0) then
                imgui.TextColored(colors.good, ('New Moon window is active (ends in %s)'):fmt(vanadiel.format_countdown(info.moon_events.next_new_ends - os.time())));
            else
                imgui.Text(('Next New Moon in: %s'):fmt(vanadiel.format_countdown(until_new)));
            end
        end
        if (info.moon_events.next_full_starts ~= nil) then
            local until_full = info.moon_events.next_full_starts - os.time();
            if (until_full <= 0) then
                imgui.TextColored(colors.good, ('Full Moon window is active (ends in %s)'):fmt(vanadiel.format_countdown(info.moon_events.next_full_ends - os.time())));
            else
                imgui.Text(('Next Full Moon in: %s'):fmt(vanadiel.format_countdown(until_full)));
            end
        end

        imgui.TextColored(timers.settings.style.notes_color, 'Set up New/Full Moon alerts in the Reminders tab.');
    end

    if (imgui.CollapsingHeader('RSE', ImGuiTreeNodeFlags_DefaultOpen)) then
        imgui.Checkbox('Follow (show in Overlay)##followrse', w.follow.rse);
        if (w.follow.rse[1]) then
            imgui.Indent();
                imgui.Checkbox('Also pin above the Overlay\'s tabs', w.show_in_overlay);
                imgui.ShowHelp('Keeps a one-line Active RSE summary visible at all times, regardless of which overlay tab is open -- on top of (not instead of) the RSE section in the World tab above.');
            imgui.Unindent();
        end
        imgui.TextColored(colors.header, 'Active Now');
        imgui.TextColored(colors.good, ('%s @ %s'):fmt(info.active_rse.race_name, info.active_rse.location));
        imgui.Text(('Rotates in: %s'):fmt(vanadiel.format_countdown(info.active_rse.ends_in_seconds)));
        local loc_detail = vanadiel.RSE_DETAILS[info.active_rse.location_index];
        if (loc_detail ~= nil) then
            imgui.TextColored(timers.settings.style.notes_color, 'Key droppers:');
            imgui.PushTextWrapPos(0.0);
            imgui.TextColored(timers.settings.style.notes_color, table.concat(loc_detail, ', '));
            imgui.PopTextWrapPos();
        end

        imgui.Separator();
        imgui.TextColored(colors.header, 'Your Race\'s Upcoming RSE');
        race_mode_choice[1] = (w.race_mode[1] == 'manual') and 1 or 0;
        imgui.PushItemWidth(160);
        if (imgui.Combo('Race Mode', race_mode_choice, RACE_MODE_COMBO)) then
            w.race_mode[1] = (race_mode_choice[1] == 1) and 'manual' or 'auto';
            timers.save();
        end
        imgui.PopItemWidth();

        if (w.race_mode[1] == 'auto' and not info.race_detected) then
            imgui.TextColored(colors.warn, 'Could not detect your race yet (not logged in?). Using the manual fallback below.');
        end

        if (w.race_mode[1] == 'manual' or not info.race_detected) then
            state.world_race_override[1] = w.race_index[1];
            imgui.PushItemWidth(180);
            if (imgui.Combo('Race##worldrace', state.world_race_override, RACE_COMBO)) then
                w.race_index[1] = state.world_race_override[1];
                timers.save();
            end
            imgui.PopItemWidth();
        else
            imgui.Text('Detected: ' .. vanadiel.RSE_RACES[info.race_index + 1]);
        end

        imgui.PushItemWidth(180);
        if (imgui.SliderInt('Lines##rselines', w.rse_lines, 3, 40)) then
            timers.save();
        end
        imgui.PopItemWidth();

        render_table('##rse_table', T{ 'Start', 'End', 'Location' }, info.race_schedule, function (row)
            imgui.TableNextColumn();
            imgui.Text(os.date('%b %d, %H:%M', row.starts));
            imgui.TableNextColumn();
            imgui.Text(os.date('%b %d, %H:%M', row.ends));
            imgui.TableNextColumn();
            imgui.Text(row.location);
            if (imgui.IsItemHovered()) then
                local detail = vanadiel.RSE_DETAILS[row.location_index];
                if (detail ~= nil) then
                    imgui.SetTooltip('Key droppers:\n' .. table.concat(detail, '\n'));
                end
            end
        end);

        imgui.TextColored(timers.settings.style.notes_color, 'Set up RSE alerts in the Reminders tab.');
    end

    if (imgui.CollapsingHeader('Day Calendar', ImGuiTreeNodeFlags_DefaultOpen)) then
        imgui.Checkbox('Follow (show in Overlay)##followday', w.follow.day);
        imgui.PushItemWidth(180);
        if (imgui.SliderInt('Lines##daylines', w.day_lines, 3, 40)) then
            timers.save();
        end
        imgui.PopItemWidth();

        render_table('##day_table', T{ 'Day', 'Begins', 'Ends', 'Weak Element', 'Moon' }, info.day_schedule, function (row)
            imgui.TableNextColumn();
            imgui.TextColored(row.color, row.name);
            imgui.TableNextColumn();
            imgui.Text(os.date('%b %d, %H:%M', row.begins));
            imgui.TableNextColumn();
            imgui.Text(os.date('%b %d, %H:%M', row.ends));
            imgui.TableNextColumn();
            imgui.Text(row.weak_element);
            imgui.TableNextColumn();
            imgui.Text(('%s (%d%%)'):fmt(row.moon_name, row.moon_percent));
        end);

        imgui.TextColored(timers.settings.style.notes_color, 'Set up Day Change alerts in the Reminders tab.');
    end

    if (imgui.CollapsingHeader('Guilds', ImGuiTreeNodeFlags_DefaultOpen)) then
        imgui.ShowHelp('Hover a guild\'s name for its shop NPC\'s zone and coordinates. Follow a guild to show it in the Overlay\'s World tab.');
        render_table('##guild_table', T{ 'Follow', 'Guild', 'Status', 'Next', 'Hours', 'Holiday' }, info.guilds, function (row)
            imgui.TableNextColumn();
            imgui.Checkbox('##followguild' .. row.key, w.follow.guilds[row.key]);
            imgui.TableNextColumn();
            imgui.Text(row.name);
            if (imgui.IsItemHovered()) then
                imgui.SetTooltip(('%s\n%s (%s)\nNPC: %s'):fmt(row.title, row.zone, row.coords, row.npc));
            end
            imgui.TableNextColumn();
            imgui.TextColored(GUILD_STATUS_COLOR[row.status], GUILD_STATUS_LABEL[row.status]);
            imgui.TableNextColumn();
            imgui.Text(('%s in: %s'):fmt(row.next_label == 'opens' and 'Opens' or 'Closes', vanadiel.format_countdown(row.countdown_seconds)));
            imgui.TableNextColumn();
            imgui.Text(('%02d:00 - %02d:00'):fmt(row.open_hour, row.close_hour));
            imgui.TableNextColumn();
            imgui.TextColored(vanadiel.DAY_COLORS[row.holiday_weekday + 1], row.holiday_name);
        end);
    end

    if (imgui.CollapsingHeader('Airship / Boats', ImGuiTreeNodeFlags_DefaultOpen)) then
        imgui.Text('Airships (Jeuno hub)');
        imgui.ShowHelp('Follow a route to show it in the Overlay\'s World tab.');
        render_table('##airship_table', T{ 'Follow', 'Route', 'Day', 'Arrives', 'Departs' }, info.airships, function (row)
            imgui.TableNextColumn();
            imgui.Checkbox('##followairship' .. row.name, w.follow.airships[row.name]);
            imgui.TableNextColumn();
            imgui.Text(row.name);
            imgui.TableNextColumn();
            imgui.TextColored(row.color, row.day_name);
            imgui.TableNextColumn();
            imgui.Text(vanadiel.format_countdown(row.arrives_in));
            imgui.TableNextColumn();
            imgui.Text(vanadiel.format_countdown(row.departs_in));
        end);

        imgui.NewLine();
        imgui.Text('Selbina <-> Mhaura Ferry');
        imgui.Checkbox('Follow (show in Overlay)##followferry', w.follow.ferry);
        imgui.PushItemWidth(180);
        if (imgui.SliderInt('Lines##ferrylines', w.ferry_lines, 3, 20)) then
            timers.save();
        end
        imgui.PopItemWidth();

        render_table('##ferry_table', T{ 'Arrives', 'ETA', 'Departs', 'ETD' }, info.ferries, function (row)
            imgui.TableNextColumn();
            imgui.TextColored(row.arrive_color, ('%s %s'):fmt(row.arrive_day, row.arrive_label));
            imgui.TableNextColumn();
            imgui.Text(vanadiel.format_countdown(row.arrives_in));
            imgui.TableNextColumn();
            imgui.TextColored(row.depart_color, ('%s %s'):fmt(row.depart_day, row.depart_label));
            imgui.TableNextColumn();
            imgui.Text(vanadiel.format_countdown(row.departs_in));
        end);
    end

    imgui.Separator();
    imgui.TextColored(timers.settings.style.notes_color, 'RSE, day/element, guild, and airship/ferry timing by Pyogenes (pyogenes.com/ffxi/timer).');
end

--[[
* Renders the shared enabled/approaching/active/lead-time/sound controls for one reminder
* category. `cfg` is one of timers.settings.reminders.{rse,day,new_moon,full_moon,guild_points,
* fishing}. `extra_fn`, if given, is called right after the Enabled checkbox (while still
* indented) -- used by Day Change for its day-of-the-week selector, and Guild Points for its
* guild picker. `show_approaching` (default true) hides the approaching/lead-time controls for
* reminders with no meaningful "not yet started" state (Guild Points, Fishing).
--]]
local function render_reminder_controls(id_suffix, cfg, help_text, extra_fn, show_approaching)
    if (show_approaching == nil) then
        show_approaching = true;
    end

    imgui.Checkbox('Enabled' .. id_suffix, cfg.enabled);
    if (help_text ~= nil) then
        imgui.ShowHelp(help_text);
    end
    if (not cfg.enabled[1]) then
        return;
    end

    imgui.Indent();
        if (extra_fn ~= nil) then
            extra_fn();
        end

        if (show_approaching) then
            imgui.Checkbox('When approaching' .. id_suffix, cfg.approaching);
            imgui.SameLine();
            imgui.Checkbox('When active' .. id_suffix, cfg.active);

            imgui.PushItemWidth(160);
            if (imgui.SliderInt('Warn this many minutes ahead' .. id_suffix, cfg.lead_minutes, 1, 60)) then
                timers.save();
            end
            imgui.PopItemWidth();
        else
            -- No "approaching" phase makes sense for this reminder (e.g. Guild Points -- its
            -- window always anchors to the most recent reset so a completed note's status
            -- persists for the rest of the day, which means there's never a future "starts" to
            -- count down to). "When active" is still meaningful on its own.
            imgui.Checkbox('When active' .. id_suffix, cfg.active);
        end

        render_sound_picker(id_suffix, cfg.sound);
    imgui.Unindent();
end

--[[
* Renders the "which Vana'diel days to alert for" checkboxes for the Day Change reminder.
--]]
local function render_day_selector(cfg)
    imgui.Text('Days to alert for:');
    for i = 1, 8 do
        imgui.Checkbox(vanadiel.VANA_DAYS[i] .. '##rdayday' .. i, cfg.days[i]);
        if (i ~= 4 and i ~= 8) then
            imgui.SameLine();
        end
    end
    if (imgui.SmallButton('All##rdayall')) then
        for i = 1, 8 do cfg.days[i][1] = true; end
        timers.save();
    end
    imgui.SameLine();
    if (imgui.SmallButton('None##rdaynone')) then
        for i = 1, 8 do cfg.days[i][1] = false; end
        timers.save();
    end
    imgui.Separator();
end

--[[
* Renders the 'Reminders' tab: one collapsible section per alert category (RSE, Day Change,
* Moon Phase -- which covers both New and Full Moon as its own independently-configurable
* sub-sections), each with its own enable/approach/active/lead-time/sound controls. Separated
* out from World Info so that tab stays a pure, uncluttered display.
--]]
local function render_tab_reminders()
    local w = timers.settings.world;
    local r = timers.settings.reminders;

    if (not w.enabled[1]) then
        imgui.TextColored(colors.warn, 'Enable World Info (World Info tab) to use reminders.');
        return;
    end

    if (imgui.CollapsingHeader('RSE', ImGuiTreeNodeFlags_DefaultOpen)) then
        render_reminder_controls('##rrse', r.rse,
            'Alerts for your own race\'s next RSE pop (race is set in the World Info tab). Shows up here and in the Overlay\'s Reminders tab -- not World Info.');
    end

    if (imgui.CollapsingHeader('Day Change', ImGuiTreeNodeFlags_DefaultOpen)) then
        render_reminder_controls('##rday', r.day,
            'Alerts when the Vana\'diel day -- and its weak element -- is about to change, or just did.',
            function () render_day_selector(r.day); end);
    end

    if (imgui.CollapsingHeader('Moon Phase', ImGuiTreeNodeFlags_DefaultOpen)) then
        imgui.TextColored(colors.header, 'New Moon');
        render_reminder_controls('##rnewmoon', r.new_moon,
            'Bite rates for fishing are increased during New and Full Moon phases.');

        imgui.Separator();

        imgui.TextColored(colors.header, 'Full Moon');
        render_reminder_controls('##rfullmoon', r.full_moon,
            'Bite rates for fishing are increased during New and Full Moon phases.');
    end

    if (imgui.CollapsingHeader('Guild Points', ImGuiTreeNodeFlags_DefaultOpen)) then
        render_reminder_controls('##rguildpoints', r.guild_points,
            'Daily Guild Point item turn-in reset -- UTC 15:00 / JP Midnight (a fixed real-world time, not tied to the Vana\'diel clock). A Note is automatically created each day; marking it Completed also updates this Reminder in the Overlay to show as completed.',
            function ()
                guild_points_choice[1] = 0;
                for x = 1, #vanadiel.GUILDS do
                    if (vanadiel.GUILDS[x].key == r.guild_points.guild[1]) then
                        guild_points_choice[1] = x - 1;
                        break;
                    end
                end

                imgui.PushItemWidth(180);
                if (imgui.Combo('Guild##rguildpointsguild', guild_points_choice, GUILD_COMBO)) then
                    r.guild_points.guild[1] = vanadiel.GUILDS[guild_points_choice[1] + 1].key;
                    timers.save();
                end
                imgui.PopItemWidth();
            end,
            false);
    end

    if (imgui.CollapsingHeader('Fishing', ImGuiTreeNodeFlags_DefaultOpen)) then
        render_reminder_controls('##rfishing', r.fishing,
            'Daily Fishing catch goal reset -- UTC 15:00 / JP Midnight (a fixed real-world time, not tied to the Vana\'diel clock). A Note is automatically created each day; marking it Completed also updates this Reminder in the Overlay to show as completed.',
            nil, false);
    end
end

--[[
* Writes a preset's colors into the editable style fields and records it as the active
* preset (used for the window/overlay reskin). Called both the moment the preset combo
* changes and from the "Re-apply Preset Colors" button.
--]]
local function apply_preset(preset_id)
    timers.settings.style.theme_preset[1] = preset_id;

    local style = timers.settings.style;
    local colors_out = theme.overlay_colors(preset_id);

    style.bg_color[1], style.bg_color[2], style.bg_color[3] = colors_out.bg_color[1], colors_out.bg_color[2], colors_out.bg_color[3];
    style.bg_opacity[1] = colors_out.bg_opacity;
    style.border_color[1], style.border_color[2], style.border_color[3] = colors_out.border_color[1], colors_out.border_color[2], colors_out.border_color[3];
    style.border_opacity[1] = colors_out.border_opacity;
    for i = 1, 4 do style.text_color[i] = colors_out.text_color[i]; end
    for i = 1, 4 do style.header_color[i] = colors_out.header_color[i]; end
    for i = 1, 4 do style.notes_color[i] = colors_out.notes_color[i]; end
    for i = 1, 4 do style.warn_color[i] = colors_out.warn_color[i]; end
    for i = 1, 4 do style.finished_color[i] = colors_out.finished_color[i]; end

    timers.save();
end

--[[
* Renders the 'Appearance' tab of the settings/editor window.
--]]
local function render_tab_appearance()
    local style = timers.settings.style;

    imgui.BeginChild('tn_appearance', { 0, -imgui.GetFrameHeightWithSpacing() }, ImGuiChildFlags_Borders);
        if (imgui.CollapsingHeader('General', ImGuiTreeNodeFlags_DefaultOpen)) then
            imgui.Checkbox('Show Overlay', style.overlay_visible);
            imgui.SameLine();
            imgui.Checkbox('Low Profile Mode', style.low_profile_mode);
            imgui.ShowHelp('Overlay only -- forces background, border, and header-background opacity to 0 for a fully see-through HUD, without touching those sliders below (turning this off brings them right back).');
            imgui.Checkbox('Lock Overlay (hides edit buttons)', style.locked);
            imgui.Checkbox('Show category tags', style.show_categories);
            imgui.Checkbox('Move title bar to bottom', style.title_bar_bottom);
            imgui.ShowHelp('Leaves the top of the overlay -- above the tabs -- completely clean, with a custom bar at the bottom taking over the collapse arrow, label, settings gear, and close button instead.');

            imgui.PushItemWidth(200);
            if (imgui.Combo('Preset', theme_choice, THEME_COMBO)) then
                apply_preset(theme.PRESETS[theme_choice[1] + 1].id);
            end
            imgui.PopItemWidth();
            imgui.ShowHelp('Picking a preset reskins the overlay and this window immediately, and seeds the colors below -- which you can still fine-tune individually afterward.');
            imgui.SameLine();
            if (imgui.Button('Re-apply Preset Colors')) then
                apply_preset(theme.PRESETS[theme_choice[1] + 1].id);
            end
            imgui.ShowHelp('Use this if you\'ve tweaked individual colors below and want to snap them all back to the selected preset.');

            imgui.PushItemWidth(200);
            if (imgui.SliderInt('Window Scale', style.window_scale, 50, 200, '%d%%')) then
                timers.request_window_rescale();
                timers.save();
            end
            imgui.PopItemWidth();
            imgui.ShowHelp('Resizes both the overlay and this settings window to this percent of their default size -- an alternative to dragging their bottom-right corner, which still works too.');
        end

        if (imgui.CollapsingHeader('Background', ImGuiTreeNodeFlags_DefaultOpen)) then
            imgui.ColorEdit3('Background Color', style.bg_color);
            imgui.SliderFloat('Background Opacity', style.bg_opacity, 0.0, 1.0, '%.2f');
        end

        if (imgui.CollapsingHeader('Border', ImGuiTreeNodeFlags_DefaultOpen)) then
            imgui.Checkbox('Show Border', style.show_border);
            imgui.ColorEdit3('Border Color', style.border_color);
            imgui.SliderFloat('Border Opacity', style.border_opacity, 0.0, 1.0, '%.2f');
            imgui.SliderFloat('Border Thickness', style.border_size, 0.0, 10.0, '%.1f');
            imgui.SliderFloat('Separator Thickness (Overlay only)', style.separator_size, 1.0, 8.0, '%.1f');
            imgui.ShowHelp('Thickness of the line drawn between entries in the overlay -- 1.0 matches the thin default line.');
        end

        if (imgui.CollapsingHeader('Text', ImGuiTreeNodeFlags_DefaultOpen)) then
            imgui.ColorEdit4('Text Color', style.text_color);
            imgui.ColorEdit4('Header/Note Title Color', style.header_color);
            imgui.ColorEdit4('Notes Color', style.notes_color);
            imgui.ColorEdit4('Warning Color', style.warn_color);
            imgui.ColorEdit4('Finished Color', style.finished_color);
            imgui.SliderFloat('Text Size', style.text_scale, 0.5, 3.0, '%.2f');

            imgui.Checkbox('Black Text Outline in Low Profile Mode (Overlay only)', style.text_outline);
            imgui.ShowHelp('Only actually drawn while Low Profile Mode is also on -- keeps overlay text readable with no background box behind it.');
        end

        if (imgui.CollapsingHeader('Alerts', ImGuiTreeNodeFlags_DefaultOpen)) then
            imgui.SliderInt('Warn Threshold (seconds)', style.warn_threshold, 0, 120);
            imgui.Checkbox('Flash when a timer finishes', style.flash_on_finish);
            imgui.Checkbox('Play a sound when a timer finishes', style.sound_enabled);
            if (style.sound_enabled[1]) then
                local files = sound.list_files();
                if (#files == 0) then
                    imgui.TextColored(colors.warn, ('Drop .wav/.mp3 files into: %s'):fmt(sound.FOLDER));
                else
                    imgui.PushItemWidth(220);
                    if (imgui.BeginCombo('Sound File', style.sound_file[1] == '' and '(choose a file)' or style.sound_file[1])) then
                        for x = 1, #files do
                            if (imgui.Selectable(files[x], files[x] == style.sound_file[1])) then
                                style.sound_file[1] = files[x];
                                timers.save();
                            end
                        end
                        imgui.EndCombo();
                    end
                    imgui.PopItemWidth();
                    imgui.SameLine();
                    if (imgui.Button('Test')) then
                        pcall(sound.play, style.sound_file[1], style.sound_volume[1]);
                    end
                end
                imgui.SliderInt('Volume', style.sound_volume, 0, 100, '%d%%');
            end
        end
    imgui.EndChild();

    if (imgui.Button('Save Settings')) then
        timers.save();
        print(chat.header(addon.name):append(chat.message('Settings saved.')));
    end
    imgui.SameLine();
    if (imgui.Button('Reload Settings')) then
        timers.reload();
        print(chat.header(addon.name):append(chat.message('Settings reloaded.')));
    end
    imgui.SameLine();
    if (imgui.Button('Reset To Defaults')) then
        timers.reset();
        print(chat.header(addon.name):append(chat.message('Settings reset to defaults.')));
    end
end

--[[
* Returns the Sunday-00:00 start (and the Saturday-23:59:59 end) of the calendar week
* containing `timestamp`, for grouping the Journal into weekly buckets.
--]]
local function week_bounds(timestamp)
    local t = os.date('*t', timestamp);
    local day_start = timestamp - (t.hour * 3600 + t.min * 60 + t.sec);
    local start = day_start - ((t.wday - 1) * 86400); -- t.wday: 1 = Sunday .. 7 = Saturday
    return start, start + (7 * 86400) - 1;
end

--[[
* Renders one Journal week's table of entries.
--]]
local function render_journal_week_table(id, rows)
    render_table(id, T{ 'When', 'Status', 'Name', 'Notes' }, rows, function (row)
        imgui.TableNextColumn();
        imgui.Text(os.date('%b %d, %H:%M', row.timestamp));
        imgui.TableNextColumn();
        if (row.kind == 'completed') then
            imgui.TextColored(colors.good, 'Completed');
        else
            imgui.TextColored(colors.info, 'Added');
        end
        imgui.TableNextColumn();
        imgui.Text(row.name);
        imgui.TableNextColumn();
        imgui.PushTextWrapPos(0.0);
        imgui.TextColored(timers.settings.style.notes_color, row.notes);
        imgui.PopTextWrapPos();
    end);
end

--[[
* Renders the 'Journal' tab: a dated, append-only log of Notes added and completed, bucketed
* into collapsible weeks (most recent week expanded, older weeks collapsed) to keep a
* long-running log from turning into a wall of rows.
--]]
local function render_tab_journal()
    imgui.TextColored(colors.header, 'Journal');
    imgui.TextWrapped('A dated log of every note you\'ve added and completed, grouped by week.');
    imgui.NewLine();

    local entries = timers.settings.journal.entries;
    if (#entries == 0) then
        imgui.TextColored(colors.warn, 'Nothing logged yet. Add or complete a note to start your journal.');
    else
        -- Newest first, then grouped into consecutive same-week buckets (entries are already
        -- chronological, so a single pass is enough -- no separate sort needed).
        local buckets = T{ };
        for x = #entries, 1, -1 do
            local row = entries[x];
            local w_start, w_end = week_bounds(row.timestamp);
            local bucket = buckets[#buckets];
            if (bucket == nil or bucket.start ~= w_start) then
                bucket = T{ start = w_start, ends = w_end, rows = T{ } };
                buckets:insert(#buckets + 1, bucket);
            end
            bucket.rows:insert(#bucket.rows + 1, row);
        end

        for b = 1, #buckets do
            local bucket = buckets[b];
            local label = ('Week of %s - %s (%d)##journalweek%d'):fmt(
                os.date('%b %d', bucket.start), os.date('%b %d', bucket.ends), #bucket.rows, b);
            local flags = (b == 1) and ImGuiTreeNodeFlags_DefaultOpen or 0;
            if (imgui.CollapsingHeader(label, flags)) then
                render_journal_week_table('##journal_table_' .. b, bucket.rows);
            end
        end
    end

    imgui.NewLine();
    if (imgui.Button('Clear Journal')) then
        timers.clear_journal();
    end
end

--[[
* Renders the 'About' tab.
--]]
local function render_tab_about()
    imgui.TextColored(colors.header, addon.name .. ' v' .. addon.version);
    imgui.Text('by ' .. addon.author);
    imgui.TextWrapped('A scalable overlay for user-created timers and notes, with a built-in Vana\'diel RSE and day/element tracker for Phoenix XI.');
    imgui.NewLine();
    imgui.TextColored(colors.header, 'Credits');
    imgui.TextWrapped('RSE rotation, day/element timing, guild hours, and airship/ferry schedules are computed locally using the public timing formulas published by Pyogenes:');
    imgui.TextColored(timers.settings.style.header_color, 'https://www.pyogenes.com/ffxi/timer/v2.html');
    imgui.TextWrapped('No part of World Info contacts that site, or any other site, at runtime -- the math runs entirely in this addon.');
    imgui.NewLine();
    imgui.TextWrapped('Guild shop NPC zone/coordinates cross-referenced from FFXIclopedia\'s Guild Merchant page (hours/holidays on that page are outdated for this server and were not used).');
    imgui.NewLine();
    imgui.TextWrapped('Theme presets and settings-window design patterns were inspired by Cadence and Momentum, by Kipling.');
end

--[[
* Renders the settings/editor window.
--]]
function settings_window.render()
    if (not state.is_config_open[1]) then
        return;
    end

    local preset_id = timers.settings.style.theme_preset[1];
    local color_count, var_count = theme.push_window_style(preset_id);

    if (timers.settings_scale_dirty) then
        local scale = timers.settings.style.window_scale[1] / 100.0;
        imgui.SetNextWindowSize({ 760 * scale, 520 * scale }, ImGuiCond_Always);
        timers.settings_scale_dirty = false;
    else
        imgui.SetNextWindowSize({ 760, 520 }, ImGuiCond_FirstUseEver);
    end
    if (imgui.Begin('VanaLog - Settings', state.is_config_open)) then
        if (imgui.BeginTabBar('##tn_tabbar', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton)) then
            if (imgui.BeginTabItem('Appearance')) then
                render_tab_appearance();
                imgui.EndTabItem();
            end
            if (imgui.BeginTabItem('Timers & Notes')) then
                render_tab_timers();
                imgui.EndTabItem();
            end
            if (imgui.BeginTabItem('Journal')) then
                render_tab_journal();
                imgui.EndTabItem();
            end
            if (imgui.BeginTabItem('World Info')) then
                render_tab_world();
                imgui.EndTabItem();
            end
            if (imgui.BeginTabItem('Reminders')) then
                render_tab_reminders();
                imgui.EndTabItem();
            end
            if (imgui.BeginTabItem('About')) then
                render_tab_about();
                imgui.EndTabItem();
            end
            imgui.EndTabBar();
        end
    end
    imgui.End();

    theme.pop_window_style(color_count, var_count);
end

return settings_window;
