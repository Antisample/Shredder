-- @description Antisample Shredder
-- @version 1.49
-- @author Zdravko Djordjević
-- @provides
--   Antisample_Shredder_Engine.lua
--   Presets/*.txt
--   CHANGELOG.md
--   README.md
-- @about
--   # Antisample Shredder
--
--   A glitch/stutter tool: chops selected item(s) into randomized
--   segments using any of 11 Cut Modes (Euclidean rhythms, Fibonacci-
--   style sequences, Collatz chaos, Cantor Dust fractals, Morse code,
--   and more), reshuffles them, randomizes per-segment pitch/pan/
--   volume/rate/reverse, and either glues the result into one item or
--   (the default) leaves the cut pieces grouped and selected for
--   further manual editing. Includes a preset system, three starter
--   presets, and a live preview of exactly what a run will produce
--   before you commit to it.
--
--   Requires the ReaImGui extension - install it first via
--   Extensions > ReaPack > Browse packages, under ReaTeam Extensions.
--
--   See README.md for full usage details and CHANGELOG.md for version
--   history.
-- @changelog
--   - Removed extra padding and separator above Run Shredder
--   - Added Run Shredder button color selection (Settings > Appearance)
--   - Fixed button color picker showing wrong colors

--[[
     Antisample Shredder UI v1.49
     Requires: ReaImGui (via ReaPack / ReaTeam Extensions)

     Full version history lives in CHANGELOG.md (in the same folder as
     this script).
]]--

------------------------------------------------------------
-- ReaImGui dependency
------------------------------------------------------------

if not reaper.ImGui_CreateContext then
  reaper.ShowMessageBox(
    "ReaImGui is required for this UI.\n\n" ..
    "Install ReaImGui through ReaPack (ReaTeam Extensions), then run this script again.",
    "Antisample Shredder",
    0
  )
  return

end

------------------------------------------------------------
-- Configuration
------------------------------------------------------------

local SCRIPT_DIR = debug.getinfo(1, "S").source:match("@?(.*[/\\])") or ""

local SCRIPT_SHREDDER = SCRIPT_DIR .. "Antisample_Shredder_Engine.lua"

-- Beat-Synced cut mode (V2): division length options, expressed in
-- quarter-note beats (e.g. 0.25 = a 1/16 note). Order here is the
-- order shown in the Beat Division dropdown.
local SHREDDER_BEAT_DIVISIONS = {
  { label = "1/4",          beats = 1 },
  { label = "1/8",          beats = 0.5 },
  { label = "1/16",         beats = 0.25 },
  { label = "1/32",         beats = 0.125 },
  { label = "1/8 Triplet",  beats = 1 / 3 },
  { label = "1/16 Triplet", beats = 1 / 6 },
  { label = "1/4 Dotted",   beats = 1.5 },
  { label = "1/8 Dotted",   beats = 0.75 },
}

local SHREDDER_BEAT_DIVISION_ITEMS = ""
for _, d in ipairs(SHREDDER_BEAT_DIVISIONS) do
  SHREDDER_BEAT_DIVISION_ITEMS = SHREDDER_BEAT_DIVISION_ITEMS .. d.label .. "\0"
end
-- Single trailing \0 (not double) - ReaImGui's Lua->C string marshalling
-- already NUL-terminates the buffer, so an extra manually-appended \0
-- creates a genuine spurious blank entry at the end of the dropdown.

-- Finds the dropdown index (0-based, for ImGui_Combo) whose beats
-- value is closest to `beats` - falls back to 1/16 if nothing is
-- within tolerance (e.g. a value hand-edited into ExtState).
local function find_beat_division_index(beats)
  for i, d in ipairs(SHREDDER_BEAT_DIVISIONS) do
    if math.abs(d.beats - beats) < 0.0001 then return i - 1 end
  end
  return 2 -- fallback: index of "1/16" above
end

-- Scale-Quantized Pitch (V3): root-note and scale-type dropdown data.
local SHREDDER_SCALE_ROOTS = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local SHREDDER_SCALE_ROOT_ITEMS = table.concat(SHREDDER_SCALE_ROOTS, "\0") .. "\0"

local SHREDDER_SCALE_TYPES = {
  { label = "Major",            value = "major" },
  { label = "Minor",            value = "minor" },
  { label = "Major Pentatonic", value = "majpent" },
  { label = "Minor Pentatonic", value = "minpent" },
  { label = "Chromatic",        value = "chromatic" },
}
local SHREDDER_SCALE_TYPE_ITEMS = ""
for _, s in ipairs(SHREDDER_SCALE_TYPES) do
  SHREDDER_SCALE_TYPE_ITEMS = SHREDDER_SCALE_TYPE_ITEMS .. s.label .. "\0"
end

local function find_scale_type_index(value)
  for i, s in ipairs(SHREDDER_SCALE_TYPES) do
    if s.value == value then return i - 1 end
  end
  return 0
end

-- Shuffle Mode (V3): dropdown data for the unified Full/None/Local/
-- Weighted selector that replaces V2's simple No-Shuffle checkbox.
local SHREDDER_SHUFFLE_MODES = {
  { label = "Full Shuffle", value = "full" },
  { label = "No Shuffle",   value = "none" },
  { label = "Local (Windowed)", value = "local" },
  { label = "Weighted (Amount Dial)", value = "weighted" },
}
local SHREDDER_SHUFFLE_MODE_ITEMS = ""
for _, s in ipairs(SHREDDER_SHUFFLE_MODES) do
  SHREDDER_SHUFFLE_MODE_ITEMS = SHREDDER_SHUFFLE_MODE_ITEMS .. s.label .. "\0"
end

local function find_shuffle_mode_index(value)
  for i, s in ipairs(SHREDDER_SHUFFLE_MODES) do
    if s.value == value then return i - 1 end
  end
  return 0
end

-- Sequence-Based Cutting (V5): Sequence Type dropdown data, plus small
-- generator functions duplicated from the engine (Antisample_Shredder_
-- V4.lua) purely so the UI can show a "Weights: 1, 1, 2, 3, 5, 8"
-- preview line - these never touch real audio, they only produce the
-- text preview.
local SHREDDER_SEQUENCE_TYPES = {
  { label = "Fibonacci",  value = "fibonacci" },
  { label = "Lucas",      value = "lucas" },
  { label = "Padovan",    value = "padovan" },
  { label = "Tribonacci", value = "tribonacci" },
  { label = "Custom",     value = "custom" },
}
local SHREDDER_SEQUENCE_TYPE_ITEMS = ""
for _, s in ipairs(SHREDDER_SEQUENCE_TYPES) do
  SHREDDER_SEQUENCE_TYPE_ITEMS = SHREDDER_SEQUENCE_TYPE_ITEMS .. s.label .. "\0"
end

local function find_sequence_type_index(value)
  for i, s in ipairs(SHREDDER_SEQUENCE_TYPES) do
    if s.value == value then return i - 1 end
  end
  return 0
end

-- Pitagora (V6) triple selector data.
local SHREDDER_PITAGORA_TRIPLES = {
  "3-4-5", "5-12-13", "8-15-17", "7-24-25", "20-21-29", "9-40-41",
}
local SHREDDER_PITAGORA_TRIPLE_ITEMS = table.concat(SHREDDER_PITAGORA_TRIPLES, "\0") .. "\0"

local function find_pitagora_triple_index(value)
  for i, t in ipairs(SHREDDER_PITAGORA_TRIPLES) do
    if t == value then return i - 1 end
  end
  return 0
end

-- Three-column Cut Mode selector (v1.9): "Classic" / "Sequence" /
-- "Bizarre", each its own dropdown, with a leading "-" placeholder
-- item (index 0) shown whenever the active Cut Mode belongs to a
-- DIFFERENT column - so only one of the three combos ever shows a
-- real selection at a time, same mutual-exclusivity the old flat
-- radio-button row had, just organized into categories. Clicking a
-- column's own placeholder is a no-op (see the call site) rather than
-- a way to "turn off" the active mode - some Cut Mode is always
-- active.
local SHREDDER_MODE_COLUMNS = {
  {
    label = "Classic",
    modes = {
      { label = "-", value = nil },
      { label = "By Cut Length", value = "length" },
      { label = "By Number of Cuts", value = "count" },
      { label = "Beat-Synced", value = "beat" },
      { label = "Euclidean", value = "euclid" },
      { label = "Transient", value = "onset" },
    },
  },
  {
    label = "Sequence",
    modes = {
      { label = "-", value = nil },
      { label = "Sequence", value = "sequence" },
    },
  },
  {
    label = "Bizarre",
    modes = {
      { label = "-", value = nil },
      { label = "Black/White Hole", value = "blackhole" },
      { label = "Pitagora", value = "pitagora" },
      { label = "Collatz", value = "collatz" },
      { label = "Cantor Dust", value = "cantor" },
      { label = "Morse", value = "morse" },
    },
  },
}
for _, col in ipairs(SHREDDER_MODE_COLUMNS) do
  local items = ""
  for _, m in ipairs(col.modes) do items = items .. m.label .. "\0" end
  col.items = items
end

local function shredder_mode_col_index(col, current_mode)
  for i, m in ipairs(col.modes) do
    if m.value == current_mode then return i - 1 end
  end
  return 0
end

local function shredder_fibonacci_sequence(count)
  local seq = {}
  local a, b = 1, 1
  for i = 1, count do
    seq[i] = a
    a, b = b, a + b
  end
  return seq
end

local function shredder_lucas_sequence(count)
  local seq = {}
  local a, b = 2, 1
  for i = 1, count do
    seq[i] = a
    a, b = b, a + b
  end
  return seq
end

local function shredder_padovan_sequence(count)
  local seq = { 1, 1, 1 }
  for i = 4, count do
    seq[i] = seq[i - 2] + seq[i - 3]
  end
  local result = {}
  for i = 1, count do result[i] = seq[i] end
  return result
end

local function shredder_tribonacci_sequence(count)
  local seq = { 1, 1, 2 }
  for i = 4, count do
    seq[i] = seq[i - 1] + seq[i - 2] + seq[i - 3]
  end
  local result = {}
  for i = 1, count do result[i] = seq[i] end
  return result
end

local function shredder_parse_custom_sequence(str)
  local weights = {}
  for token in string.gmatch(str or "", "[^,]+") do
    local n = tonumber(token)
    if n and n > 0 then table.insert(weights, n) end
  end
  if #weights == 0 then weights = { 1 } end
  return weights
end

-- Morse Code Cuts (v1.16) - mirrors the engine's MORSE_TABLE/morse_
-- encode() (Antisample_Shredder_V11.lua) exactly, purely so the UI
-- can show a live "dots and dashes" preview of what the typed message
-- encodes to, and so the Cut Lengths chart can preview it accurately.
local SHREDDER_MORSE_TABLE = {
  A = ".-",    B = "-...",  C = "-.-.",  D = "-..",   E = ".",
  F = "..-.",  G = "--.",   H = "....",  I = "..",    J = ".---",
  K = "-.-",   L = ".-..",  M = "--",    N = "-.",    O = "---",
  P = ".--.",  Q = "--.-",  R = ".-.",   S = "...",   T = "-",
  U = "..-",   V = "...-",  W = ".--",   X = "-..-",  Y = "-.--",
  Z = "--..",
  ["0"] = "-----", ["1"] = ".----", ["2"] = "..---", ["3"] = "...--",
  ["4"] = "....-", ["5"] = ".....", ["6"] = "-....", ["7"] = "--...",
  ["8"] = "---..", ["9"] = "----.",
  ["."] = ".-.-.-", [","] = "--..--", ["?"] = "..--..",
}

local function shredder_morse_encode(text)
  local symbols = {}
  local at_word_start = true
  local function add(units, muted) table.insert(symbols, { units = units, muted = muted }) end
  for i = 1, #text do
    local ch = text:sub(i, i):upper()
    if ch == " " then
      if not at_word_start then add(7, true) end
      at_word_start = true
    else
      local code = SHREDDER_MORSE_TABLE[ch]
      if code then
        if not at_word_start then add(3, true) end
        at_word_start = false
        for j = 1, #code do
          if j > 1 then add(1, true) end
          if code:sub(j, j) == "." then add(1, false) else add(3, false) end
        end
      end
    end
  end
  return symbols
end

-- Builds the human-readable "... --- ..." display string for a
-- message (word gaps shown as " / ", letters space-separated) - for
-- the read-only preview caption under the text input, not used for
-- any cut math (shredder_morse_encode() above is the source of truth
-- for that).
local function shredder_morse_display(text)
  local words = {}
  for word in (text .. " "):gmatch("(.-) ") do
    if word ~= "" then
      local letters = {}
      for i = 1, #word do
        local code = SHREDDER_MORSE_TABLE[word:sub(i, i):upper()]
        if code then table.insert(letters, code) end
      end
      if #letters > 0 then table.insert(words, table.concat(letters, " ")) end
    end
  end
  if #words == 0 then return "(nothing encodable - try letters, digits, or spaces)" end
  return table.concat(words, "  /  ")
end


local EXT_SECTION = "AntisampleFXUI"
-- All ExtState key strings, consolidated into one table instead of
-- ~43 separate top-level locals (Lua's main-chunk local limit is 200,
-- and this script was right at the edge).
local KEYS = {
  NUM_EFFECTS = "NUM_EFFECTS",
  NUM_PARALLEL_BRANCHES = "NumParallelBranches",
  RANDOMIZE_WET_DRY = "RandomizeWetDry",
  PARALLEL_CHAIN_ENABLED = "ParallelChainEnabled",
  PALETTE_NAME = "PaletteName",
  FONT_COLOR_NAME = "FontColorName",
  RUN_BUTTON_COLOR = "RunButtonColor",
  BYPASS = "NUM_EFFECTS_TO_BYPASS",
  RANDOM_SKIP_PARAMS = "RandomFXSkipParams",
  Shredder_CUT_LENGTH = "ShredderCutLength",
  Shredder_NUM_CUTS = "ShredderNumCuts",
  Shredder_CUT_MODE = "ShredderCutMode",
  Shredder_MASH_MODE = "ShredderMashMode",
  Shredder_IGNORE_SILENCE = "ShredderIgnoreSilence",
  Shredder_POSITION = "ShredderPositionMs",
  Shredder_RATE = "ShredderRate",
  Shredder_PITCH = "ShredderPitch",
  Shredder_PAN = "ShredderPan",
  Shredder_VOLUME = "ShredderVolume",
  Shredder_REVERSE = "ShredderReverse",
  Shredder_REPEAT = "ShredderRepeat",
  Shredder_MUTE = "ShredderMute",
  Shredder_STRETCH = "ShredderStretch",
  Shredder_STRETCH_DIRECTION = "ShredderStretchDirection",
  Shredder_RAND_INCLUDE_STRETCH = "ShredderRandIncludeStretch",
  Shredder_PITCH_MODE = "ShredderPitchMode",
  Shredder_PITCH_MODE_RANDOM = "ShredderPitchModeRandom",
  -- V2 additions:
  Shredder_BEAT_DIVISION = "ShredderBeatDivision",
  Shredder_BEAT_VARIANCE = "ShredderBeatVariance",
  Shredder_NO_SHUFFLE = "ShredderNoShuffle",
  Shredder_SUBSET_MODE = "ShredderSubsetMode",
  Shredder_SUBSET_KEEP = "ShredderSubsetKeepPercent",
  -- V3 additions:
  Shredder_EUCLID_STEPS = "ShredderEuclidSteps",
  Shredder_EUCLID_HITS = "ShredderEuclidHits",
  Shredder_FIB_SEGMENTS = "ShredderFibSegments",
  Shredder_FIB_DESCENDING = "ShredderFibDescending",
  Shredder_ONSET_SENSITIVITY = "ShredderOnsetSensitivity",
  Shredder_SHUFFLE_MODE = "ShredderShuffleMode",
  Shredder_LOCAL_WINDOW = "ShredderLocalShuffleWindow",
  Shredder_WEIGHTED_AMOUNT = "ShredderWeightedShuffleAmount",
  Shredder_PALINDROME = "ShredderPalindrome",
  Shredder_SCALE_QUANTIZE = "ShredderScaleQuantize",
  Shredder_SCALE_ROOT = "ShredderScaleRoot",
  Shredder_SCALE_TYPE = "ShredderScaleType",
  Shredder_SIDECHAIN_ENABLED = "ShredderSidechainEnabled",
  Shredder_SIDECHAIN_TRACK = "ShredderSidechainTrack",
  Shredder_SIDECHAIN_THRESHOLD = "ShredderSidechainThreshold",
  Shredder_SIDECHAIN_INVERT = "ShredderSidechainInvert",
  Shredder_SIDECHAIN_DROP = "ShredderSidechainDrop",
  Shredder_SHOW_PREVIEW = "ShredderShowPreview",
  Shredder_SEQUENCE_TYPE = "ShredderSequenceType",
  Shredder_SEQUENCE_CUSTOM = "ShredderSequenceCustom",
  Shredder_PREVIEW_ITEM_LEN = "ShredderPreviewItemLen", -- unused since V7 (fixed constant now), kept so old ExtState reads don't error
  Shredder_CUT_CHART_HEIGHT = "ShredderCutChartHeight",
  Shredder_CHUNK_FATE_HEIGHT = "ShredderChunkFateHeight",
  Shredder_MASH_PREVIEW_HEIGHT = "ShredderMashPreviewHeight",
  Shredder_CHUNK_FATE_VIEW = "ShredderChunkFateView",
  Shredder_BLACKHOLE_START = "ShredderBlackholeStart",
  Shredder_BLACKHOLE_DECAY = "ShredderBlackholeDecay",
  Shredder_WHITE_HOLE = "ShredderWhiteHole",
  Shredder_BLACKHOLE_LOOP = "ShredderBlackholeLoop",
  Shredder_PITAGORA_TRIPLE = "ShredderPitagoraTriple",
  Shredder_COLLATZ_SEED = "ShredderCollatzSeed",
  Shredder_COLLATZ_DESCENDING = "ShredderCollatzDescending",
  Shredder_CANTOR_DEPTH = "ShredderCantorDepth",
  Shredder_MORSE_TEXT = "ShredderMorseText",
  Shredder_MORSE_UNIT_MS = "ShredderMorseUnitMs",
  Shredder_MORSE_LOOP = "ShredderMorseLoop",
  Shredder_MIN_SEG_OVERRIDE = "ShredderMinSegOverride",
  Shredder_MIN_SEG_OVERRIDE_MS = "ShredderMinSegOverrideMs",
  Shredder_PRESET_NAME = "ShredderPresetName",
  Shredder_POSITION_DIRECTION = "ShredderPositionDirection",
  Shredder_PITCH_DIRECTION = "ShredderPitchDirection",
  Shredder_PAN_DIRECTION = "ShredderPanDirection",
  Shredder_VOLUME_DIRECTION = "ShredderVolumeDirection",
  Shredder_HIDE_HELP_TEXT = "ShredderHideHelpText",
  Shredder_RAND_INCLUDE_POSITION = "ShredderRandIncludePosition",
  Shredder_RAND_INCLUDE_RATE = "ShredderRandIncludeRate",
  Shredder_RAND_INCLUDE_PITCH = "ShredderRandIncludePitch",
  Shredder_RAND_INCLUDE_PAN = "ShredderRandIncludePan",
  Shredder_RAND_INCLUDE_VOLUME = "ShredderRandIncludeVolume",
  Shredder_RAND_INCLUDE_REVERSE = "ShredderRandIncludeReverse",
  Shredder_RAND_INCLUDE_REPEAT = "ShredderRandIncludeRepeat",
  Shredder_RAND_INCLUDE_MUTE = "ShredderRandIncludeMute",
  Shredder_RENDER_NAME_PATTERN = "ShredderRenderNamePattern",
  Shredder_SCATTER_REPEATS = "ShredderScatterRepeats",
  Shredder_PIN_POSITION = "ShredderPinPosition",
  Shredder_COMPACT_MODE = "ShredderCompactMode",
  Shredder_CUT_LENGTH_FIXED = "ShredderCutLengthFixed",
  Shredder_CUT_ONLY = "ShredderCutOnly",
  FONT_SIZE = "FontSize",
  LIMITER_NAME = "LimiterName",
  WIN_W = "WinW",
  WIN_H = "WinH",
  DOCK_ID = "DockID",
  MOD_TARGET = "ModTarget",
  MOD_SHOW_LAST_TOUCHED = "ModShowLastTouched",
  MOD_MANUAL_ADD = "ModManualAdd",
  MOD_TYPE = "ModType",
  MOD_BASELINE = "ModBaseline",
  MOD_SHAPE = "ModShape",
  MOD_DIR = "ModDir",
  MOD_TEMPOSYNC = "ModTempoSync",
  MOD_VISIBLE = "ModVisible",
  MOD_LFO_SPEED = "ModLfoSpeed",
  MOD_LFO_STRENGTH = "ModLfoStrength",
  MOD_LFO_PHASE = "ModLfoPhase",
  MOD_ACS_CHAN = "ModAcsChan",
  MOD_ACS_ATTACK = "ModAcsAttack",
  MOD_ACS_RELEASE = "ModAcsRelease",
  MOD_ACS_STRENGTH = "ModAcsStrength",
}
local DEFAULT_LIMITER_NAME = "VST3: Pro-L 2 (Fabfilter)"
local LIMITER_FALLBACK_NAME = "ReaLimit" -- same fallback used by the chain-builder scripts

------------------------------------------------------------
-- Shredder Presets
------------------------------------------------------------
-- A preset is a snapshot of every SOUND-affecting Shredder setting
-- (Cut Mode + its params, Structural Modes, Per-Segment Randomization)
-- - deliberately NOT the rest of this app's other tabs (Modulation,
-- Parallel Branches, etc.) or Shredder's own UI-layout prefs (preview
-- window sizes, which view is open) - just the things that change
-- what a run actually sounds like. Stored as one plain-text file per
-- preset (key=value lines) in REAPER's resource folder, so presets
-- are visible/portable/backup-able as ordinary files, not buried
-- inside REAPER's single global ExtState.ini.
--
-- Every setting is ALREADY kept in sync with ExtState by its own
-- widget's SetExtState call (that's how settings already survive
-- across sessions) - so SAVING a preset is simple: read the current
-- ExtState value for every key in the schema below and write it out.
-- LOADING is the harder half: writing to ExtState alone wouldn't
-- update the UI until next restart, since most settings are read into
-- local variables/the SD table once at launch, not re-read every
-- frame - so loading also has to push each value into whichever LIVE
-- variable holds it. Settings living in the SD table (most of them)
-- are simple, since SD is addressable by string key; the smaller set
-- still living in standalone top-level locals (from before the SD
-- table existed) need explicit handling - see
-- shredder_apply_preset_value_to_local() further down, defined right
-- after those locals so it can see them as upvalues.
--
-- Schema entries: { key = <ExtState key, via KEYS>, kind = "num"|
-- "bool"|"str", sd = <SD field name, if this setting lives in SD;
-- omitted for the standalone-local settings> }.
local SHREDDER_PRESET_SCHEMA = {
  -- Cut Mode + basic (standalone locals)
  { key = KEYS.Shredder_CUT_MODE, kind = "str" },
  { key = KEYS.Shredder_CUT_LENGTH, kind = "num" },
  { key = KEYS.Shredder_NUM_CUTS, kind = "num" },
  { key = KEYS.Shredder_MASH_MODE, kind = "bool" },
  { key = KEYS.Shredder_IGNORE_SILENCE, kind = "bool" },
  { key = KEYS.Shredder_BEAT_DIVISION, kind = "num" },
  { key = KEYS.Shredder_BEAT_VARIANCE, kind = "num" },
  { key = KEYS.Shredder_SUBSET_MODE, kind = "bool" },
  { key = KEYS.Shredder_SUBSET_KEEP, kind = "num" },
  -- Per-segment randomization (standalone locals)
  { key = KEYS.Shredder_POSITION, kind = "num" },
  { key = KEYS.Shredder_RATE, kind = "num" },
  { key = KEYS.Shredder_PITCH, kind = "num" },
  { key = KEYS.Shredder_PAN, kind = "num" },
  { key = KEYS.Shredder_VOLUME, kind = "num" },
  { key = KEYS.Shredder_REVERSE, kind = "num" },
  { key = KEYS.Shredder_REPEAT, kind = "num" },
  { key = KEYS.Shredder_MUTE, kind = "num" },
  { key = KEYS.Shredder_STRETCH, kind = "num" },
  -- Everything below lives in the SD table
  { key = KEYS.Shredder_SHUFFLE_MODE, kind = "str", sd = "shuffle_mode" },
  { key = KEYS.Shredder_LOCAL_WINDOW, kind = "num", sd = "local_window" },
  { key = KEYS.Shredder_WEIGHTED_AMOUNT, kind = "num", sd = "weighted_amount" },
  { key = KEYS.Shredder_PALINDROME, kind = "bool", sd = "palindrome" },
  { key = KEYS.Shredder_EUCLID_STEPS, kind = "num", sd = "euclid_steps" },
  { key = KEYS.Shredder_EUCLID_HITS, kind = "num", sd = "euclid_hits" },
  { key = KEYS.Shredder_FIB_SEGMENTS, kind = "num", sd = "fib_segments" },
  { key = KEYS.Shredder_FIB_DESCENDING, kind = "bool", sd = "fib_descending" },
  { key = KEYS.Shredder_SEQUENCE_TYPE, kind = "str", sd = "sequence_type" },
  { key = KEYS.Shredder_SEQUENCE_CUSTOM, kind = "str", sd = "sequence_custom" },
  { key = KEYS.Shredder_ONSET_SENSITIVITY, kind = "num", sd = "onset_sensitivity" },
  { key = KEYS.Shredder_SCALE_QUANTIZE, kind = "bool", sd = "scale_quantize" },
  { key = KEYS.Shredder_SCALE_ROOT, kind = "num", sd = "scale_root" },
  { key = KEYS.Shredder_SCALE_TYPE, kind = "str", sd = "scale_type" },
  { key = KEYS.Shredder_SIDECHAIN_ENABLED, kind = "bool", sd = "sidechain_enabled" },
  { key = KEYS.Shredder_SIDECHAIN_TRACK, kind = "str", sd = "sidechain_track" },
  { key = KEYS.Shredder_SIDECHAIN_THRESHOLD, kind = "num", sd = "sidechain_threshold" },
  { key = KEYS.Shredder_SIDECHAIN_INVERT, kind = "bool", sd = "sidechain_invert" },
  { key = KEYS.Shredder_SIDECHAIN_DROP, kind = "bool", sd = "sidechain_drop" },
  { key = KEYS.Shredder_BLACKHOLE_START, kind = "num", sd = "blackhole_start" },
  { key = KEYS.Shredder_BLACKHOLE_DECAY, kind = "num", sd = "blackhole_decay" },
  { key = KEYS.Shredder_WHITE_HOLE, kind = "bool", sd = "white_hole" },
  { key = KEYS.Shredder_BLACKHOLE_LOOP, kind = "bool", sd = "blackhole_loop" },
  { key = KEYS.Shredder_PITAGORA_TRIPLE, kind = "str", sd = "pitagora_triple" },
  { key = KEYS.Shredder_COLLATZ_SEED, kind = "num", sd = "collatz_seed" },
  { key = KEYS.Shredder_COLLATZ_DESCENDING, kind = "bool", sd = "collatz_descending" },
  { key = KEYS.Shredder_CANTOR_DEPTH, kind = "num", sd = "cantor_depth" },
  { key = KEYS.Shredder_MORSE_TEXT, kind = "str", sd = "morse_text" },
  { key = KEYS.Shredder_MORSE_UNIT_MS, kind = "num", sd = "morse_unit_ms" },
  { key = KEYS.Shredder_MORSE_LOOP, kind = "bool", sd = "morse_loop" },
  { key = KEYS.Shredder_MIN_SEG_OVERRIDE, kind = "bool", sd = "min_seg_override_enabled" },
  { key = KEYS.Shredder_MIN_SEG_OVERRIDE_MS, kind = "num", sd = "min_seg_override_ms" },
  -- v1.21: Direction (see the APPENDIX (V12) note in the engine file).
  { key = KEYS.Shredder_POSITION_DIRECTION, kind = "str", sd = "position_direction" },
  { key = KEYS.Shredder_PITCH_DIRECTION, kind = "str", sd = "pitch_direction" },
  { key = KEYS.Shredder_PAN_DIRECTION, kind = "str", sd = "pan_direction" },
  { key = KEYS.Shredder_VOLUME_DIRECTION, kind = "str", sd = "volume_direction" },
  { key = KEYS.Shredder_STRETCH_DIRECTION, kind = "str", sd = "stretch_direction" },
  -- v1.35: Scatter Repeats (see the APPENDIX (V15) note in the engine
  -- file) - a genuine sound-affecting setting, unlike the render/
  -- workflow prefs above, so it's part of the schema.
  { key = KEYS.Shredder_SCATTER_REPEATS, kind = "bool", sd = "scatter_repeats" },
  -- v1.38: Cut Length Fixed (see the APPENDIX (V16) note in the engine
  -- file) - also sound-affecting, displayed in Settings but still
  -- part of the schema for the same reason Scatter Repeats is.
  { key = KEYS.Shredder_CUT_LENGTH_FIXED, kind = "bool", sd = "cut_length_fixed" },
  { key = KEYS.Shredder_PITCH_MODE, kind = "num", sd = "pitch_mode" },
  { key = KEYS.Shredder_PITCH_MODE_RANDOM, kind = "bool", sd = "pitch_mode_random" },
}

-- Presets live in a "Presets" subfolder right next to this script
-- (not REAPER's own Data folder) - so a ReaPack package (or a plain
-- manual copy) that includes both the scripts AND a Presets/ folder
-- ships with working default presets out of the box, no separate
-- install step, and everything for this tool stays together in one
-- place rather than split across REAPER's install tree.
local function shredder_preset_dir()
  local dir = SCRIPT_DIR .. "Presets"
  reaper.RecursiveCreateDirectory(dir, 0)
  return dir
end

-- Strips characters that aren't safe in a filename on any of Windows/
-- macOS/Linux, trims whitespace, and falls back to "Preset" if that
-- leaves nothing usable (e.g. the field was empty or pure symbols).
local function shredder_sanitize_preset_name(name)
  name = tostring(name or "")
  name = name:gsub('[/\\:%*%?"<>|]', "_")
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then name = "Preset" end
  return name
end

local function shredder_preset_path(name)
  return shredder_preset_dir() .. "/" .. shredder_sanitize_preset_name(name) .. ".txt"
end

-- Returns a sorted array of preset names (without the .txt extension)
-- currently saved in the presets folder.
local function shredder_list_presets()
  local dir = shredder_preset_dir()
  local names = {}
  local i = 0
  while true do
    local fn = reaper.EnumerateFiles(dir, i)
    if not fn then break end
    local name = fn:match("^(.*)%.txt$")
    if name then table.insert(names, name) end
    i = i + 1
  end
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  return names
end

-- Writes every schema setting's CURRENT ExtState value out to the
-- preset file - since every widget already keeps ExtState in sync as
-- the user changes things, this is just a read-and-copy, no need to
-- know whether a given setting lives in SD or a standalone local.
local function shredder_save_preset(name)
  local path = shredder_preset_path(name)
  local file = io.open(path, "w")
  if not file then return false end
  for _, entry in ipairs(SHREDDER_PRESET_SCHEMA) do
    local v = reaper.GetExtState(EXT_SECTION, entry.key)
    v = tostring(v):gsub("\n", " "):gsub("\r", " ")
    file:write(entry.key .. "=" .. v .. "\n")
  end
  file:close()
  return true
end

-- Reads a preset file into a plain { ExtStateKey = rawStringValue }
-- table. Returns nil if the file doesn't exist or can't be read.
local function shredder_read_preset_file(name)
  local path = shredder_preset_path(name)
  local file = io.open(path, "r")
  if not file then return nil end
  local values = {}
  for line in file:lines() do
    local k, v = line:match("^([^=]+)=(.*)$")
    if k then values[k] = v end
  end
  file:close()
  return values
end

local function shredder_delete_preset(name)
  os.remove(shredder_preset_path(name))
end

-- Edited-preset tracking: a snapshot of every schema setting as it was
-- when the current preset was loaded/saved/Init'd. The preset bar shows
-- "*" whenever the live ExtState values differ from it - so changing a
-- value back clears the mark again. Nothing is written to disk until
-- the user saves. `file_values` (optional) seeds the snapshot from a
-- preset file instead of the live values - used at startup, so edits
-- made last session still show as edited.
local shredder_preset_baseline = {}

local function shredder_snapshot_preset_baseline(file_values)
  for _, entry in ipairs(SHREDDER_PRESET_SCHEMA) do
    local v = file_values and file_values[entry.key]
    if v == nil then v = reaper.GetExtState(EXT_SECTION, entry.key) end
    shredder_preset_baseline[entry.key] = v
  end
end

local function shredder_preset_is_dirty()
  for _, entry in ipairs(SHREDDER_PRESET_SCHEMA) do
    if reaper.GetExtState(EXT_SECTION, entry.key) ~= shredder_preset_baseline[entry.key] then
      return true
    end
  end
  return false
end



------------------------------------------------------------
-- Antisample brand palette (sampled from Logo512.png)
--   background : #282A28  (dark charcoal)
--   orange     : #CC7129  (the "a" mark + "anti")
--   gray       : #C4C4C4  (the "sample" text)
-- Orange is the primary accent (default buttons, active tab, checkmarks,
-- sliders); the brand gray is used for Item-specific buttons so Track
-- vs Item stays visually distinct while both read as "Antisample".
------------------------------------------------------------

local THEME_BG              = 0x282A28FF
local THEME_BG_ALT          = 0x1F211FFF -- child windows, popups, inactive tabs
local THEME_FRAME_BG        = 0x34362FFF -- inputs/sliders/checkboxes/headers
local THEME_FRAME_BG_HOVER  = 0x3E4038FF
local THEME_FRAME_BG_ACTIVE = 0x484A40FF
local THEME_TEXT            = 0xC4C4C4FF
local THEME_TEXT_DISABLED   = 0x7A7C78FF
local THEME_BORDER          = 0x45473FFF

local THEME_ORANGE          = 0xCC7129FF
local THEME_ORANGE_HOVER    = 0xE0813AFF
local THEME_ORANGE_ACTIVE   = 0xA8591FFF

-- Amber, used only for the status line when it's reporting a no-op
-- (nothing selected, nothing to do, an error) rather than a completed
-- action - distinct from the brand orange so it reads as "heads up".
local STATUS_WARN_COLOR     = 0xE0A020FF

-- Chunk Fate marker colors (V7) - fixed accents (like the two above),
-- not palette-driven, one per per-segment property shown in the mini
-- bar-code row under each Final order box.
local MARKER_POSITION = 0x3E8EDEFF -- blue
local MARKER_RATE     = 0x5FAE4CFF -- green
local MARKER_PITCH    = 0x9B6FD8FF -- purple
local MARKER_PAN      = 0x3FB6A8FF -- teal
local MARKER_VOLUME   = 0xD86FA0FF -- pink

-- Multi-item Mash preview (V10) - two colors distinguishing which
-- demo item a chunk originally came from (distinct from the 7
-- per-property MARKER_* colors above, which mean something different).
local MARKER_ITEM_A = 0x4FA8D8FF -- light blue
local MARKER_ITEM_B = 0xE0825AFF -- coral

local ITEM_BTN_COLOR         = 0x8A8C86FF -- brand gray, for Item actions
local ITEM_BTN_COLOR_HOVERED = 0x9EA097FF
local ITEM_BTN_COLOR_ACTIVE  = 0x6E706AFF

-- Built-in color palette presets (UI Settings tab > Color Palette).
-- Every field below is reassigned into the THEME_*/STATUS_WARN_COLOR/
-- ITEM_BTN_COLOR* variables above by apply_palette() - the values
-- hardcoded above are simply the "Antisample (Orange)" preset's own
-- values, so the app looks identical on first launch before any
-- preset button is ever clicked.
local PALETTE_PRESETS = {
  {
    name = "Antisample (Orange)",
    bg = 0x282A28FF, bg_alt = 0x1F211FFF,
    frame_bg = 0x34362FFF, frame_bg_hover = 0x3E4038FF, frame_bg_active = 0x484A40FF,
    text = 0xC4C4C4FF, text_disabled = 0x7A7C78FF, border = 0x45473FFF,
    accent = 0xCC7129FF, accent_hover = 0xE0813AFF, accent_active = 0xA8591FFF,
    status_warn = 0xE0A020FF,
    item_btn = 0x8A8C86FF, item_btn_hovered = 0x9EA097FF, item_btn_active = 0x6E706AFF,
  },
  {
    name = "Flat Dark (Blue)",
    bg = 0x22252AFF, bg_alt = 0x1A1C20FF,
    frame_bg = 0x2E3238FF, frame_bg_hover = 0x383D44FF, frame_bg_active = 0x424852FF,
    text = 0xD0D3D6FF, text_disabled = 0x7D8388FF, border = 0x3A3F45FF,
    accent = 0x3E8EDEFF, accent_hover = 0x5AA0E8FF, accent_active = 0x2E72BEFF,
    status_warn = 0xE0A020FF,
    item_btn = 0x6E747AFF, item_btn_hovered = 0x828892FF, item_btn_active = 0x585E64FF,
  },
  {
    name = "Forest (Green)",
    bg = 0x232A25FF, bg_alt = 0x1B211CFF,
    frame_bg = 0x303A32FF, frame_bg_hover = 0x39453BFF, frame_bg_active = 0x435046FF,
    text = 0xC8D0C8FF, text_disabled = 0x7C847CFF, border = 0x3E4A3FFF,
    accent = 0x4CA85EFF, accent_hover = 0x5EBC70FF, accent_active = 0x3B8B4AFF,
    status_warn = 0xE0A020FF,
    item_btn = 0x7A867CFF, item_btn_hovered = 0x8E9A90FF, item_btn_active = 0x606C62FF,
  },
  {
    name = "Slate (Purple)",
    bg = 0x252428FF, bg_alt = 0x1C1B1FFF,
    frame_bg = 0x322F38FF, frame_bg_hover = 0x3C3942FF, frame_bg_active = 0x46424CFF,
    text = 0xCBC8D0FF, text_disabled = 0x7E7B84FF, border = 0x423F49FF,
    accent = 0x8E5FD6FF, accent_hover = 0xA279E4FF, accent_active = 0x7248B0FF,
    status_warn = 0xE0A020FF,
    item_btn = 0x827E8AFF, item_btn_hovered = 0x96929EFF, item_btn_active = 0x68646FFF,
  },
  {
    name = "Crimson (Red)",
    bg = 0x2A2424FF, bg_alt = 0x211C1CFF,
    frame_bg = 0x3A3030FF, frame_bg_hover = 0x453838FF, frame_bg_active = 0x504040FF,
    text = 0xD0C8C8FF, text_disabled = 0x847C7CFF, border = 0x4A3D3DFF,
    accent = 0xD6483EFF, accent_hover = 0xE45E52FF, accent_active = 0xB0362DFF,
    status_warn = 0xE0A020FF,
    item_btn = 0x8A7C7CFF, item_btn_hovered = 0x9E9090FF, item_btn_active = 0x706464FF,
  },
  {
    name = "Amber (Gold)",
    bg = 0x2A2620FF, bg_alt = 0x211E19FF,
    frame_bg = 0x3A3428FF, frame_bg_hover = 0x453E30FF, frame_bg_active = 0x504838FF,
    text = 0xD4CCBCFF, text_disabled = 0x86806FFF, border = 0x4A4232FF,
    accent = 0xD6A030FF, accent_hover = 0xE4B448FF, accent_active = 0xB08024FF,
    status_warn = 0xE0A020FF,
    item_btn = 0x8C8270FF, item_btn_hovered = 0xA0968AFF, item_btn_active = 0x726A5AFF,
  },
  {
    name = "Teal",
    bg = 0x1F2A28FF, bg_alt = 0x18211FFF,
    frame_bg = 0x2A3A36FF, frame_bg_hover = 0x334540FF, frame_bg_active = 0x3D504AFF,
    text = 0xC4D4D0FF, text_disabled = 0x788480FF, border = 0x3A4A45FF,
    accent = 0x2EB89AFF, accent_hover = 0x44CCAEFF, accent_active = 0x239480FF,
    status_warn = 0xE0A020FF,
    item_btn = 0x788A84FF, item_btn_hovered = 0x8C9E98FF, item_btn_active = 0x60726CFF,
  },
  {
    name = "Rose",
    bg = 0x2A242AFF, bg_alt = 0x211C21FF,
    frame_bg = 0x3A303AFF, frame_bg_hover = 0x453845FF, frame_bg_active = 0x504050FF,
    text = 0xD4C8D0FF, text_disabled = 0x847C82FF, border = 0x4A3D48FF,
    accent = 0xE0568EFF, accent_hover = 0xEC70A2FF, accent_active = 0xBC4272FF,
    status_warn = 0xE0A020FF,
    item_btn = 0x8C7C86FF, item_btn_hovered = 0xA0909AFF, item_btn_active = 0x72646CFF,
  },
}

