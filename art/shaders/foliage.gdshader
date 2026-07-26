shader_type spatial;
// Wind sway for leaves and grass.
//
// Applied only to foliage surfaces, never bark, so trunks stay planted while
// their canopies move. Sway scales with local height, so the base of a grass
// tuft stays rooted and the tips travel furthest.
//
// Phase is derived from world position, so neighbouring plants are out of sync
// instead of the whole forest breathing as one organism.

render_mode diffuse_lambert_wrap, specular_disabled, cull_back;

uniform vec4 albedo : source_color = vec4(0.45, 0.76, 0.40, 1.0);
uniform float sway_strength : hint_range(0.0, 0.3) = 0.055;
uniform float sway_speed : hint_range(0.0, 4.0) = 1.15;
/// Secondary faster, smaller motion so it doesn't read as a single sine.
uniform float flutter_strength : hint_range(0.0, 0.1) = 0.018;
uniform float flutter_speed : hint_range(0.0, 12.0) = 4.6;

void vertex() {
	vec3 world = MODEL_MATRIX[3].xyz;
	float phase = world.x * 0.35 + world.z * 0.27;

	// Only sway above the origin: roots and trunk bases shouldn't slide.
	float h = max(VERTEX.y, 0.0);

	float sway = sin(TIME * sway_speed + phase) * sway_strength * h;
	float flutter = sin(TIME * flutter_speed + phase * 2.3 + VERTEX.y) * flutter_strength * h;

	VERTEX.x += sway + flutter;
	VERTEX.z += sway * 0.55 - flutter * 0.4;
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
