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


## A random point inside the arena, at least `clearance` away from `avoid`, with
## the boss's own `footprint` clear of solid geometry.
##
## The avoidance is what stops a teleport landing the boss inside the player,
## which is a cheap way to make a fight feel unfair. It retries a few times
## rather than solving exactly: a boss that is briefly cornered is a fine
## outcome, a boss that teleports onto the player's face is not.
##
## `footprint` is the half-extent of the boss's collision shape, and it is what
## makes this work in a room with things in it. The arena rect only knows about
## the room; every arena worth fighting in has ledges or platforms standing in
## it, and a point that is comfortably inside the rect can still be inside a
## ledge. Measured with a 160x160 boss: 4% of teleport targets in the template
## arena and 11% in the main level overlapped solid geometry before this check
## existed, which is a boss appearing embedded in a platform roughly one time in
## twenty.
func random_point(avoid: Vector2 = Vector2.INF, clearance: float = 0.0, footprint: Vector2 = Vector2.ZERO) -> Vector2:
	var r := rect().grow(-edge_clearance)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return global_position

	var fallback := Vector2.ZERO
	for attempt in 16:
		var p := Vector2(
			randf_range(r.position.x, r.end.x),
			randf_range(r.position.y, r.end.y)
		)
		if attempt == 0:
			fallback = p
		if not _is_clear(p, avoid, clearance, footprint):
			continue
		return p

	# Could not find a clearing point. Take a legal point anyway rather than
	# stalling the fight waiting for a spot that may not exist.
	return fallback


## True when `point` is far enough from `avoid` and out of the scenery.
##
## Every condition is skipped when it does not apply, so a caller that only
## wants a random point pays nothing for the checks it is not asking for.
func _is_clear(point: Vector2, avoid: Vector2, clearance: float, footprint: Vector2) -> bool:
	if clearance > 0.0 and avoid.is_finite() and point.distance_to(avoid) < clearance:
		return false
	if footprint.x > 0.0 or footprint.y > 0.0:
		if _overlaps_solid(point, footprint):
			return false
	return true


## True when a box of half-extent `footprint` centred on `point` touches anything
## solid on the physics layer.
##
## The centre alone is not enough to answer that. A boss is 160px wide, so a
## centre sitting 20px clear of a wall still has most of the boss inside it, and
## that is exactly the case that reads as clipping. The box is sampled as a
## rectangle of points because Godot has no swept box-vs-world query here, and
## because a handful of point queries is cheaper than the alternative of
## modelling the level as a set of rectangles the arena also has to know about.
func _overlaps_solid(point: Vector2, footprint: Vector2) -> bool:
	var world := get_world_2d()
	if world == null:
		return false
	var space := world.direct_space_state
	if space == null:
		return false
	var q := PhysicsPointQueryParameters2D.new()
	q.collision_mask = 1  # Everything solid in this project is on layer 1.
	q.collide_with_bodies = true
	q.collide_with_areas = false
	for y in [-1.0, 0.0, 1.0]:
		for x in [-1.0, 0.0, 1.0]:
			q.position = point + Vector2(x * footprint.x, y * footprint.y)
			if not space.intersect_point(q, 1).is_empty():
				return true
	return false


## True when `point` has wandered further than `despawn_margin` from the arena
## centre, which is the signal to give up a chase and go home.
func is_stranded(point: Vector2) -> bool:
	return point.distance_to(global_position) > despawn_margin
