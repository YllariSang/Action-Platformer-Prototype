extends Area2D

var speed = 800
var damage = 15
var direction = Vector2.ZERO

func _ready():
	if direction != Vector2.ZERO:
		rotation = direction.angle()
	
	# Connect signals
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
	await get_tree().create_timer(2.0).timeout
	queue_free()

func _physics_process(delta):
	position += direction * speed * delta

# Handle hitting Walls/Floors (TileMap)
func _on_body_entered(body):
	if body.name == "Player": return 
		
	if body.has_method("take_damage"):
		body.take_damage(damage)
		# REDUCED: 0.02 prevents motion sickness on rapid fire
		get_tree().call_group("camera", "add_shake", 0.02) 
		queue_free()
	else:
		queue_free()

# Handle hitting Enemies (Areas)
func _on_area_entered(area):
	# Ignore the Player's own Parry Box
	var parent = area.get_parent()
	if parent and parent.is_in_group("player"):
		return
		
	# Direct Hit (e.g. Enemy Hitbox)
	if area.has_method("take_damage"):
		area.take_damage(damage)
		get_tree().call_group("camera", "add_shake", 0.02)
		queue_free()
		return
		
	# Parent Hit (e.g. Dummy/Boss parts)
	if parent and parent.has_method("take_damage"):
		parent.take_damage(damage)
		get_tree().call_group("camera", "add_shake", 0.02)
		queue_free()
