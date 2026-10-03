class_name Boss
extends CharacterBody2D

## A pattern-driven boss.
##
## Replaces the prototype's single hardcoded state machine, where
## `INTRO / IDLE / SPIRAL / SHOTGUN / TIRED / TELEPORT / DYING` all lived in one
## script and the choice between the two attacks was `randi() % 2`. Two
## consequences, both of which this file exists to fix:
##
##   - Adding an attack meant adding a branch to a 250-line function. Attacks are
##     now BossPattern scenes; a boss is a list of them.
##   - A coin flip has no rhythm. Bosses are memorable because of the order
##     their attacks arrive in, and `randi() % 2` cannot produce one. Selection is
##     a weighted pool that will not repeat the same attack twice running, so
##     the fight has a shape the player can learn.
##
## The beat is the part that was worth keeping and is now explicit rather than
## emergent: attack, punish window, reposition, attack. A player who survives
## gets a readable chance to punish, which is what makes the parry worth doing
## instead of only surviving.

enum State { INACTIVE, INTRO, IDLE, PATTERN, TIRED, TELEPORT, DYING }

# --- CONFIGURATION ---

@export_category("Boss")
@export var max_hp: int = 500
## Shown on the health bar. Mostly here so a template arena with two bosses
## makes it obvious which one is being tested.
@export var display_name: String = "BOSS"
@export var bullet_scene: PackedScene
## Bullets are spawned at the boss and driven by their own script. This scales
## every pattern's bullets at once, which is the phase-two lever.
##
## Above 1.0 because the fight was measured at one attack every 6.8s and 2.7
## bullets a second at 400px/s, which is slow enough that the player has time to
## memorise an answer rather than read one. The ceiling is the player's own
## reflexes: they move at 300 and dash at 1000, so 580px/s is fast to react to
## and still slower than a committed dodge.
@export var bullet_speed_mult: float = 1.45

@export_category("Patterns")
## The pool this boss draws from. Order does not matter; weight and phase do.
@export var pattern_scenes: Array[PackedScene] = []

@export_category("Pacing")
## Seconds of breathing room before the first attack of a cycle. Short enough
## that the fight starts, long enough to read the intro. Kept well under the
## player's 0.8s parry cooldown, because the gap before an attack is the window
## in which a parry actually lands.
@export var idle_time: float = 0.35
## Punish window after every attack. This is the player's reward for surviving
## a pattern, and the main thing to tune if the fight feels unfair — a parry
## that lands here is a parry that buys something.
##
## Cut from 1.8s, but not further: this has to stay longer than a parry cooldown
## so that a parry which reflects a bullet is followed by the time to use the
## Sparks it paid for. Halving it made the fight quick and took the reward with
## it.
@export var tired_time: float = 1.15
## Blink to a new spot at the end of every punish window, so each attack arrives
## from a different angle. Turning it off restores the older behaviour: the boss
## holds its ground for the entire fight and only blinks when it enrages, which
## lets the player memorise one safe spot per pattern and then simply stand
## there. It is an export because "how often should a set piece re-stage itself"
## is a design call, not a bug fix.
@export var reposition_between_attacks: bool = true
## Fade the boss out and back in when repositioning. Short, because with a
## reposition between every attack this happens several times a fight and a long
## fade turns the loop into waiting.
@export var teleport_out: float = 0.18
@export var teleport_in: float = 0.18
## Never place the boss closer than this to the player, so a reposition is never
## an instant hit.
@export var teleport_clearance: float = 260.0
## Hold the camera on the arena for the whole fight instead of following the
## player. This was requested, and it is a real improvement for a fight played
## inside a box, but **it is off by default in `main.tscn`'s boss room** because
## of what was measured about that room (see the note on `_claim_camera`).
## Leave this on for a self-contained arena like `boss_arena.tscn`.
@export var hold_camera_on_arena: bool = true

@export_category("Phase Two")
## Fraction of max_hp at which the boss enrages. 0.5 means halfway.
@export var phase_two_at: float = 0.5
## Popup shown at the transition.
@export var phase_two_text: String = "ENRAGED!"

