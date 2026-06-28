shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_opaque, fog_disabled;

uniform vec3 color_hot : source_color = vec3(1.0, 0.85, 0.35);
uniform vec3 color_cool : source_color = vec3(1.0, 0.35, 0.05);
uniform float flicker_speed : hint_range(0.5, 12.0) = 5.0;
uniform float noise_scale : hint_range(1.0, 12.0) = 4.0;

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

void fragment() {
	vec2 uv = UV;
	float height = pow(clamp(1.0 - uv.y, 0.0, 1.0), 0.65);
	float width = 1.0 - abs(uv.x - 0.5) * 2.6;
	width = clamp(width, 0.0, 1.0);
	vec2 noise_uv = uv * vec2(noise_scale, noise_scale * 1.6) + vec2(0.0, TIME * flicker_speed);
	float n = noise2d(noise_uv);
	float flicker = 0.9 + 0.1 * n;
	float pulse = 0.92 + 0.08 * sin(TIME * flicker_speed * 1.6);
	vec3 color = mix(color_cool, color_hot, height * flicker * pulse);
	float alpha = height * width * flicker;
	ALBEDO = color;
	ALPHA = alpha;
}