-- Applies a preset (one of the tables in PALETTE_PRESETS) by
-- reassigning every THEME_*/STATUS_WARN_COLOR/ITEM_BTN_COLOR*
-- variable above. Takes effect the next frame, since push_theme()
-- reads these fresh every time it's called rather than a frozen map.
local function apply_palette(p)
  THEME_BG = p.bg
  THEME_BG_ALT = p.bg_alt
  THEME_FRAME_BG = p.frame_bg
  THEME_FRAME_BG_HOVER = p.frame_bg_hover
  THEME_FRAME_BG_ACTIVE = p.frame_bg_active
  THEME_TEXT = p.text
  THEME_TEXT_DISABLED = p.text_disabled
  THEME_BORDER = p.border
  THEME_ORANGE = p.accent
  THEME_ORANGE_HOVER = p.accent_hover
  THEME_ORANGE_ACTIVE = p.accent_active
  STATUS_WARN_COLOR = p.status_warn
  ITEM_BTN_COLOR = p.item_btn
  ITEM_BTN_COLOR_HOVERED = p.item_btn_hovered
  ITEM_BTN_COLOR_ACTIVE = p.item_btn_active
end

-- Font color presets - independent of the background/button palette
-- above, so text color can be mixed and matched separately. Only
-- overrides THEME_TEXT/THEME_TEXT_DISABLED; everything else (bg,
-- buttons, accent) is untouched.
local FONT_COLOR_PRESETS = {
  { name = "Light Gray", text = 0xC4C4C4FF, text_disabled = 0x7A7C78FF },
  { name = "Warm White", text = 0xE8E4DCFF, text_disabled = 0x8C887FFF },
  { name = "Cool White", text = 0xDCE4E8FF, text_disabled = 0x7F888CFF },
  { name = "Soft Amber", text = 0xE0C090FF, text_disabled = 0x8C7C5CFF },
}

local function apply_font_color(p)
  THEME_TEXT = p.text
  THEME_TEXT_DISABLED = p.text_disabled
end


-- Restore the saved palette choice (by name) on launch, if any -
-- falls back silently to the hardcoded defaults above (the "Antisample
-- (Orange)" preset's own values) if nothing was saved yet, or if the
-- saved name no longer matches a known preset.
local active_palette_name = reaper.GetExtState(EXT_SECTION, KEYS.PALETTE_NAME)
if active_palette_name ~= "" then
  for _, p in ipairs(PALETTE_PRESETS) do
    if p.name == active_palette_name then
      apply_palette(p)
      break
    end
  end
end

-- Restored AFTER the palette above, so a separately-chosen font color
-- correctly overrides whatever text color the palette itself set.
local active_font_color_name = reaper.GetExtState(EXT_SECTION, KEYS.FONT_COLOR_NAME)
if active_font_color_name ~= "" then
  for _, p in ipairs(FONT_COLOR_PRESETS) do
    if p.name == active_font_color_name then
      apply_font_color(p)
      break
    end
  end
end

-- Run Shredder button color (Settings > Appearance > Color Palette),
-- 0xRRGGBBAA. nil = follow the palette's accent like every other
-- button. Hover/pressed shades and a readable text color are derived
-- from it, so one pick is enough.
local run_button_color = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.RUN_BUTTON_COLOR))

-- Scales each RGB channel toward white (amount > 0) or black (amount
-- < 0) by |amount| (0-1), keeping alpha.
local function shade_color(rgba, amount)
  local r = (rgba >> 24) & 0xFF
  local g = (rgba >> 16) & 0xFF
  local b = (rgba >> 8) & 0xFF
  local a = rgba & 0xFF
  local function mix(c)
    if amount >= 0 then return math.floor(c + (255 - c) * amount + 0.5) end
    return math.floor(c * (1 + amount) + 0.5)
  end
  return (mix(r) << 24) | (mix(g) << 16) | (mix(b) << 8) | a
end

-- Near-black or white, whichever reads better on `rgba`.
local function contrast_text_color(rgba)
  local r = (rgba >> 24) & 0xFF
  local g = (rgba >> 16) & 0xFF
  local b = (rgba >> 8) & 0xFF
  local luminance = 0.299 * r + 0.587 * g + 0.114 * b
  return luminance > 150 and 0x1A1A1AFF or 0xFFFFFFFF
end

-- Maps ImGui color slot NAME (as in reaper.ImGui_Col_<name>) to the
-- theme color it should use. Rebuilt fresh each time push_theme() runs
-- (not a frozen module-level table) so switching palettes at runtime
-- takes effect immediately - see apply_palette() above.
local function build_theme_map()
  return {
  WindowBg = THEME_BG,
  ChildBg = THEME_BG_ALT,
  PopupBg = THEME_BG_ALT,
  Text = THEME_TEXT,
  TextDisabled = THEME_TEXT_DISABLED,
  Border = THEME_BORDER,
  FrameBg = THEME_FRAME_BG,
  FrameBgHovered = THEME_FRAME_BG_HOVER,
  FrameBgActive = THEME_FRAME_BG_ACTIVE,
  TitleBg = THEME_BG_ALT,
  TitleBgActive = THEME_BG,
  CheckMark = THEME_ORANGE,
  SliderGrab = THEME_ORANGE,
  SliderGrabActive = THEME_ORANGE_ACTIVE,
  Button = THEME_ORANGE,
  ButtonHovered = THEME_ORANGE_HOVER,
  ButtonActive = THEME_ORANGE_ACTIVE,
  Header = THEME_FRAME_BG,
  HeaderHovered = THEME_FRAME_BG_HOVER,
  HeaderActive = THEME_ORANGE,
  Separator = THEME_BORDER,
  SeparatorHovered = THEME_ORANGE_HOVER,
  SeparatorActive = THEME_ORANGE_ACTIVE,
  Tab = THEME_BG_ALT,
  TabHovered = THEME_ORANGE_HOVER,
  TabActive = THEME_ORANGE,
  TabUnfocused = THEME_BG_ALT,
  TabUnfocusedActive = THEME_FRAME_BG,
  -- Dear ImGui 1.91+ renamed the tab slots above - both sets are listed
  -- so whichever this ReaImGui build actually has gets picked up
  -- (push_theme silently skips names that don't exist).
  TabSelected = THEME_ORANGE,
  TabSelectedOverline = THEME_ORANGE,
  TabDimmed = THEME_BG_ALT,
  TabDimmedSelected = THEME_FRAME_BG,
  TabDimmedSelectedOverline = THEME_ORANGE,
  ScrollbarBg = THEME_BG_ALT,
  ScrollbarGrab = THEME_FRAME_BG_HOVER,
  ScrollbarGrabHovered = THEME_ORANGE_HOVER,
  ScrollbarGrabActive = THEME_ORANGE_ACTIVE,
  }
end

-- Pushes every color in THEME_MAP that this ReaImGui build supports.
-- Returns how many were actually pushed, so the matching pop knows the
-- count (some slots may not exist on older builds and are skipped).
-- Defined here (rather than up with THEME_MAP) because it needs `ctx`,
-- which isn't created until below.
local push_theme, pop_theme

------------------------------------------------------------
-- Helpers (defined before first use)
------------------------------------------------------------

local function file_exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end


local ctx = reaper.ImGui_CreateContext("Antisample Shredder", reaper.ImGui_ConfigFlags_DockingEnable())

function push_theme()
  local count = 0
  for name, color in pairs(build_theme_map()) do
    local getter = reaper["ImGui_Col_" .. name]
    if getter then
      local ok, col_id = pcall(getter)
      if ok and col_id then
        local ok2 = pcall(reaper.ImGui_PushStyleColor, ctx, col_id, color)
        if ok2 then count = count + 1 end
      end
    end
  end
  return count
end

function pop_theme(count)
  if count > 0 then
    reaper.ImGui_PopStyleColor(ctx, count)
  end
end

local font_size = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.FONT_SIZE)) or 15
font_size = math.max(8, math.min(32, math.floor(font_size)))

local current_font = reaper.ImGui_CreateFont("sans-serif", font_size)
reaper.ImGui_Attach(ctx, current_font)

