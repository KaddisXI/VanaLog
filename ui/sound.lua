--[[
* vanalog - Optional sound alert when a timer finishes or a reminder fires.
*
* Plays a .wav/.mp3 file via the Windows MCI API (winmm.dll), the standard way to
* fire-and-forget play a short sound from Lua on Windows without bundling any audio library.
* Every call is pcall-guarded: a bad/missing file just silently fails to play rather than
* erroring out the addon.
*
* Two folders are searched: BUILT_IN (shipped with the addon -- the 22 in-game "call" sound
* effects, converted from the game's own se000017.spw-se000038.spw via vgmstream, since those
* are a proprietary Square Enix container format Windows can't play directly) and FOLDER (your
* own config folder, for anything you add yourself). A name in both is the user's copy.
--]]

require 'common';

local ffi = require('ffi');

local sound = { };

sound.BUILT_IN = addon.path:gsub('[\\/]+$', '') .. '\\sounds\\';
sound.FOLDER = AshitaCore:GetInstallPath() .. '\\config\\addons\\' .. addon.name .. '\\sounds\\';

local loaded, winmm;
local alias = 'vanalog_alert';
local opened = nil;

pcall(ffi.cdef, 'unsigned long __stdcall mciSendStringA(const char *command, char *answer, unsigned int size, void *window);');

local function mci(command)
    if (loaded == nil) then
        loaded, winmm = pcall(ffi.load, 'winmm');
    end
    if (not loaded) then
        return false;
    end
    local ok, result = pcall(winmm.mciSendStringA, command, nil, 0, nil);
    return ok and result == 0;
end

local function valid(name)
    if (type(name) ~= 'string' or name == '' or #name > 200) then
        return false;
    end
    if (name:find('[%c"\\/:]') ~= nil or name:find('..', 1, true) ~= nil) then
        return false;
    end
    local lower = name:lower();
    return lower:match('%.wav$') ~= nil or lower:match('%.mp3$') ~= nil;
end

function sound.ensure_folder()
    if (not ashita.fs.exists(sound.FOLDER)) then
        pcall(ashita.fs.create_dir, sound.FOLDER);
    end
end

--[[
* Plays a sound file by name. Looks in the user's config folder first, then the addon's
* built-in folder.
*
* @param {string} name - The file name, e.g. 'alert.wav' or 'call17.wav'.
* @param {number} volume - 0-100.
* @return {boolean} True if playback was started.
--]]
function sound.play(name, volume)
    if (not valid(name)) then
        return false;
    end

    local path = sound.FOLDER .. name;
    if (not ashita.fs.exists(path)) then
        path = sound.BUILT_IN .. name;
        if (not ashita.fs.exists(path)) then
            return false;
        end
    end

    mci('close ' .. alias);
    if (not mci(('open "%s" type mpegvideo alias %s'):format(path, alias))) then
        return false;
    end
    opened = name;

    volume = math.floor(math.max(0, math.min(100, tonumber(volume) or 100)) * 10 + 0.5);
    mci(('setaudio %s volume to %d'):format(alias, volume));

    return mci('play ' .. alias .. ' from 0');
end

--[[
* Lists every valid sound file available (built-in call sounds plus anything in the user's
* own config folder), alphabetically, with duplicates (by name) kept only once.
--]]
function sound.list_files()
    sound.ensure_folder();

    local files = T{ };
    local seen = { };

    for _, folder in ipairs({ sound.BUILT_IN, sound.FOLDER }) do
        local ok, entries = pcall(ashita.fs.get_directory, folder, '.*', false);
        if (ok and entries ~= nil) then
            for x = 1, #entries do
                local name = entries[x];
                if (valid(name) and not seen[name:lower()]) then
                    seen[name:lower()] = true;
                    files:insert(#files + 1, name);
                end
            end
        end
    end

    table.sort(files, function (a, b) return a:lower() < b:lower(); end);

    return files;
end

return sound;
