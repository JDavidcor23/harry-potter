extends Control
## Draws a row of enchanted hearts: [member current] filled out of [member maximum].
## Filled hearts are glossy gems in a gold setting; lost hearts become dark,
## cracked glass. A heart that is lost flashes and shrinks; a heart that is
## regained pops in.

@export var maximum: int = 5:
	set(v):
		maximum = v
		_resize()
@export var current: int = 5:
	set(v):
		if v < current:
			for i in range(maxi(v, 0), mini(current, maximum)):
				_anim[i] = -1.0
		elif v > current:
			for i in range(maxi(current, 0), mini(v, maximum)):
				_anim[i] = 1.0
		current = v
		queue_redraw()
@export var heart_size: float = 34.0
## Main gem color of a filled heart.
@export var fill_color: Color = Color(0.86, 0.08, 0.16)
## Color of a lost heart.
@export var empty_color: Color = Color(0.09, 0.06, 0.08, 0.85)
## Metal of the heart setting.
@export var rim_color: Color = Color(0.93, 0.76, 0.36)
## Painted art for a filled heart. When set, it replaces the procedural shape.
@export var full_texture: Texture2D
## Painted art for a lost heart. Falls back to a darkened [member full_texture].
@export var empty_texture: Texture2D
## How much bigger than [member heart_size] the art is drawn, since painted
## sprites carry transparent padding around the gem.
@export var texture_scale: float = 0.98

const SPACING := 1.2
const ANIM_TIME := 0.45

var _shape: PackedVector2Array
## Per-heart animation clock: >0 gaining, <0 losing, 0 idle.
var _anim: Dictionary = {}
var _time: float = 0.0


func _ready() -> void:
	for i in 48:
		var t: float = TAU * i / 48.0
		var x: float = 16.0 * pow(sin(t), 3)
		var y: float = -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
		_shape.append(Vector2(x, y + 1.5) / 34.0)
	_resize()


func _process(delta: float) -> void:
	_time += delta
	for k in _anim.keys():
		var v: float = _anim[k]
		v = move_toward(v, 0.0, delta / ANIM_TIME)
		if is_zero_approx(v):
			_anim.erase(k)
		else:
			_anim[k] = v
	queue_redraw()


func _resize() -> void:
	custom_minimum_size = Vector2(maximum * heart_size * SPACING, heart_size * 1.1)
	queue_redraw()


func _draw() -> void:
	if _shape.is_empty():
		return
	for i in maximum:
		var c := Vector2(heart_size * 0.6 + i * heart_size * SPACING, heart_size * 0.55)
		var filled: bool = i < current
		var s: float = heart_size
		var flash: float = 0.0
		if _anim.has(i):
			var a: float = _anim[i]
			if a < 0.0:
				# Losing: swell, flash white, settle into the empty shell.
				var p: float = 1.0 + a
				s *= 1.0 + 0.35 * sin(p * PI)
				flash = 1.0 - p
			else:
				var p2: float = 1.0 - a
				s *= 0.4 + 0.6 * ease(p2, -2.0) + 0.15 * sin(p2 * PI)
		elif filled:
			# Gentle heartbeat, staggered per heart.
			s *= 1.0 + 0.04 * maxf(0.0, sin(_time * 4.0 - i * 0.5)) ** 6
		_draw_heart(c, s, filled, flash)


func _draw_heart(c: Vector2, s: float, filled: bool, flash: float) -> void:
	if full_texture:
		_draw_heart_texture(c, s, filled, flash)
		return
	# Soft magical glow behind filled hearts.
	if filled:
		var glow := fill_color
		glow.a = 0.22
		draw_colored_polygon(_scaled(c, s * 1.38), glow)
	# Dark backing, then gold setting with a darker inner bevel.
	draw_colored_polygon(_scaled(c, s * 1.24), Color(0.08, 0.04, 0.02, 0.9))
	draw_colored_polygon(_scaled(c, s * 1.16), rim_color)
	draw_colored_polygon(_scaled(c, s * 1.04), rim_color.darkened(0.55))

	var body := _scaled(c, s * 0.98)
	if filled or flash > 0.0:
		# Vertical gradient: bright top, deep bottom.
		var top := fill_color.lightened(0.35)
		var bottom := fill_color.darkened(0.55)
		var cols := PackedColorArray()
		for p in body:
			var t: float = clampf((p.y - (c.y - s * 0.45)) / (s * 0.9), 0.0, 1.0)
			var col: Color = top.lerp(bottom, t)
			if flash > 0.0:
				col = col.lerp(Color.WHITE, flash * 0.8)
			cols.append(col)
		draw_polygon(body, cols)
		# Glass highlights.
		draw_colored_polygon(_ellipse(c + Vector2(-0.2, -0.17) * s, Vector2(0.13, 0.08) * s, -0.6), Color(1, 1, 1, 0.75))
		draw_circle(c + Vector2(0.2, -0.2) * s, s * 0.04, Color(1, 1, 1, 0.55))
		draw_colored_polygon(_ellipse(c + Vector2(0.08, 0.2) * s, Vector2(0.12, 0.05) * s, 0.7), Color(1, 1, 1, 0.12))
	else:
		draw_colored_polygon(body, empty_color)
		# A crack across the empty shell.
		var crack := PackedVector2Array([
			c + Vector2(-0.02, -0.3) * s, c + Vector2(0.06, -0.12) * s,
			c + Vector2(-0.05, 0.02) * s, c + Vector2(0.04, 0.18) * s,
			c + Vector2(0.0, 0.32) * s,
		])
		draw_polyline(crack, rim_color.darkened(0.35), maxf(1.0, s * 0.045), true)


func _draw_heart_texture(c: Vector2, s: float, filled: bool, flash: float) -> void:
	var tex_size: Vector2 = full_texture.get_size()
	var d := Vector2(s * texture_scale * tex_size.x / tex_size.y, s * texture_scale)
	var rect := Rect2(c - d * 0.5, d)
	if filled or flash > 0.0:
		draw_texture_rect(full_texture, rect, false)
		if flash > 0.0:
			draw_circle(c, s * 0.5, Color(1, 1, 1, flash * 0.7))
	elif empty_texture:
		draw_texture_rect(empty_texture, rect, false)
	else:
		draw_texture_rect(full_texture, rect, false, Color(0.25, 0.2, 0.22, 0.85))


func _scaled(c: Vector2, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in _shape:
		out.append(c + p * s)
	return out


func _ellipse(c: Vector2, r: Vector2, rot: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 16:
		var t: float = TAU * i / 16.0
		out.append(c + Vector2(cos(t) * r.x, sin(t) * r.y).rotated(rot))
	return out
