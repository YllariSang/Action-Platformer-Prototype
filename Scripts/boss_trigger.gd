extends Area2D

@export var boss_node: CharacterBody2D 

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body.name == "Player":
		# Define the conversation
		var conversation = [
			{
				"name": "Clef", 
				"text": "Wait... [wave]do you hear that?[/wave]", 
				"node": body # Attach bubble to Player
			},
			{
				"name": "Boss", 
				"text": "[shake level=20]Who dares enter my domain?![/shake]", 
				"node": boss_node # Attach bubble to Boss
			},
			{
				"name": "Clef", 
				"text": "It's like if you have huge swords and try to look at your feet.", 
				"node": body
			}
		]
		
		
		# Original logic
		if boss_node and boss_node.has_method("start_fight"):
			# Wait for dialogue to finish before starting fight?
			# You can add a signal to DialogueManager for "dialogue_finished"
			boss_node.start_fight()
			
		queue_free()
