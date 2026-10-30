--[[
* Addons - vanalog
*
* A scalable overlay for creating your own timers and notes, with adjustable background color,
* opacity, text size, and text color -- plus a built-in Vana'diel clock showing active RSE and
* your race's upcoming RSE pops, the day/element calendar, and moon phase, computed locally (no
* network access) using timing formulas published by Pyogenes (https://www.pyogenes.com/ffxi/timer/).
--]]

addon.name      = 'vanalog';
addon.author    = 'Kaddis';
addon.version   = '2.5';
addon.desc      = 'A scalable overlay for user-created timers and notes, with a Vana\'diel RSE/day/moon tracker.';
addon.link      = 'https://ashitaxi.com/';

require 'common';

local chat     = require 'chat';
local timers   = require 'core.timers';
local world    = require 'core.world';
local vanadiel = require 'core.vanadiel';
local sound    = require 'ui.sound';
local overlay  = require 'ui.overlay';
local settings_window = require 'ui.settings_window';

--[[
* Prints the addon help information.
*
* @param {boolean} isError - Flag if this function was invoked due to an error.
--]]
local function print_help(isError)
    if (isError) then
        print(chat.header(addon.name):append(chat.error('Invalid command syntax for command: ')):append(chat.success('/vl')));
    else
        print(chat.header(addon.name):append(chat.message('Available commands:')));
    end

    local cmds = T{
        { '/vl', 'Toggles the timers/notes overlay.' },
        { '/vl config', 'Toggles the settings/editor window.' },
        { '/vl add <name> <duration> [notes...]', 'Adds a countdown timer. Duration: hh:mm:ss, mm:ss, or seconds.' },
        { '/vl note <name> [notes...]', 'Adds a pinned note (no countdown).' },
        { '/vl del <name>', 'Removes the timer/note with the given name.' },
        { '/vl clear', 'Removes all timers and notes.' },
        { '/vl lock', 'Toggles locking the overlay.' },
        { '/vl world', 'Prints the active RSE and your race\'s next pop to chat.' },
        { '/vl reload', 'Reloads settings from disk.' },
        { '/vl reset', 'Resets settings to their defaults.' },
        { '/vl help', 'Displays this help information.' },
    };

    cmds:ieach(function (v)
        print(chat.header(addon.name):append(chat.error('Usage: ')):append(chat.message(v[1]):append(' - ')):append(chat.color1(6, v[2])));
    end);
end

--[[
* Prints a quick World Info summary to chat.
--]]
local function print_world()
    local w = timers.settings.world;
    if (not w.enabled[1]) then
        print(chat.header(addon.name):append(chat.error('World Info is disabled. Enable it in /vl config.')));
        return;
    end

    local ok, info = pcall(world.overview, w);
    if (not ok) then
        print(chat.header(addon.name):append(chat.error('Could not compute World Info right now.')));
        return;
    end

    print(chat.header(addon.name):append(chat.message('Active RSE: ')):append(chat.success(('%s @ %s'):fmt(info.active_rse.race_name, info.active_rse.location))):append(chat.message(' (' .. vanadiel.format_countdown(info.active_rse.ends_in_seconds) .. ' left)')));

    local next_pop = info.race_schedule[1];
    if (next_pop ~= nil) then
        local race_name = vanadiel.RSE_RACES[info.race_index + 1];
        print(chat.header(addon.name):append(chat.message(('Next for %s: '):fmt(race_name))):append(chat.success(next_pop.location)):append(chat.message(' - ' .. os.date('%b %d, %H:%M', next_pop.starts))));
    end
end

