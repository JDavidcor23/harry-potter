extends CanvasLayer
## On-screen UI: villain/player hearts, deflect counter, duel tug bar,
## banners and end screens. Styled as an old wizarding-school grimoire:
## engraved serif lettering, gold filigree and glowing arcane accents.

const HealthBar := preload("res://src/health_bar.gd")

const FONT_PATH := "res://assets/fonts/Cinzel.ttf"
const FONT_BODY_WEIGHT := 500
const FONT_TITLE_WEIGHT := 700
const UI_DIR := "res://assets/ui/"
## Painted bar frame: inner channel rows and horizontal inset, in source pixels.
const BAR_CHANNEL := Vector2(26, 51)
const BAR_CAP := 12.0
## Panel frame border width, in source pixels, for 9-slice stretching.
const PANEL_MARGIN := 40.0
const PANEL_SMALL_MARGIN := 20.0

const GOLD := Color(0.95, 0.79, 0.4)
const GOLD_DARK := Color(0.45, 0.3, 0.1)
const PARCHMENT := Color(0.97, 0.91, 0.76)
const INK := Color(0.1, 0.05, 0.02)
const ARCANE := Color(0.45, 0.8, 1.0)
const EMERALD := Color(0.2, 0.78, 0.42)


## Two-color bar showing where the beam clash sits (-1 player .. +1 villain).
class TugBar extends Control:
	var tug: float = 0.0:
		set(v):
			tug = v
			queue_redraw()
	## Painted frame; when null a procedural gold frame is drawn instead.
	var frame: Texture2D
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if frame:
			r = _draw_frame()
		var rad: float = r.size.y * 0.5
		var split: float = r.position.x + r.size.x * (tug + 1.0) * 0.5
		if not frame:
			_rounded(r.grow(7), rad + 7, INK)
			_rounded(r.grow(5), rad + 5, GOLD)
			_rounded(r.grow(2), rad + 2, GOLD_DARK)
		# Player beam (gold) and villain beam (emerald), each with a sheen.
		_beam(Rect2(r.position, Vector2(split - r.position.x, r.size.y)), Color(0.78, 0.55, 0.22), Color(1.0, 0.86, 0.55), rad)
		_beam(Rect2(split, r.position.y, r.end.x - split, r.size.y), Color(0.1, 0.42, 0.25), Color(0.45, 0.8, 0.55), rad)
		# Clash point: pulsing white-hot orb.
		var h: float = r.size.y
		var pulse: float = 0.5 + 0.5 * sin(_time * 18.0)
		var p := Vector2(split, r.get_center().y)
		draw_circle(p, h * (1.3 + 0.25 * pulse), Color(1, 0.95, 0.7, 0.18))
		draw_circle(p, h * (0.9 + 0.15 * pulse), Color(1, 0.95, 0.75, 0.4))
		draw_circle(p, h * 0.55, Color(1, 1, 1, 0.95))
		for i in 6:
			var a: float = TAU * i / 6.0 + _time * 3.0
			var ray: float = h * (1.1 + 0.5 * pulse)
			draw_line(p, p + Vector2(cos(a), sin(a)) * ray, Color(1, 0.95, 0.7, 0.55), 2.0, true)

	## Draws the painted frame with uniformly scaled end caps and a stretched
	## middle; returns the inner channel rect where the beams go.
	func _draw_frame() -> Rect2:
		# Drawn whole (the frame has a centered ornament that must not stretch);
		# the HUD sizes this control to the texture's aspect ratio.
		var src: Vector2 = frame.get_size()
		var k := size / src
		draw_texture_rect(frame, Rect2(Vector2.ZERO, size), false)
		var top: float = BAR_CHANNEL.x * k.y + 1.0
		var bottom: float = BAR_CHANNEL.y * k.y - 1.0
		return Rect2(BAR_CAP * k.x, top, size.x - BAR_CAP * 2.0 * k.x, bottom - top)

	func _beam(r: Rect2, base: Color, light: Color, rad: float) -> void:
		if r.size.x <= 0.0:
			return
		_rounded(r, rad, base)
		_rounded(Rect2(r.position + Vector2(0, r.size.y * 0.15), Vector2(r.size.x, r.size.y * 0.3)), rad * 0.3, Color(light, 0.55))

	func _rounded(r: Rect2, rad: float, col: Color) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(int(minf(rad, r.size.y * 0.5)))
		sb.anti_aliasing = true
		draw_style_box(sb, r)


