shader_type canvas_item;
render_mode unshaded;

// Hit/telegraph flash that is independent of the node's `modulate`.
//
// Why this exists: the prototype used `sprite.modulate = Color(10, 10, 10)` to
// blow a sprite out to white on impact. That only looked right because every
// sprite is a flat placeholder shape. On real artwork it clamps ugly, and it
// fights the tint states (stun blue, charge cyan, dash alpha) for the same
// property. Keeping the flash in a shader means tint and flash compose instead
// of overwriting each other, so swapping in a texture needs no code change.

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	// COLOR already carries the node's modulate, so tint and alpha keep working
	// exactly as before while the flash is applied on top.
	vec4 base = texture(TEXTURE, UV) * COLOR;
	vec3 flashed = mix(base.rgb, flash_color.rgb, flash_amount);

	// Preserve the texture's own alpha: flashing must not make a transparent
	// sprite opaque, and the flash must not fight a dash's partial alpha.
	COLOR = vec4(flashed, base.a);
}
