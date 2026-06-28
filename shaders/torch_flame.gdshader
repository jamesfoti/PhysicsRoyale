shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_opaque, fog_disabled;

uniform vec3 flame_color_hot : source_color = vec3(1.0, 0.85, 0.35);
uniform vec3 flame_color_cool : source_color = vec3(1.0, 0.35, 0.05);
uniform float flicker_speed : hint_range(0.5, 12.0) = 4.5;
uniform float flicker_strength : hint_range(0.0, 1.0) = 0.35;
uniform float noise_scale : hint_range(1.0, 12.0) = 5.0;

varying vec3 v_local_pos;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	v_local_pos = VERTEX;
}

void fragment() {
	float height = clamp((v_local_pos.z + 0.07) / 0.14, 0.0, 1.0);
	float edge = 1.0 - abs(v_local_pos.x) * 8.0;
	edge = clamp(edge, 0.0, 1.0);

	vec2 noise_uv = vec2(v_local_pos.x, v_local_pos.z) * noise_scale + vec2(0.0, TIME * flicker_speed);
	float n = noise2d(noise_uv);
	float flicker = 1.0 + (n - 0.5) * flicker_strength;
	float pulse = 0.9 + 0.1 * sin(TIME * flicker_speed * 1.7);

	vec3 color = mix(flame_color_cool, flame_color_hot, height * flicker * pulse);
	color *= edge;

	ALBEDO = color;
	ALPHA = height * edge * flicker;
}
