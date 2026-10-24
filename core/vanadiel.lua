--[[
* vanalog - Vana'diel clock, RSE rotation, and day/element calendar.
*
* This is a Lua port of the public domain-use timing formulas published by
* Pyogenes at https://www.pyogenes.com/ffxi/timer/v2.html (script: timer4.js).
* Per that script's own license terms ("CODE IS FREE FOR USE AS LONG AS YOU
* GIVE CREDIT"), credit is given here and in the addon's README/UI.
*
* Everything below is pure math against the real-world clock -- there is no
* network access, no login, and no scraping involved. The addon computes the
* same Vana'diel time / moon phase / RSE rotation / weekday schedule that
* page does, independently, using the same basis timestamps.
--]]

require 'common';

local vanadiel = T{ };

-- Seconds in a Vana'diel day (the real time it takes for one in-game day to pass) and a real day.
local SEC_GAME_DAY = (24 * 60 * 60) / 25;
local SEC_REAL_DAY = 24 * 60 * 60;

vanadiel.VANA_DAYS = T{ 'Firesday', 'Earthsday', 'Watersday', 'Windsday', 'Iceday', 'Lightningday', 'Lightsday', 'Darksday' };
vanadiel.DAY_COLORS = T{
    { 0.87, 0.27, 0.27, 1.0 }, -- Firesday
    { 0.80, 0.80, 0.20, 1.0 }, -- Earthsday
    { 0.30, 0.45, 0.95, 1.0 }, -- Watersday
    { 0.25, 0.75, 0.35, 1.0 }, -- Windsday
    { 0.60, 0.80, 1.00, 1.0 }, -- Iceday
    { 0.75, 0.40, 0.90, 1.0 }, -- Lightningday
    { 0.80, 0.80, 0.80, 1.0 }, -- Lightsday
    { 0.45, 0.45, 0.50, 1.0 }, -- Darksday
};
vanadiel.WEAK_ELEMENT = T{ 'Ice', 'Lightning', 'Fire', 'Earth', 'Wind', 'Water', 'Darkness', 'Light' };
vanadiel.PHASE_NAMES = T{ 'Full Moon', 'Waning Gibbous', 'Last Quarter', 'Waning Crescent', 'New Moon', 'Waxing Crescent', 'First Quarter', 'Waxing Gibbous' };

-- RSErace array order from the source script. Index (1-based here) matches FFXI's own
-- race id minus 1, i.e. race id 1 (Hume M) -> index 1, ... race id 8 (Galka) -> index 8.
vanadiel.RSE_RACES = T{ 'Male Hume', 'Female Hume', 'Male Elvaan', 'Female Elvaan', 'Male Tarutaru', 'Female Tarutaru', 'Mithra', 'Galka' };
vanadiel.RSE_LOCATIONS = T{ 'Gusgen Mines', 'Shakrami Maze', 'Ordelle Caves' };

-- Key item droppers per RSE location, for reference when the pop is up.
vanadiel.RSE_DETAILS = T{
    [1] = { -- Gusgen Mines
        'Sad Fly', 'Gallinipper', 'Rancid Ooze', 'Banshee', 'Mauthe Dog', 'Myconid', 'Wight',
        'Ghast', 'Wendigo', 'Spunkie', 'Amphisbaena', 'Thunder Elemental', 'Greater Pugil',
    },
    [2] = { -- Shakrami Maze
        'Goblin Furrier', 'Goblin Shaman', 'Goblin Pathfinder', 'Goblin Smithy', 'Caterchipillar', 'Wight',
        'Labyrinth Scorpion', 'Abyss Worm', 'Protozoan', 'Air Elemental', 'Ichorous Ire',
    },
    [3] = { -- Ordelle Caves
        'Air Elemental', 'Goblin Shaman', 'Goblin Smithy', 'Goblin Pathfinder', 'Goliath Beetle',
        'Napam', 'Stroper', 'Stroper Chyme', 'Water Elemental',
    },
};