-- Bold variant, used for button labels in the Random FX tab. Whether
-- ReaImGui's CreateFont actually supports a bold flag for generic font
-- families varies by version/platform, so this is built defensively:
-- if the flag constant or the resulting font turns out unusable,
-- bold_font just falls back to the regular font (no crash, just not
-- visually bold).
-- Bold font attempt removed - reaper.ImGui_CreateFont only accepts 2
-- arguments in this REAPER/ReaImGui build (confirmed by a live error:
-- "expected 2 arguments maximum"), so passing a third "bold flags"
-- argument was invalid and crashed script startup. Falling back to the
-- regular font for now rather than risk another CreateFont-related
-- error - see chat for a safer alternative approach if bold text is
-- still wanted.
local bold_font = current_font

-- Shredder tab state (target cut length stored in seconds like the
-- rest of the app; the slider itself displays/edits in ms). Cut Mode
-- and Number of Cuts are two mutually-exclusive ways to decide where
-- cuts happen - not combined.
local Shredder_cut_length = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_CUT_LENGTH)) or 0.03
local Shredder_num_cuts = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_NUM_CUTS)) or 8
local Shredder_cut_mode = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_CUT_MODE)
if Shredder_cut_mode == "fibonacci" then Shredder_cut_mode = "sequence" end
if Shredder_cut_mode == "pithalgora" then Shredder_cut_mode = "pitagora" end -- v1.15 rename
local SHREDDER_VALID_CUT_MODES = {
  count = true, beat = true, euclid = true, sequence = true, onset = true, blackhole = true,
  pitagora = true, collatz = true, cantor = true, morse = true,
}
if not SHREDDER_VALID_CUT_MODES[Shredder_cut_mode] then Shredder_cut_mode = "length" end
local Shredder_mash_mode = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_MASH_MODE) ~= "0" -- default true (mash)
local Shredder_ignore_silence = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_IGNORE_SILENCE) == "1"

-- V2 additions: Beat-Synced cut mode settings, Ordered-Subset.
local Shredder_beat_division = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_BEAT_DIVISION)) or 0.25
local Shredder_beat_variance = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_BEAT_VARIANCE)) or 10
local Shredder_subset_mode = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_SUBSET_MODE) == "1"
local Shredder_subset_keep = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_SUBSET_KEEP)) or 70

-- V3 additions, bundled into one table (rather than ~20 more top-
-- level locals) to stay well clear of Lua's 200-local main-chunk
-- limit mentioned in the KEYS comment above - this file already has a
-- lot of state across its other tabs.
local SD = {
  shuffle_mode = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_SHUFFLE_MODE),
  local_window = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_LOCAL_WINDOW)) or 4,
  weighted_amount = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_WEIGHTED_AMOUNT)) or 50,
  palindrome = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_PALINDROME) == "1",

  euclid_steps = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_EUCLID_STEPS)) or 16,
  euclid_hits = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_EUCLID_HITS)) or 5,

  fib_segments = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_FIB_SEGMENTS)) or 8,
  fib_descending = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_FIB_DESCENDING) ~= "0", -- default true
  sequence_type = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_SEQUENCE_TYPE),
  sequence_custom = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_SEQUENCE_CUSTOM),

  onset_sensitivity = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_ONSET_SENSITIVITY)) or 30,

  scale_quantize = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_SCALE_QUANTIZE) == "1",
  scale_root = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_SCALE_ROOT)) or 0,
  scale_type = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_SCALE_TYPE),

  sidechain_enabled = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_SIDECHAIN_ENABLED) == "1",
  sidechain_track = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_SIDECHAIN_TRACK),
  sidechain_threshold = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_SIDECHAIN_THRESHOLD)) or 10,
  sidechain_invert = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_SIDECHAIN_INVERT) == "1",
  sidechain_drop = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_SIDECHAIN_DROP) == "1",

  -- V4: Chunk Fate diagram cache (not persisted - just re-rolls on
  -- first draw each launch). V6: show_preview now means "the popped-
  -- out Preview window is open", not an inline section.
  show_preview = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_SHOW_PREVIEW) == "1",
  preview_data = nil,
  preview_fingerprint = nil,

  -- V6: Cut Lengths chart state (preview window, section A). Item
  -- length comes from the real selected item when there is one, or a
  -- fixed fallback otherwise (v1.11) - see shredder_get_preview_
  -- item_length() - so only the computed data/fingerprint live here.
  cut_preview_data = nil,
  cut_preview_fingerprint = nil,

  -- V8: user-draggable heights for both preview drawing areas (see
  -- shredder_resize_handle() below).
  cut_chart_h = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_CUT_CHART_HEIGHT)) or 140,
  chunk_fate_h = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_CHUNK_FATE_HEIGHT)) or 240,

  -- V10: Multi-item Mash preview state (cache + resizable height).
  mash_preview_data = nil,
  mash_preview_fingerprint = nil,
  mash_preview_h = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_MASH_PREVIEW_HEIGHT)) or 220,

  -- v1.7: which view "Chunk fate" currently shows - "single" or
  -- "multi" - merged into one section with a switcher next to the
  -- title instead of two always-visible stacked sections.
  chunk_fate_view = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_CHUNK_FATE_VIEW),

  -- v1.8: Black Hole / White Hole cut mode settings. Stored in
  -- SECONDS internally (matching the engine's ShredderBlackholeStart
  -- key and the existing Cut Length pattern) - only the slider itself
  -- works in ms.
  blackhole_start = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_BLACKHOLE_START)) or 0.3,
  blackhole_decay = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_BLACKHOLE_DECAY)) or 90,
  white_hole = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_WHITE_HOLE) == "1",
  -- v1.13: default true - see the APPENDIX (V9) note in the engine
  -- file for why non-looping was a real design gap, not a preference.
  blackhole_loop = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_BLACKHOLE_LOOP) ~= "0",

  -- v1.9: Pitagora cut mode's triple selection.
  -- v1.15: falls back to the pre-rename key if the new one hasn't
  -- been set yet, so upgrading users don't lose their triple choice.
  pitagora_triple = (function()
    local v = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_PITAGORA_TRIPLE)
    if v ~= "" then return v end
    return reaper.GetExtState(EXT_SECTION, "ShredderPithalgoraTriple")
  end)(),

  -- v1.10: Collatz Cuts and Cantor Dust settings.
  collatz_seed = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_COLLATZ_SEED)) or 27,
  collatz_descending = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_COLLATZ_DESCENDING) == "1",
  cantor_depth = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_CANTOR_DEPTH)) or 3,

  -- v1.16: Morse Code Cuts settings.
  morse_text = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_MORSE_TEXT),
  morse_unit_ms = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_MORSE_UNIT_MS)) or 60,
  morse_loop = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_MORSE_LOOP) ~= "0",

  -- v1.12: Minimum Chunk Length override (global floor, most
  -- consequential for the recursive/decaying Bizarre modes).
  min_seg_override_enabled = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_MIN_SEG_OVERRIDE) == "1",
  min_seg_override_ms = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_MIN_SEG_OVERRIDE_MS)) or 10,

  -- Presets: preset_name is remembered across sessions (convenience -
  -- so the bar doesn't just say "Preset" every time you reopen the
  -- script); preset_browser_open is NOT persisted, it always starts
  -- closed, same as any other popup in this app.
  preset_name = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_PRESET_NAME),
  preset_browser_open = false,

  -- v1.21: Direction (per bipolar property: "both"/"neg"/"pos") - see
  -- the APPENDIX (V12) note in the engine file for the reasoning.
  position_direction = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_POSITION_DIRECTION),
  pitch_direction = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_PITCH_DIRECTION),
  pan_direction = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_PAN_DIRECTION),
  volume_direction = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_VOLUME_DIRECTION),
  stretch_direction = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_STRETCH_DIRECTION),

  -- v1.23: workflow/appearance preferences, not "sound" settings - not
  -- part of the preset schema, same reasoning as show_preview/font_size.
  -- hide_help_text: hides the explanatory paragraphs throughout the
  -- Shredder tab, leaving control labels themselves visible - the
  -- checkbox for this lives in the Settings tab. cut_only: Run
  -- Shredder cuts/shuffles/randomizes exactly as normal but skips the
  -- final glue, instead selecting+grouping the resulting segments and
  -- moving the edit cursor to the start of the selection - default ON.
  hide_help_text = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_HIDE_HELP_TEXT) == "1",
  cut_only = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_CUT_ONLY) ~= "0",

  -- v1.33: which Per-Segment Randomization properties the Random
  -- button (in the Shredder tab) is allowed to touch - the Settings
  -- tab's 8 checkboxes control these. Manually dragging a slider, or
  -- the Init button, are NOT affected by any of these - this only
  -- gates the Random button's own randomization pass. Default true
  -- (included) for all eight, matching the Random button's original
  -- behavior before this setting existed.
  rand_include_position = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_RAND_INCLUDE_POSITION) ~= "0",
  rand_include_rate = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_RAND_INCLUDE_RATE) ~= "0",
  rand_include_pitch = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_RAND_INCLUDE_PITCH) ~= "0",
  rand_include_pan = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_RAND_INCLUDE_PAN) ~= "0",
  rand_include_volume = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_RAND_INCLUDE_VOLUME) ~= "0",
  rand_include_reverse = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_RAND_INCLUDE_REVERSE) ~= "0",
  rand_include_repeat = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_RAND_INCLUDE_REPEAT) ~= "0",
  rand_include_mute = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_RAND_INCLUDE_MUTE) ~= "0",
  rand_include_stretch = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_RAND_INCLUDE_STRETCH) ~= "0",

  -- v1.34: naming pattern for the glued render - see the engine's
  -- expand_render_name_pattern() for the full wildcard list and how
  -- each one resolves. Not part of the preset schema - like Hide
  -- Helper Text/Disable Visuals/the Randomization Settings checkboxes,
  -- this is a workflow/output preference, not something that changes
  -- what a run sounds like.
  render_name_pattern = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_RENDER_NAME_PATTERN),

  -- v1.35: whether Number Of Repeats' duplicate copies scatter to
  -- random positions throughout the result instead of clustering
  -- right after the segment they're a copy of - this DOES change what
  -- a run sounds like, unlike the workflow prefs just above, so it's
  -- part of the preset schema (added below).
  scatter_repeats = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_SCATTER_REPEATS) == "1",

  -- v1.36: layout preferences, not sound settings - not part of the
  -- preset schema, same reasoning as Hide Helper Text/Disable Visuals.
  -- pin_position: which end of the Shredder tab Run Shredder stays
  -- fixed to while the rest scrolls in its own region - "bottom"
  -- (matches convention: fill out settings, commit at the bottom) or
  -- "top" (button always the first thing you see/reach).
  pin_position = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_PIN_POSITION),
  -- compact_mode: tighter spacing throughout the Shredder tab, for
  -- narrow docked widths or small windows.
  compact_mode = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_COMPACT_MODE) == "1",

  -- cut_length_fixed: DOES change what a run sounds like (By Cut
  -- Length becomes genuinely equal-length segments instead of +/-50%
  -- randomized around the target) - unlike its neighbors just above,
  -- this IS part of the preset schema (added below), even though it's
  -- displayed in the Settings tab rather than next to the Cut Length
  -- slider itself, per how this was asked for.
  cut_length_fixed = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_CUT_LENGTH_FIXED) == "1",

  -- Take pitch shift / time stretch mode for every segment, in
  -- REAPER's I_PITCHMODE encoding ((shifter << 16) | submode); -1 =
  -- project default. Sound-affecting, so part of the preset schema.
  pitch_mode = math.floor(tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_PITCH_MODE)) or -1),
  -- Randomized: each chunk picks randomly between Project default,
  -- elastique 3 Pro, Rrreeeaaa, and ReaReaRea instead of using pitch_mode.
  pitch_mode_random = reaper.GetExtState(EXT_SECTION, KEYS.Shredder_PITCH_MODE_RANDOM) == "1",
}
if SD.pin_position ~= "top" then SD.pin_position = "bottom" end
if SD.render_name_pattern == "" then SD.render_name_pattern = "Shredder_{number}" end
if SD.preset_name == "" then SD.preset_name = "Preset" end
shredder_snapshot_preset_baseline(shredder_read_preset_file(SD.preset_name))
local function valid_direction(d) return d == "neg" or d == "pos" or d == "both" end
if not valid_direction(SD.position_direction) then SD.position_direction = "both" end
if not valid_direction(SD.pitch_direction) then SD.pitch_direction = "both" end
if not valid_direction(SD.pan_direction) then SD.pan_direction = "both" end
if not valid_direction(SD.volume_direction) then SD.volume_direction = "both" end
if not valid_direction(SD.stretch_direction) then SD.stretch_direction = "both" end
if SD.chunk_fate_view ~= "multi" then SD.chunk_fate_view = "single" end
if SD.pitagora_triple == "" then SD.pitagora_triple = "3-4-5" end
if SD.morse_text == "" then SD.morse_text = "Welcome to Antisample Shredder" end

-- Migrate from V2's simple No-Shuffle checkbox if Shuffle Mode has
-- never been saved yet, so upgrading users don't lose their setting.
if SD.shuffle_mode == "" then
  SD.shuffle_mode = (reaper.GetExtState(EXT_SECTION, KEYS.Shredder_NO_SHUFFLE) == "1") and "none" or "full"
end
if SD.shuffle_mode ~= "none" and SD.shuffle_mode ~= "local" and SD.shuffle_mode ~= "weighted" then
  SD.shuffle_mode = "full"
end
if SD.scale_type == "" then SD.scale_type = "major" end

local SHREDDER_VALID_SEQUENCE_TYPES = {
  fibonacci = true, lucas = true, padovan = true, tribonacci = true, custom = true,
}
if not SHREDDER_VALID_SEQUENCE_TYPES[SD.sequence_type] then SD.sequence_type = "fibonacci" end
if SD.sequence_custom == "" then SD.sequence_custom = "1,1,2,3,5,8" end

-- Returns the weights list for the CURRENT SD.sequence_type/segments/
-- custom-string/descending settings, for the "Weights: ..." preview
-- caption under the Sequence controls. Defined here (after SD exists)
-- rather than up with its helper functions, since it reads SD.
local function shredder_sequence_preview_weights()
  local num_segments = math.max(2, math.floor(SD.fib_segments))
  local weights
  if SD.sequence_type == "lucas" then
    weights = shredder_lucas_sequence(num_segments)
  elseif SD.sequence_type == "padovan" then
    weights = shredder_padovan_sequence(num_segments)
  elseif SD.sequence_type == "tribonacci" then
    weights = shredder_tribonacci_sequence(num_segments)
  elseif SD.sequence_type == "custom" then
    weights = shredder_parse_custom_sequence(SD.sequence_custom)
  else
    weights = shredder_fibonacci_sequence(num_segments)
  end
  if #weights < 2 then weights = { weights[1] or 1, weights[1] or 1 } end

  if SD.fib_descending then
    local reversed = {}
    for i = 1, #weights do reversed[i] = weights[#weights - i + 1] end
    weights = reversed
  end
  return weights
end

-- Cut Lengths preview (V6/V7, real-item-length in v1.11): computes
-- one realization of actual segment DURATIONS (seconds) for the
-- current Cut Mode settings. Uses the FIRST selected item's real
-- length when one is selected (so you can actually see what a given
-- Cut Mode does to your own short/long item instead of imagining it
-- against an arbitrary stand-in), falling back to a fixed
-- SHREDDER_CUT_PREVIEW_ITEM_LEN-second hypothetical item when nothing
-- is selected. Mirrors the engine's generate_cut_positions_by_*()
-- algorithms (Antisample_Shredder_V11.lua) closely enough to be
-- structurally honest - "length" and "count" involve the engine's own
-- randomness, so this rerolls like Chunk Fate does; "euclid" and
-- "sequence" are fully deterministic given the settings, so rerolling
-- them is a no-op (that's expected, not a bug). "beat" uses the
-- project's CURRENT tempo (Master_GetTempo) rather than true tempo-
-- map-aware conversion, since there's no real item position to anchor
-- to here - fine for a preview, but the actual run can differ under a
-- tempo map. "onset" can't be previewed at all without real audio, so
-- this returns a nil durations list with an explanatory note instead.
local SHREDDER_CUT_PREVIEW_ITEM_LEN = 8 -- seconds - fallback only, see shredder_get_preview_item_length()

-- Returns (length_in_seconds, is_real_item, item_count). is_real_item
-- is false when nothing is selected (using the fixed fallback above).
-- item_count is how many items are currently selected, purely for the
-- "(+N more)" caption note when more than one is selected - only the
-- FIRST one's length is actually used.
local function shredder_get_preview_item_length()
  local count = reaper.CountSelectedMediaItems(0)
  if count > 0 then
    local item = reaper.GetSelectedMediaItem(0, 0)
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    if len and len > 0 then return len, true, count end
  end
  return SHREDDER_CUT_PREVIEW_ITEM_LEN, false, 0
end

local function compute_cut_length_preview()
  local item_pos = 0
  local item_len = select(1, shredder_get_preview_item_length())
  local MIN_SEG = SD.min_seg_override_enabled and (math.max(1, SD.min_seg_override_ms) / 1000) or 0.01

  if Shredder_cut_mode == "onset" then
    return nil, "Transient depends on the actual audio, so there's nothing meaningful to " ..
      "preview here - run Shredder to see its real cuts."
  end

  local positions = {}
  local hole_flags = nil

  if Shredder_cut_mode == "count" then
    local variance = math.max(1, math.floor(Shredder_num_cuts * 0.2))
    local num_cuts = math.max(1, Shredder_num_cuts + math.random(-variance, variance))
    local max_possible = math.floor(item_len / MIN_SEG) - 1
    num_cuts = math.min(num_cuts, math.max(0, max_possible))
    if num_cuts > 0 then
      for i = 1, num_cuts do
        positions[i] = item_pos + MIN_SEG + math.random() * (item_len - 2 * MIN_SEG)
      end
      table.sort(positions)
      for i = 2, #positions do
        if positions[i] - positions[i - 1] < MIN_SEG then
          positions[i] = positions[i - 1] + MIN_SEG
        end
      end
      local limit = item_pos + item_len - MIN_SEG
      while #positions > 0 and positions[#positions] > limit do
        table.remove(positions)
      end
    end
  elseif Shredder_cut_mode == "beat" then
    local bpm = reaper.Master_GetTempo() or 120
    local div_sec = Shredder_beat_division * (60 / bpm)
    if div_sec > 0 then
      local limit = item_pos + item_len - MIN_SEG
      local t, prev = item_pos + div_sec, item_pos
      while t <= limit do
        local tt = t
        if Shredder_beat_variance > 0 then
          local jitter = (math.random() * 2 - 1) * (div_sec * (Shredder_beat_variance / 100) * 0.5)
          tt = tt + jitter
          if tt - prev < MIN_SEG then tt = prev + MIN_SEG end
        end
        if tt > limit then break end
        table.insert(positions, tt)
        prev = tt
        t = t + div_sec
      end
    end
  elseif Shredder_cut_mode == "euclid" then
    local n = math.max(1, math.floor(SD.euclid_steps))
    local k = math.max(0, math.min(math.floor(SD.euclid_hits), n))
    local step_len = item_len / n
    if step_len >= MIN_SEG then
      local pattern, bucket = {}, 0
      for i = 1, n do
        bucket = bucket + k
        if bucket >= n then bucket = bucket - n; pattern[i] = true else pattern[i] = false end
      end
      for i = 2, n do
        if pattern[i] then table.insert(positions, item_pos + (i - 1) * step_len) end
      end
    end
  elseif Shredder_cut_mode == "sequence" then
    local weights = shredder_sequence_preview_weights()
    local total = 0
    for _, w in ipairs(weights) do total = total + w end
    if total > 0 then
      local pos = item_pos
      local limit = item_pos + item_len - MIN_SEG
      for i = 1, #weights - 1 do
        pos = pos + item_len * (weights[i] / total)
        if pos > limit then break end
        table.insert(positions, pos)
      end
    end
  elseif Shredder_cut_mode == "blackhole" then
    if SD.blackhole_start >= MIN_SEG then
      local decay = SD.blackhole_decay / 100
      local sizes = {}
      local size = SD.blackhole_start
      local total = 0
      local limit = item_len - MIN_SEG
      local max_chunks = 2000
      while total + size < limit and #sizes < max_chunks do
        table.insert(sizes, size)
        total = total + size
        size = size * decay
        if size < MIN_SEG then
          if not SD.blackhole_loop then break end
          size = SD.blackhole_start
        end
      end
      if SD.white_hole then
        local reversed = {}
        for i = 1, #sizes do reversed[i] = sizes[#sizes - i + 1] end
        sizes = reversed
      end
      local pos = item_pos
      for i = 1, #sizes do
        pos = pos + sizes[i]
        table.insert(positions, pos)
      end
    end
  elseif Shredder_cut_mode == "pitagora" then
    local triple = SD.pitagora_triple
    local a, b
    if triple == "5-12-13" then a, b = 5, 12
    elseif triple == "8-15-17" then a, b = 8, 15
    elseif triple == "7-24-25" then a, b = 7, 24
    elseif triple == "20-21-29" then a, b = 20, 21
    elseif triple == "9-40-41" then a, b = 9, 40
    else a, b = 3, 4 end
    local frac_a = a / (a + b)
    local max_cuts = 300

    local function recurse(start, len)
      if #positions >= max_cuts then return end
      if len < MIN_SEG * 2 then return end
      local len_a = len * frac_a
      local len_b = len - len_a
      if len_a < MIN_SEG or len_b < MIN_SEG then return end
      table.insert(positions, start + len_a)
      recurse(start, len_a)
      recurse(start + len_a, len_b)
    end

    recurse(item_pos, item_len)
    table.sort(positions)
  elseif Shredder_cut_mode == "collatz" then
    local weights = {}
    local n = math.max(2, math.floor(SD.collatz_seed))
    table.insert(weights, n)
    while n ~= 1 and #weights < 300 do
      if n % 2 == 0 then n = math.floor(n / 2) else n = 3 * n + 1 end
      table.insert(weights, n)
    end
    if SD.collatz_descending then
      local reversed = {}
      for i = 1, #weights do reversed[i] = weights[#weights - i + 1] end
      weights = reversed
    end
    local total = 0
    for _, w in ipairs(weights) do total = total + w end
    if total > 0 and #weights >= 2 then
      local pos = item_pos
      local limit = item_pos + item_len - MIN_SEG
      for i = 1, #weights - 1 do
        pos = pos + item_len * (weights[i] / total)
        if pos > limit then break end
        table.insert(positions, pos)
      end
    end
  elseif Shredder_cut_mode == "cantor" then
    local depth = math.max(1, math.min(7, math.floor(SD.cantor_depth)))
    local leaves = {}
    local max_leaves = 400

    local function recurse(start, len, level)
      local third = len / 3
      if level <= 0 or third < MIN_SEG or #leaves >= max_leaves then
        table.insert(leaves, { len = len, is_hole = false })
        return
      end
      recurse(start, third, level - 1)
      table.insert(leaves, { len = third, is_hole = true })
      recurse(start + third * 2, third, level - 1)
    end

    recurse(item_pos, item_len, depth)
    hole_flags = {}
    for i, leaf in ipairs(leaves) do
      hole_flags[i] = leaf.is_hole
      if i < #leaves then
        local prev_end = item_pos
        for j = 1, i do prev_end = prev_end + leaves[j].len end
        table.insert(positions, prev_end)
      end
    end
  elseif Shredder_cut_mode == "morse" then
    local symbols = shredder_morse_encode(SD.morse_text)
    if #symbols > 0 then
      local unit = math.max(MIN_SEG, SD.morse_unit_ms / 1000)
      local limit = item_len - MIN_SEG
      local max_chunks = 2000
      local durations, muted = {}, {}
      local total, idx = 0, 1

      while total < limit and #durations < max_chunks do
        local sym = symbols[idx]
        local dur = sym.units * unit
        if total + dur >= limit then break end

        table.insert(durations, dur)
        table.insert(muted, sym.muted)
        total = total + dur

        idx = idx + 1
        if idx > #symbols then
          if not SD.morse_loop then break end
          idx = 1
        end
      end

      hole_flags = muted
      local pos = item_pos
      for i = 1, #durations do
        pos = pos + durations[i]
        table.insert(positions, pos)
      end
    end
  else -- "length"
    local variance = Shredder_cut_length * 0.5
    local pos = item_pos
    local limit = item_pos + item_len - MIN_SEG
    while true do
      local seg_len = math.max(MIN_SEG, Shredder_cut_length + (math.random() * 2 - 1) * variance)
      pos = pos + seg_len
      if pos > limit then break end
      table.insert(positions, pos)
    end
  end

  local durations = {}
  local prev = item_pos
  for _, p in ipairs(positions) do
    table.insert(durations, p - prev)
    prev = p
  end
  table.insert(durations, item_pos + item_len - prev)

  if #durations > 40 then
    local trimmed = {}
    local trimmed_holes = hole_flags and {} or nil
    for i = 1, 40 do
      trimmed[i] = durations[i]
      if hole_flags then trimmed_holes[i] = hole_flags[i] end
    end
    durations = trimmed
    hole_flags = trimmed_holes
  end

  return durations, nil, hole_flags
end

-- Draws `durations` (seconds) as a simple bar chart, bars scaled
-- relative to the tallest one in the set. Bars narrower than 24px drop
-- their ms label (still visible as a bar) so long lists stay legible.
-- Drag-to-resize handle (V8) - a thin invisible strip the user can
-- drag vertically to resize a preview drawing area above it, since
-- neither preview uses a real ImGui child window (they're drawn
-- directly via DrawList into a Dummy()'d region, which has no native
-- resize affordance of its own). Draws a short grip line so it's
-- discoverable, and switches the cursor to a resize icon on hover.
-- Returns the (possibly updated) height; persists to ExtState only
-- once the drag ends, not every frame while dragging.
local function shredder_resize_handle(current_h, min_h, max_h, ext_key)
  reaper.ImGui_InvisibleButton(ctx, "##resize_" .. ext_key, -1, 8)
  local hovered = reaper.ImGui_IsItemHovered(ctx)
  local active = reaper.ImGui_IsItemActive(ctx)
  if hovered or active then
    reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeNS())
  end

  local new_h = current_h
  if active then
    local _, dy = reaper.ImGui_GetMouseDelta(ctx)
    new_h = math.max(min_h, math.min(max_h, current_h + dy))
  end
  if reaper.ImGui_IsItemDeactivated(ctx) then
    reaper.SetExtState(EXT_SECTION, ext_key, tostring(new_h), true)
  end

  local gx1, gy1 = reaper.ImGui_GetItemRectMin(ctx)
  local gx2, gy2 = reaper.ImGui_GetItemRectMax(ctx)
  local gcx, gcy = (gx1 + gx2) / 2, (gy1 + gy2) / 2
  local grip_col = (hovered or active) and THEME_TEXT or THEME_BORDER
  local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
  reaper.ImGui_DrawList_AddLine(draw_list, gcx - 15, gcy, gcx + 15, gcy, grip_col, 2)

  return new_h
