extends Marker2D

@onready var label = $Label

func setup(text_value: String, color: Color):
	label.text = text_value
	label.modulate = color
	
	# Float up and Fade out
	var tween = create_tween()
	tween.set_parallel(true) # Do both at the same time
	
	# Move up by X pixels over Y seconds
	tween.tween_property(self, "position", position + Vector2(0, -50), 0.8)
	# Fade opacity to X
	tween.tween_property(self, "modulate:a", 0.0, 0.8)
	
	# Delete self when done
	await tween.finished
	queue_free()
