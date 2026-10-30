--[[
* vanalog - Color presets for the overlay and settings window.
*
* A small role-based palette (background / card / control / border / text / heading / muted /
* accent / success / warn / danger), the same shape used by the other Phoenix addons, so
* picking a preset reskins the whole window in one go. The default 'phoenix' preset matches
* phoenix-xi.com's own red/gold branding.
--]]

require 'common';

local imgui = require 'imgui';

local theme = { };

-- Turns 'c55151' into an { r, g, b, a } ImGui color table.
local function hex(value, alpha)
    return {
        tonumber(value:sub(1, 2), 16) / 255,
        tonumber(value:sub(3, 4), 16) / 255,
        tonumber(value:sub(5, 6), 16) / 255,
        alpha or 1.0,
    };
end
theme.hex = hex;

theme.PRESETS = T{
    { id = 'phoenix', name = 'Phoenix' },
    { id = 'classic', name = 'Classic FFXI' },
    { id = 'minimal', name = 'Minimal' },
    { id = 'contrast', name = 'High Contrast' },
    { id = 'ember', name = 'Ember' },
    { id = 'mint', name = 'Mint' },
    { id = 'lavender', name = 'Lavender' },
    { id = 'colorblind', name = 'Colorblind Safe' },
};

theme.PALETTES = T{
    phoenix = {
        background = hex('180e0e', 0.90), card = hex('291c1c'), control = hex('321f1f'),
        hover      = hex('3a2525'),       border = hex('d2abab', 0.30), text = hex('fff8f8'),
        heading    = hex('d2abab'),       muted = hex('8a6b6b'), accent = hex('c55151'),
        success    = hex('63ba8a'),       warn = hex('f5c850'), danger = hex('ff8d79'),
        rounding   = 0,
    },
    classic = {
        background = hex('0b1a3d', 0.88), card = hex('13275a'), control = hex('1b3470'),
        hover      = hex('27468c'),        border = hex('8ea3d6', 0.55), text = hex('ffffff'),
        heading    = hex('f2e6c4'),        muted = hex('9fb0d8'), accent = hex('e8c86a'),
        success    = hex('7ee08a'),        warn = hex('ffd666'), danger = hex('ff8d79'),
        rounding   = 4,
    },
    minimal = {
        background = hex('1e1e1e', 0.90), card = hex('2a2a2a'), control = hex('333333'),
        hover      = hex('404040'),        border = hex('ffffff', 0.15), text = hex('f2f2f2'),
        heading    = hex('cfcfcf'),        muted = hex('8c8c8c'), accent = hex('d0d0d0'),
        success    = hex('9be3b5'),        warn = hex('e8d27a'), danger = hex('e08a8a'),
        rounding   = 3,
    },
    contrast = {
        background = hex('000000', 0.95), card = hex('141414'), control = hex('262626'),
        hover      = hex('3d3d3d'),        border = hex('ffffff', 0.70), text = hex('ffffff'),
        heading    = hex('ffe066'),        muted = hex('c8c8c8'), accent = hex('ffd000'),
        success    = hex('39ff14'),        warn = hex('ffe066'), danger = hex('ff4040'),
        rounding   = 0,
    },
    ember = {
        background = hex('1a120c', 0.90), card = hex('2a1d12'), control = hex('3a2716'),
        hover      = hex('4a321c'),        border = hex('ffb070', 0.25), text = hex('fff4e8'),
        heading    = hex('ffc38a'),        muted = hex('a07c5c'), accent = hex('e8742a'),
        success    = hex('8fcf6a'),        warn = hex('ffc85a'), danger = hex('ff6a4d'),
        rounding   = 2,
    },
    mint = {
        background = hex('101f1b', 0.90), card = hex('192f29'), control = hex('233d34'),
        hover      = hex('2e5446'),        border = hex('8fe3ba', 0.35), text = hex('edf9f1'),
        heading    = hex('b1ebd0'),        muted = hex('9bbbad'), accent = hex('74d9ad'),
        success    = hex('8fe3b7'),        warn = hex('e8d27a'), danger = hex('ff8d79'),
        rounding   = 4,
    },
    lavender = {
        background = hex('191523', 0.90), card = hex('262033'), control = hex('342b45'),
        hover      = hex('463858'),        border = hex('cdb1f4', 0.35), text = hex('f3ecff'),
        heading    = hex('deccf7'),        muted = hex('b5a5c9'), accent = hex('c3a0ed'),
        success    = hex('a8d9c0'),        warn = hex('e8c86a'), danger = hex('ff8d79'),
        rounding   = 4,
    },
    -- Okabe and Ito colorblind-safe palette: blue stands in for accent/success, orange for danger.
    colorblind = {
        background = hex('101418', 0.90), card = hex('1b2129'), control = hex('252d37'),
        hover      = hex('313b47'),        border = hex('56b4e9', 0.30), text = hex('f2f2f2'),
        heading    = hex('9fd3f5'),        muted = hex('8f9aa6'), accent = hex('56b4e9'),
        success    = hex('56b4e9'),        warn = hex('e69f00'), danger = hex('e69f00'),
        rounding   = 2,
    },
};

