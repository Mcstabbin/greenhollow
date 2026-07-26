shader_type spatial;
// Stream surface. Procedural, no textures — two crossing sine waves drive both
// a small vertical ripple and a shallow/deep colour mix, so the stream reads as
// moving water rather than a flat blue plane.

render_mode blend_mix, depth_draw_opaque, cull_disabled,
	diffuse_lambert_wrap, specular_schlick_ggx;

uniform vec4 shallow_colour : source_color = vec4(0.40, 0.70, 0.74, 0.72);
uniform vec4 deep_colour : source_color = vec4(0.13, 0.35, 0.50, 0.92);
uniform float wave_speed : hint_range(0.0, 3.0) = 0.5;
uniform float wave_scale : hint_range(0.1, 8.0) = 1.6;
uniform float wave_height : hint_range(0.0, 0.3) = 0.045;
/// Constant drift, so the stream looks like it's flowing somewhere.
uniform vec2 flow = vec2(0.35, 0.0);

float ripple(vec2 p, float t) {
	return sin(p.x * 1.7 + t) * 0.5 + sin(p.y * 2.4 - t * 1.35) * 0.5;
}

void vertex() {
	// Only disturb the top face; the sides of the slab should stay put.
	if (NORMAL.y > 0.5) {
		vec2 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz * wave_scale;
		VERTEX.y += ripple(w + flow * TIME, TIME * wave_speed) * wave_height;
	}
}

void fragment() {
	vec2 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz * wave_scale;
	float f = clamp(ripple(w + flow * TIME, TIME * wave_speed) * 0.5 + 0.5, 0.0, 1.0);
	vec4 c = mix(deep_colour, shallow_colour, f);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ROUGHNESS = 0.12;
	SPECULAR = 0.65;
}
