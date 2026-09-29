extends StaticBody2D

## A solid box for the template areas.
##
## Size is an export and the collision shape is built in _ready() instead of
## being authored in the scene, so one small scene can be instanced at any size
## from a property. Authoring sizes in the .tscn would mean a hand-written
## SubResource override per instance, which is exactly the sort of thing that
## makes a test rig annoying to edit while tuning.
##
## These rigs deliberately do not use a TileMapLayer. The production level keeps
## its collision in the TileSet sub-resource, because Godot 4.7 moved it there,
## and that is not something to hand-author when the point of these scenes is to
## be reshaped constantly.

## Full size in pixels, centred on this node.
@export var size: Vector2 = Vector2(400, 40)
@export var color: Color = Color(0.15, 0.17, 0.23)
## A visible outline, because the single most common thing to do in a test area
## is judge distance and edge alignment by eye, and a flat fill against a dark
## background is very hard to read.
@export var border: Color = Color(0.42, 0.48, 0.6)
@export var border_width: float = 3.0

@onready var shape_node: CollisionShape2D = $Shape
@onready var visual: Polygon2D = $Visual
@onready var outline: Line2D = $Outline


func _ready() -> void:
	var rect := RectangleShape2D.new()
	rect.size = size
	shape_node.shape = rect

	var half := size * 0.5
	var points := PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	visual.polygon = points
	visual.color = color
	outline.points = points
	outline.closed = true
	outline.width = border_width
	outline.default_color = border
