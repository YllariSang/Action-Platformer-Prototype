extends Label

## A world-space caption for the template areas.
##
## Zones in a test area are only useful if you can tell where you are without
## stopping to look, and a plain Label over a dark placeholder background is
## close to invisible. This applies the same treatment the HUD already uses for
## its own readouts — outlined text — so the captions are legible against
## whatever is behind them, and ignores mouse input so a caption can never
## swallow the click the player is aiming with.

@export var caption_color: Color = Color(0.75, 0.82, 0.95)
@export var caption_size: int = 16


func _ready() -> void:
	# Set here rather than per-instance in the .tscn: the point is that a new
	# zone is one Label with some text, not six lines of theme overrides.
	add_theme_color_override("font_color", caption_color)
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	add_theme_constant_override("outline_size", 6)
	add_theme_font_size_override("font_size", caption_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
