extends Node3D
## A glowing spell projectile that homes on a node (or flies to a point).

const Fx := preload("res://src/fx.gd")

## Emitted on arrival; [param target] is the homed node or null.
signal arrived(bolt: Node3D, target: Node3D)

var speed: float = 20.0
var target: Node3D
var target_point: Vector3
var _offset: Vector3


## [param homing] may be null; then the bolt flies to [param point].
func fire(from: Vector3, homing: Node3D, point: Vector3, color: Color, bolt_speed: float, aim_offset: Vector3 = Vector3.ZERO) -> void:
	global_position = from
	target = homing
	target_point = point
	speed = bolt_speed
	_offset = aim_offset
	var core := Fx.sphere(0.16, Fx.mat(color, 8.0))
	add_child(core)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.0
	light.omni_range = 4.0
	add_child(light)


func _process(delta: float) -> void:
	if is_instance_valid(target):
		target_point = target.global_position + _offset
	var to: Vector3 = target_point - global_position
	var step: float = speed * delta
	if to.length() <= step:
		global_position = target_point
		arrived.emit(self, target if is_instance_valid(target) else null)
		queue_free()
		return
	global_position += to.normalized() * step
	# Sparkle trail.
	if randf() < 0.6:
		var spark := Fx.sphere(0.06, Fx.mat(Color(1, 0.9, 0.5), 4.0))
		get_parent().add_child(spark)
		spark.global_position = global_position
		var tw := spark.create_tween()
		tw.tween_property(spark, "scale", Vector3.ZERO, 0.3)
		tw.tween_callback(spark.queue_free)
