extends CanvasLayer
## Pause menu: ESC or P freezes the game and shows Resume / Restart / Quit.
## Runs while the tree is paused; everything else stops.

const FONT_PATH := "res://assets/fonts/Cinzel.ttf"
const GOLD := Color(0.95, 0.79, 0.4)
const PARCHMENT := Color(0.97, 0.91, 0.76)
const NIGHT := Color(0.05, 0.04, 0.09, 0.94)
const PANEL_SIZE := Vector2(460, 430)
const TOGGLE_KEYS := [KEY_ESCAPE, KEY_P]

## Returns false when pausing is not allowed right now (e.g. the end screen).
var can_pause: Callable = func() -> bool: return true

var _root: Control
var _resume: Button
var _mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _font: Font


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.03, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	var frame := StyleBoxFlat.new()
	frame.bg_color = NIGHT
	frame.border_color = GOLD
	frame.set_border_width_all(3)
	frame.set_corner_radius_all(8)
	frame.shadow_color = Color(GOLD, 0.22)
	frame.shadow_size = 28
	frame.set_content_margin_all(36)
	panel.add_theme_stylebox_override("panel", frame)
	centre.add_child(panel)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	column.add_child(_text("PAUSED", 54, GOLD))
	var rule := ColorRect.new()
	rule.color = Color(GOLD, 0.6)
	rule.custom_minimum_size = Vector2(0, 2)
	column.add_child(rule)
	_resume = _button("Resume", resume)
	column.add_child(_resume)
	column.add_child(_button("Restart level", _restart))
	column.add_child(_button("Quit game", _quit))
	column.add_child(_text("ESC or P to resume", 16, Color(PARCHMENT, 0.6)))


func _exit_tree() -> void:
	# A scene reload while paused must never leave the next scene frozen.
	get_tree().paused = false


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if not (event as InputEventKey).physical_keycode in TOGGLE_KEYS:
		return
	if get_tree().paused:
		resume()
	elif can_pause.call():
		open()
	get_viewport().set_input_as_handled()


## Freezes the game and shows the menu.
func open() -> void:
	_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	_root.visible = true
	_resume.grab_focus()


## Hides the menu and lets the game continue.
func resume() -> void:
	_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = _mouse_mode


func _restart() -> void:
	resume()
	get_tree().reload_current_scene()


func _quit() -> void:
	get_tree().quit()


func _text(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if _font:
		l.add_theme_font_override("font", _font)
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 58)
	b.add_theme_font_size_override("font_size", 26)
	if _font:
		b.add_theme_font_override("font", _font)
	b.add_theme_color_override("font_color", PARCHMENT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_stylebox_override("normal", _button_style(Color(0.12, 0.1, 0.18), Color(GOLD, 0.35)))
	b.add_theme_stylebox_override("hover", _button_style(Color(0.2, 0.16, 0.28), GOLD))
	b.add_theme_stylebox_override("focus", _button_style(Color(0.2, 0.16, 0.28), GOLD))
	b.add_theme_stylebox_override("pressed", _button_style(Color(0.3, 0.22, 0.1), GOLD))
	b.pressed.connect(action)
	return b


func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	return sb