--[[
* Converts a table of UTC date/time fields into Unix epoch seconds, without assuming the
* host's local timezone. Lua's os.time(table) interprets the table as local time, so we
* measure the local<->UTC offset against "now" and apply it as a correction. This can be
* off by up to an hour around a DST transition between now and the target date; that's an
* accepted, long-standing tradeoff for this kind of client-side Vana'diel clock and matches
* what community Lua ports of this script have always done.
--]]
local function utc_offset()
    local now = os.time();
    return os.difftime(now, os.time(os.date('!*t', now)));
end

local function timegm(t)
    return os.time(t) + utc_offset();
end

-- Basis timestamps, matching timer4.js exactly (basisDate / Mndate / RSEdate).
local BASIS_EPOCH = timegm({ year = 2002, month = 6, day = 23, hour = 15, min = 0,  sec = 0,  isdst = false });
local MOON_EPOCH  = timegm({ year = 2004, month = 1, day = 25, hour = 2,  min = 31, sec = 12, isdst = false });
local RSE_EPOCH   = timegm({ year = 2004, month = 1, day = 28, hour = 9,  min = 14, sec = 24, isdst = false });

--[[
* Formats a countdown in seconds as 'd:hh:mm', 'h:mm:ss' or 'm:ss'.
--]]
function vanadiel.format_countdown(seconds)
    seconds = math.max(0, math.floor(seconds or 0));

    local d = math.floor(seconds / SEC_REAL_DAY);
    local h = math.floor((seconds % SEC_REAL_DAY) / 3600);
    local m = math.floor((seconds % 3600) / 60);
    local s = seconds % 60;

    if (d > 0) then
        return ('%d:%02d:%02d:%02d'):fmt(d, h, m, s);
    elseif (h > 0) then
        return ('%d:%02d:%02d'):fmt(h, m, s);
    end

    return ('%d:%02d'):fmt(m, s);
end

--[[
* Returns the current Vana'diel date/time, derived purely from the real-world clock.
*
* @return {table} { year, month, day, hour, min, sec, weekday (0-7) }
--]]
function vanadiel.now()
    local now = os.time();
    local vana = ((898 * 360 + 30) * SEC_REAL_DAY) + (now - BASIS_EPOCH) * 25;

    return T{
        year    = math.floor(vana / (360 * SEC_REAL_DAY)),
        month   = math.floor((vana % (360 * SEC_REAL_DAY)) / (30 * SEC_REAL_DAY)) + 1,
        day     = math.floor((vana % (30 * SEC_REAL_DAY)) / SEC_REAL_DAY) + 1,
        hour    = math.floor((vana % SEC_REAL_DAY) / 3600),
        min     = math.floor((vana % 3600) / 60),
        sec     = math.floor(vana % 60),
        weekday = math.floor((vana % (8 * SEC_REAL_DAY)) / SEC_REAL_DAY),
    };
end

--[[
* Resolves a moon-phase bucket (0-7, indexing PHASE_NAMES) and percentage for a given
* 0-83 game-day position in the 84-day lunar cycle, mirroring timer4.js's bucket ranges.
--]]
local function moon_bucket(moon_days)
    local percent = -math.floor(((42 - moon_days) / 42 * 100) + 0.5);

    local phase;
    if (percent <= -94 or percent >= 90) then
        phase = 0;
    elseif (percent >= -93 and percent <= -62) then
        phase = 1;
    elseif (percent >= -61 and percent <= -41) then
        phase = 2;
    elseif (percent >= -40 and percent <= -11) then
        phase = 3;
    elseif (percent >= -10 and percent <= 6) then
        phase = 4;
    elseif (percent >= 7 and percent <= 36) then
        phase = 5;
    elseif (percent >= 37 and percent <= 56) then
        phase = 6;
    else
        phase = 7;
    end

    return phase, math.abs(percent);
end

