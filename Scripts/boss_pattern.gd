class_name BossPattern
extends Node2D

## One boss attack, as a self-contained scene the boss instantiates per use.
##
## Patterns exist so that a boss is a *list of attacks* rather than a `match`
## statement. The prototype boss chose between two hardcoded states with
## `randi() % 2`, which meant a new attack was a new branch inside one
## 250-line function, and the fight had no rhythm at all — a coin flip is not a
## sequence. With patterns, a new attack is a new file, a boss is a list of
## them, and the boss's identity is which patterns it draws from and in what
## order.
##
## Lifecycle, driven by the boss rather than by `_process`:
##
##     begin(boss)  ->  tick(delta) ...  ->  end()
##
## `begin` and `end` are each called exactly once. `tick` is called once per
## physics frame while active and not after `end`. Driving it explicitly rather
## than letting patterns use `_physics_process` is what makes a pattern
## interruptible: the boss stops a pattern on a phase change, on death, and on
## the player dying, and a pattern that owned its own process loop would keep
## firing through all three.

## How long this pattern runs before the boss moves on. Zero or less means it
## only ends when something stops it, which is what a charge or a beam wants.
@export var duration: float = 3.0

## Relative likelihood of being picked once phase and no-repeat filtering are
## done. Weights are relative, not percentages, so [1, 4] is a 1-in-5.
@export var weight: float = 1.0

## 1 = available from the start. 2 = only once the phase-two threshold is
## crossed. A phase-2 pattern is in addition to phase 1, never instead of it.
@export var phase: int = 1

## Boss tint while this pattern runs, so the player can read what is coming
## before it arrives. Kept in 0..1 for the same reason the entity tints are.
@export var tint: Color = Color(1, 1, 1)

## Selection preferences. These do not hard-code attacks into the boss: they
## let each pattern describe the situation where it is most interesting. A
## shotgun should be common up close, for example, without disappearing from
## the fight completely when the player backs away.
@export_group("Selection")
@export var preferred_min_distance: float = 0.0
## Zero or less means there is no upper preference.
@export var preferred_max_distance: float = 0.0
## Weight multiplier outside the preferred distance band. Keep this above zero
## when the attack is still valid there, just less interesting.
@export_range(0.0, 1.0, 0.05) var outside_range_weight: float = 1.0
## Arena-shaped attacks are invalid when the player is not actually in the
## arena. This is principally for Sweep, and prevents a stale Arena node from
## producing a perfectly functional attack in the wrong part of the level.
@export var requires_player_in_arena: bool = false

## The bullet this pattern fires. Left empty on the pattern and inherited from
## the boss when unset, so a whole boss shares one bullet scene by default and
## only a pattern that genuinely needs something different overrides it.
@export_group("")
@export var bullet_scene: PackedScene

## The owning boss, set by `begin`.
var boss: Boss = null

## Set by `end()`. The boss checks this so a pattern that finished itself is
## not ticked again while its node is still alive for a frame.
var finished: bool = false

## Seconds accumulated across `tick`, so a pattern can reason about elapsed time
## without keeping its own timer. This advances with `Engine.time_scale`, which
## is deliberate: a pattern slows down inside a parry hit-stop along with
## everything else, rather than continuing to fire while the world is stopped.
var elapsed: float = 0.0


## Called once, the moment the pattern is put to work.
func begin(owning_boss: Boss) -> void:
	boss = owning_boss
	finished = false
	elapsed = 0.0


## Called once per physics frame while the pattern is active.
func tick(delta: float) -> void:
	elapsed += delta


## Called exactly once, whether the pattern ran out of time, was cut short by a
## phase change, or the boss died. Anything the pattern started and the boss
## will not clean up belongs here.
func end() -> void:
	finished = true


## Ask the boss to advance as soon as the designed attack has been emitted.
## `end()` is cleanup; patterns should call this instead so the boss remains the
## sole owner of the lifecycle transition.
func finish() -> void:
	finished = true


# --- SHARED HELPERS ---

## The bullet scene to use: this pattern's, else the boss's.
func _bullet_scene() -> PackedScene:
	if bullet_scene != null:
		return bullet_scene
	if boss != null:
		return boss.bullet_scene
	return null


## Fire through the boss, so every pattern shares one spawn path and the
## camera-shake and parenting conventions live in one place instead of being
## copied into each attack.
##
## `speed_mult` is a multiplier on the bullet's own speed, so the default is 1.0
## and it must never be 0. It used to default to 0.0, which read as "unspecified"
## and meant every pattern that called `_fire(direction)` got `speed * 1.0 * 0.0`
## — a stationary bullet. The result was not subtle and not new: the spiral, the
## fan and the volley dropped their bullets at the boss's feet and they sat there
## in a slowly growing ring for the full 5s lifetime while the player could not
## parry or dodge any of it. The sweep pattern was unaffected because it calls
## `spawn_bullet_at` directly. Measured: 0px of travel in half a second for the
## first three, against 200px for the sweep.
func _fire(direction: Vector2, speed_mult: float = 1.0) -> void:
	if boss != null:
		boss.spawn_bullet(direction.normalized(), speed_mult, 0.0, _bullet_scene())


## Small shared punctuation for a firing beat. It uses the feedback shader, so
## it composes with the attack tint and remains safe when placeholder art is
## replaced.
func _attack_pulse(strength: float = 0.3) -> void:
	if boss != null:
		boss.attack_pulse(strength)


## A unit vector at `angle` radians, so patterns can think in angles without
## each one repeating the `Vector2.RIGHT.rotated()` incantation.
func _dir(angle: float) -> Vector2:
	return Vector2.RIGHT.rotated(angle)


## Screen angle from this pattern to the player, or `fallback` when there is no
## player to aim at. Returns an angle rather than a direction so a pattern can
## fan bullets around it.
func _angle_to_player(fallback: float = 0.0) -> float:
	if boss == null or not boss.is_instance_valid_player():
		return fallback
	return (boss.player_position() - boss.global_position).angle()


## True once the pattern has run for at least `seconds`.
func _elapsed_at_least(seconds: float) -> bool:
	return elapsed >= seconds