## A horizontal gold flourish: a line that tapers into a diamond tip.
class Flourish extends Control:
	var mirrored: bool = false

	func _draw() -> void:
		var y: float = size.y * 0.5
		var w: float = size.x
		var tip := Vector2(0.0 if not mirrored else w, y)
		var root := Vector2(w if not mirrored else 0.0, y)
		var dir: float = -1.0 if not mirrored else 1.0
		draw_line(root, tip, GOLD, 2.0, true)
		draw_line(root + Vector2(0, 4), tip + Vector2(-dir * w * 0.25, 4), Color(GOLD, 0.45), 1.0, true)
		var d := tip - Vector2(dir * 2.0, 0)
		draw_colored_polygon(PackedVector2Array([
			d + Vector2(0, -5), d + Vector2(dir * 6, 0), d + Vector2(0, 5), d + Vector2(-dir * 6, 0),
		]), GOLD)
		draw_circle(root, 2.5, GOLD)


var villain_hearts: Control
var player_hearts: Control
var _pips: Array[TextureRect] = []
var _rune_on: Texture2D
var _rune_off: Texture2D
var _banner: Label
var _hint: Label
var _duel_box: VBoxContainer
var _tug: TugBar
var _end_panel: PanelContainer
var _end_title: Label
var _end_sub: Label
var _banner_tween: Tween
var _font_body: Font
var _font_title: Font


