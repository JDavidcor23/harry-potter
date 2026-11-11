extends Control
## A segmented health bar: [member current] out of [member maximum] hits.
## Damage leaves a pale trail that drains after a short delay; healing fills up
## smoothly. Drawn procedurally so it stays crisp at any size.

@export var maximum: int = 5:
	set(v):
		maximum = maxi(v, 1)
		queue_redraw()
@export var current: int = 5:
	set(v):
		var before := current
		current = clampi(v, 0, maximum)
		if current < before:
			_trail_hold = TRAIL_DELAY
			_flash = 1.0
		queue_redraw()
## Bar size in pixels.
@export var bar_size: Vector2 = Vector2(300, 20):
	set(v):
		bar_size = v
		custom_minimum_size = v
		queue_redraw()
## Main fill color; the top gets lighter and the bottom darker.
@export var fill_color: Color = Color(0.62, 0.08, 0.14)
@export var frame_color: Color = Color(0.78, 0.64, 0.38)
@export var back_color: Color = Color(0.05, 0.04, 0.08, 0.88)
@export var trail_color: Color = Color(1.0, 0.88, 0.7)

const TRAIL_DELAY := 0.35
const TRAIL_SPEED := 0.9
const FILL_SPEED := 2.5

## Displayed fill and trail, as fractions of the bar (0..1).
var _shown: float = 1.0
var _trail: float = 1.0
var _trail_hold: float = 0.0
var _flash: float = 0.0


func _ready() -> void:
	custom_minimum_size = bar_size
	_shown = _target()
	_trail = _shown


func _process(delta: float) -> void:
	var target := _target()
	if _shown > target:
		_shown = target
	else:
		_shown = move_toward(_shown, target, FILL_SPEED * delta)
	if _trail_hold > 0.0:
		_trail_hold -= delta
	else:
		_trail = move_toward(_trail, _shown, TRAIL_SPEED * delta)
	_trail = maxf(_trail, _shown)
	_flash = move_toward(_flash, 0.0, delta * 4.0)
	queue_redraw()


func _target() -> float:
	return float(current) / float(maximum)


func _draw() -> void:
	var outer := Rect2(Vector2.ZERO, bar_size)
	var rad: int = int(bar_size.y * 0.5)
	_box(outer.grow(2), rad + 2, Color(0, 0, 0, 0.6))
	_box(outer, rad, frame_color)
	var inner := outer.grow(-2)
	_box(inner, rad - 2, back_color)
	var track := inner.grow(-2)
	var trad: int = maxi(rad - 4, 1)

	if _trail > _shown:
		_box(Rect2(track.position, Vector2(track.size.x * _trail, track.size.y)), trad, trail_color)
	if _shown > 0.0:
		var fill := Rect2(track.position, Vector2(track.size.x * _shown, track.size.y))
		_gradient_box(fill, trad, fill_color.lightened(0.25), fill_color.darkened(0.35))
		# Thin sheen along the top.
		draw_line(fill.position + Vector2(trad, 2), Vector2(fill.end.x - trad, fill.position.y + 2), Color(1, 1, 1, 0.18), 1.5)
	if _flash > 0.0:
		_box(track, trad, Color(1, 1, 1, _flash * 0.35))

	# Segment ticks, one per hit.
	for i in range(1, maximum):
		var x: float = track.position.x + track.size.x * i / maximum
		draw_line(Vector2(x, track.position.y + 1), Vector2(x, track.end.y - 1), Color(0, 0, 0, 0.55), 2.0)


func _box(r: Rect2, rad: int, col: Color) -> void:
	if r.size.x <= 0.0:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(mini(rad, int(r.size.x * 0.5)))
	sb.anti_aliasing = true
	draw_style_box(sb, r)


## Rounded box shaded darker at the bottom and lighter at the top.
func _gradient_box(r: Rect2, rad: int, top: Color, bottom: Color) -> void:
	_box(r, rad, bottom)
	_box(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.7)), rad, bottom.lerp(top, 0.5))
	_box(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.4)), rad, top)
