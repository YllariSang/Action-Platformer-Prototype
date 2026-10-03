# AGENTS.md

Conventions for working in this repository. Read this before making changes.

## This is a 2D game. It stays 2D.

**There is no 3D pivot, and there never will be.** The project is a 2D action
platformer built in Godot 4.7 with the 2D (Forward+) renderer. Do not:

- Suggest, plan, or begin a 3D port, "upgrade", or 3D rewrite
- Introduce `Node3D`, `MeshInstance3D`, `CharacterBody3D`, `Sprite3D`,
  `Camera3D`, `RigidBody3D`, or any 3D primitive
- Add 3D-only project settings, shaders, or navigation
- Use the terms "3D-ify", "upgrade to 3D", or "modernize to 3D" as future work

An earlier revision of `README.md` said the project might pivot to 3D. That
line is out of date and has been corrected. If you find yourself writing 3D
anywhere, you have misread the project. The only legitimate 3D-looking strings
in the repo are Godot resource UIDs that happen to contain "3d".

All gameplay is 2D: `CharacterBody2D`, `Area2D`, `Sprite2D`, `GPUParticles2D`,
`TileMapLayer`, `Camera2D`. Keep it that way.

## Assets: `icon.svg` is the placeholder, and real art is coming

`icon.svg` is currently the only image file in the repo, and every sprite,
particle, and texture reference points at it. That is a **placeholder state,
not a permanent rule.**

**The owner will supply real artwork once the mechanics and gameplay loop are
fleshed out and good.** Until that happens:

- Keep using `res://icon.svg` as the placeholder for any new visual
- Do not commit new image files, sprite sheets, or fonts before then
- Do not reference external or downloaded assets
- Distinguish entities visually with `modulate`, `scale`, `rotation`, `skew`,
  `flip_h`, or by composing existing nodes

When real art lands, the goal is that it is a **texture swap, not a code
change**. The feedback system was refactored specifically to make that true, so
preserve that separation:

- **Tints stay in the 0..1 range.** Use the named colour constants in
  `player.gd` (`CHARGE_TINT`, `VULNERABLE_TINT`, `DASH_TINT`) and in each
  enemy (`NORMAL_TINT`, `STUN_TINT`, `WARNING_TINT`, `PARRIED_TINT`). Values
  above 1.0 look fine on flat shapes and clip badly on real artwork.
- **Hit flashes go through `SpriteFeedback`, never `modulate`.** The old
  `sprite.modulate = Color(10, 10, 10)` trick only read correctly on flat
  placeholders. See "Feedback system" below.
- **Never bake state into a texture.** Stun, charge, telegraph, and hit
  reactions are all tint/flash driven so they survive an art swap.

```gdscript
# Correct: placeholder texture, tinted to tell entities apart.
@onready var sprite: Sprite2D = $Sprite2D
SpriteFeedback.set_tint(sprite, NORMAL_TINT)   # melee enemy: red
SpriteFeedback.flash(sprite, Color.WHITE, 1.0)  # on impact

# Wrong: an over-bright modulate that only looks right on a flat shape.
# sprite.modulate = Color(10, 10, 10)
```

## Feedback system: tint and flash are separate channels

`Scripts/sprite_feedback.gd` (`class_name SpriteFeedback`) plus
`Shaders/feedback_flash.gdshader` split visual feedback into two independent
channels that compose instead of fighting over `modulate`:

- **Tint** (`SpriteFeedback.set_tint`) — the entity's base state colour:
  stunned blue, charging cyan, boss state colours, dash translucency
- **Flash** (`SpriteFeedback.flash`) — a short impact/telegraph burst applied
  by the shader on top of whatever tint is underneath

This matters for the art swap: previously a hit flash overwrote the tint, so
shooting a stunned enemy made it stop looking stunned. Now a stunned enemy
stays blue while flashing white on impact.

```gdscript
func _ready() -> void:
    SpriteFeedback.attach(sprite)   # once, gives the sprite its own material

func take_damage(amount: int) -> void:
    SpriteFeedback.flash(sprite, Color.WHITE, 1.0, 0.1)
    # tint is left completely alone
```

`attach()` gives each sprite its **own** material instance, so one entity
flashing never affects another. It is idempotent, so it is safe to call
repeatedly.

To reset a sprite cleanly use `SpriteFeedback.clear(sprite)` (drops any running
flash) followed by `set_tint`. The player wraps this in `reset_player_tint()`;
prefer that over assigning `modulate` directly.

**Godot 4.7 note:** this build exposes the material property as `material`, not
`material_override`. Accessing `material_override` raises at runtime. The
helper uses `get("material")` / `set("material", ...)` deliberately.

## Audio

There is currently no audio in the project, and no `.ogg`/`.wav` files. If audio
is added, keep it minimal and treat any new sound as a placeholder.

## Project facts worth knowing

