extends BossPattern

## A wall of bullets with one gap in it, fired across the arena.
##
## The pattern that tests reading rather than reacting. Every other attack
## arrives at the player; this one demands the player look at where the boss is
## and work out where it is *not*. There is exactly one safe column, it moves
## between sweeps, and a player who does not look walks into it.
##
## That makes it the pattern the arena is really for. The fan and the spiral
## punish reflexes; this one punishes not looking, which is the failure mode a
## parry-only player actually has.

## Columns of bullets in the wall. Each is a full-height column, so the gap is
## `gap_width` columns wide and the player has to be inside it.
@export_range(4, 40, 1) var columns: int = 16
## Columns left open, centred on a random position.
@export_range(1, 8, 1) var gap_width: int = 2
## Seconds between sweeps. The gap moves each time, so holding one spot fails.
@export var sweep_interval: float = 1.4
## Seconds of wind-up before the first wall, with the gap briefly telegraphed.
@export var wind_up: float = 0.6
## How long before the second wall the gap is hinted at, so the player has a
## chance to commit to a column rather than reacting to a wall.
@export var hint_time: float = 0.45
## Bullets fired in a vertical stack per column. One per column is a clean
## line; more makes a wall the player cannot stand between.
@export_range(1, 5, 1) var rows: int = 1
## Phase two narrows the gap, which is the one number that makes this pattern
## genuinely mean something later.
@export var phase_two_gap_width: int = 1

var _next_sweep: float = 0.0
var _sweeps: int = 0
var _gap_start: int = 0


func begin(owning_boss: Boss) -> void:
	super.begin(owning_boss)
	_next_sweep = wind_up
	_pick_gap()


func tick(delta: float) -> void:
	super.tick(delta)
	while elapsed >= _next_sweep:
		_emit_wall()
		_sweeps += 1
		_next_sweep += sweep_interval


func _emit_wall() -> void:
	if _bullet_scene() == null or boss == null:
		return

	var width := gap_width
	if boss.is_phase_two:
		width = max(1, phase_two_gap_width)

	# Lay the wall across the whole arena, not just the camera's current view of
	# it: a wall that only covers what happens to be on screen is a wall the
	# player can walk around the edge of, which reads as the attack missing.
	# ArenaBounds is a Node2D, so the rect comes from rect() rather than off the
	# node's own position/size.
	var bounds := boss.arena()
	var r: Rect2
	if bounds != null:
		r = bounds.rect()
	else:
		# No arena on this boss. Fall back to a wall straddling the boss, so the
		# pattern still does something legible instead of erroring out.
		r = Rect2(boss.global_position - Vector2(560, 300), Vector2(1120, 600))

	var left := r.position.x
	var step := r.size.x / float(columns)

	for c in columns:
		# The gap is a contiguous run of columns starting at _gap_start.
		if c >= _gap_start and c < _gap_start + width:
			continue
		var x := left + (float(c) + 0.5) * step
		for row in rows:
			# Straddle the wall's midpoint, so a multi-row wall is a band across
			# the middle rather than a stack hanging off the ceiling.
			var offset := float(row) - (float(rows) - 1.0) * 0.5
			var y := (r.position.y + r.size.y * 0.5) + offset * 90.0
			_fire_from(Vector2(x, y), Vector2.UP)

	_pick_gap()


## Fire from a world point rather than from the boss, since a wall is not
## something the boss shoots out of its own body.
func _fire_from(at: Vector2, direction: Vector2) -> void:
	boss.spawn_bullet_at(at, direction.normalized())


func _pick_gap() -> void:
	var width := gap_width
	if boss != null and boss.is_phase_two:
		width = max(1, phase_two_gap_width)
	# Biased away from the edges so the safe column is reachable rather than
	# jammed in a corner the player has to cross the whole wall to reach.
	var lo := 0
	var hi := maxi(0, columns - width)
	_gap_start = randi_range(lo, hi) if hi > lo else 0