--[[
* Returns the current moon phase.
*
* @return {table} { name, percent, next_name, next_in_seconds }
--]]
function vanadiel.moon_phase()
    local now = os.time();
    local elapsed = now - MOON_EPOCH;
    local moon_days = math.floor(elapsed / SEC_GAME_DAY) % 84;
    local into_day = elapsed % SEC_GAME_DAY;

    local phase, percent = moon_bucket(moon_days);

    -- Phase boundaries, in game-days from the start of the 84-day cycle.
    local bounds = T{ 3, 17, 25, 38, 45, 58, 66, 80 };
    local next_bound = nil;
    for x = 1, #bounds do
        if (bounds[x] > moon_days) then
            next_bound = bounds[x];
            break;
        end
    end
    next_bound = next_bound or (bounds[1] + 84);

    local next_in = ((next_bound - moon_days) * SEC_GAME_DAY) - into_day;

    return T{
        name            = vanadiel.PHASE_NAMES[phase + 1],
        percent         = percent,
        next_name       = vanadiel.PHASE_NAMES[((phase + 1) % 8) + 1],
        next_in_seconds = next_in,
    };
end

--[[
* Builds a forward-looking calendar of New Moon and Full Moon windows -- the phases that
* matter most for moon-gated fishing and gardening. Each lunar cycle is 84 game days; the
* Full Moon window is the last 7 game days of the cycle, and the New Moon window is game
* days 35-42 of the cycle (7 days wide, same as Full Moon).
*
* @param {number} count - How many upcoming cycles to list.
* @return {table} Array of { new_start, new_end, full_start, full_end }
--]]
function vanadiel.moon_calendar(count)
    local now = os.time();
    local full_moon_basis = MOON_EPOCH + (3 * SEC_GAME_DAY);

    local list = T{ };
    for i = 0, (count - 1) do
        local elapsed_cycles = math.floor((now - full_moon_basis) / (84 * SEC_GAME_DAY)) + i;
        local full_end = full_moon_basis + (elapsed_cycles * 84 * SEC_GAME_DAY);
        local full_start = full_end - (7 * SEC_GAME_DAY);
        local new_start = full_end - (49 * SEC_GAME_DAY);
        local new_end = full_end - (42 * SEC_GAME_DAY);

        list:insert(#list + 1, T{
            new_start  = new_start,
            new_end    = new_end,
            full_start = full_start,
            full_end   = full_end,
        });
    end

    return list;
end

--[[
* Finds the next upcoming New Moon window and Full Moon window, for a quick "time until"
* readout (useful for planning moon-gated fishing/gardening without reading a whole table).
*
* @return {table} { next_new_starts, next_new_ends, next_full_starts, next_full_ends }
--]]
function vanadiel.next_moon_events()
    local now = os.time();
    local cal = vanadiel.moon_calendar(3);

    local next_new, next_full;
    for x = 1, #cal do
        if (next_new == nil and cal[x].new_end > now) then
            next_new = cal[x];
        end
        if (next_full == nil and cal[x].full_end > now) then
            next_full = cal[x];
        end
    end

    return T{
        next_new_starts  = next_new and next_new.new_start or nil,
        next_new_ends    = next_new and next_new.new_end or nil,
        next_full_starts = next_full and next_full.full_start or nil,
        next_full_ends   = next_full and next_full.full_end or nil,
    };
end

--[[
* Builds a forward-looking Vana'diel day/weak-element/moon-phase calendar.
*
* Note: the source page actually anchors its "Day Calendar" table to a different basis
* timestamp (Mndate) than the one it uses for the live "Vana'diel Time" readout
* (basisDate), so the page's own calendar labels can disagree with its own "today" --
* confirmed by comparing a live capture of both sections. That's not something worth
* reproducing: this anchors the whole calendar to the same basis as vanadiel.now(), so
* "today" here always matches the live clock.
*
* @param {number} count - How many consecutive Vana'diel days to list, starting today.
* @return {table} Array of { weekday, name, color, begins, ends, weak_element, moon_name, moon_percent }
--]]
function vanadiel.day_schedule(count)
    local now = os.time();
    local vana = ((898 * 360 + 30) * SEC_REAL_DAY) + (now - BASIS_EPOCH) * 25;

    local into_day_real_seconds = (vana % SEC_REAL_DAY) / 25;
    local day_start = now - into_day_real_seconds;
    local weekday_now = math.floor((vana % (8 * SEC_REAL_DAY)) / SEC_REAL_DAY);

    local list = T{ };
    for i = 0, (count - 1) do
        local begins = day_start + (i * SEC_GAME_DAY);
        local ends = begins + SEC_GAME_DAY;
        local idx = (weekday_now + i) % 8;

        local moon_days = math.floor((begins - MOON_EPOCH) / SEC_GAME_DAY) % 84;
        local phase, percent = moon_bucket(moon_days);

        list:insert(#list + 1, T{
            weekday      = idx,
            name         = vanadiel.VANA_DAYS[idx + 1],
            color        = vanadiel.DAY_COLORS[idx + 1],
            begins       = begins,
            ends         = ends,
            weak_element = vanadiel.WEAK_ELEMENT[idx + 1],
            moon_name    = vanadiel.PHASE_NAMES[phase + 1],
            moon_percent = percent,
        });
    end

    return list;
