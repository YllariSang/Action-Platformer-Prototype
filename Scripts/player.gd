extends CharacterBody2D

# --- CONFIGURATION ---
@export_category("Combat")
@export var bullet_scene: PackedScene 
@export var railgun_scene: PackedScene 
@export var max_ammo: int = 6
@export var start_ammo: int = 0
@export var parry_duration: float = 0.2 
@export var parry_cooldown: float = 0.8 
@export var parry_success_cooldown: float = 0.1 

@export_category("Movement")
@export var speed: float = 300.0
@export var jump_force: float = -600.0
@export var gravity: float = 1500.0
@export var dash_speed: float = 1000.0
@export var max_jumps: int = 2
@export var wall_jump_push: float = 500.0
@export var wall_slide_speed: float = 100.0
@export var recoil_force: float = 900.0 
@export var coyote_time: float = 0.15 

# --- STATE MACHINE ---
enum State { IDLE, RUN, ATTACK, PARRY, DASH, STUNNED, RECOVERY }
var current_state = State.IDLE
var current_ammo: int = 0
var facing_direction: int = 1
var can_parry: bool = true 
var jump_count: int = 0
var can_dash: bool = true
var coyote_timer: float = 0.0 

# Charging Variables
var charge_timer: float = 0.0
var is_charging: bool = false
var railgun_cost: int = 3

# --- NODES ---
@onready var parry_box: Area2D = $ParryBox
@onready var parry_timer: Timer = $ParryTimer
@onready var cooldown_timer: Timer = $ParryCooldownTimer
@onready var dash_timer: Timer = $DashTimer
@onready var sprite: Sprite2D = $Sprite2D

# Use Unique Name to find the label inside the container
@onready var label_ammo = %AmmoLabel 
@onready var ui_container = $UI/SkewContainer

var ui_origin_pos = Vector2.ZERO
var ui_time = 0.0

var popup_scene = preload("res://Scenes/popup.tscn")

func _ready() -> void:
	# --- COLLISION FIX ---
	# Disable Mask 3 (Enemy Layer) so Player doesn't get stuck on bosses
	# Assuming Layer 3 is Enemy. Value 4 = Bit 3.
	set_collision_mask_value(3, false)
	
	current_ammo = start_ammo
	ui_origin_pos = ui_container.position 
	update_ui()
	parry_box.monitoring = false 
	parry_box.monitorable = false
	
	if not dash_timer.timeout.is_connected(_on_dash_timer_timeout):
		dash_timer.timeout.connect(_on_dash_timer_timeout)

func _process(delta: float) -> void:
	# UI FLOATING EFFECT (Bobbing up and down)
	ui_time += delta * 5.0 
	var bob_offset = sin(ui_time) * 5.0 
	ui_container.position.y = ui_origin_pos.y + bob_offset

func _physics_process(delta: float) -> void:
	if current_state == State.STUNNED: return
	
	#COYOTE TIME & GRAVITY
	if is_on_floor():
		coyote_timer = coyote_time
		jump_count = 0
		can_dash = true 
	else:
		coyote_timer -= delta
		if current_state != State.DASH:
			if is_on_wall() and velocity.y > 0:
				velocity.y = wall_slide_speed
				can_dash = true 
			else:
				velocity.y += gravity * delta

	#MOVEMENT
	if current_state != State.DASH and current_state != State.PARRY:
		handle_movement_and_jumps()
	
	move_and_slide()
	
	#AIMING
	parry_box.look_at(get_global_mouse_position())
	
	#ACTIONS
	handle_attack_input(delta)
	
	if Input.is_action_just_pressed("parry"):
		try_to_parry()
	elif Input.is_action_just_pressed("dash"):
		try_to_dash()

# --- MOVEMENT LOGIC ---
func handle_movement_and_jumps():
	var input_dir = Input.get_axis("left", "right")
	
	var current_speed = speed
	if current_state == State.RECOVERY:
		current_speed = speed * 0.5 
	
	if input_dir:
		velocity.x = input_dir * current_speed
		facing_direction = sign(input_dir)
		sprite.flip_h = (input_dir < 0)
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)

	if Input.is_action_just_pressed("jump"):
		if current_state == State.RECOVERY and is_on_floor(): return

		# Wall Jump
		if is_on_wall() and not is_on_floor():
			velocity.y = jump_force
			velocity.x = -facing_direction * wall_jump_push 
			jump_count = 1 
			can_dash = true 
			
		# Normal Jump (Coyote)
		elif coyote_timer > 0:
			velocity.y = jump_force
			jump_count = 1
			coyote_timer = 0
			
		# Double Jump
		elif jump_count < max_jumps:
			velocity.y = jump_force
			jump_count += 1

# --- CHARGE & ATTACK LOGIC ---
func handle_attack_input(delta):
	if current_state == State.PARRY or current_state == State.DASH or current_state == State.RECOVERY:
		is_charging = false
		return

	if Input.is_action_pressed("attack"):
		is_charging = true
		charge_timer += delta
		if charge_timer >= 1.0:
			sprite.modulate = Color(0, 10, 10) # Cyan Glow
		elif charge_timer > 0.1:
			sprite.modulate = Color(1, 1, 1).lerp(Color(0, 1, 1), charge_timer)
			
	elif Input.is_action_just_released("attack"):
		is_charging = false
		sprite.modulate = Color(1, 1, 1)
		
		if charge_timer >= 1.0:
			fire_railgun()
		else:
			fire_normal_shot()
		charge_timer = 0.0

func fire_normal_shot():
	if current_ammo > 0:
		spawn_bullet(bullet_scene, 1, 0.2)
		current_ammo -= 1
		update_ui()
	else:
		spawn_popup("NO AMMO!", Color(0.5, 0.5, 0.5))

