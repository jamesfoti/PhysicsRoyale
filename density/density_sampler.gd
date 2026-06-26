class_name DensitySampler
extends RefCounted
## Builds signed density fields from analytic shapes and noise.


class WorldDensity:
	## Analytic density + gradient at any world position (seam-consistent normals).
	var sphere_enabled: bool = true
	var sphere_center: Vector3 = Vector3.ZERO
	var sphere_radius: float = 18.0
	var noise_enabled: bool = true
	var noise_amplitude: float = 3.0
	var noise_octaves: int = 3
	var noise_lacunarity: float = 2.0
	var noise_gain: float = 0.5
	var bounds_falloff_enabled: bool = false
	var bounds_center: Vector3 = Vector3.ZERO
	var bounds_half: Vector3 = Vector3.ZERO
	var bounds_falloff_distance: float = 8.0
	var bounds_falloff_strength: float = 5.0
	var bounds_clip_inset: float = 0.5
	var ravines_enabled: bool = false
	var ravine_depth: float = 100.0
	var ravine_width: float = 0.12
	var caves_enabled: bool = false
	var cave_noise_strength: float = 400.0
	var cave_height_multiplier: float = 0.03
	var cave_reference_scale: float = 1500.0 / 1600.0
	var cave_height_noise_scale: float = 1.5
	var cave_smoothness: float = 5.0
	var _noise: FastNoiseLite
	var _ravine_noise: FastNoiseLite
	var _ravine_blend_noise: FastNoiseLite
	var _cave_noise: FastNoiseLite
	var terrain_edits: TerrainEdits = null

	static func create(
		sphere_enabled: bool,
		sphere_center: Vector3,
		sphere_radius: float,
		noise_enabled: bool,
		noise_seed: int,
		noise_frequency: float,
		noise_amplitude: float,
		noise_octaves: int,
		noise_lacunarity: float,
		noise_gain: float,
		bounds_center: Vector3,
		bounds_half: Vector3,
		bounds_falloff_enabled: bool,
		bounds_falloff_distance: float,
		bounds_falloff_strength: float,
		bounds_clip_inset: float = 0.5
	) -> WorldDensity:
		var density := WorldDensity.new()
		density.sphere_enabled = sphere_enabled
		density.sphere_center = sphere_center
		density.sphere_radius = sphere_radius
		density.noise_enabled = noise_enabled
		density.noise_amplitude = noise_amplitude
		density.noise_octaves = noise_octaves
		density.noise_lacunarity = noise_lacunarity
		density.noise_gain = noise_gain
		density.bounds_falloff_enabled = bounds_falloff_enabled
		density.bounds_center = bounds_center
		density.bounds_half = bounds_half
		density.bounds_falloff_distance = bounds_falloff_distance
		density.bounds_falloff_strength = bounds_falloff_strength
		density.bounds_clip_inset = bounds_clip_inset
		if noise_enabled:
			density._noise = FastNoiseLite.new()
			density._noise.seed = noise_seed
			density._noise.noise_type = FastNoiseLite.TYPE_PERLIN
			density._noise.frequency = noise_frequency
		return density

	func _init_planet_feature_noises(planet_seed: int) -> void:
		if ravines_enabled:
			_ravine_noise = FastNoiseLite.new()
			_ravine_noise.seed = planet_seed
			_ravine_noise.noise_type = FastNoiseLite.TYPE_PERLIN
			_ravine_noise.frequency = 1.0
			_ravine_blend_noise = FastNoiseLite.new()
			_ravine_blend_noise.seed = planet_seed + 2
			_ravine_blend_noise.noise_type = FastNoiseLite.TYPE_PERLIN
			_ravine_blend_noise.frequency = 1.0
		if caves_enabled:
			_cave_noise = FastNoiseLite.new()
			_cave_noise.seed = planet_seed + 202
			_cave_noise.noise_type = FastNoiseLite.TYPE_PERLIN
			_cave_noise.frequency = 1.0
			_cave_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
			_cave_noise.fractal_octaves = 6
			_cave_noise.fractal_lacunarity = 2.5
			_cave_noise.fractal_gain = 0.5

	func evaluate(world_pos: Vector3) -> float:
		var value := 1.0
		var surface_noise := 0.0
		if sphere_enabled:
			value = DensitySampler.sphere_sdf(world_pos, sphere_center, sphere_radius)
		if noise_enabled:
			surface_noise = DensitySampler.fbm_noise_3d(
				_noise, world_pos, noise_octaves, noise_lacunarity, noise_gain
			)
			value -= surface_noise * noise_amplitude
		if ravines_enabled and _ravine_noise != null and _ravine_blend_noise != null:
			value += DensitySampler.ravine_density_offset(
				world_pos,
				sphere_center,
				_ravine_noise,
				_ravine_blend_noise,
				ravine_depth,
				ravine_width
			)
		if caves_enabled and _cave_noise != null:
			value = DensitySampler.apply_cave_smooth_subtract(
				value,
				world_pos,
				sphere_center,
				sphere_radius,
				_cave_noise,
				surface_noise,
				noise_amplitude,
				cave_noise_strength,
				cave_height_multiplier,
				cave_reference_scale,
				cave_height_noise_scale,
				cave_smoothness
			)
		if bounds_falloff_enabled:
			if sphere_enabled:
				var max_radius := (
					minf(bounds_half.x, minf(bounds_half.y, bounds_half.z)) - bounds_clip_inset
				)
				value += DensitySampler.bounds_sphere_push(
					world_pos,
					sphere_center,
					max_radius,
					bounds_falloff_distance,
					bounds_falloff_strength
				)
			else:
				value += DensitySampler.bounds_edge_push(
					world_pos,
					bounds_center,
					bounds_half,
					bounds_falloff_distance,
					bounds_falloff_strength
				)
		if terrain_edits != null:
			value = terrain_edits.apply_to_density(value, world_pos)
		return value

	func gradient(world_pos: Vector3, epsilon: float) -> Vector3:
		var dx := (
			evaluate(world_pos + Vector3(epsilon, 0.0, 0.0))
			- evaluate(world_pos - Vector3(epsilon, 0.0, 0.0))
		) / (2.0 * epsilon)
		var dy := (
			evaluate(world_pos + Vector3(0.0, epsilon, 0.0))
			- evaluate(world_pos - Vector3(0.0, epsilon, 0.0))
		) / (2.0 * epsilon)
		var dz := (
			evaluate(world_pos + Vector3(0.0, 0.0, epsilon))
			- evaluate(world_pos - Vector3(0.0, 0.0, epsilon))
		) / (2.0 * epsilon)
		return Vector3(dx, dy, dz)


