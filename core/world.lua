--[[
* vanalog - World Info: active RSE, race-specific RSE schedule, and the day/element
* calendar, built on top of core/vanadiel.lua's pure Vana'diel-clock math.
--]]

require 'common';

local vanadiel = require 'core.vanadiel';

local world = T{ };

--[[
* Reads the local character's race from the game's memory, defensively. Returns nil (rather
* than throwing) if the character isn't fully loaded yet -- e.g. during zoning -- so callers
* always have a safe fallback.
*
* @return {number|nil} 0-7, indexing vanadiel.RSE_RACES, or nil if unavailable.
--]]
function world.detect_race()
    local ok, index = pcall(function ()
        return AshitaCore:GetMemoryManager():GetParty():GetMemberTargetIndex(0);
    end);
    if (not ok or index == nil or index == 0) then
        return nil;
    end

    local ok2, race = pcall(function ()
        return AshitaCore:GetMemoryManager():GetEntity():GetRace(index);
    end);
    if (not ok2 or race == nil or race < 1 or race > 8) then
        return nil;
    end

    -- FFXI race ids are 1-8 (Hume M/F, Elvaan M/F, Tarutaru M/F, Mithra, Galka), matching
    -- vanadiel.RSE_RACES in the same order, 1-based vs 0-based.
    return race - 1;
end

--[[
* Resolves which race index to use for the RSE schedule, honoring a manual override in
* settings and falling back gracefully if auto-detection isn't available yet.
*
* @param {table} world_settings - The addon's settings.world table.
* @return {number} 0-7, indexing vanadiel.RSE_RACES.
--]]
function world.effective_race_index(world_settings)
    if (world_settings.race_mode[1] == 'manual') then
        return world_settings.race_index[1];
    end

    local detected = world.detect_race();
    if (detected ~= nil) then
        return detected;
    end

    return world_settings.race_index[1];
end

--[[
* Builds the full World Info snapshot used by both the settings window and the overlay.
*
* @param {table} world_settings - The addon's settings.world table.
* @return {table} {
*   vana_time, moon, race_index, race_detected, active_rse, race_schedule, day_schedule
* }
--]]
function world.overview(world_settings)
    local race_index = world.effective_race_index(world_settings);

    return T{
        vana_time     = vanadiel.now(),
        moon          = vanadiel.moon_phase(),
        moon_events   = vanadiel.next_moon_events(),
        moon_calendar = vanadiel.moon_calendar(math.max(1, world_settings.moon_lines[1])),
        race_index    = race_index,
        race_detected = world.detect_race() ~= nil,
        active_rse    = vanadiel.rse_active(),
        race_schedule = vanadiel.rse_schedule_for_race(race_index, math.max(1, world_settings.rse_lines[1])),
        day_schedule  = vanadiel.day_schedule(math.max(1, world_settings.day_lines[1])),
    };
end

--[[
* Returns { starts, ends, extra } for a reminder category's next occurrence, or nil if it
* can't currently be computed. `extra` carries category-specific display context.
--]]
local function next_occurrence(category, settings)
    if (category == 'rse') then
        -- rse_schedule_for_race's first row is "this race's slot within the current 64-game-day
        -- cycle", which has usually already ended by the time you ask (each race only owns 1/8
        -- of that cycle) -- row 2 (one full cycle later) is always guaranteed to still be ahead
        -- of now, so pick whichever of the two hasn't ended yet.
        local ok, rows = pcall(function ()
            local race_index = world.effective_race_index(settings.world);
            return vanadiel.rse_schedule_for_race(race_index, 2);
        end);
        if (not ok or rows == nil) then
            return nil;
        end
        local now = os.time();
        local row = (rows[1] ~= nil and rows[1].ends > now) and rows[1] or rows[2];
        if (row == nil) then
            return nil;
        end
        return T{ starts = row.starts, ends = row.ends, extra = T{ location = row.location } };
    end

    if (category == 'day') then
        -- rows[1] is today (already begun), so the search starts at rows[2]. Up to 8 further
        -- rows guarantee covering every distinct Vana'diel weekday at least once, so this always
        -- finds a match if at least one day is selected.
        local ok, rows = pcall(vanadiel.day_schedule, 9);
        if (not ok or rows == nil) then
            return nil;
        end

        local selected = settings.reminders.day.days;
        for x = 2, #rows do
            local row = rows[x];
            if (selected[row.weekday + 1] ~= nil and selected[row.weekday + 1][1]) then
                return T{ starts = row.begins, ends = row.ends, extra = T{ day_name = row.name, weak_element = row.weak_element } };
            end
        end

        return nil; -- no day is selected
    end

    local ok, moon_events = pcall(vanadiel.next_moon_events);
    if (not ok) then
        return nil;
    end
    if (category == 'new_moon' and moon_events.next_new_starts ~= nil) then
        return T{ starts = moon_events.next_new_starts, ends = moon_events.next_new_ends, extra = T{ } };
    end
    if (category == 'full_moon' and moon_events.next_full_starts ~= nil) then
        return T{ starts = moon_events.next_full_starts, ends = moon_events.next_full_ends, extra = T{ } };
    end

    return nil;
