extends Camera2D

# Config
@export var decay = 0.8
@export var max_offset = Vector2(20, 10) # Tighter shake
@export var max_roll = 0.1
@export var follow_speed = 5.0 # How fast it pans to the target

# Shake Variables
var trauma = 0.0
var trauma_power = 2
var noise = FastNoiseLite.new()
var noise_y = 0

# Target Logic
var target_node: Node2D = null

func _ready():
	randomize()
	noise.seed = randi()
	noise.frequency = 0.5
	add_to_group("camera")
	
	# DETACH from Player to move freely
	top_level = true
	# Default target is the parent (The Player)
	target_node = get_parent()

func _process(delta):
	# 1. FOLLOW TARGET (Smooth Pan)
	if target_node:
		global_position = global_position.lerp(target_node.global_position, follow_speed * delta)
	
	# 2. SHAKE LOGIC
	if trauma:
		trauma = max(trauma - decay * delta, 0)
		shake()

func change_target(new_target: Node2D):
	target_node = new_target

func return_to_player():
	# Assuming the camera started as a child of the Player
	target_node = get_parent()

func add_shake(amount):
	trauma = min(trauma + amount, 1.0)

func shake():
	var amount = pow(trauma, trauma_power)
	noise_y += 1
	rotation = max_roll * amount * noise.get_noise_2d(0, noise_y)
	offset.x = max_offset.x * amount * noise.get_noise_2d(100, noise_y)
	offset.y = max_offset.y * amount * noise.get_noise_2d(200, noise_y)