# --- STATE ---

var current_state: State = State.INACTIVE
var hp: int = 0
var is_phase_two: bool = false
var player_ref: Node2D = null

## The pattern running right now, or null.
var _pattern: BossPattern = null
## Pattern metadata read once at ready, so picking is a data operation and does
## not allocate a node per candidate several times a second.
var _pool: Array[Dictionary] = []
## The scene used for the pattern currently running, kept out of the next pick so
## a boss cannot fire the same attack twice in a row.
var _last_pattern_scene: PackedScene = null
var _phase: int = 1
## Seconds left in the current timed state.
var _state_time: float = 0.0
## Where an in-flight teleport is heading. Assigned before the fade so the boss
## can be moved there at the midpoint.
var _destination: Vector2 = Vector2.ZERO
var _player: Node2D = null

@onready var health_bar: ProgressBar = $CanvasLayer/HealthBar
@onready var name_label: Label = $CanvasLayer/NameLabel
@onready var sprite: Sprite2D = $Sprite2D
@onready var bounds_node: ArenaBounds = get_node_or_null("../Arena") as ArenaBounds

# --- COLOURS ---
# Per-state boss colour, kept in 0..1 like every other tint in the project. The
# pattern's own tint wins while a pattern runs, so the player can read which
# attack is coming; these are the fallback for the states between attacks.
const INACTIVE_TINT := Color(0.35, 0.35, 0.4)
const IDLE_TINT := Color(0.55, 0.15, 0.55)
const TIRED_TINT := Color(0.4, 0.4, 0.45)
const DYING_TINT := Color(0.3, 0.3, 0.3)


func _ready() -> void:
	hp = max_hp
	add_to_group("enemy")
	player_ref = get_tree().get_first_node_in_group("player")
	_player = player_ref as Node2D

	SpriteFeedback.attach(sprite)

	_read_pattern_pool()

	if health_bar != null:
		health_bar.max_value = max_hp
		health_bar.value = hp
		health_bar.visible = false
	if name_label != null:
		name_label.text = display_name
		name_label.visible = false

	# current_state is already INACTIVE from its member initialiser, so
	# _set_state(State.INACTIVE) here would hit the same-state guard added for
	# the teleport and silently do nothing. Apply the presentation directly
	# instead. If INACTIVE ever needs more setup, this is the line to add it to.
	_apply_tint(INACTIVE_TINT)
	_set_bar_visible(false)


# --- PATTERN POOL ---

## Read weight and phase off each pattern scene once, up front.
##
## The obvious alternative is to instantiate every candidate on every pick, but
## that allocates a node per pattern per attack for the whole fight to read two
## floats. Freeing the probe with `free()` rather than `queue_free()` is safe
## because it was never in the tree.
func _read_pattern_pool() -> void:
	_pool.clear()
	for scene in pattern_scenes:
		if scene == null:
			continue
		var probe := scene.instantiate() as BossPattern
		if probe == null:
			push_warning("Boss: %s is not a BossPattern, skipping." % scene.resource_path)
			continue
		_pool.append({
			"scene": scene,
			"weight": maxf(0.01, probe.weight),
			"phase": probe.phase,
			"duration": probe.duration,
			"tint": probe.tint,
			"preferred_min_distance": maxf(0.0, probe.preferred_min_distance),
			"preferred_max_distance": maxf(0.0, probe.preferred_max_distance),
			"outside_range_weight": clampf(probe.outside_range_weight, 0.0, 1.0),
			"requires_player_in_arena": probe.requires_player_in_arena,
		})
		probe.free()


