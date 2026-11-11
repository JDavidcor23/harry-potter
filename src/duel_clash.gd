extends Node3D
## The beam-versus-beam duel effect: two crackling spell beams meeting in a
## violent clash point with arcs, sparks, spinning rings and shockwaves.
## Purely visual; the caller owns the rules and feeds it positions and the tug.

const Gothic := preload("res://src/gothic_dressing.gd")

## Seconds between re-rolls of the electric arcs (lower = more frantic).
const ARC_REFRESH := 0.045
const BEAM_ARCS := 2
const ARC_SEGMENTS := 7
const CLASH_ARCS := 6
const CLASH_ARC_SEGMENTS := 4
## Seconds between the automatic shockwave rings while the duel runs.
const RING_EVERY := 0.55

var _hero: Color
var _villain: Color
var _cores: Array[MeshInstance3D] = []
var _glows: Array[MeshInstance3D] = []
var _beam_arcs: Array = []  # [side][arc] -> Array[MeshInstance3D]
var _clash_arcs: Array = []  # [arc] -> Array[MeshInstance3D]
var _clash: Node3D
var _core: MeshInstance3D
var _halo: MeshInstance3D
var _rings: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _tip_lights: Array[OmniLight3D] = []
var _sparks: CPUParticles3D
var _arc_timer: float = 0.0
var _ring_timer: float = 0.0
var _pulse: float = 0.0
var _time: float = 0.0
var _ends: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]


## Builds every piece, hidden. [param hero] and [param villain] are the two
## spell colours.
func setup(hero: Color, villain: Color) -> void:
	_hero = hero
	_villain = villain
	for side in 2:
		var color: Color = hero if side == 0 else villain
		var core := _unit_beam(0.045, _glow_mat(color.lerp(Color.WHITE, 0.5), 1.1, 1.0))
		var glow := _unit_beam(0.11, _glow_mat(color, 0.75, 0.5))
		add_child(core)
		add_child(glow)
		_cores.append(core)
		_glows.append(glow)
		var arcs: Array = []
		for _a in BEAM_ARCS:
			arcs.append(_arc_pool(ARC_SEGMENTS, 0.035, color.lerp(Color.WHITE, 0.45)))
		_beam_arcs.append(arcs)
		var tip := OmniLight3D.new()
		tip.light_color = color
		tip.light_energy = 3.0
		tip.omni_range = 4.0
		add_child(tip)
		_tip_lights.append(tip)

	_clash = Node3D.new()
	add_child(_clash)
	_core = _sphere(0.17, _glow_mat(Color(1.0, 0.95, 0.8), 1.2, 1.0))
	_clash.add_child(_core)
	_halo = _sphere(0.45, _glow_mat(Color(1.0, 0.7, 0.3), 0.35, 0.4))
	_clash.add_child(_halo)
	for i in 2:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.5 + 0.2 * i
		torus.outer_radius = 0.53 + 0.2 * i
		ring.mesh = torus
		ring.material_override = _glow_mat(Color(1.0, 0.8, 0.4), 0.9, 0.9)
		_clash.add_child(ring)
		_rings.append(ring)
	_light = OmniLight3D.new()
	_light.light_energy = 7.0
	_light.omni_range = 11.0
	_light.shadow_enabled = true
	_light.light_volumetric_fog_energy = 2.0
	_clash.add_child(_light)
	_sparks = Gothic.embers(Vector3.ONE * 0.12, 90, 0.75, 0.085, Color(1.0, 0.85, 0.5))
	_sparks.direction = Vector3.UP
	_sparks.spread = 180.0
	_sparks.gravity = Vector3(0, -9.0, 0)
	_sparks.initial_velocity_min = 2.5
	_sparks.initial_velocity_max = 7.5
	_clash.add_child(_sparks)
	for _a in CLASH_ARCS:
		_clash_arcs.append(_arc_pool(CLASH_ARC_SEGMENTS, 0.03, Color(1.0, 0.95, 0.8)))
	set_active(false)


## Shows or hides the whole effect.
func set_active(on: bool) -> void:
	visible = on
	_sparks.emitting = on
	set_process(on)
	_pulse = 0.0


## World position of the clash point.
func clash_position() -> Vector3:
	return _clash.global_position