## Builds every widget. [param villain_max], [param player_max] and
## [param deflects] come from the balance config.
func setup(villain_max: int, player_max: int, deflects: int) -> void:
	var base_font := _load_font(FONT_PATH)
	if base_font:
		_font_body = _weighted(base_font, FONT_BODY_WEIGHT)
		_font_title = _weighted(base_font, FONT_TITLE_WEIGHT)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Villain: name plate, hearts, deflect pips (top center).
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-220, 12)
	top.custom_minimum_size = Vector2(440, 0)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 6)
	root.add_child(top)
	var plate_tex := _tex("nameplate")
	if plate_tex:
		# Painted ribbon; the title sits on the parchment band (lower ~60%).
		var plate := Control.new()
		plate.custom_minimum_size = Vector2(400, 400.0 * plate_tex.get_height() / plate_tex.get_width())
		plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(plate)
		var art := TextureRect.new()
		art.texture = plate_tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_child(art)
		var name_label := _label("The Dark Mage", 22, PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER, true)
		name_label.add_theme_constant_override("outline_size", 0)
		name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.anchor_left = 0.0
		name_label.anchor_right = 1.0
		name_label.anchor_top = 0.2
		name_label.anchor_bottom = 0.85
		plate.add_child(name_label)
	else:
		var plate_row := HBoxContainer.new()
		plate_row.alignment = BoxContainer.ALIGNMENT_CENTER
		plate_row.add_theme_constant_override("separation", 10)
		top.add_child(plate_row)
		plate_row.add_child(_flourish(false))
		plate_row.add_child(_label("The Dark Mage", 26, Color(0.7, 1.0, 0.78), HORIZONTAL_ALIGNMENT_CENTER, true))
		plate_row.add_child(_flourish(true))
	villain_hearts = HealthBar.new()
	villain_hearts.bar_size = Vector2(400, 24)
	villain_hearts.maximum = villain_max
	villain_hearts.current = villain_max
	villain_hearts.fill_color = Color(0.1, 0.48, 0.26)
	villain_hearts.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.add_child(villain_hearts)
	var pips := HBoxContainer.new()
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	pips.add_theme_constant_override("separation", 8)
	top.add_child(pips)
	_rune_on = _tex("rune_on")
	_rune_off = _tex("rune_off")
	for i in deflects:
		var p := TextureRect.new()
		p.custom_minimum_size = Vector2(30, 30)
		p.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		p.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.pivot_offset = Vector2(15, 15)
		pips.add_child(p)
		_pips.append(p)
	set_deflects(0)

	# Player hearts (bottom left), on a dark parchment plaque.
	var plaque := PanelContainer.new()
	plaque.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	plaque.position = Vector2(14, -146)
	var plaque_sb: StyleBox = _frame_style("panel_frame_small", PANEL_SMALL_MARGIN, 32.0)
	plaque.add_theme_stylebox_override("panel", plaque_sb if plaque_sb else _plaque_style())
	root.add_child(plaque)
	var bl := VBoxContainer.new()
	bl.add_theme_constant_override("separation", 2)
	plaque.add_child(bl)
	bl.add_child(_label("You", 22, GOLD, HORIZONTAL_ALIGNMENT_LEFT, true))
	player_hearts = HealthBar.new()
	player_hearts.bar_size = Vector2(260, 24)
	player_hearts.maximum = player_max
	player_hearts.current = player_max
	bl.add_child(player_hearts)

	# Controls hint (bottom center).
	_hint = _label("", 18, PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position = Vector2(-450, -44)
	_hint.custom_minimum_size = Vector2(900, 30)
	root.add_child(_hint)

	# Banner (center).
	_banner = _label("", 48, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, true)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.position = Vector2(-560, -115)
	_banner.custom_minimum_size = Vector2(1120, 70)
	_banner.pivot_offset = Vector2(560, 35)
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.modulate.a = 0.0
	root.add_child(_banner)

	# Duel tug bar.
	_duel_box = VBoxContainer.new()
	_duel_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_duel_box.position = Vector2(-320, -165)
	_duel_box.custom_minimum_size = Vector2(640, 0)
	_duel_box.add_theme_constant_override("separation", 14)
	root.add_child(_duel_box)
	_duel_box.add_child(_label("Priori Incantatum!", 32, GOLD, HORIZONTAL_ALIGNMENT_CENTER, true))
	_duel_box.add_child(_label("Mash  SPACE", 18, PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER))
	_tug = TugBar.new()
	_tug.frame = _tex("bar_frame")
	if _tug.frame:
		_tug.custom_minimum_size = Vector2(640, 640.0 * _tug.frame.get_height() / _tug.frame.get_width())
	else:
		_tug.custom_minimum_size = Vector2(640, 22)
	_duel_box.add_child(_tug)
	_duel_box.visible = false

	# End screen.
	_end_panel = PanelContainer.new()
	_end_panel.set_anchors_preset(Control.PRESET_CENTER)
	_end_panel.position = Vector2(-340, -120)
	_end_panel.custom_minimum_size = Vector2(680, 280)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.03, 0.1, 0.92)
	sb.set_corner_radius_all(6)
	sb.border_color = GOLD
	sb.set_border_width_all(3)
	sb.shadow_color = Color(0.95, 0.75, 0.3, 0.25)
	sb.shadow_size = 24
	sb.set_content_margin_all(28)
	var end_sb: StyleBox = _frame_style("panel_frame", PANEL_MARGIN, 56.0)
	_end_panel.add_theme_stylebox_override("panel", end_sb if end_sb else sb)
	var ev := VBoxContainer.new()
	ev.alignment = BoxContainer.ALIGNMENT_CENTER
	ev.add_theme_constant_override("separation", 12)
	_end_panel.add_child(ev)
	_end_title = _label("", 60, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, true)
	var rule := HBoxContainer.new()
	rule.alignment = BoxContainer.ALIGNMENT_CENTER
	rule.add_theme_constant_override("separation", 0)
	rule.add_child(_flourish(false, 160))
	rule.add_child(_flourish(true, 160))
	_end_sub = _label("", 24, PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER)
	ev.add_child(_end_title)
	if end_sb == null:
		ev.add_child(rule)
	ev.add_child(_end_sub)
	_end_panel.visible = false
	root.add_child(_end_panel)