## Pick the next pattern: anything available in this phase, weighted, and never
## the same one twice running.
##
## The no-repeat rule falls back to allowing a repeat when it would leave
## nothing to pick. A pool of one should fire that one forever, not stall the
## fight waiting for an option that does not exist.
func _pick_pattern() -> PackedScene:
	var eligible: Array[Dictionary] = []
	var player_distance := global_position.distance_to(player_position())
	var player_in_arena := bounds_node != null and bounds_node.rect().grow(1.0).has_point(player_position())
	for entry in _pool:
		if int(entry["phase"]) > _phase:
			continue
		if bool(entry["requires_player_in_arena"]) and not player_in_arena:
			continue
		var effective_weight := float(entry["weight"])
		var below_range := player_distance < float(entry["preferred_min_distance"])
		var max_distance := float(entry["preferred_max_distance"])
		var above_range := max_distance > 0.0 and player_distance > max_distance
		if below_range or above_range:
			effective_weight *= float(entry["outside_range_weight"])
		if effective_weight <= 0.0:
			continue
		eligible.append({"entry": entry, "weight": effective_weight})

	if eligible.is_empty():
		push_warning("Boss: no valid attack pattern for phase %d and the player's current position." % _phase)
		return null

	var candidates: Array[Dictionary] = []
	for option in eligible:
		if option["entry"]["scene"] != _last_pattern_scene:
			candidates.append(option)
	# A one-pattern pool may repeat. Importantly, this falls back only to
	# phase/context-eligible patterns; it can never leak a phase-two attack into
	# phase one just because the only phase-one attack was used last.
	if candidates.is_empty():
		candidates = eligible

	var total := 0.0
	for option in candidates:
		total += float(option["weight"])
	var roll := randf() * total
	for option in candidates:
		roll -= float(option["weight"])
		if roll <= 0.0:
			return option["entry"]["scene"]
	return candidates[candidates.size() - 1]["entry"]["scene"]


func _spawn_pattern(scene: PackedScene) -> void:
	_stop_pattern()
	if scene == null:
		return
	var p := scene.instantiate() as BossPattern
	if p == null:
		push_warning("Boss: %s did not instantiate as a BossPattern." % scene.resource_path)
		return
	add_child(p)
	p.begin(self)
	_pattern = p
	_last_pattern_scene = scene


## Stop whatever is running. Called on every path out of a pattern, including
## death and the player dying, which is why a pattern must not own its own
## process loop: `end()` has to be able to actually stop it.
func _stop_pattern() -> void:
	if _pattern == null:
		return
	var p := _pattern
	_pattern = null
	if not is_instance_valid(p):
		return
	p.end()
	p.queue_free()


# --- STATE MACHINE ---

func _physics_process(delta: float) -> void:
	match current_state:
		State.PATTERN:
			_tick_pattern(delta)
		State.IDLE:
			_state_time -= delta
			if _state_time <= 0.0:
				_set_state(State.PATTERN)
		State.TIRED:
			_state_time -= delta
			if _state_time <= 0.0:
				# The punish window ends on a reposition, not straight back into the
				# next attack. That is the beat this file's header describes —
				# attack, punish, reposition, attack — and it is the whole difference
				# between a fight and a target. With a fixed origin every pattern
				# fires from the same point along the same angles forever, so the
				# player learns one safe column per pattern and then only has to
				# stand still: measured, 0px of movement and 0.0 peak velocity
				# across a 20s phase-one fight. The bullets are not the problem —
				# an aimed shot hits at every range from 40px to 700px, including
				# pressed right up against the boss.
				_set_state(State.TELEPORT if reposition_between_attacks else State.PATTERN)
		_:
			# INACTIVE, INTRO, TELEPORT and DYING are all driven by awaits and
			# tweens inside _set_state(), so there is deliberately nothing to tick
			# here. Teleport is included: its fade is a tween, and the boss has no
			# business moving while it is halfway through being somewhere else.
			pass


