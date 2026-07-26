shader_type spatial;
// Screen-space outline pass. Lives on a fullscreen quad parented to the camera.
//
// Detects edges two ways: depth discontinuities (silhouettes) and normal
// discontinuities (creases, e.g. where a wall meets the floor). Inverted-hull
// outlines were the other option, but they tear open at the corners of box
// geometry, and this world is all boxes.
//
// Uses ALPHA so Godot sorts it into the transparent pass, which is what makes
// the depth/normal buffers available by the time this runs.

render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled,
	cull_disabled, fog_disabled, shadows_disabled, ambient_light_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;

uniform vec4 outline_color : source_color = vec4(0.05, 0.05, 0.09, 1.0);
/// Outline width in pixels.
uniform float thickness : hint_range(0.5, 4.0, 0.1) = 1.3;
/// Higher = picks up subtler depth steps. Too high and flat floors get noisy.
uniform float depth_sensitivity : hint_range(1.0, 60.0) = 16.0;
/// Higher = fewer crease lines. Around 0.8-1.4 catches wall/floor junctions.
uniform float normal_sensitivity : hint_range(0.0, 4.0) = 1.0;

// Reconstruct view-space depth. Godot uses reverse-Z, so sky reads as 0.
float view_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).x;
	vec4 view = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return clamp(-(view.z / view.w), 0.0, 4000.0);
}

void vertex() {
	// Force the quad to clip-space corners regardless of its transform.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 t = thickness / VIEWPORT_SIZE;

	// Roberts cross: sample the two diagonals.
	vec2 uv0 = SCREEN_UV + vec2(-t.x, -t.y);
	vec2 uv1 = SCREEN_UV + vec2(t.x, t.y);
	vec2 uv2 = SCREEN_UV + vec2(-t.x, t.y);
	vec2 uv3 = SCREEN_UV + vec2(t.x, -t.y);

	float dc = view_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float d0 = view_depth(uv0, INV_PROJECTION_MATRIX);
	float d1 = view_depth(uv1, INV_PROJECTION_MATRIX);
	float d2 = view_depth(uv2, INV_PROJECTION_MATRIX);
	float d3 = view_depth(uv3, INV_PROJECTION_MATRIX);

	// Relative, so distant geometry outlines as readily as near geometry.
	float dd = length(vec2(d1 - d0, d3 - d2)) / max(dc, 0.001);
	float depth_edge = step(1.0 / depth_sensitivity, dd);

	vec3 n0 = texture(normal_tex, uv0).xyz * 2.0 - 1.0;
	vec3 n1 = texture(normal_tex, uv1).xyz * 2.0 - 1.0;
	vec3 n2 = texture(normal_tex, uv2).xyz * 2.0 - 1.0;
	vec3 n3 = texture(normal_tex, uv3).xyz * 2.0 - 1.0;
	float nd = length(abs(n1 - n0) + abs(n3 - n2));
	float normal_edge = step(normal_sensitivity, nd);

	ALBEDO = outline_color.rgb;
	ALPHA = max(depth_edge, normal_edge) * outline_color.a;
}
