--[[
* vanalog - Timer/note data model and persistence.
--]]

require 'common';

local settings = require 'settings';
local vanadiel = require 'core.vanadiel';

local SCHEMA_VERSION = 2;

-- Built-in categories. Each timer/note is tagged with one of these ids. `color` here is only
-- the *default* -- the live, player-customizable color for each id lives in
-- timers.settings.category_colors (see make_defaults() below) and is what's actually
-- displayed; timers.category_color() resolves that with a fallback to this default.
local CATEGORIES = T{
    { id = 'general', name = 'General',    color = { 0.82, 0.82, 0.86, 1.0 } },
    { id = 'recast',  name = 'Recast',     color = { 0.45, 0.70, 1.00, 1.0 } },
    { id = 'pop',     name = 'Pop/Spawn',  color = { 0.95, 0.55, 0.30, 1.0 } },
    { id = 'buff',    name = 'Buff/Food',  color = { 0.55, 0.90, 0.60, 1.0 } },
    { id = 'craft',   name = 'Craft',      color = { 0.85, 0.70, 0.35, 1.0 } },
    { id = 'event',   name = 'Event',      color = { 0.80, 0.50, 0.90, 1.0 } },
    { id = 'mission', name = 'Mission',    color = { 0.90, 0.35, 0.35, 1.0 } },
    { id = 'quest',   name = 'Quest',      color = { 0.45, 0.85, 0.85, 1.0 } },
    { id = 'daily',   name = 'Daily',      color = { 1.00, 0.84, 0.00, 1.0 } },
};

