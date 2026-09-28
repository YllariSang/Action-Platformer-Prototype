extends CharacterBody2D

enum State { CHASE, PREPARE, DASH, STUNNED }
var current_state = State.CHASE

@export var speed = 150.0
@export var dash_speed = 600.0
@export var damage = 10
@export var gravity = 980.0

@export var max_hp: int = 30 # Example value
@export var windup_duration: float = 0.5
@export var dash_duration: float = 0.3
@export var stun_duration: float = 2.0
@export var parry_knockback: float = 300.0
var hp: int

## Base tint. Kept as a named constant so a flash can be layered on top of it
## without permanently overwriting the colour.
const NORMAL_TINT := Color(1, 0, 0.1)
const STUN_TINT := Color(0, 0, 1)

var player_ref = null
var popup_scene = preload("res://Scenes/popup.tscn")
@onready var hitbox = $Hitbox
@onready var sprite = $Sprite2D

func _ready():
	
	hp = max_hp
	
	add_to_group("enemy")
	player_ref = get_tree().get_first_node_in_group("player")
	SpriteFeedback.attach(sprite)
	
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
	
	# 1. Telegraph (flash white, then settle back to the red tint)
	SpriteFeedback.flash(sprite, Color.WHITE, 0.9, 0.25)
	SpriteFeedback.set_tint(sprite, NORMAL_TINT)
	
	await get_tree().create_timer(windup_duration).timeout
	if current_state != State.PREPARE: return # Stopped if died/stunned
	
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
	SpriteFeedback.set_tint(sprite, STUN_TINT) # Turn Blue
	# A short flash on top sells the impact without wiping the blue.
	SpriteFeedback.flash(sprite, Color(1, 1, 1), 1.0, 0.15)
	velocity.x = -sign(velocity.x) * parry_knockback # Knockback
	
	# Stun duration
	await get_tree().create_timer(stun_duration).timeout
	if not is_instance_valid(self): return # Killed while stunned
	
	SpriteFeedback.clear(sprite)
	SpriteFeedback.set_tint(sprite, NORMAL_TINT) # Reset Color
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
