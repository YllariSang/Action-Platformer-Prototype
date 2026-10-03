extends BossPattern

## A rotating radial burst. The prototype's SPIRAL state, as a pattern.
##
## The version this replaces fired on `Engine.get_physics_frames() % 5`, which is
## a wall-clock timer: the pattern kept its firing rate while a parry hit-stop
## had the rest of the world nearly frozen, so the boss spat bullets into a
## stopped screen. Accumulating `elapsed` in `tick` instead means the burst
## slows with the world.

## Radians per second the firing line sweeps.
@export var rotation_speed: float = 5.0
## Phase-two value. Above 1 turns the sweep into a readable spin instead of a
## blur, which is the point of speeding a pattern up rather than just adding
## more of it.
@export var phase_two_rotation_speed: float = 15.0
## Seconds between volleys.
@export var fire_interval: float = 0.2
@export var phase_two_fire_interval: float = 0.14
## Bullets per volley, spread evenly around the circle. Two gives the classic
## two-armed cross; more turns it into a rotating star.
@export_range(1, 12, 1) var bullets_per_volley: int = 2
## Rounds of lead-in before the first volley, so the pattern announces itself.
@export var wind_up: float = 0.3
## Exact volley counts avoid a final burst landing on the same frame as the
## duration timeout and make the pattern's rhythm independent of frame rate.
@export_range(1, 30, 1) var max_volleys: int = 10
@export_range(1, 30, 1) var phase_two_max_volleys: int = 13

var _next_fire: float = 0.0
var _speed: float = 0.0
var _interval: float = 0.2
var _max_volleys: int = 10
var _volleys_fired: int = 0
## Angle the next volley is centred on. Advanced every frame rather than only on
## volley frames, so the pattern reads as a continuous spin and not a stutter.
var _fire_angle: float = 0.0


func begin(owning_boss: Boss) -> void:
	super.begin(owning_boss)
	_speed = rotation_speed
	_interval = fire_interval
	_max_volleys = max_volleys
	if boss != null and boss.is_phase_two:
		_speed = phase_two_rotation_speed
		_interval = phase_two_fire_interval
		_max_volleys = phase_two_max_volleys
	_next_fire = wind_up


func tick(delta: float) -> void:
	super.tick(delta)
	# Rotate the line continuously, not only on volley frames, or the whole
	# pattern reads as a stutter rather than a spin.
	_fire_angle += _speed * delta

	if elapsed < wind_up:
		return
	while elapsed >= _next_fire:
		_emit_volley()
		_volleys_fired += 1
		if _volleys_fired >= _max_volleys:
			finish()
			return
		_next_fire += _interval


func _emit_volley() -> void:
	if _bullet_scene() == null:
		return
	_attack_pulse(0.22)
	var step := TAU / float(bullets_per_volley)
	for i in bullets_per_volley:
		_fire(_dir(_fire_angle + step * i))
