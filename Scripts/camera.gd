extends Camera2D

# Config
@export var decay = 0.8
@export var max_offset = Vector2(20, 10) # Tighter shake
@export var max_roll = 0.1
@export var follow_speed = 5.0 # How fast it pans to the target

@export_group("Heal Focus")
## Multiplier applied to the camera's rest zoom while a heal channel is running.
## Camera2D.zoom is a scale where 1.0 is the authored framing and HIGHER is
## closer in, so anything above 1 pushes in. Expressed as a multiplier rather
## than an absolute Vector2 so it composes with whatever zoom the scene authored
## instead of overwriting it.
@export var heal_zoom_mult: float = 1.15
## How fast the camera walks toward whichever zoom is wanted. Slow on purpose:
## the channel is 0.6s, and the whole point is that the world closes in across
## that time rather than cutting to it. At this rate a full channel lands around
## 88% of the way before the release starts, so the player sees the move happen
## instead of arriving somewhere and having to work out how it got there.
@export var zoom_speed: float = 3.5

# Shake Variables
var trauma = 0.0
var trauma_power = 2
var noise = FastNoiseLite.new()
var noise_y = 0

# Target Logic
var target_node: Node2D = null

## Zoom the camera is heading for, and the zoom it returns to. Both are walked
## toward rather than assigned, so starting and ending a heal are the same kind
## of move.
var _zoom_target: Vector2 = Vector2.ONE
## Whatever zoom the scene shipped with, captured in _ready() so a designer can
## set zoom in the inspector without also having to keep an export in sync.
var _rest_zoom: Vector2 = Vector2.ONE

func _ready():
	randomize()
	noise.seed = randi()
	noise.frequency = 0.5
	add_to_group("camera")
	
	# DETACH from Player to move freely
	top_level = true
	# Default target is the parent (The Player)
	target_node = get_parent()
	_rest_zoom = zoom
	_zoom_target = zoom

func _process(delta):
	# 1. FOLLOW TARGET (Smooth Pan)
	if target_node:
		global_position = global_position.lerp(target_node.global_position, follow_speed * delta)
	
	# 2. HEAL FOCUS. Exponential smoothing rather than `lerp(a, b, speed * delta)`
	# like the pan above: that form is frame-rate dependent, so the zoom would
	# travel a different distance on a 144Hz monitor than on a 60Hz one. This
	# converges on the same curve at any tick rate.
	if not zoom.is_equal_approx(_zoom_target):
		zoom = zoom.lerp(_zoom_target, 1.0 - exp(-zoom_speed * delta))
	
	# 3. SHAKE LOGIC
	if trauma:
		trauma = max(trauma - decay * delta, 0)
		shake()

## Open or close the camera's heal focus. Called by the player when a heal
## channel starts and when it ends for any reason, so the camera always releases
## even if the channel was cancelled by a hit.
func set_heal_focus(active: bool):
	_zoom_target = _rest_zoom * (heal_zoom_mult if active else 1.0)

func change_target(new_target: Node2D):
	target_node = new_target

func return_to_player():
	# Assuming the camera started as a child of the Player
	target_node = get_parent()

func add_shake(amount):
	trauma = min(trauma + amount, 1.0)

func shake():
	var amount = pow(trauma, trauma_power)
	noise_y += 1
	rotation = max_roll * amount * noise.get_noise_2d(0, noise_y)
	offset.x = max_offset.x * amount * noise.get_noise_2d(100, noise_y)
	offset.y = max_offset.y * amount * noise.get_noise_2d(200, noise_y)