end

-- `hole_flags`, when provided (Cantor Dust only), marks which bars are
-- structural silence - those get filled with STATUS_WARN_COLOR (the
-- same amber used for "muted" everywhere else in this file) so the
-- holes are visually obvious rather than looking like ordinary cuts.
local function draw_cut_lengths_chart(draw_list, ox, oy, avail_w, chart_h, durations, hole_flags)
  local margin = 4
  local usable_w = math.max(200, avail_w - margin * 2)
  local n = #durations
  if n == 0 then return end

  local gap = n > 16 and 3 or 6
  local bar_w = (usable_w - (n - 1) * gap) / n
  bar_w = math.max(6, math.min(60, bar_w))

  local max_d = 0
  for _, d in ipairs(durations) do if d > max_d then max_d = d end end
  if max_d <= 0 then max_d = 1 end

  local baseline_y = oy + chart_h
  reaper.ImGui_DrawList_AddLine(draw_list, ox + margin, baseline_y, ox + margin + usable_w, baseline_y, THEME_BORDER, 1)

  for i, d in ipairs(durations) do
    local x = ox + margin + (i - 1) * (bar_w + gap)
    local h = math.max(2, (d / max_d) * (chart_h - 20))
    local y = baseline_y - h
    local is_hole = hole_flags and hole_flags[i]
    local fill_col = is_hole and STATUS_WARN_COLOR or THEME_FRAME_BG_HOVER
    reaper.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + bar_w, baseline_y, fill_col, 2)
    reaper.ImGui_DrawList_AddRect(draw_list, x, y, x + bar_w, baseline_y, THEME_BORDER, 2, 0, 1)
    if bar_w >= 24 then
      local label = is_hole and "hole" or string.format("%.0f ms", d * 1000)
      local tw, th = reaper.ImGui_CalcTextSize(ctx, label)
      if tw <= bar_w + 10 then
        reaper.ImGui_DrawList_AddText(draw_list, x + bar_w / 2 - tw / 2, y - th - 2, THEME_TEXT_DISABLED, label)
      end
    end
  end
end

-- Per-segment randomization intensities - all "how much" sliders, see
-- the matching comment in Antisample_Shredder.lua for exactly how
-- each one is applied.
local Shredder_position_ms = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_POSITION)) or 0
local Shredder_rate = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_RATE)) or 1
local Shredder_pitch = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_PITCH)) or 0
local Shredder_pan = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_PAN)) or 0
local Shredder_volume = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_VOLUME)) or 0
local Shredder_reverse = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_REVERSE)) or 0
local Shredder_repeat = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_REPEAT)) or 0
local Shredder_mute = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_MUTE)) or 0
local Shredder_stretch = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.Shredder_STRETCH)) or 0

-- Applies one preset value to whichever standalone (non-SD) local
-- variable it belongs to - defined here, after all of them exist, so
-- it can see and reassign them as upvalues. `raw_value` is always the
-- raw STRING as read from the preset file; conversion happens inline
-- per setting, mirroring exactly how each one's own initial ExtState
-- read converts it. Falls back to leaving the variable untouched if
-- the file's value doesn't parse (e.g. a hand-edited preset file with
-- a typo) rather than silently zeroing something out.
local function shredder_apply_preset_value_to_local(key, raw_value)
  local function as_num(current)
    local n = tonumber(raw_value)
    if n then return n end
    return current
  end
  local as_bool = raw_value == "1"

  if key == KEYS.Shredder_CUT_MODE then
    local v = raw_value
    if v == "fibonacci" then v = "sequence" end
    if v == "pithalgora" then v = "pitagora" end
    if SHREDDER_VALID_CUT_MODES[v] then Shredder_cut_mode = v end
  elseif key == KEYS.Shredder_CUT_LENGTH then Shredder_cut_length = as_num(Shredder_cut_length)
  elseif key == KEYS.Shredder_NUM_CUTS then Shredder_num_cuts = as_num(Shredder_num_cuts)
  elseif key == KEYS.Shredder_MASH_MODE then Shredder_mash_mode = as_bool
  elseif key == KEYS.Shredder_IGNORE_SILENCE then Shredder_ignore_silence = as_bool
  elseif key == KEYS.Shredder_BEAT_DIVISION then Shredder_beat_division = as_num(Shredder_beat_division)
  elseif key == KEYS.Shredder_BEAT_VARIANCE then Shredder_beat_variance = as_num(Shredder_beat_variance)
  elseif key == KEYS.Shredder_SUBSET_MODE then Shredder_subset_mode = as_bool
  elseif key == KEYS.Shredder_SUBSET_KEEP then Shredder_subset_keep = as_num(Shredder_subset_keep)
  elseif key == KEYS.Shredder_POSITION then Shredder_position_ms = as_num(Shredder_position_ms)
  elseif key == KEYS.Shredder_RATE then Shredder_rate = as_num(Shredder_rate)
  elseif key == KEYS.Shredder_PITCH then Shredder_pitch = as_num(Shredder_pitch)
  elseif key == KEYS.Shredder_PAN then Shredder_pan = as_num(Shredder_pan)
  elseif key == KEYS.Shredder_VOLUME then Shredder_volume = as_num(Shredder_volume)
  elseif key == KEYS.Shredder_REVERSE then Shredder_reverse = as_num(Shredder_reverse)
  elseif key == KEYS.Shredder_REPEAT then Shredder_repeat = as_num(Shredder_repeat)
  elseif key == KEYS.Shredder_MUTE then Shredder_mute = as_num(Shredder_mute)
  elseif key == KEYS.Shredder_STRETCH then Shredder_stretch = as_num(Shredder_stretch)
  end
end

-- Applies one preset value to an SD-table field - generic, since SD
-- is addressable by string key (unlike the standalone locals above).
local function shredder_apply_preset_value_to_sd(sd_field, kind, raw_value)
  if kind == "num" then
    local n = tonumber(raw_value)
    if n then SD[sd_field] = n end
  elseif kind == "bool" then
    SD[sd_field] = (raw_value == "1")
  else
    SD[sd_field] = raw_value
  end
end

-- Loads a preset by name: reads its file, and for every schema entry
-- found in it, writes the value to BOTH ExtState (so it's still there
-- next session) and whichever live variable actually drives the UI
-- (so the change is visible immediately, no restart needed). Missing
-- keys in the file (e.g. an older preset saved before some setting
-- existed) are simply left as whatever they currently are - loading a
-- preset never resets things the preset itself doesn't mention.
-- Returns true on success, false if the preset file couldn't be read.
local function shredder_load_preset(name)
  local values = shredder_read_preset_file(name)
  if not values then return false end

  for _, entry in ipairs(SHREDDER_PRESET_SCHEMA) do
    local raw = values[entry.key]
    if raw ~= nil then
      reaper.SetExtState(EXT_SECTION, entry.key, raw, true)
      if entry.sd then
        shredder_apply_preset_value_to_sd(entry.sd, entry.kind, raw)
      else
        shredder_apply_preset_value_to_local(entry.key, raw)
      end
    end
  end

  SD.preset_name = name
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_PRESET_NAME, name, true)
  shredder_snapshot_preset_baseline()
  return true
end

-- Loads a uniformly-random preset from whatever's currently saved.
-- Returns the name loaded, or nil if there are no presets yet.
local function shredder_load_random_preset()
  local names = shredder_list_presets()
  if #names == 0 then return nil end
  local pick = names[math.random(#names)]
  shredder_load_preset(pick)
  return pick
end

local new_group_name = ""
local status = "Ready."
local status_warn = false

local function set_status(text, warn)
  status = text
  status_warn = warn or false
end

-- Remembered window size (persisted across sessions).
local win_w = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.WIN_W)) or 480
local win_h = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.WIN_H)) or 620
local last_win_w, last_win_h = win_w, win_h

-- Last known dock state (REAPER's own docker, not ImGui's internal
-- multi-window docking) - restored on launch, then tracked each frame
-- so it survives closing/reopening the script. 0 = not docked.
local dock_id = tonumber(reaper.GetExtState(EXT_SECTION, KEYS.DOCK_ID)) or 0
local last_dock_id = dock_id

-- Search/filter text for the manual-add FX list (FX Groups tab).
local manual_add_filter = ""

local function run_script(path, display_name)
  if not file_exists(path) then
    set_status("Missing: " .. display_name, true)
    reaper.ShowMessageBox(
      "Could not find:\n\n" .. path ..
      "\n\nPut the required Antisample scripts in the same folder as this UI script.",
      "Antisample Shredder",
      0
    )
    return
  end

  local ok, err = pcall(dofile, path)

  if ok then
    set_status("Ran: " .. display_name, false)
  else
    set_status("Error in " .. display_name, true)
    reaper.ShowMessageBox(
      "The script returned an error:\n\n" .. tostring(err),
      "Antisample Shredder",
      0
    )
  end
end


local function set_font_size(new_size)
  new_size = math.max(8, math.min(32, math.floor(new_size)))
  if new_size == font_size then return end
  font_size = new_size
  reaper.SetExtState(EXT_SECTION, KEYS.FONT_SIZE, tostring(font_size), true)
  set_status("Font size set to " .. font_size .. ".", false)
end


------------------------------------------------------------
-- Chunk Preview (V4) - a live diagram (drawn via ReaImGui's DrawList
-- API, no image files) simulating SHREDDER_PREVIEW_N demo chunks
-- through the CURRENT Structural Mode settings above (drop, shuffle,
-- repeat, palindrome, reverse, mute), so you can see the shape of a
-- run before spending it on real audio. Mirrors the actual engine's
-- algorithms (shuffle_copy/local_shuffle/weighted_shuffle/expand_with_
-- repeats/apply_palindrome in Antisample_Shredder_V11.lua) closely
-- enough to be structurally honest, but this is a separate, simpler
-- copy living only in the UI - it never touches real items. Sidechain
-- dropping isn't simulated here (it depends on actual audio); only
-- Ordered-Subset's keep/drop is.
------------------------------------------------------------

local SHREDDER_PREVIEW_N = 6

-- Multi-item Mash preview (V10) demo shape: 2 demo items, N chunks
-- each - see build_mash_preview()/draw_mash_preview() below.
local SHREDDER_MASH_ITEMS = 2
local SHREDDER_MASH_PER_ITEM = 4
local SHREDDER_MASH_TOTAL = SHREDDER_MASH_ITEMS * SHREDDER_MASH_PER_ITEM

local function shredder_preview_shuffle_copy(t)
  local copy = {}
  for i, v in ipairs(t) do copy[i] = v end
  for i = #copy, 2, -1 do
    local j = math.random(i)
    copy[i], copy[j] = copy[j], copy[i]
  end
  return copy
end

local function shredder_preview_local_shuffle(t, window)
  window = math.max(2, math.floor(window))
  local result = {}
  local i = 1
  local n = #t
  while i <= n do
    local j = math.min(i + window - 1, n)
    local group = {}
    for idx = i, j do table.insert(group, t[idx]) end
    group = shredder_preview_shuffle_copy(group)
    for _, v in ipairs(group) do table.insert(result, v) end
    i = j + 1
  end
  return result
end

local function shredder_preview_weighted_shuffle(t, amount_percent)
  local n = #t
  if n <= 1 then return t end
  local amount = math.max(0, math.min(100, amount_percent)) / 100
  local keyed = {}
  for i, v in ipairs(t) do
    local jitter = (math.random() * 2 - 1) * amount * n
    keyed[i] = { v = v, key = i + jitter }
  end
  table.sort(keyed, function(a, b) return a.key < b.key end)
  local result = {}
  for i, k in ipairs(keyed) do result[i] = k.v end
  return result
end

-- Builds one random preview outcome from the current settings. Pure
-- data - no drawing here, so it's cheap to rebuild only when settings
-- actually change (see the fingerprint check in the Shredder tab).
local function build_shredder_preview()
  local originals = {}
  for i = 1, SHREDDER_PREVIEW_N do originals[i] = i end

  local dropped, kept = {}, {}
  if Shredder_subset_mode then
    for _, i in ipairs(originals) do
      if math.random() * 100 < Shredder_subset_keep then
        table.insert(kept, i)
      else
        table.insert(dropped, i)
      end
    end
    if #kept == 0 then table.insert(kept, table.remove(dropped)) end
  else
    kept = originals
  end

  -- Ordered-Subset always preserves order, same as the real engine.
  local order
  if Shredder_subset_mode then
    order = kept
  elseif SD.shuffle_mode == "none" then
    order = kept
  elseif SD.shuffle_mode == "local" then
    order = shredder_preview_local_shuffle(kept, SD.local_window)
  elseif SD.shuffle_mode == "weighted" then
    order = shredder_preview_weighted_shuffle(kept, SD.weighted_amount)
  else
    order = shredder_preview_shuffle_copy(kept)
  end

  local final = {}
  for _, i in ipairs(order) do
    table.insert(final, { orig = i, mark = "" })
    -- Capped at 3 extra (rather than the real Number Of Repeats' full
    -- 0-20 range) purely so the preview boxes stay legible.
    local repeat_count = math.random(0, math.min(Shredder_repeat, 3))
    for _ = 1, repeat_count do
      table.insert(final, { orig = i, mark = "+" })
    end
  end
  if #final > 14 then
    local trimmed = {}
    for i = 1, 14 do trimmed[i] = final[i] end
    final = trimmed
  end

  if SD.palindrome and #final > 1 then
    for i = #final - 1, 1, -1 do
      table.insert(final, { orig = final[i].orig, mark = "~" })
    end
  end
  if #final > 20 then
    local trimmed = {}
    for i = 1, 20 do trimmed[i] = final[i] end
    final = trimmed
  end

  for _, seg in ipairs(final) do
    seg.reversed = math.random() * 100 < Shredder_reverse
    seg.muted = math.random() * 100 < Shredder_mute
    -- Continuous properties: a random 0-1 magnitude ("how much of the
    -- available range this chunk happened to get") when that
    -- property's intensity slider is above its neutral value, or
    -- always 0 (an always-flat marker) when the slider is off - this
    -- mirrors the real engine only touching a property at all once
    -- its intensity is non-zero (or, for Rate, above 1x).
    seg.position_mag = Shredder_position_ms > 0 and math.random() or 0
    seg.rate_mag = Shredder_rate > 1 and math.random() or 0
    seg.pitch_mag = Shredder_pitch > 0 and math.random() or 0
    seg.pan_mag = Shredder_pan > 0 and math.random() or 0
    seg.volume_mag = Shredder_volume > 0 and math.random() or 0
  end

  return { originals = originals, dropped = dropped, final = final }
end

-- Multi-item Mash preview (V10): builds SHREDDER_MASH_ITEMS demo
-- items of SHREDDER_MASH_PER_ITEM chunks each (labeled A1-A4, B1-B4),
-- then shows what your CURRENT "Mode: Mash Together"/"Process
-- Individually" button setting (Shredder_mash_mode) would do with
-- them - mirrors the real engine's process_mashup()/process_single_
-- item() dispatch (Antisample_Shredder_V11.lua) at the structural
-- level: mash mode pools every item's chunks into one ordered list
-- and reorders across the WHOLE pool; individual mode reorders each
-- item's chunks independently, and they never cross into each other's
-- slots. Uses the same Shuffle Mode / Ordered-Subset rules as Chunk
-- Fate above (Ordered-Subset always preserves order; otherwise
-- whichever Shuffle Mode is selected). Simplified relative to Chunk
-- Fate on purpose - no repeats/palindrome/reverse/mute markers here,
-- since this section's whole point is the cross-item mixing question,
-- not re-covering ground the Chunk Fate section already covers.
local function build_mash_preview()
  local chunks = {}
  local letters = { "A", "B" }
  for item = 1, SHREDDER_MASH_ITEMS do
    for c = 1, SHREDDER_MASH_PER_ITEM do
      table.insert(chunks, { item = item, label = letters[item] .. c })
    end
  end

  local function apply_order(list)
    if Shredder_subset_mode then return list end
    if SD.shuffle_mode == "none" then return list end
    if SD.shuffle_mode == "local" then return shredder_preview_local_shuffle(list, SD.local_window) end
    if SD.shuffle_mode == "weighted" then return shredder_preview_weighted_shuffle(list, SD.weighted_amount) end
    return shredder_preview_shuffle_copy(list)
  end

  if Shredder_mash_mode then
    return { mash = true, chunks = chunks, order = apply_order(chunks) }
  end

  local per_item = {}
  for item = 1, SHREDDER_MASH_ITEMS do
    local item_chunks = {}
    for _, c in ipairs(chunks) do
      if c.item == item then table.insert(item_chunks, c) end
    end
    per_item[item] = apply_order(item_chunks)
  end
  return { mash = false, chunks = chunks, per_item = per_item }
end

-- Draws `data` from build_mash_preview() above. Both rows share the
-- SAME fixed slot positions (computed once for SHREDDER_MASH_TOTAL
-- chunks) - in mash mode the Final row's chunks are free to land in
-- ANY slot regardless of origin item; in individual mode each item's
-- chunks are confined to that item's own original slots, which is
-- what visually proves nothing crosses between items.
local function draw_mash_preview(draw_list, ox, oy, avail_w, scale, data)
  local margin = 4
  local usable_w = math.max(200, avail_w - margin * 2)
  local box_h = 30 * scale
  local row1_y = oy + 30 * scale
  local row2_y = row1_y + box_h + 60 * scale

  local gap = 6 * scale
  local box_w = (usable_w - (SHREDDER_MASH_TOTAL - 1) * gap) / SHREDDER_MASH_TOTAL
  box_w = math.max(14, math.min(70 * scale, box_w))

  local function item_color(item)
    return item == 1 and MARKER_ITEM_A or MARKER_ITEM_B
  end

  local function draw_box(x, y, col, label)
    reaper.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + box_w, y + box_h, THEME_FRAME_BG_HOVER, 4)
    reaper.ImGui_DrawList_AddRect(draw_list, x, y, x + box_w, y + box_h, col, 4, 0, 2)
    if box_w >= 16 then
      local tw, th = reaper.ImGui_CalcTextSize(ctx, label)
      reaper.ImGui_DrawList_AddText(draw_list, x + box_w / 2 - tw / 2, y + box_h / 2 - th / 2, THEME_TEXT, label)
    end
  end

  reaper.ImGui_DrawList_AddText(draw_list, ox + margin, oy, THEME_TEXT_DISABLED, "Original (per item)")
  reaper.ImGui_DrawList_AddText(
    draw_list, ox + margin, row2_y - 22 * scale, THEME_TEXT_DISABLED,
    data.mash and "Final - mashed into ONE item" or "Final - each item stays SEPARATE")

  local slot_x = {}
  for idx, c in ipairs(data.chunks) do
    local x = ox + margin + (idx - 1) * (box_w + gap)
    slot_x[idx] = x
    draw_box(x, row1_y, item_color(c.item), c.label)
  end

  local a_cx = (slot_x[1] + slot_x[SHREDDER_MASH_PER_ITEM] + box_w) / 2
  local b_cx = (slot_x[SHREDDER_MASH_PER_ITEM + 1] + slot_x[SHREDDER_MASH_TOTAL] + box_w) / 2
  reaper.ImGui_DrawList_AddText(draw_list, a_cx - 20 * scale, row1_y - 16 * scale, MARKER_ITEM_A, "Item A")
  reaper.ImGui_DrawList_AddText(draw_list, b_cx - 20 * scale, row1_y - 16 * scale, MARKER_ITEM_B, "Item B")

  local final_x = {}
  if data.mash then
    for idx, c in ipairs(data.order) do
      local x = slot_x[idx]
      draw_box(x, row2_y, item_color(c.item), c.label)
      final_x[c.label] = x + box_w / 2
    end
  else
    for item = 1, SHREDDER_MASH_ITEMS do
      local base_idx = (item - 1) * SHREDDER_MASH_PER_ITEM
      for i, c in ipairs(data.per_item[item]) do
        local x = slot_x[base_idx + i]
        draw_box(x, row2_y, item_color(c.item), c.label)
        final_x[c.label] = x + box_w / 2
      end
    end
  end

  for idx, c in ipairs(data.chunks) do
    local x1, y1 = slot_x[idx] + box_w / 2, row1_y + box_h
    local x2 = final_x[c.label]
    if x2 then
      local mid_y = (y1 + row2_y) / 2
      reaper.ImGui_DrawList_AddBezierCubic(draw_list, x1, y1, x1, mid_y, x2, mid_y, x2, row2_y, THEME_BORDER, 1, 0)
    end
  end
end

