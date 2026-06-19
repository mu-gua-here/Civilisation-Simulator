shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, blend_mix;

// Samples a territory mask texture by world XZ position. Areas with mask
// value 0 are rendered as solid "void" color; areas with mask value 1 are
// fully transparent (showing the ground beneath). This is entirely
// world-space — it does NOT depend on camera position, so the boundary
// never recedes as the player approaches it.

uniform sampler2D territory_mask : hint_default_black, filter_linear, repeat_disable;
uniform float world_extent = 80.0;     // Must match TerritoryMask.world_extent
uniform vec4 void_color : source_color = vec4(0.78, 0.85, 0.92, 1.0); // pastel fog color
uniform float void_alpha : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Map world XZ to UV [0,1] over world_extent, centered at origin.
	vec2 uv = (world_pos.xz / world_extent) + 0.5;

	float revealed = 0.0;
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		revealed = texture(territory_mask, uv).r;
	}
	// Outside the mask's covered area entirely: treat as unrevealed (void).

	ALBEDO = void_color.rgb;
	ALPHA = (1.0 - revealed) * void_alpha;
}