static func sphere_sdf(world_pos: Vector3, center: Vector3, radius: float) -> float:
	# Standard signed distance: negative inside, zero on surface, positive outside.
	return world_pos.distance_to(center) - radius


static func create_planet_world_density(
	center: Vector3,
	radius: float,
	planet_seed: int = 42,
	surface_noise_amplitude: float = -1.0,
	surface_noise_frequency: float = -1.0,
	ravines_enabled: bool = true,
	caves_enabled: bool = true,
	bounds_center: Vector3 = Vector3.ZERO,
	bounds_half: Vector3 = Vector3.ZERO,
	bounds_falloff_enabled: bool = false,
	bounds_falloff_distance: float = 8.0,
	bounds_falloff_strength: float = 5.0,
	bounds_clip_inset: float = 0.5,
	ravine_depth: float = -1.0,
	ravine_width: float = -1.0
) -> WorldDensity:
	## Planet SDF with surface noise, radial ravines, and near-surface cave pockets.
	## Parameters scale from the old voxel graph defaults (radius ~1600).
	var scale := maxf(radius / 1600.0, 0.01)
	var amp := surface_noise_amplitude if surface_noise_amplitude >= 0.0 else lerpf(3.0, 100.0, scale)
	var freq := (
		surface_noise_frequency
		if surface_noise_frequency >= 0.0
		else lerpf(0.08, 0.001, scale)
	)
	var density := WorldDensity.create(
		true,
		center,
		radius,
		true,
		planet_seed,
		freq,
		amp,
		3,
		2.0,
		0.5,
		bounds_center,
		bounds_half,
		bounds_falloff_enabled,
		bounds_falloff_distance,
		bounds_falloff_strength,
		bounds_clip_inset
	)
	density.ravines_enabled = ravines_enabled
	density.ravine_depth = (
		ravine_depth
		if ravine_depth >= 0.0
		else compute_auto_ravine_depth(radius, amp)
	)
	density.ravine_width = (
		ravine_width
		if ravine_width >= 0.0
		else compute_auto_ravine_width(radius)
	)
	density.caves_enabled = caves_enabled
	density.cave_noise_strength = 400.0 * scale
	density.cave_height_multiplier = 0.03
	density.cave_reference_scale = 1500.0 / 1600.0
	density.cave_height_noise_scale = 1.5
	density.cave_smoothness = maxf(5.0 * scale, 0.5)
	density._init_planet_feature_noises(planet_seed)
	return density