-- Draws `data` starting at screen position (ox, oy), sized to fit
-- `avail_w`, scaled by `scale` (1.0 = original size; the caller derives
-- this from SD.chunk_fate_h / 240 and also pushes a matching bigger
-- font before calling this, so text grows too - see the call site).
-- Uses the file's existing THEME_*/MARKER_* colors, so the box colors
-- automatically follow whichever palette is active (marker colors are
-- fixed accents, like reversed/muted always were). Boxes narrower than
-- 16px drop their number label; the per-segment marker row (below
-- each Final order box) only draws when that box is wide enough
-- (>=24*scale px) to be legible, and each of the 7 bars spans an
-- equal share of that box's own width (edge to edge) rather than a
-- small fixed-width cluster, so wider boxes get proportionally wider
-- (more legible) marker bars automatically.
local function draw_shredder_preview(draw_list, ox, oy, avail_w, scale, data)
  local margin = 4
  local usable_w = math.max(200, avail_w - margin * 2)
  local box_h = 34 * scale

  local row1_y = oy + 34 * scale
  local row2_y = row1_y + box_h + 80 * scale
  local markers_baseline_y = row2_y + box_h + 24 * scale
  local marker_max_h = 16 * scale

  local function layout(count)
    local gap = count > 10 and 4 or 8
    local box_w = (usable_w - (count - 1) * gap) / count
    box_w = math.max(12, math.min(80 * scale, box_w))
    return box_w, gap
  end

  reaper.ImGui_DrawList_AddText(draw_list, ox + margin, oy, THEME_TEXT_DISABLED, "Original")
  reaper.ImGui_DrawList_AddText(draw_list, ox + margin, row2_y - 26 * scale, THEME_TEXT_DISABLED, "Final order")

  local is_dropped = {}
  for _, d in ipairs(data.dropped) do is_dropped[d] = true end

  local box_w1, gap1 = layout(#data.originals)
  local row1_x_center = {}
  for idx, num in ipairs(data.originals) do
    local x = ox + margin + (idx - 1) * (box_w1 + gap1)
    local fill_col = is_dropped[num] and THEME_FRAME_BG or THEME_FRAME_BG_HOVER
    local text_col = is_dropped[num] and THEME_TEXT_DISABLED or THEME_TEXT
    reaper.ImGui_DrawList_AddRectFilled(draw_list, x, row1_y, x + box_w1, row1_y + box_h, fill_col, 4)
    reaper.ImGui_DrawList_AddRect(draw_list, x, row1_y, x + box_w1, row1_y + box_h, THEME_BORDER, 4, 0, 1)
    if box_w1 >= 16 then
      local label = tostring(num)
      local tw, th = reaper.ImGui_CalcTextSize(ctx, label)
      reaper.ImGui_DrawList_AddText(draw_list, x + box_w1 / 2 - tw / 2, row1_y + box_h / 2 - th / 2, text_col, label)
    end
    row1_x_center[num] = x + box_w1 / 2
  end

  -- Fixed order/colors for the 7-property marker row: each is a small
  -- bar whose height is that segment's rolled magnitude (0 = flat/
  -- absent, full height = maxed out) - reversed/muted are just 0 or 1.
  local MARKERS = {
    { key = "reversed",    color = THEME_ORANGE,   binary = true },
    { key = "muted",       color = STATUS_WARN_COLOR, binary = true },
    { key = "position_mag", color = MARKER_POSITION },
    { key = "rate_mag",     color = MARKER_RATE },
    { key = "pitch_mag",    color = MARKER_PITCH },
    { key = "pan_mag",      color = MARKER_PAN },
    { key = "volume_mag",   color = MARKER_VOLUME },
  }
  local marker_gap = 1 * scale

  local box_w2, gap2 = layout(#data.final)
  local first_occurrence_x = {}
  for idx, seg in ipairs(data.final) do
    local x = ox + margin + (idx - 1) * (box_w2 + gap2)
    local cx = x + box_w2 / 2
    if seg.mark == "" and not first_occurrence_x[seg.orig] then
      first_occurrence_x[seg.orig] = cx
    end

    reaper.ImGui_DrawList_AddRectFilled(draw_list, x, row2_y, x + box_w2, row2_y + box_h, THEME_FRAME_BG_HOVER, 4)
    reaper.ImGui_DrawList_AddRect(draw_list, x, row2_y, x + box_w2, row2_y + box_h, THEME_BORDER, 4, 0, 1)
    if box_w2 >= 16 then
      local label = tostring(seg.orig) .. seg.mark
      local tw, th = reaper.ImGui_CalcTextSize(ctx, label)
      reaper.ImGui_DrawList_AddText(draw_list, x + box_w2 / 2 - tw / 2, row2_y + box_h / 2 - th / 2, THEME_TEXT, label)
    end

    if box_w2 >= 24 * scale then
      -- Bars span the FULL width of this box (edge to edge), rather
      -- than a small fixed-width cluster centered under it - each of
      -- the 7 markers gets an equal share of box_w2.
      local total_gap = (#MARKERS - 1) * marker_gap
      local marker_bar_w = math.max(1, (box_w2 - total_gap) / #MARKERS)
      for mi, marker in ipairs(MARKERS) do
        local mag = marker.binary and (seg[marker.key] and 1 or 0) or seg[marker.key]
        if mag > 0 then
          local mx = x + (mi - 1) * (marker_bar_w + marker_gap)
          local mh = math.max(2, mag * marker_max_h)
          reaper.ImGui_DrawList_AddRectFilled(
            draw_list, mx, markers_baseline_y - mh, mx + marker_bar_w, markers_baseline_y, marker.color, 1)
        end
      end
    end
  end

  for _, num in ipairs(data.originals) do
    if not is_dropped[num] and first_occurrence_x[num] then
      local x1, y1 = row1_x_center[num], row1_y + box_h
      local x2, y2 = first_occurrence_x[num], row2_y
      local mid_y = (y1 + y2) / 2
      reaper.ImGui_DrawList_AddBezierCubic(
        draw_list, x1, y1, x1, mid_y, x2, mid_y, x2, y2, THEME_BORDER, 1, 0)
    end
  end
end

-- Draws <-, <->, -> direction buttons right after a slider (which
-- must have been given a hidden "##..." label and an explicit width
-- reserving room for this, at the call site - see the Direction
-- comment above the Position slider for the exact pattern), then the
-- slider's own visible label text after the buttons - so the reading
-- order is [slider][buttons][label], not [slider][label][buttons].
-- The currently-active direction is highlighted in THEME_ORANGE_ACTIVE
-- (the darkest of the three orange shades this app already has -
-- deliberately darker than a plain hover/idle button so "this one is
-- selected" actually reads at a glance, not just plain THEME_ORANGE).
-- `sd_field` is the SD table field holding "both"/"neg"/"pos";
-- `ext_key` is its ExtState key (via KEYS). Updates SD/ExtState
-- directly on click - no return value needed.
-- Draws explanatory/helper text (as opposed to a live computed
-- preview, a warning, or a control's own label) - a thin wrapper
-- around TextWrapped that does nothing at all when SD.hide_help_text
-- is on, so the Settings tab's "Hide helper text" option can hide
-- every one of these at once without touching control labels
-- themselves, which are drawn separately and never go through this.
local function shredder_help_text(ctx_, text)
  if SD.hide_help_text then return end
  reaper.ImGui_TextWrapped(ctx_, text)
end

-- A vertical gap between major sections of the Shredder tab, sized
-- down when Compact Mode is on - `large` picks which of two rough
-- sizes (a section-to-section gap vs. a smaller within-section one),
-- Compact Mode just scales both down rather than having a separate
-- size table to keep in sync.
local function shredder_gap(large)
  local h = large and 8 or 4
  if SD.compact_mode then h = large and 4 or 2 end
  reaper.ImGui_Dummy(ctx, 0, h)
end

-- Resets EVERY sound-affecting Shredder setting back to its documented
-- default - Cut Mode and every mode-specific param, Structural Modes,
-- Per-Segment Randomization, Multi-item mode - not just the eight
-- per-segment sliders the original Init scope covered. Every value
-- here was cross-checked directly against each field's own live `or
-- <default>` fallback (or its post-load validation, for the handful
-- that resolve an empty string to a sensible default rather than
-- carrying a literal fallback inline) rather than re-guessed from
-- memory, so this matches exactly what a fresh install already
-- produces for each one.
local function shredder_init_everything()
  Shredder_cut_mode = "length"
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_CUT_MODE, "length", true)
  Shredder_cut_length = 0.03
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_CUT_LENGTH, "0.03", true)
  Shredder_num_cuts = 8
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_NUM_CUTS, "8", true)
  Shredder_mash_mode = true
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_MASH_MODE, "1", true)
  Shredder_ignore_silence = false
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_IGNORE_SILENCE, "0", true)
  Shredder_beat_division = 0.25
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_BEAT_DIVISION, "0.25", true)
  Shredder_beat_variance = 10
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_BEAT_VARIANCE, "10", true)
  Shredder_subset_mode = false
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SUBSET_MODE, "0", true)
  Shredder_subset_keep = 70
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SUBSET_KEEP, "70", true)

  Shredder_position_ms, Shredder_rate, Shredder_pitch, Shredder_pan = 0, 1, 0, 0
  Shredder_volume, Shredder_reverse, Shredder_repeat, Shredder_mute = 0, 0, 0, 0
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_POSITION, "0", true)
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_RATE, "1", true)
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_PITCH, "0", true)
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_PAN, "0", true)
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_VOLUME, "0", true)
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_REVERSE, "0", true)
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_REPEAT, "0", true)
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_MUTE, "0", true)
  Shredder_stretch = 0
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_STRETCH, "0", true)

  -- "full" here, NOT "" - the dropdown's "Full Shuffle" entry has an
  -- explicit literal value ("full"), unlike sequence_type/scale_type
  -- where "" is a safe, direct default sentinel. An empty string here
  -- instead sends the ENGINE down a legacy backward-compat path (an
  -- old "ShredderNoShuffle" boolean flag, from before Shuffle Mode was
  -- a multi-option dropdown) that can silently resolve to "none"
  -- depending on that unrelated flag's own stale ExtState value - a
  -- real bug this was, not hypothetical: writing "" here is exactly
  -- what caused Init to silently leave Shredder shuffling off even
  -- though the UI displayed "Full Shuffle" as selected the whole time.
  SD.shuffle_mode = "full"
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SHUFFLE_MODE, "full", true)
  SD.local_window = 4
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_LOCAL_WINDOW, "4", true)
  SD.weighted_amount = 50
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_WEIGHTED_AMOUNT, "50", true)
  SD.palindrome = false
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_PALINDROME, "0", true)
  SD.euclid_steps = 16
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_EUCLID_STEPS, "16", true)
  SD.euclid_hits = 5
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_EUCLID_HITS, "5", true)
  SD.fib_segments = 8
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_FIB_SEGMENTS, "8", true)
  SD.fib_descending = true
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_FIB_DESCENDING, "1", true)
  SD.sequence_type = ""
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SEQUENCE_TYPE, "", true)
  SD.sequence_custom = ""
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SEQUENCE_CUSTOM, "", true)
  SD.onset_sensitivity = 30
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_ONSET_SENSITIVITY, "30", true)
  SD.scale_quantize = false
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SCALE_QUANTIZE, "0", true)
  SD.scale_root = 0
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SCALE_ROOT, "0", true)
  SD.scale_type = ""
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SCALE_TYPE, "", true)
  SD.sidechain_enabled = false
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SIDECHAIN_ENABLED, "0", true)
  SD.sidechain_track = ""
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SIDECHAIN_TRACK, "", true)
  SD.sidechain_threshold = 10
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SIDECHAIN_THRESHOLD, "10", true)
  SD.sidechain_invert = false
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SIDECHAIN_INVERT, "0", true)
  SD.sidechain_drop = false
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SIDECHAIN_DROP, "0", true)
  SD.blackhole_start = 0.3
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_BLACKHOLE_START, "0.3", true)
  SD.blackhole_decay = 90
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_BLACKHOLE_DECAY, "90", true)
  SD.white_hole = false
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_WHITE_HOLE, "0", true)
  SD.blackhole_loop = true
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_BLACKHOLE_LOOP, "1", true)
  SD.pitagora_triple = "3-4-5"
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_PITAGORA_TRIPLE, "3-4-5", true)
  SD.collatz_seed = 27
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_COLLATZ_SEED, "27", true)
  SD.collatz_descending = false
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_COLLATZ_DESCENDING, "0", true)
  SD.cantor_depth = 3
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_CANTOR_DEPTH, "3", true)
  SD.morse_text = "Shredder"
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_MORSE_TEXT, "Shredder", true)
  SD.morse_unit_ms = 60
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_MORSE_UNIT_MS, "60", true)
  SD.morse_loop = true
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_MORSE_LOOP, "1", true)
  SD.min_seg_override_enabled = false
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_MIN_SEG_OVERRIDE, "0", true)
  SD.min_seg_override_ms = 10
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_MIN_SEG_OVERRIDE_MS, "10", true)
  SD.position_direction = "both"
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_POSITION_DIRECTION, "both", true)
  SD.pitch_direction = "both"
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_PITCH_DIRECTION, "both", true)
  SD.pan_direction = "both"
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_PAN_DIRECTION, "both", true)
  SD.volume_direction = "both"
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_VOLUME_DIRECTION, "both", true)
  SD.stretch_direction = "both"
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_STRETCH_DIRECTION, "both", true)
  SD.scatter_repeats = false
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SCATTER_REPEATS, "0", true)
  SD.cut_length_fixed = false
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_CUT_LENGTH_FIXED, "0", true)
  SD.pitch_mode = -1
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_PITCH_MODE, "-1", true)
  SD.pitch_mode_random = false
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_PITCH_MODE_RANDOM, "0", true)

  SD.preset_name = "Init"
  reaper.SetExtState(EXT_SECTION, KEYS.Shredder_PRESET_NAME, SD.preset_name, true)
  shredder_snapshot_preset_baseline()

  set_status("Init: every Shredder setting reset to default.", false)
end

-- The Run Shredder button itself - a standalone function so it can be
-- called from either end of the Shredder tab depending on
-- SD.pin_position ("top" or "bottom"), rather than duplicating this
-- block or fighting over where in the source it physically sits.
-- Uses run_button_color when one is set in Settings, otherwise the
-- palette's normal button colors.
local function shredder_run_button()
  if run_button_color then
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), run_button_color)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), shade_color(run_button_color, 0.15))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), shade_color(run_button_color, -0.2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), contrast_text_color(run_button_color))
  end

  if reaper.ImGui_Button(ctx, "Run Shredder", -1, 50) then
    run_script(SCRIPT_SHREDDER, "Antisample_Shredder_Engine.lua")
  end

  if run_button_color then
    reaper.ImGui_PopStyleColor(ctx, 4)
  end
end

-- Draws a slider's trailing label. Plain text - the near-max RGB
-- channel-split effect this used to have was removed per feedback
-- that the animation-family features weren't earning their keep long
-- term. Keeps the same (text, value, min_val, max_val) signature all
-- eight Per-Segment Randomization sliders already call it with, even
-- though value/min_val/max_val go unused now, so none of those call
-- sites need to change - only this function's body did.
local function shredder_slider_label(text, value, min_val, max_val)
  reaper.ImGui_Text(ctx, text)
end

-- Pitch shift / time stretch modes as REAPER itself reports them (so
-- the list always matches this install - elastique, Rubber Band, etc.),
-- enumerated once and cached. Each entry: id (shifter index, the high
-- 16 bits of I_PITCHMODE), name, subs (submode names), sub_items (the
-- "\0"-joined Combo string for those submodes).
local shredder_pitch_modes_cache = nil
local function shredder_get_pitch_modes()
  if shredder_pitch_modes_cache then return shredder_pitch_modes_cache end
  local list = {}
  if reaper.EnumPitchShiftModes then
    for i = 0, 255 do
      local ok, name = reaper.EnumPitchShiftModes(i)
      if not ok then break end
      if name and name ~= "" then
        local subs = {}
        if reaper.EnumPitchShiftSubModes then
          for s = 0, 4095 do
            local sub = reaper.EnumPitchShiftSubModes(i, s)
            if not sub or sub == "" then break end
            subs[#subs + 1] = sub
          end
        end
        list[#list + 1] = { id = i, name = name, subs = subs, sub_items = table.concat(subs, "\0") .. "\0" }
      end
    end
  end
  local names = { "Project default" }
  for _, m in ipairs(list) do names[#names + 1] = m.name end
  shredder_pitch_modes_cache = { list = list, items = table.concat(names, "\0") .. "\0" }
  return shredder_pitch_modes_cache
end

local function shredder_direction_buttons(sd_field, ext_key, label_text, value, min_val, max_val)
  local current = SD[sd_field]
  local btn_w = 28

  local function dir_button(label, value)
    local active = (current == value)
    if active then
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), THEME_ORANGE_ACTIVE)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), THEME_ORANGE_ACTIVE)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), THEME_ORANGE_ACTIVE)
    end
    if reaper.ImGui_Button(ctx, label .. "##dir_" .. ext_key .. "_" .. value, btn_w, 0) then
      SD[sd_field] = value
      reaper.SetExtState(EXT_SECTION, ext_key, value, true)
    end
    if active then
      reaper.ImGui_PopStyleColor(ctx, 3)
    end
  end

  reaper.ImGui_SameLine(ctx, 0, 10)
  dir_button("<-", "neg")
  reaper.ImGui_SameLine(ctx, 0, 2)
  dir_button("<->", "both")
  reaper.ImGui_SameLine(ctx, 0, 2)
  dir_button("->", "pos")
  reaper.ImGui_SameLine(ctx, 0, 8)
  if value and min_val and max_val then
    shredder_slider_label(label_text, value, min_val, max_val)
  else
    reaper.ImGui_Text(ctx, label_text)
  end
end


------------------------------------------------------------
-- UI
------------------------------------------------------------

local function draw()
  

  reaper.ImGui_PushFont(ctx, current_font, font_size)
  local theme_count = push_theme()

  reaper.ImGui_SetNextWindowSize(ctx, win_w, win_h, reaper.ImGui_Cond_FirstUseEver())
  reaper.ImGui_SetNextWindowDockID(ctx, dock_id, reaper.ImGui_Cond_FirstUseEver())

  -- Suppress ImGui's own title bar while docked - REAPER's docker
  -- already shows a tab with the window name, so the internal title
  -- bar becomes a redundant blank strip (visible as a gap at the top).
  -- Based on the PREVIOUS frame's dock state, since flags must be
  -- decided before Begin() reveals this frame's docking.
  local begin_flags = 0
  if dock_id < 0 then
    begin_flags = reaper.ImGui_WindowFlags_NoTitleBar()
  end

  local visible, open = reaper.ImGui_Begin(ctx, "Antisample Shredder", true, begin_flags)

  if visible then

    local cur_w, cur_h = reaper.ImGui_GetWindowSize(ctx)
    if cur_w ~= last_win_w or cur_h ~= last_win_h then
      last_win_w, last_win_h = cur_w, cur_h
      win_w, win_h = cur_w, cur_h
      reaper.SetExtState(EXT_SECTION, KEYS.WIN_W, tostring(win_w), true)
      reaper.SetExtState(EXT_SECTION, KEYS.WIN_H, tostring(win_h), true)
    end

    local cur_dock_id = reaper.ImGui_GetWindowDockID(ctx)
    if cur_dock_id ~= last_dock_id then
      last_dock_id = cur_dock_id
      dock_id = cur_dock_id
      reaper.SetExtState(EXT_SECTION, KEYS.DOCK_ID, tostring(dock_id), true)
    end

    reaper.ImGui_PushFont(ctx, current_font, font_size + 5)
    reaper.ImGui_Text(ctx, "Antisample Shredder")
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_Dummy(ctx, 0, 6)

    if reaper.ImGui_BeginTabBar(ctx, "MainTabs") then

      
      

      ------------------------------------------------------
      -- TAB 4: SHREDDER ex Shredder
      ------------------------------------------------------

      if reaper.ImGui_BeginTabItem(ctx, "Shredder") then
        
        reaper.ImGui_Spacing(ctx)

        -- Preset bar: type a name, then Save / Load (opens the browser
        -- popup below) / Random. Saving over an existing preset name
        -- asks for confirmation first. Only the SOUND-affecting
        -- settings are part of a preset - see the schema comment near
        -- SHREDDER_PRESET_SCHEMA up top for exactly what that does and
        -- doesn't include.
        do
          local btn_w = 64
          local gap = 6
          local star_gap, star_w = 4, 14
          local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
          local field_w = avail_w - (btn_w * 3 + gap * 2 + star_gap + star_w)
          if field_w < 80 then field_w = 80 end

          reaper.ImGui_SetNextItemWidth(ctx, field_w)
          local name_changed, new_name = reaper.ImGui_InputText(ctx, "##preset_name", SD.preset_name)
          if name_changed then
            SD.preset_name = new_name
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_PRESET_NAME, SD.preset_name, true)
          end

          -- "*" = settings changed since this preset was loaded/saved/
          -- Init'd. Fixed-width slot so the buttons don't shift when it
          -- appears.
          reaper.ImGui_SameLine(ctx, 0, star_gap)
          local star_x = reaper.ImGui_GetCursorPosX(ctx)
          if shredder_preset_is_dirty() then
            reaper.ImGui_Text(ctx, "*")
            if reaper.ImGui_IsItemHovered(ctx) then
              reaper.ImGui_SetTooltip(ctx, "Edited - settings differ from the saved preset. Save to keep them.")
            end
          else
            reaper.ImGui_Dummy(ctx, 1, 1)
          end

          reaper.ImGui_SameLine(ctx, star_x + star_w)
          if reaper.ImGui_Button(ctx, "Save", btn_w, 0) then
            local sanitized = shredder_sanitize_preset_name(SD.preset_name)
            local already_exists = false
            for _, existing_name in ipairs(shredder_list_presets()) do
              if existing_name == sanitized then already_exists = true end
            end

            local proceed = true
            if already_exists then
              -- Native OS dialog (blocking, synchronous) rather than a
              -- custom ImGui modal - no cross-frame popup-state to get
              -- wrong, and it's a well-established, simple REAPER API.
              local choice = reaper.ShowMessageBox(
                "A preset named \"" .. sanitized .. "\" already exists. Overwrite it?",
                "Overwrite Preset?", 4) -- 4 = yes/no
              proceed = (choice == 6) -- 6 = IDYES
            end

            if proceed then
              if shredder_save_preset(SD.preset_name) then
                shredder_snapshot_preset_baseline()
                set_status((already_exists and "Overwrote preset: " or "Saved preset: ") .. sanitized, false)
              else
                set_status("Couldn't save preset - check file permissions.", true)
              end
            else
              set_status("Save cancelled.", false)
            end
          end

          reaper.ImGui_SameLine(ctx, 0, gap)
          if reaper.ImGui_Button(ctx, "Load", btn_w, 0) then
            SD.preset_browser_open = true
          end

          reaper.ImGui_SameLine(ctx, 0, gap)
          if reaper.ImGui_Button(ctx, "Random##preset", btn_w, 0) then
            local picked = shredder_load_random_preset()
            if picked then
              set_status("Loaded random preset: " .. picked, false)
            else
              set_status("No saved presets yet - Save one first.", true)
            end
          end
        end

        reaper.ImGui_Dummy(ctx, 0, 4)

        -- Init/Random: quick-setup actions, always visible at the top
        -- (like Run Shredder itself) rather than tucked inside the
        -- collapsible Chunk Randomization section - Init now resets
        -- EVERY sound-affecting Shredder setting (see
        -- shredder_init_everything() above), not just the eight per-
        -- segment sliders it originally covered; Random is unchanged,
        -- still only the per-segment sliders (respecting the
        -- Randomization Settings checkboxes in the Settings tab).
        do
          local topbtn_w = (reaper.ImGui_GetContentRegionAvail(ctx) - 8) / 2
          if reaper.ImGui_Button(ctx, "Init", topbtn_w, 26) then
            shredder_init_everything()
          end
          if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx,
              "Resets EVERYTHING - Cut Mode and its settings, Structural Modes, Per-Segment " ..
              "Randomization, Multi-item mode - back to defaults.")
          end

          reaper.ImGui_SameLine(ctx)
          if reaper.ImGui_Button(ctx, "Random", topbtn_w, 26) then
            if SD.rand_include_position then
              Shredder_position_ms = math.random(0, 300)
              reaper.SetExtState(EXT_SECTION, KEYS.Shredder_POSITION, tostring(Shredder_position_ms), true)
            end
            if SD.rand_include_rate then
              Shredder_rate = 1.0 + math.random() * 5.0
              reaper.SetExtState(EXT_SECTION, KEYS.Shredder_RATE, tostring(Shredder_rate), true)
            end
            if SD.rand_include_pitch then
              Shredder_pitch = math.random() * 24.0
              reaper.SetExtState(EXT_SECTION, KEYS.Shredder_PITCH, tostring(Shredder_pitch), true)
            end
            if SD.rand_include_pan then
              Shredder_pan = math.random(0, 100)
              reaper.SetExtState(EXT_SECTION, KEYS.Shredder_PAN, tostring(Shredder_pan), true)
            end
            if SD.rand_include_volume then
              Shredder_volume = math.random() * 6.0
              reaper.SetExtState(EXT_SECTION, KEYS.Shredder_VOLUME, tostring(Shredder_volume), true)
            end
            if SD.rand_include_reverse then
              Shredder_reverse = math.random(0, 100)
              reaper.SetExtState(EXT_SECTION, KEYS.Shredder_REVERSE, tostring(Shredder_reverse), true)
            end
            if SD.rand_include_repeat then
              Shredder_repeat = math.random(0, 20)
              reaper.SetExtState(EXT_SECTION, KEYS.Shredder_REPEAT, tostring(Shredder_repeat), true)
            end
            if SD.rand_include_mute then
              Shredder_mute = math.random(0, 100)
              reaper.SetExtState(EXT_SECTION, KEYS.Shredder_MUTE, tostring(Shredder_mute), true)
            end
            if SD.rand_include_stretch then
              Shredder_stretch = math.random(0, 1000)
              reaper.SetExtState(EXT_SECTION, KEYS.Shredder_STRETCH, tostring(Shredder_stretch), true)
            end
          end
          if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx,
              "Rerolls Per-Segment Randomization only (Position/Rate/Pitch/Pan/Volume/" ..
              "Reverse/Repeats/Mute) - which ones is controlled by Randomization Settings " ..
              "in the Settings tab.")
          end
        end

        shredder_gap(true)

        -- Run Shredder pinned to whichever end SD.pin_position picks -
        -- everything else lives in its own scrollable child region, so
        -- however far you scroll through settings, the button itself
        -- never moves out of reach (the actual bug this whole thing
        -- fixes: in a narrow dock or small window, the button used to
        -- be wherever the bottom of one long stack happened to land).
        -- BeginChild's height: 0 = fill all remaining space, a
        -- NEGATIVE value = fill remaining space MINUS that many
        -- pixels - both documented Dear ImGui sizing rules, not a
        -- REAPER/ReaImGui-specific convention. That "remaining space"
        -- is measured to the bottom of the WHOLE window, not just the
        -- Shredder tab - so the status bar drawn after EndTabBar()
        -- also has to be accounted for here, in BOTH pin positions,
        -- or the total content (tab bar + child + button + status)
        -- overflows the window's actual height and forces the whole
        -- window to scroll, not just this one region. That's exactly
        -- the bug being fixed: the original -70 only ever covered the
        -- button, not the status bar below it.
        -- These are necessarily best-effort estimates (button height
        -- is exact since it's an explicit ImGui_Button() argument, but
        -- the status line's own height depends on font size and
        -- whether a long status message wraps to 2+ lines) - generous
        -- rounding rather than pixel-exact, so a slightly-long status
        -- message is still the one edge case that could reintroduce a
        -- sliver of scroll; a genuinely fixed-height single-line
        -- status readout would close that gap entirely if it recurs.
        local RUN_BUTTON_RESERVE_H = 54   -- button (50) + one item-spacing gap above it
        local STATUS_BAR_RESERVE_H = 40   -- Separator + one line of status text, with margin

        if SD.pin_position == "top" then
          shredder_run_button()
          shredder_gap(true)
        end

        local shredder_scroll_h
        if SD.pin_position == "bottom" then
          shredder_scroll_h = -(RUN_BUTTON_RESERVE_H + STATUS_BAR_RESERVE_H)
        else
          shredder_scroll_h = -STATUS_BAR_RESERVE_H
        end
        local shredder_scroll_visible = reaper.ImGui_BeginChild(ctx, "shredder_scroll", 0, shredder_scroll_h)
        if shredder_scroll_visible then

        --reaper.ImGui_Separator(ctx)
        --reaper.ImGui_Dummy(ctx, 0, 8)

        shredder_help_text(
          ctx,
          "Random-cut-and-reshuffle glitch tool. Chops selected item(s) into random-length " ..
          "segments, shuffles their order, and glues the result back into a single item - a " ..
          "stutter/mangle effect. One item selected: reshuffled in place. Multiple items " ..
          "selected: depends on the mode below."
        )

        --reaper.ImGui_Dummy(ctx, 0, 8)
        --reaper.ImGui_Separator(ctx)
        reaper.ImGui_Dummy(ctx, 0, 5)

        --reaper.ImGui_Text(ctx, "How cuts are decided (pick one - not combined):")
        reaper.ImGui_PushFont(ctx, current_font, font_size + 3)
        reaper.ImGui_SeparatorText(ctx, "HOW DO YOU WANT TO SHRED?")
        reaper.ImGui_PopFont(ctx)
        reaper.ImGui_Dummy(ctx, 0, 2)
        reaper.ImGui_Spacing(ctx)

        -- Generous gap (not the requested 5px) - this is the third
        -- attempt at getting spacing right without being able to test
        -- live in REAPER, and the most likely culprit both previous
        -- attempts missed is that a combo box's REAL rendered width
        -- can exceed what SetNextItemWidth requests (internal frame/
        -- border overhead) - a small gap has no margin against that,
        -- a bigger one does regardless of the exact overhead amount.
        local col_gap = 14
        local col_w = (reaper.ImGui_GetContentRegionAvail(ctx) - col_gap * 2) / 3
        local function col_x(i) return (col_w + col_gap) * (i - 1) end

        -- Both rows use the SAME absolute column offsets, so headers
        -- always land exactly above their combo - relative spacing
        -- (SameLine(ctx, 0, gap)) doesn't work for the header row
        -- because each header's own text width differs from col_w,
        -- so it drifts out of alignment with the (fixed-width) combos
        -- below it.
        for i, col in ipairs(SHREDDER_MODE_COLUMNS) do
          if i > 1 then reaper.ImGui_SameLine(ctx, col_x(i)) end
          reaper.ImGui_Text(ctx, col.label)
        end

        local col_changed, col_new_idx = {}, {}
        for i, col in ipairs(SHREDDER_MODE_COLUMNS) do
          if i > 1 then reaper.ImGui_SameLine(ctx, col_x(i)) end
          reaper.ImGui_SetNextItemWidth(ctx, col_w)
          local idx = shredder_mode_col_index(col, Shredder_cut_mode)
          col_changed[i], col_new_idx[i] = reaper.ImGui_Combo(ctx, "##mode_col_" .. i, idx, col.items)
        end

        -- A column's own placeholder ("-", value=nil) is a no-op if
        -- clicked - some Cut Mode is always active, so "selecting
        -- nothing" from a column can't turn the tool off. The nil-
        -- guard on `entry` is defensive: an out-of-range index here
        -- (e.g. from the phantom extra dropdown entry a doubled \0
        -- terminator used to cause) would otherwise crash on `.value`.
        for i, col in ipairs(SHREDDER_MODE_COLUMNS) do
          if col_changed[i] then
            local entry = col.modes[col_new_idx[i] + 1]
            local picked = entry and entry.value
            if picked then
              Shredder_cut_mode = picked
              reaper.SetExtState(EXT_SECTION, KEYS.Shredder_CUT_MODE, Shredder_cut_mode, true)
            end
          end
        end

        reaper.ImGui_Spacing(ctx)

        if Shredder_cut_mode == "length" then
          local cut_length_ms = math.floor(Shredder_cut_length * 1000 + 0.5)
          local cl_changed, new_cl_ms = reaper.ImGui_SliderInt(ctx, "Cut Length (ms)", cut_length_ms, 10, 3000)
          if cl_changed then
            Shredder_cut_length = new_cl_ms / 1000
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_CUT_LENGTH, tostring(Shredder_cut_length), true)
          end
          shredder_help_text(
            ctx,
            "Target segment length - actual segments vary randomly around this value, so it " ..
            "controls segment SIZE, not how many cuts happen."
          )
        elseif Shredder_cut_mode == "count" then
          local nc_changed, new_num_cuts = reaper.ImGui_SliderInt(ctx, "Number of Cuts", Shredder_num_cuts, 1, 100)
          if nc_changed then
            Shredder_num_cuts = new_num_cuts
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_NUM_CUTS, tostring(Shredder_num_cuts), true)
          end
          shredder_help_text(
            ctx,
            "Target number of cuts (segments = cuts + 1), scattered randomly across the item - " ..
            "controls segment COUNT, not their size."
          )
        elseif Shredder_cut_mode == "beat" then
          local div_idx = find_beat_division_index(Shredder_beat_division)
          local div_changed, new_div_idx = reaper.ImGui_Combo(
            ctx, "Beat Division", div_idx, SHREDDER_BEAT_DIVISION_ITEMS)
          if div_changed then
            local entry = SHREDDER_BEAT_DIVISIONS[new_div_idx + 1]
            if entry then
              Shredder_beat_division = entry.beats
              reaper.SetExtState(EXT_SECTION, KEYS.Shredder_BEAT_DIVISION, tostring(Shredder_beat_division), true)
            end
          end

          local bv_changed, new_bv = reaper.ImGui_SliderInt(ctx, "Humanize (%)", Shredder_beat_variance, 0, 50)
          if bv_changed then
            Shredder_beat_variance = new_bv
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_BEAT_VARIANCE, tostring(Shredder_beat_variance), true)
          end

          shredder_help_text(
            ctx,
            "Cuts land on the project tempo grid at the chosen division (tempo-map aware) instead " ..
            "of free-running seconds - segments are exactly one division long, plus optional " ..
            "Humanize jitter."
          )
        elseif Shredder_cut_mode == "euclid" then
          local steps_changed, new_steps = reaper.ImGui_SliderInt(ctx, "Steps", SD.euclid_steps, 4, 32)
          if steps_changed then
            SD.euclid_steps = new_steps
            if SD.euclid_hits > SD.euclid_steps then SD.euclid_hits = SD.euclid_steps end
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_EUCLID_STEPS, tostring(SD.euclid_steps), true)
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_EUCLID_HITS, tostring(SD.euclid_hits), true)
          end

          local hits_changed, new_hits = reaper.ImGui_SliderInt(ctx, "Hits", SD.euclid_hits, 1, SD.euclid_steps)
          if hits_changed then
            SD.euclid_hits = new_hits
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_EUCLID_HITS, tostring(SD.euclid_hits), true)
          end

          shredder_help_text(
            ctx,
            "Distributes Hits cuts as evenly as possible among Steps equal divisions of the item - " ..
            "a rhythmic, clave-like cut placement instead of pure randomness."
          )
        elseif Shredder_cut_mode == "sequence" then
          local seq_idx = find_sequence_type_index(SD.sequence_type)
          local seq_changed, new_seq_idx = reaper.ImGui_Combo(
            ctx, "Sequence Type", seq_idx, SHREDDER_SEQUENCE_TYPE_ITEMS)
          if seq_changed then
            local entry = SHREDDER_SEQUENCE_TYPES[new_seq_idx + 1]
            if entry then
              SD.sequence_type = entry.value
              reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SEQUENCE_TYPE, SD.sequence_type, true)
            end
          end

          if SD.sequence_type == "custom" then
            local custom_changed, new_custom = reaper.ImGui_InputText(
              ctx, "Weights (comma-separated)", SD.sequence_custom)
            if custom_changed then
              SD.sequence_custom = new_custom
              reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SEQUENCE_CUSTOM, SD.sequence_custom, true)
            end
          else
            local fibn_changed, new_fibn = reaper.ImGui_SliderInt(ctx, "Segments", SD.fib_segments, 3, 13)
            if fibn_changed then
              SD.fib_segments = new_fibn
              reaper.SetExtState(EXT_SECTION, KEYS.Shredder_FIB_SEGMENTS, tostring(SD.fib_segments), true)
            end
          end

          local fib_label = SD.fib_descending and "Shape: Shrinking" or "Shape: Growing"
          if reaper.ImGui_Button(ctx, fib_label, -1, 28) then
            SD.fib_descending = not SD.fib_descending
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_FIB_DESCENDING, SD.fib_descending and "1" or "0", true)
          end

          local preview_weights = shredder_sequence_preview_weights()
          reaper.ImGui_TextWrapped(ctx, "Weights: " .. table.concat(preview_weights, ", "))

          shredder_help_text(
            ctx,
            "Segment lengths are proportional to this sequence's numbers instead of equal or " ..
            "random sizes - an organic, structured sense of scale across the item. Custom lets " ..
            "you type your own comma-separated list (e.g. \"1,2,4,8,16\")."
          )
        elseif Shredder_cut_mode == "onset" then
          local sens_changed, new_sens = reaper.ImGui_SliderInt(
            ctx, "Sensitivity (%)", SD.onset_sensitivity, 5, 100)
          if sens_changed then
            SD.onset_sensitivity = new_sens
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_ONSET_SENSITIVITY, tostring(SD.onset_sensitivity), true)
          end

          shredder_help_text(
            ctx,
            "Cuts right before each detected transient, snapped to a zero crossing. Detection " ..
            "listens to lows, highs, and the full signal separately and adapts to the " ..
            "material's own level, so quiet takes and hi-hats over bass still get caught. " ..
            "Lower sensitivity = more (and smaller) cuts."
          )
        elseif Shredder_cut_mode == "blackhole" then
          local bh_start_ms = math.floor(SD.blackhole_start * 1000 + 0.5)
          local bh_changed, new_bh_ms = reaper.ImGui_SliderInt(ctx, "Starting Size (ms)", bh_start_ms, 10, 3000)
          if bh_changed then
            SD.blackhole_start = new_bh_ms / 1000
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_BLACKHOLE_START, tostring(SD.blackhole_start), true)
          end

          local decay_changed, new_decay = reaper.ImGui_SliderInt(ctx, "Decay (%)", SD.blackhole_decay, 50, 99)
          if decay_changed then
            SD.blackhole_decay = new_decay
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_BLACKHOLE_DECAY, tostring(SD.blackhole_decay), true)
          end

          local wh_label = SD.white_hole and "Mode: White Hole (grows)" or "Mode: Black Hole (shrinks)"
          if reaper.ImGui_Button(ctx, wh_label, -1, 28) then
            SD.white_hole = not SD.white_hole
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_WHITE_HOLE, SD.white_hole and "1" or "0", true)
          end

          local loop_changed, new_loop = reaper.ImGui_Checkbox(
            ctx, "Loop (repeat the collapse across the whole item)", SD.blackhole_loop)
          if loop_changed then
            SD.blackhole_loop = new_loop
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_BLACKHOLE_LOOP, SD.blackhole_loop and "1" or "0", true)
          end

        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_Text(ctx, "(?)")
        if reaper.ImGui_IsItemHovered(ctx) then
          reaper.ImGui_SetTooltip(
            ctx, 
            "Each chunk is Decay% the size of the one before it, starting from Starting Size - a \n" ..
            "fixed-ratio geometric shrink (Black Hole) that lands cuts at logarithmically-closer \n" ..
            "intervals, like a classic drum-and-bass accelerando roll. White Hole reverses it: \n" ..
            "starts tiny and grows instead. A single collapse only ever covers Starting Size / \n" ..
            "(1 - Decay) seconds no matter how long the item is (e.g. the defaults sum to exactly \n" ..
            "3s) - Loop restarts the collapse once it bottoms out so the WHOLE item gets covered \n" ..
            "instead of one collapse plus a static leftover tail; turn it off for a single \n" ..
            "accelerando at the start followed by untouched audio."
            )
        end


        elseif Shredder_cut_mode == "pitagora" then
          local pt_idx = find_pitagora_triple_index(SD.pitagora_triple)
          local pt_changed, new_pt_idx = reaper.ImGui_Combo(
            ctx, "Triple (a-b-c)", pt_idx, SHREDDER_PITAGORA_TRIPLE_ITEMS)
          if pt_changed then
            local entry = SHREDDER_PITAGORA_TRIPLES[new_pt_idx + 1]
            if entry then
              SD.pitagora_triple = entry
              reaper.SetExtState(EXT_SECTION, KEYS.Shredder_PITAGORA_TRIPLE, SD.pitagora_triple, true)
            end
          end

          shredder_help_text(
            ctx,
            "Treats each chunk as the hypotenuse of this Pythagorean triple and splits it into two " ..
            "children sized proportionally to legs a and b, then recurses into BOTH children the " ..
            "same way - a branching fractal split (the timeline version of the Pythagoras tree), " ..
            "not a straight chain like Black/White Hole. Stops subdividing a branch once it's too " ..
            "small to split further, so sibling chunks can end up wildly different sizes."
          )
        elseif Shredder_cut_mode == "collatz" then
          local seed_changed, new_seed = reaper.ImGui_SliderInt(ctx, "Seed", SD.collatz_seed, 2, 999)
          if seed_changed then
            SD.collatz_seed = new_seed
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_COLLATZ_SEED, tostring(SD.collatz_seed), true)
          end

          local cd_label = SD.collatz_descending and "Shape: Shrinking" or "Shape: Growing"
          if reaper.ImGui_Button(ctx, cd_label, -1, 28) then
            SD.collatz_descending = not SD.collatz_descending
            reaper.SetExtState(
              EXT_SECTION, KEYS.Shredder_COLLATZ_DESCENDING, SD.collatz_descending and "1" or "0", true)
          end

          shredder_help_text(
            ctx,
            "Runs the Collatz (\"3n+1\") sequence from Seed - even numbers halve, odd numbers " ..
            "become 3n+1 - until it reaches 1, and uses the values visited along the way as " ..
            "segment-length weights. Can swell dramatically before crashing down, unlike Black " ..
            "Hole's steady shrink - chaotic rather than trending. Try 27 for a long, dramatic ride."
          )
        elseif Shredder_cut_mode == "cantor" then
          local depth_changed, new_depth = reaper.ImGui_SliderInt(ctx, "Depth", SD.cantor_depth, 1, 7)
          if depth_changed then
            SD.cantor_depth = new_depth
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_CANTOR_DEPTH, tostring(SD.cantor_depth), true)
          end

          shredder_help_text(
            ctx,
            "The classical Cantor-set construction: recursively divides each chunk into thirds, " ..
            "keeps the left and right thirds, and permanently mutes the MIDDLE third, Depth times " ..
            "- a fractal lattice of structural silence rather than just varying chunk size. Like " ..
            "Morse, the muted \"holes\" are fixed by the cut itself, not rolled by the Chunk Mute " ..
            "slider below."
          )
        else -- "morse"
          local mt_changed, new_mt = reaper.ImGui_InputText(ctx, "Message", SD.morse_text)
          if mt_changed then
            SD.morse_text = new_mt
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_MORSE_TEXT, SD.morse_text, true)
          end

          local mu_changed, new_mu = reaper.ImGui_SliderInt(ctx, "Unit (ms)", SD.morse_unit_ms, 10, 500)
          if mu_changed then
            SD.morse_unit_ms = new_mu
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_MORSE_UNIT_MS, tostring(SD.morse_unit_ms), true)
          end

          local ml_changed, new_ml = reaper.ImGui_Checkbox(
            ctx, "Loop (repeat the message across the whole item)", SD.morse_loop)
          if ml_changed then
            SD.morse_loop = new_ml
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_MORSE_LOOP, SD.morse_loop and "1" or "0", true)
          end

          reaper.ImGui_TextWrapped(ctx, shredder_morse_display(SD.morse_text))

          shredder_help_text(
            ctx,
            "Encodes your message into real Morse timing (dot = 1 unit, dash = 3 units, gaps " ..
            "between letters/words longer still) and lays out one chunk per symbol - dots and " ..
            "dashes are audible, every gap is forced SILENT (same structural-mute mechanism as " ..
            "Cantor Dust above), so the mute pattern in the glued result actually spells out the " ..
            "message. Loop restarts the message once fully placed, so a short message like \"Shredder\" " ..
            "still covers a long item instead of leaving most of it untouched."
          )
        end

        reaper.ImGui_Spacing(ctx)

        local mso_changed, new_mso = reaper.ImGui_Checkbox(
          ctx, "Override Minimum Chunk Length", SD.min_seg_override_enabled)
        if mso_changed then
          SD.min_seg_override_enabled = new_mso
          reaper.SetExtState(
            EXT_SECTION, KEYS.Shredder_MIN_SEG_OVERRIDE, SD.min_seg_override_enabled and "1" or "0", true)
        end

        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_Text(ctx, "(?)")
        if reaper.ImGui_IsItemHovered(ctx) then
          reaper.ImGui_SetTooltip(
            ctx, 
            "Replaces the default 10ms floor used everywhere a chunk could otherwise get \n" ..
            "vanishingly small - most noticeable on Pitagora, Cantor Dust, Black/White Hole, \n" ..
            "and Collatz, which all recursively/iteratively shrink toward this floor. Raise it to \n" ..
            "force chunks to stay chunkier instead of cascading all the way down."
            )
        end


        if SD.min_seg_override_enabled then
          local msms_changed, new_msms = reaper.ImGui_SliderInt(
            ctx, "Minimum Chunk Length (ms)", SD.min_seg_override_ms, 1, 1000)
          if msms_changed then
            SD.min_seg_override_ms = new_msms
            reaper.SetExtState(
              EXT_SECTION, KEYS.Shredder_MIN_SEG_OVERRIDE_MS, tostring(SD.min_seg_override_ms), true)
          end

        
        end

        shredder_gap(true)

        --reaper.ImGui_Text(ctx, "Structural Modes")
        reaper.ImGui_PushFont(ctx, current_font, font_size + 3)
        reaper.ImGui_SetNextItemOpen(ctx, true, reaper.ImGui_Cond_FirstUseEver())
        local structural_open = reaper.ImGui_CollapsingHeader(ctx, "NOW, PUT IT TOGETHER... bravely ...")
        reaper.ImGui_PopFont(ctx)
        if structural_open then
        reaper.ImGui_Dummy(ctx, 0, 2)
        reaper.ImGui_Spacing(ctx)

        local shuf_idx = find_shuffle_mode_index(SD.shuffle_mode)
        local shuf_changed, new_shuf_idx = reaper.ImGui_Combo(
          ctx, "Shuffle Mode", shuf_idx, SHREDDER_SHUFFLE_MODE_ITEMS)
        if shuf_changed then
          local entry = SHREDDER_SHUFFLE_MODES[new_shuf_idx + 1]
          if entry then
            SD.shuffle_mode = entry.value
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SHUFFLE_MODE, SD.shuffle_mode, true)
          end
        end

        if SD.shuffle_mode == "local" then
          local win_changed, new_win = reaper.ImGui_SliderInt(ctx, "Window Size", SD.local_window, 2, 16)
          if win_changed then
            SD.local_window = new_win
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_LOCAL_WINDOW, tostring(SD.local_window), true)
          end
          shredder_help_text(
            ctx,
            "Segments are grouped into chunks of this size and shuffled within each group only - " ..
            "keeps the item's broad structure while still jumbling detail locally."
          )
        elseif SD.shuffle_mode == "weighted" then
          local wamt_changed, new_wamt = reaper.ImGui_SliderInt(
            ctx, "Shuffle Amount (%)", SD.weighted_amount, 0, 100)
          if wamt_changed then
            SD.weighted_amount = new_wamt
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_WEIGHTED_AMOUNT, tostring(SD.weighted_amount), true)
          end
          shredder_help_text(
            ctx,
            "0% = original order, 100% = full random shuffle - a continuous dial between the two " ..
            "rather than an all-or-nothing switch."
          )
        end

        reaper.ImGui_Spacing(ctx)

        -- PALINDROM MODE
        local pal_changed, new_pal = reaper.ImGui_Checkbox(
          ctx, "Palindrome Mode", SD.palindrome)
         
          reaper.ImGui_SameLine(ctx)
          reaper.ImGui_Text(ctx, "(?)")

          if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Play the final order forward, then backward\n")
          end 

        if pal_changed then
          SD.palindrome = new_pal
          reaper.SetExtState(EXT_SECTION, KEYS.Shredder_PALINDROME, SD.palindrome and "1" or "0", true)
        end

        reaper.ImGui_Spacing(ctx)

        -- ORDERED SUBSET MODE
        local subset_changed, new_subset = reaper.ImGui_Checkbox(
          ctx, "Ordered-Subset Mode",
          Shredder_subset_mode)

          reaper.ImGui_SameLine(ctx)
          reaper.ImGui_Text(ctx, "(?)")

          if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Randomly drop segments, keep the rest in original order\n")
          end   

        if subset_changed then
          Shredder_subset_mode = new_subset
          reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SUBSET_MODE, Shredder_subset_mode and "1" or "0", true)
        end

        if Shredder_subset_mode then
          local keep_changed, new_keep = reaper.ImGui_SliderInt(ctx, "Keep (%)", Shredder_subset_keep, 10, 100)
          if keep_changed then
            Shredder_subset_keep = new_keep
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SUBSET_KEEP, tostring(Shredder_subset_keep), true)
          end
          shredder_help_text(
            ctx,
            "Each segment is independently kept at this % chance and dropped otherwise - dropped " ..
            "chunks are removed (not muted), so the result is SHORTER than the source. Always " ..
            "plays back in the original order, overriding Shuffle Mode above."
          )
        end

        reaper.ImGui_Spacing(ctx)
       
        -- IGNORE SILENCE MODE
        local ignore_changed, new_ignore = reaper.ImGui_Checkbox(
          ctx, "Ignore Silence", Shredder_ignore_silence)

          reaper.ImGui_SameLine(ctx)
          reaper.ImGui_Text(ctx, "(?)")

          if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Skip near-silent segments when reshuffling\n")
          end 
                 
        if ignore_changed then
          Shredder_ignore_silence = new_ignore
          reaper.SetExtState(
            EXT_SECTION, KEYS.Shredder_IGNORE_SILENCE, Shredder_ignore_silence and "1" or "0", true)
        end

        reaper.ImGui_Dummy(ctx, 0, 8)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Dummy(ctx, 0, 8)

        -- Multiple items selected: was its own "MULTI SHRED-MASHER"
        -- collapsible section - just this one toggle button didn't
        -- need a whole section of its own, so it moved in here.
        local mash_label = Shredder_mash_mode and
          "Mode: Mash Together (all items combined into one)" or
          "Mode: Process Individually (each item stays separate)"
        if reaper.ImGui_Button(ctx, mash_label, -1, 34) then
          Shredder_mash_mode = not Shredder_mash_mode
          reaper.SetExtState(EXT_SECTION, KEYS.Shredder_MASH_MODE, Shredder_mash_mode and "1" or "0", true)
        end
        shredder_help_text(
          ctx,
          "Only matters with multiple items selected - Mash Together pools every selected item's " ..
          "segments into one combined result; Process Individually shreds each item on its own, " ..
          "staying separate."
        )

        shredder_gap(true)

        local preview_label = SD.show_preview and "Close Preview Window" or "Open Preview Window (cut lengths + chunk fate)"
        if reaper.ImGui_Button(ctx, preview_label, -1, 30) then
          SD.show_preview = not SD.show_preview
          reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SHOW_PREVIEW, SD.show_preview and "1" or "0", true)
        end

        shredder_help_text(
          ctx,
          "Opens a separate, movable window with a live bar chart of actual cut lengths for your " ..
          "current Cut Mode, plus the chunk drop/shuffle/repeat/palindrome diagram - keeps this tab " ..
          "compact instead of eating space here."
        )

        shredder_gap(true)

        end -- if structural_open

        reaper.ImGui_PushFont(ctx, current_font, font_size + 3)
        reaper.ImGui_SetNextItemOpen(ctx, true, reaper.ImGui_Cond_FirstUseEver())
        local chunk_rand_open = reaper.ImGui_CollapsingHeader(ctx, "CHUNK RANDOMIZATION")
        reaper.ImGui_PopFont(ctx)
        if chunk_rand_open then
        reaper.ImGui_Dummy(ctx, 0, 2)

        --reaper.ImGui_Text(ctx, "Per-Segment Randomization (how much - 0 means no change)")
        reaper.ImGui_Spacing(ctx)

        -- Init and Random both moved to the top of the tab (next to
        -- the preset bar) in v1.39 - Init now resets everything, not
        -- just what's in this section, so it made more sense grouped
        -- with Random up there than staying here. See
        -- shredder_init_everything() and the button row right after
        -- the preset bar, near the top of this file's draw().

        -- Direction buttons need room reserved after the slider, so
        -- these use a hidden "##..." label (no auto-drawn label eating
        -- that space) and an explicit width - the visible label text
        -- is drawn by shredder_direction_buttons() itself, AFTER the
        -- buttons, so the reading order is [slider][buttons][label].
        local DIR_RESERVE_W = 190

        reaper.ImGui_SetNextItemWidth(ctx, reaper.ImGui_GetContentRegionAvail(ctx) - DIR_RESERVE_W)
        local pos_changed, new_pos = reaper.ImGui_SliderInt(ctx, "##position_ms", Shredder_position_ms, 0, 300)
        if pos_changed then
          Shredder_position_ms = new_pos
          reaper.SetExtState(EXT_SECTION, KEYS.Shredder_POSITION, tostring(Shredder_position_ms), true)
        end
        shredder_direction_buttons("position_direction", KEYS.Shredder_POSITION_DIRECTION, "Position (ms)",
          Shredder_position_ms, 0, 300)

        reaper.ImGui_SetNextItemWidth(ctx, reaper.ImGui_GetContentRegionAvail(ctx) - DIR_RESERVE_W)
        local pan_changed, new_pan = reaper.ImGui_SliderInt(ctx, "##pan_pct", Shredder_pan, 0, 100)
        if pan_changed then
          Shredder_pan = new_pan
          reaper.SetExtState(EXT_SECTION, KEYS.Shredder_PAN, tostring(Shredder_pan), true)
        end
        shredder_direction_buttons("pan_direction", KEYS.Shredder_PAN_DIRECTION, "Pan (%)",
          Shredder_pan, 0, 100)

        reaper.ImGui_SetNextItemWidth(ctx, reaper.ImGui_GetContentRegionAvail(ctx) - DIR_RESERVE_W)
        local vol_changed, new_vol = reaper.ImGui_SliderDouble(
          ctx, "##volume_db", Shredder_volume, 0.0, 6.0, "%.1f")
        if vol_changed then
          Shredder_volume = new_vol
          reaper.SetExtState(EXT_SECTION, KEYS.Shredder_VOLUME, tostring(Shredder_volume), true)
        end
        shredder_direction_buttons("volume_direction", KEYS.Shredder_VOLUME_DIRECTION, "Volume (dB)",
          Shredder_volume, 0.0, 6.0)

        reaper.ImGui_SetNextItemWidth(ctx, reaper.ImGui_GetContentRegionAvail(ctx) - DIR_RESERVE_W)
        local stretch_changed, new_stretch = reaper.ImGui_SliderInt(ctx, "##stretch_pct", Shredder_stretch, 0, 1000)
        if stretch_changed then
          Shredder_stretch = new_stretch
          reaper.SetExtState(EXT_SECTION, KEYS.Shredder_STRETCH, tostring(Shredder_stretch), true)
        end
        shredder_direction_buttons("stretch_direction", KEYS.Shredder_STRETCH_DIRECTION, "Stretch (%)",
          Shredder_stretch, 0, 1000)

                reaper.ImGui_SetNextItemWidth(ctx, reaper.ImGui_GetContentRegionAvail(ctx) - DIR_RESERVE_W)
        local pitch_changed, new_pitch = reaper.ImGui_SliderDouble(
          ctx, "##pitch_st", Shredder_pitch, 0.0, 24.0, "%.1f")
        if pitch_changed then
          Shredder_pitch = new_pitch
          reaper.SetExtState(EXT_SECTION, KEYS.Shredder_PITCH, tostring(Shredder_pitch), true)
        end
        shredder_direction_buttons("pitch_direction", KEYS.Shredder_PITCH_DIRECTION, "Pitch (st)",
          Shredder_pitch, 0.0, 24.0)

        local scaleq_changed, new_scaleq = reaper.ImGui_Checkbox(
          ctx, "Scale-Quantize Pitch", SD.scale_quantize)
        if scaleq_changed then
          SD.scale_quantize = new_scaleq
          reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SCALE_QUANTIZE, SD.scale_quantize and "1" or "0", true)
        end

        if SD.scale_quantize then
          local root_changed, new_root = reaper.ImGui_Combo(ctx, "Root", SD.scale_root, SHREDDER_SCALE_ROOT_ITEMS)
          if root_changed then
            SD.scale_root = new_root
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SCALE_ROOT, tostring(SD.scale_root), true)
          end

          local st_idx = find_scale_type_index(SD.scale_type)
          local st_changed, new_st_idx = reaper.ImGui_Combo(ctx, "Scale", st_idx, SHREDDER_SCALE_TYPE_ITEMS)
          if st_changed then
            local entry = SHREDDER_SCALE_TYPES[new_st_idx + 1]
            if entry then
              SD.scale_type = entry.value
              reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SCALE_TYPE, SD.scale_type, true)
            end
          end

          shredder_help_text(
            ctx,
            "Snaps each segment's randomized pitch to the nearest note in this scale, instead of " ..
            "landing anywhere in the Pitch range above - turns pitch randomization into an in-key " ..
            "glitch-melody generator."
          )
        end

        local rate_changed, new_rate = reaper.ImGui_SliderDouble(ctx, "##rate_x", Shredder_rate, 1.0, 6.0, "%.2f")
        if rate_changed then
          Shredder_rate = new_rate
          reaper.SetExtState(EXT_SECTION, KEYS.Shredder_RATE, tostring(Shredder_rate), true)
        end
        reaper.ImGui_SameLine(ctx, 0, 8)
        shredder_slider_label("Rate (x)", Shredder_rate, 1.0, 6.0)

        local rev_changed, new_rev = reaper.ImGui_SliderInt(ctx, "##reverse_pct", Shredder_reverse, 0, 100)
        if rev_changed then
          Shredder_reverse = new_rev
          reaper.SetExtState(EXT_SECTION, KEYS.Shredder_REVERSE, tostring(Shredder_reverse), true)
        end
        reaper.ImGui_SameLine(ctx, 0, 8)
        shredder_slider_label("Reverse Cut (%)", Shredder_reverse, 0, 100)

        local rpt_changed, new_rpt = reaper.ImGui_SliderInt(ctx, "##repeat_count", Shredder_repeat, 0, 20)
        if rpt_changed then
          Shredder_repeat = new_rpt
          reaper.SetExtState(EXT_SECTION, KEYS.Shredder_REPEAT, tostring(Shredder_repeat), true)
        end
        reaper.ImGui_SameLine(ctx, 0, 8)
        shredder_slider_label("Number Of Repeats", Shredder_repeat, 0, 20)

        local scatter_changed, new_scatter = reaper.ImGui_Checkbox(
          ctx, "Scatter Repeats", SD.scatter_repeats)
        if scatter_changed then
          SD.scatter_repeats = new_scatter
          reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SCATTER_REPEATS, SD.scatter_repeats and "1" or "0", true)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
          reaper.ImGui_SetTooltip(ctx,
            "Off: repeat copies play right after their original, clustered (A A A A B C).\n" ..
            "On: copies land at random positions throughout the result instead (A B A C A B).\n" ..
            "Either way, the base order (Shuffle Mode/Palindrome/etc) is unaffected - this " ..
            "only changes where the EXTRA copies go.")
        end

        local mute_changed, new_mute = reaper.ImGui_SliderInt(ctx, "##mute_pct", Shredder_mute, 0, 100)
        if mute_changed then
          Shredder_mute = new_mute
          reaper.SetExtState(EXT_SECTION, KEYS.Shredder_MUTE, tostring(Shredder_mute), true)
        end
        reaper.ImGui_SameLine(ctx, 0, 8)
        shredder_slider_label("Chunk Mute (%)", Shredder_mute, 0, 100)

        shredder_help_text(
          ctx,
          "Position jitters each segment's placed position by up to +/- amount set above. " .. 
          "Number Of Repeats: high values can make the result MUCH longer "
          )

        reaper.ImGui_Dummy(ctx, 0, 8)
       -- reaper.ImGui_Separator(ctx)
       -- reaper.ImGui_Dummy(ctx, 0, 8)

        -- Hidden for now (V7) - not useful in its current form. Code
        -- kept intact behind this flag so it's a one-line flip to
        -- bring back once it's reworked; the engine side (Antisample_
        -- Shredder_V4.lua) is untouched and still supports it if
        -- ExtState values are set some other way.
        local SHREDDER_SHOW_SIDECHAIN_UI = false
        if SHREDDER_SHOW_SIDECHAIN_UI then

        reaper.ImGui_Text(ctx, "Sidechain-Aware Shredding")
        reaper.ImGui_Spacing(ctx)

        local sc_en_changed, new_sc_en = reaper.ImGui_Checkbox(
          ctx, "Enable Sidechain Gate", SD.sidechain_enabled)
        if sc_en_changed then
          SD.sidechain_enabled = new_sc_en
          reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SIDECHAIN_ENABLED, SD.sidechain_enabled and "1" or "0", true)
        end

        if SD.sidechain_enabled then
          local sc_track_changed, new_sc_track = reaper.ImGui_InputText(ctx, "Sidechain Track Name", SD.sidechain_track)
          if sc_track_changed then
            SD.sidechain_track = new_sc_track
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SIDECHAIN_TRACK, SD.sidechain_track, true)
          end

          local sc_thr_changed, new_sc_thr = reaper.ImGui_SliderInt(
            ctx, "Threshold (%)", SD.sidechain_threshold, 0, 100)
          if sc_thr_changed then
            SD.sidechain_threshold = new_sc_thr
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SIDECHAIN_THRESHOLD, tostring(SD.sidechain_threshold), true)
          end

          local sc_inv_changed, new_sc_inv = reaper.ImGui_Checkbox(
            ctx, "Invert (duck on hits instead of gate)", SD.sidechain_invert)
          if sc_inv_changed then
            SD.sidechain_invert = new_sc_inv
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SIDECHAIN_INVERT, SD.sidechain_invert and "1" or "0", true)
          end

          local sc_drop_changed, new_sc_drop = reaper.ImGui_Checkbox(
            ctx, "Drop Instead Of Mute (shortens the result)", SD.sidechain_drop)
          if sc_drop_changed then
            SD.sidechain_drop = new_sc_drop
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SIDECHAIN_DROP, SD.sidechain_drop and "1" or "0", true)
          end

          shredder_help_text(
            ctx,
            "Reads the named track's audio and keeps/mutes/drops each segment based on whether " ..
            "that track has energy above Threshold at the segment's ORIGINAL position - ties the " ..
            "glitch's hits/gaps to another track's rhythm (e.g. a kick pattern). Track name must " ..
            "match an existing track exactly."
          )
        end

        shredder_gap(true)
        --reaper.ImGui_Separator(ctx)
        --reaper.ImGui_Dummy(ctx, 0, 8)

        end -- SHREDDER_SHOW_SIDECHAIN_UI

        end -- if chunk_rand_open

        reaper.ImGui_EndChild(ctx)
        end -- if shredder_scroll_visible (opened right after BeginChild, above)

        if SD.pin_position == "bottom" then
          shredder_run_button()
        end

        reaper.ImGui_EndTabItem(ctx)
      end

      
      ------------------------------------------------------
      -- TAB 7: UI SETTINGS
      ------------------------------------------------------

      if reaper.ImGui_BeginTabItem(ctx, "Settings") then

        -- Same own-scroll-region setup as the Shredder tab, so the
        -- status bar below the tab bar stays pinned to the bottom
        -- instead of scrolling away with the settings.
        local SETTINGS_STATUS_BAR_RESERVE_H = 40 -- keep in sync with the Shredder tab's STATUS_BAR_RESERVE_H
        local settings_scroll_visible = reaper.ImGui_BeginChild(ctx, "settings_scroll", 0, -SETTINGS_STATUS_BAR_RESERVE_H)
        if settings_scroll_visible then

        reaper.ImGui_Spacing(ctx)
        --reaper.ImGui_Indent(ctx)

        reaper.ImGui_TextWrapped(ctx, "Appearance and behavior settings for this window.")
        --reaper.ImGui_Dummy(ctx, 0, 10)
        reaper.ImGui_Spacing(ctx)

        reaper.ImGui_PushFont(ctx, current_font, font_size + 3)
        reaper.ImGui_SetNextItemOpen(ctx, false, reaper.ImGui_Cond_FirstUseEver())
        local appearance_open = reaper.ImGui_CollapsingHeader(ctx, "Appearance")
        reaper.ImGui_PopFont(ctx)
        if appearance_open then
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Indent(ctx)

        reaper.ImGui_SetNextItemOpen(ctx, false, reaper.ImGui_Cond_FirstUseEver())
        if reaper.ImGui_CollapsingHeader(ctx, "Color Palette") then
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_TextWrapped(
          ctx, "One click changes background, buttons, text, and every other color at once.")
        reaper.ImGui_Dummy(ctx, 0, 8)

        for i, preset in ipairs(PALETTE_PRESETS) do
          reaper.ImGui_PushID(ctx, "palette_" .. preset.name)
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), preset.accent)
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), preset.accent_hover)
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), preset.accent_active)
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x1A1A1AFF)

          local label = preset.name .. (preset.name == active_palette_name and "  (active)" or "")
          if reaper.ImGui_Button(ctx, label, 220, 34) then
            apply_palette(preset)
            active_palette_name = preset.name
            reaper.SetExtState(EXT_SECTION, KEYS.PALETTE_NAME, preset.name, true)

            -- Re-apply the separately-chosen font color (if any) right
            -- after, so it correctly keeps overriding the palette's own
            -- text color rather than getting silently reset by it.
            if active_font_color_name ~= "" then
              for _, fc in ipairs(FONT_COLOR_PRESETS) do
                if fc.name == active_font_color_name then
                  apply_font_color(fc)
                  break
                end
              end
            end

            set_status(preset.name .. " palette applied.", false)
          end

          reaper.ImGui_PopStyleColor(ctx, 4)
          reaper.ImGui_PopID(ctx)

          if i % 2 == 1 and i < #PALETTE_PRESETS then
            reaper.ImGui_SameLine(ctx)
          end
        end

        reaper.ImGui_Dummy(ctx, 0, 8)
        reaper.ImGui_Text(ctx, "Run Shredder button color")
        reaper.ImGui_Dummy(ctx, 0, 4)
        do
          -- ColorEdit3 works in 0xRRGGBB; the rest of this file (and
          -- run_button_color) uses 0xRRGGBBAA, so convert both ways.
          local picker_flags = reaper.ImGui_ColorEditFlags_NoInputs()
          local shown = (run_button_color or THEME_ORANGE) >> 8
          local rb_changed, new_rb = reaper.ImGui_ColorEdit3(ctx, "##run_button_color", shown, picker_flags)
          if rb_changed then
            run_button_color = ((new_rb & 0xFFFFFF) << 8) | 0xFF -- always fully opaque
            reaper.SetExtState(EXT_SECTION, KEYS.RUN_BUTTON_COLOR, tostring(run_button_color), true)
          end
          reaper.ImGui_SameLine(ctx, 0, 8)
          reaper.ImGui_Text(ctx, run_button_color and "Custom" or "Palette default")
          if run_button_color then
            reaper.ImGui_SameLine(ctx, 0, 12)
            if reaper.ImGui_Button(ctx, "Reset##run_button_color") then
              run_button_color = nil
              reaper.DeleteExtState(EXT_SECTION, KEYS.RUN_BUTTON_COLOR, true)
              set_status("Run Shredder button color reset to palette default.", false)
            end
          end
        end
        reaper.ImGui_Dummy(ctx, 0, 4)

        reaper.ImGui_Spacing(ctx)
        end -- Color Palette

        reaper.ImGui_SetNextItemOpen(ctx, false, reaper.ImGui_Cond_FirstUseEver())
        if reaper.ImGui_CollapsingHeader(ctx, "Font and Font Color") then
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_TextWrapped(
          ctx, "Independent of the palette above - pick a text color separately and it stays " ..
          "even if you switch palettes.")
        reaper.ImGui_Dummy(ctx, 0, 8)

        for i, preset in ipairs(FONT_COLOR_PRESETS) do
          reaper.ImGui_PushID(ctx, "fontcolor_" .. preset.name)
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), THEME_FRAME_BG)
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), THEME_FRAME_BG_HOVER)
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), THEME_FRAME_BG_ACTIVE)
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), preset.text)

          local label = preset.name .. (preset.name == active_font_color_name and "  (active)" or "")
          if reaper.ImGui_Button(ctx, label, 220, 34) then
            apply_font_color(preset)
            active_font_color_name = preset.name
            reaper.SetExtState(EXT_SECTION, KEYS.FONT_COLOR_NAME, preset.name, true)
            set_status(preset.name .. " font color applied.", false)
          end

          reaper.ImGui_PopStyleColor(ctx, 4)
          reaper.ImGui_PopID(ctx)

          if i % 2 == 1 and i < #FONT_COLOR_PRESETS then
            reaper.ImGui_SameLine(ctx)
          end
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Dummy(ctx, 0, 4)

        local font_changed, new_font_size = reaper.ImGui_InputInt(
          ctx,
          "Font size",
          font_size,
          1,
          1
        )

        if font_changed then
          set_font_size(new_font_size)
        end
        reaper.ImGui_Dummy(ctx, 0, 4)

        reaper.ImGui_Spacing(ctx)
        end -- Font and Font Color

        reaper.ImGui_SetNextItemOpen(ctx, false, reaper.ImGui_Cond_FirstUseEver())
        if reaper.ImGui_CollapsingHeader(ctx, "Layout") then
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_TextWrapped(
          ctx,
          "How the Shredder tab lays itself out - useful once it's docked narrow or the " ..
          "window is small."
        )
        reaper.ImGui_Spacing(ctx)

        reaper.ImGui_Text(ctx, "Run Shredder button position")
        reaper.ImGui_Dummy(ctx, 0, 4)
        do
          local col_w2 = 110
          local active_top = (SD.pin_position == "top")
          if active_top then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), THEME_ORANGE_ACTIVE)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), THEME_ORANGE_ACTIVE)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), THEME_ORANGE_ACTIVE)
          end
          if reaper.ImGui_Button(ctx, "Top", col_w2, 0) then
            SD.pin_position = "top"
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_PIN_POSITION, "top", true)
          end
          if active_top then reaper.ImGui_PopStyleColor(ctx, 3) end

          reaper.ImGui_SameLine(ctx, 0, 6)
          local active_bottom = (SD.pin_position == "bottom")
          if active_bottom then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), THEME_ORANGE_ACTIVE)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), THEME_ORANGE_ACTIVE)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), THEME_ORANGE_ACTIVE)
          end
          if reaper.ImGui_Button(ctx, "Bottom", col_w2, 0) then
            SD.pin_position = "bottom"
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_PIN_POSITION, "bottom", true)
          end
          if active_bottom then reaper.ImGui_PopStyleColor(ctx, 3) end
        end
        reaper.ImGui_Dummy(ctx, 0, 4)
        reaper.ImGui_TextWrapped(
          ctx,
          "Everything else in the Shredder tab scrolls in its own region, so however far " ..
          "you've scrolled, Run Shredder stays exactly where you left it."
        )

        reaper.ImGui_Spacing(ctx)

        local compact_changed, new_compact = reaper.ImGui_Checkbox(ctx, "Compact Mode", SD.compact_mode)
        if compact_changed then
          SD.compact_mode = new_compact
          reaper.SetExtState(EXT_SECTION, KEYS.Shredder_COMPACT_MODE, SD.compact_mode and "1" or "0", true)
        end
        reaper.ImGui_TextWrapped(
          ctx,
          "Tighter spacing throughout the Shredder tab - more fits on screen at once, useful " ..
          "for a narrow dock or a small window."
        )

        reaper.ImGui_Spacing(ctx)
        end -- Layout

        reaper.ImGui_Unindent(ctx)
        end -- if appearance_open

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        reaper.ImGui_PushFont(ctx, current_font, font_size + 3)
        reaper.ImGui_SetNextItemOpen(ctx, false, reaper.ImGui_Cond_FirstUseEver())
        local behavior_open = reaper.ImGui_CollapsingHeader(ctx, "Shredder Behaviour")
        reaper.ImGui_PopFont(ctx)
        if behavior_open then
        reaper.ImGui_Spacing(ctx)

        reaper.ImGui_Text(ctx, "Cut Variance")
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_Text(ctx, "(?)")
        if reaper.ImGui_IsItemHovered(ctx) then
          reaper.ImGui_SetTooltip(
            ctx,
            "Affects By Cut Length AND By Number of Cuts (Shredder tab, Classic column) - one \n" ..
            "switch for both, not two. Randomized (default): By Cut Length's segments are \n" ..
            "+/-50% around its slider's value (a 500ms setting actually produces 250-750ms \n" ..
            "segments); By Number of Cuts' actual count is +/-20% around its slider's value \n" ..
            "(a setting of 2 can genuinely produce 1-3 cuts, i.e. 2-4 segments) - same as it's \n" ..
            "always been for both. Fixed: By Cut Length's segments are exactly its slider's \n" ..
            "value; By Number of Cuts produces exactly that many cuts, every time - no \n" ..
            "randomization of size or count either way. The last segment in an item can still \n" ..
            "come out shorter regardless of this setting, the same way it does for every other \n" ..
            "Cut Mode, since there's always some leftover unless the item's length divides \n" ..
            "evenly - and By Number of Cuts' individual cut POSITIONS stay randomly scattered \n" ..
            "even when Fixed, since Fixed only locks the count, not where the cuts land."
          )
        end
        reaper.ImGui_Dummy(ctx, 0, 4)
        do
          local col_w3 = 130
          local active_rand = not SD.cut_length_fixed
          if active_rand then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), THEME_ORANGE_ACTIVE)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), THEME_ORANGE_ACTIVE)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), THEME_ORANGE_ACTIVE)
          end
          if reaper.ImGui_Button(ctx, "Randomized", col_w3, 0) then
            SD.cut_length_fixed = false
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_CUT_LENGTH_FIXED, "0", true)
          end
          if active_rand then reaper.ImGui_PopStyleColor(ctx, 3) end

          reaper.ImGui_SameLine(ctx, 0, 6)
          local active_fixed = SD.cut_length_fixed
          if active_fixed then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), THEME_ORANGE_ACTIVE)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), THEME_ORANGE_ACTIVE)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), THEME_ORANGE_ACTIVE)
          end
          if reaper.ImGui_Button(ctx, "Fixed", col_w3, 0) then
            SD.cut_length_fixed = true
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_CUT_LENGTH_FIXED, "1", true)
          end
          if active_fixed then reaper.ImGui_PopStyleColor(ctx, 3) end
        end
        reaper.ImGui_Dummy(ctx, 0, 4)

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        reaper.ImGui_Text(ctx, "Take Pitch Shift / Time Stretch Mode")
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_Text(ctx, "(?)")
        if reaper.ImGui_IsItemHovered(ctx) then
          reaper.ImGui_SetTooltip(
            ctx,
            "The pitch shift / time stretch algorithm set on every chunk Shredder produces - \n" ..
            "affects how Stretch, Pitch, and Rate sound. The list comes straight from REAPER, \n" ..
            "so it matches whatever modes this install supports. Project default leaves each \n" ..
            "chunk on whatever the project is set to.\n\n" ..
            "Fixed: every chunk uses the mode picked in the dropdown (Project default unless \n" ..
            "you choose otherwise). Randomized: each chunk independently picks one of Project \n" ..
            "default, elastique 3 Pro, Rrreeeaaa, or ReaReaRea (any this REAPER version \n" ..
            "doesn't have is skipped)."
          )
        end
        reaper.ImGui_Dummy(ctx, 0, 4)
        do
          local col_w4 = 130
          local active_pm_fixed = not SD.pitch_mode_random
          if active_pm_fixed then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), THEME_ORANGE_ACTIVE)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), THEME_ORANGE_ACTIVE)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), THEME_ORANGE_ACTIVE)
          end
          if reaper.ImGui_Button(ctx, "Fixed##pitch_mode_fixed", col_w4, 0) then
            SD.pitch_mode_random = false
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_PITCH_MODE_RANDOM, "0", true)
          end
          if active_pm_fixed then reaper.ImGui_PopStyleColor(ctx, 3) end

          reaper.ImGui_SameLine(ctx, 0, 6)
          local active_pm_rand = SD.pitch_mode_random
          if active_pm_rand then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), THEME_ORANGE_ACTIVE)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), THEME_ORANGE_ACTIVE)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), THEME_ORANGE_ACTIVE)
          end
          if reaper.ImGui_Button(ctx, "Randomized##pitch_mode_random", col_w4, 0) then
            SD.pitch_mode_random = true
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_PITCH_MODE_RANDOM, "1", true)
          end
          if active_pm_rand then reaper.ImGui_PopStyleColor(ctx, 3) end
        end
        reaper.ImGui_Dummy(ctx, 0, 4)
        if SD.pitch_mode_random then
          reaper.ImGui_TextColored(ctx, THEME_TEXT_DISABLED,
            "Per chunk: Project default / elastique 3 Pro / Rrreeeaaa / ReaReaRea")
        else
        do
          local pm = shredder_get_pitch_modes()
          local cur_shifter = SD.pitch_mode >= 0 and math.floor(SD.pitch_mode / 65536) or -1
          local cur_sub = SD.pitch_mode >= 0 and (SD.pitch_mode % 65536) or 0

          local mode_idx, entry = 0, nil
          for k, m in ipairs(pm.list) do
            if m.id == cur_shifter then mode_idx, entry = k, m end
          end

          reaper.ImGui_SetNextItemWidth(ctx, 280)
          local mode_changed, new_mode_idx = reaper.ImGui_Combo(ctx, "Mode##shredder_pitch_mode", mode_idx, pm.items)
          if mode_changed then
            entry = pm.list[new_mode_idx]
            cur_sub = 0
            SD.pitch_mode = entry and entry.id * 65536 or -1
            reaper.SetExtState(EXT_SECTION, KEYS.Shredder_PITCH_MODE, tostring(SD.pitch_mode), true)
          end

          if entry and #entry.subs > 0 then
            if cur_sub >= #entry.subs then cur_sub = 0 end
            reaper.ImGui_SetNextItemWidth(ctx, 280)
            local sub_changed, new_sub = reaper.ImGui_Combo(ctx, "Submode##shredder_pitch_submode", cur_sub, entry.sub_items)
            if sub_changed then
              SD.pitch_mode = entry.id * 65536 + new_sub
              reaper.SetExtState(EXT_SECTION, KEYS.Shredder_PITCH_MODE, tostring(SD.pitch_mode), true)
            end
          end
        end
        end -- if SD.pitch_mode_random
        reaper.ImGui_Dummy(ctx, 0, 4)

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        local cutonly_changed, new_cutonly = reaper.ImGui_Checkbox(
          ctx, "Cut but don't render", SD.cut_only)
        if cutonly_changed then
          SD.cut_only = new_cutonly
          reaper.SetExtState(EXT_SECTION, KEYS.Shredder_CUT_ONLY, SD.cut_only and "1" or "0", true)
        end
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_Text(ctx, "(?)")
        if reaper.ImGui_IsItemHovered(ctx) then
          reaper.ImGui_SetTooltip(
            ctx,
            "Run Shredder cuts, shuffles, and randomizes exactly as normal, but stops short of \n" ..
            "the final glue - instead the resulting segments are selected and grouped, and the \n" ..
            "edit cursor moves to the start of the selection. On by default."
          )
        end

        reaper.ImGui_Spacing(ctx)

        local hidehelp_changed, new_hidehelp = reaper.ImGui_Checkbox(
          ctx, "Hide helper text", SD.hide_help_text)
        if hidehelp_changed then
          SD.hide_help_text = new_hidehelp
          reaper.SetExtState(EXT_SECTION, KEYS.Shredder_HIDE_HELP_TEXT, SD.hide_help_text and "1" or "0", true)
        end
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_Text(ctx, "(?)")
        if reaper.ImGui_IsItemHovered(ctx) then
          reaper.ImGui_SetTooltip(
            ctx,
            "Hides the explanatory paragraphs throughout the Shredder tab - control names, \n" ..
            "sliders, and values stay exactly as they are, only the descriptive prose is hidden."
          )
        end

        end -- if behavior_open

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        reaper.ImGui_PushFont(ctx, current_font, font_size + 3)
        reaper.ImGui_SetNextItemOpen(ctx, false, reaper.ImGui_Cond_FirstUseEver())
        local randset_open = reaper.ImGui_CollapsingHeader(ctx, "Randomization Settings")
        reaper.ImGui_PopFont(ctx)
        if randset_open then
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_TextWrapped(
          ctx,
          "Which Per-Segment Randomization properties the Random button (Shredder tab) is " ..
          "allowed to reroll. Unchecked properties are left completely untouched by Random - " ..
          "manually dragging a slider, and the Init button, aren't affected by this either way."
        )
        reaper.ImGui_Spacing(ctx)

        do
          local col_w = reaper.ImGui_GetContentRegionAvail(ctx) / 2

          local function rand_include_checkbox(label, sd_field, ext_key, col)
            if col == 2 then
              reaper.ImGui_SameLine(ctx, col_w)
            end
            local changed, new_val = reaper.ImGui_Checkbox(ctx, label, SD[sd_field])
            if changed then
              SD[sd_field] = new_val
              reaper.SetExtState(EXT_SECTION, ext_key, new_val and "1" or "0", true)
            end
          end

          rand_include_checkbox("Position", "rand_include_position", KEYS.Shredder_RAND_INCLUDE_POSITION, 1)
          rand_include_checkbox("Rate", "rand_include_rate", KEYS.Shredder_RAND_INCLUDE_RATE, 2)
          rand_include_checkbox("Pitch", "rand_include_pitch", KEYS.Shredder_RAND_INCLUDE_PITCH, 1)
          rand_include_checkbox("Pan", "rand_include_pan", KEYS.Shredder_RAND_INCLUDE_PAN, 2)
          rand_include_checkbox("Volume", "rand_include_volume", KEYS.Shredder_RAND_INCLUDE_VOLUME, 1)
          rand_include_checkbox("Reverse", "rand_include_reverse", KEYS.Shredder_RAND_INCLUDE_REVERSE, 2)
          rand_include_checkbox("Repeat", "rand_include_repeat", KEYS.Shredder_RAND_INCLUDE_REPEAT, 1)
          rand_include_checkbox("Mute", "rand_include_mute", KEYS.Shredder_RAND_INCLUDE_MUTE, 2)
          rand_include_checkbox("Stretch", "rand_include_stretch", KEYS.Shredder_RAND_INCLUDE_STRETCH, 1)
        end

        end -- if randset_open

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        reaper.ImGui_PushFont(ctx, current_font, font_size + 3)
        reaper.ImGui_SetNextItemOpen(ctx, false, reaper.ImGui_Cond_FirstUseEver())
        local render_open = reaper.ImGui_CollapsingHeader(ctx, "Render Settings")
        reaper.ImGui_PopFont(ctx)
        if render_open then
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_TextWrapped(
          ctx,
          "Naming pattern for the glued result (only applies when Cut Only, in the Shredder " ..
          "tab, is off - Cut Only leaves segments as separate items and never renames anything)."
        )
        reaper.ImGui_Spacing(ctx)

        reaper.ImGui_SetNextItemWidth(ctx, -1)
        local namepat_changed, new_namepat = reaper.ImGui_InputText(
          ctx, "##render_name_pattern", SD.render_name_pattern)
        if namepat_changed then
          SD.render_name_pattern = new_namepat
          reaper.SetExtState(EXT_SECTION, KEYS.Shredder_RENDER_NAME_PATTERN, SD.render_name_pattern, true)
        end

        reaper.ImGui_TextWrapped(
          ctx,
          "{name} original item's name  -  {number} incrementing counter  -  {mode} current " ..
          "Cut Mode  -  {date} YYYY-MM-DD  -  {time} HH-MM-SS"
        )

        do
          -- Live preview - uses the actually-selected item's name if
          -- there is one (falls back to a placeholder if not), and
          -- READS the counter without incrementing it (unlike an
          -- actual run), so just looking at this never burns a number.
          local preview_name = "MySample"
          local sel_item = reaper.GetSelectedMediaItem(0, 0)
          if sel_item then
            local sel_take = reaper.GetActiveTake(sel_item)
            if sel_take then
              local nm = reaper.GetTakeName(sel_take)
              if nm and nm ~= "" then preview_name = nm end
            end
          end

          local next_number = (tonumber(reaper.GetExtState(EXT_SECTION, "ShredderCounter")) or 0) + 1
          local preview = SD.render_name_pattern
          preview = preview:gsub("{name}", preview_name)
          preview = preview:gsub("{number}", tostring(next_number))
          preview = preview:gsub("{mode}", Shredder_cut_mode or "")
          preview = preview:gsub("{date}", os.date("%Y-%m-%d"))
          preview = preview:gsub("{time}", os.date("%H-%M-%S"))

          reaper.ImGui_TextColored(ctx, THEME_TEXT_DISABLED, "Preview: " .. preview)
        end
        reaper.ImGui_Dummy(ctx, 0, 8)

        end -- if render_open

        --reaper.ImGui_Unindent(ctx)

        reaper.ImGui_EndChild(ctx)
        end -- if settings_scroll_visible

        reaper.ImGui_EndTabItem(ctx)
      end

      reaper.ImGui_EndTabBar(ctx)
    end

    -- Compact, single-line status strip - kept OUTSIDE the tab bar
    -- (not folded into shredder_run_button()) since set_status() gets
    -- called from actions on other tabs too (palette/font color
    -- changes in Settings, for instance), not just Shredder tab
    -- actions - moving it inside the Shredder tab's pinned area would
    -- mean those other tabs' confirmations never show while you're
    -- actually looking at them. Trimmed down from its own separator +
    -- double spacing to a single tight line, both to look tidier and
    -- because STATUS_BAR_RESERVE_H below has to match this block's
    -- real height - the less padding here, the less guesswork there.
    reaper.ImGui_Separator(ctx)
    if status_warn then
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), STATUS_WARN_COLOR)
    end
    reaper.ImGui_TextWrapped(ctx, "Status: " .. status)
    if status_warn then
      reaper.ImGui_PopStyleColor(ctx)
    end

    reaper.ImGui_End(ctx)
  end

  -- Preview window (V6) - a separate, movable/resizable window rather
  -- than an inline section, so it doesn't eat space in the main tab.
  -- Begin() is only called while SD.show_preview is true (no point
  -- rendering a window nobody asked for); End() is always called
  -- once Begin() has been, regardless of the returned visible state.
  if SD.show_preview then
    reaper.ImGui_SetNextWindowSize(ctx, 700, 560, reaper.ImGui_Cond_FirstUseEver())
    local preview_visible, preview_open = reaper.ImGui_Begin(ctx, "Antisample Shredder - Preview", true)

    if preview_visible then
      reaper.ImGui_Text(ctx, "Cut lengths")
      reaper.ImGui_Spacing(ctx)

      local cut_reroll_clicked = reaper.ImGui_Button(ctx, "Reroll Cut Lengths", -1, 26)

      local preview_len, preview_is_real, preview_item_count = shredder_get_preview_item_length()

      local cut_fingerprint = table.concat({
        Shredder_cut_mode, Shredder_cut_length, Shredder_num_cuts,
        Shredder_beat_division, Shredder_beat_variance,
        SD.euclid_steps, SD.euclid_hits,
        SD.sequence_type, SD.fib_segments, SD.fib_descending and "1" or "0", SD.sequence_custom,
        SD.blackhole_start, SD.blackhole_decay, SD.white_hole and "1" or "0", SD.blackhole_loop and "1" or "0",
        SD.pitagora_triple,
        SD.collatz_seed, SD.collatz_descending and "1" or "0",
        SD.cantor_depth,
        SD.morse_text, SD.morse_unit_ms, SD.morse_loop and "1" or "0",
        preview_len,
        SD.min_seg_override_enabled and "1" or "0", SD.min_seg_override_ms,
      }, "|")

      if cut_reroll_clicked or cut_fingerprint ~= SD.cut_preview_fingerprint or not SD.cut_preview_data then
        local durations, note, hole_flags = compute_cut_length_preview()
        SD.cut_preview_data = { durations = durations, note = note, hole_flags = hole_flags }
        SD.cut_preview_fingerprint = cut_fingerprint
      end

      reaper.ImGui_Spacing(ctx)
      if SD.cut_preview_data.durations then
        local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
        local chart_h = SD.cut_chart_h
        local origin_x, origin_y = reaper.ImGui_GetCursorScreenPos(ctx)
        local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
        draw_cut_lengths_chart(
          draw_list, origin_x, origin_y, avail_w, chart_h,
          SD.cut_preview_data.durations, SD.cut_preview_data.hole_flags)
        reaper.ImGui_Dummy(ctx, avail_w, chart_h)
        SD.cut_chart_h = shredder_resize_handle(SD.cut_chart_h, 80, 500, KEYS.Shredder_CUT_CHART_HEIGHT)
        local exact_note = ""
        if Shredder_cut_mode == "cantor" then
          exact_note = " Amber bars are Cantor Dust's structural holes - fixed silence, not a " ..
            "random mute roll."
        elseif Shredder_cut_mode == "morse" then
          exact_note = " Amber bars are Morse's silent gaps (between symbols/letters/words) - " ..
            "fixed silence, not a random mute roll."
        end
        local item_note
        if preview_is_real then
          item_note = string.format("your selected item (%.2fs)", preview_len)
          if preview_item_count > 1 then
            item_note = item_note .. string.format(" - the first of %d selected", preview_item_count)
          end
        else
          item_note = string.format("a hypothetical %ds item (select an item to preview its own length)", preview_len)
        end
        reaper.ImGui_TextWrapped(
          ctx,
          "One realization of segment lengths (numbers are milliseconds) for " .. item_note ..
          " under your current Cut Mode settings. " ..
          "Euclidean, Sequence, Black/White Hole, Pitagora, Collatz, Cantor Dust, and Morse are " ..
          "exact; Length/Count/Beat involve randomness, so Reroll shows a different realization " ..
          "each time. Drag the small handle below the chart to resize it." .. exact_note
        )
      else
        reaper.ImGui_TextWrapped(ctx, SD.cut_preview_data.note)
      end

      reaper.ImGui_Dummy(ctx, 0, 8)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Dummy(ctx, 0, 8)

      reaper.ImGui_Text(ctx, "Chunk fate")
      reaper.ImGui_SameLine(ctx, 0, 16)
      local view_single_changed = reaper.ImGui_RadioButton(ctx, "Single item", SD.chunk_fate_view == "single")
      reaper.ImGui_SameLine(ctx)
      local view_multi_changed = reaper.ImGui_RadioButton(ctx, "Multi item", SD.chunk_fate_view == "multi")
      if view_single_changed then
        SD.chunk_fate_view = "single"
        reaper.SetExtState(EXT_SECTION, KEYS.Shredder_CHUNK_FATE_VIEW, SD.chunk_fate_view, true)
      elseif view_multi_changed then
        SD.chunk_fate_view = "multi"
        reaper.SetExtState(EXT_SECTION, KEYS.Shredder_CHUNK_FATE_VIEW, SD.chunk_fate_view, true)
      end
      reaper.ImGui_Spacing(ctx)

      if SD.chunk_fate_view == "single" then
        local reroll_clicked = reaper.ImGui_Button(ctx, "Reroll Chunk Fate", -1, 26)

        local fingerprint = table.concat({
          Shredder_subset_mode and "1" or "0", Shredder_subset_keep,
          SD.shuffle_mode, SD.local_window, SD.weighted_amount,
          Shredder_reverse, Shredder_mute, Shredder_repeat,
          Shredder_position_ms, Shredder_rate, Shredder_pitch, Shredder_pan, Shredder_volume,
          SD.palindrome and "1" or "0",
        }, "|")

        if reroll_clicked or fingerprint ~= SD.preview_fingerprint or not SD.preview_data then
          SD.preview_data = build_shredder_preview()
          SD.preview_fingerprint = fingerprint
        end

        reaper.ImGui_Spacing(ctx)
        local avail_w2 = reaper.ImGui_GetContentRegionAvail(ctx)
        local scale = math.max(0.6, math.min(2.5, SD.chunk_fate_h / 240))
        local origin_x2, origin_y2 = reaper.ImGui_GetCursorScreenPos(ctx)
        local draw_list2 = reaper.ImGui_GetWindowDrawList(ctx)
        reaper.ImGui_PushFont(ctx, current_font, math.max(8, math.min(40, math.floor(font_size * scale + 0.5))))
        draw_shredder_preview(draw_list2, origin_x2, origin_y2, avail_w2, scale, SD.preview_data)
        reaper.ImGui_PopFont(ctx)
        reaper.ImGui_Dummy(ctx, avail_w2, SD.chunk_fate_h)
        SD.chunk_fate_h = shredder_resize_handle(SD.chunk_fate_h, 160, 700, KEYS.Shredder_CHUNK_FATE_HEIGHT)

        reaper.ImGui_Spacing(ctx)
        local legend = {
          { color = THEME_ORANGE, label = "reverse" },
          { color = STATUS_WARN_COLOR, label = "mute" },
          { color = MARKER_POSITION, label = "position" },
          { color = MARKER_RATE, label = "rate" },
          { color = MARKER_PITCH, label = "pitch" },
          { color = MARKER_PAN, label = "pan" },
          { color = MARKER_VOLUME, label = "volume" },
        }
        for i, item in ipairs(legend) do
          reaper.ImGui_TextColored(ctx, item.color, "\xe2\x96\xa0")
          reaper.ImGui_SameLine(ctx, 0, 4)
          reaper.ImGui_Text(ctx, item.label)
          if i < #legend then reaper.ImGui_SameLine(ctx, 0, 12) end
        end

        reaper.ImGui_TextWrapped(
          ctx,
          "6 demo chunks moving through your Structural Mode settings (drop, shuffle, repeat, " ..
          "palindrome). Bar height under each Final order box = how much of that property's range " ..
          "this chunk got (flat = that slider is at 0/neutral, so it isn't touching anything right " ..
          "now); faded box = dropped, \"+\" = repeat, \"~\" = palindrome mirror. Sidechain dropping " ..
          "isn't simulated here since it depends on real audio. Drag the small handle above this " ..
          "text to resize the diagram - boxes and text scale up together. This never touches your " ..
          "actual items - only Run Shredder does."
        )
      else
        local mash_reroll_clicked = reaper.ImGui_Button(ctx, "Reroll Mash", -1, 26)

        local mash_fingerprint = table.concat({
          Shredder_mash_mode and "1" or "0",
          Shredder_subset_mode and "1" or "0",
          SD.shuffle_mode, SD.local_window, SD.weighted_amount,
        }, "|")

        if mash_reroll_clicked or mash_fingerprint ~= SD.mash_preview_fingerprint or not SD.mash_preview_data then
          SD.mash_preview_data = build_mash_preview()
          SD.mash_preview_fingerprint = mash_fingerprint
        end

        reaper.ImGui_Spacing(ctx)
        local avail_w3 = reaper.ImGui_GetContentRegionAvail(ctx)
        local mash_scale = math.max(0.6, math.min(2.5, SD.mash_preview_h / 220))
        local origin_x3, origin_y3 = reaper.ImGui_GetCursorScreenPos(ctx)
        local draw_list3 = reaper.ImGui_GetWindowDrawList(ctx)
        reaper.ImGui_PushFont(ctx, current_font, math.max(8, math.min(40, math.floor(font_size * mash_scale + 0.5))))
        draw_mash_preview(draw_list3, origin_x3, origin_y3, avail_w3, mash_scale, SD.mash_preview_data)
        reaper.ImGui_PopFont(ctx)
        reaper.ImGui_Dummy(ctx, avail_w3, SD.mash_preview_h)
        SD.mash_preview_h = shredder_resize_handle(SD.mash_preview_h, 140, 600, KEYS.Shredder_MASH_PREVIEW_HEIGHT)

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_TextColored(ctx, MARKER_ITEM_A, "\xe2\x96\xa0")
        reaper.ImGui_SameLine(ctx, 0, 4)
        reaper.ImGui_Text(ctx, "Item A")
        reaper.ImGui_SameLine(ctx, 0, 12)
        reaper.ImGui_TextColored(ctx, MARKER_ITEM_B, "\xe2\x96\xa0")
        reaper.ImGui_SameLine(ctx, 0, 4)
        reaper.ImGui_Text(ctx, "Item B")

        reaper.ImGui_TextWrapped(
          ctx,
          "2 demo items with 4 chunks each, reflecting your CURRENT \"With multiple items " ..
          "selected\" mode from the Shredder tab: Mash Together pools every item's chunks and " ..
          "reorders across the whole set - watch the colors mix in the Final row. Process " ..
          "Individually reorders each item's chunks only among their own original slots - colors " ..
          "never cross. Same Shuffle Mode/Ordered-Subset rules as Single item apply here too."
        )
      end
    end

    reaper.ImGui_End(ctx)

    if preview_open ~= SD.show_preview then
      SD.show_preview = preview_open
      reaper.SetExtState(EXT_SECTION, KEYS.Shredder_SHOW_PREVIEW, SD.show_preview and "1" or "0", true)
    end
  end

  -- Preset browser - a separate popup window, same pattern as the
  -- Preview window above. Opened by clicking the preset name field or
  -- the Load button at the top of the Shredder tab. Lists every saved
  -- preset as a button (click to load it and close the browser) with
  -- a small delete button alongside - no confirmation dialog before
  -- delete, so treat it as immediate.
  if SD.preset_browser_open then
    reaper.ImGui_SetNextWindowSize(ctx, 420, 420, reaper.ImGui_Cond_FirstUseEver())
    local browser_visible, browser_open = reaper.ImGui_Begin(ctx, "Antisample Shredder - Presets", true)

    if browser_visible then
      reaper.ImGui_TextWrapped(ctx, "Click a preset to load it. Saved as plain text files in:")
      reaper.ImGui_TextColored(ctx, THEME_TEXT_DISABLED, shredder_preset_dir())
      reaper.ImGui_Dummy(ctx, 0, 8)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Dummy(ctx, 0, 8)

      local preset_names = shredder_list_presets()
      if #preset_names == 0 then
        reaper.ImGui_TextWrapped(ctx, "No presets saved yet - type a name in the bar above and hit Save.")
      else
        local del_w = 28
        local gap = 8
        local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
        local row_w = avail_w - del_w - gap
        for _, preset_name in ipairs(preset_names) do
          local label = preset_name
          if preset_name == SD.preset_name then label = label .. "  (current)" end
          if reaper.ImGui_Button(ctx, label .. "##load_" .. preset_name, row_w, 0) then
            shredder_load_preset(preset_name)
            set_status("Loaded preset: " .. preset_name, false)
            SD.preset_browser_open = false
          end
          reaper.ImGui_SameLine(ctx, 0, gap)
          if reaper.ImGui_Button(ctx, "x##del_" .. preset_name, del_w, 0) then
            shredder_delete_preset(preset_name)
            set_status("Deleted preset: " .. preset_name, false)
          end
        end
      end
    end

    reaper.ImGui_End(ctx)

    if browser_open ~= SD.preset_browser_open then
      SD.preset_browser_open = browser_open
    end
  end

  pop_theme(theme_count)
  reaper.ImGui_PopFont(ctx)

  if open then
    reaper.defer(draw)
  end
end

draw()