- **The boss re-stages itself between attacks, and that is what `TELEPORT` is
  for.** `State.TIRED` (the punish window) now resolves to `State.TELEPORT`, not
  straight back to `State.PATTERN`, giving the beat the header of `boss.gd`
  describes: attack, punish, reposition, attack. It used to go back to PATTERN
  every time, so `TELEPORT` was reachable only from the phase-two threshold and
  the boss held one spot for the entire fight — measured at 0px of movement and
  0.0 peak velocity across a 20s phase-one fight. That is not "hard", it is
  *stale*: a fixed origin means every pattern fires from the same point along the
  same angles forever, so the player memorises one safe column per pattern and
  then only has to stand still. The bullets were never the problem — an aimed
  shot hits at every range from 40px to 700px, including pressed against the
  boss, so do not go looking for a collision bug when a pattern "does not hit".
  `reposition_between_attacks` is an export because how often a set piece
  re-stages itself is a design call; turning it off restores the old behaviour.
- **`_apply_motion()` is a hook with no input, and that is deliberate.** It damps
  `velocity` toward zero and calls `move_and_slide()` when it is non-zero, but
  nothing in the project ever writes a non-zero velocity to the boss, so in the
  current fight it damps zero toward zero and never moves. It exists so a future
  charge or drift pattern can set `boss.velocity` and inherit the damping. The
  boss is a floating set piece by design: no gravity, because gravity would fight
  the teleport and pin the boss to whatever floor it was over. Repositioning is
  the teleport's job, not motion's.
- **A teleport target has to be clear of the boss's own body, not just inside the
  arena rect.** `ArenaBounds.random_point()` takes a `footprint` half-extent and
  rejects any candidate whose 3x3 sampled box touches a solid on layer 1. The
  arena rect only knows about the room, and every arena worth fighting in has
  ledges standing in it, so a point comfortably inside the rect can still be
  inside a ledge. Measured with a 160x160 boss over 400 random targets: **4% of
  teleports in the template arena and 11% in the main level landed in solid
  geometry** before this existed — a boss appearing embedded in a platform about
  once every twenty attacks. After: 0 in both, with the same query ignoring the
  footprint still returning 2% and 11% as a control. The boss passes
  `body_footprint()`, read off its real collision shapes, so resizing it in the
  inspector cannot silently bring the clipping back.
- **A bullet must never be born inside a wall.** The sweep's curtain columns are
  stacked back from the entry edge, and the leading one used to start
  `column_spacing * 0.5` *outside* the bounds, on the reasoning that a bullet
  flying in through the wall is a good telegraph. It is — for the trailing
  columns. The leading one is destroyed by the wall on its first physics frame
  (`_on_body_entered` sees a `TileMapLayer` and pops it), so a curtain thick
  enough to put its leading column outside the room fires a burst of explosions
  against the wall and no curtain at all. Columns now start *inside* the edge,
  so a thicker curtain gains depth without ever losing its leading edge.
- **The parry crunch is two stages, not one, and both are in real seconds.**
  `parry_crunch()` holds `parry_crush_scale` (0.02) for `parry_crush_hold` (0.05s,
  about three frames — the shortest stop that still reads as a stop) and then
  `parry_recover_scale` (0.35) for `parry_recover_time` (0.09s). A single hold
  that snaps to 1.0 reads as a stutter; one long hold reads as the game lagging.
  The ramp also puts the parry's own follow-through *inside* the frozen window,
  so the guard dropping, the sparks and the reflect read as one decisive moment
  rather than three things that happened to coincide. Two rules:
  - **The timers must pass `ignore_time_scale = true`.** That is the entire
    trick: 0.05s is 0.05s of wall clock however hard the world is slowed. A
    scaled timer measures the slowdown instead of the stop.
  - **The scale is 0.02, not 0.0.** A true zero makes delta-scaled tweens and
    particles produce NaN, and the difference is not visible.
  - It goes through `TimeControl.hold()` like every other slow-down, so a parry
    landing during the boss death cinematic does not cut the cinematic back to
    full speed early. Verified: a crunch over a `0.5` hold reaches 0.02 and
    settles back at exactly 0.5.
