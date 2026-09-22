# Changelog

All notable changes to Antisample Shredder (`Antisample_Shredder_UI.lua` +
`Antisample_Shredder_Engine.lua`) are documented here, newest first.

Entries prefixed `v1.x` cover the current, fixed-filename era. Entries prefixed
`V2`-`V11` (no decimal) predate that convention, when each major revision of the
UI shipped under its own versioned filename (`Antisample_Shredder_UI_V2.lua`,
`_V3.lua`, and so on) - those entries are preserved here exactly as originally
written, including their references to those older filenames.

## v1.47

Swapped the Mode toggle (Mash Together/Process Individually) and Open Preview Window buttons' order in "Now, Put It Together..." - Mode toggle first, Preview second (was the other way round) - and added a trailing `shredder_gap(true)` after Preview, matching the same gap already used between the two buttons, so the section has consistent bottom spacing rather than ending flush against its closing `end`.

## v1.46

Two collapsible-section cleanups. Fixed a real leftover-separator bug: a `Dummy`/`Separator`/`shredder_gap` block right after "Now, Put It Together..."'s closing `end` was outside that section's `if structural_open then` guard, so it rendered regardless of whether the section was actually expanded - visible as a stray line under the collapsed header with nothing above it. Removed entirely, since the other header-to-header transition (Chunk Randomization into what used to be Multi Shred-Masher) already had no such separator and read fine on its own - `CollapsingHeader` widgets don't need manual dividers between them. Also merged the old standalone "MULTI SHRED-MASHER" section - a single Mash Together/Process Individually toggle button - into the end of "Now, Put It Together...", since one button didn't need a whole collapsible section of its own. Picked up a help-text explanation for that button along the way, since it didn't have one before in either location.

## v1.45