func set_villain(hearts: int) -> void:
	villain_hearts.current = hearts


func set_player(hearts: int) -> void:
	player_hearts.current = hearts


## Lights [param n] deflect pips as glowing arcane runes.
func set_deflects(n: int) -> void:
	for i in _pips.size():
		var lit: bool = i < n
		var p := _pips[i]
		var was_lit: bool = p.texture == _rune_on and _rune_on != null
		p.texture = _rune_on if lit else _rune_off
		if _rune_on == null:
			# No art: tint a plain square so the counter still reads.
			p.texture = PlaceholderTexture2D.new()
			p.modulate = ARCANE if lit else Color(0.2, 0.15, 0.25)
		if lit and not was_lit and is_inside_tree():
			p.scale = Vector2(1.5, 1.5)
			create_tween().tween_property(p, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func set_hint(text: String) -> void:
	_hint.text = text


func show_duel(on: bool) -> void:
	_duel_box.visible = on


func set_tug(value: float) -> void:
	_tug.tug = value


## Pops a centered message that fades after [param hold] seconds.
func show_banner(text: String, color: Color = Color.WHITE, hold: float = 1.6) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	if _banner_tween:
		_banner_tween.kill()
	_banner.modulate.a = 0.0
	_banner.scale = Vector2(0.85, 0.85)
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.18)
	_banner_tween.tween_property(_banner, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.chain().tween_interval(hold)
	_banner_tween.chain().tween_property(_banner, "modulate:a", 0.0, 0.4)


func show_end(title: String, sub: String, color: Color) -> void:
	_end_title.text = title
	_end_title.add_theme_color_override("font_color", color)
	_end_sub.text = sub
	_end_panel.visible = true
	_duel_box.visible = false
	_hint.text = ""


func _label(text: String, size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, title: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	var font: Font = _font_title if title else _font_body
	if font:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 8 if title else 6)
	# Solid cartoon drop shadow under titles.
	l.add_theme_color_override("font_shadow_color", Color(INK, 0.55 if title else 0.0))
	l.add_theme_constant_override("shadow_outline_size", 8)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _flourish(mirrored: bool, width: float = 70.0) -> Control:
	var f := Flourish.new()
	f.mirrored = mirrored
	f.custom_minimum_size = Vector2(width, 20)
	f.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return f


func _plaque_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.04, 0.08, 0.72)
	sb.border_color = Color(GOLD, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	return sb


## Loads a painted UI texture from [constant UI_DIR], falling back to the raw
## PNG before the editor has imported it. Returns null if missing.
func _tex(name: String) -> Texture2D:
	var path := UI_DIR + name + ".png"
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img:
			return ImageTexture.create_from_image(img)
	return null


## A 9-slice stylebox from a painted frame; null when the art is missing.
func _frame_style(name: String, margin: float, content: float) -> StyleBoxTexture:
	var t := _tex(name)
	if t == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.set_texture_margin_all(margin)
	sb.set_content_margin_all(content)
	return sb


## A variable-font instance at the given weight axis value.
func _weighted(base: Font, weight: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return fv


## Loads an imported font, falling back to reading the raw file so the HUD
## still works before the editor has imported it. Returns null if missing.
func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		return load(path) as Font
	if FileAccess.file_exists(path):
		var f := FontFile.new()
		if f.load_dynamic_font(path) == OK:
			return f
	return null
