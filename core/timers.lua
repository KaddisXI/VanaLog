--[[
* vanalog - Timer/note data model and persistence.
--]]

require 'common';

local settings = require 'settings';

local SCHEMA_VERSION = 2;

-- Built-in categories. Each timer/note is tagged with one of these ids.
local CATEGORIES = T{
    { id = 'general', name = 'General',    color = { 0.82, 0.82, 0.86, 1.0 } },
    { id = 'recast',  name = 'Recast',     color = { 0.45, 0.70, 1.00, 1.0 } },
    { id = 'pop',     name = 'Pop/Spawn',  color = { 0.95, 0.55, 0.30, 1.0 } },
    { id = 'buff',    name = 'Buff/Food',  color = { 0.55, 0.90, 0.60, 1.0 } },
    { id = 'craft',   name = 'Craft',      color = { 0.85, 0.70, 0.35, 1.0 } },
    { id = 'event',   name = 'Event',      color = { 0.80, 0.50, 0.90, 1.0 } },
};

--[[
* Returns a brand new defaults table. Called fresh every time it's needed (on load, and again
* right after, for the unshare pass below) so nothing can ever hand out the same table twice --
* Ashita's settings library otherwise fills any missing nested table with the *same* default
* table reference for every character, so mutating one character's settings could silently
* mutate the shared defaults (and every other character's settings) too.
--]]
local function make_defaults()
    return T{
        schema_version = SCHEMA_VERSION,
        next_id        = 1,
        timers         = T{ },

        style = T{
            theme_preset     = { 'phoenix' },

            overlay_visible  = { true },
            locked           = { false },
            show_border      = { true },

            bg_color         = { 0.05, 0.05, 0.08 },
            bg_opacity       = { 0.75 },

            border_color     = { 0.35, 0.35, 0.42 },
            border_opacity   = { 0.85 },
            border_size      = { 1.0 },

            text_color       = { 1.00, 1.00, 1.00, 1.00 },
            header_color     = { 1.00, 0.82, 0.40, 1.00 },
            notes_color      = { 0.75, 0.75, 0.80, 1.00 },
            warn_color       = { 1.00, 0.85, 0.20, 1.00 },
            finished_color   = { 1.00, 0.25, 0.25, 1.00 },

            warn_threshold   = { 10 },
            text_scale       = { 1.0 },
            flash_on_finish  = { true },
            show_categories  = { true },

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
            moon_lines       = { 4 },
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

local timers = T{
    CATEGORIES = CATEGORIES,
};

local kept_defaults = make_defaults();
timers.settings = settings.load(kept_defaults);
unshare(timers.settings, kept_defaults, make_defaults());

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
* Callback invoked whenever the settings block updates (e.g. character switch).
--]]
local function on_settings_update(s)
    if (s ~= nil) then
        local fresh = make_defaults();
        unshare(s, kept_defaults, fresh);
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
        id           = id,
        name         = opts.name or ('Timer %d'):fmt(id),
        notes        = opts.notes or '',
        mode         = opts.mode or 'timer',
        category     = opts.category or 'general',
        duration     = opts.duration or 0,
        start_time   = os.time(),
        paused       = false,
        paused_at    = 0,
        repeating    = opts.repeating or false,
        sound_played = false,
    };

    timers.settings.timers:insert(#timers.settings.timers + 1, entry);
    timers.save();

    return id;
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
