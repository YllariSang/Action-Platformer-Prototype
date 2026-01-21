extends Node2D

@onready var sprite = $Sprite2D
@onready var attack_area = $AttackArea
@onready var attack_timer = $AttackTimer

var popup_scene = preload("res://Scenes//popup.tscn")

func _ready():
	attack_timer.timeout.connect(_on_attack_timer_timeout)
	attack_area.monitoring = false
	attack_area.monitorable = false
	
	# IMPORTANT: Add the area to a group so the Player can identify it as an "EnemyAttack"
	attack_area.add_to_group("enemy_attack")
	# Store a reference to the parent (Dummy) in the Area so we can call functions on it
	attack_area.set_meta("parent_node", self)

func take_damage(amount: int):
	var popup = popup_scene.instantiate()
	add_child(popup)
	popup.setup(str(amount), Color(1, 0.5, 0))
	
	# Simple Flash
	sprite.modulate = Color(10, 10, 10)
	await get_tree().create_timer(0.1).timeout
	sprite.modulate = Color(1, 0.4, 0.4) # Return to normal redish

# --- NEW FUNCTION called by Player on Parry ---
func get_parried(_should_reflect = false):
	print("Dummy got Parried! Attack cancelled.")
	attack_area.set_deferred("monitorable", false)
	sprite.modulate = Color(0, 0, 1)
	
# -----------------------------------------------

func _on_attack_timer_timeout():
	sprite.modulate = Color(1, 1, 0) # Yellow Warning
	await get_tree().create_timer(0.5).timeout
	
	sprite.modulate = Color(10, 10, 10) # White Flash
	attack_area.monitorable = true 
	
	await get_tree().create_timer(0.2).timeout
	
	attack_area.monitorable = false
	sprite.modulate = Color(1, 0, 0)