--[[
* Returns a brand new defaults table. Called fresh every time it's needed (on load, and again
* right after, for the unshare pass below) so nothing can ever hand out the same table twice --
* Ashita's settings library otherwise fills any missing nested table with the *same* default
* table reference for every character, so mutating one character's settings could silently
* mutate the shared defaults (and every other character's settings) too.
--]]
local function make_defaults()
    -- One {r,g,b,a} per category id, seeded from CATEGORIES' built-in defaults -- this is the
    -- table the color pickers in the Timers & Notes tab actually edit.
    local category_colors = T{ };
    for x = 1, #CATEGORIES do
        local c = CATEGORIES[x].color;
        category_colors[CATEGORIES[x].id] = { c[1], c[2], c[3], c[4] };
    end

    return T{
        schema_version   = SCHEMA_VERSION,
        next_id          = 1,
        timers           = T{ },
        category_colors  = category_colors,

        -- A dated, append-only log of Notes added and completed -- a running receipt of what
        -- you've worked on, independent of the active Notes list itself.
        journal = T{
            entries = T{ },
        },

        style = T{
            theme_preset     = { 'phoenix' },

            overlay_visible  = { true },
            locked           = { false },
            show_border      = { true },

            -- Overlay-only: forces background, border, and header-background opacity to 0
            -- (regardless of their own sliders below) for a fully see-through HUD look, without
            -- touching the stored slider values themselves -- turning this off brings them right
            -- back. Does not affect the settings window.
            low_profile_mode = { false },

            -- Moves the overlay's title bar (collapse arrow, "VanaLog" label, settings gear,
            -- close button) from its native spot at the top to a custom bar at the bottom,
            -- leaving the top of the window completely clean/transparent above the tabs.
            -- `collapsed` is this custom bar's own collapse state (there's no native title bar
            -- left to track it once this is on).
            title_bar_bottom = { false },
            collapsed        = { false },

            -- Overall window size, as a percent of each window's own default size (50-200).
            -- Separate from text_scale below (which only scales the overlay's font); this
            -- resizes both the overlay and the settings window themselves, as an alternative to
            -- dragging their bottom-right resize grip.
            window_scale     = { 100 },

            bg_color         = { 0.05, 0.05, 0.08 },
            bg_opacity       = { 0.75 },

            border_color     = { 0.35, 0.35, 0.42 },
            border_opacity   = { 0.85 },
            border_size      = { 1.0 },

            -- Overlay-only: thickness of the horizontal line drawn between entries/lines. 1.0
            -- (the default) matches ImGui's own built-in Separator() exactly; anything above
            -- that switches to a hand-drawn line instead, since Separator() has no public way
            -- to make it thicker. Uses the Border color/opacity above.
            separator_size   = { 1.0 },

            text_color       = { 1.00, 1.00, 1.00, 1.00 },
            header_color     = { 1.00, 0.82, 0.40, 1.00 },
            notes_color      = { 0.75, 0.75, 0.80, 1.00 },
            warn_color       = { 1.00, 0.85, 0.20, 1.00 },
            finished_color   = { 1.00, 0.25, 0.25, 1.00 },

            warn_threshold   = { 10 },
            text_scale       = { 1.0 },
            flash_on_finish  = { true },
            show_categories  = { true },

            -- Overlay-only: a black outline around overlay text, simulated by drawing extra
            -- offset copies of each piece of text (no real font-level outline is available).
            -- Only actually drawn while Low Profile Mode is also on.
            text_outline     = { true },

            sound_enabled    = { false },
            sound_file       = { '' },
            sound_volume     = { 80 },
        },

        world = T{
            enabled          = { true },
            race_mode        = { 'auto' }, -- 'auto' or 'manual'
            race_index       = { 7 },      -- manual fallback (0-7, see vanadiel.RSE_RACES)
            show_in_overlay  = { false },
            rse_lines        = { 8 },
            day_lines        = { 8 },
            ferry_lines      = { 5 },

            -- Which World Info items to show in the overlay's World tab -- off by default for
            -- everything, so nobody's forced to track something they don't care about. The
            -- settings window's own World Info tab always shows everything regardless of this;
            -- it's only the compact overlay view that's opt-in. guilds/airships are keyed by
            -- guild key / route name (see ensure_world_follow()) since there are several of each.
            follow = T{
                rse      = { false },
                day      = { false },
                moon     = { false },
                ferry    = { false },
                guilds   = T{ },
                airships = T{ },
            },
        },

        -- Reminders: one block per alert category (rse, day, new_moon, full_moon), each with
        -- the same shape -- enabled, whether to alert when approaching and/or when active, how
        -- far ahead "approaching" means, and an optional local sound file (never a party call).
        reminders = T{
            rse = T{
                enabled         = { false },
                approaching     = { true },
                active          = { true },
                lead_minutes    = { 15 },
                sound           = { '' },
            },
            day = T{
                enabled         = { false },
                approaching     = { true },
                active          = { true },
                lead_minutes    = { 15 },
                sound           = { '' },
                -- Which of the 8 Vana'diel days (vanadiel.VANA_DAYS order, 1-indexed here) to
                -- alert for -- each its own {bool} so it can bind straight to a Checkbox, same
                -- as every other setting. Defaults to every day, matching the original
                -- "every day change" behavior.
                days = T{ { true }, { true }, { true }, { true }, { true }, { true }, { true }, { true } },
            },
            new_moon = T{
                enabled         = { false },
                approaching     = { true },
                active          = { true },
                lead_minutes    = { 15 },
                sound           = { '' },
            },
            full_moon = T{
                enabled         = { false },
                approaching     = { true },
                active          = { true },
                lead_minutes    = { 15 },
                sound           = { '' },
            },
            -- Daily Guild Point item turn-in reset -- a real-world (not Vana'diel) clock event,
            -- fixed at 15:00 UTC (8am PT / 11am ET / 12am JPT) every day. `guild` is which
            -- guild's turn-in to track, by key (vanadiel.GUILDS); defaults to the first guild so
            -- there's always a valid selection even before the player has picked one.
            guild_points = T{
                enabled         = { false },
                approaching     = { true },
                active          = { true },
                lead_minutes    = { 15 },
                sound           = { '' },
                guild           = { vanadiel.GUILDS[1].key },

                -- Tracks the auto-created "{Guild} GP Item Turn-In" note (see
                -- world.sync_linked_notes()): which cycle it was last (re)created for, and which
                -- cycle (if any) has been marked completed. 0 means "none yet" for both.
                cycle_starts    = { 0 },
                completed_for   = { 0 },
            },
            -- Daily Fishing catch goal reset -- same real-world 15:00 UTC event as Guild Points
            -- above, auto-creating its own linked "Daily: Fishing 200 catches" note each cycle.
            fishing = T{
                enabled         = { false },
                approaching     = { true },
                active          = { true },
                lead_minutes    = { 15 },
                sound           = { '' },

                cycle_starts    = { 0 },
                completed_for   = { 0 },
            },
        },
    };
end