- **`main.tscn`'s boss fight happens somewhere its `Arena` does not describe, and
  that is measured, not assumed.** The arena rect is x 325..1272, y -937..-600.
  The player spawns at (0, 0) and is **outside** it. The nearest standable
  surface to the boss at (801, -896) is the ceiling slab at y = -1216, 320px away,
  with the player hanging 384px *above* the boss's head. The player climbs a
  route of ledges at y = 32, -208, -384 and never enters the rect. So:
  - **The sweep cannot hit anything in this level, and that is not a sweep bug.**
    The curtain's lanes are derived from the arena, and the arena is not where the
    fight is. It is a correct pattern pointed at the wrong rectangle. Its own
    `begin()` now pushes a warning naming both the lane span and the player's
    actual position when nothing comes near, so this class of silence is loud.
  - **The camera does not claim the arena here.** `_claim_camera()` checks
    `bounds_node.rect().has_point(player_position())` and leaves the camera on the
    player when it fails, because framing a rect that contains neither the player
    nor anything they can stand on plays the fight off the bottom of the screen.
    In `boss_arena.tscn` the check passes and the camera frames the room as
    asked.
  - **The `Arena` node in `main.tscn` is stale and is left alone on purpose.** It
    is a one-number fix (`position` / `size`) that only the owner can make,
    because only they know where the fight is meant to happen. Everything that
    reads it is now guarded, so a wrong rect is a missed opportunity rather than
    a broken fight.
  - **Do not rebuild hand-authored level geometry.** An earlier pass read a
    "topmost solid cell per column" summary as "the level has no floor east of
    x = 16", erased 1,479 cells, and replaced the platforming with flat
    `platform.tscn` boxes. The level was not empty and the tilemap is the design.
    `platform.tscn` is for throwaway rigs, which is what `boss_arena.tscn` is. A
    single topmost-cell summary cannot tell a floor from a ceiling; dump *every*
    run per column before concluding anything about a level's shape.
- **The trigger in `main.tscn` resolves to x -40..5, y -5417..-5199** — a tall
  thin column far above the ground floor, sitting on the route up to the boss. It
  is a route trigger, not a doorway. Before concluding a trigger is misplaced,
  work out what its shape resolves to in world space (position + offset × scale ×
  size); the authored numbers do not look like a box on the floor and are not
  meant to be.
- **The sweep's lanes are anchored to the floor, not divided across the arena.**
  Lane 0 sits `floor_lane_inset` (34px) above the arena's bottom edge and the rest
  stack upward at `lane_target` (100px). Dividing the arena's height into equal
  lanes was the original approach and it is wrong in a way that is invisible from
  the outside: on a 337px arena it put the lanes at y = -881, -768 and -656 while
  a player standing on the level's floor occupies y = -64..32, so the nearest lane
  was **624px away** and the pattern could not hit anyone. Anchoring the lowest
  lane to the floor fixes it structurally — `_lane_y(0)` is now within 2px of a
  grounded player in `boss_arena.tscn`.
  - **The gap may sit on the floor lane.** An earlier version biased it away from
    the bottom edge on the reasoning that a gap near the floor was uninteresting,
    which removed the only lane that can reach a grounded player on some room
    sizes. The gap is a safe column wherever the pattern puts it.
  - **Test a curtain with two controls in the same trial shape:** the player
    stands in the gap (must survive) and stands two lanes up with the gap pinned
    low (must be hit). "The player survived" alone passes for a pattern that
    fires nothing. Pin `_gap_start` and `_from_left` *every frame* — `_pick_gap()`
    runs after each curtain, so a gap pinned once is re-randomised by the second
    one. Give the pattern a long `duration` so it is not retired mid-trial, and
    clear `is_dead` between trials: 5 HP plus a 1s invulnerability window means
    several curtains kill the player, and a corpse takes no damage, which reads as
    "the curtain missed" when it actually landed five times.
  - `gap_size` is a pixel budget, not a lane count, so the hole stays the same
    physical size in any room. Two to three player heights is findable and still a
    commitment.
- **A bullet's `lifetime` must be set before it enters the tree.**
  `enemy_bullet._ready()` reads `lifetime` to start its self-destruct timer, so
  assigning it after `add_child` sets it *after* the 5s default is already
  committed and the range silently becomes the default. Measured: the shotgun's
  pellets travelled 778px instead of the ~200px `pellet_lifetime` asks for.
  `_place_bullet()` now configures speed, lifetime, direction and rotation on the
  instance and only then adds it, which is the same discipline as measuring the
  muzzle offset off the instance before placing it.
- **The camera's zoom is composed from three independent pieces, never assigned.**
  `_rest_zoom` (authored) × `_frame_zoom` (boss-fight framing) × `_heal_zoom`
  (heal push-in), summed by `_refresh_zoom_target()`. Writing `_zoom_target`
  directly from two features is how the heal focus and the fight framing would
  end up fighting, with whichever ran last winning. `frame_rect()` clamps to
  never zoom *in* past the authored framing, because a room smaller than the
  screen should be fully visible with its surroundings still in shot, not blown
  up to fill the frame. Note `Camera2D.zoom` is a scale where the visible world
  size is `viewport / zoom`, so fitting a rect means going *down* to
  `viewport / rect` — the opposite of the instinct.
- **The boss holds the camera on the arena for the whole fight**
  (`hold_camera_on_arena`). `_intro()` used to call `return_to_player()` 1.4s in,
  which framed the fight on wherever the player happened to be standing — and
  every attack here is an *area* attack, with teleports ranging across the arena
  and a curtain crossing all of it, so a camera on the player is a camera
  pointed at a fraction of the threats. `_claim_camera()` takes it in the intro
  and `_release_camera()` gives it back at the end of the death cinematic, which
  also clears the framing. Fall back to targeting the boss when there is no
  arena: framing the boss's own 160x160 box would zoom in on a dot.
