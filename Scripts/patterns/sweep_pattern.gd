extends BossPattern

## A curtain of bullets that crosses the arena from one side to the other.
##
## The version this replaces laid a wall of columns standing still at the
## arena's vertical midpoint, with every bullet travelling UP. That made it
## close to useless rather than merely easy: a player standing on the floor is
## below the wall, and the wall only ever moved further away from them, so the
## only player it could hit was one who had climbed above mid-height — which is
## the last place anyone wants to be. The gap it offered was horizontal, in a
## wall that was never going to reach the player standing on the ground.
##
## This is a curtain instead: a full-height block that enters from one side and
## travels to the other, with a gap left in it. The player is in its path, so
## the answer is to move, and because the side alternates, camping on the side it
## came from stops working after the first one. The gap is what makes it
## readable rather than a wall of pure denial — it is roughly three player
## heights tall, so it can be found and stood in, if committing to a spot is
## cheaper than running.

## The player's own height, and the top of the arena rect. Together they are the
## only two numbers that decide whether the curtain can reach anyone, and getting
## them wrong makes the whole pattern silently useless — see the note on
## `floor_lane_index`. 64 is the player's collision box, not its sprite.
@export var player_height: float = 64.0
## How far from the arena's bottom edge the lowest lane is placed. The lane has
## to sit where a player standing on the arena's floor actually is: their box
## occupies `rect.end.y - player_height .. rect.end.y`. Centring the lowest lane
## in that band is what makes the curtain threaten the ground rather than pass
## harmlessly underneath everyone.
@export var floor_lane_inset: float = 34.0
## Height of one lane, as a target. The lane count is rounded to a whole number
## and the spacing follows, because a gap of "2.3 lanes" is not a thing.
@export var lane_target: float = 100.0
## Height of the safe lane, in pixels. Two to three player heights: findable,
## and standing still in one is a commitment.
@export var gap_size: float = 200.0
## How many columns deep the curtain is. One is a line with a hole in it; two is
## a wall, and reads as an approaching threat rather than a shower.
@export_range(1, 4, 1) var thickness: int = 2
## Horizontal gap between those columns.
@export var column_spacing: float = 55.0
## Seconds between curtains. Firing one before the last has left the arena is
## what turns a series of dodges into a sweep.
@export var sweep_interval: float = 0.9
## Seconds of wind-up before the first curtain.
@export var wind_up: float = 0.3
## Multiplier on bullet speed, because a curtain has to cross the whole arena
## and would otherwise take longer to arrive than the pattern is interesting for.
@export var travel_speed_mult: float = 1.5
## Enter from the other side each time. This is the difference between a sweep
## and a one-way push: with it on, the player is pinched from both sides and
## eventually has to use the gap or the dash.
@export var alternate_sides: bool = true
## Phase two closes the gap, which is the one number that makes this pattern
## genuinely mean something later.
@export var phase_two_gap_size: float = 110.0
@export_range(1, 8, 1) var max_curtains: int = 3
@export_range(1, 8, 1) var phase_two_max_curtains: int = 4

## Cached from the arena on the first curtain, since the arena cannot change size
## mid-fight and reading it every emission is waste.
var _lanes: int = 7
var _spacing: float = 100.0
var _gap: int = 2
## World y of the lane a grounded player occupies, and its index in the stack.
var _floor_y: float = 0.0
var _floor_lane: int = 0
var _next_sweep: float = 0.0
var _gap_start: int = 0
var _from_left: bool = true
var _curtains_fired: int = 0
var _max_curtains: int = 3


func begin(owning_boss: Boss) -> void:
	super.begin(owning_boss)
	_next_sweep = wind_up
	_measure_room()
	_max_curtains = phase_two_max_curtains if boss != null and boss.is_phase_two else max_curtains
	_report_if_unreachable()
	_pick_gap()


## Warn once per pattern if no lane is anywhere near the player.
##
## This failure is completely silent — the pattern fires, the bullets fly, and
## they pass through a band of level nobody is standing in — and it reads from
## the outside as a pattern that "does not hit". That is how the sweep was
## reported broken twice before anyone checked where its lanes actually were. A
## warning costs nothing when the pattern is working and saves an afternoon when
## it is not.
func _report_if_unreachable() -> void:
	if boss == null or not boss.is_instance_valid_player():
		return
	# Every lane, not just the floor lane: the player may be on a ledge, and the
	# question is whether the curtain covers where the fight is, not where the
	# floor is.
	var closest := INF
	for i in _lanes:
		closest = minf(closest, absf(_lane_y(i) - boss.player_position().y))
	if closest > 96.0 + maxf(player_height, 1.0):
		push_warning("Sweep: its lanes never come near the player. Arena %s, lanes span y %s..%s, closest is %s px from the player at %s. The curtain cannot hit anyone — check the Arena node against where the fight actually happens."
			% [_arena_rect(), _lane_y(_lanes - 1), _lane_y(0), snappedf(closest, 1.0), boss.player_position()])



