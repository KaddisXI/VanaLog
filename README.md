# VanaLog

A scalable Ashita v4 overlay for creating your own timers and notes, with
adjustable background color, opacity/transparency, border, text size, and
text color -- plus a built-in **World Info** tracker that shows the active
Race Specific Equipment (RSE) event, your race's upcoming RSE schedule, a
forward-looking day/weekly calendar, and moon phase.

World Info is computed entirely locally, from the real-world clock. It does
**not** contact phoenix-xi.com, any wiki, or any other server at runtime --
see [Credits](#credits) below.

(Formerly "timernotes" -- renamed to VanaLog now that it covers more than
just timers and notes.)

## Installation

1. Copy the `vanalog` folder into your Ashita `addons` folder, so you end
   up with `Ashita\addons\vanalog\vanalog.lua`.
2. In-game (or in your Ashita `scripts\default.txt` autoload list), run:
   ```
   /addon load vanalog
   ```
3. Run `/vl config` to open the settings window and add your first timer or
   note, or check the World Info tab.

Settings are saved per-character automatically under:
`Ashita\config\addons\vanalog\<CharacterName>_<ServerId>\settings.lua`

## Commands

| Command | What it does |
|---|---|
| `/vl` | Toggles the timers/notes overlay on and off. |
| `/vl config` | Opens/closes the settings & editor window. |
| `/vl add <name> <duration> [notes...]` | Quick-adds a countdown timer. Duration accepts `hh:mm:ss`, `mm:ss`, or plain seconds (e.g. `/vl add "Sky God" 45:00 kill the placeholder`). |
| `/vl note <name> [notes...]` | Quick-adds a pinned note with no countdown. |
| `/vl del <name>` | Removes the timer/note with the given name. |
| `/vl clear` | Removes all timers and notes. |
| `/vl lock` | Toggles locking the overlay in place (hides the edit buttons and freezes position/size for a clean HUD look). |
| `/vl world` | Prints the currently active RSE pop and your race's next upcoming RSE pop to chat. |
| `/vl reload` | Reloads settings from disk, discarding unsaved changes. |
| `/vl reset` | Resets all settings back to their defaults. |
| `/vl help` | Prints this command list to the chat log in-game. |

`/vanalog` works as a longhand alias everywhere `/vl` does.

You can also right-click the overlay itself for a quick menu (add entry,
lock/unlock, open settings, clear all).

## Using the overlay

- **Timers** count down from a set duration. They can optionally repeat,
  auto-restarting as soon as they hit zero -- handy for recasts or pop timers.
- **Notes** are just a pinned name + note text with no countdown, for things
  you want to remember (strategy reminders, macros, etc.).
- Each entry has a **category** (General, Recast, Pop/Spawn, Buff/Food, Craft,
  Event) that tints its name and tag in the overlay, purely for organization.
- Each entry can have multi-line notes attached, shown wrapped underneath it
  in the overlay.
- While unlocked, each entry shows **Pause/Resume**, **Restart**, **Edit**,
  and **Delete** buttons. Lock the overlay (`/vl lock` or the right-click
  menu) to hide these and get a clean display.
- The overlay window itself is a normal draggable/resizable window when
  unlocked -- drag the title bar to move it, drag a corner/edge to resize it.
- The overlay has four tabs -- **Timers**, **Notes**, **World** (a compact
  view of active RSE, your race's next few pops, upcoming elemental day of the week, and
  moon phase), and **Reminders** (a live countdown for whichever reminders
  you've turned on) -- so you can flip between them without opening the full
  settings window. World and Reminders are hidden if World Info is disabled.
  Drag a tab to reorder it.
- Optionally pin the **active RSE** as a line above the tabs regardless of
  which tab is open (World Info tab in settings -> "Show active RSE in
  overlay").
- Optionally play a sound and/or flash when a timer finishes (Appearance tab).
- The overlay fully follows your chosen theme preset -- not just its
  background/border/text, but button, tab, and header colors too.
- A small cogwheel button sits in the top-right corner of the overlay at all
  times (click to open the settings window) -- useful since locking the
  overlay hides its title bar entirely. It's colored from your active theme
  preset's accent, so it always matches whatever look you've picked.
- The overlay can be collapsed to just its title bar, the same as the
  settings window -- click the arrow next to the title.
- The bottom-right resize handle on both the overlay and settings window is
  colored with your theme's accent (and lights up on hover/drag), instead of
  ImGui's barely-visible default gray.

## World Info (`/vl config` -> World Info tab)

A pure display tab -- each section below is its own collapsible header, so
you can fold away what you don't care about. Alert/reminder setup lives in
the separate **Reminders** tab, not here.

- **Vana'diel Clock** -- current date/time and elemental day of the week.
- **Moon Phase** -- current phase and percent, a countdown to the next New
  Moon and next Full Moon (or "active, ends in..." if one is in progress),
  and a forward calendar of upcoming New/Full Moon windows. Moon phase
  matters in-game for certain fish bites and gardening crop quality -- fish
  bite rates in particular drop to ~7s (from the default ~15s) during either
  phase.
- **Active RSE Now** -- which race's camp is currently spawning, where, how
  long until the rotation moves on, and the key-item droppers for that camp
  (wrapped to fit the window instead of running off the edge).
- **Your race's upcoming RSE** -- a forward schedule of start/end times and
  locations for a chosen race. Race is auto-detected from your logged-in
  character by default, with a manual override if you'd rather track a
  different race (e.g. an alt, or a friend's).
- **Day Calendar** -- a forward-looking list of upcoming Vana'diel days, each
  elemental day and moon phase, so you can plan accordingly.
- Lists default to 8 lines (4 cycles for the moon calendar) and can be
  expanded (sliders, 3-40 / 1-12).

## Reminders (`/vl config` -> Reminders tab)

Three collapsible sections -- **RSE**, **Day Change**, and **Moon Phase**
(which itself holds independently-configurable New Moon and Full Moon
sub-sections). Each reminder has the same core controls:

- **Enabled** -- turns that category's reminders on.
- **When approaching** / **When active** -- alert as the window is coming up,
  when it starts, or both.
- **Warn this many minutes ahead** -- how early an "approaching" alert fires
  (1-60 minutes).
- **Sound** -- optional, per reminder. "(none)" or any sound file, picked
  from a combined list of 22 bundled in-game "call" sound effects (converted
  from the game's own `se000017.spw`-`se000038.spw`, since those are a
  proprietary format Windows can't play directly) plus anything you drop into
  `Ashita\config\addons\vanalog\sounds\` yourself. A **Test** button plays
  whichever is selected. Playback is always local only -- a reminder never
  sends a chat message to your party or anyone else, regardless of what sound
  you pick.

Day Change reminders additionally let you pick **which Vana'diel days** to
alert for (all 8 by default, with "All"/"None" shortcuts) -- useful if you
only care about one or two specific days rather than every day change.

Each reminder prints one chat line as it fires (not spammed every frame for
however long the window stays open), and the overlay's **Reminders** tab
shows a live countdown for everything you've turned on.

RSE reminders track your own race's next pop (same race setting as the World
Info tab).

## Appearance settings (`/vl config` -> Appearance tab, first tab in the window)

Each section below (General, Background, Border, Text, Alerts) is its own
collapsible header. The tab you're currently on, in any tab bar in the
addon, is marked with an accent-colored underline so it's easy to tell at a
glance -- without a solid block of color that could clash with some presets.

- **Show Overlay / Lock Overlay** -- visibility and lock toggles (same as the
  `/vl` and `/vl lock` commands).
- **Theme Preset** -- Phoenix (default, matches phoenix-xi.com's own
  branding), Classic FFXI, Minimal, High Contrast, Ember, Mint, Lavender, and
  a colorblind-safe preset. Picking one from the dropdown immediately reskins
  both the overlay and this window and seeds the individual colors below with
  that preset; you can still fine-tune any of them afterward, and "Re-apply
  Preset Colors" snaps them all back to the preset if you want a clean reset.
- **Background** -- background color and opacity/transparency.
- **Border** -- show/hide, color, opacity, and thickness (independent of the
  background).
- **Text** -- text color, header/note-title color, notes color, warning
  color, and finished color (used for countdown states), plus a text size
  slider.
- **Alerts** -- the "Warn Threshold" slider controls how many seconds remain
  before a countdown switches to the warning color; you can also enable a
  finish flash and/or a sound alert (drop `.wav`/`.mp3` files into
  `Ashita\config\addons\vanalog\sounds\`).

Use **Save Settings**, **Reload Settings**, or **Reset To Defaults** at the
bottom of the Appearance tab to manage your configuration.

## Notes for testers

- This addon has no dependencies beyond what ships with Ashita v4.
- There is no custom font-family picker ("Text Type") -- an earlier build
  tried loading extra `.ttf` files into ImGui at runtime and this caused a
  crash (`EXCEPTION_ACCESS_VIOLATION` in the Present event) on at least one
  system. Text size is still fully adjustable via the "Text Size" slider,
  just not the font family.
- v2.0 fixed a crash that could happen when deleting a timer/note from the
  overlay: the delete button used to remove the entry from the list while
  that same list was still being iterated over for rendering, which could
  walk past the (now shorter) list and crash. Deletes are now deferred until
  after the render pass completes.
- If something looks wrong after an update, try `/vl reset` to rule out a
  stale settings file, or delete the character-specific settings file listed
  above and let it regenerate.
- Feedback/bug reports: describe what you did, what you expected, and what
  happened instead (a screenshot of the overlay/settings window helps a lot).

## Credits

Created by Kaddis.

RSE rotation, moon phase, and the Vana'diel day/element calendar are computed
using the public timing formulas published by **Pyogenes** at
<https://www.pyogenes.com/ffxi/timer/v2.html> (`timer4.js`), ported to Lua in
`core/vanadiel.lua`. That script's own license terms ask only that credit be
given and a link be placed on any page the code is used in -- this section,
and the addon's in-game About tab, are that credit and link. No network
request is made to that site (or anywhere else) by this addon; the formulas
run entirely offline against the local clock.

Theme presets and settings-window design patterns were inspired by two other
Ashita addons for this server, **Cadence** and **Momentum**, both by
**Kipling**. No code was copied from either; VanaLog's theme and UI code is
its own, written in the same spirit.

The 22 bundled "call" sound options (`sounds/call17.wav`-`call38.wav`) are
the game's own `se000017.spw`-`se000038.spw` sound effects, converted to
`.wav` with [vgmstream](https://github.com/vgmstream/vgmstream), an
open-source game-audio tool, since the game's own `.spw` container isn't
something Windows can play directly. Nothing about this reads or writes your
actual game files at runtime; the conversion was a one-time, offline step.