## The boss does not fall or slide; it is a floating set piece that repositions
## on its own timer. Gravity here would fight the teleport and pin the boss to
## whatever floor it happened to be over.
func _apply_motion(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
	if velocity != Vector2.ZERO:
		move_and_slide()


func _tick_pattern(delta: float) -> void:
	if _pattern == null or not is_instance_valid(_pattern):
		# Should not happen, but a pattern that freed itself must not strand the
		# boss in PATTERN with nothing running.
		_set_state(State.TIRED)
		return
	_pattern.tick(delta)
	_apply_motion(delta)
	if _pattern.finished:
		_stop_pattern()
		_set_state(State.TIRED)
		return
	if _pattern.duration > 0.0 and _pattern.elapsed >= _pattern.duration:
		_stop_pattern()
		_set_state(State.TIRED)


func _set_state(new_state: State) -> void:
	# The DYING guard is what stops a teleport or a pattern from reviving the
	# boss after its death cinematic has already started.
	if current_state == State.DYING:
		return
	# A repeated request for the state we are already in is a no-op. This matters
	# for TELEPORT, whose handler is an await chain: re-entering it would leave
	# two fade tweens fighting over one sprite's alpha and send the boss to
	# whichever destination was written last. Checked before the assignment below,
	# since by then the two states are indistinguishable.
	if current_state == new_state:
		return

	# Leaving PATTERN must stop the pattern, or a phase change or a teleport
	# would leave bullets coming out of a boss that is no longer attacking.
	if current_state == State.PATTERN and new_state != State.PATTERN:
		_stop_pattern()

	current_state = new_state
	_state_time = 0.0

	match new_state:
		State.INACTIVE:
			_apply_tint(INACTIVE_TINT)
			_set_bar_visible(false)
		State.INTRO:
			_set_bar_visible(true)
			_apply_tint(Color(1, 1, 1))
			_intro()
		State.IDLE:
			_apply_tint(IDLE_TINT)
			_state_time = idle_time
		State.PATTERN:
			_spawn_pattern(_pick_pattern())
			if _pattern != null:
				# The pattern's own tint wins, so the player can read the attack
				# from the boss before the first bullet exists.
				_apply_tint(_pattern.tint)
				_telegraph_attack()
			else:
				_set_state(State.TIRED)
		State.TIRED:
			_apply_tint(TIRED_TINT)
			_state_time = tired_time
		State.TELEPORT:
			_teleport()
		State.DYING:
			_stop_pattern()
			_apply_tint(DYING_TINT)
			_set_bar_visible(false)


## Start the fight. Idempotent, so a trigger that the player clips twice cannot
## restart a fight in progress.
func start_fight() -> void:
	if current_state == State.INACTIVE:
		_set_state(State.INTRO)


# --- INTRO / TELEPORT ---

func _intro() -> void:
	_claim_camera()
	await get_tree().create_timer(1.4).timeout
	if current_state == State.DYING: return
	if name_label != null:
		name_label.visible = true
	_set_state(State.IDLE)


## Take the camera for the whole fight, and frame the room on it.
##
## The camera used to be handed back to the player 1.4s into the intro, which
## meant the framing during an actual fight was whatever the player happened to
## be standing under. For a fight played inside a closed box that is the wrong
## camera: the boss teleports anywhere inside the arena and the sweep curtain
## crosses all of it, so a camera locked to the player is looking at a fraction
## of the threats.
##
## **But only if the fight is actually inside the box.** Measured on
## `main.tscn`: the arena rect is x 325..1272, y -937..-600, and the nearest
## standable surface to the boss is the ceiling slab at y = -1216 — 320px away,
## with the player hanging 384px *above* the boss's head. The player never
## enters the rect at all; they climb a route on ledges outside it. Framing that
## rect during a fight would centre the camera on a region of level that
## contains neither the player nor anything they can stand on, so the fight would
## be played off the bottom of the screen.
##
## So this only claims the camera when the arena actually contains the player. If
## it does not, the fight is happening somewhere the arena does not describe, and
## following the player is the lesser evil. `hold_camera_on_arena` stays the
## master switch; this is a second, measured guard behind it.
func _claim_camera() -> void:
	if not hold_camera_on_arena:
		return
	# No arena, or the arena is not where the player is: leave the camera alone.
	if bounds_node == null or not bounds_node.rect().has_point(player_position()):
		return
	var target: Node2D = bounds_node
	for cam in get_tree().get_nodes_in_group("camera"):
		if cam.has_method("change_target"):
			cam.change_target(target)
		# Only frame when there is an arena: framing the boss's own 160x160 box
		# would zoom in on a dot.
		if cam.has_method("frame_rect"):
			cam.frame_rect(bounds_node.rect())


## Hand the camera back once the fight is over and there is nothing left to
## watch. Called at the end of the death cinematic, so a boss fight that ends
## does not leave the camera parked on an empty room if the player walks on.
func _release_camera() -> void:
	for cam in get_tree().get_nodes_in_group("camera"):
		if cam.has_method("return_to_player"):
			cam.return_to_player()
		if cam.has_method("clear_frame"):
			cam.clear_frame()


func _teleport() -> void:
	# The boss's own footprint goes with the request, so a target that would bury
	# it in a ledge is rejected. See ArenaBounds.random_point() for the numbers.
	_destination = bounds_node.random_point(player_position(), teleport_clearance, body_footprint()) \
		if bounds_node != null else global_position
	var tween := create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, teleport_out)
	await tween.finished
	if current_state == State.DYING: return
	global_position = _destination
	var tween_in := create_tween()
	tween_in.tween_property(sprite, "modulate:a", 1.0, teleport_in)
	await tween_in.finished
	if current_state == State.DYING: return
	_set_state(State.IDLE)


