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
@export var bullet_speed_mult: float = 1.0

@export_category("Patterns")
## The pool this boss draws from. Order does not matter; weight and phase do.
@export var pattern_scenes: Array[PackedScene] = []

@export_category("Pacing")
## Seconds of breathing room before the first attack of a cycle. Short enough
## that the fight starts, long enough to read the intro.
@export var idle_time: float = 0.9
## Punish window after every attack. This is the player's reward for surviving
## a pattern, and the main thing to tune if the fight feels unfair — a parry
## that lands here is a parry that buys something.
@export var tired_time: float = 1.8
## Fade the boss out and back in when repositioning.
@export var teleport_out: float = 0.3
@export var teleport_in: float = 0.3
## Never place the boss closer than this to the player, so a reposition is never
## an instant hit.
@export var teleport_clearance: float = 260.0

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
		})
		probe.free()


## Pick the next pattern: anything available in this phase, weighted, and never
## the same one twice running.
##
## The no-repeat rule falls back to allowing a repeat when it would leave
## nothing to pick. A pool of one should fire that one forever, not stall the
## fight waiting for an option that does not exist.
func _pick_pattern() -> PackedScene:
	var candidates: Array[Dictionary] = []
	var unique: Array[Dictionary] = []
	for entry in _pool:
		if int(entry["phase"]) > _phase:
			continue
		if entry["scene"] == _last_pattern_scene:
			continue
		unique.append(entry)
		candidates.append(entry)

	if candidates.is_empty():
		candidates = unique
	if candidates.is_empty():
		# Every pattern is phase 2 and the boss has not enraged yet. Use the
		# whole pool rather than standing still.
		candidates = _pool
	if candidates.is_empty():
		return null

	var total := 0.0
	for entry in candidates:
		total += float(entry["weight"])
	var roll := randf() * total
	for entry in candidates:
		roll -= float(entry["weight"])
		if roll <= 0.0:
			return entry["scene"]
	return candidates[candidates.size() - 1]["scene"]


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
		State.IDLE, State.TIRED:
			_state_time -= delta
			if _state_time <= 0.0:
				_set_state(State.PATTERN)
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
	get_tree().call_group("camera", "change_target", self)
	await get_tree().create_timer(1.4).timeout
	if current_state == State.DYING: return
	if name_label != null:
		name_label.visible = true
	get_tree().call_group("camera", "return_to_player")
	_set_state(State.IDLE)


func _teleport() -> void:
	_destination = bounds_node.random_point(player_position(), teleport_clearance) \
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


# --- BULLETS ---

## The one place a pattern's bullet is created. Patterns call this rather than
## instantiating bullets themselves so the parenting, the shake, and the phase
## speed multiplier stay in one place.
func spawn_bullet(direction: Vector2, speed_mult: float = 1.0) -> void:
	spawn_bullet_at(global_position, direction, speed_mult)


func spawn_bullet_at(at: Vector2, direction: Vector2, speed_mult: float = 1.0) -> void:
	if bullet_scene == null or direction == Vector2.ZERO:
		return
	var b := bullet_scene.instantiate()
	get_parent().add_child(b)
	b.global_position = at
	b.direction = direction.normalized()
	b.rotation = b.direction.angle()
	if "speed" in b:
		b.speed = b.speed * bullet_speed_mult * speed_mult


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
	# rest of the frame.
	get_tree().call_group("camera", "return_to_player")
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
