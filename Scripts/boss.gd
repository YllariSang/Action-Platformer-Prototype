extends CharacterBody2D

@export var max_hp: int = 500
@export var bullet_scene: PackedScene 

# --- ROOM BOUNDARIES ---
@export_group("Room Limits")
@export var limit_left: float = -500.0
@export var limit_right: float = 500.0
@export var limit_top: float = -500.0
@export var limit_bottom: float = 0.0

@onready var state_timer = $StateTimer
@onready var health_bar = $CanvasLayer/HealthBar 
@onready var sprite = $Sprite2D

var popup_scene = preload("res://Scenes/popup.tscn")
# 1. PRELOAD EXPLOSION
var explosion_scene = preload("res://Scenes/explosion.tscn")

# 2. ADD "DYING" STATE
enum State { INACTIVE, INTRO, IDLE, SPIRAL, SHOTGUN, TIRED, TELEPORT, DYING } 
var current_state = State.INACTIVE
var hp = 0
var spiral_angle = 0.0
var player_ref = null
var is_phase_two = false

func _ready():
	hp = max_hp
	add_to_group("enemy") 
	player_ref = get_tree().get_first_node_in_group("player")
	state_timer.timeout.connect(_on_state_timer_timeout)
	
	health_bar.max_value = max_hp
	health_bar.value = hp
	health_bar.visible = false 
	
	# --- COLLISION FIX ---
	# Ensure boss hits Walls (1) but NOT Player (2)
	collision_layer = 4 # Enemy Layer (Bit 3)
	collision_mask = 1  # Wall Layer (Bit 1)
	
	change_state(State.INACTIVE)

func start_fight():
	if current_state == State.INACTIVE:
		change_state(State.INTRO)

func _physics_process(delta):
	# 1. Soft Collision (Force Push)
	if current_state != State.DYING and current_state != State.INACTIVE and player_ref:
		var dist = global_position.distance_to(player_ref.global_position)
		if dist < 100.0: 
			var push_dir = (player_ref.global_position - global_position).normalized()
			# CHANGE: Modify global_position directly to override player input
			player_ref.global_position += push_dir * 400 * delta
			
	match current_state:
		State.SPIRAL: process_spiral(delta)
		State.SHOTGUN: process_shotgun()


func change_state(new_state):
	# 1. GUARD CLAUSE: If we are dead, IGNORE all other orders.
	# This stops the Teleport logic from reviving the boss.
	if current_state == State.DYING:
		return
		
	current_state = new_state
	
	var time_mult = 0.5 if is_phase_two else 1.0
	
	match new_state:
		State.INACTIVE:
			sprite.modulate = Color(0.2, 0.2, 0.2)
			state_timer.stop()
		State.INTRO:
			get_tree().call_group("camera", "change_target", self)
			sprite.modulate = Color(1, 1, 1) 
			await get_tree().create_timer(2.0).timeout
			health_bar.visible = true
			get_tree().call_group("camera", "return_to_player")
			change_state(State.IDLE)
		State.IDLE:
			sprite.modulate = Color(1, 0.2, 0.2) if is_phase_two else Color(0.5, 0, 0.5)
			state_timer.start(1.0 * time_mult)
		State.SPIRAL:
			sprite.modulate = Color(1, 0, 1)
			state_timer.start(4.0 * time_mult) 
		State.SHOTGUN:
			sprite.modulate = Color(1, 0.5, 0) 
			state_timer.start(3.0 * time_mult)
		State.TIRED:
			sprite.modulate = Color(0.5, 0.5, 0.5) 
			state_timer.start(2.0 * time_mult)
		State.TELEPORT:
			# 2. Add checks inside the tweens
			var tween_out = create_tween()
			tween_out.tween_property(sprite, "modulate:a", 0.0, 0.3)
			await tween_out.finished
			
			if current_state == State.DYING: return # STOP if died during fade out

			var rand_x = randf_range(limit_left, limit_right)
			var rand_y = randf_range(limit_top, limit_bottom)
			global_position = Vector2(rand_x, rand_y)
			
			var tween_in = create_tween()
			tween_in.tween_property(sprite, "modulate:a", 1.0, 0.3)
			await tween_in.finished
			
			if current_state == State.DYING: return # STOP if died during fade in

			change_state(State.IDLE)
			
		State.DYING:
			state_timer.stop()
			sprite.modulate = Color(0.3, 0.3, 0.3)

func _on_state_timer_timeout():
	match current_state:
		State.IDLE:
			var roll = randi() % 2
			change_state(State.SPIRAL if roll == 0 else State.SHOTGUN)
		State.SPIRAL, State.SHOTGUN:
			change_state(State.TIRED)
		State.TIRED:
			change_state(State.TELEPORT)

