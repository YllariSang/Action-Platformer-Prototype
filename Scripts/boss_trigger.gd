extends Area2D

@export var boss_node: CharacterBody2D # Drag the Boss here

func _ready():
	# Connect the signal via code or editor
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body.name == "Player":
		if boss_node and boss_node.has_method("start_fight"):
			boss_node.start_fight()
			
			# Optional: Lock the room?
			# spawn_walls() 
			
			# Destroy this trigger so it doesn't trigger twice
			queue_free()
