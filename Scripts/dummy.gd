extends Node2D

## Training dummy. Exists to be shot and parried, so its feedback doubles as a
## readable reference for how a parry feels.

@onready var sprite = $Sprite2D
@onready var attack_area = $AttackArea
@onready var attack_timer = $AttackTimer

var popup_scene = preload("res://Scenes/popup.tscn")

const NORMAL_TINT := Color(1, 0.4, 0.4)
const WARNING_TINT := Color(1, 1, 0)
const PARRIED_TINT := Color(0, 0, 1)

@export var warning_time: float = 0.5
@export var strike_time: float = 0.2

func _ready():
	add_to_group("enemy")
	if not attack_timer.timeout.is_connected(_on_attack_timer_timeout):
		attack_timer.timeout.connect(_on_attack_timer_timeout)
	attack_area.monitoring = false
	attack_area.monitorable = false
	SpriteFeedback.attach(sprite)
	
	# IMPORTANT: Add the area to a group so the Player can identify it as an "EnemyAttack"
	attack_area.add_to_group("enemy_attack")
	# Store a reference to the parent (Dummy) in the Area so we can call functions on it
	attack_area.set_meta("parent_node", self)

func take_damage(amount: int):
	var popup = popup_scene.instantiate()
	add_child(popup)
	popup.setup(str(amount), Color(1, 0.5, 0))
	
	# Flash on top of the current tint rather than replacing it, so getting shot
	# while a swing is telegraphing does not wipe the warning colour.
	SpriteFeedback.flash(sprite, Color.WHITE, 1.0, 0.1)

# --- NEW FUNCTION called by Player on Parry ---
func get_parried(_should_reflect = false):
	print("Dummy got Parried! Attack cancelled.")
	attack_area.set_deferred("monitorable", false)
	SpriteFeedback.set_tint(sprite, PARRIED_TINT)
	attack_timer.stop() # The cancelled swing must not come back on its own

# -----------------------------------------------

func _on_attack_timer_timeout():
	SpriteFeedback.set_tint(sprite, WARNING_TINT) # Yellow Warning
	await get_tree().create_timer(warning_time).timeout
	if not is_instance_valid(self): return
	
	SpriteFeedback.set_tint(sprite, NORMAL_TINT)
	SpriteFeedback.flash(sprite, Color.WHITE, 1.0, strike_time) # Strike tell
	attack_area.monitorable = true 
	
	await get_tree().create_timer(strike_time).timeout
	if not is_instance_valid(self): return
	
	attack_area.monitorable = false
	SpriteFeedback.set_tint(sprite, NORMAL_TINT)
	attack_timer.start() # Only rearm if the swing actually completed
