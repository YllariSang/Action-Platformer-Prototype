extends CharacterBody2D

@export var max_hp: int = 600
@export_group("Room Limits")
@export var limit_left: float = -500.0
@export var limit_right: float = 500.0
@export var limit_top: float = -500.0
@export var limit_bottom: float = 0.0

@onready var state_timer = $StateTimer
@onready var health_bar = $CanvasLayer/HealthBar 
@onready var sprite = $Sprite2D
@onready var laser_ray = $LaserRay
@onready var laser_line = $LaserLine
@onready var bullet_scene = preload("res://Scenes/homing_bullet.tscn")

var popup_scene = preload("res://Scenes/popup.tscn")
var explosion_scene = preload("res://Scenes/explosion.tscn")

enum State { INACTIVE, INTRO, IDLE, LASER_AIM, LASER_FIRE, CHARGE_PREP, CHARGE, MISSILE, TIRED, DYING }
var current_state = State.INACTIVE
var hp = 0
var player_ref = null
var charge_dir = Vector2.ZERO

# --- TUNING VARIABLES ---
var charge_speed = 600.0
var laser_damage = 1
var laser_rotation_speed = 2.5 # How fast it turns (Lower = Slower Aim)
var aim_lock_time = 0.5 # How long before firing does it STOP tracking?

func _ready():
	hp = max_hp
	add_to_group("enemy") 
	player_ref = get_tree().get_first_node_in_group("player")
	state_timer.timeout.connect(_on_state_timer_timeout)
	
	health_bar.max_value = max_hp
	health_bar.value = hp
	health_bar.visible = false 
	
	laser_line.visible = false
	laser_ray.enabled = false
	
	# --- COLLISION FIX ---
	# Layer 3 = Enemy. Mask 1 = World/Walls.
	# We EXPLICITLY turn off Mask 2 (Player) so we don't physically collide.
	collision_layer = 4 # Bit 3 (Value 4)
	collision_mask = 1  # Bit 1 (Value 1) - Only hit walls
	
	change_state(State.INACTIVE) 

func start_fight():
	if current_state == State.INACTIVE:
		change_state(State.INTRO)

func _physics_process(delta):
	# ... (Keep Soft Collision Logic) ...
	
	match current_state:
		State.LASER_AIM:
			process_laser_aim(delta)
			
		State.LASER_FIRE:
			update_laser_visuals(true) 
			check_laser_damage()
			
		State.CHARGE_PREP:
			face_player_smoothly(delta * 10)
			
		State.CHARGE:
			# ... (Keep Charge Logic) ...
			velocity = charge_dir * charge_speed
			move_and_slide()
			# ... (Keep Collision/Parry Logic) ...
			

		# --- THE FIX ---
		State.MISSILE:
			# Face the player slowly while firing missiles so they don't spawn backwards
			face_player_smoothly(delta * 2.0)
			
			for i in range(get_slide_collision_count()):
				var collision = get_slide_collision(i)
				var collider = collision.get_collider()
				if collider and collider.is_in_group("player"):
					# PARRY CHECK
					if collider.get("current_state") == 3: # State.PARRY
						print("BOSS CHARGE PARRIED!")
						if collider.has_method("on_parry_success"):
							collider.on_parry_success()
						take_damage(0)
						change_state(State.TIRED)
						velocity = -charge_dir * 200
					else:
						hit_player(collider)
						change_state(State.TIRED)

# --- NEW AIMING LOGIC ---
func process_laser_aim(delta):
	# Calculate time remaining in this state
	var time_left = state_timer.time_left
	
	# If we have more than 'aim_lock_time' seconds left, we track the player
	if time_left > aim_lock_time:
		face_player_smoothly(delta * laser_rotation_speed)
		update_laser_visuals(false)
		
		# Visual Warning: Cyan (Tracking)
		laser_line.default_color = Color(0, 1, 1, 0.5)
		laser_line.width = 2
	else:
		# LOCK PHASE: Stop rotating! Flash Red!
		update_laser_visuals(false)
		laser_line.default_color = Color(1, 0, 0, 0.8) # Red Warning
		laser_line.width = 4

func face_player_smoothly(speed_factor):
	if player_ref:
		var target_dir = (player_ref.global_position - global_position).normalized()
		var target_angle = target_dir.angle()
		# Rotate towards the target angle smoothly, not instantly
		rotation = rotate_toward(rotation, target_angle, speed_factor)

