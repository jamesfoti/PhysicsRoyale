shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 core_color : source_color = vec4(1.0, 0.88, 0.45, 1.0);
uniform vec4 ray_color : source_color = vec4(1.0, 0.62, 0.12, 1.0);
uniform float glow_strength : hint_range(0.0, 6.0) = 1.8;
uniform float ray_strength : hint_range(0.0, 3.0) = 1.1;
uniform float ray_count : hint_range(4.0, 36.0) = 16.0;
uniform float ray_sharpness : hint_range(1.0, 20.0) = 7.0;
uniform float pulse_speed : hint_range(0.0, 2.0) = 0.3;
uniform float noise_amount : hint_range(0.0, 1.0) = 0.22;
uniform float core_bias : hint_range(0.0, 1.0) = 0.55;

varying vec2 v_uv;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	v_uv = UV;
}

void fragment() {
	vec2 p = v_uv * 2.0 - 1.0;
	float dist = length(p);
	float angle = atan(p.y, p.x);

	float pulse = sin(TIME * pulse_speed * 6.28318) * 0.12 + 0.88;
	float ray_wave = sin(angle * ray_count + TIME * pulse_speed * 1.7);
	float ray_jitter = hash(vec2(floor(angle * ray_count * 0.35), floor(TIME * 0.15))) * noise_amount;
	float rays = pow(max(0.0, ray_wave * 0.5 + 0.5 + ray_jitter), ray_sharpness);
	rays *= smoothstep(1.0, 0.08, dist);

	float core = exp(-dist * dist * 4.0);
	float halo = exp(-dist * 1.6) * 0.28;

	float brightness = (core * (1.0 + core_bias) + rays * ray_strength + halo) * glow_strength * pulse;
	brightness *= smoothstep(1.02, 0.72, dist);

	vec3 color = mix(ray_color.rgb, core_color.rgb, clamp(core * 1.4, 0.0, 1.0));
	float alpha = clamp(brightness, 0.0, 1.0);
	ALBEDO = color;
	ALPHA = alpha;
}
