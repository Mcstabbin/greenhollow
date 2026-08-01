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
//
// Both terms are attenuated with distance, after
// pink-arcana/godot-distance-field-outlines (MIT), which ships the same feature
// with modes NONE/ALPHA/WIDTH/ALPHA_AND_WIDTH and defaults depth_fade_start 4 /
// depth_fade_end 40, for the same stated reason: it "prevents wide outlines from
// obscuring far-away content." See fade_begin below for why the crease term is
// attenuated harder than the silhouette term, and for the measurements the
// numbers came from.

render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled,
	cull_disabled, fog_disabled, shadows_disabled, ambient_light_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;

uniform vec4 outline_color : source_color = vec4(0.05, 0.05, 0.09, 1.0);
/// Outline width in pixels, in the near field.
uniform float thickness : hint_range(0.5, 4.0, 0.1) = 1.3;
/// Higher = picks up subtler depth steps. Too high and flat floors get noisy.
uniform float depth_sensitivity : hint_range(1.0, 60.0) = 16.0;
/// Higher = fewer crease lines. Around 0.8-1.4 catches wall/floor junctions.
uniform float normal_sensitivity : hint_range(0.0, 4.0) = 1.0;

// --- Distance attenuation -------------------------------------------------
//
// View depth in metres at which attenuation starts. NOTHING nearer than this is
// touched, which is the point: the near-field contour is the art direction.
// Measured against tools/shots — the player sits at 5.2-5.8 m (5.5 m spring arm),
// props the player stands among at 2-8 m, the mid-ground gate and logs at 8-16 m,
// the treeline at 16-48 m. 12 m clears every near-field measurement and still
// catches the whole treeline.
uniform float fade_begin : hint_range(0.0, 80.0) = 12.0;
/// Depth at which attenuation is complete. 40 m is the reference's default and
/// the far bank of the river measures 32-48 m.
uniform float fade_end : hint_range(1.0, 200.0) = 40.0;
/// What the SILHOUETTE (depth) term keeps at fade_end. Not zero: distant objects
/// have to stay objects, and their outlines are what say so. It is the crease
/// term that goes to zero, because normal differences are distance-invariant and
/// so a shrinking tree emits the same full-strength hatch over fewer and fewer
/// pixels until the canopy is a solid scribble — and ours sway, so it shimmers.
/// Measured on tools/shots/clearing spawn_north: of pixels beyond 32 m, 30.6%
/// were inked by the crease term against 16.0% by the silhouette term.
uniform float far_silhouette : hint_range(0.0, 1.0) = 0.6;
/// Outline width in pixels at fade_end. Do not go below 1.0: the Roberts cross
/// samples on the two diagonals, so an offset under half a texel puts both
/// samples of a pair in the same texel and the outline breaks into dashes.
uniform float far_thickness : hint_range(1.0, 4.0, 0.1) = 1.0;

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
	// Centre depth first, so it can drive the sampling radius as well as the
	// alpha. It costs nothing extra: this tap has no offset and was already read.
	float dc = view_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float fade = smoothstep(fade_begin, fade_end, dc);
	vec2 t = mix(thickness, far_thickness, fade) / VIEWPORT_SIZE;

	// Roberts cross: sample the two diagonals.
	vec2 uv0 = SCREEN_UV + vec2(-t.x, -t.y);
	vec2 uv1 = SCREEN_UV + vec2(t.x, t.y);
	vec2 uv2 = SCREEN_UV + vec2(-t.x, t.y);
	vec2 uv3 = SCREEN_UV + vec2(t.x, -t.y);

	float d0 = view_depth(uv0, INV_PROJECTION_MATRIX);
	float d1 = view_depth(uv1, INV_PROJECTION_MATRIX);
	float d2 = view_depth(uv2, INV_PROJECTION_MATRIX);
	float d3 = view_depth(uv3, INV_PROJECTION_MATRIX);

	// Relative, so distant geometry outlines as readily as near geometry. Kept:
	// this is what makes a distant silhouette fire at all, and the attenuation
	// below is the right place to decide how loudly it should.
	float dd = length(vec2(d1 - d0, d3 - d2)) / max(dc, 0.001);
	float silhouette = step(1.0 / depth_sensitivity, dd) * mix(1.0, far_silhouette, fade);

	vec3 n0 = texture(normal_tex, uv0).xyz * 2.0 - 1.0;
	vec3 n1 = texture(normal_tex, uv1).xyz * 2.0 - 1.0;
	vec3 n2 = texture(normal_tex, uv2).xyz * 2.0 - 1.0;
	vec3 n3 = texture(normal_tex, uv3).xyz * 2.0 - 1.0;
	float nd = length(abs(n1 - n0) + abs(n3 - n2));
	float crease = step(normal_sensitivity, nd) * (1.0 - fade);

	ALBEDO = outline_color.rgb;
	ALPHA = max(silhouette, crease) * outline_color.a;
}
