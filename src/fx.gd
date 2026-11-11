extends RefCounted
## Small procedural mesh/material/effect helpers shared by the scene scripts.

## Builds a StandardMaterial3D; [param glow] > 0 makes it emissive.
static func mat(color: Color, glow: float = 0.0, rough: float = 0.6, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func box(size: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	return mi


static func sphere(radius: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	mi.material_override = m
	return mi


static func cylinder(radius: float, height: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = m
	return mi


## Points a Y-aligned unit cylinder from [param a] to [param b].
static func place_beam(beam: Node3D, a: Vector3, b: Vector3) -> void:
	var dir: Vector3 = b - a
	var length: float = dir.length()
	if length < 0.01:
		beam.global_position = a
		return
	var q := Quaternion(Vector3.UP, dir / length)
	beam.global_transform = Transform3D(Basis(q) * Basis.from_scale(Vector3(1, length, 1)), (a + b) * 0.5)


## Spawns little brick chunks that fly out, fall and fade.
static func shatter(parent: Node, at: Vector3, color: Color, count: int = 8) -> void:
	for i in count:
		var chunk := box(Vector3.ONE * randf_range(0.1, 0.22), mat(color, 0.0, 0.3))
		parent.add_child(chunk)
		chunk.global_position = at
		var target: Vector3 = at + Vector3(randf_range(-1.6, 1.6), randf_range(-0.2, 1.4), randf_range(-1.6, 1.6))
		var tw := chunk.create_tween().set_parallel(true)
		tw.tween_property(chunk, "global_position", target, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(chunk, "rotation", Vector3(randf() * 6, randf() * 6, randf() * 6), 0.7)
		tw.chain().tween_property(chunk, "global_position:y", 0.05, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.chain().tween_property(chunk, "scale", Vector3.ZERO, 0.4)
		tw.chain().tween_callback(chunk.queue_free)


## Expanding glowing ring/flash at a point.
static func burst(parent: Node, at: Vector3, color: Color, size: float = 1.5) -> void:
	var s := sphere(0.3, mat(Color(color.r, color.g, color.b, 0.8), 6.0))
	parent.add_child(s)
	s.global_position = at
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 6.0
	light.omni_range = size * 4.0
	s.add_child(light)
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "scale", Vector3.ONE * size * 3.0, 0.35)
	tw.tween_property(light, "light_energy", 0.0, 0.35)
	tw.chain().tween_callback(s.queue_free)
