extends Area2D

var explosion_scene = preload("res://Scenes/explosion.tscn")

var speed = 400
var damage = 1
var direction = Vector2.RIGHT
var is_reflected = false 

## Seconds before this bullet gives up and frees itself.
##
## Exported rather than hardcoded because range is a weapon property. Boss
## patterns currently keep the readable five-second default; a future pattern
## may override it, but must do so before the bullet enters the tree.
@export var lifetime: float = 5.0

func _ready():
	add_to_group("enemy")
	await get_tree().create_timer(lifetime).timeout
	queue_free()

func _physics_process(delta):
	position += direction * speed * delta
	rotation = direction.angle()

# --- COLLISION LOGIC ---
func _on_body_entered(body):
	# Hitting Player (Normal Behavior)
	if body.name == "Player":
		if not is_reflected:
			# A parry in progress is a hard immunity, but the parry box is
			# directional: it only catches what comes from the way the player is
			# facing. Without this, a bullet that slipped past the box would be
			# consumed on the player's body while their guard was still up. Skip
			# the player entirely and leave the bullet alive, so it can still be
			# reflected a frame later instead of being silently eaten.
			if body.has_method("is_parrying") and body.is_parrying():
				return
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

	# Hitting level geometry. Production levels use TileMapLayer; the reusable
	# boss arena and test lab deliberately use StaticBody2D platform rigs. Treat
	# both as walls so cover and arena boundaries behave the same in either scene.
	if body is TileMapLayer or body is StaticBody2D:
		spawn_pop()
		queue_free()

# Handle hitting the Dummy
func _on_area_entered(area):
	if not is_reflected: return # The player's parry box handles the un-reflected case
	
	if area.has_method("take_damage"):
		area.take_damage(5) 
		queue_free()
		return
	
	var parent = area.get_parent()
	if parent and parent.has_method("take_damage"):
		parent.take_damage(5)
		queue_free()

# --- REFLECTION LOGIC ---
func get_parried(should_reflect = false):
	if is_reflected: return 
	
	if should_reflect:
		# --- FULL SPARK: REFLECT! ---
		is_reflected = true
		direction = -direction 
		speed *= 2.0 
		modulate = Color(0, 1, 1) # Cyan
		scale *= 1.5
		print("Bullet Reflected (Full Spark Bonus!)")
		
	else:
		# --- NOT FULL: JUST DESTROY ---
		spawn_pop()
		queue_free()

func spawn_pop():
	if explosion_scene:
		var ex = explosion_scene.instantiate()
		get_parent().add_child(ex)
		ex.global_position = global_position
		ex.scale = Vector2(0.5, 0.5) # Smaller explosion for bullets