Fixed the main window needing to scroll slightly whenever Run Shredder is pinned. Root cause: the scrollable child region's negative-margin reserve (`BeginChild`, Shredder tab) only ever accounted for the Run Shredder button's own height, and only in bottom-pin mode - it didn't know about the status bar drawn after `EndTabBar()`, at the true bottom of the window, in either pin position. Top-pin mode used a reserve of `0` ("fill all remaining space"), which has the identical gap: filling all remaining space also doesn't leave room for the status bar below it. Fixed by reserving for both the button and the status bar, in both pin positions (`RUN_BUTTON_RESERVE_H` + `STATUS_BAR_RESERVE_H`, only the button's contributing when top-pinned). Also compacted the status bar itself from `Spacing + Dummy + Separator + Spacing` down to a single tight `Separator` + text line - simpler, and shrinks the margin of error in the fixed-pixel reserve estimate that now has to roughly match its real height. Status stayed outside the tab bar rather than moving into the Shredder tab's pinned area specifically, since `set_status()` is called from actions on other tabs too (palette/font color changes in Settings, for instance) - folding it into the Shredder-tab-only pinned area would mean those confirmations never show while actually looking at them.

## v1.44

Release prep - renamed both files, dropping the "_V5" version suffix now that version history lives entirely in this changelog: Antisample_Shredder_UI_V5.lua -> Antisample_Shredder_UI.lua, and the engine's Antisample_Shredder_V5.lua -> Antisample_Shredder_Engine.lua (see the updated note right below the version line above for the full reasoning). Every live cross-reference between the two files was updated to match - the @provides tag, the SCRIPT_SHREDDER path construction, and the run_script() display-name argument - and cross-checked afterward with a full-file sweep for any remaining "_V5" fragment, confirming only historical changelog text (correctly left alone) and the new explanatory note remained. The engine's own @noindex comment (which names this file) was updated to match, and its Undo History label - stuck at "Shredder V11" since long before either file had a changelog to speak of - was cleaned up to "Antisample Shredder" while touching this anyway. No functional changes to either file's actual behavior.

## v1.43

pairs with a real engine change - see the (now-updated) APPENDIX (V16) note in Antisample_Shredder_V5.lua. The Randomized/Fixed toggle (Settings > Shredder Behaviour) now also covers By Number of Cuts, not just By Cut Length - the SAME toggle, no second button/checkbox added, per how this was asked for. Fixed now means: By Cut Length's segments are exactly its slider's value (as before) AND By Number of Cuts produces exactly that many cuts every time, instead of its usual +/-20% organic variance (a setting of 2 could genuinely produce 1-3 cuts = 2-4 segments before this). Renamed the section header from "Cut Length Mode" to "Cut Variance" and rewrote its explanation to cover both modes - the ExtState key/setting name (ShredderCutLengthFixed/cut_length_fixed) weren't renamed to match, since a rename would need a migration path for no functional benefit; only the label the person actually sees changed.

## v1.42

UI-only - no engine changes. Real bug fix: Init silently left Shredder not shuffling even with Shuffle Mode showing "Full Shuffle" selected in the UI. Root cause: shredder_init_everything() reset shuffle_mode to "" (empty string), following the same pattern used for sequence_type/scale_type elsewhere in that same function - but those two are safe because the engine's own fallback for an unrecognized value goes straight to a literal default. Shuffle Mode is different: the engine treats an explicitly empty "ShredderShuffleMode" as a signal to check an entirely separate LEGACY flag, "ShredderNoShuffle" (predating Shuffle Mode being a multi-option dropdown at all), and that flag can silently resolve to "none" depending on its own unrelated, possibly-stale ExtState value
- meanwhile the UI's dropdown shows "Full Shuffle" regardless, since
find_shuffle_mode_index() also falls back to displaying index 0 (Full) for any unmatched value, including "". Two different kinds of "empty means default" logic, quietly disagreeing with each other. Fixed by writing the literal "full" (matching the dropdown's own explicit value for that entry) instead of "" - traced and confirmed against the actual engine source before changing anything, not guessed from symptoms. The engine's legacy-fallback path itself was deliberately left untouched - it still correctly serves genuinely old installs that have never touched Shuffle Mode at all; only Init's own reset value was wrong.

## v1.41

UI-only - no engine changes. Removed the entire animation/glitch feature family (v1.28-v1.31) - per feedback that it didn't hold up long-term and was distracting enough to end up disabled more often than not. Specifically removed:
- The Run Shredder glitch burst (all-text RGB flicker on click) - GLITCH_DURATION, GLITCH_STEP_RATE, glitch_start_time, shredder_glitch_active(), shredder_glitch_text_color(), and the Col_Text push/pop in draw() that applied it.
- The per-slider drag artifacts (flickering particles while dragging a Per-Segment Randomization slider) - shredder_slider_artifact() and its 8 call sites, one per slider.
- The near-max label channel-split effect (the one we'd specifically reworked to be gradual/non-animated last time) - shredder_slider_label() is now a plain one-line label draw; kept its (text, value, min_val, max_val) signature even though the last three go unused now, so none of the 8 call sites needed touching, only the function body did.
- glitch_hash() (the shared deterministic sine-hash helper) - no longer used by anything once the three effects above were gone.
- The "Disable animations/visuals" checkbox, and its disable_visuals SD field/KEYS entry - nothing left for it to disable.
Everything else - the standalone Glitch_Header_Prototype.lua mockup, and any purely descriptive use of the word "glitch" (the tool's own description, "glitch-melody generator", etc.) - is untouched; this was specifically the animation/visual-flourish code, not the word.

## v1.40

UI-only - no engine changes. Settings tab reorganized into two collapsible groups, same CollapsingHeader pattern as the Shredder tab's three (SetNextItemOpen + Cond_FirstUseEver, both default open):
- "Appearance": Font size, Color Palette, Font Color, and Layout (Run Shredder button position + Compact Mode) - Layout moved here from its own standalone section.
- "Shredder Behaviour": Cut Length Mode (moved here from its own section at the very top of the tab) plus the original Shredder Behavior content (Cut but don't render, Hide Helper Text, Disable Animations/Visuals) - dropped the redundant inner "Shredder Behavior" sub-label once it was nested inside a "Shredder Behaviour" header, since having both was just repeating itself.
Randomization Settings and Render Settings weren't touched - still their own plain (non-collapsible) sections, in the same relative order as before, right after Shredder Behaviour.

## v1.39

UI-only - no engine changes. Init and Random both moved from inside the (collapsible, easy to miss) Chunk Randomization section up to the top of the tab, right below the preset bar - always visible now, the same reasoning as why Run Shredder itself got pinned rather than living wherever a long scroll happened to leave it. Init's scope changed significantly: it used to reset only the eight Per-Segment Randomization sliders; shredder_init_everything() now resets EVERY sound-affecting Shredder setting - Cut Mode and every mode-specific param, Structural Modes, Per-Segment Randomization, Multi-item mode, 55 settings in total. Every default value was cross-checked directly against each field's own live `or <default>` fallback (or its post-load validation, for the few that resolve an empty string to a sensible default) rather than re-guessed from memory - and then verified as an exact set match against SHREDDER_PRESET_SCHEMA (same 55 keys, neither list missing anything the other has), not just a matching count. Random is functionally unchanged - moved, not modified - still only the eight per-segment sliders, still respecting the Randomization Settings checkboxes in the Settings tab.

## v1.38

pairs with a real engine change - see the APPENDIX (V16) note in Antisample_Shredder_V5.lua. Turns out "By Cut Length" was never actually producing segments AT its Cut Length setting - it's randomized +/-50% around that value by design (an organic feel was always the point of the mode), so a 500ms setting really meant "somewhere between 250-750ms," which read as a bug when asked about directly. New Settings tab section, "Cut Length Mode": Randomized (default, unchanged) / Fixed (every segment exactly the Cut Length slider's value, no randomization) toggle, styled like the Direction/Pin Position buttons. Per how this was asked for, it lives in Settings rather than next to the Cut Length slider itself - but since it genuinely changes what a run sounds like (unlike most of what else is in Settings), it IS part of the preset schema.

## v1.37

UI-only - no engine changes. Condensed layout, phase 2: Structural Modes, Chunk Randomization, and Multi-item are now CollapsingHeader sections instead of always-expanded - click the (still oversized, still punchy) section title to fold it up. Cut Mode stays always-expanded, deliberately - it's the primary choice, not something to tuck away. All three default to OPEN on first use (reaper.ImGui_SetNextItemOpen(ctx, true, Cond_FirstUseEver()) before each header - reuses Cond_FirstUseEver, already proven elsewhere in this file for window sizing, rather than the CollapsingHeader flags argument directly, to avoid a second source of uncertainty about exact flag-passing syntax) - collapsing state is then remembered by ImGui itself per label, same as any other CollapsingHeader, no extra bookkeeping needed on this end. The Preview button lives inside Structural Modes' section (folds with it); the hidden sidechain UI still nests correctly inside Chunk Randomization's.

## v1.36

UI-only - no engine changes. Condensed layout, phase 1 (pinning the Run Shredder button - collapsible sections and a deeper Compact Mode sweep are a planned follow-up, not part of this pass):
- Everything in the Shredder tab except the preset bar and Run Shredder itself now lives in its own scrollable child region (BeginChild/EndChild - new API for this file, verified against real ReaImGui documentation first: EndChild() must only be called when BeginChild() returned true, a genuine ReaImGui-specific gotcha that differs from upstream Dear ImGui's C++ convention, confirmed via a real bug report before writing any code, not assumed). This fixes the actual bug: in a narrow dock or small window, Run Shredder used to be wherever the bottom of one long, single-stack layout happened to land - now it's pinned and the settings scroll independently underneath/above it.
- New Settings tab "Layout" section: a Top/Bottom toggle (Settings > Layout > Run Shredder button position, default Bottom, highlighted the same way as the Direction buttons) for which end of the tab the button pins to, and a "Compact Mode" checkbox that tightens spacing at the three major section breaks (Cut Mode -> Structural Modes -> Chunk Randomization -> Multi-item) via a new shredder_gap() helper. Both are layout preferences, not sound settings, so neither is part of the preset schema.
- Caught and fixed two real mistakes while building this, worth recording honestly rather than glossing over: an early version split the required BeginChild/EndChild guard across two separate if-blocks instead of one continuous one (a genuine syntax error, caught immediately by luac); and a later edit accidentally deleted the "Render Settings" header and part of its following text, caught by grepping for that header right after the edit and not finding it, then restored and re-verified with a full line-by-line re-read of the affected region.

## v1.35

pairs with a real engine change - see the APPENDIX (V15) note in Antisample_Shredder_V5.lua. New "Scatter Repeats" checkbox right under Number Of Repeats in the Shredder tab: off (default), repeat copies cluster immediately after their original, same as always ("A A A A B C"); on, copies land at random positions throughout the result instead ("A B A C A B") - the base order from Shuffle Mode/Palindrome/etc is unaffected either way, only where the EXTRA duplicate copies go. Unlike the last several additions (Render Settings, Randomization Settings, Disable Visuals, Hide Helper Text), this genuinely changes what a run sounds like, so it lives on the Shredder tab itself (not Settings) and IS part of the preset schema.

## v1.34

pairs with a real engine change - see the APPENDIX (V14) note in Antisample_Shredder_V5.lua. New "Render Settings" section in the Settings tab: a text field for the glued result's naming pattern, using {name}/{number}/{mode}/{date}/{time} wildcards (full list and exactly how each resolves in the engine's appendix note), a wildcard reference line, and a live preview that uses the actually-selected item's real name when there is one and reads (without incrementing) the persistent render counter, so just looking at the Settings tab never burns a number. Only applies when Cut Only (Shredder tab) is off, since Cut Only never renders or renames anything. Defaults to "Shredder_{number}" - identical to the old fixed naming, so nothing changes for anyone who doesn't touch this. Not part of the preset schema, same reasoning as Hide Helper Text/Disable Visuals/Randomization Settings - a workflow/output preference, not something that changes what a run sounds like.

## v1.33

UI-only - no engine changes. New "Randomization Settings" section in the Settings tab: 8 checkboxes in 2 columns (Position/Rate, Pitch/Pan, Volume/Reverse, Repeat/Mute), one per Per-Segment Randomization property, controlling ONLY what the Random button (Shredder tab) is allowed to reroll - an unchecked property is left completely untouched by Random, not zeroed or reset. Manually dragging a slider and the Init button are unaffected either way - this only gates Random's own randomization pass. All default checked (on), matching Random's original behavior before this setting existed. Deliberately NOT part of the preset schema, same reasoning as Hide Helper Text/Disable Visuals - this is about how a UI shortcut button behaves, not a setting that changes what a run sounds like.

## v1.32

UI-only - no engine changes. Rate/Reverse Cut/Number Of Repeats/Chunk Mute now get the same gradual near-max label effect as Position/Pitch/Pan/Volume - the follow-up flagged back in v1.30. Converted each from ImGui's own auto-drawn slider label to a hidden "##..." label plus a separate shredder_slider_label() call afterward (the same restructuring Position/Pitch/Pan/Volume already needed for their Direction buttons), so all eight Per-Segment Randomization sliders now behave identically: shredder_slider_artifact() first (reads the slider's own rect/active-state, so it has to run before anything else is drawn), then SameLine, then the label itself. All 8 use exactly the same shredder_slider_label() function with each slider's own real min/max, so the gradual ramp-from-halfway behavior from v1.31 applies uniformly - no separate tuning needed per slider.

## v1.31

UI-only - no engine changes. Reworked the near-max label effect from v1.30 based on feedback that it was too busy and kicked in too late. Two changes:
- No more animation. v1.30's version jittered the channel-split offset every ~0.1s via reaper.time_precise(), the same timed technique as Run Shredder's glitch burst. Removed entirely - the offset and opacity are now a pure function of the CURRENT VALUE, nothing time-based at all, so a slider sitting still shows a perfectly still label; only actually moving the value changes it.
- Gradual instead of on/off. Was a binary switch at 85% of range (SHREDDER_NEAR_MAX_FRAC); now starts ramping in at the halfway point (SHREDDER_NEAR_MAX_START = 0.5) and increases smoothly - both the channel-split offset (0 to 2.5px) and the color layers' opacity (barely-there to fairly strong) scale together in direct proportion to how far past 50% the value is, reaching full strength exactly at max instead of snapping on abruptly.

## v1.30

UI-only - no engine changes. Position/Pitch/Pan/Volume's labels now switch to a proper RGB channel-split "chromatic aberration" glitch (three layered DrawList_AddText calls - magenta and cyan copies offset in opposite directions, the real text dead-center on top so it stays legible) once the slider's value climbs into the top 15% of its range (SHREDDER_NEAR_MAX_FRAC = 0.85) - visibly different from, and stronger than, the plain Col_Text flicker Run Shredder/slider-drag artifacts use, since this flags a specific meaningful moment (near-max) rather than a brief timed or drag-driven effect. Respects Disable Animations/Visuals like everything else in this family.

Rate/Reverse Cut/Number Of Repeats/Chunk Mute are NOT included yet - they still use ImGui's own auto-drawn slider label rather than a separately-drawn one like the other four, so adding this to them means converting them to the same hidden-label + manual-draw pattern first, not just calling an existing function with new arguments. Left as a deliberate follow-up rather than rushed in alongside this.

## v1.29

UI-only - no engine changes.
- Per-Segment Randomization sliders (Position, Rate, Pitch, Pan, Volume, Reverse, Repeats, Mute - all eight, as a trial) now show a small flicker of colored particles right on the slider itself while you're actively dragging it - same stepped pseudo-random technique as the Run Shredder glitch, but driven by IsItemActive() instead of a timed burst, and confined to the slider's own bounding box (via GetItemRectMin()/GetItemRectMax(), the exact pattern shredder_resize_handle() already used for the Preview window's resize grip) rather than the whole screen.
- New Settings tab option, "Disable animations/visuals": turns off both the Run Shredder glitch burst and the slider-drag flicker in one switch. Purely decorative either way - nothing functional changes, and it's deliberately NOT part of the preset schema (same reasoning as Hide Helper Text) since it's an appearance preference, not a setting that affects what a run sounds like.

## v1.28

UI-only - no engine changes. Run Shredder now triggers a brief (0.7s) glitch effect across ALL text in the app: an RGB-flicker of Col_Text (mostly magenta/cyan/white, dropping back to the normal color on about a third of steps so it reads as "the text glitching" rather than "the text replaced") - stepped ~14x/second, not smoothly animated, since sudden jumps read as digital corruption where smooth motion just reads as an animation. Since run_script() calls dofile() directly (synchronous, blocks the frame), the burst starts the instant the button is clicked and plays out over the next several real frames once control returns - decoupled from actual processing time, which in practice is usually too fast to see happen live anyway. Deliberately doesn't touch text that sets its own color (TextColored - warnings, dimmed hints) - those stay legible and their color stays meaningful even mid-glitch. Same deterministic sine-hash technique as the standalone Glitch_Header_Prototype.lua mockup, just applied as one global Col_Text push instead of manual per-character DrawList calls.

## v1.27

UI-only - no engine changes. Presets now live in a "Presets" subfolder next to this script (SCRIPT_DIR .. "Presets") instead of REAPER's Data folder - so a distributed copy of this tool (ReaPack or a plain manual copy) that includes a Presets/ folder alongside the .lua files ships with working default presets immediately, no separate install step, and everything lives together in one place. Existing presets saved under the old location (REAPER's resource path, Data/AntisampleShredder/Presets/) aren't moved automatically - copy that folder's .txt files into the new Presets/ folder next to this script if you want to keep them.

## v1.26

pairs with a real engine fix - see the (now-updated) APPENDIX (V13) note in Antisample_Shredder_V5.lua. v1.25's fix was incomplete - the actual root cause was a SECOND, pre-existing selection/range mechanism in main() that runs once at the very end, after every originally-selected item has been processed, and immediately overwrote whatever v1.25's per-item fix had just set. finish_segments() now always returns a full list of its results (every segment with Cut Only on, not just one) instead of a single arbitrary item, and main() collects every call's results into one flattened list before doing select/range/cursor exactly once, over everything. Root-caused rather than patched again - group_segments() (renamed from select_group_and_set_range(), since it now only handles grouping) no longer touches selection or the time range at all; that's main()'s job alone now, for both Cut Only and normal glue runs.

## v1.25

pairs with a real engine fix - see the (now-updated) APPENDIX (V13) note in Antisample_Shredder_V5.lua. Cut but don't render's "make a selection" (from the v1.13 request: select items, make a selection, move the playhead) was never actually implemented as its own step - only the edit cursor got moved, so there was nothing spanning the cut region at all, not even the first segment. Fixed: select_group_and_set_range() (renamed from select_group_and_move_cursor(), since it now does more than that) sets the project's time selection to span from the EARLIEST segment's start to the LATEST segment's end - a min/max over every segment, not just whichever happens to be first in the list, since shuffling means segment order and timeline order aren't the same thing.

## v1.24

pairs with a real engine change - see the APPENDIX (V13) note in Antisample_Shredder_V5.lua. Also renamed the "UI Settings" tab to "Settings", since it's no longer just appearance.
- Cut but don't render (Settings tab, default ON): Run Shredder cuts/shuffles/randomizes exactly as normal, but stops short of the final glue - the resulting segments stay as separate items, selected and grouped together (a fresh I_GROUPID, same effect as REAPER's own "Group items"), with the edit cursor moved to the start of the selection. Turn it off to get the old glue-into-one-item behavior back.
- Hide helper text (Settings tab): hides the 18 explanatory paragraphs throughout the Shredder tab (what each Cut Mode/Structural Mode/setting does) while leaving every control's own label, slider, and value exactly as visible as always. The two LIVE preview captions (Sequence's "Weights: ...", Morse's "... --- ..." pattern) are deliberately NOT helper text and stay visible regardless, since they show your actual current settings rather than static explanation.
- Removed "Show bypass console output" - a leftover from an older, unrelated feature (Random FX Chain / Randomize Existing FX Parameters bypass-count logging), not used by anything in the Shredder tab. Turned out to reference an implicitly-global Lua variable that was never properly declared anywhere - a real, if harmless, bug in its own right, now moot since the whole checkbox is gone.

## v1.23

pairs with a real engine change - see the (now-updated) APPENDIX (V12) note in Antisample_Shredder_V5.lua. Removed Jitter % entirely, after testing showed it made every parameter depend on remembering to raise a separate master dial first - each of the eight Per-Segment Randomization sliders is back to controlling its own amount directly, no master gate, the way this section worked before either Jitter mechanism (the original Enabled/Disabled toggle, then Jitter %) existed. Direction (added alongside Jitter %) is unaffected and still here. Also removed the now-dead jitter_saved SD field, a leftover from the original toggle that nothing has read since v1.21.

## v1.22

UI-only - no engine changes, still launches Antisample_Shredder_V5.lua.
- Fixed the Direction buttons' layout: they now sit right after the slider with a small gap, and the slider's own label moves to AFTER the buttons (also with a gap) instead of sitting between the slider and the buttons - [slider][buttons][label], not [slider] [label][buttons]. Required giving each of the four sliders a hidden "##..." label and an explicit reserved width, since the visible label is now drawn by shredder_direction_buttons() itself.
- The active direction button now uses THEME_ORANGE_ACTIVE (the darkest of the app's three orange shades) instead of plain THEME_ORANGE, so "this one is selected" is actually visible at a glance rather than blending into the hover color.
- Direction wasn't actually broken - Jitter % (added last version) gates ALL EIGHT per-segment properties, Direction included, and it defaults to 0% (deliberately - see the v1.21 entry below). At 0%, every direction looks identical because none of them do anything, which is exactly the "nothing happens in any direction" report. Not a bug, but clearly not obvious enough - the caption under Jitter % now turns into a colored warning specifically when it's at 0%, spelling out that Direction (and everything else in the section) is inert until it's raised.

## v1.21

pairs with a real engine change - see the APPENDIX (V12) note in Antisample_Shredder_V5.lua. Two related reworks of Per-Segment Randomization:
- Direction: <-, <->, -> buttons now sit next to Position, Pitch, Pan, and Volume (the four properties centered on a neutral value) - constrain each to only its negative half (down/left/quieter/earlier), only its positive half (up/right/louder/later), or both (the original behavior, still the default). Rate/Reverse/Repeats/Mute don't have a comparable notion of direction, so they don't get these buttons.
- Jitter % replaces the old Jitter Enabled/Disabled toggle. That toggle only affected Position/Pitch/Pan/Volume, leaving Rate/Reverse/Repeats/Mute always fully active regardless of its state - a real bug, not just a naming quibble, since "jitter" implied it covered everything. This is a single master intensity (0-100%, default 0) that scales ALL EIGHT sliders below uniformly - each still sets its own ceiling; this is how much of that ceiling actually applies. At 0% nothing randomizes at all, genuinely disabled by default rather than depending on remembering to zero eight sliders individually. The old jitter_saved remember/restore mechanism is gone - there's nothing to remember now, since the sliders themselves never get touched by this, only scaled.
- Both new setting groups are covered by presets (added to SHREDDER_PRESET_SCHEMA), same as everything else in this section.

## v1.20

UI-only - no engine changes, still launches Antisample_Shredder_V5.lua.
- Fixed a real crash: the preset bar's "Random" button and the existing Per-Segment Randomization "Random" button both used the plain label "Random" with no ID suffix - Dear ImGui derives widget IDs from their label text, so two identically-labeled buttons in the same window is a genuine ID collision, not a cosmetic issue. Renamed the preset one to "Random##preset" (still displays as "Random" - the ##suffix is ID-only, invisible in the UI).
- Removed clicking the preset name field to open the browser popup - it got in the way of quickly typing a name to Save. The Load button still opens the browser; the field is now just for typing.
- Saving over an existing preset name now asks for confirmation (a native yes/no dialog) before overwriting, instead of silently replacing it.

## v1.19

UI-only - no engine changes, still launches Antisample_Shredder_V5.lua. Adds preset save/load/randomize:
- A bar at the top of the Shredder tab: a name field (click it, or the Load button, to open the preset browser popup) plus Save / Load / Random buttons.
- Presets are plain-text files (one line per setting) in REAPER's resource folder under Data/AntisampleShredder/Presets/ - visible, backupable, and hand-editable, not buried in ExtState.
- A preset covers every SOUND-affecting Shredder setting (Cut Mode and its params, Structural Modes, Per-Segment Randomization) - deliberately not this app's other tabs, and not Shredder's own UI-layout prefs (preview window sizes, which view is open). See the SHREDDER_PRESET_SCHEMA comment for the exact scope.
- Loading updates both ExtState (so it's still there next session) and whatever live variable actually drives the UI, so the change is visible immediately - no restart needed.
- Also fixed two pre-existing bugs found while building this: SHREDDER_VALID_CUT_MODES (a startup validation list, separate from the Cut Mode selector's own list) was missing Pitagora/Collatz/Cantor Dust/Morse, so a saved cut mode of any of those four would silently reset to "By Cut Length" on every restart - the exact failure mode preset loading would otherwise have hit immediately. Also, the engine filename shown in a status message still said "Antisample_Shredder_V11.lua" after the actual file was renamed to V5.lua - cosmetic only, but now correct.

## v1.18

UI-only - no engine changes, still launches Antisample_Shredder_V5.lua.
- The three-column Cut Mode selector's gap is now 14px (was 5px, requested; then effectively 0px again after the v1.17 header-alignment fix reverted to absolute positioning). Couldn't verify the exact cause by testing live in REAPER, but the most likely culprit is a combo box's real rendered width exceeding what SetNextItemWidth requests by a few pixels (internal frame/border overhead) - a 5px gap has no margin against that; 14px does, regardless of the exact overhead amount.
- Added a "Random" button between Init and Jitter in Per-Segment Randomization: rolls a fresh random value for every slider in that section (Position, Rate, Pitch, Pan, Volume, Reverse, Repeats, Chunk Mute), each within its own normal range - Cut Mode and its settings are never touched, only the per-segment intensities.

## v1.17

UI-only - no engine changes, still launches Antisample_Shredder_V11.lua, which will now also keep this exact filename for future updates rather than incrementing further.
- Fixed a real crash: every dropdown's item-string had a doubled trailing "\0" (e.g. "A\0B\0C\0\0" instead of "A\0B\0C\0") - ReaImGui appears to already NUL-terminate the buffer during its Lua-to-C marshalling, so the extra manually-appended null created a genuine spurious blank entry at the end of every combo. Selecting it returned an index one past the real list, and indexing that result crashed with "attempt to index a nil value". Fixed at the source (removed the extra "\0" from all 6 combo item-string constructions) and added defensive nil-guards on every combo's selection handler as a safety net, so an out-of-range index can never crash the script again even if something like this recurs.
- Fixed the three-column Cut Mode selector's header labels (Classic/Sequence/Bizarre) not lining up above their dropdowns - the v1.14 gap fix switched to relative spacing for BOTH the header row and the combo row, but headers have narrower, content-dependent text widths than the combos' forced-equal widths, so relative spacing made the headers drift out of alignment (each one placed just after the PREVIOUS header's own narrow width, not the wider column boundary below it). Both rows now use the same absolute, precomputed column offsets, so headers and combos always agree.

## v1.16

pairs with a real engine change - now launches Antisample_Shredder_V11.lua (was V10). Adds "Morse" to the Bizarre column: type a message, and it's encoded into real Morse timing (dot = 1 unit, dash = 3 units, longer silent gaps between letters/words) laid out as one chunk per symbol - dots/dashes are audible, every gap is forced silent via the same structural-mute mechanism Cantor Dust uses (generalized from CANTOR_HOLE_INDICES to the shared STRUCTURAL_MUTE_INDICES on the engine side), so the mute pattern in the glued result genuinely spells out the message. A live "... --- ..." readout shows under the Message field. Loop (default on) restarts the message once fully placed, reusing the exact same "restart the cycle once exhausted" idea Black/White Hole's Loop added in v1.13 - a short message like "SOS" still covers a long item instead of leaving most of it as one untouched leftover chunk. Fully deterministic (no randomness), so it's wired into the Cut Lengths preview chart as an "exact" mode alongside Euclidean/Sequence/Pitagora/Collatz/Cantor Dust, with its own silent gaps shown as amber bars just like Cantor Dust's holes.

## v1.15

pairs with a real engine change - now launches Antisample_Shredder_V10.lua (was V9). Renamed "Pithalgora" to "Pitagora" - the original name was an invented portmanteau; "Pitagora" is the actual Italian/Spanish name for Pythagoras, so it's more directly recognizable as what the mode actually is. Purely a rename, no behavior changed. A saved Cut Mode of "pithalgora" and a saved triple choice under the old ExtState key both migrate automatically
- nothing resets for existing users. (Older changelog entries below
still say "Pithalgora" - that was its correct name at the time, left as accurate history rather than rewritten.)

## v1.14

UI-only - no engine changes, still launches Antisample_Shredder_V9.lua. Fixes the three-column Cut Mode selector's inconsistent gaps (Classic/Sequence were touching while Sequence/Bizarre had a visible gap) - was using precomputed absolute SameLine offsets that could drift out of sync with each column's actual rendered width; switched to relative spacing (SameLine(ctx, 0, col_gap), placing each column right after the previous one's real edge) which is immune to that drift. Gap is now a consistent 5px (was intended to be 8px, but never rendered consistently).

## v1.13

pairs with a real engine change - now launches Antisample_Shredder_V9.lua (was V8). Fixes a real design gap in Black/White Hole, not just a tweak: a geometric series has a FINITE sum even carried out forever (Starting Size / (1 - Decay)), so with the defaults, one collapse cycle only ever covered exactly 3 seconds REGARDLESS of item length - everything past that was one large, completely unprocessed leftover chunk. Added a "Loop" checkbox (default ON) that restarts the collapse from Starting Size once it bottoms out, repeating for as long as the item has room, so the whole item actually gets covered instead of one collapse plus a static tail. Off restores the exact pre-v1.13 one-shot behavior for anyone who specifically wants a single accelerando intro. Capped at 2000 total chunks as a safety limit. The Cut Lengths preview chart mirrors this exactly, so you can see the repeating pattern before running.

## v1.12

pairs with a real engine change - now launches Antisample_Shredder_V8.lua (was V7). Adds "Override Minimum Chunk Length": a checkbox + ms slider (right after the Cut Mode controls, applies globally) that replaces the previously-hardcoded 10ms floor used everywhere a chunk could otherwise get vanishingly small. Most useful for Pithalgora, Cantor Dust, Black/White Hole, and Collatz - all four recursively/iteratively shrink toward this floor, so raising it directly controls how small their smallest chunk is allowed to get, without changing anything else about how they work. Off by default (unchanged 10ms behavior). The Cut Lengths preview chart respects it too, so you can see the effect before running.

## v1.11

UI-only - no engine changes, still launches Antisample_Shredder_V7.lua. The Cut Lengths chart now previews against your FIRST SELECTED item's actual length (via CountSelectedMediaItems/GetSelectedMediaItem/D_LENGTH) instead of always using a fixed 8-second stand-in - much easier to judge what a Cut Mode will actually do to a short/long item than imagining it scaled from an arbitrary hypothetical one. Falls back to the old fixed-8s behavior when nothing is selected, with the caption saying which case you're in; auto-refreshes if you change the selection or resize the actual item while the window's open (both are legitimate reasons to reroll, not bugs). Multiple items selected: only the first one's length is used, noted in the caption ("- the first of N selected").

## v1.10

pairs with a real engine change - now launches Antisample_Shredder_V7.lua (was V6). Adds two more Bizarre Cut Modes:
- "Collatz": runs the Collatz ("3n+1") sequence from a Seed and uses the values visited as segment-length weights (same normalize-and-lay-out approach as Sequence mode). Unlike Black/White Hole's steady trend, this can genuinely swell before collapsing - chaotic rather than monotonic. Has its own Seed slider and Shrinking/Growing shape toggle.
- "Cantor Dust": the classical Cantor-set construction on the timeline - recursively divides each chunk into thirds, keeps the outer two, and permanently mutes the middle third, Depth times. This is the first Bizarre mode where the cut itself dictates fixed silence rather than just varying chunk size - the Cut Lengths preview chart shows these holes as amber bars (same color "muted" uses everywhere else) so they're visually obvious, and this also surfaced and fixed a real bug: the chart's refresh check had never included Black/White Hole's or Pithalgora's settings, so tweaking those silently wouldn't update the preview until something else changed it - now fixed for all six exact/deterministic Bizarre and Sequence modes.

## v1.9

pairs with a real engine change - now launches Antisample_Shredder_V6.lua (was V5).
- Adds the "Pithalgora" Cut Mode: a recursive fractal split using a real Pythagorean triple's leg ratio (a-b-c, selectable from six real triples) - treats each chunk as the hypotenuse, splits it into two children sized proportionally to legs a and b, then recurses into BOTH children the same way. Branches rather than chains, so sibling chunks can end up wildly different sizes - genuinely different character from Black/White Hole's straight linear chain. See the APPENDIX (V6) note in Antisample_Shredder_V6.lua for the exact algorithm.
- Renamed "Onset-Detection" to "Transient" (label only - the internal Cut Mode value is unchanged, so no settings migration was needed).
- Reorganized Cut Mode selection from one flat row of radio buttons into three grouped dropdowns side by side - Classic (Cut Length / Number of Cuts / Beat-Synced / Euclidean / Transient), Sequence (Sequence), and Bizarre (Black/White Hole / Pithalgora) - each dropdown shows a "-" placeholder whenever the active mode belongs to a different column, so only one column ever shows a real selection, same mutual exclusivity as before, just categorized.

## v1.8

pairs with a real engine change - now launches Antisample_Shredder_V5.lua (was V4). Adds the "Black/White Hole" Cut Mode: starts at a Starting Size and shrinks each next chunk to Decay% of the one before it (a fixed-ratio geometric shrink - lands cuts at logarithmically-closer intervals, the classic drum-and-bass accelerando-roll effect). White Hole flips it to grow instead of shrink. See the APPENDIX (V5) note in Antisample_Shredder_V5.lua for the exact algorithm.

## v1.7

UI-only - no engine changes, still launches Antisample_Shredder_V4.lua. Merged the v1.6 "Multi-item mash" section back into "Chunk fate" as a single item/multi item switcher (two radio buttons) next to the "Chunk fate" title, rather than two always-visible stacked sections - since it's all just preview and never touches real items, there's no cost to hiding whichever one isn't currently useful. Each view keeps its own Reroll button and independently-resizable height, so switching back and forth doesn't lose either one's size or last roll.

## v1.6

UI-only - no engine changes, still launches Antisample_Shredder_V4.lua. Adds a third Preview window section, "Multi-item mash": 2 demo items x 4 chunks each, showing what your current "With multiple items selected" mode (Mash Together vs Process Individually) would actually do - Mash Together pools and reorders across every item (colors mix in the Final row); Process Individually reorders each item's chunks only within their own slots (colors never cross). Same resizable-height/reroll/Shuffle Mode behavior as the other two Preview sections.

## v1.5

UI-only - no engine changes, still launches Antisample_Shredder_V4.lua.
- Moved "Ignore Silence" to below Ordered-Subset Mode (was above the Structural Modes section; now sits right after it instead).
- Added "Init" and a real "Jitter Enabled"/"Jitter Disabled" toggle at the top of Per-Segment Randomization. Init zeroes every slider in that section (Rate resets to 1x, its own neutral/no-op value, since 0 isn't a valid playback rate). The Jitter button's label always reflects current state and only touches the four bipolar +/- properties - Position, Pitch, Pan, Volume - leaving Rate, Reverse, Number Of Repeats, and Chunk Mute untouched; turning it off remembers the current values, turning it back on restores them (or falls back to a small preset the first time there's nothing saved yet).
- "Run Shredder" button no longer shows the engine version number.

Earlier history (back when this incremented per file):

## V9

Chunk Fate's 7 per-segment marker bars now span the FULL width of their chunk's own box, edge to edge, instead of a small fixed-width cluster centered under it - wider boxes (fewer final segments, or a taller/resized diagram) get proportionally wider, more legible bars automatically.

## V8

UI-only release - no engine changes, still launches Antisample_Shredder_V4.lua. Both preview drawing areas (Cut Lengths and Chunk Fate) are now genuinely resizable: a small drag handle below each one lets you pull it taller or shorter (the window itself was always resizable, but these DrawList-drawn regions had no native resize affordance of their own - see shredder_resize_handle()). Chunk Fate's boxes and text scale up together with its height rather than just gaining empty padding. Sizes persist across sessions.

## V7

UI-only release - no engine changes, still launches Antisample_Shredder_V4.lua. Refines the Preview window from V6:
- Cut Lengths bar labels now read e.g. "615 ms" instead of a bare number, so the unit is obvious at a glance.
- Removed the "Preview item length" slider - it added a confusing extra control for little benefit. The chart now always previews against a fixed 8-second stand-in item.
- Chunk Fate diagram is bigger, with more breathing room under the "Original"/"Final order" labels before their box rows.
- Chunk Fate now visualizes ALL per-segment randomization, not just Reverse/Mute: Position, Rate, Pitch, Pan, and Volume each get their own small colored bar under every Final order box, with height showing how much of that property's range this chunk happened to get (flat = that slider is off, so nothing is happening there).
- Sidechain-Aware Shredding's UI is hidden for now (not useful in its current form) - the code is intact behind a single flag, and the engine still supports it unchanged.

## V6

replaced the old inline "Show Chunk Preview" section with a single "Open Preview Window" button that pops a separate, movable/resizable ReaImGui window - keeps the main tab compact.

## V5

pairs with engine V4 - launches Antisample_Shredder_V4.lua. Generalizes the Fibonacci Cut Mode into "Sequence" with a Sequence Type dropdown (Fibonacci / Lucas / Padovan / Tribonacci / Custom); Custom lets you type your own comma-separated weights. A small preview line shows the actual numbers your current settings resolve to. See the APPENDIX (V4) note in Antisample_Shredder_V4.lua for details on each sequence type.