- **The shotgun is a wide close-range cone, not a bullet that expires.**
  `pellet_lifetime = 0.42` was an attempt to give it range by making its pellets
  evaporate, and it reads badly: bullets visibly stop dead in mid-air, which looks
  like a bug rather than a weapon. Prefer expressing a weapon's character in its
  spread, pellet count and speed, and letting bullets live their normal 5s. It
  fires 3 blasts of 9 pellets across ~63 degrees, re-aiming on each blast, so
  standing next to the boss doing nothing is the losing state it punishes. If a
  range limit is wanted later, make it a much larger `lifetime` and check how it
  looks, not a value small enough to be seen dying.
- **The sweep is a left-to-right curtain, and it used to be a wall that could
  not reach anyone.** It laid columns standing still at the arena's *vertical
  midpoint* with every bullet travelling `Vector2.UP`. A player on the floor is
  below that wall and it only moves further away, so the only player it could
  hit was one who had climbed above mid-height — the last place anyone wants to
  be. That is why it read as useless rather than merely easy. It is now a
  full-height curtain that enters from one side and crosses to the other with a
  contiguous gap left in it, and the side alternates so the player is pinched
  rather than herded. Three things are load-bearing:
  - **The gap is what makes it readable.** It is ~2 lanes of ~100px against a
    64px-tall player, so it can be found and stood in. Verified both ways with
    the player pinned to one lane and one curtain at a time: 6 damage taken
    across 3 curtains held in the floor lane with the gap elsewhere, 0 damage
    held in the gap. Without that control, "the player survived" proves nothing.
  - **The lanes must reach the floor.** A player standing on the ground has
    their body between y = -64 and y = 0, so the lowest lane has to sit near
    -50. A curtain that stops at mid-height is the old bug wearing a new shape,
    and in `main.tscn` it was literally that: the arena's bottom edge was 600px
    above the floor. Read the lane layout off the pattern's own `_lanes` /
    `_spacing` / `_gap` rather than sampling bullets in flight, since half a
    curtain is still outside the arena a few frames after it fires.
  - **Columns are stacked back from the entry edge, outside the arena**, so the
    curtain arrives as a wall and flying in through the wall is the clearest
    possible telegraph. Do not spread them across the room: they would appear
    already spread out instead of arriving.
  - Test a sweep by pinning `sweep_interval` high and holding the player at a
    fixed y. Also beware that an invulnerable player reads as never hit, since
    `take_damage` returns early without touching `hp` — count damage, do not
    watch for a boolean.
- **The fight is tuned fast on purpose; the numbers are in one place.** Measured
  before the pass: one attack every 6.8s, 2.7 bullets a second, 400px/s, which
  is slow enough to memorise an answer rather than read one. After: one attack
  every 4.0s, ~4.6 bullets a second, ~750px/s. Two numbers are deliberate floors
  rather than leftovers, so do not "finish" the speedup by cutting them:
  - **`tired_time` is 1.15s because the player's parry cycle is 1.0s**
    (`parry_duration + parry_cooldown`). The punish window has to fit a second
    parry, otherwise a parry that reflects a bullet is followed by no time to
    spend the Sparks it paid for and the reward disappears.
  - **`bullet_speed_mult` is 1.45 because the player moves at 300 and dashes at
    1000.** Faster bullets stop being readable; past this they stop being a
    dodge test and start being a coin flip. Phase two multiplies by 1.25 on top.
- **`BossPattern._fire()`'s second argument is a multiplier, and it defaults to
  1.0 for that reason.** It used to default to `0.0`, which read as
  "unspecified" and silently meant `bullet.speed * bullet_speed_mult * 0.0` — a
  stationary bullet. Every pattern that calls `_fire(direction)` was affected, so
  the spiral, the fan and the volley all dropped their bullets at the boss's feet
  and they sat there in a slowly growing ring for the full 5s lifetime, looking
  like decoration and impossible to parry or dodge. Measured: 0px of travel in
  half a second for those three, against 200px for the sweep, which was fine only
  because it calls `spawn_bullet_at` directly and never went through `_fire`. The
  parameter is named `speed_mult` so the multiplication is not a surprise, and
  `_place_bullet` pushes a warning on a non-positive speed, because a frozen
  bullet otherwise fails completely silently.