end

local REMINDER_CATEGORIES = T{ 'rse', 'day', 'new_moon', 'full_moon' };
local REMINDER_LABELS = T{ rse = 'RSE', day = 'Day Change', new_moon = 'New Moon', full_moon = 'Full Moon' };

-- Tracks which occurrence (by its start timestamp) has already triggered each kind of alert,
-- per category, so check_alerts() fires once per real occurrence rather than once per frame
-- for however long the window stays active/approaching. Session-local: resets on addon reload,
-- which just means a reload mid-window can re-announce it once -- a minor, acceptable quirk.
local alert_state = T{ };
for x = 1, #REMINDER_CATEGORIES do
    alert_state[REMINDER_CATEGORIES[x] .. '_approach_for'] = nil;
    alert_state[REMINDER_CATEGORIES[x] .. '_active_for'] = nil;
end

--[[
* Checks whether any reminder should fire this call, based on the current settings and what's
* already been alerted for the current occurrence of each category. Call this once per frame
* (or less often) from the UI layer; it returns only newly-triggered events, not ongoing state.
*
* @param {table} settings - The addon's whole settings table (needs .world and .reminders).
* @return {table} Array of { kind, category, seconds, sound, extra } -- kind is
*   '<category>_approach' or '<category>_active'; `extra` carries category-specific context
*   (e.g. rse.location, day.day_name/weak_element).
--]]
function world.check_alerts(settings)
    local events = T{ };

    if (not settings.world.enabled[1]) then
        return events;
    end

    local now = os.time();

    for x = 1, #REMINDER_CATEGORIES do
        local category = REMINDER_CATEGORIES[x];
        local cfg = settings.reminders[category];
        if (cfg.enabled[1]) then
            local occurrence = next_occurrence(category, settings);
            if (occurrence ~= nil) then
                local until_start = occurrence.starts - now;
                local approach_key = category .. '_approach_for';
                local active_key = category .. '_active_for';

                if (until_start <= 0) then
                    if (cfg.active[1] and alert_state[active_key] ~= occurrence.starts) then
                        alert_state[active_key] = occurrence.starts;
                        events:insert(#events + 1, T{
                            kind = category .. '_active', category = category,
                            seconds = occurrence.ends - now, sound = cfg.sound[1], extra = occurrence.extra,
                        });
                    end
                elseif (until_start <= math.max(0, cfg.lead_minutes[1]) * 60) then
                    if (cfg.approaching[1] and alert_state[approach_key] ~= occurrence.starts) then
                        alert_state[approach_key] = occurrence.starts;
                        events:insert(#events + 1, T{
                            kind = category .. '_approach', category = category,
                            seconds = until_start, sound = cfg.sound[1], extra = occurrence.extra,
                        });
                    end
                end
            end
        end
    end

    return events;
end

--[[
* Builds a live status snapshot of every *enabled* reminder category, for the overlay's
* Reminders tab -- independent of the approach/active alert thresholds above, this just shows
* "what's coming up and when" for anything you've turned on.
*
* @param {table} settings - The addon's whole settings table.
* @return {table} Array of { category, label, active, starts, ends, extra }
--]]
function world.reminder_status(settings)
    local status = T{ };

    if (not settings.world.enabled[1]) then
        return status;
    end

    local now = os.time();
    for x = 1, #REMINDER_CATEGORIES do
        local category = REMINDER_CATEGORIES[x];
        if (settings.reminders[category].enabled[1]) then
            local occurrence = next_occurrence(category, settings);
            if (occurrence ~= nil) then
                status:insert(#status + 1, T{
                    category = category,
                    label    = REMINDER_LABELS[category],
                    active   = (occurrence.starts <= now),
                    starts   = occurrence.starts,
                    ends     = occurrence.ends,
                    extra    = occurrence.extra,
                });
            end
        end
    end

    return status;
end

return world;
