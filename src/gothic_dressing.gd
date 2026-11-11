extends RefCounted
## Procedural gothic set dressing for the castle grounds: weathered stone,
## braziers with real flames, ruined arches, broken columns, dead trees, rune
## stones and drifting embers. Pure builders: each returns a node for the caller
## to add.

const IRON := Color(0.08, 0.08, 0.09)
const BARK := Color(0.09, 0.075, 0.065)


## Weathered dark stone, projected in world space so any mesh (whatever its
## UVs or scale) gets the same block size. [param tint] multiplies the texture.
static func stone_material(tint: Color = Color.WHITE, tile_metres: float = 3.0) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.1, 0.1, 0.115))
	ramp.set_color(1, Color(0.4, 0.39, 0.4))
	ramp.add_point(0.35, Color(0.25, 0.25, 0.27))
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
	normal.bump_strength = 10.0
	normal.noise = noise
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = albedo
	m.normal_enabled = true
	m.normal_texture = normal
	m.roughness = 0.92
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tile_metres
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## A Y-aligned tapered prism standing on its base (origin at the bottom).
static func tapered(bottom: float, top: float, height: float, m: Material, sides: int = 8) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.bottom_radius = bottom
	cm.top_radius = top
	cm.height = height
	cm.radial_segments = sides
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = m
	mi.position.y = height * 0.5
	return mi


## A box stretched between two local points, [param thick] wide.
static func strut(a: Vector3, b: Vector3, thick: float, m: Material) -> MeshInstance3D:
	var dir: Vector3 = b - a
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(thick, dir.length(), thick)
	mi.mesh = bm
	mi.material_override = m
	mi.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir.normalized())), (a + b) * 0.5)
	return mi


## A fluted stone column with plinth and capital, [param height] tall.
## [param broken] snaps the top off at an angle.
static func column(height: float, radius: float, m: Material, broken: bool = false) -> Node3D:
	var root := Node3D.new()
	root.add_child(tapered(radius * 1.7, radius * 1.45, 0.35, m, 4))
	var shaft := tapered(radius * 1.05, radius * 0.9, height, m, 10)
	shaft.position.y += 0.35
	root.add_child(shaft)
	var top := tapered(radius * 0.95, radius * (0.5 if broken else 1.6), 0.4, m, 4 if not broken else 6)
	top.position.y += 0.35 + height
	if broken:
		top.rotation = Vector3(0.25, 0.6, 0.18)
	root.add_child(top)
	return root


## A ruined gothic arch: two columns joined by a pointed arch. [param whole]
## false leaves one side of the arch fallen.
static func arch(width: float, height: float, m: Material, whole: bool = true) -> Node3D:
	var root := Node3D.new()
	var half: float = width * 0.5
	var spring: float = height + 0.75
	var apex := Vector3(0, spring + width * 0.75, 0)
	for side: float in [-1.0, 1.0]:
		var col := column(height, 0.42, m)
		col.position.x = side * half
		root.add_child(col)
		if side > 0.0 and not whole:
			continue
		# Two straight segments per side read as a pointed (lancet) curve.
		var knee := Vector3(side * half * 0.72, spring + width * 0.45, 0)
		root.add_child(strut(Vector3(side * half, spring, 0), knee, 0.55, m))
		root.add_child(strut(knee, apex, 0.55, m))
	return root


## A leaning standing stone with a glowing rune groove in [param glow].
static func rune_stone(height: float, m: Material, glow: Color) -> Node3D:
	var root := Node3D.new()
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(height * 0.42, height, height * 0.2)
	slab.mesh = bm
	slab.material_override = m
	slab.position.y = height * 0.5
	root.add_child(slab)
	var rune_mat := StandardMaterial3D.new()
	rune_mat.albedo_color = glow
	rune_mat.emission_enabled = true
	rune_mat.emission = glow
	rune_mat.emission_energy_multiplier = 3.5
	for i in 3:
		var groove := MeshInstance3D.new()
		var gm := BoxMesh.new()
		gm.size = Vector3(height * (0.22 - 0.05 * i), height * 0.04, 0.03)
		groove.mesh = gm
		groove.material_override = rune_mat
		groove.position = Vector3(0, height * (0.72 - 0.16 * i), height * 0.1)
		groove.rotation.z = 0.5 - 0.5 * i
		root.add_child(groove)
	var light := OmniLight3D.new()
	light.light_color = glow
	light.light_energy = 0.8
	light.omni_range = 3.0
	light.position = Vector3(0, height * 0.6, height * 0.4)
	root.add_child(light)
	root.rotation.z = 0.08
	return root