## Places the beams between the two wand tips. [param tug] is -1 (villain
## winning) .. +1 (player winning).
func update(player_tip: Vector3, villain_tip: Vector3, tug: float, delta: float) -> void:
	_time += delta
	_pulse = move_toward(_pulse, 0.0, delta * 4.0)
	var share: float = (tug + 1.0) * 0.5
	var clash: Vector3 = player_tip.lerp(villain_tip, share)
	_ends = [player_tip, villain_tip]
	_clash.global_position = clash
	var throb: float = 1.0 + 0.18 * sin(_time * 38.0) + _pulse * 0.6
	for side in 2:
		_place(_cores[side], _ends[side], clash, 1.0 + _pulse * 0.5)
		_place(_glows[side], _ends[side], clash, throb)
		_tip_lights[side].global_position = _ends[side]
	_core.scale = Vector3.ONE * (1.0 + 0.25 * sin(_time * 47.0) + _pulse * 0.9)
	_halo.scale = Vector3.ONE * (1.0 + 0.15 * sin(_time * 23.0) + _pulse * 0.7)
	_rings[0].rotation += Vector3(2.3, 3.1, 0.7) * delta
	_rings[1].rotation += Vector3(-1.7, 0.9, -2.9) * delta
	# The clash takes the colour of whoever is winning the push.
	_light.light_color = _villain.lerp(_hero, share).lerp(Color.WHITE, 0.35)
	_light.light_energy = 3.5 + 1.5 * sin(_time * 31.0) + _pulse * 4.0
	_arc_timer -= delta
	if _arc_timer <= 0.0:
		_arc_timer = ARC_REFRESH
		_reroll_arcs(clash)
	_ring_timer -= delta
	if _ring_timer <= 0.0:
		_ring_timer = RING_EVERY
		shockwave(clash, _villain.lerp(_hero, share), 2.2)


## One button mash: the clash flares.
func pulse() -> void:
	_pulse = 1.0


## A big push from either side: flare plus a large shockwave.
func surge(color: Color) -> void:
	_pulse = 1.6
	shockwave(_clash.global_position, color, 5.0)


## An expanding, fading ring of light centred on [param at].
func shockwave(at: Vector3, color: Color, size: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	ring.mesh = torus
	var m := _glow_mat(color.lerp(Color.WHITE, 0.25), 0.9, 0.9)
	ring.material_override = m
	ring.top_level = true
	get_parent().add_child(ring)
	ring.global_position = at
	ring.rotation = Vector3(randf_range(-0.5, 0.5), randf() * TAU, randf_range(-0.5, 0.5))
	ring.scale = Vector3.ONE * 0.2
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE * size, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.45)
	tw.chain().tween_callback(ring.queue_free)


func _reroll_arcs(clash: Vector3) -> void:
	for side in 2:
		for arc: Array in _beam_arcs[side]:
			_layout_arc(arc, _ends[side], clash, 0.22)
	for arc: Array in _clash_arcs:
		var out: Vector3 = Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)).normalized()
		_layout_arc(arc, clash, clash + out * randf_range(0.9, 2.3), 0.3)


## Lays a pool of segments as a jagged line from [param a] to [param b].
func _layout_arc(pool: Array, a: Vector3, b: Vector3, amplitude: float) -> void:
	var axis: Vector3 = (b - a)
	if axis.length() < 0.05:
		return
	var dir: Vector3 = axis.normalized()
	var from: Vector3 = a
	for i in pool.size():
		var u: float = float(i + 1) / float(pool.size())
		var to: Vector3 = a + axis * u
		if i < pool.size() - 1:
			var off := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
			off -= dir * off.dot(dir)
			to += off * amplitude
		_place(pool[i], from, to, 1.0)
		from = to


## Stretches a unit Y-aligned mesh from [param a] to [param b].
func _place(mi: MeshInstance3D, a: Vector3, b: Vector3, width: float) -> void:
	var d: Vector3 = b - a
	var length: float = d.length()
	if length < 0.01:
		return
	var q := Quaternion(Vector3.UP, d / length)
	mi.global_transform = Transform3D(Basis(q) * Basis.from_scale(Vector3(width, length, width)), (a + b) * 0.5)


func _arc_pool(count: int, thick: float, color: Color) -> Array:
	var m := _glow_mat(color, 1.0, 1.0)
	var pool: Array = []
	for _i in count:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(thick, 1.0, thick)
		mi.mesh = bm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		pool.append(mi)
	return pool


func _unit_beam(radius: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 1.0
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _sphere(radius: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Unshaded additive light material; [param energy] > 1 pushes it into bloom.
func _glow_mat(color: Color, energy: float, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
