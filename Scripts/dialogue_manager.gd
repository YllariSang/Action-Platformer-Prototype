extends Node

var dialogue_bubble_scene = preload("uid://diqkeglblx2wv")
var is_dialogue_active = false
var current_bubble = null

signal dialogue_finished

# Data format: [{"name": "Clef", "text": "Hello!", "node": player_node}, ...]
var dialogue_queue = [] 

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

func start_dialogue(lines: Array):
	if is_dialogue_active: return
	
	is_dialogue_active = true
	dialogue_queue = lines
	
	# Pause the game logic (optional, depends on preference)
	get_tree().paused = true
	
	show_next_line()

func show_next_line():
	if dialogue_queue.size() == 0:
		end_dialogue()
		return
	
	var line_data = dialogue_queue.pop_front()
	
	# Clean up old bubble if it exists to spawn a new one 
	# (Or keep the same one and move it if you prefer)
	if current_bubble:
		current_bubble.queue_free()
	
	# Spawn new bubble
	current_bubble = dialogue_bubble_scene.instantiate()
	
	# Add to the highest canvas layer or the current scene
	# Adding to 'Window' ensures it's on top of everything
	get_tree().root.add_child(current_bubble)
	
	# Determine position (default to player if no node provided)
	var target_pos = Vector2.ZERO
	if line_data.has("node") and is_instance_valid(line_data["node"]):
		target_pos = line_data["node"].global_position
	
	current_bubble.show_message(line_data["name"], line_data["text"], target_pos)

func _input(event):
	if not is_dialogue_active: return
	
	# Advance on "Jump" or "Interact"
	if event.is_action_pressed("jump") or event.is_action_pressed("attack"):
		if current_bubble and current_bubble.text_label.visible_ratio < 1.0:
			# If text is still typing, skip to end
			current_bubble.text_label.visible_ratio = 1.0
			current_bubble.next_indicator.visible = true
		else:
			# If text is done, go to next line
			show_next_line()

func end_dialogue():
	is_dialogue_active = false
	get_tree().paused = false
	if current_bubble:
		current_bubble.close()
		current_bubble = null
	emit_signal("dialogue_finished")
