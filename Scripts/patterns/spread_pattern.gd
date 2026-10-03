extends BossPattern

## An aimed fan of bullets, re-aimed at the player on every volley.
##
## The prototype's SHOTGUN state, as a pattern. Its important property is that it
## aims at where the player is *at the moment of firing*, so walking sideways
## during the wind-up genuinely dodges it. That makes it the pattern that tests
## whether a player can parry under pressure rather than just hold a direction.

## Bullets in the fan, including the centre one. Five is a readable wall.
@export_range(1, 13, 2) var shots: int = 5
## Radians between adjacent shots. Wider spreads cover more ground and give the
## player more to read.
@export var spread: float = 0.2
## Seconds of wind-up before the first volley, and the player sees the boss
## change tint for it.
@export var wind_up: float = 0.45
## Seconds between volleys. Zero means a single volley and the pattern is over.
@export var volley_interval: float = 0.0
## How many volleys to fire at most, so a pattern with a non-zero interval
## cannot run forever by accident.
@export var max_volleys: int = 1
## Phase two fires the fan twice as tightly, which reads as "more bullets in
## the same cone" rather than a harder pattern to read.
@export var phase_two_spread: float = 0.12

var _volleys_fired: int = 0
var _next_volley: float = 0.0
var _spread: float = 0.2


func begin(owning_boss: Boss) -> void:
	super.begin(owning_boss)
	_spread = spread
	if boss != null and boss.is_phase_two:
		_spread = phase_two_spread
	_next_volley = wind_up


func tick(delta: float) -> void:
	super.tick(delta)
	if _volleys_fired >= max_volleys:
		return

	while elapsed >= _next_volley:
		_emit_volley()
		_volleys_fired += 1
		if _volleys_fired >= max_volleys:
			finish()
			return
		if volley_interval <= 0.0:
			finish()
			return
		_next_volley += volley_interval


func _emit_volley() -> void:
	if _bullet_scene() == null:
		return
	_attack_pulse(0.38)
	# Re-aim per volley, not once at begin(): that is the whole reason this
	# pattern is a dodge test rather than a static cone.
	var aim := _angle_to_player()
	var step := _spread
	if shots > 1:
		step = _spread * 2.0 / float(shots - 1)
	var first := aim - _spread
	for i in shots:
		_fire(_dir(first + step * i))