# --- TELEGRAPHING ---

func _set_bar_visible(v: bool) -> void:
	if health_bar != null:
		health_bar.visible = v


## Single exit point for the boss tint, for the same reason the regular enemies
## have one: a flash layered on top of a tint must not be able to desync them.
func _apply_tint(tint: Color) -> void:
	SpriteFeedback.set_tint(sprite, tint)


## Every attack starts with the same short visual grammar: tint identifies the
## pattern, white flash says "read now". The pattern's own wind-up still owns
## the actual reaction time.
func _telegraph_attack() -> void:
	SpriteFeedback.flash(sprite, Color.WHITE, 0.7, 0.12)


## Called once per volley/curtain, not once per bullet, so dense attacks feel
## decisive without turning the boss into a permanent white strobe.
func attack_pulse(strength: float = 0.3) -> void:
	if current_state != State.PATTERN or sprite.modulate.a <= 0.5:
		return
	SpriteFeedback.flash(sprite, Color.WHITE, clampf(strength, 0.0, 1.0), 0.06)
	get_tree().call_group("camera", "add_shake", strength * 0.08)


# --- BULLETS ---

## The one place a pattern's bullet is created. Patterns call this rather than
## instantiating bullets themselves so the parenting, the shake, and the phase
## speed multiplier stay in one place.
##
## This one clears the boss's own body; spawn_bullet_at() deliberately does not.
## Bullets used to be born at `global_position`, which is the middle of a 160x160
## collision shape sitting under a 192px sprite, so every shot started inside the
## boss and spent the first fifth of a second travelling under its own sprite.
## Measured, before the fix: 0px of clearance in every direction, against 80px
## of body and ~96px of sprite. A spiral volley read as a clump growing out of
## the boss's chest rather than shots leaving it.
func spawn_bullet(direction: Vector2, speed_mult: float = 1.0, lifetime: float = 0.0, scene_override: PackedScene = null) -> void:
	var source := scene_override if scene_override != null else bullet_scene
	if source == null:
		return
	var dir := direction.normalized()
	if dir == Vector2.ZERO:
		return
	# Instantiate before placing, because the muzzle has to clear the bullet's own
	# shape as well as the boss's. An Area2D reports a given body exactly once, so
	# a bullet born overlapping its own boss permanently disowns that pair: the
	# player could reflect the shot and it would sail straight back through the
	# boss that fired it, taking no damage. Measured, before the fix: a reflected
	# bullet passing back through the boss left it on 500/500.
	var b := source.instantiate()
	var at := global_position + dir * (muzzle_distance(dir) + shape_reach(b, dir))
	_place_bullet(b, at, dir, speed_mult, lifetime)


## Fire from a world point the pattern chose, rather than from the boss. The
## sweep pattern lays a wall across the arena with this, so the spawn point is
## already somewhere the boss has nothing to do with and no muzzle offset is
## wanted. See spawn_bullet() for the offset that the other path needs.
func spawn_bullet_at(at: Vector2, direction: Vector2, speed_mult: float = 1.0, lifetime: float = 0.0, scene_override: PackedScene = null) -> void:
	var source := scene_override if scene_override != null else bullet_scene
	if source == null:
		return
	var dir := direction.normalized()
	if dir == Vector2.ZERO:
		return
	_place_bullet(source.instantiate(), at, dir, speed_mult, lifetime)


