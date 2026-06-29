shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, fog_disabled;

uniform vec3 space_color : source_color = vec3(0.0, 0.0, 0.01);
uniform float star_scale : hint_range(8.0, 80.0) = 34.0;
uniform float star_brightness : hint_range(0.0, 3.0) = 1.35;
uniform float star_size : hint_range(0.01, 0.2) = 0.06;

varying vec3 v_dir;

vec3 hash33(vec3 p) {
	p = fract(p * vec3(127.1, 311.7, 74.7));
	p += dot(p, p.yzx + 19.19);
	return fract(vec3(p.x * p.x, p.y * p.y, p.z * p.z) * p.xzy);
}

float hash11(float n) {
	return fract(sin(n) * 43758.5453);
}

float stars_at(vec3 dir, float scale, float size, float seed) {
	vec3 p = dir * scale + vec3(seed);
	vec3 cell = floor(p);
	vec3 local = fract(p) - 0.5;
	float brightest = 0.0;

	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 neighbor = vec3(float(x), float(y), float(z));
				vec3 point = hash33(cell + neighbor) - 0.5;
				float dist = length(neighbor + point - local);
				float pick = hash11(dot(cell + neighbor, vec3(13.7, 27.3, 41.1)) + seed);
				if (pick >= 0.7) {
					float star = smoothstep(size, 0.0, dist) * pick;
					brightest = max(brightest, star);
				}
			}
		}
	}

	return brightest;
}

void vertex() {
	vec4 clip_pos = PROJECTION_MATRIX * (VIEW_MATRIX * MODEL_MATRIX * vec4(VERTEX, 1.0));
	POSITION = clip_pos.xyww;
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_dir = normalize(world_pos - origin);
}

void fragment() {
	vec3 color = space_color;
	float layer_a = stars_at(v_dir, star_scale, star_size, 0.0);
	float layer_b = stars_at(v_dir, star_scale * 1.7, star_size * 0.72, 19.0);
	color += vec3(0.82, 0.9, 1.0) * (layer_a + layer_b * 0.65) * star_brightness;
	ALBEDO = color;
}