end

--[[
* Returns the RSE pop that is active right now (across all races), plus how long until the
* rotation moves on.
*
* @return {table} { race_index (0-7), race_name, location, location_index (1-3), ends_in_seconds }
--]]
function vanadiel.rse_active()
    local now = os.time();
    local elapsed_weeks = math.floor((now - RSE_EPOCH) / (8 * SEC_GAME_DAY));
    local block_start = RSE_EPOCH + (elapsed_weeks * 8 * SEC_GAME_DAY);
    local block_end = block_start + (8 * SEC_GAME_DAY);

    local race_index = elapsed_weeks % 8;
    local location_index = elapsed_weeks % 3;

    return T{
        race_index      = race_index,
        race_name       = vanadiel.RSE_RACES[race_index + 1],
        location        = vanadiel.RSE_LOCATIONS[location_index + 1],
        location_index  = location_index + 1,
        ends_in_seconds = block_end - now,
    };
end

--[[
* Builds the upcoming RSE schedule for one specific race.
*
* @param {number} race_index - 0-7, indexing RSE_RACES (FFXI race id - 1).
* @param {number} count - How many upcoming pops to list.
* @return {table} Array of { starts, ends, location, location_index }
--]]
function vanadiel.rse_schedule_for_race(race_index, count)
    local now = os.time();
    local offset_time = race_index * 8 * SEC_GAME_DAY;

    local list = T{ };
    for i = 0, (count - 1) do
        local elapsed_cycles = math.floor((now - RSE_EPOCH) / (64 * SEC_GAME_DAY)) + i;

        local elapsed_location_weeks = math.floor((now - RSE_EPOCH) / (8 * SEC_GAME_DAY)) + (8 * i);
        local race_offset = race_index - (elapsed_location_weeks % 8);
        elapsed_location_weeks = elapsed_location_weeks + race_offset;

        local starts = RSE_EPOCH + (elapsed_cycles * 64 * SEC_GAME_DAY) + offset_time;
        local ends = starts + (8 * SEC_GAME_DAY);
        local location_index = elapsed_location_weeks % 3;

        list:insert(#list + 1, T{
            starts         = starts,
            ends           = ends,
            location       = vanadiel.RSE_LOCATIONS[location_index + 1],
            location_index = location_index + 1,
        });
    end

    return list;
end

--[[
* Builds the upcoming RSE schedule across all races, in rotation order.
*
* @param {number} count - How many upcoming pops to list.
* @return {table} Array of { starts, ends, race_index, race_name, location, location_index }
--]]
function vanadiel.rse_schedule_all(count)
    local now = os.time();
    local base_weeks = math.floor((now - RSE_EPOCH) / (8 * SEC_GAME_DAY));

    local list = T{ };
    for i = 0, (count - 1) do
        local elapsed_weeks = base_weeks + i;
        local starts = RSE_EPOCH + (elapsed_weeks * 8 * SEC_GAME_DAY);
        local race_index = elapsed_weeks % 8;
        local location_index = elapsed_weeks % 3;

        list:insert(#list + 1, T{
            starts         = starts,
            ends           = starts + (8 * SEC_GAME_DAY),
            race_index     = race_index,
            race_name      = vanadiel.RSE_RACES[race_index + 1],
            location       = vanadiel.RSE_LOCATIONS[location_index + 1],
            location_index = location_index + 1,
        });
    end

    return list;
end

-- Return the vanadiel library table..
return vanadiel;
