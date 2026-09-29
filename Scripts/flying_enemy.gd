extends CharacterBody2D

@export var max_hp = 20
@export var speed = 120.0
@export var preferred_dist = 350.0 # The "Safe Zone"
@export var bullet_scene: PackedScene = preload("res://Scenes/enemy_bullet.tscn")

@export_group("Aggro")
## Leash radius. Past this the enemy stops shooting and drifts back to its
## spawn point. Sits above shoot_range on purpose: it needs room to finish a
## burst that started in range, and it must never be inside the range it
## abandons the player at, or the pair would oscillate.
@export var aggro_range: float = 800.0
@export var shoot_range: float = 600.0
## Drift back to the spawn point while de-aggroed, so a long fight cannot drag
## the enemy across the level.
@export var return_home: bool = true

## Matches the sprite modulate authored in flying_enemy.tscn, so a future art
## swap does not silently change the enemy the player is looking at.
const NORMAL_TINT := Color(0.41, 1, 0.6)
## The same green drained out, so a de-aggroed flier still reads as itself
## rather than as a different enemy.
const IDLE_TINT := Color(0.37, 0.55, 0.45)

var popup_scene = preload("res://Scenes/popup.tscn")
var hp = max_hp
var player_ref = null
var can_shoot = true

## The spawn point, captured before anything moves.
var home_position: Vector2 = Vector2.ZERO
var is_aggroed: bool = false
## The tint the sprite is actually wearing, so the per-frame aggro check does
## not push the same modulate into the rendering server 60 times a second.
var _applied_tint: Color = Color(-1, -1, -1, -1)

@onready var sprite = $Sprite2D

func _ready():
	add_to_group("enemy")
	player_ref = get_tree().get_first_node_in_group("player")
	home_position = global_position
	SpriteFeedback.attach(sprite)
	# Paint the starting state rather than trusting the scene file's modulate.
	_update_aggro()

func _physics_process(delta):
	if not is_instance_valid(player_ref):
		velocity = velocity.move_toward(Vector2.ZERO, 200 * delta)
		move_and_slide()
		return
	
	var vec_to_player = player_ref.global_position - global_position
	var dist = vec_to_player.length()
	var dir = vec_to_player.normalized()
	
	_update_aggro(dist)
	
	if is_aggroed:
		if dist < preferred_dist - 50:
			# Too Close! Retreat!
			velocity = -dir * speed * 1.5
		elif dist > preferred_dist + 50:
			# Too Far! Chase!
			velocity = dir * speed
		else:
			# Just Right: Strafe / Hover
			velocity = velocity.move_toward(Vector2.ZERO, 200 * delta)
	else:
		_drift_home(delta)
	
	move_and_slide()
	
	# Try to shoot
	if is_aggroed and can_shoot and dist < shoot_range:
		start_burst_fire()

# --- AGGRO ---
func _update_aggro(dist: float = -1.0) -> void:
	# Measured as a straight-line radius rather than horizontal distance, so a
	# player standing above the flier still drops aggro.
	if dist < 0.0:
		dist = INF if not is_instance_valid(player_ref) else global_position.distance_to(player_ref.global_position)
	
	is_aggroed = dist <= aggro_range
	_apply_tint(NORMAL_TINT if is_aggroed else IDLE_TINT)

## Single exit point for this enemy's tint, so _applied_tint never drifts out of
## sync with what the sprite is actually showing.
func _apply_tint(tint: Color) -> void:
	if tint == _applied_tint: return
	_applied_tint = tint
	SpriteFeedback.set_tint(sprite, tint)

## Fliers have no gravity to fight, so homing is a straight 2D move. It eases
## out inside a small radius instead of jittering around the spawn point.
func _drift_home(delta: float) -> void:
	if not return_home:
		velocity = velocity.move_toward(Vector2.ZERO, 200 * delta)
		return
	
	var to_home := home_position - global_position
	if to_home.length() < 8.0:
		velocity = velocity.move_toward(Vector2.ZERO, 200 * delta)
	else:
		velocity = velocity.move_toward(to_home.normalized() * speed, speed * 2.0 * delta)

func start_burst_fire():
	can_shoot = false
	
	# Burst of 3 shots
	for i in range(3):
		if not is_instance_valid(player_ref): break
		
		# Re-checked between shots, not just before the burst: the player breaking
		# the leash mid-burst has to stop the rest of it, otherwise the flier
		# keeps firing from beyond the range it supposedly gave up at.
		if not is_aggroed: break
		
		var b = bullet_scene.instantiate()
		get_parent().add_child(b)
		b.global_position = global_position
		
		# Calculate Aim (Predictive or Direct)
		var aim_dir = (player_ref.global_position - global_position).normalized()
		b.direction = aim_dir
		b.rotation = aim_dir.angle()
		
		# Increase speed manually here
		b.speed = 600 # Faster than default 400
		
		# Wait before next bullet
		await get_tree().create_timer(0.2).timeout
	
	# Cooldown before next burst
	await get_tree().create_timer(2.0).timeout
	can_shoot = true

func take_damage(amount):
	hp -= amount
	
	# 1. Show Damage Popup
	if popup_scene:
		var popup = popup_scene.instantiate()
		get_parent().add_child(popup)
		popup.global_position = global_position + Vector2(0, -50)
		popup.setup(str(amount), Color(1, 0.8, 0)) # Yellow numbers
	
	# 2. Visual Flash
	# Flashes via the shader so the green tint is preserved underneath.
	SpriteFeedback.flash(sprite, Color.WHITE, 1.0, 0.1)
	
	if hp <= 0:
		die()

func die():
	queue_free()
