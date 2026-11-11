extends Node3D
## A villain projectile: rock, cursed rock or green spell ray.
## Flies toward a target; everything but cursed pieces can be deflected back
## at the villain with Protego.

const Fx := preload("res://src/fx.gd")

enum State { INCOMING, DEFLECTED, DONE }

const KIND_ROCK := "rock"
const KIND_CURSED := "cursed"
const KIND_SPELL := "spell"

const CURSED_COLOR := Color(0.55, 0.0, 0.08)
const SPELL_COLOR := Color(0.25, 1.0, 0.35)

## Emitted when the path ends. The scene decides if it hit someone.
signal landed(brick: Node3D)

var state: State = State.INCOMING
var kind: String = KIND_ROCK
var cursed: bool = false
var color: Color
var _from: Vector3
var _to: Vector3
var _duration: float = 1.0
var _arc: float = 2.0
var _t: float = 0.0
var _spin: Vector3
var _visual: Node3D


## Builds the visual for [param projectile_kind]; also used for the piece the
## villain holds during his wind-up.
static func make_visual(projectile_kind: String) -> Node3D:
	match projectile_kind:
		KIND_CURSED:
			# A rock glowing with a red curse.
			return _rock(Fx.mat(CURSED_COLOR, 2.5, 0.6))
		KIND_SPELL:
			var orb := Fx.sphere(0.28, Fx.mat(SPELL_COLOR, 8.0))
			var light := OmniLight3D.new()
			light.light_color = SPELL_COLOR
			light.light_energy = 4.0
			light.omni_range = 4.0
			orb.add_child(light)
			return orb
	var g: float = randf_range(0.35, 0.5)
	return _rock(Fx.mat(Color(g, g * 0.95, g * 0.88), 0.0, 0.95))


static func _rock(material: Material) -> Node3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.55
	sm.height = 0.9
	sm.radial_segments = 7
	sm.rings = 4
	mi.mesh = sm
	mi.material_override = material
	mi.scale = Vector3(randf_range(0.85, 1.2), randf_range(0.8, 1.0), randf_range(0.85, 1.2))
	return mi


## Configures and launches the projectile. Call after adding it to the tree.
func launch(from: Vector3, to: Vector3, duration: float, projectile_kind: String, arc: float) -> void:
	kind = projectile_kind
	cursed = kind == KIND_CURSED
	_visual = make_visual(kind)
	add_child(_visual)
	match kind:
		KIND_CURSED:
			color = CURSED_COLOR
			var light := OmniLight3D.new()
			light.light_color = Color(1, 0.1, 0.2)
			light.light_energy = 3.0
			light.omni_range = 3.0
			add_child(light)
		KIND_SPELL:
			color = SPELL_COLOR
		_:
			color = Color(0.42, 0.4, 0.37)
	_spin = Vector3.ZERO if kind == KIND_SPELL else Vector3(randf_range(3, 7), randf_range(2, 6), randf_range(1, 4))
	_set_path(from, to, duration, arc)


## Sends the projectile back toward [param target] (Protego).
func deflect(target: Vector3, duration: float) -> void:
	state = State.DEFLECTED
	_set_path(global_position, target, duration, 0.0 if kind == KIND_SPELL else 1.0)
	_spin *= -2.0
	if kind == KIND_SPELL:
		# A returned ray turns gold: it is the wizard's now.
		var orb := _visual as MeshInstance3D
		orb.material_override = Fx.mat(Color(1.0, 0.8, 0.25), 8.0)


func progress() -> float:
	return _t / _duration


func _set_path(from: Vector3, to: Vector3, duration: float, arc: float) -> void:
	_from = from
	_to = to
	_duration = max(duration, 0.05)
	_arc = arc
	_t = 0.0
	global_position = from


func _process(delta: float) -> void:
	if state == State.DONE:
		return
	_t += delta
	var u: float = clamp(_t / _duration, 0.0, 1.0)
	global_position = _from.lerp(_to, u) + Vector3.UP * _arc * 4.0 * u * (1.0 - u)
	_visual.rotation += _spin * delta
	if cursed or kind == KIND_SPELL:
		_visual.scale = Vector3.ONE * (1.0 + 0.15 * sin(_t * 18.0))
	if kind == KIND_SPELL and randf() < 0.7:
		_trail()
	if u >= 1.0:
		landed.emit(self)


func _trail() -> void:
	var spark := Fx.sphere(0.1, Fx.mat(color if state == State.INCOMING else Color(1, 0.85, 0.3), 5.0))
	get_parent().add_child(spark)
	spark.global_position = global_position
	var tw := spark.create_tween()
	tw.tween_property(spark, "scale", Vector3.ZERO, 0.35)
	tw.tween_callback(spark.queue_free)


## Breaks the projectile (chunks for solids, a flash for spells) and removes it.
func smash() -> void:
	if state == State.DONE:
		return
	state = State.DONE
	if kind == KIND_SPELL:
		Fx.burst(get_parent(), global_position, color, 0.8)
	else:
		Fx.shatter(get_parent(), global_position, color)
	queue_free()
