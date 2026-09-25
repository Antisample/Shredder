# Antisample Shredder

A random-cut-and-reshuffle glitch tool for REAPER. Chops selected item(s) into
segments using any of eleven Cut Modes, reshuffles them, randomizes per-segment
pitch/pan/volume/rate/reverse, and either leaves the cut pieces grouped and
selected for further editing (the default) or glues the result into a single
rendered item.

For version history, see
[CHANGELOG.md](https://github.com/Antisample/Shredder/blob/main/Script/CHANGELOG.md).

## Requirements

- REAPER
- [ReaImGui](https://github.com/cfillion/reaimgui) (install via
  `Extensions > ReaPack > Browse packages`, under ReaTeam Extensions, if you
  don't already have it)

## Installation

**Via ReaPack** (recommended):

1. In REAPER, go to `Extensions > ReaPack > Import repositories...`
2. Paste this URL and click OK:

   ```
   https://github.com/Antisample/Shredder/raw/main/index.xml
   ```

3. Open `Extensions > ReaPack > Browse packages`, search for "Antisample
   Shredder", and install it.

Updates then arrive through ReaPack like any other package
(`Extensions > ReaPack > Synchronize packages`).

**Manually**: copy `Antisample_Shredder_UI.lua`, `Antisample_Shredder_Engine.lua`,
and the `Presets/` folder into the same directory under REAPER's
`Scripts` folder, then load `Antisample_Shredder_UI.lua` as a new action
(`Actions List > New Action > Load ReaScript...`).

Either way, only run/bind `Antisample_Shredder_UI.lua` - the Engine file is a
dependency the UI launches itself; it isn't meant to be run directly.

## Quick start

1. Select one or more media items.
2. Open the Shredder tab and pick a Cut Mode.
3. Adjust Structural Modes and Chunk Randomization to taste - or just hit
   **Random** to roll fresh per-segment values.
4. Hit **Run Shredder**.

By default, Run Shredder does **not** render anything - it cuts, shuffles, and
randomizes exactly as configured, then leaves the resulting segments grouped
and selected, with the edit cursor at the start, so you can keep editing
before committing to anything. Turn this off in Settings (Shredder
Behaviour > Cut but don't render) if you'd rather it glue straight into one
item.

## Features

### Cut Modes

Three groups, one mode active at a time:

- **Classic** - By Cut Length, By Number of Cuts, Beat-Synced (tempo divisions
  with humanize), Euclidean/rhythmic distribution, Transient detection.
- **Sequence** - Fibonacci/Lucas/Padovan/Tribonacci/Custom weighted cuts.
- **Bizarre** - Blackhole (geometric decay, with a Loop and White Hole/reverse-
  trend option), Pitagora (Pythagorean-triple ratios), Collatz (the "3n+1"
  sequence as segment-length weights), Cantor Dust (fractal gaps), Morse Code
  (cuts encode a text message's actual dots/dashes).

By Cut Length and By Number of Cuts both randomize their target by default (an
organic, non-mechanical feel) - flip **Cut Variance** to Fixed (Settings >
Shredder Behaviour) for exact segment sizes / exact cut counts instead.

### Structural Modes

- **Shuffle Mode** - Full, Local (windowed), Weighted (amount dial), or None.
- **Palindrome** - plays the final order forward, then backward.
- **Ordered-Subset Mode** - keeps segments with some probability, drops
  (deletes, not mutes) the rest, always in original order - a shorter, gated
  result rather than a shuffled one.
- **Ignore Silence** - filters out segments that are effectively silent.

### Per-Segment Randomization

Position, Rate, Pitch, Pan, Volume, Stretch, Reverse, Repeats, and Mute, each
independently controlled - no master gate, every slider does its own thing at
its own amount. **Stretch** lengthens or shortens each chunk by up to 1000%
while keeping its pitch. Position, Pitch, Pan, Volume, and Stretch additionally support
**Direction** (both/negative-only/positive-only). **Scatter Repeats** spreads
repeat-duplicate copies throughout the result instead of clustering them right
after their source. **Init** resets every sound-affecting setting in the tab
to default; **Random** rerolls just this section (which sliders it's allowed
to touch is configurable under Settings > Randomization Settings).

### Multiple items

Mash Together (every selected item's segments pooled, shuffled, and glued/
grouped as one combined result) or Process Individually (each item shredded
on its own, staying separate).

### Presets

Save, load, or load-a-random-saved-preset from the bar at the top of the
Shredder tab. Presets capture every sound-affecting setting (Cut Mode and its
parameters, Structural Modes, Per-Segment Randomization, Multi-item mode) -
not layout/appearance preferences, which are per-install instead. A **\***
next to the preset name shows when you've changed something since loading it.
A set of starter presets (including `_Init`) ships in `Presets/`.

### Settings tab

- **Appearance** - Color Palette, Font and Font Color (including font size),
  and Layout (which end of the tab Run Shredder pins to, and Compact Mode for
  narrow docks).
- **Shredder Behaviour** - Cut Variance, Take Pitch Shift / Time Stretch Mode
  (one mode for every chunk, or a random pick per chunk), Cut but don't
  render, and Hide Helper Text.
- **Randomization Settings** - which Per-Segment properties the Random button
  is allowed to reroll.
- **Render Settings** - naming pattern for the glued result (when Cut but
  don't render is off), with `{name}`/`{number}`/`{mode}`/`{date}`/`{time}`
  wildcards and a live preview.