--[[
* Returns the full overlay color set (bg/border/text/header/notes/warn/finished) derived from
* a palette preset, in the same shape vanalog's style settings already use. Used by the
* Appearance tab's "Apply Preset" button to seed the individually-editable colors.
--]]
function theme.overlay_colors(preset_id)
    local p = theme.PALETTES[preset_id] or theme.PALETTES.phoenix;
    return T{
        bg_color       = { p.background[1], p.background[2], p.background[3] },
        bg_opacity     = p.background[4],
        border_color   = { p.border[1], p.border[2], p.border[3] },
        border_opacity = p.border[4],
        text_color     = p.text,
        header_color   = p.heading,
        notes_color    = p.muted,
        warn_color     = p.warn,
        finished_color = p.danger,
    };
end

-- The settings-window ImGui colors this theme controls, and the role each pulls from.
local WINDOW_COLOR_MAP = T{
    { role = 'background', paints = ImGuiCol_WindowBg },
    -- Same role as WindowBg, not 'card': without this, every BeginChild region (the Timers &
    -- Notes and Appearance tabs' panes) falls back to ImGui's own default ChildBg instead of the
    -- preset, showing as a flat grey box instead of blending into the rest of the window the
    -- way the tabs that don't use a child (Journal, World Info, Reminders, About) already do.
    { role = 'background', paints = ImGuiCol_ChildBg },
    { role = 'card',       paints = ImGuiCol_TitleBgActive, also = ImGuiCol_PopupBg },
    { role = 'card',       paints = ImGuiCol_TitleBg },
    { role = 'border',     paints = ImGuiCol_Border },
    { role = 'border',     paints = ImGuiCol_Separator },
    { role = 'text',       paints = ImGuiCol_Text },
    { role = 'control',    paints = ImGuiCol_FrameBg },
    { role = 'hover',      paints = ImGuiCol_FrameBgHovered },
    -- Not 'accent': ImGuiCol_FrameBgActive is the *track* background behind a slider while
    -- it's being dragged (also an input box while typing, etc.) -- using the loud accent color
    -- here fills the whole track solid, drowning out the grab knob (itself accent-colored) so
    -- dragging looks like one solid bar instead of a knob sliding along a track. 'hover' keeps
    -- the track subtle while dragging, same as while merely hovered, so only the knob stands out.
    { role = 'hover',      paints = ImGuiCol_FrameBgActive },
    { role = 'control',    paints = ImGuiCol_Button },
    { role = 'hover',      paints = ImGuiCol_ButtonHovered },
    { role = 'accent',     paints = ImGuiCol_ButtonActive },
    { role = 'accent',     paints = ImGuiCol_CheckMark },
    { role = 'accent',     paints = ImGuiCol_SliderGrab },
    { role = 'accent',     paints = ImGuiCol_SliderGrabActive },
    { role = 'card',       paints = ImGuiCol_Tab },
    { role = 'hover',      paints = ImGuiCol_TabHovered },
    -- The active tab: a soft accent tint behind it (not a solid fill, so it won't clash with
    -- any palette's accent hue) plus a crisp accent line under it -- ImGui's own modern pattern
    -- for marking the current tab, used tastefully rather than a loud full-accent background.
    { role = 'accent',     paints = ImGuiCol_TabSelected, alpha = 0.40 },
    { role = 'accent',     paints = ImGuiCol_TabSelectedOverline },
    { role = 'card',       paints = ImGuiCol_Header },
    { role = 'hover',      paints = ImGuiCol_HeaderHovered },
    { role = 'accent',     paints = ImGuiCol_HeaderActive },
    { role = 'control',    paints = ImGuiCol_ScrollbarBg },
    { role = 'hover',      paints = ImGuiCol_ScrollbarGrab },
    { role = 'accent',     paints = ImGuiCol_ScrollbarGrabActive },
    -- The resize grip in the bottom-right corner: ImGui's default is a faint gray that's easy
    -- to miss entirely. Make it loud -- accent normally, warn on hover, danger while dragging --
    -- so both the overlay and settings window have an obvious resize handle.
    { role = 'accent',     paints = ImGuiCol_ResizeGrip },
    { role = 'warn',       paints = ImGuiCol_ResizeGripHovered },
    { role = 'danger',     paints = ImGuiCol_ResizeGripActive },
};

--[[
* Pushes the settings window's ImGui colors and corner rounding for the given preset.
* Always pair with theme.pop_window_style() using the returned counts.
*
* @param {string} preset_id - One of theme.PRESETS' ids.
* @return {number, number} color push count, style-var push count.
--]]
function theme.push_window_style(preset_id)
    local p = theme.PALETTES[preset_id] or theme.PALETTES.phoenix;

    local colors = 0;
    for x = 1, #WINDOW_COLOR_MAP do
        local entry = WINDOW_COLOR_MAP[x];
        local color = p[entry.role];
        if (entry.alpha ~= nil) then
            color = { color[1], color[2], color[3], color[4] * entry.alpha };
        end
        imgui.PushStyleColor(entry.paints, color);
        colors = colors + 1;
        if (entry.also ~= nil) then
            imgui.PushStyleColor(entry.also, color);
            colors = colors + 1;
        end
    end

    local ROUNDED = T{
        ImGuiStyleVar_WindowRounding, ImGuiStyleVar_ChildRounding, ImGuiStyleVar_FrameRounding,
        ImGuiStyleVar_PopupRounding, ImGuiStyleVar_GrabRounding, ImGuiStyleVar_TabRounding,
        ImGuiStyleVar_ScrollbarRounding,
    };
    for x = 1, #ROUNDED do
        imgui.PushStyleVar(ROUNDED[x], p.rounding);
    end

    return colors, #ROUNDED;
end

function theme.pop_window_style(color_count, var_count)
    imgui.PopStyleVar(var_count);
    imgui.PopStyleColor(color_count);
end

return theme;
