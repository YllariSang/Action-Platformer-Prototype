extends Area2D

var speed = 400
var damage = 1
var direction = Vector2.RIGHT
var is_reflected = false 

func _ready():
	await get_tree().create_timer(5.0).timeout
	queue_free()

func _physics_process(delta):
	position += direction * speed * delta
	rotation = direction.angle()

# --- COLLISION LOGIC ---
func _on_body_entered(body):
	# Hitting Player (Normal Behavior)
	if body.name == "Player":
		if not is_reflected:
			if body.has_method("take_damage"):
				body.take_damage(damage)
			queue_free()
		return # If reflected, ignore player!

	# 2. Hitting Boss (Reflected Behavior)
	if is_reflected and body.is_in_group("enemy"):
		if body.has_method("take_damage"):
			body.take_damage(5) 
			spawn_pop()
			queue_free()
		return

	# Hitting Walls
	if body is TileMapLayer:
		spawn_pop()
		queue_free()

# Handle hitting the Dummy
func _on_area_entered(area):
	if is_reflected:
		if area.has_method("take_damage"):
			area.take_damage(5) 
			queue_free()
		elif area.get_parent().has_method("take_damage"):
			area.get_parent().take_damage(5)
			queue_free()

# --- REFLECTION LOGIC ---
func get_parried(should_reflect = false):
	if is_reflected: return 
	
	if should_reflect:
		is_reflected = true
		direction = -direction 
		speed *= 2.0 
		modulate = Color(0, 1, 1) # Cyan
		scale *= 1.5
		
		# --- THE FIX ---
		# Enable detection of Layer 3 (Enemies). 
		# Value 4 represents Bit 3.
		# We use the bitwise OR operator (|) to add it to the existing mask.
		collision_mask = collision_mask | 4 
		
		print("Bullet Reflected (Full Spark Bonus!)")
		
	else:
		spawn_pop()
		queue_free()

func spawn_pop():
	pass
