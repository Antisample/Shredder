-- @noindex
-- (this file is a dependency bundled via Antisample_Shredder_UI.
-- lua's @provides tag, launched by that script - not meant to be
-- indexed as its own separate ReaPack package or run standalone)

--[[
  Antisample: Shredder
  -------------------------
  Random-cut-and-reshuffle glitch tool. Chops selected item(s) into
  random-length segments (sized around a target cut length), shuffles
  their order, and glues the result back into a single rendered item -
  a stutter/mangle effect.

    - ONE item selected: cut into random segments, reshuffle, glue in
      place. The item's own overall position/length is preserved -
      only the internal arrangement changes.
    - MULTIPLE items selected: either every item gets cut and ALL
      segments from ALL items are pooled together, shuffled as one big
      mashup, moved onto a single track, and glued into one combined
      item (MASH_MULTIPLE_ITEMS_TOGETHER = true), or each selected
      item is processed independently and stays separate (= false).

  Settings (cut length, mash-vs-individual, ignore silence) are read
  from ExtState so the Randomizer UI's Shredder tab can control them
  without editing this file - same pattern as the rest of Antisample.

  Uses REAPER's native "Item: Glue items" action (command ID 40362) to
  render the shuffled segments back into one item - confirmed via
  multiple independent published scripts before relying on it here.

  INSTALL:
    Actions List > New Action > Load ReaScript... > select this file.
    Right-click the action to add it to a toolbar button if you like.

  -----------------------------------------------------------------
  APPENDIX (V2) - three new modes added on top of the original engine
  -----------------------------------------------------------------
  All three reuse the existing cut/split/randomize/glue pipeline -
  none of them are separate scripts, they're just new switches read
  from ExtState (same pattern as everything else here), settable from
  the Randomizer UI's Shredder tab.

  1) BEAT-SYNCED CUT MODE (a third CUT_MODE, alongside "length" and
     "count"): CUT_MODE = "beat". Cuts land on the project tempo grid
     at a chosen note division (1/4 down to 1/32, plus triplet/dotted
     variants) instead of free-running seconds - segments are exactly
     one division long. Uses REAPER's TimeMap2_timeToQN/QNToTime
     conversions, so it stays correctly grid-locked even across tempo
     changes within the item. An optional "Humanize" percentage adds a
     small +/- jitter around each cut (as a fraction of the division's
     own length) without breaking the beat-synced feel.
       - BEAT_DIVISION_BEATS: division length in quarter-note beats
         (e.g. 0.25 = a 1/16 note). ExtState "ShredderBeatDivision".
       - BEAT_VARIANCE_PERCENT (0-50%): humanize jitter amount.
         ExtState "ShredderBeatVariance".

  2) NO-SHUFFLE MODE: segments are kept in their original left-to-
     right order instead of being reshuffled. Every other step
     (position jitter, rate/pitch/pan/volume randomization, reverse,
     repeats, mute) still applies per-segment independently, so the
     result is a randomized-but-still-sequential mangle - a subtler
     effect than the full scramble, good for texture rather than
     rhythm destruction.
       - NO_SHUFFLE: ExtState "ShredderNoShuffle" ("1"/"0").

  3) ORDERED-SUBSET MODE: each segment (after silence filtering) is
     independently KEPT with some % chance and DROPPED (deleted)
     otherwise. Surviving segments always play back in their ORIGINAL
     order - this mode never shuffles, regardless of the No-Shuffle
     setting above, since "ordered subset" specifically means a subset
     that preserves the source's own sequence. Because dropped
     segments are removed rather than muted, the glued result ends up
     SHORTER than the source - a rhythmic gating/gapped feel, distinct
     from Chunk Mute (which keeps the gap's timing slot and fills it
     with silence instead of shortening the item).
       - ORDERED_SUBSET_MODE: ExtState "ShredderSubsetMode" ("1"/"0").
       - SUBSET_KEEP_PERCENT (10-100%): chance to keep each segment.
         ExtState "ShredderSubsetKeepPercent".

  These three are orthogonal to each other and to everything that
  already existed (cut-by-length/count, mash mode, per-segment
  randomization, reverse/repeat/mute) - mix and match freely. The one
  interaction worth knowing: turning on Ordered-Subset Mode makes the
  No-Shuffle checkbox redundant (Ordered-Subset always preserves
  order on its own).

  -----------------------------------------------------------------
  APPENDIX (V3) - eight more modes, same reused pipeline
  -----------------------------------------------------------------
  Same deal as V2: no new scripts, just more ExtState-driven switches
  on top of the same cut/split/filter/order/randomize/glue pipeline.

  CUT_MODE gains three more options (alongside "length"/"count"/"beat"):

  4) EUCLIDEAN/RHYTHMIC MODE: CUT_MODE = "euclid". Divides the item
     into EUCLID_STEPS equal steps and distributes EUCLID_HITS cuts
     among them using an evenly-spread "bucket" algorithm (the same
     class of even-distribution used by classic Euclidean-rhythm tools
     like Bjorklund's algorithm, though the phase/rotation isn't
     guaranteed identical) - gives cuts a rhythmic, almost-clave-like
     placement instead of pure randomness.
       - EUCLID_STEPS (4-32): total steps across the item.
         ExtState "ShredderEuclidSteps".
       - EUCLID_HITS (1-EUCLID_STEPS): how many of those steps get a
         cut. ExtState "ShredderEuclidHits".

  5) FIBONACCI/GOLDEN-RATIO SPACING: CUT_MODE = "fibonacci". Segment
     lengths are proportional to the first FIB_NUM_SEGMENTS Fibonacci
     numbers (1,1,2,3,5,8,13...) rather than equal or random - produces
     an organic, spiral-like sense of growing (or, with
     FIB_DESCENDING, shrinking) segment sizes across the item.
       - FIB_NUM_SEGMENTS (3-13). ExtState "ShredderFibSegments".
       - FIB_DESCENDING: shrinking (true) vs growing (false) segments.
         ExtState "ShredderFibDescending".

  6) ONSET-DETECTION CUTTING: CUT_MODE = "onset". A multi-band
     transient detector - reads the item's audio via a take audio
     accessor at 22.05kHz, tracks level in low/high/full bands, and
     cuts where the combined dB rise clearly beats the local average
     (adaptive, level-independent). Each cut is placed sample-
     accurately just before its attack and snapped to a zero crossing;
     hits closer than 25ms (or MIN_SEGMENT_LEN, if larger) merge into
     the stronger one. Still best on percussive material - smooth
     legato sources have few real transients to find.
       - ONSET_SENSITIVITY_PERCENT (5-100): lower = more (and more
         sensitive) cuts. ExtState "ShredderOnsetSensitivity".

  Segment ORDERING gains a unified Shuffle Mode (replacing V2's simple
  No-Shuffle checkbox, which is still honored as a one-time migration
  default if no Shuffle Mode has been saved yet):

  7) LOCAL-SHUFFLE / WINDOWED SHUFFLE: SHUFFLE_MODE = "local". Segments
     are chunked into consecutive groups of LOCAL_SHUFFLE_WINDOW and
     each group is shuffled independently, then the groups are
     concatenated back in their original order - keeps the item's
     broad structure recognizable while still jumbling detail locally.
       - LOCAL_SHUFFLE_WINDOW (2-16 segments per group).
         ExtState "ShredderLocalShuffleWindow".

     WEIGHTED/MARKOV SHUFFLE: SHUFFLE_MODE = "weighted". A single
     WEIGHTED_SHUFFLE_AMOUNT (0-100%) dial that continuously blends
     between original order (0%) and a full random shuffle (100%).
     Implemented as a jittered-index sort (each segment's original
     index gets a random offset scaled by the amount, then the list is
     re-sorted by that key) rather than a literal Markov chain - it
     gives the same practical "how much disorder" dial the name
     implies, just via a simpler, deterministic-at-the-extremes method.
       - WEIGHTED_SHUFFLE_AMOUNT (0-100%).
         ExtState "ShredderWeightedShuffleAmount".
     (SHUFFLE_MODE = "full" and "none" are the original shuffle/
     No-Shuffle behaviors from before, now just two more values of the
     same setting. ExtState "ShredderShuffleMode".)

  8) PALINDROME MODE: after the final segment order (including
     repeats) is built, appends a mirrored copy of it in reverse
     (skipping the exact middle segment so it doesn't repeat back-to-
     back) - the glued result plays forward then backward, like a
     boomerang/reverse-loop edit. Reversed-half segments are
     independent duplicates (via the same duplicate_segment() used for
     Number Of Repeats), so they still get their own independent
     per-segment randomization, reverse chance, and mute chance -
     PALINDROME_MODE: ExtState "ShredderPalindrome" ("1"/"0").

  SCALE-QUANTIZED PITCH: an addition to the existing Pitch
  randomization (not a new mode of its own) - when SCALE_QUANTIZE is
  on, each segment's randomized pitch offset is snapped to the nearest
  semitone belonging to a chosen scale (rooted at SCALE_ROOT), instead
  of landing anywhere in the randomized range - turns pitch
  randomization into an in-key glitch-melody generator.
       - SCALE_QUANTIZE: ExtState "ShredderScaleQuantize" ("1"/"0").
       - SCALE_ROOT (0-11, C=0): ExtState "ShredderScaleRoot".
       - SCALE_TYPE ("major"/"minor"/"majpent"/"minpent"/"chromatic"):
         ExtState "ShredderScaleType".

  SIDECHAIN-AWARE SHREDDING: an additional filter step (alongside
  Ignore Silence and Ordered-Subset) that reads another track's audio
  via a track audio accessor and keeps/mutes/drops each segment based
  on whether that track has energy above SIDECHAIN_THRESHOLD at the
  segment's ORIGINAL (pre-reshuffle) position - ties the glitch's
  hits/gaps to a different track's rhythm (e.g. shred a pad in time
  with a kick pattern on another track). SIDECHAIN_INVERT flips which
  side counts as a "hit" (gate vs. duck); SIDECHAIN_DROP removes
  non-hit segments entirely (shortening the result, like Ordered-
  Subset) instead of just muting them in place.
       - SIDECHAIN_ENABLED: ExtState "ShredderSidechainEnabled".
       - SIDECHAIN_TRACK_NAME (must match an existing track's name
         exactly): ExtState "ShredderSidechainTrack".
       - SIDECHAIN_THRESHOLD_PERCENT (0-100, of full-scale peak
         amplitude): ExtState "ShredderSidechainThreshold".
       - SIDECHAIN_INVERT: ExtState "ShredderSidechainInvert".
       - SIDECHAIN_DROP: ExtState "ShredderSidechainDrop".

  All eight are orthogonal to each other and to everything from V1/V2
  - mix freely. Ordered-Subset Mode still always preserves order,
  taking priority over whatever Shuffle Mode is selected (Palindrome
  still applies on top, since it runs after ordering either way).

  -----------------------------------------------------------------
  APPENDIX (V4) - Fibonacci generalized into Sequence-Based Cutting
  -----------------------------------------------------------------
  CUT_MODE = "fibonacci" is gone, replaced by CUT_MODE = "sequence"
  (a saved "fibonacci" value from V3 auto-migrates to this, defaulting
  SEQUENCE_TYPE to "fibonacci" so nobody's settings silently change).
  The underlying cutting logic never actually depended on Fibonacci
  specifically - it just needs an ordered list of positive numbers to
  use as relative segment-length weights - so it now supports several
  sequences plus a fully custom one, via SEQUENCE_TYPE:

    - "fibonacci" (default): 1,1,2,3,5,8,13... - the original behavior.
    - "lucas": 2,1,3,4,7,11,18... - same recurrence as Fibonacci
      (sum of the previous two), different seed values.
    - "padovan": 1,1,1,2,2,3,4,5,7,9,12,16... - sum of the value 2 and
      3 positions back rather than 1 and 2 - grows more slowly than
      Fibonacci (converges to the plastic number, ~1.3247, instead of
      the golden ratio, ~1.618), so segment-size jumps feel gentler.
    - "tribonacci": 1,1,2,4,7,13,24,44... - sum of the previous THREE
      values - grows faster than Fibonacci.
    - "custom": SEQUENCE_CUSTOM is a comma-separated list of positive
      numbers typed by the user (e.g. "1,2,4,8,16" or "3,1,4,1,5,9") -
      parsed directly as the weights, ignoring FIB_NUM_SEGMENTS
      entirely (the count is just however many numbers were typed).
      Non-numeric or non-positive entries are dropped; an empty/all-
      invalid list falls back to a single flat weight.

  FIB_NUM_SEGMENTS and FIB_DESCENDING (both from V3) still apply to
  every built-in sequence type exactly as before - they only stop
  applying (segments-count-wise) for "custom", where the typed list's
  own length is the segment count, though FIB_DESCENDING still flips
  it. ExtState keys are unchanged for both (ShredderFibSegments,
  ShredderFibDescending); new ones are ShredderSequenceType and
  ShredderSequenceCustom.

  -----------------------------------------------------------------
  APPENDIX (V5) - Black Hole / White Hole cutting
  -----------------------------------------------------------------
  CUT_MODE = "blackhole". Starts from a single starting chunk size
  (BLACKHOLE_START, its own dedicated setting - NOT shared with "By
  Cut Length"'s TARGET_CUT_LENGTH, so tuning one doesn't surprise the
  other) and repeatedly multiplies it by BLACKHOLE_DECAY (e.g. 0.9 =
  each chunk is 90% the size of the one before it) to get the next
  chunk's size, laying chunks out back-to-back from the item's start.
  This continues until either the next chunk would be smaller than
  MIN_SEGMENT_LEN, or there isn't room left for one more chunk PLUS a
  final MIN_SEGMENT_LEN-sized leftover - at that point it stops, and
  whatever time remains becomes one final segment that absorbs the
  rest of the item (rather than leaving a stray sliver or a gap). This
  is a fixed-ratio geometric shrink, which is what makes the cut
  positions land at logarithmically-decreasing intervals - the
  "accelerando" feel of a classic drum-and-bass buildup, automated.

  BLACKHOLE_WHITE_HOLE flips it: the same geometric sequence of sizes
  is computed exactly the same way, then the whole list is reversed
  before laying out cut positions - so instead of starting big and
  shrinking toward the end (Black Hole), it starts tiny and grows
  toward the end (White Hole). Same knobs, same math, just read
  backwards.

    - BLACKHOLE_START (seconds internally, ms in the UI): starting
      chunk size. ExtState "ShredderBlackholeStart".
    - BLACKHOLE_DECAY_PERCENT (50-99, stored as a percent, used as a
      0-1 fraction): how much smaller each next chunk is, e.g. 90 =
      each chunk is 90% of the previous one's size. Lower = faster
      collapse (or, in White Hole, a faster initial ramp-up).
      ExtState "ShredderBlackholeDecay".
    - BLACKHOLE_WHITE_HOLE: ExtState "ShredderWhiteHole" ("1"/"0").

  -----------------------------------------------------------------
  APPENDIX (V6) - Pitagora cutting
  -----------------------------------------------------------------
  Named "Pitagora" (v1.15 - renamed from "Pithalgora", the original
  invented portmanteau; "Pitagora" is the actual Italian/Spanish name
  for Pythagoras, so it's more directly recognizable). A saved
  CUT_MODE of "pithalgora" and a saved ShredderPithalgoraTriple both
  still migrate automatically - nothing resets for existing users.

  CUT_MODE = "pitagora". A recursive fractal split, structurally the
  timeline equivalent of the classic "Pythagoras tree" construction:
  pick a real Pythagorean triple (a, b, c - e.g. 3-4-5), treat the
  current chunk's length as the hypotenuse, and split it into two
  children sized proportionally to legs a and b (fractions a/(a+b) and
  b/(a+b) of the chunk's own length - the triple's THIRD number, c,
  never appears in the math directly; it's what makes a/b a "real"
  Pythagorean ratio rather than an arbitrary one, and is why the whole
  chunk being split is described as "the hypotenuse"). Both children
  are then recursively split the same way, and so on, until a child
  would be smaller than MIN_SEGMENT_LEN (at which point that branch
  just stops, keeping its current size) or a safety cap on total cuts
  is hit. Unlike Blackhole's straight linear chain, this BRANCHES -
  siblings can end up wildly different sizes, since one branch might
  keep subdividing for several more levels while its neighbor already
  bottomed out - an irregular, self-similar, non-monotonic rhythm
  rather than a smooth accelerando.

    - PITAGORA_TRIPLE: which (a, b, c) triple to use, chosen from a
      fixed set of real primitive triples (3-4-5, 5-12-13, 8-15-17,
      7-24-25, 20-21-29, 9-40-41). ExtState "ShredderPitagoraTriple",
      stored as the triple's own "a-b-c" string.

  -----------------------------------------------------------------
  APPENDIX (V7) - Collatz Cuts and Cantor Dust
  -----------------------------------------------------------------
  Two more Bizarre modes.

  1) COLLATZ CUTS: CUT_MODE = "collatz". Runs the Collatz sequence
     (the "3n+1" conjecture) starting from COLLATZ_SEED: while n isn't
     1, if n is even, n becomes n/2; if odd, n becomes 3n+1. The
     resulting sequence of values (which can climb dramatically before
     eventually crashing down to 1 - nobody has ever proven every seed
     actually reaches 1, though every seed ever tested does) becomes
     the segment-length WEIGHTS, exactly the same normalize-and-lay-
     out approach as Sequence mode (each weight / sum-of-weights *
     item_len). Unlike Blackhole's monotonic shrink or Pitagora's
     clean branching, this can genuinely swell before collapsing -
     chaotic rather than trending. Capped at 300 terms as a safety
     limit (real orbits for reasonable seeds are far shorter; seed 27
     famously takes 111 steps and peaks at 9232 along the way).
       - COLLATZ_SEED (2+): ExtState "ShredderCollatzSeed".
       - COLLATZ_DESCENDING: reverses the sequence before laying out
         weights (same "Shrinking/Growing" idea as Sequence mode's
         FIB_DESCENDING, its own separate setting here). ExtState
         "ShredderCollatzDescending".

  2) CANTOR DUST: CUT_MODE = "cantor". Structurally unlike most other
     modes - it decides not just WHERE to cut but that certain
     resulting segments must be SILENT (Chunk Mute rolls randomly per
     segment later in the pipeline; this is deterministic, structural
     silence baked into the cut itself - "morse" mode, added in V11,
     works the same way). Implements the classical Cantor-set
     construction on the timeline: recursively divide a segment into
     thirds, keep the left and right thirds as further-recursable
     pieces, and the MIDDLE third becomes a fixed hole. Recurse into
     the two kept thirds the same way, CANTOR_DEPTH times. After depth
     d, there are 2^d solid leaf segments and 2^d - 1 holes interleaved
     between them, a fractal lattice of silence.

     Because "this segment must be silent" isn't information the
     shared position-only pipeline carries, generate_cut_positions_by_
     cantor() also sets the module-level STRUCTURAL_MUTE_INDICES (a set
     of which resulting segment indices, left-to-right, must be muted)
     as a side effect - process_single_item()/process_mashup() call
     apply_structural_mutes() right after splitting, which force-mutes
     exactly those segments before any other filtering/shuffling
     happens (a no-op whenever nothing set it, i.e. every mode besides
     Cantor Dust and Morse). This is the one place in the script where
     a Cut Mode reaches beyond generate_cut_positions() into the rest
     of the pipeline - every other mode is a pure "positions in, done"
     call.
       - CANTOR_DEPTH (1-7): ExtState "ShredderCantorDepth".

  -----------------------------------------------------------------
  APPENDIX (V8) - Minimum Chunk Length Override
  -----------------------------------------------------------------
  MIN_SEGMENT_LEN (the 10ms floor used throughout the script - every
  generate_cut_positions_by_*() function stops subdividing/shrinking/
  cutting once a piece would land below it) is now overridable instead
  of a hardcoded constant. Most consequential for the Bizarre modes
  that actively cascade toward this floor - Pitagora keeps branching
  until a child would be smaller than it, Cantor Dust keeps recursing
  into thirds until they would be, Black/White Hole and Collatz both
  keep shrinking/laying out weighted chunks until the next one would
  be - so raising it directly controls "how small is the smallest
  chunk allowed to get" for exactly the modes where that's otherwise
  hard to predict or control. It's the same floor everywhere else too
  (Length/Count/Beat/Euclid/Sequence/Onset), so raising it affects
  those as well, though it's rarely the binding constraint there since
  their own settings (Cut Length, Number of Cuts, etc.) usually
  dominate first.

    - MIN_SEG_OVERRIDE_ENABLED: ExtState "ShredderMinSegOverride"
      ("1"/"0"). When off, MIN_SEGMENT_LEN is the original 10ms
      default, unchanged from every version before this one.
    - MIN_SEG_OVERRIDE_MS: the floor in milliseconds when the override
      is on. ExtState "ShredderMinSegOverrideMs".

  -----------------------------------------------------------------
  APPENDIX (V9) - Black Hole looping
  -----------------------------------------------------------------
  Fixes a real design gap: a geometric series has a FINITE sum even
  carried out forever (BLACKHOLE_START / (1 - BLACKHOLE_DECAY)) - so
  with the defaults (300ms start, 90% decay), one collapse cycle only
  ever covers exactly 3 seconds, REGARDLESS of how long the item is.
  Past that point the cycle had already bottomed out below
  MIN_SEGMENT_LEN, so everything else became one large, completely
  unprocessed leftover segment - on anything longer than a few
  seconds, Black Hole was only ever touching its opening moment.

  BLACKHOLE_LOOP (default true) fixes this: once a cycle bottoms out,
  it restarts from BLACKHOLE_START and collapses again, repeating for
  as long as the item has room, so the whole item gets covered by a
  repeating collapse pattern instead of one collapse plus a static
  tail. Turning it off restores the pre-V9 one-shot behavior exactly,
  for anyone who specifically wants a single accelerando at the start
  followed by untouched audio (a legitimate creative choice, just no
  longer the default). Capped at 2000 total chunks as a safety limit
  regardless, since looping on a long item at small chunk sizes could
  otherwise produce an excessive number of cuts. BLACKHOLE_WHITE_HOLE
  still just reverses the entire computed list (all cycles at once)
  before laying out positions, exactly as before - with looping on,
  this mirrors the whole repeating pattern into a repeating GROW-then-
  reset-to-tiny shape instead of shrink-then-reset-to-big.

    - BLACKHOLE_LOOP: ExtState "ShredderBlackholeLoop" ("1"/"0").

  -----------------------------------------------------------------
  APPENDIX (V11) - Morse Code Cuts
  -----------------------------------------------------------------
  CUT_MODE = "morse". Encodes MORSE_TEXT into real International
  Morse Code and lays out one chunk per symbol using standard timing
  ratios: dot = 1 unit, dash = 3 units, gap between symbols within a
  letter = 1 unit, gap between letters = 3 units, gap between words =
  7 units - MORSE_UNIT_MS sets what "1 unit" is in milliseconds. Dots
  and dashes are audible; all three gap types are forced SILENT via
  the same STRUCTURAL_MUTE_INDICES mechanism Cantor Dust uses (see the
  APPENDIX (V7) note above) - so the muted regions of the glued result
  literally spell out the message rhythmically, independent of
  whatever Chunk Mute rolls happen later in the pipeline. Unsupported
  characters (anything outside A-Z, 0-9, space, and ".", ",", "?")
  are silently skipped during encoding.

  MORSE_LOOP (default true) restarts the message from its first
  symbol once fully laid out, repeating for as long as the item has
  room - the exact same "restart the cycle once exhausted" idea
  BLACKHOLE_LOOP uses (APPENDIX (V9) above), just triggered by running
  out of symbols instead of decaying below the minimum chunk length.
  With it off, a short message (e.g. "SOS") only ever covers its own
  brief duration before leaving the rest of the item as one large,
  untouched leftover segment - exactly the failure mode V9 fixed for
  Black/White Hole, so Morse ships with the fix already built in.
  Capped at 2000 total chunks as a safety limit regardless.

    - MORSE_TEXT: the message to encode. ExtState "ShredderMorseText".
    - MORSE_UNIT_MS: the base timing unit, in milliseconds. ExtState
      "ShredderMorseUnitMs".
    - MORSE_LOOP: ExtState "ShredderMorseLoop" ("1"/"0").

  -----------------------------------------------------------------
  APPENDIX (V12) - Direction
  -----------------------------------------------------------------
  Position, Pitch, Pan, and Volume are each "bipolar" - centered on a
  neutral value (no shift, no pitch change, centered pan, unity
  volume), randomized anywhere in [-magnitude, +magnitude] by default.
  A Direction setting per property constrains which half of that range
  is actually used: "both" (default, original behavior), "neg" (only
  downward/left/quieter/earlier), or "pos" (only upward/right/louder/
  later). See directional_random() below - every bipolar property's
  randomization routes through it. Rate, Reverse, Repeats, and Mute
  don't have a comparable notion of direction, so they're unaffected
  by this setting.
    - POSITION_DIRECTION/PITCH_DIRECTION/PAN_DIRECTION/VOLUME_DIRECTION:
      ExtState "ShredderPositionDirection"/"ShredderPitchDirection"/
      "ShredderPanDirection"/"ShredderVolumeDirection" ("both"/"neg"/
      "pos", default "both").

  (This appendix originally also covered a "Jitter %" master intensity
  that scaled all eight per-segment amounts, replacing an even older
  Jitter Enabled/Disabled toggle. Both were tried and both got
  reverted - Jitter % made every parameter depend on remembering to
  raise a separate master dial, which turned out to be more confusing
  in practice than each slider directly controlling its own amount at
  100%, no master gate, the way this section worked originally. Back
  to that: every per-segment property is controlled ONLY by its own
  slider now, same as before either Jitter mechanism existed.)

  -----------------------------------------------------------------
  APPENDIX (V13) - Cut Only
  -----------------------------------------------------------------
  CUT_ONLY, default true (on unless explicitly turned off in the
  Settings tab). Every mode, every Structural Mode, every per-segment
  property behaves exactly as it always has - the only thing this
  changes is the very last step, AND who's responsible for selection/
  range/cursor afterward. Normally finish_segments() calls
  glue_segments(): select the finished segments, run REAPER's native
  glue (producing one rendered item), rename it "Shredder_<n>". With
  Cut Only on, finish_segments() calls group_segments() instead: the
  segments stay as separate items and get assigned a freshly-picked
  I_GROUPID so they move together from here on (same effect as
  REAPER's own "Group items" action - implemented directly via the
  I_GROUPID item property rather than a native action, since that's a
  plain documented MediaItem field, the same category as D_POSITION/
  B_MUTE already used everywhere else in this script). No render, no
  rename either way in this half.

  Both finish_segments() paths ALWAYS return a list now (a single-
  element list holding the glued item, or the full segment list with
  Cut Only on) rather than a single item or nil - this matters because
  process_single_item()/process_mashup() can each be called MULTIPLE
  times in one run (once per originally-selected item, when Process
  Individually is active), and it's main() - not any per-item call -
  that does the final select-everything-and-set-the-combined-range
  step, once, over the FULL flattened list of every result from every
  call. An earlier version of this had finish_segments() do its own
  per-item select/range immediately, which main()'s existing (and
  correct) combined-range logic would then immediately overwrite using
  only the single item each call had returned - with Cut Only on, that
  single item was one arbitrary segment, not all of them, so the final
  selection only ever covered a sliver of the actual result. Routing
  everything through one flattened list fixes that at the root instead
  of duplicating (and fighting) the same logic in two places.
    - CUT_ONLY: ExtState "ShredderCutOnly" ("1"/"0", default true - the
      ~= "0" read means an unset/empty ExtState value is also true).

  -----------------------------------------------------------------
  APPENDIX (V14) - Render Naming
  -----------------------------------------------------------------
  The glued result's take name (glue_segments(), only reached when
  Cut Only is off) is built from RENDER_NAME_PATTERN instead of a
  fixed "Shredder_<n>" - a user-editable pattern (Settings tab, UI
  file) with {wildcard} placeholders, expanded by
  expand_render_name_pattern() right before the name gets applied.
    - {name}: the ORIGINAL (pre-shred) item's take name.
      process_single_item()/process_mashup() both capture this BEFORE
      any cutting happens (the original item reference doesn't
      reliably survive past split_item_into_segments()) - for a
      mashup of multiple items, the FIRST selected item's name is
      used, a reasonable default rather than trying to concatenate
      every item's name together. Falls back to "item" if the source
      has no take or an empty name.
    - {number}: next_Shredder_number() - the same persistent ExtState
      counter ("ShredderCounter") the old fixed naming always used, so
      switching to a custom pattern doesn't reset or collide with
      numbering from before this existed.
    - {mode}: the current Cut Mode (e.g. "blackhole", "euclid").
    - {date}/{time}: os.date() - YYYY-MM-DD / HH-MM-SS (hyphens in the
      time, not colons - colons aren't valid in filenames on Windows).
    - RENDER_NAME_PATTERN: ExtState "ShredderRenderNamePattern",
      default "Shredder_{number}" (matches the original fixed naming
      exactly, so nothing changes unless the pattern is edited).

  -----------------------------------------------------------------
  APPENDIX (V15) - Scatter Repeats
  -----------------------------------------------------------------
  SCATTER_REPEATS, default false (off - original behavior unchanged
  unless explicitly turned on). expand_with_repeats() has always
  rolled an independent repeat count per segment and duplicated it
  that many times - what changes is WHERE those duplicates land.
  Off: duplicates are inserted immediately after the segment they're
  a copy of, same as always (a segment repeated 3 times plays as a
  clustered "A A A A" stutter right there before moving on).
  On: `order`'s own sequence - one instance of each segment, in
  whatever order Shuffle Mode/Palindrome/etc already left them -
  stays intact as the "spine". Every duplicate instead gets inserted
  at an independently-random position anywhere in the growing result,
  recomputed fresh after each insertion (so later duplicates aren't
  biased toward the end just because the list has grown by then).
  This only changes where the EXTRA copies land, not the base
  ordering Shuffle Mode/Palindrome already determined - so Scatter
  Repeats and Shuffle Mode = None can be used together: original
  segment order preserved, only the repeat copies scattered in.
    - SCATTER_REPEATS: ExtState "ShredderScatterRepeats" ("1"/"0",
      default "0"/false).

  -----------------------------------------------------------------
  APPENDIX (V16) - Cut Length Fixed
  -----------------------------------------------------------------
  "By Cut Length" has randomized each segment +/-50% around
  TARGET_CUT_LENGTH since it was first built - the whole point of the
  mode being an organic, non-mechanical feel rather than a metronomic
  one. That's still the default (CUT_LENGTH_FIXED = false), but it
  means a 500ms Cut Length setting was never actually producing 500ms
  segments - every segment landed somewhere in 250-750ms, uniformly
  random, with 500ms being nothing more than the center of that
  range. CUT_LENGTH_FIXED = true skips the randomization entirely:
  every segment is exactly TARGET_CUT_LENGTH (still floored by
  MIN_SEGMENT_LEN for very short settings). The FINAL segment can
  still differ from the rest either way - whatever's left between the
  last cut and the item's actual end, the same "leftover absorbs the
  remainder" behavior every other Cut Mode in this script already has
  (Blackhole, Euclidean, Sequence, etc. all work the same way) - not
  a gap specific to this setting, and not fixable without changing
  the item's total length, which no Cut Mode does.

  Despite the name, CUT_LENGTH_FIXED also now covers "By Number of
  Cuts" - the SAME setting, not a second one, per how this was asked
  for. "count" mode has always rolled its own target count +/-20% for
  organic variation (Number Of Cuts = 2 could genuinely produce 1-3
  cuts = 2-4 segments) - CUT_LENGTH_FIXED = true skips THAT
  randomization too: exactly TARGET_NUM_CUTS cuts, every time. Either
  way, "count" mode's individual cut POSITIONS are still randomly
  scattered across the item - Fixed only makes the COUNT exact, the
  same relationship "length" mode's Fixed has to ITS positions (exact
  SIZE, still organically placed). The ExtState key/setting name
  weren't changed to something more generic (e.g. "ShredderCutFixed")
  since the functional behavior - and the existing Settings-tab
  toggle - matter more than the internal name matching perfectly; a
  rename would've meant a migration path for no real benefit.
    - CUT_LENGTH_FIXED: ExtState "ShredderCutLengthFixed" ("1"/"0",
      default "0"/false - unchanged behavior unless turned on).
]]--