func change_state(new_state):
	if current_state == State.DYING: return
	current_state = new_state
	
	# RESET MASK to Walls Only (1) by default
	collision_mask = 1
	
	match new_state:
		State.INACTIVE:
			sprite.modulate = Color(0.2, 0.2, 0.2)
		State.INTRO:
			sprite.modulate = Color(1, 1, 1) 
			await get_tree().create_timer(2.0).timeout
			health_bar.visible = true
			change_state(State.IDLE)
		State.IDLE:
			sprite.modulate = Color(1, 1, 1)
			laser_line.visible = false
			laser_ray.enabled = false
			state_timer.start(1.0)
		
		State.LASER_AIM:
			sprite.modulate = Color(0, 1, 1) 
			laser_line.visible = true
			# 2.5 seconds total: 2.0s tracking + 0.5s locked
			state_timer.start(2.5) 
			
		State.LASER_FIRE:
			sprite.modulate = Color(0, 5, 5) 
			laser_ray.enabled = true
			laser_line.width = 15
			laser_line.default_color = Color(0, 1, 1, 1.0)
			get_tree().call_group("camera", "add_shake", 0.1) 
			state_timer.start(2.5) 
			
		State.CHARGE_PREP:
			sprite.modulate = Color(1, 0, 0)
			state_timer.start(0.8)
			
		State.CHARGE:
			charge_dir = Vector2.RIGHT.rotated(rotation)
			state_timer.start(1.5)
		
		State.MISSILE:
			sprite.modulate = Color(1, 0.5, 0) 
			start_missile_barrage()
			state_timer.start(2.0)
			
		State.TIRED:
			sprite.modulate = Color(0.5, 0.5, 0.5)
			velocity = Vector2.ZERO 
			state_timer.start(2.0)
			
		State.DYING:
			laser_line.visible = false
			die_sequence()

func _on_state_timer_timeout():
	match current_state:
		State.IDLE:
			var roll = randi() % 3
			if roll == 0: change_state(State.LASER_AIM)
			elif roll == 1: change_state(State.CHARGE_PREP)
			else: change_state(State.MISSILE)
			
		State.LASER_AIM:
			change_state(State.LASER_FIRE)
		State.LASER_FIRE, State.CHARGE, State.MISSILE:
			change_state(State.TIRED)
		State.TIRED:
			change_state(State.IDLE)
		State.CHARGE_PREP:
			change_state(State.CHARGE)

# --- MISSILE LOGIC ---
func start_missile_barrage():
	for i in range(3):
		if current_state != State.MISSILE and current_state != State.DYING: break
		fire_homing_bullets()
		await get_tree().create_timer(0.4).timeout

func fire_homing_bullets():
	if not bullet_scene: return
	var bullet = bullet_scene.instantiate()
	
	# 1. Calculate spawn offset (60 pixels in front of the boss)
	# This prevents it from spawning inside the boss or instantly hitting a nearby player
	var spawn_offset = Vector2.RIGHT.rotated(rotation) * 80
	bullet.global_position = global_position + spawn_offset
	
	if bullet.get("target") == null: 
		bullet.target = player_ref 
	
	# 2. Spread Logic
	var spread = randf_range(-0.5, 0.5)
	bullet.rotation = rotation + spread
	
	get_parent().add_child(bullet)

# --- LASER / HIT LOGIC ---
func update_laser_visuals(is_firing):
	var end_point = Vector2(1000, 0)
	if laser_ray.is_colliding():
		end_point = to_local(laser_ray.get_collision_point())
	laser_line.clear_points()
	laser_line.add_point(Vector2.ZERO)
	laser_line.add_point(end_point)

func check_laser_damage():
	if not laser_ray.is_colliding(): return
	var collider = laser_ray.get_collider()
	if collider and collider.is_in_group("player"):
		if collider.has_method("take_damage"):
			collider.take_damage(laser_damage)

func hit_player(player):
	if player.has_method("take_damage"):
		player.take_damage(20) 
		var knock_dir = (player.global_position - global_position).normalized()
		player.velocity += knock_dir * 1000 
		get_tree().call_group("camera", "add_shake", 0.5)

func take_damage(amount):
	if current_state == State.DYING: return
	hp -= amount
	health_bar.value = hp
	if popup_scene:
		var popup = popup_scene.instantiate()
		get_parent().add_child(popup)
		popup.global_position = global_position + Vector2(0, -50)
		popup.setup(str(amount), Color(1, 0.8, 0))
	if hp <= 0:
		change_state(State.DYING)

func die_sequence():
	health_bar.visible = false
	Engine.time_scale = 0.5
	for i in range(10):
		var ex = explosion_scene.instantiate()
		get_parent().add_child(ex)
		ex.global_position = global_position + Vector2(randf_range(-50,50), randf_range(-50,50))
		await get_tree().create_timer(0.2).timeout
	Engine.time_scale = 1.0
	queue_free()