-- One message-builder per reminder "kind" (core/world.lua's check_alerts() event.kind values).
-- Each receives the event (with .seconds and .extra) and returns the chat line's text.
local REMINDER_MESSAGES = {
    rse_approach = function (e)
        return ('Your race\'s RSE pop is coming up in %s at %s.'):fmt(vanadiel.format_countdown(e.seconds), e.extra.location);
    end,
    rse_active = function (e)
        return ('Your race\'s RSE is active now at %s! (%s left)'):fmt(e.extra.location, vanadiel.format_countdown(e.seconds));
    end,
    day_approach = function (e)
        return ('The Vana\'diel day is about to change in %s -- %s (%s) coming up.'):fmt(vanadiel.format_countdown(e.seconds), e.extra.day_name, e.extra.weak_element);
    end,
    day_active = function (e)
        return ('It\'s now %s -- weak element: %s. (%s left today)'):fmt(e.extra.day_name, e.extra.weak_element, vanadiel.format_countdown(e.seconds));
    end,
    new_moon_approach = function (e)
        return ('New Moon approaching in %s -- fish bite rate drops to ~7s during this phase.'):fmt(vanadiel.format_countdown(e.seconds));
    end,
    new_moon_active = function (e)
        return ('New Moon is active! Fish bite rate: ~7s. (%s left)'):fmt(vanadiel.format_countdown(e.seconds));
    end,
    full_moon_approach = function (e)
        return ('Full Moon approaching in %s -- fish bite rate drops to ~7s during this phase.'):fmt(vanadiel.format_countdown(e.seconds));
    end,
    full_moon_active = function (e)
        return ('Full Moon is active! Fish bite rate: ~7s. (%s left)'):fmt(vanadiel.format_countdown(e.seconds));
    end,
    guild_points_approach = function (e)
        return ('Daily Guild Point turn-in for %s resets in %s.'):fmt(e.extra.guild_name, vanadiel.format_countdown(e.seconds));
    end,
    guild_points_active = function (e)
        return ('Daily Guild Point turn-in for %s is open! (%s left today)'):fmt(e.extra.guild_name, vanadiel.format_countdown(e.seconds));
    end,
    fishing_approach = function (e)
        return ('Daily Fishing goal resets in %s.'):fmt(vanadiel.format_countdown(e.seconds));
    end,
    fishing_active = function (e)
        return ('Daily Fishing goal (200 catches) is active! (%s left today)'):fmt(vanadiel.format_countdown(e.seconds));
    end,
};

--[[
* Prints any newly-triggered reminders to chat and, if the category has a sound assigned,
* plays it locally (never sent to party chat or anyone else).
--]]
local function print_reminder_alerts()
    local ok, events = pcall(world.check_alerts, timers.settings);
    if (not ok) then
        return;
    end

    for x = 1, #events do
        local event = events[x];
        local build_message = REMINDER_MESSAGES[event.kind];
        if (build_message ~= nil) then
            print(chat.header(addon.name):append(chat.success('Reminder: ')):append(chat.message(build_message(event))));
        end
        if (event.sound ~= nil and event.sound ~= '') then
            pcall(sound.play, event.sound, timers.settings.style.sound_volume[1]);
        end
    end
end

--[[
* Prints any Notes whose "remind me" countdown just elapsed, and plays that note's chosen sound
* locally (if any) -- never sent to party chat or anyone else.
--]]
local function print_note_reminders()
    local ok, fired = pcall(timers.check_note_reminders);
    if (not ok) then
        return;
    end

    for x = 1, #fired do
        local entry = fired[x];
        print(chat.header(addon.name):append(chat.success('Reminder: ')):append(chat.message(entry.name)));
        if (entry.sound ~= nil and entry.sound ~= '') then
            pcall(sound.play, entry.sound, timers.settings.style.sound_volume[1]);
        end
    end
end

--[[
* event: load
--]]
ashita.events.register('load', 'load_cb', function ()
    print(chat.header(addon.name):append(chat.message('Loaded. Type ')):append(chat.success('/vl help')):append(chat.message(' for a list of commands.')));
end);

--[[
* event: unload
--]]
ashita.events.register('unload', 'unload_cb', function ()
    timers.save();
end);

--[[
* event: d3d_present
--]]
ashita.events.register('d3d_present', 'present_cb', function ()
    overlay.render();
    settings_window.render();
    pcall(world.sync_linked_notes, timers.settings);
    print_reminder_alerts();
    print_note_reminders();
end);

--[[
* event: command
--]]
ashita.events.register('command', 'command_cb', function (e)
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/vl', '/vanalog')) then
        return;
    end

    e.blocked = true;

    -- Handle: /vl - Toggles the overlay.
    if (#args == 1) then
        overlay.toggle();
        return;
    end

    -- Handle: /vl help
    if (args[2]:any('help')) then
        print_help(false);
        return;
    end

    -- Handle: /vl config - Toggles the settings/editor window.
    if (args[2]:any('config', 'cfg', 'editor')) then
        settings_window.toggle();
        return;
    end

    -- Handle: /vl lock - Toggles locking the overlay.
    if (args[2]:any('lock', 'unlock')) then
        overlay.toggle_lock();
        return;
    end

    -- Handle: /vl world - Prints World Info to chat.
    if (args[2]:any('world', 'rse')) then
        print_world();
        return;
    end

    -- Handle: /vl reload - Reloads settings from disk.
    if (args[2]:any('reload', 'rl')) then
        timers.reload();
        print(chat.header(addon.name):append(chat.message('Settings reloaded from disk.')));
        return;
    end

    -- Handle: /vl reset - Resets settings to defaults.
    if (args[2]:any('reset')) then
        timers.reset();
        print(chat.header(addon.name):append(chat.message('Settings reset to defaults.')));
        return;
    end

    -- Handle: /vl clear - Removes all timers/notes.
    if (args[2]:any('clear')) then
        timers.clear_all();
        print(chat.header(addon.name):append(chat.message('All timers and notes removed.')));
        return;
    end

    -- Handle: /vl del <name> - Removes a timer/note by name.
    if (args[2]:any('del', 'delete', 'remove', 'rem') and #args >= 3) then
        local name = args:concat(' ', 3);
        local entry = timers.find_by_name(name);
        if (entry == nil) then
            print(chat.header(addon.name):append(chat.error('No timer or note found with that name.')));
            return;
        end
        timers.remove_timer(entry.id);
        print(chat.header(addon.name):append(chat.message('Removed: ')):append(chat.success(entry.name)));
        return;
    end

    -- Handle: /vl note <name> [notes...] - Adds a pinned note.
    if (args[2]:any('note') and #args >= 3) then
        local name = args[3];
        local notes = #args >= 4 and args:concat(' ', 4) or '';
        timers.add_timer(T{ name = name, notes = notes, mode = 'note' });
        print(chat.header(addon.name):append(chat.message('Added note: ')):append(chat.success(name)));
        return;
    end

    -- Handle: /vl add <name> <duration> [notes...] - Adds a countdown timer.
    if (args[2]:any('add') and #args >= 4) then
        local name = args[3];
        local duration = timers.parse_duration(args[4]);

        if (duration == nil or duration <= 0) then
            print(chat.header(addon.name):append(chat.error('Invalid duration. Use hh:mm:ss, mm:ss, or seconds.')));
            return;
        end

        local notes = #args >= 5 and args:concat(' ', 5) or '';
        timers.add_timer(T{ name = name, notes = notes, mode = 'timer', duration = duration });
        print(chat.header(addon.name):append(chat.message('Added timer: ')):append(chat.success(name)):append(chat.message(' (' .. timers.format_time(duration) .. ')')));
        return;
    end

    print_help(true);
end);