func tick(delta: float) -> void:
	super.tick(delta)
	while elapsed >= _next_sweep:
		_emit_curtain()
		_curtains_fired += 1
		if _curtains_fired >= _max_curtains:
			finish()
			return
		_next_sweep += sweep_interval


func _emit_curtain() -> void:
	if _bullet_scene() == null or boss == null:
		return
	_attack_pulse(0.45)

	var r := _arena_rect()
	var travel := Vector2.RIGHT if _from_left else Vector2.LEFT
	for i in _lanes:
		if i >= _gap_start and i < _gap_start + _gap:
			continue
		var y := _lane_y(i)
		# Columns are grouped at the entry edge rather than spread across the room,
		# so the curtain arrives as a wall instead of already surrounding the
		# player. Every column begins just inside the arena and the later columns
		# extend farther into it. A bullet born in the boundary wall is destroyed on
		# its first physics frame, so keeping the whole stack inside is load-bearing:
		# increasing thickness must add depth, not erase the leading columns.
		for c in thickness:
			var behind := float(c) * column_spacing
			var x := r.position.x + behind if _from_left else r.end.x - behind
			boss.spawn_bullet_at(Vector2(x, y), travel, travel_speed_mult, 0.0, _bullet_scene())

	if alternate_sides:
		_from_left = not _from_left
	_pick_gap()


## World y of lane `i`, measured up from the floor lane rather than down from the
## arena's top edge. See `_measure_room()` for why the bottom lane is the anchor.
func _lane_y(i: int) -> float:
	return _floor_y - float(i - _floor_lane) * _spacing


## Turn the arena's height into a whole number of lanes, a spacing, and a gap,
## and pin the lowest lane to the band a grounded player occupies.
##
## The bottom lane is the one that matters and the one that is easiest to get
## wrong. Measured on `main.tscn` with evenly spread lanes across its 337px-tall
## arena, the lanes landed at y = -881, -768 and -656 while a player standing on
## the level's real floor occupies y = -64..32. The nearest lane was **624px away
## from the player** — the curtain crossed a band of the level nobody stands on
## and the pattern could not hit anyone at all, which is exactly how it read.
##
## So the lowest lane is placed inside the player's own band rather than being
## left to whatever the even division happens to produce, and the rest are
## stacked upward from it at `spacing`.
func _measure_room() -> void:
	var r := _arena_rect()
	_spacing = maxf(lane_target, 1.0)
	_floor_y = r.end.y - floor_lane_inset
	# The floor lane is the anchor, and it is always lane 0, so the lanes stack
	# upward from where a grounded player is. The count is however many it takes
	# to reach the arena's ceiling at that spacing, with a floor of 3 so a short
	# room still gets a curtain rather than a single line.
	_floor_lane = 0
	_lanes = clampi(int((_floor_y - r.position.y) / _spacing) + 1, 3, 64)
	_gap = _gap_lanes()


## Where the lowest lane ended up, in world y. Exposed so this can be measured
## against the real level rather than assumed: a curtain whose lanes sit 600px
## from the player is not a hard pattern, it is a pattern that cannot hit anyone,
## and the only way to notice is to read the number.
func floor_lane_y() -> float:
	return _floor_y


func _gap_lanes() -> int:
	var want := phase_two_gap_size if (boss != null and boss.is_phase_two) else gap_size
	# Never eat the whole curtain, and always leave at least one lane of wall.
	return clampi(int(round(want / maxf(_spacing, 1.0))), 1, maxi(1, _lanes - 1))


## The rect to cover, from the arena when there is one. See the note in
## ArenaBounds about why a pattern reads the arena rather than the boss.
func _arena_rect() -> Rect2:
	var bounds := boss.arena()
	if bounds != null:
		return bounds.rect()
	# No arena on this boss. Fall back to a box straddling it, so the pattern
	# still does something legible instead of erroring out.
	return Rect2(boss.global_position - Vector2(700, 350), Vector2(1400, 700))


func _pick_gap() -> void:
	_gap = _gap_lanes()
	# Anywhere in the stack, including over the floor lane. Biasing the gap away
	# from the bottom (which an earlier version did) quietly removed the only lane
	# that can reach a grounded player on some room sizes, which is the same
	# "cannot hit anyone" failure wearing a different hat.
	var lo := 0
	var hi := maxi(0, _lanes - _gap)
	_gap_start = randi_range(lo, hi) if hi > lo else 0