-------------------------------------------------------------------
-- USER CONFIG
-------------------------------------------------------------------

local EXT_SECTION = "AntisampleFXUI"

-- Two mutually-exclusive ways to decide where cuts happen - pick one,
-- not combined:
--   "length" - target segment length in seconds; actual segment
--              lengths vary randomly around this (+/- 50%). Settable
--              via the Shredder tab's Cut Length slider (10-60ms).
--   "count"  - a target NUMBER of cuts (segments = cuts + 1),
--              distributed randomly across the item. Settable via the
--              Shredder tab's Number of Cuts slider.
-- V2 added "beat"; V3 added "euclid", "fibonacci", "onset"; V4
-- generalizes "fibonacci" into "sequence" (a saved "fibonacci" value
-- migrates automatically below) - see generate_cut_positions_by_*()
-- below and the APPENDIX notes up top.
local CUT_MODE = reaper.GetExtState(EXT_SECTION, "ShredderCutMode")
if CUT_MODE == "fibonacci" then CUT_MODE = "sequence" end
if CUT_MODE == "pithalgora" then CUT_MODE = "pitagora" end -- v1.15 rename
local VALID_CUT_MODES = {
  count = true, beat = true, euclid = true, sequence = true, onset = true,
  blackhole = true, pitagora = true, collatz = true, cantor = true, morse = true,
}
if not VALID_CUT_MODES[CUT_MODE] then CUT_MODE = "length" end

