class_name ArenaBounds
extends Node2D

## The rectangle a boss is allowed to occupy.
##
## The prototype boss carried `limit_left` / `limit_right` / `limit_top` /
## `limit_bottom` as four exported numbers that every scene had to override by
## hand. Nothing stopped those being set to a box larger than the room the boss
## actually sat in, and moving the arena meant editing the boss. One exported
## size, positioned by this node, cannot disagree with itself: the arena moves
## and the boss follows.

## Full width and height of the fight area, centred on this node.
@export var size: Vector2 = Vector2(1400, 700)

## Keep the boss this far inside the edge. A boss sitting flush against a wall
## telegraphs its own back corner, which makes the fight read as broken rather
## than hard.
@export var edge_clearance: float = 90.0

## How far the boss may stray outside the arena before it gives up and walks
## back. The boss is deliberately NOT leashed by the player the way the regular
## enemies are — it is a set piece — but "leashed by the map" is different, and
## without it a player who sprints out of the room can simply never be reached.
@export var despawn_margin: float = 2400.0


## The arena as a world-space rect.
func rect() -> Rect2:
	return Rect2(global_position - size * 0.5, size)


## A random point inside the arena, at least `clearance` away from `avoid`.
##
## The avoidance is what stops a teleport landing the boss inside the player,
## which is a cheap way to make a fight feel unfair. It retries a few times
## rather than solving exactly: a boss that is briefly cornered is a fine
## outcome, a boss that teleports onto the player's face is not.
func random_point(avoid: Vector2 = Vector2.INF, clearance: float = 0.0) -> Vector2:
	var r := rect().grow(-edge_clearance)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return global_position

	var fallback := Vector2.ZERO
	for attempt in 12:
		var p := Vector2(
			randf_range(r.position.x, r.end.x),
			randf_range(r.position.y, r.end.y)
		)
		if attempt == 0:
			fallback = p
		if clearance <= 0.0 or not avoid.is_finite():
			return p
		if p.distance_to(avoid) >= clearance:
			return p

	# Could not find a clearing point. Take a legal point anyway rather than
	# stalling the fight waiting for a spot that may not exist.
	return fallback


## True when `point` has wandered further than `despawn_margin` from the arena
## centre, which is the signal to give up a chase and go home.
func is_stranded(point: Vector2) -> bool:
	return point.distance_to(global_position) > despawn_margin
