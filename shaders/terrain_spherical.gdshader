shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled, fog_disabled;

uniform vec3 planet_center;
uniform float planet_radius;

uniform vec4 grass_color : source_color = vec4(0.22, 0.68, 0.18, 1.0);
uniform vec4 dirt_color : source_color = vec4(0.45, 0.38, 0.28, 1.0);
uniform vec4 rock_color : source_color = vec4(0.42, 0.42, 0.46, 1.0);
uniform vec4 snow_color : source_color = vec4(0.93, 0.95, 0.98, 1.0);
uniform float noise_scale : hint_range(1.0, 64.0) = 18.0;
uniform float rock_elevation_start = 1.2;
uniform float rock_elevation_end = 2.8;
uniform float pole_snow_start : hint_range(0.0, 1.0) = 0.62;
uniform float pole_snow_end : hint_range(0.0, 1.0) = 0.9;

varying vec3 world_vertex;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float terrain_noise_at_dir(vec3 dir) {
	vec2 sphere_uv = vec2(
		atan(dir.z, dir.x) / TAU + 0.5,
		acos(clamp(dir.y, -1.0, 1.0)) / PI
	);
	vec2 scaled = sphere_uv * noise_scale;
	float n0 = value_noise(scaled);
	float n1 = value_noise(scaled * 2.17 + vec2(13.7, 9.2));
	float n2 = value_noise(scaled * 4.83 + vec2(4.1, 21.5));
	return n0 * 0.55 + n1 * 0.3 + n2 * 0.15;
}

void vertex() {
	world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 sphere_dir = normalize(world_vertex - planet_center);
	float elevation = length(world_vertex - planet_center) - planet_radius;
	float rock_blend = smoothstep(rock_elevation_start, rock_elevation_end, elevation);
	float noise = terrain_noise_at_dir(sphere_dir);
	float dirt_from_noise = smoothstep(0.38, 0.62, noise);
	float dirt_from_valley = smoothstep(-0.2, -1.5, elevation);
	float dirt_blend = clamp(
		max(dirt_from_noise, dirt_from_valley) * (1.0 - rock_blend * 0.85),
		0.0,
		1.0
	);

	vec3 base = mix(grass_color.rgb, dirt_color.rgb, dirt_blend);
	base = mix(base, rock_color.rgb, rock_blend);

	float pole_snow = smoothstep(pole_snow_start, pole_snow_end, abs(sphere_dir.y));
	base = mix(base, snow_color.rgb, pole_snow);

	ALBEDO = base;
}
