extends CharacterBody2D

enum State { IDLE, CHASE, PREPARE, DASH, STUNNED }
var current_state = State.IDLE

@export var speed = 150.0
@export var dash_speed = 600.0
## Damage is in HEARTS, the same unit enemy_bullet.gd uses, because the player's
## whole damage economy assumes it: healing restores 1, a hit during parry
## recovery doubles, and the popup prints the number that was subtracted.
## This was 10, which one-shot the player at any max_hp, because nothing in
## take_damage() clamps a hit to a single heart.
@export var damage = 2
@export var gravity = 980.0

@export var max_hp: int = 30 # Example value
@export var windup_duration: float = 0.5
@export var dash_duration: float = 0.3
@export var stun_duration: float = 2.0
@export var parry_knockback: float = 300.0

@export_group("Aggro")
## Leash radius. Past this the enemy drops aggro entirely: no chase, no dash,
## no live hitbox. Kept well above the 600px chase threshold so an enemy that
## has walked a long way still visibly returns home instead of stopping dead
## where the player left it.
@export var aggro_range: float = 900.0
## Drift back to the spawn point while de-aggroed, so a long chase cannot drag
## the enemy across the level or pile it up against the map edge.
@export var return_home: bool = true
## How far off the spawn level the enemy may be and still walk home. Past this
## it stands still, because an enemy that fell off a ledge would otherwise walk
## back at the wrong height.
@export var home_level_tolerance: float = 64.0
## Walking home is slower than chasing, so a give-up reads as a give-up. The
## last two are the arrival window: inside ARRIVE it has stopped, inside BRAKE
## it is winding the speed down to get there.
@export var home_walk_speed_mult: float = 0.75
const HOME_ARRIVE := 8.0
const HOME_BRAKE := 40.0

var hp: int

## Base tint. Kept as a named constant so a flash can be layered on top of it
## without permanently overwriting the colour.
const NORMAL_TINT := Color(1, 0, 0.1)
const STUN_TINT := Color(0, 0, 1)
## Drained-out grey while de-aggroed, so the leash is readable without having to
## watch the movement. Stays in 0..1 for the same reason the other tints do.
const IDLE_TINT := Color(0.45, 0.45, 0.5)

var player_ref = null
var popup_scene = preload("res://Scenes/popup.tscn")
@onready var hitbox = $Hitbox
@onready var sprite = $Sprite2D

## The spawn point, captured before anything moves. Not an @export: it is
## authored by where the designer dropped the enemy, not by a number.
var home_position: Vector2 = Vector2.ZERO
var is_aggroed: bool = false

## The tint the sprite is actually wearing. _update_aggro() runs every physics
## frame, and writing `modulate` unconditionally would push the same value into
## the rendering server 60 times a second for nothing.
var _applied_tint: Color = Color(-1, -1, -1, -1)

func _ready():
	
	hp = max_hp
	home_position = global_position
	
	add_to_group("enemy")
	player_ref = get_tree().get_first_node_in_group("player")
	SpriteFeedback.attach(sprite)
	
	# Setup Hitbox (Make sure it knows who owns it for parrying)
	hitbox.body_entered.connect(_on_hitbox_entered)
	hitbox.add_to_group("enemy_attack") 
	hitbox.set_meta("parent_node", self) # Crucial for parry logic
	hitbox.monitoring = false # Only dangerous when dashing
	
	# Paint the starting state. The scene file ships the red tint, but the very
	# first thing that happens may well be a de-aggro, and the enemy should
	# never sit there red while it is standing down.
	_update_aggro()

func _physics_process(delta):
	if not is_on_floor():
		velocity.y += gravity * delta
	
	# The leash is re-measured in every state except DASH and STUNNED. PREPARE is
	# included on purpose: a telegraph is not a commitment, and this is where the
	# player finds out that backing off after the flash actually works. DASH is
	# exempt because an attack in flight is not cancelled halfway, so retreating
	# from a committed dash still gets you hit.
	if current_state != State.DASH and current_state != State.STUNNED:
		_update_aggro()
	
	match current_state:
		State.IDLE:
			# Walking home owns the horizontal velocity when it applies; without
			# this the enemy would brake and accelerate every frame it is away.
			if not _walk_home():
				velocity.x = move_toward(velocity.x, 0, speed * delta)
			
		State.CHASE:
			if is_instance_valid(player_ref):
				var dir = (player_ref.global_position - global_position).normalized()
				var dist = abs(player_ref.global_position.x - global_position.x)
				
				if dist < 250: # Trigger Dash Attack
					start_dash_attack()
				elif dist < 600: # Normal Chase
					velocity.x = sign(dir.x) * speed
					sprite.flip_h = (dir.x < 0)
				else:
					velocity.x = move_toward(velocity.x, 0, speed * delta)
		
		State.PREPARE:
			velocity.x = move_toward(velocity.x, 0, speed * delta) # Stop moving
			
		State.DASH:
			# Velocity is set in start_dash, just apply gravity here
			pass
			
		State.STUNNED:
			velocity.x = move_toward(velocity.x, 0, speed * delta)

	move_and_slide()

