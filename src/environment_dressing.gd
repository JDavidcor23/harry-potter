extends RefCounted
## Procedural ground dressing: textured grass ground, wind-swayed grass blades
## and a cobblestone path. Pure builders: each returns a node for the caller to add.

const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 root_color : source_color = vec3(0.07, 0.2, 0.04);
uniform vec3 tip_color : source_color = vec3(0.5, 0.78, 0.22);
uniform float sway = 0.12;
varying float tip;
void vertex() {
	tip = UV.y;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float s = sin(TIME * 1.8 + wp.x * 0.6 + wp.z * 0.45) * sway * tip * tip;
	VERTEX.x += s;
	VERTEX.z += s * 0.6;
}
void fragment() {
	ALBEDO = mix(root_color, tip_color, tip) * COLOR.rgb;
	ROUGHNESS = 0.75;
	SPECULAR = 0.2;
	BACKLIGHT = vec3(0.25, 0.4, 0.1);
}
"""


## Large ground plane with a tiling noise grass texture and matching normal map.
static func grass_ground(size: float, tile_metres: float) -> MeshInstance3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.12, 0.26, 0.07))
	ramp.set_color(1, Color(0.36, 0.55, 0.18))
	ramp.add_point(0.55, Color(0.22, 0.42, 0.12))
	var albedo := NoiseTexture2D.new()
	albedo.width = 512
	albedo.height = 512
	albedo.seamless = true
	albedo.noise = noise
	albedo.color_ramp = ramp
	var normal := NoiseTexture2D.new()
	normal.width = 512
	normal.height = 512
	normal.seamless = true
	normal.as_normal_map = true
	normal.bump_strength = 6.0
	normal.noise = noise
	var m := StandardMaterial3D.new()
	m.albedo_texture = albedo
	m.normal_enabled = true
	m.normal_texture = normal
	m.roughness = 0.95
	m.uv1_scale = Vector3.ONE * (size / tile_metres)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = m
	return mi


## Scatters [param count] grass blades over [param area] (XZ rect), skipping
## every rect in [param holes].
static func grass_blades(area: Rect2, holes: Array, count: int) -> MultiMeshInstance3D:
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GRASS_SHADER
	mat.shader = sh
	var blade := _blade_mesh()
	blade.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = blade
	var xforms: Array[Transform3D] = []
	var tries: int = 0
	while xforms.size() < count and tries < count * 3:
		tries += 1
		var p := Vector2(area.position.x + randf() * area.size.x, area.position.y + randf() * area.size.y)
		var blocked := false
		for h: Rect2 in holes:
			if h.has_point(p):
				blocked = true
				break
		if blocked:
			continue
		var b := Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.RIGHT, randf_range(-0.25, 0.25))
		var s: float = randf_range(0.6, 1.4)
		xforms.append(Transform3D(b.scaled(Vector3(s, s * randf_range(0.8, 1.3), s)), Vector3(p.x, 0.0, p.y)))
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		var tint: float = randf_range(0.75, 1.15)
		mm.set_instance_color(i, Color(tint, tint * randf_range(0.95, 1.05), tint * 0.9))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## Cobblestone path covering [param rect] (XZ), stones on a jittered grid.
static func cobble_path(rect: Rect2, spacing: float) -> Node3D:
	var root := Node3D.new()
	var dirt := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(rect.size.x + 0.4, 0.04, rect.size.y + 0.4)
	dirt.mesh = bm
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.3, 0.24, 0.17)
	dm.roughness = 1.0
	dirt.material_override = dm
	dirt.position = Vector3(rect.get_center().x, 0.0, rect.get_center().y)
	root.add_child(dirt)

	var stone := CylinderMesh.new()
	stone.radial_segments = 7
	stone.rings = 1
	stone.top_radius = 0.24
	stone.bottom_radius = 0.28
	stone.height = 0.1
	var sm := StandardMaterial3D.new()
	sm.vertex_color_use_as_albedo = true
	sm.albedo_color = Color(0.48, 0.46, 0.43)
	sm.roughness = 0.85
	stone.material = sm
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = stone
	var xforms: Array[Transform3D] = []
	var z: float = rect.position.y + spacing * 0.5
	var row: int = 0
	while z < rect.end.y:
		var x: float = rect.position.x + spacing * (0.5 if row % 2 == 0 else 1.0)
		while x < rect.end.x:
			var p := Vector3(x + randf_range(-0.08, 0.08), 0.04, z + randf_range(-0.08, 0.08))
			var s: float = randf_range(0.85, 1.15)
			var b := Basis(Vector3.UP, randf() * TAU).scaled(Vector3(s * randf_range(0.9, 1.2), randf_range(0.8, 1.2), s))
			xforms.append(Transform3D(b, p))
			x += spacing
		z += spacing * 0.88
		row += 1
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		var g: float = randf_range(0.42, 0.68)
		mm.set_instance_color(i, Color(g, g * 0.97, g * 0.92))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	root.add_child(mmi)
	return root


## A tapered three-segment blade, UV.y = 0 at the root and 1 at the tip.
static func _blade_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w: Array = [0.045, 0.035, 0.02, 0.0]
	var y: Array = [0.0, 0.14, 0.28, 0.42]
	for i in 3:
		var a0 := Vector3(-w[i], y[i], 0)
		var a1 := Vector3(w[i], y[i], 0)
		var b0 := Vector3(-w[i + 1], y[i + 1], 0.02 * i)
		var b1 := Vector3(w[i + 1], y[i + 1], 0.02 * i)
		for v in [[a0, i], [a1, i], [b1, i + 1], [a0, i], [b1, i + 1], [b0, i + 1]]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0.5, float(v[1]) / 3.0))
			st.set_color(Color.WHITE)
			st.add_vertex(v[0])
	return st.commit()
