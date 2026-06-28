shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled, fog_disabled;

uniform vec4 albedo : source_color = vec4(0.35, 0.55, 0.28, 1.0);
uniform vec3 sun_direction = vec3(-1.0, 0.0, 0.0);
uniform float ambient_strength : hint_range(0.0, 1.0) = 0.42;
uniform float emissive_boost : hint_range(0.0, 4.0) = 0.0;

void fragment() {
	vec3 n: vec3 = normalize(NORMAL);
	float ndl: float = max(dot(n, normalize(sun_direction)), 0.0);
	float light: float = ambient_strength + (1.0 - ambient_strength) * ndl;
	vec3 lit: vec3 = albedo.rgb * light + albedo.rgb * emissive_boost;
	ALBEDO = lit;
}
