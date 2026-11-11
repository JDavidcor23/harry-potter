extends Node3D
## The golden snitch: a gold ball with flapping wings that wanders the arena
## and darts away when the player gets close.

const Fx := preload("res://src/fx.gd")

var speed: float = 5.0
var bounds: AABB = AABB(Vector3(-6, 0.9, -3), Vector3(12, 1.4, 8))
var flee_from: Node3D
var _goal: Vector3
var _wings: Array[Node3D] = []
var _t: float = 0.0


func _ready() -> void:
	var gold := Fx.mat(Color(1.0, 0.78, 0.15), 1.2, 0.2, 0.9)
	add_child(Fx.sphere(0.2, gold))
	var wing_mat := Fx.mat(Color(1, 1, 0.92, 0.75), 0.6, 0.3)
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.15 * side, 0.05, 0)
		var wing := Fx.box(Vector3(0.55, 0.02, 0.22), wing_mat)
		wing.position = Vector3(0.28 * side, 0, 0)
		pivot.add_child(wing)
		add_child(pivot)
		_wings.append(pivot)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.85, 0.3)
	light.light_energy = 2.5
	light.omni_range = 3.5
	add_child(light)
	_pick_goal()


func _process(delta: float) -> void:
	_t += delta
	for i in _wings.size():
		_wings[i].rotation.z = sin(_t * 40.0) * 0.8 * (1.0 if i == 0 else -1.0)
	var spd: float = speed
	if is_instance_valid(flee_from):
		var away: Vector3 = global_position - (flee_from.global_position + Vector3.UP)
		if away.length() < 2.6 and global_position.distance_to(_goal) < 1.5:
			_goal = _clamp(global_position + Vector3(away.x, 0, away.z).normalized() * 4.0
				+ Vector3(randf_range(-2, 2), randf_range(-0.5, 0.5), randf_range(-2, 2)))
			spd *= 1.4
	var to: Vector3 = _goal - global_position
	if to.length() < 0.3:
		_pick_goal()
	else:
		global_position += to.normalized() * min(spd * delta, to.length())
		global_position.y += sin(_t * 6.0) * 0.01
		look_at(global_position + Vector3(to.x, 0, to.z + 0.001), Vector3.UP)


func _pick_goal() -> void:
	_goal = bounds.position + Vector3(randf() * bounds.size.x, randf() * bounds.size.y, randf() * bounds.size.z)


func _clamp(p: Vector3) -> Vector3:
	var lo: Vector3 = bounds.position
	var hi: Vector3 = bounds.end
	return Vector3(clamp(p.x, lo.x, hi.x), clamp(p.y, lo.y, hi.y), clamp(p.z, lo.z, hi.z))