static func compute_auto_ravine_depth(
	radius: float,
	surface_noise_amplitude: float
) -> float:
	## Graph default at r=1600 is 100 (6.25% of radius). Smaller planets bump depth so grooves
	## stay comparable to surface noise.
	var graph_depth := radius * 0.0625
	return maxf(graph_depth, surface_noise_amplitude * 0.75)


static func compute_auto_ravine_width(radius: float) -> float:
	## Wider grooves on small planets so ravines resolve at voxel scale (graph uses ~0.002 at r=1600).
	return lerpf(0.12, 0.002, clampf((radius - 20.0) / 380.0, 0.0, 1.0))


static func ravine_density_offset(
	world_pos: Vector3,
	center: Vector3,
	shape_noise: FastNoiseLite,
	blend_noise: FastNoiseLite,
	depth_multiplier: float,
	mask_edge: float
) -> float:
	## Radial grooves where direction noise forms valleys. Higher mask_edge = wider grooves.
	var rel := world_pos - center
	var dist := rel.length()
	if dist <= 0.001 or depth_multiplier <= 0.0 or mask_edge <= 0.0:
		return 0.0
	var dir := rel / dist
	var n := shape_noise.get_noise_3d(dir.x, dir.y, dir.z)
	var blend := blend_noise.get_noise_3d(dir.x, dir.y, dir.z)
	var blend_clamped := clampf(blend * 4.0, 0.0, 1.0)
	if blend_clamped <= 0.0:
		return 0.0
	var mask := smoothstep(mask_edge, 0.0, n * n + blend_clamped)
	return mask * depth_multiplier


static func apply_cave_smooth_subtract(
	density: float,
	world_pos: Vector3,
	center: Vector3,
	radius: float,
	cave_noise: FastNoiseLite,
	surface_noise: float,
	surface_noise_amplitude: float,
	noise_strength: float,
	height_multiplier: float,
	reference_scale: float,
	height_noise_scale: float,
	smoothness: float
) -> float:
	## Matches voxel_graph_planet_v4: smooth-subtract (n² × strength + depth² × 0.03 − 1).
	var rel := world_pos - center
	var dist := rel.length()
	if dist <= 0.001 or noise_strength <= 0.0:
		return density
	var dir := rel / dist
	var reference_radius := radius * reference_scale
	var height_offset := height_noise_scale * (-surface_noise_amplitude * surface_noise)
	var shell_depth := dist + height_offset - reference_radius
	var height_term := shell_depth * shell_depth * height_multiplier - 1.0
	var cave_n := cave_noise.get_noise_3d(dir.x, dir.y, dir.z)
	var cave_sdf := cave_n * cave_n * noise_strength + height_term
	return sdf_smooth_subtract(density, cave_sdf, smoothness)


static func sdf_smooth_subtract(distance_a: float, distance_b: float, smoothing: float) -> float:
	## Voxel graph SdfSmoothSubtract (IQ-style smooth boolean subtraction).
	if smoothing <= 0.0:
		return maxf(distance_a, -distance_b)
	var h := clampf(0.5 - 0.5 * (distance_b + distance_a) / smoothing, 0.0, 1.0)
	return lerpf(distance_a, -distance_b, h) + smoothing * h * (1.0 - h)