- **Boss bullets are born outside the boss, and the offset is measured, not
  guessed.** `spawn_bullet()` places a bullet at `global_position + dir *
  (muzzle_distance(dir) + shape_reach(bullet, dir))`. It used to place it at
  `global_position`, which is the middle of a 160x160 collision shape sitting
  under a 192px sprite: measured, 0px of clearance in every direction against 80px
  of body and ~96px of sprite, so every shot spent its first fifth of a second
  travelling under the boss's own sprite and a spiral read as a clump growing out
  of its chest. Three rules keep it fixed:
  - **Both shapes are measured, and the bullet is instantiated before it is
    placed**, because the muzzle has to clear the bullet's radius too. Reaching
    only as far as the boss's own edge still overlaps.
  - **The clearance must include the bullet.** An `Area2D` reports a given body
    exactly once, so a bullet born overlapping its own boss permanently disowns
    that pair: the player could reflect the shot and it sailed straight back
    through the boss that fired it, which measured as the boss sitting on
    500/500. Do not "fix" the visual by offsetting to the boss's edge only.
  - **`spawn_bullet_at()` is deliberately *not* offset.** The sweep pattern fires
    a wall across the arena from world points it chose, where the boss has
    nothing to do with. Offsetting that path would leave a hole at one end of
    every wall. Rectangles are measured by their support function along `dir`, not
    by a bounding circle, so a diagonal shot is not pushed out to a corner
    distance and read as a wider gap than a horizontal one.
- **A boss is a list of attack patterns, not a state machine.** `boss.gd` knows
  about pacing and nothing about attacks. Every attack is a `BossPattern` scene
  under `Scripts/patterns/` with a `duration`, a `weight`, a `phase`, a `tint`,
  and a `tick(delta)`. The boss instantiates one per use, drives it, and stops
  it. The prototype instead hardcoded `INTRO / IDLE / SPIRAL / SHOTGUN / TIRED
  / TELEPORT / DYING` in one function and chose between its two attacks with
  `randi() % 2`; adding an attack there meant adding a branch to a 250-line
  file, and a coin flip has no rhythm. Four things are load-bearing:
  - **Selection is a weighted pool that will not repeat back to back.** See
    `_pick_pattern()`. A fight is memorable because of the *order* its attacks
    arrive in, so `weight` and the no-repeat rule are the design knobs, not a
    starting point to replace with `randi()`.
  - **`phase = 2` patterns are added to phase 1, never swapped in for them.**
    Phase two only speeds things up (`bullet_speed_mult`, each pattern's
    `phase_two_*` value) and repositions the boss.
  - **Patterns are driven, never self-ticking.** `begin` / `tick` / `end` are
    called by the boss. A pattern with its own `_physics_process` would keep
    firing through a phase change, through the boss dying, and through the
    player dying. `end()` is the only place a pattern cleans up, so anything it
    starts that the boss will not tear down belongs there.
  - **`elapsed` accumulates the scaled physics delta**, so a pattern slows
    inside a parry hit-stop along with the world. The prototype's spiral fired
    on `Engine.get_physics_frames() % 5`, which is a wall-clock timer, so it
    spat bullets into a screen that had nearly stopped.
- **The arena owns its own bounds.** A boss reads an `ArenaBounds` node named
  `Arena` (`Scripts/arena_bounds.gd`) instead of four
  `limit_left/right/top/bottom` exports. One exported size positioned by a node
  cannot disagree with itself, and the arena can move without touching the boss.
  `random_point(avoid, clearance)` is what stops a teleport landing the boss
  inside the player.
- **`_set_state()` ignores a request for the state it is already in**, and the
  check happens *before* the assignment, because after it the two are
  indistinguishable. That is what stops a second teleport starting while one is
  in flight, which would leave two fade tweens fighting over one sprite's alpha.
  The consequence to remember: `_ready()` cannot call
  `_set_state(State.INACTIVE)`, because `current_state` is already `INACTIVE`
  from its member initialiser and the call would silently do nothing. The
  dormant presentation is applied directly there instead.
- **The template areas use `Scripts/platform.gd`, not a TileMapLayer.** Size is
  an export and the collision shape is built in `_ready()`, so one scene is
  instanced at any size from a property. Hand-authoring TileSet collision for a
  rig that gets reshaped while tuning is not worth it; the production level
  still uses its TileMapLayer.
- **The melee enemy will not dash at a player it cannot reach.** The dash
  triggers on the straight-line distance and a `dash_vertical_range` tolerance,
  not on the x-only distance the chase uses. The x-only version treated a player
  standing on the platform directly above as valid, so the enemy telegraphed,
  dashed, and hit nothing — which reads as the attack bugging out rather than
  the player having evaded it.
- **Godot 4.7**, not 4.5. The README previously said 4.5; that was wrong.
  `TileMapLayer` moved `collision_layer`/`collision_mask` onto the `TileSet` in
  4.7, and collision layers now live in the `TileSet` sub-resource of
  `main.tscn` as `physics_layer_0/collision_layer`. Do not "fix" TileMapLayer
  collision by adding those properties back to the node; they do not exist.
