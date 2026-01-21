extends Area2D

var speed = 2000 
var damage = 45
var direction = Vector2.RIGHT

var explosion_scene = preload("res://Scenes/explosion.tscn")

func _ready():
	# CHANGE: Force mask to see Enemies
	collision_mask = 5
	
	rotation = direction.angle()
	get_tree().call_group("camera", "add_shake", 0.3)
	
	await get_tree().create_timer(1.0).timeout
	queue_free()

func _physics_process(delta):
	position += direction * speed * delta

func _on_body_entered(body):
	if body.name == "Player": return
	
	# HIT ENEMY
	if body.has_method("take_damage"):
		body.take_damage(damage)
		# FIX: Spawn explosion at the BULLET'S position, not the enemy's feet
		spawn_hit_effect(global_position) 
	
	# HIT WALL (TileMap)
	elif body is TileMapLayer:
		# FIX: Spawn explosion on wall hit!
		spawn_hit_effect(global_position)
		queue_free()

func _on_area_entered(area):
	# Ignore Player
	var parent = area.get_parent()
	if parent and parent.is_in_group("player"):
		return

	if area.has_method("take_damage"):
		area.take_damage(damage)
		spawn_hit_effect(global_position)
	elif parent and parent.has_method("take_damage"):
		parent.take_damage(damage)
		spawn_hit_effect(global_position)

func spawn_hit_effect(pos):
	if explosion_scene:
		var ex = explosion_scene.instantiate()
		get_parent().add_child(ex)
		ex.global_position = pos