--[[
* Recursively replaces any nested table in `loaded` that is still the *same table reference*
* as the one in `kept` (meaning Ashita's settings library filled it in from defaults rather
* than loading it from disk) with the corresponding table from a brand new defaults instance.
--]]
local function unshare(loaded, kept, fresh)
    for key, value in pairs(kept) do
        if (type(value) == 'table') then
            if (rawequal(loaded[key], value)) then
                loaded[key] = fresh[key];
            elseif (type(loaded[key]) == 'table') then
                unshare(loaded[key], value, fresh[key]);
            end
        end
    end
end

--[[
* Guarantees every current category id has a {r,g,b,a} entry in settings.category_colors,
* filling in any gap (e.g. a save file from before a category existed) with that category's
* built-in default. Keeps the Category Colors UI safe to bind directly to, regardless of how
* deeply Ashita's settings library merges missing nested keys from defaults.
--]]
local function ensure_category_colors(s)
    if (s.category_colors == nil) then
        s.category_colors = T{ };
    end
    for x = 1, #CATEGORIES do
        local cat = CATEGORIES[x];
        if (s.category_colors[cat.id] == nil) then
            s.category_colors[cat.id] = { cat.color[1], cat.color[2], cat.color[3], cat.color[4] };
        end
    end
end

--[[
* Guarantees every current guild and airship route has a follow {bool} entry in
* settings.world.follow.guilds/.airships, defaulting any gap (a new guild/route, or a save file
* from before this existed) to false -- not followed. Same self-healing reasoning as
* ensure_category_colors() above.
--]]
local function ensure_world_follow(s)
    local follow = s.world.follow;
    if (follow.guilds == nil) then
        follow.guilds = T{ };
    end
    if (follow.airships == nil) then
        follow.airships = T{ };
    end
    for x = 1, #vanadiel.GUILDS do
        local key = vanadiel.GUILDS[x].key;
        if (follow.guilds[key] == nil) then
            follow.guilds[key] = { false };
        end
    end
    for x = 1, #vanadiel.AIRSHIP_ROUTES do
        local key = vanadiel.AIRSHIP_ROUTES[x].name;
        if (follow.airships[key] == nil) then
            follow.airships[key] = { false };
        end
    end
end

local timers = T{
    CATEGORIES = CATEGORIES,
};

local kept_defaults = make_defaults();
timers.settings = settings.load(kept_defaults);
unshare(timers.settings, kept_defaults, make_defaults());
ensure_category_colors(timers.settings);
ensure_world_follow(timers.settings);

-- Non-persisted, in-memory only: set by the Window Scale slider, each flag consumed (and reset
-- to false) by its own window the next time it renders. Two separate flags, rather than one,
-- because the overlay and settings window render one after another in the same frame (see
-- vanalog.lua's d3d_present) -- a single shared flag would only reach whichever rendered first.
timers.overlay_scale_dirty = false;
timers.settings_scale_dirty = false;

--[[
* Requests a one-off resize of both the overlay and the settings window to match the current
* Window Scale setting, the next time each of them renders. Call this when that setting changes.
--]]
function timers.request_window_rescale()
    timers.overlay_scale_dirty = true;
    timers.settings_scale_dirty = true;
end

--[[
* Looks up a category by id, falling back to 'general' if unknown.
--]]
function timers.category(id)
    for x = 1, #CATEGORIES do
        if (CATEGORIES[x].id == id) then
            return CATEGORIES[x];
        end
    end
    return CATEGORIES[1];
end

--[[
* Resolves the live, player-customizable color for a category id (timers.settings.category_colors),
* falling back to that category's built-in default if the id is missing one (e.g. a category
* added in a later version, for a save file from before it existed).
*
* @param {string} id - A category id.
* @return {table} {r, g, b, a}
--]]
function timers.category_color(id)
    local custom = timers.settings.category_colors[id];
    if (custom ~= nil) then
        return custom;
    end
    return timers.category(id).color;
end

--[[
* Callback invoked whenever the settings block updates (e.g. character switch).
--]]
local function on_settings_update(s)
    if (s ~= nil) then
        local fresh = make_defaults();
        unshare(s, kept_defaults, fresh);
        ensure_category_colors(s);
        ensure_world_follow(s);
        timers.settings = s;
    end
    settings.save();
end
settings.register('settings', 'settings_update', on_settings_update);

--[[
* Saves the current settings to disk.
--]]
function timers.save()
    pcall(settings.save);
end

