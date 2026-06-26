shader_type sky;

uniform vec3 space_color : source_color = vec3(0.0, 0.0, 0.008);
uniform float star_field_scale : hint_range(8.0, 80.0) = 38.0;
uniform float star_brightness : hint_range(0.0, 3.0) = 1.15;
uniform float star_size : hint_range(0.01, 0.2) = 0.055;
uniform float bright_star_ratio : hint_range(0.0, 0.35) = 0.12;
uniform float bright_star_boost : hint_range(1.0, 8.0) = 3.2;
uniform float star_twinkle : hint_range(0.0, 1.0) = 0.35;
uniform float nebula_strength : hint_range(0.0, 1.0) = 0.22;
uniform vec3 nebula_color_a : source_color = vec3(0.12, 0.08, 0.28);
uniform vec3 nebula_color_b : source_color = vec3(0.22, 0.1, 0.08);
uniform float glow_strength : hint_range(0.0, 2.0) = 0.55;

vec3 hash33(vec3 p) {
	p = fract(p * vec3(127.1, 311.7, 74.7));
	p += dot(p, p.yzx + 19.19);
	return fract(vec3(p.x * p.x, p.y * p.y, p.z * p.z) * p.xzy);
}

float hash11(float n) {
	return fract(sin(n) * 43758.5453);
}

float star_layer(vec3 eye_dir, float scale, float size, float layer_seed) {
	vec3 p = eye_dir * scale + vec3(layer_seed);
	vec3 cell = floor(p);
	vec3 local = fract(p) - 0.5;
	float brightest = 0.0;

	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 neighbor = vec3(float(x), float(y), float(z));
				vec3 point = hash33(cell + neighbor) - 0.5;
				float dist = length(neighbor + point - local);
				float pick = hash11(dot(cell + neighbor, vec3(13.7, 27.3, 41.1)) + layer_seed);
				if (pick >= 0.72) {
					float twinkle = 1.0;
					if (star_twinkle > 0.0) {
						twinkle = 0.75 + 0.25 * sin(TIME * (1.2 + pick * 2.5) + pick * 40.0);
						twinkle = mix(1.0, twinkle, star_twinkle);
					}
					float star = smoothstep(size, 0.0, dist) * twinkle;
					brightest = max(brightest, star * pick);
				}
			}
		}
	}

	return brightest;
}

vec3 star_color_for(float pick) {
	vec3 cool = vec3(0.72, 0.84, 1.0);
	vec3 warm = vec3(1.0, 0.9, 0.72);
	vec3 gold = vec3(1.0, 0.78, 0.45);
	if (pick > 0.92) {
		return gold;
	}
	if (pick > 0.82) {
		return warm;
	}
	return cool;
}

float nebula_noise(vec3 dir) {
	vec3 p = dir * 2.8;
	float n = sin(p.x * 3.7 + p.y * 2.1) * sin(p.z * 2.9 + p.y * 4.3);
	n += sin(p.x * 8.3 + p.z * 5.7) * 0.45;
	n += sin(p.y * 11.1 + p.x * 6.2) * 0.25;
	return n * 0.5 + 0.5;
}

void sky() {
	vec3 color = space_color;

	float nebula = smoothstep(0.52, 0.92, nebula_noise(EYEDIR));
	vec3 nebula_tint = mix(nebula_color_a, nebula_color_b, nebula_noise(EYEDIR * 1.7));
	color += nebula_tint * nebula * nebula_strength;

	float layer_a = star_layer(EYEDIR, star_field_scale, star_size, 0.0);
	float layer_b = star_layer(EYEDIR, star_field_scale * 1.65, star_size * 0.75, 17.0);
	float layer_c = star_layer(EYEDIR, star_field_scale * 2.4, star_size * 0.55, 43.0);
	float stars = (layer_a + layer_b * 0.7 + layer_c * 0.45) * star_brightness;

	float pick = hash11(dot(floor(EYEDIR * star_field_scale), vec3(12.3, 45.6, 78.9)));
	vec3 star_tint = star_color_for(pick);
	float bright_mask = step(1.0 - bright_star_ratio, pick);
	stars *= mix(1.0, bright_star_boost, bright_mask);

	color += star_tint * stars;

	if (LIGHT0_ENABLED) {
		float sun_alignment = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);
		float sun_disc = smoothstep(0.018, 0.0, distance(EYEDIR, LIGHT0_DIRECTION));
		float sun_halo = pow(sun_alignment, 48.0) * glow_strength;
		vec3 sun_tint = LIGHT0_COLOR * LIGHT0_ENERGY;
		color += sun_tint * (sun_disc * 2.5 + sun_halo);
	}

	COLOR = color;
}
