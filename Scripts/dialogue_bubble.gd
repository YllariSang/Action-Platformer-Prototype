extends Control

signal message_completed

@onready var text_label = $BubbleBackground/RichTextLabel
@onready var name_label = $NameContainer/NameLabel
@onready var bubble_bg = $BubbleBackground
@onready var next_indicator = $BubbleBackground/NextIndicator

var tween: Tween

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	scale = Vector2.ZERO # Start hidden
	next_indicator.visible = false

func show_message(character_name: String, text: String, target_position: Vector2):
	# 1. Position the bubble above the target (offset y by -100 or so)
	global_position = target_position + Vector2(0, -120)
	
	# 2. Setup content
	name_label.text = character_name
	text_label.text = text
	text_label.visible_ratio = 0.0 # Reset typewriter
	next_indicator.visible = false
	
	# 3. Animate Pop-in (Elastic effect for that Persona feel)
	if scale == Vector2.ZERO:
		tween = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "scale", Vector2(1, 1), 0.5)
	
	# 4. Start Typewriter Effect
	var duration = text.length() * 0.03 # 0.03 seconds per character
	var type_tween = create_tween()
	type_tween.tween_property(text_label, "visible_ratio", 1.0, duration)
	
	await type_tween.finished
	next_indicator.visible = true # Show the "A" prompt
	emit_signal("message_completed")

func close():
	var close_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	close_tween.tween_property(self, "scale", Vector2.ZERO, 0.2)
	await close_tween.finished
	queue_free()