# --- AGGRO ---
## Re-measure the leash and fold the result into the state machine.
##
## Measured as a straight-line radius rather than the x-only distance the chase
## uses, so a player who jumps above the enemy still drops aggro.
func _update_aggro() -> void:
	var in_range := false
	if is_instance_valid(player_ref):
		in_range = global_position.distance_to(player_ref.global_position) <= aggro_range
	is_aggroed = in_range
	
	# The stun owns both its colour and its exit, so the leash must not touch
	# either until the stun has actually run out.
	if current_state == State.STUNNED: return
	
	# Only IDLE and CHASE transition below, so this stays safe to call from
	# PREPARE: the windup coroutine reads the refreshed is_aggroed itself to
	# decide whether to abandon the telegraph.
	#
	# Promotion out of IDLE is deliberately not gated on the value having just
	# changed: a parry drops the enemy into IDLE with the player still in range,
	# and it has to walk itself back out into the chase.
	if is_aggroed and current_state == State.IDLE:
		current_state = State.CHASE
	elif not is_aggroed and current_state == State.CHASE:
		current_state = State.IDLE
		# Kill any telegraph glow, or the enemy stands there flashing white as if
		# it were still winding up while it is meant to be standing down.
		SpriteFeedback.clear(sprite)
	
	_apply_tint(NORMAL_TINT if is_aggroed else IDLE_TINT)

## Single exit point for this enemy's tint, so _applied_tint never drifts out of
## sync with what the sprite is actually showing.
func _apply_tint(tint: Color) -> void:
	if tint == _applied_tint: return
	_applied_tint = tint
	SpriteFeedback.set_tint(sprite, tint)

## Returns true when it has taken over the horizontal velocity, so the caller
## can skip braking on a frame where the enemy is already walking.
func _walk_home() -> bool:
	if not return_home: return false
	if absf(global_position.y - home_position.y) > home_level_tolerance: return false
	
	var to_home := home_position.x - global_position.x
	var dist := absf(to_home)
	if dist <= HOME_ARRIVE: return false
	
	# Ease off as the gap closes rather than applying a fixed walk speed inside a
	# deadzone. At full speed the enemy covers nearly 2px per frame, so a plain
	# deadzone does not stop it: it overshoots, flips direction, and jitters on
	# the spot forever. Scaling with the remaining distance settles it instead.
	var ease := clampf((dist - HOME_ARRIVE) / (HOME_BRAKE - HOME_ARRIVE), 0.0, 1.0)
	velocity.x = sign(to_home) * speed * home_walk_speed_mult * ease
	# flip_h is true when facing left, matching how the chase sets it.
	sprite.flip_h = to_home < 0
	return true

func start_dash_attack():
	current_state = State.PREPARE
	
	# 1. Telegraph (flash white, then settle back to the red tint)
	SpriteFeedback.flash(sprite, Color.WHITE, 0.9, 0.25)
	_apply_tint(NORMAL_TINT)
	
	await get_tree().create_timer(windup_duration).timeout
	if current_state != State.PREPARE: return # Stopped if died/stunned
	
	# The player can break the leash during the windup, which is the whole point
	# of a telegraph: backing off after the flash has to actually work.
	if not is_aggroed:
		current_state = State.IDLE
		_apply_tint(IDLE_TINT)
		return
	
	# 2. Dash!
	current_state = State.DASH
	var dir = -1 if sprite.flip_h else 1
	velocity.x = dir * dash_speed
	hitbox.monitoring = true # Enable Hitbox
	
	await get_tree().create_timer(dash_duration).timeout
	
	# 3. Recovery
	hitbox.monitoring = false
	if current_state == State.DASH:
		current_state = State.CHASE

# --- PARRY LOGIC ---
# The stun must land IMMEDIATELY. Reacting two seconds late lets the enemy keep
# chasing and land its dash, which reads as "the parry did nothing". The dash
# coroutine above already bails out safely because it re-checks current_state
# after every await.
func get_parried(_is_full_spark = false):
	if current_state == State.STUNNED: return
	
	print("Enemy Parried!")
	hitbox.set_deferred("monitoring", false)
	current_state = State.STUNNED
	
	# Visual Stun Effect
	_apply_tint(STUN_TINT) # Turn Blue
	# A short flash on top sells the impact without wiping the blue.
	SpriteFeedback.flash(sprite, Color(1, 1, 1), 1.0, 0.15)
	velocity.x = -sign(velocity.x) * parry_knockback # Knockback
	
	# Stun duration
	await get_tree().create_timer(stun_duration).timeout
	if not is_instance_valid(self): return # Killed while stunned
	
	# Hand the decision back to the leash rather than assuming the player is
	# still nearby: a parry can be the last thing that happens before the player
	# disengages, and the enemy should not charge straight back out.
	SpriteFeedback.clear(sprite)
	current_state = State.IDLE
	_update_aggro()

func _on_hitbox_entered(body):
	if not body.is_in_group("player") or not body.has_method("take_damage"):
		return
	
	# An open parry swallows the contact. take_damage() refuses it either way,
	# but bailing here too keeps the hitbox from reporting a connect at all: the
	# hit passes through a parrying player exactly as it would if they were not
	# there, instead of landing while the parry is still up.
	if body.has_method("is_parrying") and body.is_parrying():
		return
	
	body.take_damage(damage)

func take_damage(amount):
	hp -= amount
	
	# 1. Show Damage Popup
	if popup_scene:
		var popup = popup_scene.instantiate()
		get_parent().add_child(popup)
		popup.global_position = global_position + Vector2(0, -50)
		popup.setup(str(amount), Color(1, 0.5, 0)) # Orange numbers
	
	# 2. Visual Flash (Hit Feedback)
	# The flash no longer clobbers the tint, so a stunned enemy stays blue while
	# it flashes on impact.
	if sprite:
		SpriteFeedback.flash(sprite, Color.WHITE, 1.0, 0.1)
	
	# 3. Death Logic
	if hp <= 0:
		die()

func die():
	# Optional: Add explosion here later
	queue_free()
