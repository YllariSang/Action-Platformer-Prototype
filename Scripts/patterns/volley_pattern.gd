extends BossPattern

## Single shots at a deliberate, readable cadence.
##
## This is the pattern that actually teaches the parry. The spiral and the fan
## both present several threats at once, so a player learns to flinch rather
## than to time. One bullet, a visible gap, then the next: the player can count
## it, which is exactly the skill the parry needs. If a template arena is going
## to have a "parry practice" zone, this is the pattern that belongs there.

## Seconds between shots. Long enough to parry one, react, and re-set the guard.
@export var shot_interval: float = 0.85
## Phase-two value, which is the number to tune if phase two reads as no worse
## than phase one.
@export var phase_two_shot_interval: float = 0.55
## Pause after the first shot, so the opening is always a free one. It gives the
## player a beat to read the tint change before the rhythm starts.
@export var lead_in: float = 0.5
## Bullets per shot. Stays at 1 on purpose: a second bullet turns this back into
## a parry-or-dodge scramble.
@export_range(1, 3, 1) var shots: int = 1
## Fan width in radians when shots is above 1.
@export var spread: float = 0.12
## A count makes the cadence a learnable phrase rather than "shots until an
## unrelated duration happens to expire".
@export_range(1, 12, 1) var max_volleys: int = 4
@export_range(1, 12, 1) var phase_two_max_volleys: int = 6

var _next_shot: float = 0.0
var _interval: float = 0.85
var _volleys_fired: int = 0
var _max_volleys: int = 4


func begin(owning_boss: Boss) -> void:
	super.begin(owning_boss)
	_interval = shot_interval
	_max_volleys = max_volleys
	if boss != null and boss.is_phase_two:
		_interval = phase_two_shot_interval
		_max_volleys = phase_two_max_volleys
	_next_shot = lead_in


func tick(delta: float) -> void:
	super.tick(delta)
	# Fire on every elapsed threshold in one go, then catch up. Without the
	# while-loop a frame hitch would silently drop a shot and break the
	# rhythm this pattern exists to establish.
	while elapsed >= _next_shot:
		_emit_shot()
		_volleys_fired += 1
		if _volleys_fired >= _max_volleys:
			finish()
			return
		_next_shot += _interval


func _emit_shot() -> void:
	if _bullet_scene() == null:
		return
	_attack_pulse(0.32)
	var aim := _angle_to_player()
	if shots <= 1:
		_fire(_dir(aim))
		return
	var step := spread * 2.0 / float(shots - 1)
	for i in shots:
		_fire(_dir(aim - spread + step * i))