- **Everything still shares collision layer 1 / mask 1.** Damage targeting uses
  `body.name == "Player"` in four scripts (`bullet.gd`, `enemy_bullet.gd`,
  `railgun_bullet.gd`, `boss_trigger.gd`). Renaming the `Player` node silently
  breaks damage. Proper layer separation is known future work.
- **`TimeControl` is an autoload** (`Scripts/time_control.gd`) and is the single
  owner of `Engine.time_scale`. Never assign `Engine.time_scale` directly.
  Use `var token = TimeControl.hold(scale)` and `TimeControl.release(token)`.
  Direct assignment is what previously let a parry hit-stop cancel the boss
  death cinematic's slow motion.
- **`result_screen`** is found via the `"result_screen"` group and has a
  `show_result(won: bool)` method. Both the boss (win) and the player (death)
  call it. It was formerly `win_screen` / `show_win()`; if you see that name in
  older notes, it is stale. **`show_result()` pauses the tree**, so the result
  panel does not fade in over a live fight (enemies chasing a corpse, bullets
  in flight, camera shaking behind the dim). The screen therefore sets its own
  `process_mode` to `PROCESS_MODE_WHEN_PAUSED` in `_ready()`: without that, the
  node inherits `PAUSABLE`, stops receiving `_unhandled_input`, and stops
  running its fade tween the instant the pause lands, leaving a half-transparent
  panel with an unreachable restart button. `_on_restart_pressed()` already
  unpauses and calls `TimeControl.reset()`.
- **Player has 5 HP and no passive regeneration.** `heal_cost = 2` Sparks.
  Invulnerability window after a hit, dash i-frames, and double damage during
  parry recovery are all intentional.
- **The player has exactly one uncommitted state, and movement is not one of
  them.** `try_to_parry()` and `try_to_heal()` accept only `State.IDLE`; every
  other state is something the player has already paid time for (shot recovery,
  the parry itself, recovery penalty, heal channel). Two states were removed
  from the enum as dead code: `RUN`, which nothing ever assigned even though two
  guards tested for it (so "parry while moving" silently meant "parry while
  standing still" — it works anyway, because the parry zeroes velocity on the
  next line), and `STUNNED`, whose `_physics_process` early return would have
  frozen the player permanently the day a stun feature was added it. Do not
  reintroduce a movement state: `handle_movement_and_jumps()` also runs during
  `ATTACK`, so a state written from it would clobber the shot recovery, and it is
  skipped entirely during `PARRY`/`DASH`, so those are the states that have to
  decide whether the player may act.
- **Assign an entity's HP in `_ready()`, never in a member initializer.**
  `var hp = max_hp` runs while the object is being constructed, which is
  *before* the scene's stored property values are applied, so it always
  resolved to the script's default and silently discarded any per-instance
  `max_hp` set in the inspector. `flying_enemy.gd` did exactly this and a flier
  with `max_hp = 99` came up with 20 HP.
- **Damage is measured in hearts, not in arbitrary numbers.** `take_damage()`
  does `hp = max(hp - amount, 0)` and does not clamp to a single heart, so an
  enemy `damage` above `max_hp` is an instant kill at any health. `melee_enemy`
  was 10 and killed the player outright at both 3 HP and 5 HP; it is now 2,
  matching `enemy_bullet.gd`'s 1. Any new damage source must be added in the
  same unit, or the healing and double-damage rules stop making sense.
- **Healing is a channel, not a tap, and that is load-bearing.** `try_to_heal()`
  starts a `State.HEALING` channel that roots the player for `heal_duration` and
  blocks parry, dash, and shooting. It was previously an instant 1 HP for
  `heal_cost` Sparks with no state guard at all, which was the same price as a
  successful parry with no timing to get right — the parry became optional.
  Five rules keep it honest, and all five are load-bearing:
  - Sparks are charged in `_finish_heal()`, not on press, so a cancelled
    channel costs only time and exposure. There is no refund path to get wrong.
  - `cancel_heal()` sets `_heal_locked`, and the poll in `_physics_process`
    refuses to start while it is set. Without the latch the poll restarts the
    channel the very next frame, so a cancel was a no-op: nudging the stick
    made the player jitter, and a hit was followed instantly by a fresh channel
    that the granted i-frames made free. The key must be released first.
  - `take_damage()` calls `cancel_heal()`. Being hit interrupts a heal, so
    healing is something you find an opening for.
  - The channel steps with `1.0 / Engine.physics_ticks_per_second`, **not**
    `get_physics_process_delta_time()`. The coroutine resumes from the
    `physics_frame` signal rather than from `_physics_process`, and the delta is
    not readable in that context, so it returns 0 and the channel never finishes.
  - **Only a *fresh* direction press cancels, and only from the channel's second
    frame on.** The loop tests `Input.is_action_just_pressed("left"/"right")`,
    not the held axis, and a `can_steer` flag stays false until after the first
    `await`. `HEALING` already roots the player, so a direction the player was
    holding when they pressed `Q` is simply overridden. This was
    `Input.get_axis("left", "right") != 0.0`, which meant the one moment a heal
    is most tempting — mid-run, in the open — was the one moment it could not
    start; the channel began and cancelled on its own first frame, so `Q` did
    nothing at all while walking. The grace frame is what keeps pressing a
    direction and `Q` on the same tick from cancelling a channel born that tick.
