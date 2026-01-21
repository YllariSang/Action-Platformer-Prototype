extends "res://Scripts/enemy_bullet.gd"

# INCREASED FORCE: From 50.0 to 1500.0 for snappy turning
@export var steer_force: float = 1500.0
@export var homing_speed: float = 350.0

var target: Node2D = null
var velocity_vector: Vector2 = Vector2.ZERO

func _ready() -> void:
	if has_method("_ready"): 
		super()
	# Initialize velocity in the direction we were spawned facing
	velocity_vector = transform.x * homing_speed

func _physics_process(delta: float) -> void:
	if target:
		# 1. Calculate where we want to go (Desired Velocity)
		var desired = (target.global_position - global_position).normalized() * homing_speed
		
		# 2. Calculate the difference (Steering)
		# We use 'limit_length' instead of 'normalized' to prevent jitter when perfectly aligned
		var steer = (desired - velocity_vector).limit_length(steer_force * delta)
		
		# 3. Apply Steering
		velocity_vector += steer
		velocity_vector = velocity_vector.limit_length(homing_speed)
		
		# 4. Update Rotation to face movement
		rotation = velocity_vector.angle()
	
	position += velocity_vector * delta