## Half-extent of this boss's own collision shape, for anything that needs to
## keep clear of it. Read off the real shapes rather than assumed, for the same
## reason `muzzle_distance()` reads them instead of hardcoding 80: a boss resized
## in the inspector must not silently start clipping again.
func body_footprint() -> Vector2:
	var half := Vector2.ZERO
	for child in get_children():
		var collider := child as CollisionShape2D
		if collider == null or collider.shape == null:
			continue
		var rect := collider.shape as RectangleShape2D
		if rect != null:
			half = half.max(rect.size * 0.5)
			continue
		var circle := collider.shape as CircleShape2D
		if circle != null:
			half = half.max(Vector2(circle.radius, circle.radius))
	return half


## The one place a spawned bullet is parented, placed, and configured, so the
## speed multiplier and the rotation cannot drift between the two spawn paths.
##
## `lifetime` of zero or less means "leave the bullet's own alone": the default
## is the bullet scene's business, not something every caller should restate.
## The hook remains available for a future weapon whose range genuinely needs
## it, and must be applied here before `_ready()` starts the bullet's timer.
func _place_bullet(b: Area2D, at: Vector2, dir: Vector2, speed_mult: float, lifetime: float = 0.0) -> void:
	# Configured BEFORE the bullet enters the tree. `enemy_bullet._ready()` reads
	# `lifetime` to start its self-destruct timer, so setting it after add_child is
	# setting it after the 5s default has already been committed: the shotgun's
	# pellets measured 778px of travel instead of the ~200px its range calls for,
	# because the range was silently the default. Same shape of mistake as the
	# muzzle offset, which is why both are read off the instance before placing it.
	if "speed" in b:
		b.speed = b.speed * bullet_speed_mult * speed_mult
		# A bullet that cannot move is never what anyone meant, and it fails
		# silently: it sits where it was born looking like a decoration until it
		# ages out. Warn rather than clamp, because a clamped 0 would hide the
		# mistake behind plausible-looking motion, and because a warning makes the
		# required `godot --headless --quit-after 300` run fail loudly.
		if b.speed <= 0.0:
			push_warning("Boss: spawned a bullet with speed %.2f. Check the pattern's speed multiplier." % b.speed)
	if lifetime > 0.0 and "lifetime" in b:
		b.lifetime = lifetime
	b.direction = dir
	b.rotation = dir.angle()
	get_parent().add_child(b)
	b.global_position = at


## Extra clearance past the boss's own collision shape before a bullet is allowed
## to exist, so it does not begin life flush against the body it came from. A
## couple of pixels is enough: the bullet's own radius is already added on top by
## the caller.
@export var muzzle_margin: float = 4.0


## How far along `direction` the boss's collision shapes reach from its centre.
##
## The largest of its own shapes, not a hardcoded number, so a boss that is
## resized in the inspector or given a second hitbox does not silently go back to
## firing from inside itself. A rectangle is measured by its support function in
## that direction rather than by its bounding circle, or a diagonal shot from a
## 160x160 square would be pushed out to a corner distance of 113px and read as
## a wider gap to the player than a horizontal one.
func muzzle_distance(direction: Vector2) -> float:
	return shape_reach(self, direction) + muzzle_margin


## Distance from `node`'s origin to the outside of its largest collision shape,
## measured along `dir`. Works on any node with CollisionShape2D children, which
## is how the same routine measures both the boss and an unscripted bullet.
func shape_reach(node: Node, dir: Vector2) -> float:
	var reach := 0.0
	for child in node.get_children():
		var collider := child as CollisionShape2D
		if collider == null or collider.shape == null:
			continue
		var rect := collider.shape as RectangleShape2D
		if rect != null:
			var half := rect.size * 0.5
			reach = maxf(reach, absf(dir.x) * half.x + absf(dir.y) * half.y)
			continue
		var circle := collider.shape as CircleShape2D
		if circle != null:
			reach = maxf(reach, circle.radius)
			continue
		var capsule := collider.shape as CapsuleShape2D
		if capsule != null:
			# Only the caps stick out sideways; the flat side is the height.
			var straight := maxf(capsule.height * 0.5 - capsule.radius, 0.0)
			reach = maxf(reach, capsule.radius + absf(dir.y) * straight)
	return reach


