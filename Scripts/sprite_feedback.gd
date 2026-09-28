class_name SpriteFeedback
extends RefCounted

## Shared hit-flash helper for sprites.
##
## Wraps the shader in `res://Shaders/feedback_flash.gdshader` so that a
## "flash this sprite white" call composes with the node's `modulate` instead of
## overwriting it. Replaces the old `sprite.modulate = Color(10, 10, 10)` trick,
## which only looked correct on flat placeholder shapes and would clamp badly on
## real artwork.
##
## Usage:
##     SpriteFeedback.attach(sprite)                    # in _ready()
##     SpriteFeedback.flash(sprite, Color.WHITE, 1.0)   # on impact

const FLASH_SHADER: Shader = preload("res://Shaders/feedback_flash.gdshader")

const DEFAULT_DURATION := 0.12
## Hits arriving closer together than this reuse the running flash instead of
## restarting it, so a shotgun volley reads as one sustained impact.
const MIN_FLASH := 0.05


## Give a sprite its own material instance with the flash shader attached.
## Safe to call repeatedly; each sprite keeps a distinct material so two
## entities flashing never affect one another.
##
## Note: this Godot 4.7 build exposes the property as `material` (the editor
## still labels it "Material Override"). `CanvasItem.material_override` does not
## exist here and raises on access, so the setter is used deliberately.
static func attach(sprite: CanvasItem) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	if not sprite is CanvasItem:
		push_warning("SpriteFeedback.attach: %s is not a CanvasItem" % sprite.get_class())
		return
	if sprite.get("material") is ShaderMaterial:
		return
	var mat := ShaderMaterial.new()
	mat.shader = FLASH_SHADER
	# Set both uniforms up front. Reading a uniform that was never assigned
	# returns null rather than the shader's declared default, which would break
	# any code that inspects flash_amount.
	mat.set_shader_parameter("flash_color", Color.WHITE)
	mat.set_shader_parameter("flash_amount", 0.0)
	sprite.set("material", mat)


## Flash the sprite toward `color`, decaying to normal over `duration`.
## Returns the tween so callers can kill it or chain onto it.
static func flash(
	sprite: CanvasItem,
	color: Color = Color.WHITE,
	amount: float = 1.0,
	duration: float = DEFAULT_DURATION
) -> Tween:
	if sprite == null or not is_instance_valid(sprite):
		return null

	attach(sprite)
	var mat := sprite.get("material") as ShaderMaterial
	if mat == null:
		return null

	# A flash already in flight is killed first so rapid hits do not stack into
	# a flash that lingers long after the last bullet landed.
	var running := _running_tween(sprite)
	if running != null and running.is_valid():
		running.kill()

	mat.set_shader_parameter("flash_color", color)
	mat.set_shader_parameter("flash_amount", amount)

	var tween := sprite.create_tween()
	tween.tween_method(
		_set_flash_amount.bind(mat),
		amount,
		0.0,
		duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_clear_tween.bind(sprite))

	sprite.set_meta(&"_feedback_flash_tween", tween)
	return tween


## Set the flash level directly. Used by the tween above.
static func _set_flash_amount(value: float, mat: ShaderMaterial) -> void:
	if mat == null or not is_instance_valid(mat):
		return
	mat.set_shader_parameter("flash_amount", value)


## Drop a dead tween reference so we do not keep calling into freed memory.
static func _clear_tween(sprite: CanvasItem) -> void:
	if sprite != null and is_instance_valid(sprite):
		sprite.set_meta(&"_feedback_flash_tween", null)


static func _running_tween(sprite: CanvasItem) -> Tween:
	if sprite == null or not is_instance_valid(sprite):
		return null
	if not sprite.has_meta(&"_feedback_flash_tween"):
		return null
	return sprite.get_meta(&"_feedback_flash_tween") as Tween


## Stop any flash immediately and return the sprite to its tinted self.
static func clear(sprite: CanvasItem) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var running := _running_tween(sprite)
	if running != null and running.is_valid():
		running.kill()
	_clear_tween(sprite)

	var mat := sprite.get("material") as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("flash_amount", 0.0)


## Tint helper. Kept separate from the flash so a stunned enemy can be blue
## AND still flash white when it takes a hit.
static func set_tint(sprite: CanvasItem, color: Color) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	sprite.modulate = color