- **A refusal to heal latches `_heal_locked` too.** The "HP FULL" and
  "NEED n SPARKS!" early returns in `try_to_heal()` set the latch, for the same
  reason `cancel_heal()` does: the function is polled from `_physics_process`
  every frame the key is down, so an unlatched `return` re-entered on the next
  frame and stacked a popup per physics tick — 45 identical "HP FULL" popups
  over three quarters of a second, measured. The prompt is a reason, not a
  per-frame readout; the key has to be released to ask again.
- **A heal requires ground, and that is the same rule from the other side.** The
  channel's entire cost is that it roots the player somewhere they were going to
  be shot at. `HEALING` already zeroes `velocity.x` and gravity runs regardless,
  so an airborne channel costs nothing the player still had, and 2 Sparks bought
  1 HP on the way down past anything — measured, before the guard: a heal
  started at 4000px up completed for 1 HP and 2 Sparks. In a platformer you are
  airborne constantly, so allowing it also deleted the "find an opening" decision
  the mechanic exists for. The `is_on_floor()` guard sits *before* the
  `current_state != State.IDLE` gate, so pressing `Q` in the air gets a
  "LAND FIRST" reason rather than silence, and it latches like the other two
  refusals so a held key prints it once.
- **The dash has a cooldown, and `can_dash` is only ever handed back through
  `refresh_dash_charge()`.** There are three places that used to write
  `can_dash = true` (floor contact, wall slide, wall jump) and all three now call
  the helper, which refuses while `_dash_cooldown_left > 0` and while the state is
  already `DASH`. Both halves are load-bearing, and the second one is not
  obvious: **a ground dash never leaves the floor**, because `DASH` skips gravity
  and zeroes `velocity.y`, so `is_on_floor()` stays true for the whole 0.2s.
  Re-granting on contact therefore un-spent the dash mid-flight, and since the
  press is read as `is_action_just_pressed` a player leaning on the key could
  restart the dash forever without ever leaving the ground — measured at 1517px
  of travel in 1.5s of mashing, against 600px (three dashes) with the cooldown.
  Do not reinstate a bare `can_dash = true`. Counting entries into `State.DASH`
  cannot detect this bug, because a restart never leaves the state; measure
  distance travelled instead.
- **`dash_cooldown` runs from the start of the dash, not the end.** The dash
  itself lasts `DashTimer`'s 0.2s, so the gap the player actually feels is
  `dash_cooldown - 0.2`. It is a plain countdown in `_physics_process` rather
  than a `Timer` node because it gates one boolean and has to be readable
  synchronously by the contact check in the same function. The air dash is
  untouched: one per fall, plus one per wall contact, both now rate-limited.
- **`parry_box.monitoring` / `monitorable` are set with `set_deferred()` in
  `die()`.** A lethal bullet hit arrives inside `enemy_bullet.gd`'s
  `_on_body_entered`, and Godot refuses to change an area's monitoring state
  from inside a physics signal callback. Assigning directly raised "Function
  blocked during in/out signal" on every death and left the box monitorable.
  Same reason a successful parry drops the box deferred.
- **A hold repeats a completed heal.** Finishing a channel does not set
  `_heal_locked`, so keeping `Q` down starts the next one. That is intentional —
  the 0.6s commitment is the cost, not the first press — but it means the HUD
  hint and the `heal_fire` progress fill are re-armed immediately on success.
