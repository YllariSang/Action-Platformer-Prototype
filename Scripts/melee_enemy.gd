extends CharacterBody2D

enum State { CHASE, PREPARE, DASH, STUNNED }
var current_state = State.CHASE

@export var speed = 150.0
@export var dash_speed = 600.0
@export var damage = 10
@export var gravity = 980.0

@export var max_hp: int = 30 # Example value
var hp: int

var player_ref = null
var popup_scene = preload("res://Scenes/popup.tscn")
@onready var hitbox = $Hitbox
@onready var sprite = $Sprite2D

func _ready():
	
	hp = max_hp
	
	add_to_group("enemy")
	player_ref = get_tree().get_first_node_in_group("player")
	
	# Setup Hitbox (Make sure it knows who owns it for parrying)
	hitbox.body_entered.connect(_on_hitbox_entered)
	hitbox.add_to_group("enemy_attack") 
	hitbox.set_meta("parent_node", self) # Crucial for parry logic
	hitbox.monitoring = false # Only dangerous when dashing

func _physics_process(delta):
	if not is_on_floor():
		velocity.y += gravity * delta

	match current_state:
		State.CHASE:
			if player_ref:
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

func start_dash_attack():
	current_state = State.PREPARE
	
	# 1. Telegraph (Flash White)
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(10, 10, 10), 0.2)
	tween.tween_property(sprite, "modulate", Color(1, 0, 0), 0.2)
	
	await get_tree().create_timer(0.5).timeout
	if current_state != State.PREPARE: return # Stopped if died/stunned
	
	# 2. Dash!
	current_state = State.DASH
	var dir = -1 if sprite.flip_h else 1
	velocity.x = dir * dash_speed
	hitbox.monitoring = true # Enable Hitbox
	
	await get_tree().create_timer(0.3).timeout
	
	# 3. Recovery
	hitbox.monitoring = false
	if current_state == State.DASH:
		current_state = State.CHASE

# --- PARRY LOGIC ---
func get_parried(is_full_spark):
	print("Enemy Parried!")
	hitbox.set_deferred("monitoring", false)
	current_state = State.STUNNED
	sprite.modulate = Color(0, 0, 1)
	await get_tree().create_timer(2.0).timeout
	sprite.modulate = Color(1, 0, 0.1)
	current_state = State.CHASE

func _on_hitbox_entered(body):
	if body.is_in_group("player") and body.has_method("take_damage"):
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
	if sprite:
		# Flash White
		sprite.modulate = Color(10, 10, 10)
		var tween = create_tween()
		# Return to Normal Red Color
		tween.tween_property(sprite, "modulate", Color(1, 0, 0.1), 0.1)
	
	# 3. Death Logic
	if hp <= 0:
		die()

func die():
	# Optional: Add explosion here later
	queue_free()
