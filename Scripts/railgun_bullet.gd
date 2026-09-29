extends Area2D

var speed = 2000 
## Weapon damage is not in HP units, it is in Spark-efficiency units: 60 damage
## for 3 Sparks is 20 per Spark, against 15 for a normal shot.
##
## This used to be 45, which was exactly 15 per Spark as well, so three normal
## shots cost the same Sparks for the same damage. The railgun was strictly
## dominated and there was no reason to ever hold the charge.
var damage = 60
## How many targets one shot goes through before it burns out. Bounded on
## purpose: an unlimited railgun deletes a whole room for a single charge, and
## this is the knob to turn if it ever needs rebalancing.
@export var pierce_count: int = 3

var direction = Vector2.RIGHT
## Targets this shot has already connected with, keyed by instance id.
##
## `body_entered` fires once per body, so this is not about a single pass. An
## enemy usually has both a body *and* a child hurtbox overlapping, and both
## resolve to the same victim, so without this one enemy would eat two of the
## pierce charges and the counter would be a lie.
var _hit_targets: Dictionary = {}
var _pierces_left: int = 0

var explosion_scene = preload("res://Scenes/explosion.tscn")

func _ready():
	rotation = direction.angle()
	_pierces_left = pierce_count
	get_tree().call_group("camera", "add_shake", 0.3)
	
	# body_entered is already wired in railgun_bullet.tscn; area_entered is not,
	# and the railgun needs it to reach Area2D targets (hurtboxes, hitboxes).
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	
	await get_tree().create_timer(1.0).timeout
	queue_free()

func _physics_process(delta):
	position += direction * speed * delta

func _on_body_entered(body):
	if body.name == "Player": return
	
	# HIT WALL (TileMap). A wall still stops the shot, unlike an enemy.
	if body is TileMapLayer:
		# FIX: Spawn explosion on wall hit!
		spawn_hit_effect(global_position)
		queue_free()
		return
	
	_try_pierce(body)

func _on_area_entered(area):
	# Ignore Player
	var parent = area.get_parent()
	if parent and parent.is_in_group("player"):
		return
	
	# Resolve to whoever actually takes the damage *before* the dedup check, so a
	# child hurtbox and its parent body count as the one target they really are.
	if area.has_method("take_damage"):
		_try_pierce(area)
	elif parent and parent.has_method("take_damage"):
		_try_pierce(parent)

## Pay for one target out of the pierce budget, then stop once it is spent.
func _try_pierce(target: Node) -> void:
	if target == null or not is_instance_valid(target): return
	if not target.has_method("take_damage"): return
	
	var id := target.get_instance_id()
	if _hit_targets.has(id): return
	_hit_targets[id] = true
	
	target.take_damage(damage)
	# FIX: Spawn explosion at the BULLET's position, not the enemy's feet
	spawn_hit_effect(global_position)
	
	_pierces_left -= 1
	if _pierces_left <= 0:
		queue_free()

func spawn_hit_effect(pos):
	if explosion_scene:
		var ex = explosion_scene.instantiate()
		get_parent().add_child(ex)
		ex.global_position = pos