- **`railgun_bullet.gd` pierces through `pierce_count` targets, and the dedup is
  on the resolved victim, not the collider.** An enemy usually has a body *and* a
  child hurtbox overlapping (the melee enemy's `Hitbox` is exactly that), and
  both paths resolve to the same enemy. Keying `_hit_targets` on the collider
  instead of the victim let one enemy eat two pierces, so the budget lied. Walls
  still stop the shot, unlike enemies.
- **An open parry is a hard immunity, and the gate is `player.is_parrying()`.**
  `take_damage()` refuses damage whenever it returns true, and the two damage
  sources (`melee_enemy.gd`'s hitbox, `enemy_bullet.gd`'s `_on_body_entered`)
  bail out early too. Do not reduce that to `current_state == State.PARRY`
  alone: a successful parry drops the box with `set_deferred()` and moves to
  `IDLE` immediately, so an already-overlapping hitbox reports its body entry
  later in that same frame and used to land the hit *after* the player had
  parried it. Polling `parry_box.monitoring` as well keeps the parry
  authoritative for the frame it resolves in.
- **`enemy_bullet.gd` must not `queue_free()` itself on a parrying player.** It
  returns instead, so the bullet stays alive and the directional parry box can
  still reflect it a frame later. Consuming it there ate the reflect.
- **Regular enemies are leashed by `aggro_range`; the boss is not.** Past the
  leash they stop chasing, stop shooting, drop the hitbox, tint out to
  `IDLE_TINT`, and walk home. A telegraphed dash (`PREPARE`) *is* cancelled by
  breaking the leash; a committed dash (`DASH`) is not, or retreating from an
  attack in flight would be a free escape. Every tint write in
  `melee_enemy.gd` and `flying_enemy.gd` goes through `_apply_tint()` — writing
  `sprite.modulate` directly desyncs the cached `_applied_tint` and leaves the
  enemy stuck in the wrong colour. Walking home scales speed with the remaining
  distance: at a fixed walk speed the enemy overshoots its arrival radius,
  reverses, and jitters on the spot forever.
- **The HUD is screen-space, not on the player.** It lives under
  `Player/UI` (a `CanvasLayer`) as `UI/HudRoot/LeftColumn`, with
  `HealthRow` above and a `SparkBlock` holding the label and `SparkRow`
  side by side. Pips are built in code by `rebuild_hud()` from `max_hp` /
  `max_ammo`, so changing those in the inspector just works — do not
  hardcode pip counts or add them to the scene. The old
  `Sprite2D/SkewContainer` is gone. `UI/HealFlash` is also a child of `UI`,
  not of the HUD root: it is the full-screen white rect that punctuates a heal
  releasing, so it has to sit above `HudRoot` in draw order. It carries
  `mouse_filter = 2` (IGNORE) so it cannot eat the mouse the player aims with.
- **The camera zooms for a heal, and the release is where it flashes.**
  `camera.gd` holds `_rest_zoom` (whatever zoom the scene authored, captured in
  `_ready()`, so a designer can set zoom in the inspector without having to keep
  an export in sync) and walks `zoom` toward `_rest_zoom * heal_zoom_mult`. The
  walk uses `1.0 - exp(-zoom_speed * delta)`, not the `lerp(a, b, speed * delta)`
  form the pan above uses — that one is frame-rate dependent, so the zoom would
  cover less ground at 144Hz than at 60Hz. `heal_zoom_mult` is a multiplier, not
  an absolute `Vector2`, so it composes with the authored zoom instead of
  overwriting it. The flash lives with the player rather than the camera because
  a `Camera2D` is not a `CanvasLayer` and cannot host a viewport-sized overlay
  itself. **A channel has exactly two exits, `_finish_heal()` and
  `cancel_heal()`, and those are the only two places that release the focus.**
  Do not add a release to `die()`: a lethal hit always arrives through
  `take_damage()`, which calls `cancel_heal()` while the state is still
  `HEALING`, so the focus is already on its way out and a second release would
  be an unreachable path that reads as if death had its own special case. That
  also means an interrupted channel flashes, lethal or not, which is
  consistent — the flash marks "the channel ended" and nothing else.
- **Do not tween a `Container` child's `position`.** Containers rewrite child
  positions on every layout pass, so the tween snaps back. `shake_ui()`
  shakes `hud_column` (a child of the plain `HudRoot` `Control`) instead.
- **Shake offsets must return to `hud_rest_pos`, not to the live position.**
  That value is captured once after the first layout pass in `_ready()`
  (awaiting two `process_frame`s, because Containers have not laid out yet).
  Capturing "rest" at the start of each shake compounds the error: an
  interrupted shake leaves the column displaced, the next shake treats that
  displaced value as rest, and the HUD creeps across the screen. `_hud_shake_tween`
  is killed and the position hard-reset at the start of every shake, because a
  killed tween never runs its own restore step.
- **Tuning values are `@export`ed** on purpose. `recoil_force`,
  `recoil_duration`, `max_hp`, `invuln_time`, `heal_cost`, the enemy
  durations, and the aggro leash values are all inspector-tunable. Prefer
  adjusting an export over hardcoding a value in logic.

## Conventions

- GDScript with tabs, `_ready()` lifecycle, snake_case functions
- `@export` for anything a designer might want to tune
- Group-based lookups (`add_to_group` / `get_first_node_in_group`) over
  hardcoded node paths where practical
- Signal connections live in `.tscn` files when possible. If a script also
  connects the same signal, guard it with `is_connected()` — Godot raises
  "Signal is already connected" otherwise
- Comment *why*, not *what*. Explain the bug a workaround avoids so the next
  person does not undo it

## Before you finish

Run the project headless and confirm it is clean:

```sh
godot --headless --quit-after 300
```

Any `ERROR`, `WARNING`, or `SCRIPT ERROR` in that output is a regression.
Prefer measuring behaviour over asserting it: write a temporary scene that
instantiates `res://Scenes/main.tscn` and asserts on real values, then delete
it. Do not leave test scaffolding in the repo.