local TARGET_CUT_LENGTH = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderCutLength")) or 0.03
local TARGET_NUM_CUTS = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderNumCuts")) or 8

-- Cut Length Fixed (V16): "By Cut Length" has always randomized each
-- segment +/-50% around TARGET_CUT_LENGTH by design (see the header
-- comment on generate_cut_positions_by_length() below) - this is the
-- opt-in for genuinely EQUAL-length segments instead, every one of
-- them exactly TARGET_CUT_LENGTH (floored by MIN_SEGMENT_LEN), no
-- randomization at all. Off by default - unchanged behavior.
local CUT_LENGTH_FIXED = reaper.GetExtState(EXT_SECTION, "ShredderCutLengthFixed") == "1"

-- "beat" mode settings (V2): BEAT_DIVISION_BEATS is the division's
-- length expressed in quarter-note beats (e.g. 0.25 = a 1/16 note,
-- 1/3 = a 1/8 triplet) - set via the Shredder tab's Beat Division
-- dropdown. BEAT_VARIANCE_PERCENT (0-50%) adds humanize jitter around
-- each cut - see generate_cut_positions_by_beat() below.
local BEAT_DIVISION_BEATS = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderBeatDivision")) or 0.25
local BEAT_VARIANCE_PERCENT = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderBeatVariance")) or 10

-- "euclid" mode settings (V3): distributes EUCLID_HITS cuts evenly
-- among EUCLID_STEPS equal-length steps across the item - see
-- generate_cut_positions_by_euclid() below.
local EUCLID_STEPS = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderEuclidSteps")) or 16
local EUCLID_HITS = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderEuclidHits")) or 5

-- "sequence" mode settings (V3 as "fibonacci", generalized in V4):
-- segment lengths proportional to a chosen number sequence, growing
-- or shrinking across the item - see generate_cut_positions_by_
-- sequence() below and the APPENDIX (V4) note up top. ExtState key
-- names keep their original V3 "Fib" spelling for backward
-- compatibility even though they now apply to every sequence type.
local SEQUENCE_TYPE = reaper.GetExtState(EXT_SECTION, "ShredderSequenceType")
local VALID_SEQUENCE_TYPES = { fibonacci = true, lucas = true, padovan = true, tribonacci = true, custom = true }
if not VALID_SEQUENCE_TYPES[SEQUENCE_TYPE] then SEQUENCE_TYPE = "fibonacci" end
local SEQUENCE_CUSTOM = reaper.GetExtState(EXT_SECTION, "ShredderSequenceCustom")
if SEQUENCE_CUSTOM == "" then SEQUENCE_CUSTOM = "1,1,2,3,5,8" end
local FIB_NUM_SEGMENTS = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderFibSegments")) or 8
local FIB_DESCENDING = reaper.GetExtState(EXT_SECTION, "ShredderFibDescending") ~= "0" -- default true