## A leafless tree, deterministic for a given [param tree_seed].
static func dead_tree(height: float, tree_seed: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = tree_seed
	var m := StandardMaterial3D.new()
	m.albedo_color = BARK
	m.roughness = 1.0
	var root := Node3D.new()
	_branch(root, height * 0.5, height * 0.055, 4, rng, m)
	return root


static func _branch(parent: Node3D, length: float, radius: float, depth: int, rng: RandomNumberGenerator, m: Material) -> void:
	parent.add_child(tapered(radius, radius * 0.62, length, m, 6))
	if depth <= 0:
		return
	for i in rng.randi_range(2, 3):
		var joint := Node3D.new()
		joint.position.y = length * rng.randf_range(0.7, 1.0)
		joint.rotation = Vector3(
			rng.randf_range(0.35, 0.9) * (1.0 if rng.randf() > 0.5 else -1.0),
			rng.randf_range(0.0, TAU),
			rng.randf_range(-0.5, 0.5))
		parent.add_child(joint)
		_branch(joint, length * rng.randf_range(0.6, 0.78), radius * 0.6, depth - 1, rng, m)


## A stone pedestal topped by an iron fire bowl; the bowl rim sits at
## [param height]. Pass 0 for a bare bowl (wall bracket).
static func brazier(height: float, m: Material) -> Node3D:
	var root := Node3D.new()
	var iron := StandardMaterial3D.new()
	iron.albedo_color = IRON
	iron.metallic = 0.8
	iron.roughness = 0.55
	if height > 0.0:
		root.add_child(tapered(0.42, 0.34, 0.3, m, 6))
		var shaft := tapered(0.2, 0.15, height - 0.5, m, 6)
		shaft.position.y += 0.3
		root.add_child(shaft)
	var bowl := tapered(0.16, 0.42, 0.3, iron, 10)
	bowl.position.y += maxf(height - 0.3, 0.0)
	root.add_child(bowl)
	return root


## Flames plus rising sparks; origin is the base of the fire.
static func fire(size: float = 1.0) -> Node3D:
	var root := Node3D.new()
	var flames := CPUParticles3D.new()
	flames.amount = 26
	flames.lifetime = 0.75
	flames.mesh = _quad(0.42 * size)
	flames.material_override = _glow_particle_material()
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = 0.14 * size
	flames.direction = Vector3.UP
	flames.spread = 12.0
	flames.gravity = Vector3(0, 1.6, 0)
	flames.initial_velocity_min = 0.5 * size
	flames.initial_velocity_max = 1.1 * size
	flames.scale_amount_min = 0.7
	flames.scale_amount_max = 1.2
	flames.scale_amount_curve = _curve([Vector2(0, 0.55), Vector2(0.25, 1.0), Vector2(1, 0.0)])
	flames.color_ramp = _ramp([
		Color(1.0, 0.85, 0.45, 0.0), Color(1.0, 0.6, 0.15, 0.9),
		Color(0.9, 0.25, 0.04, 0.6), Color(0.3, 0.05, 0.0, 0.0)])
	root.add_child(flames)
	root.add_child(embers(Vector3(0.15, 0.1, 0.15) * size, 10, 2.2, 0.06))
	return root


## Glowing sparks drifting upward inside a box of half-size [param extents].
static func embers(extents: Vector3, amount: int, lifetime: float, size: float, color: Color = Color(1.0, 0.5, 0.12)) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.randomness = 1.0
	p.mesh = _quad(size)
	p.material_override = _glow_particle_material()
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3(0.3, 1, 0.1)
	p.spread = 35.0
	p.gravity = Vector3(0.15, 0.25, 0)
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.9
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	var faded := Color(color.r, color.g * 0.5, color.b * 0.5, 0.0)
	p.color_ramp = _ramp([Color(color, 0.0), Color(color, 1.0), Color(color, 0.8), faded])
	return p


static func _quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	return q


static func _curve(points: Array) -> Curve:
	var c := Curve.new()
	for pt: Vector2 in points:
		c.add_point(pt)
	return c


static func _ramp(colors: Array) -> Gradient:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	for i in colors.size():
		offsets.append(float(i) / float(colors.size() - 1))
	g.offsets = offsets
	g.colors = PackedColorArray(colors)
	return g


## Additive, camera-facing soft blob tinted per particle.
static func _glow_particle_material() -> StandardMaterial3D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = tex
	m.albedo_color = Color(0.9, 0.9, 0.9)
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
