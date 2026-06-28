shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_opaque, fog_disabled;

uniform vec3 color_hot : source_color = vec3(1.0, 0.92, 0.55);
uniform vec3 color_cool : source_color = vec3(1.0, 0.38, 0.06);
uniform float flicker_speed : hint_range(1.0, 24.0) = 12.0;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p) * 2.0;
	float alpha = pow(clamp(1.0 - r, 0.0, 1.0), 1.75);
	float flicker = 0.88 + 0.12 * sin(TIME * flicker_speed + r * 8.0);
	vec3 color = mix(color_cool, color_hot, 1.0 - r) * flicker;
	ALBEDO = color * COLOR.rgb;
	ALPHA = alpha * COLOR.a;
}