--[[
* Reloads the settings from disk.
--]]
function timers.reload()
    settings.reload();
end

--[[
* Resets the settings to their default values.
--]]
function timers.reset()
    settings.reset();
end

--[[
* Parses a duration string ('hh:mm:ss', 'mm:ss', or plain seconds) into seconds.
*
* @param {string} str - The duration string to parse.
* @return {number|nil} The parsed duration in seconds, or nil if invalid.
--]]
function timers.parse_duration(str)
    if (str == nil) then
        return nil;
    end

    str = tostring(str):trim('\0'):trim();
    if (#str == 0) then
        return nil;
    end

    if (str:find(':') ~= nil) then
        local parts = str:split(':');
        if (#parts < 1 or #parts > 3) then
            return nil;
        end

        local nums = T{ };
        for x = 1, #parts do
            local n = tonumber(parts[x]);
            if (n == nil) then
                return nil;
            end
            nums:insert(#nums + 1, n);
        end

        local seconds = 0;
        if (#nums == 3) then
            seconds = (nums[1] * 3600) + (nums[2] * 60) + nums[3];
        elseif (#nums == 2) then
            seconds = (nums[1] * 60) + nums[2];
        else
            seconds = nums[1];
        end

        return math.floor(seconds);
    end

    local n = tonumber(str);
    if (n == nil) then
        return nil;
    end

    return math.floor(n);
end

--[[
* Formats a number of seconds into a 'h:mm:ss' or 'm:ss' display string.
*
* @param {number} seconds - The number of seconds to format.
* @return {string} The formatted time string.
--]]
function timers.format_time(seconds)
    seconds = math.max(0, math.floor(seconds or 0));

    local h = math.floor(seconds / 3600);
    local m = math.floor((seconds % 3600) / 60);
    local s = seconds % 60;

    if (h > 0) then
        return ('%d:%02d:%02d'):fmt(h, m, s);
    end

    return ('%d:%02d'):fmt(m, s);
end

--[[
* Finds a timer/note entry by its id.
*
* @param {number} id - The id of the entry to find.
* @return {table|nil} The entry, or nil if not found.
--]]
function timers.find_by_id(id)
    local list = timers.settings.timers;
    for x = 1, #list do
        if (list[x].id == id) then
            return list[x];
        end
    end
    return nil;
end

--[[
* Finds a timer/note entry by its name. (Case-insensitive, first match.)
*
* @param {string} name - The name of the entry to find.
* @return {table|nil} The entry, or nil if not found.
--]]
function timers.find_by_name(name)
    if (name == nil) then
        return nil;
    end

    local lname = name:lower();
    local list = timers.settings.timers;
    for x = 1, #list do
        if (list[x].name ~= nil and list[x].name:lower() == lname) then
            return list[x];
        end
    end
    return nil;
end

--[[
* Adds a new timer or note entry.
*
* @param {table} opts - The entry options. (name, notes, mode, duration, repeating, category)
* @return {number} The id assigned to the new entry.
--]]
function timers.add_timer(opts)
    opts = opts or T{ };

    local id = timers.settings.next_id;
    timers.settings.next_id = id + 1;

    local entry = T{
        id             = id,
        name           = opts.name or ('Timer %d'):fmt(id),
        notes          = opts.notes or '',
        mode           = opts.mode or 'timer',
        category       = opts.category or 'general',
        duration       = opts.duration or 0,
        start_time     = os.time(),
        paused         = false,
        paused_at      = 0,
        repeating      = opts.repeating or false,
        sound_played   = false,

        -- Note-only "remind me" alert: a one-shot countdown independent of the timer countdown
        -- above, since Notes otherwise have no time dimension at all.
        remind_enabled = opts.remind_enabled or false,
        remind_seconds = opts.remind_seconds or 0,
        remind_start   = os.time(),
        remind_fired   = false,
        remind_sound   = opts.remind_sound or '',

        -- Ties this note back to a reminders.<category> this note was auto-created for (e.g.
        -- 'guild_points'), so completing it can reflect back as that reminder's status instead
        -- of a plain delete. `linked_cycle` identifies *which* occurrence of that reminder this
        -- note belongs to (world.lua's occurrence.starts), since a new one is created each cycle.
        -- Both nil for an ordinary, unlinked note/timer.
        linked_reminder = opts.linked_reminder,
        linked_cycle    = opts.linked_cycle,
    };

    timers.settings.timers:insert(#timers.settings.timers + 1, entry);

    if (entry.mode == 'note') then
        timers.journal_add('added', entry.name, entry.notes);
    end

    timers.save();

    return id;
end

--[[
* Appends an entry to the Journal -- a dated, append-only log of Notes added and completed.
*
* @param {string} kind - 'added' or 'completed'.
* @param {string} name - The note's name at the time of this event.
* @param {string} notes - The note's text at the time of this event.
--]]
function timers.journal_add(kind, name, notes)
    timers.settings.journal.entries:insert(#timers.settings.journal.entries + 1, T{
        timestamp = os.time(),
        kind      = kind,
        name      = name,
        notes     = notes or '',
    });
    timers.save();
end

--[[
* Marks a note as completed: logs it to the Journal, reflects back onto whatever reminder this
* note is linked to (if any -- see add_timer()'s linked_reminder/linked_cycle), then removes it
* from the active list (a completed note is done, not something still worth tracking).
*
* @param {number} id - The id of the note entry to complete.
* @return {boolean} True on success, false if no such note entry exists.
--]]
function timers.complete_note(id)
    local entry = timers.find_by_id(id);
    if (entry == nil or entry.mode ~= 'note') then
        return false;
    end

    timers.journal_add('completed', entry.name, entry.notes);

    if (entry.linked_reminder ~= nil) then
        local cfg = timers.settings.reminders[entry.linked_reminder];
        if (cfg ~= nil and cfg.completed_for ~= nil) then
            cfg.completed_for[1] = entry.linked_cycle or 0;
        end
    end

    return timers.remove_timer(id);
end

--[[
* Clears every entry from the Journal. Does not touch the active timers/notes list.
--]]
function timers.clear_journal()
    timers.settings.journal.entries = T{ };
    timers.save();
end

--[[
* Updates an existing timer or note entry.
*
* @param {number} id - The id of the entry to update.
* @param {table} opts - The entry options to update. (name, notes, mode, duration, repeating, category)
* @return {boolean} True on success, false otherwise.
--]]
function timers.update_timer(id, opts)
    local entry = timers.find_by_id(id);
    if (entry == nil) then
        return false;
    end

    opts = opts or T{ };

    if (opts.name ~= nil) then
        entry.name = opts.name;
    end
    if (opts.notes ~= nil) then
        entry.notes = opts.notes;
    end
    if (opts.mode ~= nil) then
        entry.mode = opts.mode;
    end
    if (opts.category ~= nil) then
        entry.category = opts.category;
    end
    if (opts.repeating ~= nil) then
        entry.repeating = opts.repeating;
    end
    if (opts.duration ~= nil) then
        entry.duration = opts.duration;
        entry.start_time = os.time();
        entry.paused = false;
        entry.paused_at = 0;
        entry.sound_played = false;
    end

    if (opts.remind_enabled ~= nil) then
        entry.remind_enabled = opts.remind_enabled;
    end
    if (opts.remind_sound ~= nil) then
        entry.remind_sound = opts.remind_sound;
    end
    if (opts.remind_seconds ~= nil) then
        entry.remind_seconds = opts.remind_seconds;
        entry.remind_start = os.time();
        entry.remind_fired = false;
    end

    timers.save();
    return true;
end

--[[
* Removes a timer or note entry. Safe to call from within a render loop that is iterating
* over timers.settings.timers -- callers that render lists should still prefer to defer this
* until after the loop completes (see ui/overlay.lua), since removing mid-iteration will shift
* later indices out from under a forward-iterating loop.
*
* @param {number} id - The id of the entry to remove.
* @return {boolean} True on success, false otherwise.
--]]
function timers.remove_timer(id)
    local list = timers.settings.timers;
    for x = 1, #list do
        if (list[x].id == id) then
            list:remove(x);
            timers.save();
            return true;
        end
    end
    return false;
end

--[[
* Swaps two entries' positions in the tracked list (by id), for manual drag-to-reorder in the
* settings window and the overlay. A plain value swap at two existing indices -- unlike
* remove_timer()'s removal, this never changes the list's length, so it's always safe even
* while something else is mid-iteration over it.
*
* @param {number} id_a - The id of the first entry.
* @param {number} id_b - The id of the second entry.
* @return {boolean} True if both entries were found and swapped, false otherwise.
--]]
function timers.swap_entries(id_a, id_b)
    local list = timers.settings.timers;
    local idx_a, idx_b;

    for x = 1, #list do
        if (list[x].id == id_a) then
            idx_a = x;
        end
        if (list[x].id == id_b) then
            idx_b = x;
        end
    end

    if (idx_a == nil or idx_b == nil or idx_a == idx_b) then
        return false;
    end

    list[idx_a], list[idx_b] = list[idx_b], list[idx_a];
    timers.save();
    return true;
end

--[[
* Removes all timer and note entries.
--]]
function timers.clear_all()
    timers.settings.timers = T{ };
    timers.save();
end

--[[
* Returns the remaining seconds on a countdown timer entry.
*
* @param {table} entry - The timer entry.
* @return {number|nil} The remaining seconds, or nil if the entry is not a timer.
--]]
function timers.get_remaining(entry)
    if (entry == nil or entry.mode ~= 'timer') then
        return nil;
    end

    local now = entry.paused and entry.paused_at or os.time();
    local elapsed = now - entry.start_time;

    return entry.duration - elapsed;
end

--[[
* Returns the remaining seconds on a note's "remind me" countdown.
*
* @param {table} entry - The note entry.
* @return {number|nil} The remaining seconds, or nil if this entry has no active reminder.
--]]
function timers.get_reminder_remaining(entry)
    if (entry == nil or not entry.remind_enabled) then
        return nil;
    end

    return (entry.remind_start + entry.remind_seconds) - os.time();
end

--[[
* Checks every entry's "remind me" countdown and fires (once) any that have just elapsed.
* Call this once per frame (or less often); like timers.tick(), it's safe to call repeatedly --
* each reminder only ever fires once, tracked by entry.remind_fired.
*
* @return {table} Array of { id, name, sound } for reminders that fired just now.
--]]
function timers.check_note_reminders()
    local list = timers.settings.timers;
    local fired = T{ };
    local now = os.time();

    for x = 1, #list do
        local entry = list[x];
        if (entry.remind_enabled and not entry.remind_fired) then
            local remaining = (entry.remind_start + entry.remind_seconds) - now;
            if (remaining <= 0) then
                entry.remind_fired = true;
                fired:insert(#fired + 1, T{ id = entry.id, name = entry.name, sound = entry.remind_sound });
            end
        end
    end

    if (#fired > 0) then
        timers.save();
    end

    return fired;
end

--[[
* Toggles the paused state of a countdown timer entry.
*
* @param {number} id - The id of the entry to toggle.
--]]
function timers.toggle_pause(id)
    local entry = timers.find_by_id(id);
    if (entry == nil or entry.mode ~= 'timer') then
        return;
    end

    if (entry.paused) then
        local pausedFor = os.time() - entry.paused_at;
        entry.start_time = entry.start_time + pausedFor;
        entry.paused = false;
        entry.paused_at = 0;
    else
        entry.paused = true;
        entry.paused_at = os.time();
    end

    timers.save();
end

--[[
* Restarts a countdown timer entry from now.
*
* @param {number} id - The id of the entry to restart.
--]]
function timers.restart_timer(id)
    local entry = timers.find_by_id(id);
    if (entry == nil or entry.mode ~= 'timer') then
        return;
    end

    entry.start_time = os.time();
    entry.paused = false;
    entry.paused_at = 0;
    entry.sound_played = false;

    timers.save();
end

--[[
* Ticks all timer entries: auto-restarts repeating timers that have finished, and returns the
* ids of any non-repeating timers that finished for the first time this tick (so the UI layer
* can play a sound / flash without re-triggering every frame while it sits at zero).
*
* Should be called once per frame.
*
* @return {table} Array of entry ids that just finished.
--]]
function timers.tick()
    local list = timers.settings.timers;
    local just_finished = T{ };

    for x = 1, #list do
        local entry = list[x];
        if (entry.mode == 'timer' and not entry.paused) then
            local remaining = timers.get_remaining(entry);
            if (remaining ~= nil and remaining <= 0) then
                if (entry.repeating) then
                    entry.start_time = os.time();
                    entry.sound_played = false;
                elseif (not entry.sound_played) then
                    entry.sound_played = true;
                    just_finished:insert(#just_finished + 1, entry.id);
                end
            end
        end
    end

    return just_finished;
end

-- Return the timers library table..
return timers;
