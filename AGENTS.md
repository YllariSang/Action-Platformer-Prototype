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
  older notes, it is stale.
- **Player has 3 HP and no passive regeneration.** `heal_cost = 2` Sparks.
  Invulnerability window after a hit, dash i-frames, and double damage during
  parry recovery are all intentional.
- **The HUD is screen-space, not on the player.** It lives under
  `Player/UI` (a `CanvasLayer`) as `UI/HudRoot/LeftColumn`, with
  `HealthRow` above and a `SparkBlock` holding the label and `SparkRow`
  side by side. Pips are built in code by `rebuild_hud()` from `max_hp` /
  `max_ammo`, so changing those in the inspector just works — do not
  hardcode pip counts or add them to the scene. The old
  `Sprite2D/SkewContainer` is gone.
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
  `recoil_duration`, `max_hp`, `invuln_time`, `heal_cost`, and the enemy
  durations are all inspector-tunable. Prefer adjusting an export over
  hardcoding a value in logic.

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
