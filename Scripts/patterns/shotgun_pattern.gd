extends BossPattern

## A wide cone of pellets, fired in quick succession.
##
## The boss's answer to the player closing on it. It is distinguished from
## `spread_pattern` by being a *volume* rather than a line: many more pellets,
## a much wider cone, fired three times in a row, each one re-aimed. Every other
## pattern is a bullet you dodge one at a time; this is a wall you have to be
## somewhere else when it lands, and it is at its worst when you are standing
## next to the boss doing nothing.
##
## The pellets are slower than the boss's other bullets, which is what makes the
## cone readable as a cone rather than as a wall of individually-tracked dots.
## They are deliberately given **no lifetime override**: an earlier version cut
## them short to imply a range limit, and pellets visibly stopping dead in mid-air
## read as a bug rather than as a weapon. If this ever wants a range, widen the
## cone or slow the pellets, do not make them evaporate.

## Pellets in one blast, including the centre one. Nine is a cone with holes in
## it; more stops reading as a shotgun and starts reading as a spiral.
@export_range(3, 15, 2) var pellets: int = 9
## Half-angle of the cone in radians. 0.55 is about 63 degrees end to end, which
## at arm's length is wider than the player can see past.
@export var spread: float = 0.55
## Random jitter added to each pellet's angle, in radians. Without it the pellets
## land on exact spokes and read as a laser fan rather than buckshot.
@export var jitter: float = 0.05
## Multiplier on bullet speed. Below 1 on purpose: see the note at the top.
@export var pellet_speed_mult: float = 0.85
## Seconds of wind-up before the first blast. Short: a shotgun blast is not a
## charge, and the telegraph here is the widening of the gap between blasts.
@export var wind_up: float = 0.28
## Seconds between blasts.
@export var volley_interval: float = 0.5
## Blasts per use, so the pattern cannot run forever by accident.
@export_range(1, 8, 1) var max_volleys: int = 3
## Phase two adds pellets rather than tightening the cone, because a tighter cone
## at close range is unhittable rather than harder.
@export var phase_two_pellets: int = 13
## Phase two shortens the gap between blasts instead of the reach, so the player
## is pressured to move rather than to hope.
@export var phase_two_volley_interval: float = 0.32

var _volleys_fired: int = 0
var _next_volley: float = 0.0
var _pellets: int = 9
var _interval: float = 0.5


func begin(owning_boss: Boss) -> void:
	super.begin(owning_boss)
	_pellets = pellets
	_interval = volley_interval
	if boss != null and boss.is_phase_two:
		_pellets = phase_two_pellets
		_interval = phase_two_volley_interval
	_next_volley = wind_up


func tick(delta: float) -> void:
	super.tick(delta)
	if _volleys_fired >= max_volleys:
		return
	while elapsed >= _next_volley:
		_emit_blast()
		_volleys_fired += 1
		if _volleys_fired >= max_volleys:
			finish()
			return
		_next_volley += _interval


func _emit_blast() -> void:
	if _bullet_scene() == null or boss == null:
		return
	_attack_pulse(0.55)
	# Re-aimed per blast, for the same reason the fan re-aims: a cone locked to
	# where the player was at the start of the pattern is a wall to walk around,
	# not a shotgun to dodge.
	var aim := _angle_to_player()
	var step := 0.0
	if _pellets > 1:
		step = spread * 2.0 / float(_pellets - 1)
	var first := aim - spread
	for i in _pellets:
		var angle := first + step * i
		if jitter > 0.0:
			angle += randf_range(-jitter, jitter)
		_fire(_dir(angle))


## Its own slower pellets, which is the whole reason this pattern overrides the
## shared helper: the speed is the weapon's character. It calls the boss directly
## rather than extending `BossPattern._fire`, because there is no lifetime to
## pass any more and adding an argument every other pattern would ignore is a
## worse API than one honest override.
func _fire(direction: Vector2, speed_mult: float = 1.0) -> void:
	if boss != null:
		boss.spawn_bullet(direction.normalized(), pellet_speed_mult, 0.0, _bullet_scene())
