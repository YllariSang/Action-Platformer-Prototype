extends CharacterBody2D

@export var max_hp = 20
@export var speed = 120.0
@export var preferred_dist = 350.0 # The "Safe Zone"
@export var bullet_scene: PackedScene = preload("res://Scenes/enemy_bullet.tscn")

var popup_scene = preload("res://Scenes/popup.tscn")
var hp = max_hp
var player_ref = null
var can_shoot = true

func _ready():
	add_to_group("enemy")
	player_ref = get_tree().get_first_node_in_group("player")
	SpriteFeedback.attach($Sprite2D)

func _physics_process(delta):
	if player_ref:
		var vec_to_player = player_ref.global_position - global_position
		var dist = vec_to_player.length()
		var dir = vec_to_player.normalized()
		
		if dist < preferred_dist - 50:
			# Too Close! Retreat!
			velocity = -dir * speed * 1.5
		elif dist > preferred_dist + 50:
			# Too Far! Chase!
			velocity = dir * speed
		else:
			# Just Right: Strafe / Hover
			velocity = velocity.move_toward(Vector2.ZERO, 200 * delta)
			
		move_and_slide()
		
		# Try to shoot
		if can_shoot and dist < 600:
			start_burst_fire()

func start_burst_fire():
	can_shoot = false
	
	# Burst of 3 shots
	for i in range(3):
		if not player_ref: break
		
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
	SpriteFeedback.flash($Sprite2D, Color.WHITE, 1.0, 0.1)
	
	if hp <= 0:
		die()

func die():
	queue_free()