func fire_railgun():
	if current_ammo >= railgun_cost:
		spawn_bullet(railgun_scene, 2.0, 0.5) 
		current_ammo -= railgun_cost
		update_ui()
		spawn_popup("RAILGUN!", Color(0, 1, 1))
	else:
		spawn_popup("NEED 3 SPARKS!", Color(1, 0, 0))
		fire_normal_shot()

func spawn_bullet(scene_to_spawn, shake_amount, recoil_mult):
	if not scene_to_spawn: return
	
	current_state = State.ATTACK
	
	var mouse_pos = get_global_mouse_position()
	var dir_vec = (mouse_pos - global_position).normalized()
	
	var b = scene_to_spawn.instantiate()
	get_parent().add_child(b)
	b.global_position = global_position + (dir_vec * 60) 
	b.direction = dir_vec
	
	# Recoil Logic
	velocity -= dir_vec * recoil_force * recoil_mult
	get_tree().call_group("camera", "add_shake", shake_amount)

	# Recovery Delay
	await get_tree().create_timer(0.1).timeout
	if current_state == State.ATTACK:
		current_state = State.IDLE

# --- DASH & PARRY LOGIC ---

func try_to_dash():
	if not can_dash or current_state == State.PARRY or current_state == State.RECOVERY: return
	
	current_state = State.DASH
	can_dash = false 
	
	var input_dir = Input.get_axis("left", "right")
	var dash_dir = input_dir if input_dir != 0 else facing_direction
	
	velocity.y = 0 
	velocity.x = dash_dir * dash_speed
	sprite.modulate.a = 0.5
	dash_timer.start()

func _on_dash_timer_timeout():
	if current_state == State.DASH:
		current_state = State.IDLE
	velocity.x = 0
	sprite.modulate.a = 1.0 

func try_to_parry():
	if current_state != State.IDLE and current_state != State.RUN: return
	if not can_parry: return 
	
	current_state = State.PARRY
	velocity.x = 0
	velocity.y = 0 
	can_parry = false 
	
	parry_box.monitoring = true
	parry_timer.start(parry_duration)
	cooldown_timer.start(parry_duration + parry_cooldown)

func _on_parry_box_area_entered(area: Area2D) -> void:
	if current_state == State.PARRY:
		if not area.is_in_group("enemy_attack"):
			return
		
		cooldown_timer.start(parry_success_cooldown)
		spawn_popup("PARRIED!", Color(0, 1, 1))
		get_tree().call_group("camera", "add_shake", 0.5)
		
		# Full Spark Condition
		var is_full_spark = (current_ammo == max_ammo)
		
		# Refill Ammo
		current_ammo = min(current_ammo + 2, max_ammo)
		update_ui()
		
		shake_ui()
		
		frame_freeze(0.1, 0.05)
		
		if area.has_method("get_parried"):
			area.get_parried(is_full_spark)
		elif area.has_meta("parent_node"):
			var enemy = area.get_meta("parent_node")
			if enemy.has_method("get_parried"):
				enemy.get_parried(is_full_spark)
		
		parry_box.set_deferred("monitoring", false) 
		current_state = State.IDLE

func _on_parry_timer_timeout() -> void:
	parry_box.monitoring = false
	if current_state == State.PARRY:
		current_state = State.RECOVERY
		sprite.modulate = Color(0.5, 0.5, 0.8) # Vulnerable Color

func _on_parry_cooldown_timer_timeout() -> void:
	can_parry = true
	if current_state == State.RECOVERY:
		current_state = State.IDLE
		sprite.modulate = Color(1, 1, 1)

# --- HELPERS ---

func take_damage(amount: int):
	if current_state == State.DASH:
		print("Dodged with I-Frames!")
		return 
	
	if current_state == State.RECOVERY:
		amount *= 2 
		
	print("Ouch! Took", amount, "damage")
	get_tree().call_group("camera", "add_shake", 0.3)

func update_ui():
	# Update the text of the Unique Node
	label_ammo.text = "SPARKS: %s / %s" % [current_ammo, max_ammo]

func frame_freeze(time_scale, duration):
	Engine.time_scale = time_scale
	await get_tree().create_timer(duration * time_scale).timeout
	Engine.time_scale = 1.0

func spawn_popup(text, color):
	var popup = popup_scene.instantiate()
	add_child(popup)
	popup.setup(text, color)

func shake_ui():
	var tween = create_tween()
	
	#Flash Cyan
	label_ammo.modulate = Color(0, 1, 1) 
	
	#Scale Pulse (Punch effect) on the container
	tween.set_parallel(true)
	tween.tween_property(ui_container, "scale", Vector2(1.2, 1.2), 0.05)
	
	#Shake Position
	for i in range(5):
		var offset = Vector2(randf_range(-8, 8), randf_range(-8, 8))
		tween.tween_property(ui_container, "position", ui_origin_pos + offset, 0.05)
	
	#Return to normal
	tween.chain().tween_property(ui_container, "scale", Vector2(1.0, 1.0), 0.1)
	tween.tween_property(label_ammo, "modulate", Color(1, 1, 1), 0.2)
	tween.tween_property(ui_container, "position", ui_origin_pos, 0.1)

func on_parry_success():
	# Reset parry window
	cooldown_timer.start(parry_success_cooldown)
	spawn_popup("PARRIED!", Color(0, 1, 1))
	get_tree().call_group("camera", "add_shake", 0.5)
	
	# Refill Ammo
	current_ammo = min(current_ammo + 2, max_ammo)
	update_ui()
	shake_ui()
	frame_freeze(0.1, 0.05)
	
	# Close the parry box immediately
	parry_box.set_deferred("monitoring", false) 
	current_state = State.IDLE