static func fbm_noise_3d(
	noise: FastNoiseLite,
	world_pos: Vector3,
	octaves: int,
	lacunarity: float,
	gain: float
) -> float:
	var amplitude := 1.0
	var frequency := 1.0
	var total := 0.0
	var normalizer := 0.0
	for _i in octaves:
		total += noise.get_noise_3d(
			world_pos.x * frequency,
			world_pos.y * frequency,
			world_pos.z * frequency
		) * amplitude
		normalizer += amplitude
		amplitude *= gain
		frequency *= lacunarity
	if normalizer <= 0.0:
		return 0.0
	return total / normalizer


static func fill_sphere(
	field: SignedDensityField,
	chunk_origin: Vector3,
	voxel_size: float,
	center: Vector3,
	radius: float
) -> void:
	for z in field.size.z:
		for y in field.size.y:
			for x in field.size.x:
				var world_pos := chunk_origin + Vector3(x, y, z) * voxel_size
				field.set_sample(x, y, z, sphere_sdf(world_pos, center, radius))


static func apply_noise(
	field: SignedDensityField,
	chunk_origin: Vector3,
	voxel_size: float,
	seed: int,
	frequency: float,
	amplitude: float,
	octaves: int,
	lacunarity: float,
	gain: float
) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = frequency
	for z in field.size.z:
		for y in field.size.y:
			for x in field.size.x:
				var world_pos := chunk_origin + Vector3(x, y, z) * voxel_size
				var n := fbm_noise_3d(noise, world_pos, octaves, lacunarity, gain)
				var current := field.get_sample(x, y, z)
				field.set_sample(x, y, z, current - n * amplitude)


static func bounds_edge_push(
	world_pos: Vector3,
	bounds_center: Vector3,
	bounds_half: Vector3,
	feather: float,
	strength: float
) -> float:
	if feather <= 0.0 or strength <= 0.0:
		return 0.0
	var rel: Vector3 = (world_pos - bounds_center).abs()
	var dist_to_face := bounds_half - rel
	var edge_dist: float = minf(dist_to_face.x, minf(dist_to_face.y, dist_to_face.z))
	if edge_dist < 0.0:
		return strength - edge_dist
	if edge_dist >= feather:
		return 0.0
	var t: float = 1.0 - edge_dist / feather
	var smooth_t: float = t * t * (3.0 - 2.0 * t)
	return smooth_t * strength


static func bounds_sphere_push(
	world_pos: Vector3,
	center: Vector3,
	max_radius: float,
	feather: float,
	strength: float
) -> float:
	if feather <= 0.0 or strength <= 0.0:
		return 0.0
	var dist: float = world_pos.distance_to(center)
	var edge_dist: float = max_radius - dist
	if edge_dist < 0.0:
		return strength - edge_dist
	if edge_dist >= feather:
		return 0.0
	var t: float = 1.0 - edge_dist / feather
	var smooth_t: float = t * t * (3.0 - 2.0 * t)
	return smooth_t * strength


static func apply_bounds_falloff(
	field: SignedDensityField,
	chunk_origin: Vector3,
	voxel_size: float,
	bounds_center: Vector3,
	bounds_half: Vector3,
	feather: float,
	strength: float,
	use_sphere_falloff: bool,
	falloff_center: Vector3
) -> void:
	var max_radius: float = (
		minf(bounds_half.x, minf(bounds_half.y, bounds_half.z)) - voxel_size
	)
	for z in field.size.z:
		for y in field.size.y:
			for x in field.size.x:
				var world_pos := chunk_origin + Vector3(x, y, z) * voxel_size
				var push: float
				if use_sphere_falloff:
					push = bounds_sphere_push(
						world_pos, falloff_center, max_radius, feather, strength
					)
				else:
					push = bounds_edge_push(
						world_pos, bounds_center, bounds_half, feather, strength
					)
				if push == 0.0:
					continue
				var current := field.get_sample(x, y, z)
				field.set_sample(x, y, z, current + push)


static func build_chunk_field(
	density: WorldDensity,
	sample_size: Vector3i,
	chunk_origin: Vector3,
	chunk_extent: float
) -> SignedDensityField:
	var field := SignedDensityField.new(sample_size)
	var cells := sample_size.x - 1
	var step := chunk_extent / float(cells)
	for z in field.size.z:
		for y in field.size.y:
			for x in field.size.x:
				var world_pos := chunk_origin + Vector3(x, y, z) * step
				field.set_sample(x, y, z, density.evaluate(world_pos))
	return field
