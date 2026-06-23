// Zylann voxel-tools: Transvoxel LOD stitch helpers (from voxel-tools docs / demo).
// https://voxel-tools.readthedocs.io/en/stable/smooth_terrain/

uniform int u_transition_mask;

float get_transvoxel_secondary_factor(int idata) {
	int cell_border_mask = (idata >> 0) & 63;
	int vertex_border_mask = (idata >> 8) & 63;
	int m = u_transition_mask & cell_border_mask;
	float t = float(m != 0);
	t *= float((vertex_border_mask & ~u_transition_mask) == 0);
	return t;
}

vec3 get_transvoxel_position(vec3 vertex_pos, vec4 fdata) {
	int idata = floatBitsToInt(fdata.a);

	float secondary_factor = get_transvoxel_secondary_factor(idata);
	vec3 secondary_position = fdata.xyz;
	vec3 pos = mix(vertex_pos, secondary_position, secondary_factor);

	int itransition = (idata >> 16) & 0xff;
	float transition_cull = float(itransition == 0 || (itransition & u_transition_mask) != 0);
	pos *= transition_cull;

	return pos;
}