-- "blackhole" mode settings (V5): geometric shrink (or, with
-- BLACKHOLE_WHITE_HOLE, growth) of chunk sizes - see the APPENDIX (V5)
-- note up top and generate_cut_positions_by_blackhole() below.
local BLACKHOLE_START = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderBlackholeStart")) or 0.3
local BLACKHOLE_DECAY = (tonumber(reaper.GetExtState(EXT_SECTION, "ShredderBlackholeDecay")) or 90) / 100
local BLACKHOLE_WHITE_HOLE = reaper.GetExtState(EXT_SECTION, "ShredderWhiteHole") == "1"
-- Default true: without looping, one collapse cycle only ever covers
-- BLACKHOLE_START/(1-BLACKHOLE_DECAY) seconds REGARDLESS of item
-- length (a geometric series' finite sum), leaving everything else as
-- one static leftover segment - looping is what makes the effect
-- actually cover the whole item. See generate_cut_positions_by_
-- blackhole() below for the full explanation.
local BLACKHOLE_LOOP = reaper.GetExtState(EXT_SECTION, "ShredderBlackholeLoop") ~= "0"

-- "pitagora" mode settings (V6): which real Pythagorean triple's
-- leg ratio drives the recursive split - see the APPENDIX (V6) note
-- up top and generate_cut_positions_by_pitagora() below.
local PITAGORA_TRIPLES = {
  ["3-4-5"] = { 3, 4 },
  ["5-12-13"] = { 5, 12 },
  ["8-15-17"] = { 8, 15 },
  ["7-24-25"] = { 7, 24 },
  ["20-21-29"] = { 20, 21 },
  ["9-40-41"] = { 9, 40 },
}
local PITAGORA_TRIPLE = reaper.GetExtState(EXT_SECTION, "ShredderPitagoraTriple")
if PITAGORA_TRIPLE == "" then
  PITAGORA_TRIPLE = reaper.GetExtState(EXT_SECTION, "ShredderPithalgoraTriple") -- v1.15 rename fallback
end
if not PITAGORA_TRIPLES[PITAGORA_TRIPLE] then PITAGORA_TRIPLE = "3-4-5" end

-- "collatz" mode settings (V7): see the APPENDIX (V7) note up top and
-- generate_cut_positions_by_collatz() below.
local COLLATZ_SEED = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderCollatzSeed")) or 27
local COLLATZ_DESCENDING = reaper.GetExtState(EXT_SECTION, "ShredderCollatzDescending") == "1"

-- "cantor" mode settings (V7): see the APPENDIX (V7) note up top and
-- generate_cut_positions_by_cantor() below.
local CANTOR_DEPTH = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderCantorDepth")) or 3
-- Side-channel set by generate_cut_positions_by_cantor() or _by_morse(),
-- consumed by process_single_item()/process_mashup() right after
-- splitting - see the APPENDIX (V7)/(V11) notes for why these two
-- modes need this and no other mode does.
local STRUCTURAL_MUTE_INDICES = nil

-- "morse" mode settings (V11): see the APPENDIX (V11) note up top and
-- generate_cut_positions_by_morse() below.
local MORSE_TEXT = reaper.GetExtState(EXT_SECTION, "ShredderMorseText")
if MORSE_TEXT == "" then MORSE_TEXT = "SOS" end
local MORSE_UNIT_MS = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderMorseUnitMs")) or 60
local MORSE_LOOP = reaper.GetExtState(EXT_SECTION, "ShredderMorseLoop") ~= "0"

-- International Morse Code: letters, digits, and a few common
-- punctuation marks. Unsupported characters (anything not in this
-- table and not a space) are silently skipped during encoding.
local MORSE_TABLE = {
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

-- "onset" mode settings: ONSET_SENSITIVITY_PERCENT (5-100) sets how
-- big a level jump (in dB, above the local average) counts as a
-- transient - lower = more cuts. See generate_cut_positions_by_onset().
local ONSET_SENSITIVITY_PERCENT = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderOnsetSensitivity")) or 30
local ONSET_ANALYSIS_RATE = 22050 -- Hz, high enough to see hi-hat/click energy
local ONSET_HOP = 128 -- samples per analysis frame (~5.8ms at 22.05kHz)
local ONSET_LOW_HZ = 150 -- low band (kicks/bass) = below this
local ONSET_HIGH_HZ = 4000 -- high band (hats/clicks/consonants) = above this
local ONSET_GATE_DB = 50 -- frames this far below the item's loudest frame are ignored
local ONSET_AVG_SEC = 0.15 -- adaptive-threshold averaging half-window
local ONSET_MIN_GAP_SEC = 0.025 -- two transients closer than this merge into the stronger one
local ONSET_PREROLL_SEC = 0.001 -- cut lands this far before the detected attack

-- Minimum Chunk Length (v1.12): the floor used everywhere a segment
-- could otherwise get vanishingly small - most consequential for the
-- Bizarre modes that recursively/iteratively shrink toward it
-- (Pitagora, Cantor Dust, Black/White Hole, Collatz all stop
-- subdividing/shrinking once a child would land below this), but it's
-- the same floor used as a basic safety clamp everywhere else too
-- (Length/Count/Beat/Euclid/Sequence/Onset). Overridable so those
-- Bizarre modes can be told to stay chunkier instead of cascading all
-- the way down to a 10ms default.
local MIN_SEG_OVERRIDE_ENABLED = reaper.GetExtState(EXT_SECTION, "ShredderMinSegOverride") == "1"
local MIN_SEG_OVERRIDE_MS = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderMinSegOverrideMs")) or 10
local MIN_SEGMENT_LEN = MIN_SEG_OVERRIDE_ENABLED
  and (math.max(1, MIN_SEG_OVERRIDE_MS) / 1000)
  or 0.01 -- seconds - the original default, unchanged when the override is off

-- true = pool every selected item's segments into one mashup;
-- false = process each selected item independently, staying separate.
local MASH_MULTIPLE_ITEMS_TOGETHER = reaper.GetExtState(EXT_SECTION, "ShredderMashMode") ~= "0"

-- Shuffle Mode (V3): replaces V2's simple No-Shuffle checkbox with
-- four options - "full" (original random reshuffle), "none" (V2's
-- No-Shuffle), "local" (windowed shuffle), "weighted" (Markov-esque
-- amount dial). If no Shuffle Mode has ever been saved, falls back to
-- whatever V2's No-Shuffle checkbox was set to, so upgrading users
-- don't lose their setting.
local SHUFFLE_MODE = reaper.GetExtState(EXT_SECTION, "ShredderShuffleMode")
if SHUFFLE_MODE == "" then
  SHUFFLE_MODE = (reaper.GetExtState(EXT_SECTION, "ShredderNoShuffle") == "1") and "none" or "full"
end
if SHUFFLE_MODE ~= "none" and SHUFFLE_MODE ~= "local" and SHUFFLE_MODE ~= "weighted" then
  SHUFFLE_MODE = "full"
end

-- "local" Shuffle Mode setting (V3): group size for windowed shuffle -
-- see local_shuffle() below.
local LOCAL_SHUFFLE_WINDOW = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderLocalShuffleWindow")) or 4

-- "weighted" Shuffle Mode setting (V3): 0 = original order, 100 = full
-- shuffle - see weighted_shuffle() below.
local WEIGHTED_SHUFFLE_AMOUNT = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderWeightedShuffleAmount")) or 50

-- Palindrome mode (V3): mirrors the final segment order (after
-- repeats) in reverse - see apply_palindrome() below.
local PALINDROME_MODE = reaper.GetExtState(EXT_SECTION, "ShredderPalindrome") == "1"

-- Scale-Quantized Pitch (V3): snaps randomized pitch to the nearest
-- semitone in a chosen scale - see quantize_to_scale() below.
local SCALE_QUANTIZE = reaper.GetExtState(EXT_SECTION, "ShredderScaleQuantize") == "1"
local SCALE_ROOT = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderScaleRoot")) or 0
local SCALE_TYPE = reaper.GetExtState(EXT_SECTION, "ShredderScaleType")
local VALID_SCALE_TYPES = { major = true, minor = true, majpent = true, minpent = true, chromatic = true }
if not VALID_SCALE_TYPES[SCALE_TYPE] then SCALE_TYPE = "major" end

local SCALES = {
  major = { 0, 2, 4, 5, 7, 9, 11 },
  minor = { 0, 2, 3, 5, 7, 8, 10 },
  majpent = { 0, 2, 4, 7, 9 },
  minpent = { 0, 3, 5, 7, 10 },
  chromatic = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 },
}

-- Sidechain-Aware Shredding (V3): gates/ducks segments based on
-- another track's audio energy at their ORIGINAL position - see
-- apply_sidechain() below.
local SIDECHAIN_ENABLED = reaper.GetExtState(EXT_SECTION, "ShredderSidechainEnabled") == "1"
local SIDECHAIN_TRACK_NAME = reaper.GetExtState(EXT_SECTION, "ShredderSidechainTrack")
local SIDECHAIN_THRESHOLD = (tonumber(reaper.GetExtState(EXT_SECTION, "ShredderSidechainThreshold")) or 10) / 100
local SIDECHAIN_INVERT = reaper.GetExtState(EXT_SECTION, "ShredderSidechainInvert") == "1"
local SIDECHAIN_DROP = reaper.GetExtState(EXT_SECTION, "ShredderSidechainDrop") == "1"

-- Ordered-Subset mode (V2): when on, each segment is independently
-- kept with SUBSET_KEEP_PERCENT% chance and dropped otherwise, always
-- in original order (never shuffled) - see APPENDIX (V2) notes up top.
local ORDERED_SUBSET_MODE = reaper.GetExtState(EXT_SECTION, "ShredderSubsetMode") == "1"
local SUBSET_KEEP_PERCENT = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderSubsetKeepPercent")) or 70

-- Skip segments below SILENCE_THRESHOLD peak amplitude (~-34dB) when
-- reshuffling - keeps silent gaps out of the result instead of
-- scattering them randomly through it.
local IGNORE_SILENCE = reaper.GetExtState(EXT_SECTION, "ShredderIgnoreSilence") == "1"
local SILENCE_THRESHOLD = 0.02
local SILENCE_SAMPLERATE = 8000 -- downsampled read rate for the silence check, same idea as ReaEnvious

-- Per-segment randomization intensities, all read from ExtState (set
-- via the Randomizer UI's Shredder tab sliders) and all "how much"
-- controls, not fixed values - every segment gets its OWN random pick
-- within the range the current intensity allows:
--   POSITION_INTENSITY (0-150ms): each segment's placed position gets
--     an extra +/- random offset up to this many ms, on top of the
--     normal sequential reshuffle placement. 0 = no jitter.
--   RATE_INTENSITY (1x-3x): each segment's take playrate is randomized
--     between 1x (neutral) and this value. 1 = no randomization.
--   PITCH_INTENSITY (-12 to +12 semitones): each segment's take pitch
--     is randomized anywhere in [-|intensity|, +|intensity|] - fully
--     bipolar; the slider's own sign doesn't matter, only its
--     magnitude does. 0 = no change.
--   PAN_INTENSITY (-100 to +100%): same bipolar idea, applied to take
--     pan. No range was specified for this one - +/-100% is REAPER's
--     own full-left/full-right span, used as a sensible default.
--   VOLUME_INTENSITY (-6 to +6dB): same bipolar idea, applied to take
--     volume (converted from dB to REAPER's linear D_VOL internally).
local POSITION_INTENSITY = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderPositionMs")) or 0
local RATE_INTENSITY = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderRate")) or 1
local PITCH_INTENSITY = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderPitch")) or 0
local PAN_INTENSITY = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderPan")) or 0
local VOLUME_INTENSITY = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderVolume")) or 0

-- Direction (V12): constrains which way each bipolar property can
-- move - "both" (default, original behavior, random anywhere in
-- [-magnitude, +magnitude]), "neg" (only the negative half - down/
-- left/quieter/earlier), or "pos" (only the positive half - up/right/
-- louder/later). Only applies to the four properties that are
-- naturally centered on a neutral value; Rate, Reverse, Repeats, and
-- Mute don't have a comparable "direction" (see directional_random()
-- below for exactly how each value gets shaped).
local function valid_direction(d) return d == "neg" or d == "pos" or d == "both" end
local POSITION_DIRECTION = reaper.GetExtState(EXT_SECTION, "ShredderPositionDirection")
local PITCH_DIRECTION = reaper.GetExtState(EXT_SECTION, "ShredderPitchDirection")
local PAN_DIRECTION = reaper.GetExtState(EXT_SECTION, "ShredderPanDirection")
local VOLUME_DIRECTION = reaper.GetExtState(EXT_SECTION, "ShredderVolumeDirection")
if not valid_direction(POSITION_DIRECTION) then POSITION_DIRECTION = "both" end
if not valid_direction(PITCH_DIRECTION) then PITCH_DIRECTION = "both" end
if not valid_direction(PAN_DIRECTION) then PAN_DIRECTION = "both" end
if not valid_direction(VOLUME_DIRECTION) then VOLUME_DIRECTION = "both" end

-- Stretch (0-1000%): each segment gets a random time-stretch anywhere in
-- [-magnitude, +magnitude]% (constrained by its own Direction), pitch
-- preserved. +100% = twice as long, +1000% = 11x as long; negative
-- values mirror that as a shrink (-100% = half length, -1000% = 1/11).
-- 0 = no stretch. See apply_stretch() below.
local STRETCH_INTENSITY = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderStretch")) or 0
local STRETCH_DIRECTION = reaper.GetExtState(EXT_SECTION, "ShredderStretchDirection")
if not valid_direction(STRETCH_DIRECTION) then STRETCH_DIRECTION = "both" end

-- Take pitch shift / time stretch mode applied to every segment, in
-- REAPER's I_PITCHMODE encoding ((shifter << 16) | submode). -1 =
-- leave each take on its own/the project default.
local PITCH_MODE = math.floor(tonumber(reaper.GetExtState(EXT_SECTION, "ShredderPitchMode")) or -1)

-- Randomized pitch mode: when on, each segment independently gets a
-- random pick from PITCH_MODE_POOL instead of PITCH_MODE. The pool is
-- resolved by name from whatever REAPER reports (so it survives mode
-- indices differing between versions); any mode this install doesn't
-- have is simply left out. -1 = project default.
local PITCH_MODE_RANDOM = reaper.GetExtState(EXT_SECTION, "ShredderPitchModeRandom") == "1"

local function find_pitch_shifter(matches)
  if not reaper.EnumPitchShiftModes then return nil end
  for i = 0, 255 do
    local ok, name = reaper.EnumPitchShiftModes(i)
    if not ok then break end
    if name and name ~= "" and matches(name:lower()) then return i end
  end
  return nil
end

local PITCH_MODE_POOL = { -1 }
if PITCH_MODE_RANDOM then
  local wanted = {
    function(n) return n:find("lastique 3", 1, true) and n:find("pro", 1, true) end, -- elastique 3 Pro
    function(n) return n:find("rrreeeaaa", 1, true) end,
    function(n) return n:find("rearearea", 1, true) end,
  }
  for _, matches in ipairs(wanted) do
    local shifter = find_pitch_shifter(matches)
    if shifter then table.insert(PITCH_MODE_POOL, shifter * 65536) end -- submode 0 = that mode's default
  end
end

-- Chance (0-100%) that any given segment plays reversed. 0 = never,
-- 100 = every segment reversed.
local REVERSE_PROBABILITY = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderReverse")) or 0

-- Max number of extra repeats for any given segment - each segment
-- independently gets a random repeat count in [0, this], duplicated
-- back-to-back immediately after itself. 0 = no repeating. Since this
-- can genuinely blow up total length (e.g. many segments each
-- averaging dozens of repeats), it's intentionally a wide range as
-- requested, not artificially capped low.
local REPEAT_MAX = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderRepeat")) or 0

-- Scatter Repeats (V15): when on, duplicate copies from Number Of
-- Repeats land at random positions throughout the result instead of
-- clustering immediately after the segment they're copies of - see
-- expand_with_repeats() below for exactly how.
local SCATTER_REPEATS = reaper.GetExtState(EXT_SECTION, "ShredderScatterRepeats") == "1"

-- Chance (0-100%) that any given chunk (including repeat duplicates,
-- each decided independently) gets muted rather than removed - stays
-- in its slot, contributing silence when glued.
local MUTE_PROBABILITY = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderMute")) or 0

local GLUE_COMMAND_ID = 40362 -- native "Item: Glue items"
local REVERSE_COMMAND_ID = 41051 -- native "Item properties: Toggle take reverse"

-- Cut Only (V13): when on (the default), Run Shredder stops short of
-- the final glue - segments are cut/shuffled/randomized exactly as
-- normal, then selected, grouped (via I_GROUPID rather than a native
-- action, since that's a plain documented MediaItem property, same
-- category as D_POSITION/B_MUTE already used throughout this file),
-- and the edit cursor moves to the start of the selection. See
-- finish_segments() below - both process_single_item() and
-- process_mashup() route through it instead of calling glue_segments()
-- directly.
local CUT_ONLY = reaper.GetExtState(EXT_SECTION, "ShredderCutOnly") ~= "0"

-- Render naming (V14): the glued result's take name is built from a
-- user-editable pattern (Settings tab, UI file) instead of a fixed
-- "Shredder_<n>" - see expand_render_name_pattern() below (defined
-- after next_Shredder_number(), which it calls) for the full
-- wildcard list. Falls back to the original fixed behavior if
-- nothing's been set yet.
local RENDER_NAME_PATTERN = reaper.GetExtState(EXT_SECTION, "ShredderRenderNamePattern")
if RENDER_NAME_PATTERN == "" then RENDER_NAME_PATTERN = "Shredder_{number}" end

-------------------------------------------------------------------
-- CORE LOGIC
-------------------------------------------------------------------

math.randomseed(os.time())

-- Persistent counter for naming glued results "Shredder_<n>" -
-- survives across runs so repeated use doesn't collide names.
local function next_Shredder_number()
  local n = tonumber(reaper.GetExtState(EXT_SECTION, "ShredderCounter")) or 0
  n = n + 1
  reaper.SetExtState(EXT_SECTION, "ShredderCounter", tostring(n), true)
  return n
end

-- Expands {wildcards} in RENDER_NAME_PATTERN into the glued item's
-- actual name. `source_name` is the ORIGINAL (pre-shred) item's take
-- name - process_single_item()/process_mashup() capture this BEFORE
-- cutting begins, since the original item reference doesn't survive
-- past that point. {number} still calls next_Shredder_number() (the
-- same persistent ExtState counter the old fixed naming always used),
-- so existing "Shredder_<n>" - style numbering stays continuous even
-- after switching to a custom pattern.
--   {name}   - the original item's take name (falls back to "item" if
--              it has none, e.g. an empty/unnamed take)
--   {number} - the persistent incrementing counter
--   {mode}   - the current Cut Mode (e.g. "blackhole", "euclid")
--   {date}   - today's date, YYYY-MM-DD
--   {time}   - current time, HH-MM-SS (hyphens, not colons - colons
--              aren't valid in filenames on Windows)
local function expand_render_name_pattern(source_name)
  local result = RENDER_NAME_PATTERN
  result = result:gsub("{name}", (source_name and source_name ~= "") and source_name or "item")
  result = result:gsub("{number}", tostring(next_Shredder_number()))
  result = result:gsub("{mode}", CUT_MODE or "")
  result = result:gsub("{date}", os.date("%Y-%m-%d"))
  result = result:gsub("{time}", os.date("%H-%M-%S"))
  return result
end

-- Returns a shuffled copy of t (does not modify t).
local function shuffle_copy(t)
  local copy = {}
  for i, v in ipairs(t) do
    copy[i] = v
  end
  for i = #copy, 2, -1 do
    local j = math.random(i)
    copy[i], copy[j] = copy[j], copy[i]
  end
  return copy
end

-- "local" Shuffle Mode (V3): chunks `segments` into consecutive groups
-- of `window` and shuffles each group independently, then concatenates
-- the groups back in their original order - keeps the item's broad
-- structure recognizable while still jumbling detail within each
-- window. The final group may be smaller than `window` if it doesn't
-- divide evenly.
local function local_shuffle(segments, window)
  window = math.max(2, math.floor(window))
  local result = {}
  local i = 1
  local n = #segments
  while i <= n do
    local j = math.min(i + window - 1, n)
    local group = {}
    for idx = i, j do table.insert(group, segments[idx]) end
    group = shuffle_copy(group)
    for _, seg in ipairs(group) do table.insert(result, seg) end
    i = j + 1
  end
  return result
end

-- "weighted" Shuffle Mode (V3): a single amount_percent (0-100) dial
-- that continuously blends between original order (0) and a full
-- random shuffle (100). Implemented as a jittered-index sort: each
-- segment's original index gets a random offset scaled by the amount
-- (as a fraction of the segment count), then the list is re-sorted by
-- that key - a practical "how much disorder" dial rather than a
-- literal Markov chain, but one that gives the same continuous
-- order-to-chaos control the name implies.
local function weighted_shuffle(segments, amount_percent)
  local n = #segments
  if n <= 1 then return segments end

  local amount = math.max(0, math.min(100, amount_percent)) / 100
  local keyed = {}
  for i, seg in ipairs(segments) do
    local jitter = (math.random() * 2 - 1) * amount * n
    keyed[i] = { seg = seg, key = i + jitter }
  end
  table.sort(keyed, function(a, b) return a.key < b.key end)

  local result = {}
  for i, k in ipairs(keyed) do result[i] = k.seg end
  return result
end

-- Dispatches to whichever Shuffle Mode is active (see SHUFFLE_MODE
-- above). Note: callers should skip this entirely (and just use
-- `segments` as-is) when ORDERED_SUBSET_MODE is on, since that mode
-- always preserves original order regardless of this setting.
local function apply_shuffle_mode(segments)
  if SHUFFLE_MODE == "none" then
    return segments
  elseif SHUFFLE_MODE == "local" then
    return local_shuffle(segments, LOCAL_SHUFFLE_WINDOW)
  elseif SHUFFLE_MODE == "weighted" then
    return weighted_shuffle(segments, WEIGHTED_SHUFFLE_AMOUNT)
  end
  return shuffle_copy(segments)
end

-- Generates a sorted list of random ABSOLUTE cut positions strictly
-- Generates a sorted list of ABSOLUTE cut positions strictly inside
-- [item_pos, item_pos + item_len], each at least MIN_SEGMENT_LEN apart
-- from its neighbors and from the item's own start/end - segment SIZE
-- is what's controlled here, not segment COUNT. Walks through the
-- item, advancing by TARGET_CUT_LENGTH each step and recording a cut
-- point at each step. With CUT_LENGTH_FIXED off (the default), each
-- step's actual length is randomized +/-50% around TARGET_CUT_LENGTH
-- instead of using it exactly - this has been "By Cut Length"'s
-- behavior since it was first built, an organic/non-mechanical feel
-- being the whole point of the mode. With CUT_LENGTH_FIXED on, that
-- randomization is skipped entirely: every segment is exactly
-- TARGET_CUT_LENGTH (still floored by MIN_SEGMENT_LEN) - genuinely
-- equal-length chunks, none of the +/-50% spread. Either way, the
-- FINAL segment (whatever's left between the last cut and the item's
-- actual end) can still end up a different length than the rest -
-- same "leftover absorbs the remainder" behavior every other Cut Mode
-- in this script already has, not specific to this one.
-- Returns an empty list if the item is too short to cut at all.
local function generate_cut_positions_by_length(item_pos, item_len)
  if item_len < MIN_SEGMENT_LEN * 2 then return {} end

  local positions = {}
  local pos = item_pos
  local limit = item_pos + item_len - MIN_SEGMENT_LEN
  local variance = TARGET_CUT_LENGTH * 0.5

  while true do
    local seg_len
    if CUT_LENGTH_FIXED then
      seg_len = math.max(MIN_SEGMENT_LEN, TARGET_CUT_LENGTH)
    else
      seg_len = math.max(MIN_SEGMENT_LEN, TARGET_CUT_LENGTH + (math.random() * 2 - 1) * variance)
    end
    pos = pos + seg_len
    if pos > limit then break end
    table.insert(positions, pos)
  end

  return positions
end

-- "count" mode: picks a target NUMBER of cuts, scatters them randomly
-- across the item, then enforces minimum spacing - segment COUNT is
-- what's controlled here, not size (contrast "length" mode, which
-- targets exact segment SIZE and produces however many segments fall
-- out of that). With CUT_LENGTH_FIXED off (the default), the count
-- itself is randomized +/-20% around TARGET_NUM_CUTS for organic
-- variation - the same setting/spirit as "length" mode's own +/-50%,
-- just applied to count instead of size, and sharing that one setting
-- rather than needing a second Fixed/Randomized toggle of its own.
-- With CUT_LENGTH_FIXED on, that variance is skipped: exactly
-- TARGET_NUM_CUTS cuts, no randomization of the count. Either way the
-- individual cut POSITIONS are still randomly scattered - "Fixed"
-- here means the COUNT is exact, not that positions become evenly
-- spaced or deterministic (same relationship "length" mode's Fixed
-- has to ITS positions - exact SIZE, still organically placed).
local function generate_cut_positions_by_count(item_pos, item_len)
  if item_len < MIN_SEGMENT_LEN * 2 then return {} end

  local num_cuts
  if CUT_LENGTH_FIXED then
    num_cuts = TARGET_NUM_CUTS
  else
    local variance = math.max(1, math.floor(TARGET_NUM_CUTS * 0.2))
    num_cuts = TARGET_NUM_CUTS + math.random(-variance, variance)
  end
  num_cuts = math.max(1, num_cuts)

  local max_possible_cuts = math.floor(item_len / MIN_SEGMENT_LEN) - 1
  num_cuts = math.min(num_cuts, math.max(0, max_possible_cuts))
  if num_cuts <= 0 then return {} end

  local positions = {}
  for i = 1, num_cuts do
    positions[i] = item_pos + MIN_SEGMENT_LEN + math.random() * (item_len - 2 * MIN_SEGMENT_LEN)
  end
  table.sort(positions)

  -- Enforce minimum spacing by nudging any too-close cuts forward.
  for i = 2, #positions do
    if positions[i] - positions[i - 1] < MIN_SEGMENT_LEN then
      positions[i] = positions[i - 1] + MIN_SEGMENT_LEN
    end
  end

  local limit = item_pos + item_len - MIN_SEGMENT_LEN
  while #positions > 0 and positions[#positions] > limit do
    table.remove(positions)
  end

  return positions
end

-- "beat" mode (V2): cuts land on the project tempo grid at a chosen
-- note division (BEAT_DIVISION_BEATS, in quarter-note beats) rather
-- than free-running seconds - segments are exactly one division long.
-- Walks in QUARTER-NOTE (QN) space and converts each step back to
-- project time via TimeMap2_QNToTime, which is tempo-map aware, so
-- the grid stays correct even if tempo changes partway through the
-- item. Optional BEAT_VARIANCE_PERCENT adds a small +/- humanize
-- jitter around each cut, sized as a fraction of that division's own
-- length in seconds at the current tempo.
local function generate_cut_positions_by_beat(item_pos, item_len)
  if item_len < MIN_SEGMENT_LEN * 2 then return {} end
  if BEAT_DIVISION_BEATS <= 0 then return {} end

  local end_time = item_pos + item_len
  local limit = end_time - MIN_SEGMENT_LEN
  local start_qn = reaper.TimeMap2_timeToQN(0, item_pos)

  local positions = {}
  local qn = start_qn + BEAT_DIVISION_BEATS
  local prev_t = item_pos

  while true do
    local t = reaper.TimeMap2_QNToTime(0, qn)
    if t > limit then break end

    if BEAT_VARIANCE_PERCENT > 0 then
      local div_seconds = t - prev_t -- this division's actual length in seconds at the current tempo
      local jitter = (math.random() * 2 - 1) * (div_seconds * (BEAT_VARIANCE_PERCENT / 100) * 0.5)
      t = t + jitter
      if t - prev_t < MIN_SEGMENT_LEN then t = prev_t + MIN_SEGMENT_LEN end
      if t > limit then break end
    end

    table.insert(positions, t)
    prev_t = t
    qn = qn + BEAT_DIVISION_BEATS
  end

  return positions
end

-- Evenly distributes `k` hits among `n` steps using a running-bucket
-- (digital differential analyzer) method - the same class of
-- "maximally even" spacing that classic Euclidean-rhythm algorithms
-- (e.g. Bjorklund's) produce, though the phase/rotation of the
-- resulting pattern isn't guaranteed to match Bjorklund's exactly.
-- Returns an array of `n` booleans, index 1..n, true = hit.
local function euclidean_pattern(k, n)
  local pattern = {}
  if n <= 0 then return pattern end
  k = math.max(0, math.min(k, n))
  local bucket = 0
  for i = 1, n do
    bucket = bucket + k
    if bucket >= n then
      bucket = bucket - n
      pattern[i] = true
    else
      pattern[i] = false
    end
  end
  return pattern
end

-- "euclid" mode (V3): divides the item into EUCLID_STEPS equal steps
-- and cuts at every step whose Euclidean pattern position is a hit
-- (skipping step 1, since a cut at the item's own start is a no-op).
local function generate_cut_positions_by_euclid(item_pos, item_len)
  if item_len < MIN_SEGMENT_LEN * 2 then return {} end

  local n = math.max(1, math.floor(EUCLID_STEPS))
  local k = math.max(0, math.min(math.floor(EUCLID_HITS), n))
  local step_len = item_len / n
  if step_len < MIN_SEGMENT_LEN then return {} end -- item too short for this many steps

  local pattern = euclidean_pattern(k, n)
  local positions = {}
  for i = 2, n do
    if pattern[i] then
      table.insert(positions, item_pos + (i - 1) * step_len)
    end
  end
  return positions
end

-- Returns the first `count` Fibonacci numbers (1,1,2,3,5,8,13...).
local function fibonacci_sequence(count)
  local seq = {}
  local a, b = 1, 1
  for i = 1, count do
    seq[i] = a
    a, b = b, a + b
  end
  return seq
end

-- Returns the first `count` Lucas numbers (2,1,3,4,7,11,18...) - same
-- recurrence as Fibonacci (each term is the sum of the previous two),
-- different seed values.
local function lucas_sequence(count)
  local seq = {}
  local a, b = 2, 1
  for i = 1, count do
    seq[i] = a
    a, b = b, a + b
  end
  return seq
end

-- Returns the first `count` Padovan numbers (1,1,1,2,2,3,4,5,7,9,12,
-- 16...) - each term is the sum of the values 2 and 3 positions back,
-- rather than Fibonacci's 1 and 2 - grows more slowly (converges to
-- the plastic number, ~1.3247, instead of the golden ratio, ~1.618).
local function padovan_sequence(count)
  local seq = { 1, 1, 1 }
  for i = 4, count do
    seq[i] = seq[i - 2] + seq[i - 3]
  end
  local result = {}
  for i = 1, count do result[i] = seq[i] end
  return result
end

-- Returns the first `count` Tribonacci numbers (1,1,2,4,7,13,24,44...)
-- - sum of the previous THREE values instead of two - grows faster
-- than Fibonacci.
local function tribonacci_sequence(count)
  local seq = { 1, 1, 2 }
  for i = 4, count do
    seq[i] = seq[i - 1] + seq[i - 2] + seq[i - 3]
  end
  local result = {}
  for i = 1, count do result[i] = seq[i] end
  return result
end

-- Parses SEQUENCE_CUSTOM ("1,1,2,3,5,8" or any comma-separated list of
-- positive numbers) into a weights array. Non-numeric or non-positive
-- entries are dropped silently; an empty/all-invalid result falls
-- back to a single flat weight so the mode never produces zero cuts
-- just from a typo.
local function parse_custom_sequence(str)
  local weights = {}
  for token in string.gmatch(str or "", "[^,]+") do
    local n = tonumber(token)
    if n and n > 0 then table.insert(weights, n) end
  end
  if #weights == 0 then weights = { 1 } end
  return weights
end

-- Dispatches to whichever SEQUENCE_TYPE is active. `num_segments` is
-- ignored for "custom", which uses however many numbers were typed.
local function get_sequence_weights(num_segments)
  if SEQUENCE_TYPE == "lucas" then
    return lucas_sequence(num_segments)
  elseif SEQUENCE_TYPE == "padovan" then
    return padovan_sequence(num_segments)
  elseif SEQUENCE_TYPE == "tribonacci" then
    return tribonacci_sequence(num_segments)
  elseif SEQUENCE_TYPE == "custom" then
    return parse_custom_sequence(SEQUENCE_CUSTOM)
  end
  return fibonacci_sequence(num_segments)
end

-- "sequence" mode (V3 as "fibonacci", generalized in V4): segment
-- lengths proportional to the chosen SEQUENCE_TYPE's numbers
-- (normalized to fit item_len), in growing order by default or
-- shrinking order with FIB_DESCENDING - gives an organic, structured
-- sense of scale across the item rather than equal-sized or random
-- segments. See the APPENDIX (V4) note up top for what each sequence
-- type looks like.
local function generate_cut_positions_by_sequence(item_pos, item_len)
  if item_len < MIN_SEGMENT_LEN * 2 then return {} end

  local num_segments = math.max(2, math.floor(FIB_NUM_SEGMENTS))
  local weights = get_sequence_weights(num_segments)
  if #weights < 2 then weights = { weights[1] or 1, weights[1] or 1 } end

  if FIB_DESCENDING then
    local reversed = {}
    for i = 1, #weights do reversed[i] = weights[#weights - i + 1] end
    weights = reversed
  end

  local total_weight = 0
  for _, w in ipairs(weights) do total_weight = total_weight + w end
  if total_weight <= 0 then return {} end

  local positions = {}
  local pos = item_pos
  local limit = item_pos + item_len - MIN_SEGMENT_LEN
  for i = 1, #weights - 1 do
    pos = pos + item_len * (weights[i] / total_weight)
    if pos > limit then break end
    table.insert(positions, pos)
  end
  return positions
end

-- "onset" mode: a multi-band transient detector. Reads the item's own
-- audio via a take audio accessor at 22.05kHz, measures per-frame
-- level in low/high/full bands, and picks frames where the summed dB
-- rise clearly beats the local average (adaptive threshold, level-
-- independent). Each hit is then placed sample-accurately just before
-- its attack, snapped to a zero crossing. Hits closer than
-- ONSET_MIN_GAP_SEC (or MIN_SEGMENT_LEN, if larger) merge into the
-- stronger one.
local function generate_cut_positions_by_onset(item, item_pos, item_len)
  if item_len < MIN_SEGMENT_LEN * 2 then return {} end

  local take = reaper.GetActiveTake(item)
  if not take then return {} end

  local accessor = reaper.CreateTakeAudioAccessor(take)
  if not accessor then return {} end

  local rate, hop = ONSET_ANALYSIS_RATE, ONSET_HOP
  local num_frames = math.floor(item_len * rate / hop)
  if num_frames < 5 then
    reaper.DestroyAudioAccessor(accessor)
    return {}
  end

  -- Pass 1: per-frame level (dB) in three bands - low (one-pole LP),
  -- high (input minus a one-pole LP), and full band. Tracking bands
  -- separately means a hi-hat over a sustained bass note still shows
  -- up as a clear jump in the high band, even when the full-band level
  -- barely moves.
  local LN10 = math.log(10)
  local function to_db(e) return 10 * math.log(e + 1e-12) / LN10 end

  local a_low = math.exp(-2 * math.pi * ONSET_LOW_HZ / rate)
  local a_high = math.exp(-2 * math.pi * ONSET_HIGH_HZ / rate)
  local lp_low, lp_high = 0, 0

  local low_db, high_db, full_db = {}, {}, {}
  local peak_db = -math.huge
  local block_frames = 256
  local buf = reaper.new_array(block_frames * hop * 2)

  local frame = 0
  while frame < num_frames do
    local nf = math.min(block_frames, num_frames - frame)
    buf.clear()
    reaper.GetAudioAccessorSamples(accessor, rate, 2, frame * hop / rate, nf * hop, buf)
    for f = 0, nf - 1 do
      local e_low, e_high, e_full = 0, 0, 0
      for i = f * hop, f * hop + hop - 1 do
        local x = (buf[i * 2 + 1] + buf[i * 2 + 2]) * 0.5
        lp_low = x + a_low * (lp_low - x)
        lp_high = x + a_high * (lp_high - x)
        local h = x - lp_high
        e_low = e_low + lp_low * lp_low
        e_high = e_high + h * h
        e_full = e_full + x * x
      end
      local idx = frame + f + 1
      low_db[idx] = to_db(e_low / hop)
      high_db[idx] = to_db(e_high / hop)
      full_db[idx] = to_db(e_full / hop)
      if full_db[idx] > peak_db then peak_db = full_db[idx] end
    end
    frame = frame + nf
  end

  -- Pass 2: onset strength per frame = summed dB rise across the three
  -- bands, measured against two frames back (so an attack that
  -- straddles a frame boundary isn't split in half). Levels are
  -- floored at the gate so rising out of near-silence doesn't count as
  -- a 100dB jump, and frames below the gate are ignored entirely -
  -- noise floors/reverb tails can't trigger cuts. Working in dB makes
  -- the whole thing level-independent: a quiet take and a loud one
  -- get the same cuts.
  local gate = peak_db - ONSET_GATE_DB
  local odf = {}
  for n = 1, num_frames do
    if n <= 2 or full_db[n] < gate then
      odf[n] = 0
    else
      local s = 0
      for _, band in ipairs({ low_db, high_db, full_db }) do
        local rise = math.max(band[n], gate) - math.max(band[n - 2], gate)
        if rise > 0 then s = s + rise end
      end
      odf[n] = s
    end
  end

  -- Pass 3: adaptive peak-picking. A frame is a transient when it's a
  -- local maximum (+/-2 frames) AND beats the local average (over
  -- +/-ONSET_AVG_SEC) by the Sensitivity-derived margin - busy
  -- passages need a bigger jump than sparse ones.
  local delta = 3 + math.max(1, ONSET_SENSITIVITY_PERCENT) * 0.45 -- 5% ~ 5dB ... 100% ~ 48dB
  local half_w = math.max(1, math.floor(ONSET_AVG_SEC * rate / hop))
  local prefix = { [0] = 0 }
  for n = 1, num_frames do prefix[n] = prefix[n - 1] + odf[n] end

  local candidates = {}
  for n = 3, num_frames - 2 do
    local v = odf[n]
    if v > 0 and v > odf[n - 1] and v >= odf[n + 1] and v >= odf[n - 2] and v >= odf[n + 2] then
      local lo, hi = math.max(1, n - half_w), math.min(num_frames, n + half_w)
      local mean = (prefix[hi] - prefix[lo - 1]) / (hi - lo + 1)
      if v > mean + delta then
        table.insert(candidates, { frame = n, strength = v })
      end
    end
  end

  -- Pass 4: sample-accurate placement. The frame grid is ~6ms coarse,
  -- so re-read just the audio around each detected frame, find where
  -- the attack actually starts rising out of whatever came before it,
  -- back off a hair of pre-roll, and snap to the nearest preceding
  -- zero crossing - cuts land just BEFORE the hit (never clipping its
  -- front edge) and without clicks.
  local region_len = hop * 4
  local rbuf = reaper.new_array(region_len * 2)
  local hold = math.max(1, math.floor(rate * 0.0005))
  local preroll = math.floor(rate * ONSET_PREROLL_SEC)
  local zc_search = math.floor(rate * 0.001)

  local function refine(n)
    local rstart = math.max(0, (n - 3) * hop)
    rbuf.clear()
    reaper.GetAudioAccessorSamples(accessor, rate, 2, rstart / rate, region_len, rbuf)

    local x, env = {}, {}
    for i = 0, region_len - 1 do
      x[i] = (rbuf[i * 2 + 1] + rbuf[i * 2 + 2]) * 0.5
    end
    local p, peak = 0, 0
    for i = 0, region_len - 1 do
      local m = 0
      for j = math.max(0, i - hold), i do
        local a = math.abs(x[j])
        if a > m then m = a end
      end
      env[i] = m
      if m > peak then peak, p = m, i end
    end

    local baseline = peak
    for i = 0, p do
      if env[i] < baseline then baseline = env[i] end
    end
    if peak - baseline <= 1e-6 then return (n - 1) * hop / rate end

    local thr = baseline + 0.1 * (peak - baseline)
    local i = p
    while i > 0 and env[i] > thr do i = i - 1 end
    i = math.max(0, i - preroll)
    for j = i, math.max(1, i - zc_search), -1 do
      if (x[j] >= 0) ~= (x[j - 1] >= 0) then
        i = j
        break
      end
    end
    return (rstart + i) / rate
  end

  local gap = math.max(MIN_SEGMENT_LEN, ONSET_MIN_GAP_SEC)
  local picked = {}
  for _, c in ipairs(candidates) do
    local t = item_pos + refine(c.frame)
    local last = picked[#picked]
    if last and t - last.t < gap then
      -- Too close to the previous one: keep whichever hit is stronger.
      if c.strength > last.strength then
        last.t, last.strength = t, c.strength
      end
    else
      table.insert(picked, { t = t, strength = c.strength })
    end
  end
  reaper.DestroyAudioAccessor(accessor)

  local positions = {}
  local lo_bound = item_pos + MIN_SEGMENT_LEN
  local hi_bound = item_pos + item_len - MIN_SEGMENT_LEN
  for _, pk in ipairs(picked) do
    local prev = positions[#positions]
    if pk.t >= lo_bound and pk.t <= hi_bound and (not prev or pk.t - prev >= MIN_SEGMENT_LEN) then
      table.insert(positions, pk.t)
    end
  end
  return positions
end

-- "blackhole" mode (V5, looping added V9): starts at BLACKHOLE_START
-- and repeatedly multiplies by BLACKHOLE_DECAY to get each next
-- chunk's size (a fixed-ratio geometric shrink, which is what makes
-- the resulting cut positions land at logarithmically-decreasing
-- intervals), laying chunks out back-to-back from the item's start.
--
-- A geometric series has a FINITE sum even carried out forever -
-- BLACKHOLE_START / (1 - BLACKHOLE_DECAY) - so with BLACKHOLE_LOOP
-- off, one collapse cycle only ever covers that much of the item
-- (e.g. the defaults sum to exactly 3 seconds, regardless of item
-- length) before bottoming out below MIN_SEGMENT_LEN, at which point
-- everything else becomes one large, untouched leftover segment. With
-- BLACKHOLE_LOOP on (the default), once a cycle bottoms out it
-- restarts from BLACKHOLE_START and collapses again, repeating for as
-- long as the item has room - covering the WHOLE item with a
-- repeating collapse pattern instead of one collapse followed by a
-- static tail. Either way, whatever's left once the final cycle no
-- longer fits becomes one last segment absorbing the remainder,
-- rather than a stray sliver or a gap. Capped at MAX_CHUNKS as a
-- safety limit, since looping on a long item at small chunk sizes
-- could otherwise produce an excessive number of cuts.
--
-- BLACKHOLE_WHITE_HOLE reverses the ENTIRE computed size list (all
-- cycles at once) before laying out positions - with looping on, this
-- mirrors the whole repeating pattern, so it reads as a repeating
-- GROW-then-reset-to-tiny pattern instead of shrink-then-reset-to-big
-- - same math, read backwards, same as the non-looping case.
local function generate_cut_positions_by_blackhole(item_pos, item_len)
  if item_len < MIN_SEGMENT_LEN * 2 then return {} end
  if BLACKHOLE_START < MIN_SEGMENT_LEN then return {} end

  local sizes = {}
  local size = BLACKHOLE_START
  local total = 0
  local limit = item_len - MIN_SEGMENT_LEN
  local MAX_CHUNKS = 2000

  while total + size < limit and #sizes < MAX_CHUNKS do
    table.insert(sizes, size)
    total = total + size
    size = size * BLACKHOLE_DECAY
    if size < MIN_SEGMENT_LEN then
      if not BLACKHOLE_LOOP then break end
      size = BLACKHOLE_START -- restart the collapse cycle
    end
  end
  if #sizes == 0 then return {} end

  if BLACKHOLE_WHITE_HOLE then
    local reversed = {}
    for i = 1, #sizes do reversed[i] = sizes[#sizes - i + 1] end
    sizes = reversed
  end

  local positions = {}
  local pos = item_pos
  for i = 1, #sizes do
    pos = pos + sizes[i]
    table.insert(positions, pos)
  end
  return positions
end

-- "pitagora" mode (V6): recursive fractal split using a real
-- Pythagorean triple's leg ratio - see the APPENDIX (V6) note up top.
-- Splits the item (treated as the hypotenuse) into two children sized
-- a/(a+b) and b/(a+b) of its own length, then recurses into BOTH
-- children the same way, branching until a child would be smaller
-- than MIN_SEGMENT_LEN or MAX_CUTS is hit (a safety cap - deep
-- recursion on a long item with a lopsided ratio could otherwise
-- produce an excessive number of cuts). Cuts are collected in tree
-- traversal order, not left-to-right, so the result is sorted before
-- returning.
local function generate_cut_positions_by_pitagora(item_pos, item_len)
  if item_len < MIN_SEGMENT_LEN * 2 then return {} end

  local triple = PITAGORA_TRIPLES[PITAGORA_TRIPLE]
  local a, b = triple[1], triple[2]
  local frac_a = a / (a + b)

  local positions = {}
  local MAX_CUTS = 300

  local function recurse(start, len)
    if #positions >= MAX_CUTS then return end
    if len < MIN_SEGMENT_LEN * 2 then return end
    local len_a = len * frac_a
    local len_b = len - len_a
    if len_a < MIN_SEGMENT_LEN or len_b < MIN_SEGMENT_LEN then return end
    table.insert(positions, start + len_a)
    recurse(start, len_a)
    recurse(start + len_a, len_b)
  end

  recurse(item_pos, item_len)
  table.sort(positions)
  return positions
end

-- Runs the Collatz ("3n+1") sequence from `seed`: while n isn't 1, n
-- becomes n/2 if even, or 3n+1 if odd. Returns the sequence of values
-- visited (including the seed itself and the final 1), capped at
-- `max_terms` as a safety limit.
local function collatz_sequence(seed, max_terms)
  local seq = { seed }
  local n = seed
  while n ~= 1 and #seq < max_terms do
    if n % 2 == 0 then
      n = math.floor(n / 2)
    else
      n = 3 * n + 1
    end
    table.insert(seq, n)
  end
  return seq
end

-- "collatz" mode (V7): the Collatz sequence's values become segment-
-- length weights (same normalize-and-lay-out approach as "sequence"
-- mode) - see the APPENDIX (V7) note up top. Can swell dramatically
-- before crashing down to 1, unlike Blackhole's monotonic shrink.
local function generate_cut_positions_by_collatz(item_pos, item_len)
  if item_len < MIN_SEGMENT_LEN * 2 then return {} end

  local weights = collatz_sequence(math.max(2, math.floor(COLLATZ_SEED)), 300)
  if #weights < 2 then return {} end

  if COLLATZ_DESCENDING then
    local reversed = {}
    for i = 1, #weights do reversed[i] = weights[#weights - i + 1] end
    weights = reversed
  end

  local total_weight = 0
  for _, w in ipairs(weights) do total_weight = total_weight + w end
  if total_weight <= 0 then return {} end

  local positions = {}
  local pos = item_pos
  local limit = item_pos + item_len - MIN_SEGMENT_LEN
  for i = 1, #weights - 1 do
    pos = pos + item_len * (weights[i] / total_weight)
    if pos > limit then break end
    table.insert(positions, pos)
  end
  return positions
end

-- "cantor" mode (V7): the classical Cantor-set construction applied
-- to the timeline - recursively divides a segment into thirds, keeps
-- the left and right thirds as further-recursable pieces, and marks
-- the MIDDLE third as a fixed hole, `depth` times. Unlike every other
-- generate_cut_positions_by_*() function, this ALSO sets the module-
-- level STRUCTURAL_MUTE_INDICES (which of the resulting segments,
-- left-to-right, are holes) as a side effect - see the APPENDIX (V7)
-- note up top for why. `leaves` is built by the recursive call order
-- itself (left branch fully recurses before the hole is recorded,
-- which is before the right branch recurses), so it comes out already
-- in left-to-right order - no separate sort needed, unlike Pitagora.
local function generate_cut_positions_by_cantor(item_pos, item_len)
  STRUCTURAL_MUTE_INDICES = nil
  if item_len < MIN_SEGMENT_LEN * 2 then return {} end

  local depth = math.max(1, math.min(7, math.floor(CANTOR_DEPTH)))
  local leaves = {}
  local MAX_LEAVES = 400

  local function recurse(start, len, level)
    local third = len / 3
    if level <= 0 or third < MIN_SEGMENT_LEN or #leaves >= MAX_LEAVES then
      table.insert(leaves, { start = start, len = len, is_hole = false })
      return
    end
    recurse(start, third, level - 1)
    table.insert(leaves, { start = start + third, len = third, is_hole = true })
    recurse(start + third * 2, third, level - 1)
  end

  recurse(item_pos, item_len, depth)

  local positions = {}
  local hole_indices = {}
  for i, leaf in ipairs(leaves) do
    if leaf.is_hole then hole_indices[i] = true end
    if i < #leaves then
      table.insert(positions, leaf.start + leaf.len)
    end
  end

  STRUCTURAL_MUTE_INDICES = hole_indices
  return positions
end

-- Encodes `text` into a flat list of Morse "symbols", each one either
-- a dot, a dash, or one of three silent gap types (between symbols
-- within a letter, between letters, or between words) - standard
-- International Morse Code timing: dot = 1 unit, dash = 3 units,
-- intra-letter gap = 1 unit, inter-letter gap = 3 units, inter-word
-- gap = 7 units. Characters not in MORSE_TABLE and not a space are
-- silently skipped. Returns an array of { units = N, muted = bool }.
local function morse_encode(text)
  local symbols = {}
  local at_word_start = true

  local function add(units, muted)
    table.insert(symbols, { units = units, muted = muted })
  end

  for i = 1, #text do
    local ch = text:sub(i, i):upper()
    if ch == " " then
      if not at_word_start then add(7, true) end
      at_word_start = true
    else
      local code = MORSE_TABLE[ch]
      if code then
        if not at_word_start then add(3, true) end -- inter-letter gap
        at_word_start = false
        for j = 1, #code do
          if j > 1 then add(1, true) end -- intra-letter gap
          if code:sub(j, j) == "." then add(1, false) else add(3, false) end
        end
      end
      -- unsupported character: silently skipped, no gap inserted for it
    end
  end
  return symbols
end

-- "morse" mode (V11): encodes MORSE_TEXT into real Morse timing (see
-- morse_encode() above) and lays out one chunk per symbol, each
-- MORSE_UNIT_MS * that symbol's unit count long - dots and dashes are
-- audible, all three gap types are forced silent via STRUCTURAL_MUTE_
-- INDICES (same mechanism Cantor Dust uses - see the APPENDIX (V11)
-- note up top). With MORSE_LOOP on (default), once the whole message
-- has been laid out, it restarts from the first symbol and continues
-- for as long as the item has room - the exact same "restart the
-- cycle once exhausted" idea Black/White Hole's Loop uses, just
-- triggered by running out of symbols instead of decaying below the
-- minimum chunk length. Capped at MAX_CHUNKS as a safety limit.
local function generate_cut_positions_by_morse(item_pos, item_len)
  STRUCTURAL_MUTE_INDICES = nil
  if item_len < MIN_SEGMENT_LEN * 2 then return {} end

  local symbols = morse_encode(MORSE_TEXT)
  if #symbols == 0 then return {} end

  local unit = math.max(MIN_SEGMENT_LEN, MORSE_UNIT_MS / 1000)
  local limit = item_len - MIN_SEGMENT_LEN
  local MAX_CHUNKS = 2000

  local durations, muted_flags = {}, {}
  local total = 0
  local idx = 1

  while total < limit and #durations < MAX_CHUNKS do
    local sym = symbols[idx]
    local dur = sym.units * unit
    if total + dur >= limit then break end -- doesn't fit - leftover becomes the final tail

    table.insert(durations, dur)
    table.insert(muted_flags, sym.muted)
    total = total + dur

    idx = idx + 1
    if idx > #symbols then
      if not MORSE_LOOP then break end
      idx = 1
    end
  end
  if #durations == 0 then return {} end

  local positions = {}
  local mute_indices = {}
  local pos = item_pos
  for i = 1, #durations do
    pos = pos + durations[i]
    table.insert(positions, pos)
    if muted_flags[i] then mute_indices[i] = true end
  end

  STRUCTURAL_MUTE_INDICES = mute_indices
  return positions
end

-- Dispatches to whichever mode is active (see CUT_MODE above).
local function generate_cut_positions(item, item_pos, item_len)
  if CUT_MODE == "count" then
    return generate_cut_positions_by_count(item_pos, item_len)
  elseif CUT_MODE == "beat" then
    return generate_cut_positions_by_beat(item_pos, item_len)
  elseif CUT_MODE == "euclid" then
    return generate_cut_positions_by_euclid(item_pos, item_len)
  elseif CUT_MODE == "sequence" then
    return generate_cut_positions_by_sequence(item_pos, item_len)
  elseif CUT_MODE == "blackhole" then
    return generate_cut_positions_by_blackhole(item_pos, item_len)
  elseif CUT_MODE == "pitagora" then
    return generate_cut_positions_by_pitagora(item_pos, item_len)
  elseif CUT_MODE == "collatz" then
    return generate_cut_positions_by_collatz(item_pos, item_len)
  elseif CUT_MODE == "cantor" then
    return generate_cut_positions_by_cantor(item_pos, item_len)
  elseif CUT_MODE == "morse" then
    return generate_cut_positions_by_morse(item_pos, item_len)
  elseif CUT_MODE == "onset" then
    return generate_cut_positions_by_onset(item, item_pos, item_len)
  end
  return generate_cut_positions_by_length(item_pos, item_len)
end

-- Splits `item` at each position in `cut_positions` (sorted ascending,
-- absolute project time), returning the full list of resulting
-- segment items in their original left-to-right order.
local function split_item_into_segments(item, cut_positions)
  if #cut_positions == 0 then return { item } end

  local segments = {}
  local remainder = item
  for _, pos in ipairs(cut_positions) do
    local right = reaper.SplitMediaItem(remainder, pos)
    if not right then break end -- split failed (shouldn't happen given the spacing above) - keep what we have
    table.insert(segments, remainder)
    remainder = right
  end
  table.insert(segments, remainder)
  return segments
end

-- Peak amplitude (0-1) of a segment item's own audio, read via the
-- same take-audio-accessor technique proven working in ReaEnvious -
-- item-relative time (0 = the segment's own start), downsampled read
-- rate since only a rough peak is needed here.
local function segment_peak_amplitude(item)
  local take = reaper.GetActiveTake(item)
  if not take then return 0 end

  local accessor = reaper.CreateTakeAudioAccessor(take)
  if not accessor then return 0 end

  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local num_samples = math.max(1, math.floor(SILENCE_SAMPLERATE * item_len))
  local buf = reaper.new_array(num_samples * 2) -- 2 channels

  reaper.GetAudioAccessorSamples(accessor, SILENCE_SAMPLERATE, 2, 0, num_samples, buf)

  local peak = 0
  for i = 0, num_samples - 1 do
    local l = buf[i * 2 + 1] or 0
    local r = buf[i * 2 + 2] or 0
    local v = math.max(math.abs(l), math.abs(r))
    if v > peak then peak = v end
  end

  reaper.DestroyAudioAccessor(accessor)
  return peak
end

-- Removes any segments below SILENCE_THRESHOLD from `segments`
-- (deleting their leftover item objects from the track) when
-- IGNORE_SILENCE is on. Otherwise returns `segments` unchanged.
local function filter_silent_segments(segments)
  if not IGNORE_SILENCE then return segments end

  local kept = {}
  for _, seg in ipairs(segments) do
    if segment_peak_amplitude(seg) < SILENCE_THRESHOLD then
      local track = reaper.GetMediaItem_Track(seg)
      reaper.DeleteTrackMediaItem(track, seg)
    else
      table.insert(kept, seg)
    end
  end
  return kept
end

-- Ordered-Subset mode (V2): with ORDERED_SUBSET_MODE on, keeps each
-- segment independently with SUBSET_KEEP_PERCENT% chance and drops
-- (deletes) the rest. Returns `segments` unchanged if the mode is
-- off. Deleted segments are removed from the track entirely (like
-- filter_silent_segments above), not muted, so the glued result ends
-- up shorter than the source - see APPENDIX (V2) notes up top.
-- Structural Mutes (V7, generalized V11): force-mutes exactly the
-- segments STRUCTURAL_MUTE_INDICES marked when the active generator
-- (generate_cut_positions_by_cantor() or _by_morse()) ran - see the
-- APPENDIX (V7)/(V11) notes up top for why this needs to reach beyond
-- the position-only pipeline every other Cut Mode stays within. A
-- no-op for every other CUT_MODE (STRUCTURAL_MUTE_INDICES is only
-- ever set by those two generators). Mutates in place; returns
-- `segments` unchanged (nothing is added or removed).
local function apply_structural_mutes(segments)
  if not STRUCTURAL_MUTE_INDICES then return segments end
  for i, seg in ipairs(segments) do
    if STRUCTURAL_MUTE_INDICES[i] then
      reaper.SetMediaItemInfo_Value(seg, "B_MUTE", 1)
    end
  end
  return segments
end

local function filter_ordered_subset(segments)
  if not ORDERED_SUBSET_MODE then return segments end

  local kept = {}
  for _, seg in ipairs(segments) do
    if math.random() * 100 < SUBSET_KEEP_PERCENT then
      table.insert(kept, seg)
    else
      local track = reaper.GetMediaItem_Track(seg)
      reaper.DeleteTrackMediaItem(track, seg)
    end
  end
  return kept
end

-- Sidechain-Aware Shredding (V3): opens a track audio accessor for
-- SIDECHAIN_TRACK_NAME if the feature is on and a track with that
-- exact name exists. Caller must reaper.DestroyAudioAccessor() the
-- result when done. Returns nil if disabled, no name set, or no
-- matching track is found (in which case the feature is silently a
-- no-op for this run).
local function open_sidechain_accessor()
  if not SIDECHAIN_ENABLED then return nil end
  if SIDECHAIN_TRACK_NAME == "" then return nil end

  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(tr)
    if name == SIDECHAIN_TRACK_NAME then
      return reaper.CreateTrackAudioAccessor(tr)
    end
  end
  return nil
end

-- Reads `track_accessor`'s peak amplitude over [pos, pos + len) in
-- PROJECT time (track accessors, unlike take accessors, use absolute
-- project time rather than item-relative time) - same downsampled-
-- read technique as segment_peak_amplitude above, just on a track's
-- overall audio instead of one take.
local function accessor_peak_amplitude(track_accessor, pos, len)
  local num_samples = math.max(1, math.floor(SILENCE_SAMPLERATE * len))
  local buf = reaper.new_array(num_samples * 2)
  reaper.GetAudioAccessorSamples(track_accessor, SILENCE_SAMPLERATE, 2, pos, num_samples, buf)

  local peak = 0
  for i = 0, num_samples - 1 do
    local l = buf[i * 2 + 1] or 0
    local r = buf[i * 2 + 2] or 0
    local v = math.max(math.abs(l), math.abs(r))
    if v > peak then peak = v end
  end
  return peak
end

-- With a valid `track_accessor`, keeps/mutes/drops each segment based
-- on whether the sidechain track has energy above SIDECHAIN_THRESHOLD
-- at that segment's CURRENT position - called before shuffling/
-- reordering, while segments still sit at their original split
-- positions, so this reads the sidechain against the ORIGINAL timeline
-- (see APPENDIX (V3) notes up top). Returns `segments` unchanged if
-- `track_accessor` is nil (feature off, or no matching track found).
local function apply_sidechain(segments, track_accessor)
  if not track_accessor then return segments end

  local kept = {}
  for _, seg in ipairs(segments) do
    local pos = reaper.GetMediaItemInfo_Value(seg, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(seg, "D_LENGTH")
    local peak = accessor_peak_amplitude(track_accessor, pos, len)
    local hit = peak >= SIDECHAIN_THRESHOLD
    if SIDECHAIN_INVERT then hit = not hit end

    if hit then
      table.insert(kept, seg)
    elseif SIDECHAIN_DROP then
      local tr = reaper.GetMediaItem_Track(seg)
      reaper.DeleteTrackMediaItem(tr, seg)
    else
      reaper.SetMediaItemInfo_Value(seg, "B_MUTE", 1)
      table.insert(kept, seg)
    end
  end
  return kept
end

-- Shuffles `segments` and repositions them sequentially (gapless)
-- starting at `start_pos`, preserving each segment's own length.
-- Returns the new (shuffled) order.
-- Places `segments` sequentially (gapless) starting at `start_pos`,
-- preserving each one's own length, in whatever order they're given.
local function place_segments_sequentially(segments, start_pos)
  local pos = start_pos
  for _, seg in ipairs(segments) do
    local len = reaper.GetMediaItemInfo_Value(seg, "D_LENGTH")
    reaper.SetMediaItemInfo_Value(seg, "D_POSITION", pos)
    pos = pos + len
  end
end

-- Creates an independent duplicate of `seg`'s take (same source,
-- offset, playrate, pitch, volume, pan, length, mute state) on the
-- same track. Built manually with well-established item/take
-- functions rather than a native "duplicate" action, to avoid another
-- command-ID guess. Returns the new item, or nil if seg has no take.
local function duplicate_segment(seg)
  local take = reaper.GetActiveTake(seg)
  if not take then return nil end

  local track = reaper.GetMediaItem_Track(seg)
  local source = reaper.GetMediaItemTake_Source(take)

  local new_item = reaper.AddMediaItemToTrack(track)
  local new_take = reaper.AddTakeToMediaItem(new_item)
  reaper.SetMediaItemTake_Source(new_take, source)

  for _, prop in ipairs({ "D_STARTOFFS", "D_PLAYRATE", "D_PITCH", "D_VOL", "D_PAN" }) do
    reaper.SetMediaItemTakeInfo_Value(new_take, prop, reaper.GetMediaItemTakeInfo_Value(take, prop))
  end
  for _, prop in ipairs({ "D_LENGTH", "B_MUTE" }) do
    reaper.SetMediaItemInfo_Value(new_item, prop, reaper.GetMediaItemInfo_Value(seg, prop))
  end

  return new_item
end

-- Walks `order` and, for each segment, independently rolls a random
-- repeat count in [0, REPEAT_MAX] and inserts that many duplicates -
-- either immediately after the segment they're a copy of (Scatter
-- Repeats off, the original behavior), or at an independently-random
-- position anywhere in the growing result (Scatter Repeats on).
-- Either way, `order`'s own sequence - one instance of each segment,
-- in whatever order Shuffle Mode/Palindrome/etc already left them -
-- stays intact as the "spine"; Scatter Repeats only changes where the
-- EXTRA duplicate copies land, not the base ordering. Returns the
-- expanded list (same segments as `order`, interleaved with any
-- duplicates) - this is what actually gets sequentially placed, so
-- repeats naturally push everything after them later rather than
-- overlapping.
local function expand_with_repeats(order)
  if REPEAT_MAX <= 0 then return order end

  if not SCATTER_REPEATS then
    local expanded = {}
    for _, seg in ipairs(order) do
      table.insert(expanded, seg)
      local repeat_count = math.random(0, REPEAT_MAX)
      for _ = 1, repeat_count do
        local dup = duplicate_segment(seg)
        if dup then table.insert(expanded, dup) end
      end
    end
    return expanded
  end

  -- Scatter Repeats: start from the spine as-is, then insert every
  -- duplicate at a fresh random position within the list-so-far -
  -- recomputing the random insertion point after each one keeps later
  -- duplicates from being biased toward the end just because the list
  -- has grown.
  local expanded = {}
  for _, seg in ipairs(order) do
    table.insert(expanded, seg)
  end

  for _, seg in ipairs(order) do
    local repeat_count = math.random(0, REPEAT_MAX)
    for _ = 1, repeat_count do
      local dup = duplicate_segment(seg)
      if dup then
        local insert_pos = math.random(1, #expanded + 1)
        table.insert(expanded, insert_pos, dup)
      end
    end
  end
  return expanded
end

-- Palindrome mode (V3): appends a mirrored copy of `order` in reverse,
-- skipping the last element so the pivot segment doesn't repeat back-
-- to-back (A,B,C -> A,B,C,B,A) - the glued result plays forward then
-- backward. Mirrored-half segments are independent duplicates (via
-- duplicate_segment(), the same helper Number Of Repeats uses above),
-- so they still get their own independent randomization/reverse/mute
-- treatment in the per-segment loop that runs after this. Returns
-- `order` unchanged if PALINDROME_MODE is off.
local function apply_palindrome(order)
  if not PALINDROME_MODE then return order end
  if #order <= 1 then return order end

  local mirrored = {}
  for _, seg in ipairs(order) do table.insert(mirrored, seg) end
  for i = #order - 1, 1, -1 do
    local dup = duplicate_segment(order[i])
    if dup then table.insert(mirrored, dup) end
  end
  return mirrored
end

-- With MUTE_PROBABILITY% chance, mutes this chunk - it stays in its
-- slot (unlike silence filtering, which removes it) and contributes
-- silence when glued.
local function maybe_mute_segment(seg)
  if MUTE_PROBABILITY <= 0 then return end
  if math.random() * 100 >= MUTE_PROBABILITY then return end
  reaper.SetMediaItemInfo_Value(seg, "B_MUTE", 1)
end

-- Building block for every bipolar per-segment property: returns a
-- random value in [-1,1] ("both"), [-1,0] ("neg" - down/left/quieter/
-- earlier only), or [0,1] ("pos" - up/right/louder/later only).
-- Multiply by a property's magnitude to get the
-- actual applied offset.
local function directional_random(direction)
  if direction == "neg" then return -math.random()
  elseif direction == "pos" then return math.random()
  else return math.random() * 2 - 1
  end
end

-- Nudges a segment's already-placed position by +/- a random amount
-- up to POSITION_INTENSITY ms (constrained by Direction). Applied
-- AFTER the sequential reshuffle placement, as an extra layer of
-- jitter - can create overlaps or small gaps between segments, which
-- is expected/fine for this effect.
local function apply_position_jitter(seg)
  if POSITION_INTENSITY <= 0 then return end
  local offset = directional_random(POSITION_DIRECTION) * (POSITION_INTENSITY / 1000)
  local pos = reaper.GetMediaItemInfo_Value(seg, "D_POSITION")
  reaper.SetMediaItemInfo_Value(seg, "D_POSITION", math.max(0, pos + offset))
end

-- Scale-Quantized Pitch (V3): snaps `pitch` (in semitones, any real
-- number/octave) to the nearest semitone belonging to the chosen
-- scale (SCALE_ROOT + SCALE_TYPE's intervals, repeated every octave) -
-- searches one octave above/below the pitch's own octave to make sure
-- the true nearest scale tone is found even near an octave boundary.
local function quantize_to_scale(pitch)
  local scale = SCALES[SCALE_TYPE] or SCALES.major
  local base_octave = math.floor((pitch - SCALE_ROOT) / 12)

  local best, best_dist = pitch, math.huge
  for octave = base_octave - 1, base_octave + 1 do
    for _, interval in ipairs(scale) do
      local candidate = SCALE_ROOT + interval + octave * 12
      local dist = math.abs(candidate - pitch)
      if dist < best_dist then
        best_dist = dist
        best = candidate
      end
    end
  end
  return best
end

-- Per-segment stretch info, recorded by apply_stretch() so
-- randomize_segment_properties() can fold the stretch into its own
-- Rate/Pitch values instead of overwriting it: factor (length
-- multiplier), base_rate/base_pitch (take values before stretching),
-- resample (true if the take was NOT preserving pitch, i.e. its
-- playrate used to shift pitch too).
local stretch_info = {}

local function semitones_for_rate(rate)
  return 12 * math.log(rate) / math.log(2)
end

-- Writes a stretched segment's final playrate/pitch. Stretched takes
-- always run with preserve-pitch on, so the stretch itself never
-- changes pitch - and for takes that were NOT preserving pitch, the
-- pitch shift their `rate` would have caused through resampling is
-- added back explicitly, so Rate randomization keeps its usual
-- pitch-shifting character.
local function set_stretched_rate_pitch(take, info, rate, pitch)
  reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rate / info.factor)
  if info.resample then pitch = pitch + semitones_for_rate(rate) end
  reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", pitch)
end

-- Time-stretches each segment by a random amount up to
-- STRETCH_INTENSITY% (constrained by Direction): length is multiplied
-- by the factor and playrate divided by it, so the same slice of
-- source audio just plays over a longer/shorter span, with pitch
-- preserved. Must run BEFORE place_segments_sequentially() so the new
-- lengths lay out gapless.
local function apply_stretch(segments)
  if STRETCH_INTENSITY <= 0 then return end
  for _, seg in ipairs(segments) do
    local take = reaper.GetActiveTake(seg)
    if take then
      local pct = directional_random(STRETCH_DIRECTION) * STRETCH_INTENSITY
      local factor = pct >= 0 and (1 + pct / 100) or (1 / (1 - pct / 100))
      local info = {
        factor = factor,
        base_rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE"),
        base_pitch = reaper.GetMediaItemTakeInfo_Value(take, "D_PITCH"),
        resample = reaper.GetMediaItemTakeInfo_Value(take, "B_PPITCH") == 0,
      }
      stretch_info[seg] = info

      local len = reaper.GetMediaItemInfo_Value(seg, "D_LENGTH")
      reaper.SetMediaItemInfo_Value(seg, "D_LENGTH", len * factor)
      reaper.SetMediaItemTakeInfo_Value(take, "B_PPITCH", 1)
      set_stretched_rate_pitch(take, info, info.base_rate, info.base_pitch)
    end
  end
end

-- Randomizes one segment's take rate/pitch/pan/volume, each
-- independently, based on the *_INTENSITY settings above, with the
-- three fully-bipolar ones (Pitch/Pan/Volume) constrained by their own
-- Direction setting. A zero (or, for rate, 1x) intensity leaves that
-- property untouched entirely. Also applies the chosen pitch shift /
-- time stretch mode (PITCH_MODE), if one is set.
local function randomize_segment_properties(seg)
  local take = reaper.GetActiveTake(seg)
  if not take then return end

  if PITCH_MODE_RANDOM then
    reaper.SetMediaItemTakeInfo_Value(take, "I_PITCHMODE", PITCH_MODE_POOL[math.random(#PITCH_MODE_POOL)])
  elseif PITCH_MODE >= 0 then
    reaper.SetMediaItemTakeInfo_Value(take, "I_PITCHMODE", PITCH_MODE)
  end

  local info = stretch_info[seg]
  local rate, pitch

  if RATE_INTENSITY > 1 then
    rate = 1 + math.random() * (RATE_INTENSITY - 1)
  end

  -- Pitch/Pan/Volume are fully bipolar: at intensity X (and Direction
  -- = both), each segment gets a random value anywhere in [-X, +X] -
  -- the slider's own sign doesn't matter, only its magnitude does.
  if PITCH_INTENSITY ~= 0 then
    local magnitude = math.abs(PITCH_INTENSITY)
    pitch = directional_random(PITCH_DIRECTION) * magnitude
    if SCALE_QUANTIZE then pitch = quantize_to_scale(pitch) end
  end

  if info then
    if rate or pitch then
      set_stretched_rate_pitch(take, info, rate or info.base_rate, pitch or info.base_pitch)
    end
  else
    if rate then reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rate) end
    if pitch then reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", pitch) end
  end

  if PAN_INTENSITY ~= 0 then
    local magnitude = math.abs(PAN_INTENSITY)
    local pan = directional_random(PAN_DIRECTION) * (magnitude / 100) -- % -> REAPER's -1..1 range
    reaper.SetMediaItemTakeInfo_Value(take, "D_PAN", pan)
  end

  if VOLUME_INTENSITY ~= 0 then
    local magnitude = math.abs(VOLUME_INTENSITY)
    local db = directional_random(VOLUME_DIRECTION) * magnitude
    local linear = 10 ^ (db / 20) -- dB -> REAPER's linear D_VOL
    reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", linear)
  end
end

-- With REVERSE_PROBABILITY% chance, reverses this segment's take via
-- REAPER's native action (selects just this segment to apply it,
-- restoring nothing afterward since the caller re-selects for glue
-- right after anyway).
local function maybe_reverse_segment(seg)
  if REVERSE_PROBABILITY <= 0 then return end
  if math.random() * 100 >= REVERSE_PROBABILITY then return end
  reaper.SelectAllMediaItems(0, false)
  reaper.SetMediaItemSelected(seg, true)
  reaper.Main_OnCommand(REVERSE_COMMAND_ID, 0)
end

-- Selects exactly `segments` (nothing else), glues them via REAPER's
-- native action, and renames the resulting item's take
-- "Shredder_<n>" using the persistent counter. Returns the glued
-- item, or nil if gluing didn't leave anything selected.
local function glue_segments(segments, source_name)
  reaper.SelectAllMediaItems(0, false)
  for _, seg in ipairs(segments) do
    reaper.SetMediaItemSelected(seg, true)
  end

  reaper.Main_OnCommand(GLUE_COMMAND_ID, 0)

  local glued_item = reaper.GetSelectedMediaItem(0, 0)
  if glued_item then
    local take = reaper.GetActiveTake(glued_item)
    if take then
      reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", expand_render_name_pattern(source_name), true)
    end
  end

  return glued_item
end

-- Finds a group ID not currently used by any item in the project, so
-- a freshly-grouped set of segments never gets silently merged into
-- an unrelated existing group.
local function next_unused_group_id()
  local max_id = 0
  local count = reaper.CountMediaItems(0)
  for i = 0, count - 1 do
    local it = reaper.GetMediaItem(0, i)
    local gid = reaper.GetMediaItemInfo_Value(it, "I_GROUPID")
    if gid > max_id then max_id = gid end
  end
  return max_id + 1
end

-- Cut Only's alternative to glue_segments(): assigns `segments` a
-- fresh, unused I_GROUPID so they move together from here on. Nothing
-- else - no selection, no time range, no cursor move here. Those all
-- have to happen exactly ONCE, after EVERY originally-selected item
-- has been processed (main()'s existing "Select every result" block
-- below already does this correctly for glued results) - doing it
-- here too, per-item, was the actual bug: main() would immediately
-- overwrite it using only whatever finish_segments() returned, which
-- used to be a single arbitrary segment, not the full list, so the
-- final selection only ever covered the first item's first segment.
local function group_segments(segments)
  local group_id = next_unused_group_id()
  for _, seg in ipairs(segments) do
    reaper.SetMediaItemInfo_Value(seg, "I_GROUPID", group_id)
  end
  return segments
end

-- What actually runs after all cutting/shuffling/randomizing is done.
-- ALWAYS returns a list (possibly empty) of the resulting item(s) -
-- every segment with Cut Only on, or a single-element list holding
-- the glued item otherwise - so callers can treat both the same way:
-- collect everything every call returns, then select/range/cursor
-- over the full combined set exactly once. Both process_single_item()
-- and process_mashup() call this rather than glue_segments() directly.
local function finish_segments(segments, source_name)
  if CUT_ONLY then
    return group_segments(segments)
  end
  local glued = glue_segments(segments, source_name)
  return glued and { glued } or {}
end

-- Cuts, reshuffles, and finishes (glues, or groups with Cut Only on) a
-- single item in place. ALWAYS returns a list of the resulting
-- item(s) - empty if the item was too short, entirely silent (with
-- Ignore Silence on), or nothing survived sidechain filtering.
local function process_single_item(item)
  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

  -- Captured now, before any cutting - the original `item` reference
  -- doesn't reliably survive past split_item_into_segments(), so this
  -- is the only safe point to read its take name for {name}.
  local source_take = reaper.GetActiveTake(item)
  local source_name = source_take and reaper.GetTakeName(source_take) or nil

  local cut_positions = generate_cut_positions(item, item_pos, item_len)
  if #cut_positions == 0 then return {} end

  local segments = split_item_into_segments(item, cut_positions)
  segments = apply_structural_mutes(segments)
  segments = filter_silent_segments(segments)
  segments = filter_ordered_subset(segments)
  if #segments == 0 then return {} end

  local sidechain_accessor = open_sidechain_accessor()
  segments = apply_sidechain(segments, sidechain_accessor)
  if sidechain_accessor then reaper.DestroyAudioAccessor(sidechain_accessor) end
  if #segments == 0 then return {} end

  -- Ordered-Subset Mode always preserves order (it never shuffles);
  -- otherwise use whichever Shuffle Mode is active.
  local order = ORDERED_SUBSET_MODE and segments or apply_shuffle_mode(segments)
  order = expand_with_repeats(order)
  order = apply_palindrome(order)
  apply_stretch(order)
  place_segments_sequentially(order, item_pos)

  for _, seg in ipairs(order) do
    apply_position_jitter(seg)
    randomize_segment_properties(seg)
    maybe_reverse_segment(seg)
    maybe_mute_segment(seg)
  end
  return finish_segments(order, source_name)
end

-- Cuts every item in `items`, pools ALL resulting segments together,
-- moves them all onto one target track, shuffles, and finishes
-- (glues, or groups with Cut Only on) into a single combined result.
-- ALWAYS returns a list of the resulting item(s) - empty if nothing
-- survived filtering.
local function process_mashup(items)
  local target_track = reaper.GetMediaItem_Track(items[1])

  -- Multiple original items get pooled together in a mashup, so
  -- there's no single "correct" source name - the first selected
  -- item's take name is used for {name}, a reasonable default rather
  -- than trying to concatenate every item's name together.
  local source_take = reaper.GetActiveTake(items[1])
  local source_name = source_take and reaper.GetTakeName(source_take) or nil

  local start_pos = math.huge
  for _, item in ipairs(items) do
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    if pos < start_pos then start_pos = pos end
  end

  local all_segments = {}
  for _, item in ipairs(items) do
    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local cut_positions = generate_cut_positions(item, item_pos, item_len)
    local segments = split_item_into_segments(item, cut_positions)
    segments = apply_structural_mutes(segments)
    segments = filter_silent_segments(segments)
    segments = filter_ordered_subset(segments)
    for _, seg in ipairs(segments) do
      table.insert(all_segments, seg)
    end
  end

  if #all_segments == 0 then return {} end

  local sidechain_accessor = open_sidechain_accessor()
  all_segments = apply_sidechain(all_segments, sidechain_accessor)
  if sidechain_accessor then reaper.DestroyAudioAccessor(sidechain_accessor) end
  if #all_segments == 0 then return {} end

  -- Move every segment onto the target track BEFORE duplicating for
  -- repeats, so duplicates inherit the right track too.
  for _, seg in ipairs(all_segments) do
    if reaper.GetMediaItem_Track(seg) ~= target_track then
      reaper.MoveMediaItemToTrack(seg, target_track)
    end
  end

  -- Ordered-Subset Mode always preserves order (it never shuffles);
  -- otherwise use whichever Shuffle Mode is active.
  local order = ORDERED_SUBSET_MODE and all_segments or apply_shuffle_mode(all_segments)
  order = expand_with_repeats(order)
  order = apply_palindrome(order)
  apply_stretch(order)
  place_segments_sequentially(order, start_pos)

  for _, seg in ipairs(order) do
    apply_position_jitter(seg)
    randomize_segment_properties(seg)
    maybe_reverse_segment(seg)
    maybe_mute_segment(seg)
  end
  return finish_segments(order, source_name)
end

local function main()
  local num_items = reaper.CountSelectedMediaItems(0)
  if num_items == 0 then
    reaper.ShowMessageBox("Please select at least one item first.", "No item selected", 0)
    return
  end

  reaper.PreventUIRefresh(1)
  reaper.Undo_BeginBlock()

  -- Every result item from every originally-selected item processed,
  -- flattened into one list - process_single_item()/process_mashup()
  -- (via finish_segments()) always return a list now, never a single
  -- item, specifically so Cut Only's many segments-per-item and Glue's
  -- one-item-per-item both end up here the same way. This list is what
  -- the final select/range/cursor block below operates over.
  local result_items = {}

  local function collect(list)
    for _, it in ipairs(list) do table.insert(result_items, it) end
  end

  if num_items == 1 then
    local item = reaper.GetSelectedMediaItem(0, 0)
    local results = process_single_item(item)
    if #results > 0 then
      collect(results)
    else
      reaper.ShowConsoleMsg(
        "Shredder: item too short to cut, or entirely silent with Ignore Silence on - left untouched.\n")
    end
  else
    local items = {}
    for i = 0, num_items - 1 do
      table.insert(items, reaper.GetSelectedMediaItem(0, i))
    end

    if MASH_MULTIPLE_ITEMS_TOGETHER then
      local results = process_mashup(items)
      if #results > 0 then
        collect(results)
      else
        reaper.ShowConsoleMsg("Shredder: nothing left after silence filtering - nothing to glue.\n")
      end
    else
      -- Each item processed independently, staying separate.
      for _, item in ipairs(items) do
        collect(process_single_item(item))
      end
    end
  end

  -- Select every result item and set the time selection to their
  -- combined span, regardless of how many results there were (one
  -- glued item per originally-selected item, or - with Cut Only on -
  -- every individual segment from every originally-selected item).
  if #result_items > 0 then
    reaper.SelectAllMediaItems(0, false)
    local min_pos, max_end = math.huge, -math.huge
    for _, gi in ipairs(result_items) do
      reaper.SetMediaItemSelected(gi, true)
      local pos = reaper.GetMediaItemInfo_Value(gi, "D_POSITION")
      local len = reaper.GetMediaItemInfo_Value(gi, "D_LENGTH")
      if pos < min_pos then min_pos = pos end
      if pos + len > max_end then max_end = pos + len end
    end
    reaper.GetSet_LoopTimeRange(true, false, min_pos, max_end, false)
    reaper.SetEditCurPos(min_pos, false, false) -- move playhead to the start of the time selection
  end

  reaper.Undo_EndBlock("Antisample Shredder (random cut, reshuffle, glue)", -1)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
end

main()
