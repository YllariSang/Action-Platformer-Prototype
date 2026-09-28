extends CanvasLayer

## End-of-run screen, used for both outcomes.
## The boss calls show_result(true) when it dies; the player calls it with
## false from die(). Both land here so there is only one restart flow.

@onready var panel: Control = $Panel
@onready var title: Label = $Panel/Title
@onready var subtitle: Label = $Panel/Subtitle
@onready var stats: Label = $Panel/Stats
@onready var restart_button: Button = $Panel/RestartButton

@export var fade_in_time: float = 0.6

var is_shown := false
var has_won := false


func _ready() -> void:
	add_to_group("result_screen")
	visible = false
	panel.modulate.a = 0.0
	title.pivot_offset = title.size * 0.5
	restart_button.pressed.connect(_on_restart_pressed)


func show_result(won: bool) -> void:
	if is_shown: return
	is_shown = true
	has_won = won
	visible = true

	# Hide the in-game HUD so only the result numbers are on screen.
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var hud = player.get_node_or_null("UI")
		if hud: hud.visible = false

	if won:
		title.text = "BOSS DEFEATED"
		title.add_theme_color_override("font_color", Color(0, 1, 1, 1))
		subtitle.text = "The arena falls silent."
	else:
		title.text = "YOU DIED"
		title.add_theme_color_override("font_color", Color(1, 0.25, 0.25, 1))
		subtitle.text = "The parry is the only way back."
	
	stats.text = _build_stats(won)
	restart_button.grab_focus()

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, fade_in_time)
	tween.tween_property(title, "scale", Vector2.ONE, 0.4) \
		.from(Vector2(1.6, 1.6)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Safety net so the button always ends up keyboard-reachable.
	var guard = get_tree().create_timer(0.5, true, false, true)
	guard.timeout.connect(func():
		if is_shown and not restart_button.has_focus():
			restart_button.grab_focus()
	)


func _build_stats(won: bool) -> String:
	var player = get_tree().get_first_node_in_group("player")
	if not player: return ""
	
	var sparks: int = player.current_ammo
	var max_sparks: int = player.max_ammo
	
	if won:
		return "Sparks remaining: %d/%d" % [sparks, max_sparks]
	
	var hp: int = player.hp
	return "Sparks remaining: %d/%d" % [sparks, max_sparks]


func _unhandled_input(event: InputEvent) -> void:
	if not is_shown: return
	if event.is_action_pressed("restart") or event.is_action_pressed("ui_accept"):
		_on_restart_pressed()


func _on_restart_pressed() -> void:
	if not is_shown: return
	# A death or death cinematic may still be holding slow motion; clear it so
	# the reloaded level starts at normal speed.
	TimeControl.reset()
	get_tree().paused = false
	get_tree().reload_current_scene()