# --- ATTACK PATTERNS ---
func process_spiral(delta):
	var rotation_speed = 15.0 if is_phase_two else 5.0
	spiral_angle += rotation_speed * delta
	if Engine.get_physics_frames() % 5 == 0:
		spawn_bullet(Vector2.RIGHT.rotated(spiral_angle))
		spawn_bullet(Vector2.RIGHT.rotated(spiral_angle + PI)) 

func process_shotgun():
	var fire_rate = 15 if is_phase_two else 30
	if Engine.get_physics_frames() % fire_rate == 0:
		if player_ref:
			var dir = (player_ref.global_position - global_position).normalized()
			var angle = dir.angle()
			for i in range(-2, 3):
				spawn_bullet(Vector2.RIGHT.rotated(angle + (i * 0.2)))

func spawn_bullet(direction_vec):
	if bullet_scene:
		var b = bullet_scene.instantiate()
		get_parent().add_child(b)
		b.global_position = global_position
		b.direction = direction_vec
		b.rotation = direction_vec.angle()

# --- DAMAGE LOGIC ---
func take_damage(amount):
	if current_state == State.DYING: return # Don't hurt him if he's already dead
	
	hp -= amount
	health_bar.value = hp
	
	if hp <= (max_hp / 2) and not is_phase_two:
		start_phase_two()
	
	if sprite.modulate.a > 0.5 and not is_phase_two:
		sprite.modulate = Color(10, 10, 10) 
		var tween = create_tween()
		tween.tween_property(sprite, "modulate", get_state_color(), 0.1)
	
	if popup_scene:
		var popup = popup_scene.instantiate()
		get_parent().add_child(popup)
		var rand_x = randf_range(-20, 20)
		popup.global_position = global_position + Vector2(rand_x, -50)
		var color = Color(1, 0.2, 0.2) if amount >= 40 else Color(1, 0.6, 0)
		popup.setup(str(amount), color)
	
	if hp <= 0:
		die()

func start_phase_two():
	is_phase_two = true
	print("PHASE 2 STARTED!")
	if popup_scene:
		var popup = popup_scene.instantiate()
		get_parent().add_child(popup)
		popup.global_position = global_position + Vector2(0, -80)
		popup.setup("ENRAGED!", Color(1, 0, 0))
		popup.scale = Vector2(2, 2)
	
	sprite.modulate = Color(1, 0.2, 0.2) 
	change_state(State.TELEPORT) 

func get_state_color():
	if is_phase_two: return Color(1, 0.2, 0.2)
	match current_state:
		State.TIRED: return Color(0.5, 0.5, 0.5)
		State.SPIRAL: return Color(1, 0, 1)
		_: return Color(0.5, 0, 0.5)

# --- 4. NEW DEATH SEQUENCE ---
# Inside Scripts/boss.gd

func die():
	if current_state == State.DYING: return 
	
	print("BOSS DEFEATED - Starting Cinematic")
	change_state(State.DYING) 
	
	# Force visibility in case he died while teleporting
	sprite.modulate.a = 1.0 
	health_bar.visible = false 
	
	# 1. Focus Camera on Boss for the finale
	get_tree().call_group("camera", "change_target", self)
	
	# 2. Slow Motion Explosions
	Engine.time_scale = 0.5
	
	for i in range(15):
		var rand_offset = Vector2(randf_range(-60, 60), randf_range(-60, 60))
		spawn_explosion(global_position + rand_offset)
		get_tree().call_group("camera", "add_shake", 0.4) 
		await get_tree().create_timer(0.15).timeout
	
	# 3. Restore Speed & Big Bang
	Engine.time_scale = 1.0
	
	spawn_explosion(global_position)
	spawn_explosion(global_position + Vector2(20, -20))
	spawn_explosion(global_position + Vector2(-20, 20))
	get_tree().call_group("camera", "add_shake", 1.0)
	
	await get_tree().create_timer(1.0).timeout
	
	# 4. Show Win Screen
	var win_screen = get_tree().get_first_node_in_group("win_screen")
	if win_screen:
		win_screen.show_win()
	
	# --- THE FIX ---
	# Tell camera to look at player again BEFORE we delete the boss!
	get_tree().call_group("camera", "return_to_player")
	# ---------------
	
	queue_free()

func spawn_explosion(pos):
	if explosion_scene:
		var ex = explosion_scene.instantiate()
		get_parent().add_child(ex)
		ex.global_position = pos