# --- HELPERS FOR PATTERNS ---

## The arena this fight happens in, or null when the boss is used without one.
func arena() -> ArenaBounds:
	return bounds_node


func player_position() -> Vector2:
	if is_instance_valid(_player):
		return _player.global_position
	return global_position + Vector2(0, 400)


func is_instance_valid_player() -> bool:
	return is_instance_valid(_player) and not _player.is_dead


# --- DAMAGE ---

func take_damage(amount: int) -> void:
	if current_state == State.DYING:
		return

	hp = max(hp - amount, 0)
	if health_bar != null:
		health_bar.value = hp

	# Only skip the flash mid-teleport, when the boss is invisible and a flash
	# would light up empty air.
	if sprite.modulate.a > 0.5:
		SpriteFeedback.flash(sprite, Color.WHITE, 1.0, 0.1)

	if hp <= 0:
		die()
		return
	if not is_phase_two and hp <= max_hp * phase_two_at:
		_start_phase_two()


func _start_phase_two() -> void:
	is_phase_two = true
	_phase = 2
	bullet_speed_mult *= 1.25
	teleport_clearance *= 0.8

	var popup := preload("res://Scenes/popup.tscn").instantiate()
	get_parent().add_child(popup)
	popup.global_position = global_position + Vector2(0, -90)
	popup.setup(phase_two_text, Color(1, 0.2, 0.2))
	popup.scale = Vector2(2, 2)

	# Reposition on the threshold so phase two opens from somewhere new rather
	# than from wherever the last pattern happened to leave the boss.
	_set_state(State.TELEPORT)


# --- DEATH ---

func die() -> void:
	if current_state == State.DYING:
		return
	_set_state(State.DYING)
	sprite.modulate.a = 1.0
	_set_bar_visible(false)
	get_tree().call_group("camera", "change_target", self)
	await _death_cinematic()


func _death_cinematic() -> void:
	var explosions := preload("res://Scenes/explosion.tscn")
	var slowmo := TimeControl.hold(0.5)

	# Skippable. The prototype's version was fifteen beats of hold-and-wait with
	# no way out, which is dead time the player has no agency in. Any of the
	# combat inputs counts, so a player already mashing to parry takes the hint.
	for i in 15:
		if _skip_requested():
			break
		spawn_explosion(global_position + Vector2(
			randf_range(-60, 60), randf_range(-60, 60)))
		get_tree().call_group("camera", "add_shake", 0.4)
		await get_tree().create_timer(0.15).timeout
		if current_state == State.DYING and not is_instance_valid(self):
			return

	TimeControl.release(slowmo)

	for offset in [Vector2.ZERO, Vector2(20, -20), Vector2(-20, 20)]:
		spawn_explosion(global_position + offset)
	get_tree().call_group("camera", "add_shake", 1.0)

	if not _skip_requested():
		await get_tree().create_timer(0.6).timeout

	var result_screen := get_tree().get_first_node_in_group("result_screen")
	if result_screen and result_screen.has_method("show_result"):
		result_screen.show_result(true)

	# Hand the camera back BEFORE freeing, or it follows a freed node for the
	# rest of the frame. This clears the fight framing as well as the target, so
	# a fight that ended does not leave the camera parked on an empty room.
	_release_camera()
	queue_free()


func _skip_requested() -> bool:
	return Input.is_action_just_pressed("attack") \
		or Input.is_action_just_pressed("parry") \
		or Input.is_action_just_pressed("dash") \
		or Input.is_action_just_pressed("jump")


func spawn_explosion(at: Vector2) -> void:
	var ex := preload("res://Scenes/explosion.tscn").instantiate()
	get_parent().add_child(ex)
	ex.global_position = at
