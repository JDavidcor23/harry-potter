extends Node3D
## Boss fight orchestrator: builds the castle arena, spawns the wizard and the
## Dark Mage, and runs the loop: deflect pieces -> villain comes down ->
## Priori Incantatum duel -> repeat until the snitch is caught.
##
## Debug/QA user args (after `--`): --autoplay, --phase=duel|snitch,
## --shot=<png> --shot-delay=<s>, --quit-on-end.

const Rules := preload("res://src/rules/boss_fight_rules.gd")
const Rig := preload("res://src/character_rig.gd")
const Brick := preload("res://src/brick.gd")
const Bolt := preload("res://src/spell_bolt.gd")
const Snitch := preload("res://src/snitch.gd")
const Hud := preload("res://src/hud.gd")
const Fx := preload("res://src/fx.gd")
const Dressing := preload("res://src/environment_dressing.gd")
const Gothic := preload("res://src/gothic_dressing.gd")
const DuelClash := preload("res://src/duel_clash.gd")
const Sfx := preload("res://src/sfx.gd")
const SFX_CONFIG_PATH := "res://assets/data/audio_sfx.json"
const PLAYER_SCENE := preload("res://assets/models/albus.glb")
const VILLAIN_SCENE := preload("res://assets/models/dark_mage.glb")
const VILLAIN_IDLE_SCENE := preload("res://assets/models/dark_mage_idle.glb")
## The boss is drawn bigger than the wizard so his throw reads from afar.
const VILLAIN_SCALE := 1.4
const CASTLE_MESH := preload("res://assets/models/castle/castle.obj")
const CASTLE_TEXTURE := preload("res://assets/models/castle/texture.jpg")
const CONFIG_PATH := "res://assets/data/boss_balance.json"

# Castle model units -> metres. Rotated 90 degrees, the model's back wall
# (x = -239) lands at world z = -12, behind the tower, and its island top
# (y = 5) at ground level; the arena sits on the island between wall and edge.
const CASTLE_SCALE := 0.12
const CASTLE_OFFSET := Vector3(0, -0.6, -40.7)
const ARENA_TORCH_X := 8.5
## Torch brightness multiplier: at night the torches are the main warm light.
const TORCH_BOOST := 3.2
## Seconds between lightning flashes (min, max).
const LIGHTNING_GAP := Vector2(6.0, 13.0)
## Seconds the "level cleared" screen stays before the next level loads.
const LEVEL_BREAK := 3.5
const LIGHTNING_COLOR := Color(0.62, 0.8, 1.0)
## How far up the visible bolt reaches.
const LIGHTNING_HEIGHT := 26.0

const CAST := "Charged_Spell_Cast_1"
const DEAD := "Dead"
const IDLE := "Idle"
const RUN := "Running"
const WALK := "Walking"
const THROW := "Grip_and_Throw_Down"

# Arena layout (positions, not balance values).
const PLAYER_Z := 4.0
const DUEL_PLAYER := Vector3(0, 0, 2.2)
const BALCONY := Vector3(0, 6.0, -10.0)
const DUEL_SPOT := Vector3(0, 0, -2.6)
const CHEST := Vector3(0, 1.1, 0)
# Low over-the-shoulder camera looking up at the villain's tower.
const CAM_FIGHT := [Vector3(0, 2.3, 9.8), Vector3(0, 4.6, -10.0)]
const INTRO_SPOT := Vector3(0, 0, -6.0)
## Forward/back dodge range of the wizard during the fight.
const FIGHT_Z_MIN := 1.5
const FIGHT_Z_MAX := 7.0
const CAM_DUEL := [Vector3(7.0, 2.6, 3.2), Vector3(0, 1.4, -0.2)]
const CAM_SNITCH := [Vector3(0, 7.5, 12.0), Vector3(0, 0.8, 0.5)]

const HINT_FIGHT := "WASD move   Mouse aim + Click / F shoot (%d hits in a row bring him down)   SPACE Protego shield"
const HINT_SNITCH := "WASD move   SPACE catch the Golden Snitch!"

const GOLD := Color(1.0, 0.75, 0.2)
## The hero's spell and duel beam colour.
const HERO_RED := Color(1.0, 0.12, 0.08)
## Cast clip time where both rigs have the wand arm fully extended
## (measured hand reach plateau 2.2 s - 2.8 s).
const BEAM_POSE_TIME := 2.4
const GREEN := Color(0.25, 1.0, 0.35)

enum Stage { INTRO, FIGHT, DESCEND, DUEL, ASCEND, SNITCH, END }


## Aiming reticle drawn at the mouse position; turns gold over the villain.
class Crosshair extends Control:
	var on_target: bool = false:
		set(v):
			on_target = v
			queue_redraw()

	func _draw() -> void:
		var c: Color = Color(1.0, 0.8, 0.25) if on_target else Color(1, 1, 1, 0.9)
		draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 32, Color(0, 0, 0, 0.6), 5.0)
		draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 32, c, 2.5)
		for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(d * 6.0, d * 20.0, c, 2.5)
		draw_circle(Vector2.ZERO, 2.0, c)

var cfg: Dictionary
var rules: Rules
var stage: Stage = Stage.INTRO
var player: Rig
var villain: Rig
var hud: Hud
var sfx: Sfx
var camera: Camera3D
var bricks: Array = []
var snitch

var _throw_timer: float = 2.5
var _release_in: float = -1.0
var _villain_anim_left: float = 0.0
var _held_brick: Node3D
var _next_kind: String = "rock"
var _windup_total: float = 1.0
var _held_from: Vector3
var _crosshair: Crosshair
var _sway_t: float = 0.0
var _cue_ring: MeshInstance3D
var _cue_label: Label3D
var _protego_cd: float = 0.0
var _protego_left: float = 0.0
var _spell_cd: float = 0.0
var _player_lock: float = 0.0
var _invuln: float = 0.0
var _stun: float = 0.0
var _next_surge: float = 0.0
var _shake: float = 0.0
var _lightning_timer: float = 4.0
## Current level (0-based). Static so it survives the scene reload between levels.
static var _level: int = 0
static var _level_arg_used: bool = false
var _levels: int = 1
var _cam_pos: Vector3
var _cam_look: Vector3
var _cam_goal: Array = CAM_FIGHT
var _shield: MeshInstance3D
var _duel_fx: DuelClash
var _dbg: Dictionary = {}
var _auto_mash_acc: float = 0.0


func _ready() -> void:
	randomize()
	var base_cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	_levels = Rules.level_count(base_cfg)
	# QA: --level=N starts at that level (only on the first load).
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level=") and not _level_arg_used:
			_level_arg_used = true
			_level = clampi(int(arg.trim_prefix("--level=")) - 1, 0, _levels - 1)
	cfg = Rules.config_for_level(base_cfg, _level)
	rules = Rules.new(cfg)
	sfx = Sfx.new()
	add_child(sfx)
	sfx.setup(SFX_CONFIG_PATH)
	_setup_input()
	_build_world()
	_spawn_actors()
	hud = Hud.new()
	add_child(hud)
	hud.setup(rules.villain_hearts, rules.player_hearts, int(cfg.deflects_to_duel))
	hud.set_hint(HINT_FIGHT % int(cfg.deflects_to_duel))
	hud.show_banner("LEVEL %d of %d" % [_level + 1, _levels], GOLD, 2.2)
	var aim_layer := CanvasLayer.new()
	aim_layer.layer = 5
	add_child(aim_layer)
	_crosshair = Crosshair.new()
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aim_layer.add_child(_crosshair)
	_parse_debug_args()
	# Intro: the Dark Mage starts on the ground and levitates up to his tower.
	villain.position = INTRO_SPOT
	get_tree().create_timer(0.8).timeout.connect(func() -> void:
		_levitate(BALCONY, 2.4, func() -> void:
			if stage == Stage.INTRO:
				_throw_timer = 0.4
				stage = Stage.FIGHT
				_apply_debug_phase()))


# ---------------------------------------------------------------- setup

func _setup_input() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("move_up", [KEY_W, KEY_UP])
	_add_action("move_down", [KEY_S, KEY_DOWN])
	_add_action("protego", [KEY_SPACE])
	_add_action("cast", [KEY_F], MOUSE_BUTTON_LEFT)
	_add_action("restart", [KEY_R])


func _add_action(action: String, keys: Array, mouse: int = -1) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	if mouse >= 0:
		var m := InputEventMouseButton.new()
		m.button_index = mouse
		InputMap.action_add_event(action, m)


func _build_world() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	# Overcast moonlit night: cold desaturated sky, low ambient, so the warm
	# torches and the spell colours carry the scene.
	sky_mat.sky_top_color = Color(0.02, 0.035, 0.07)
	sky_mat.sky_horizon_color = Color(0.13, 0.17, 0.24)
	sky_mat.ground_horizon_color = Color(0.1, 0.13, 0.18)
	sky_mat.ground_bottom_color = Color(0.02, 0.03, 0.05)
	sky_mat.sun_angle_max = 12.0
	sky_mat.sun_curve = 0.3
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.27, 0.42)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.ssao_enabled = true
	env.ssao_intensity = 3.0
	env.ssao_radius = 1.6
	env.ssil_enabled = true
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.82
	env.adjustment_contrast = 1.15
	# Distance haze swallows the far castle; height fog pools on the grass.
	env.fog_enabled = true
	env.fog_light_color = Color(0.16, 0.21, 0.3)
	env.fog_density = 0.009
	env.fog_sky_affect = 0.6
	env.fog_height = 1.2
	env.fog_height_density = 0.25
	# Volumetric fog makes every torch and spell light a visible halo.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.02
	env.volumetric_fog_albedo = Color(0.75, 0.82, 0.95)
	env.volumetric_fog_emission = Color(0.1, 0.14, 0.22)
	env.volumetric_fog_emission_energy = 0.25
	env.volumetric_fog_anisotropy = 0.5
	env.volumetric_fog_length = 90.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# The moon: low, cold key light raking across the grounds for long shadows.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-36, 50, 0)
	sun.light_color = Color(0.58, 0.7, 1.0)
	sun.light_energy = 1.0
	sun.light_volumetric_fog_energy = 1.4
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)

	# Textured grass sits just above the island top, hiding its flat texture.
	var ground := Dressing.grass_ground(400.0, 6.0)
	ground.position.y = 0.01
	add_child(ground)
	var path_rect := Rect2(-1.4, -8.5, 2.8, 15.0)
	add_child(Dressing.cobble_path(path_rect, 0.5))
	add_child(Dressing.grass_blades(Rect2(-24, -12.5, 48, 30), [
		path_rect.grow(0.15),
		Rect2(-2.6, -12.6, 5.2, 5.2),  # villain tower footprint
	], 26000))

	# The fight happens on the castle grounds, behind the castle: the model is
	# rotated so its back wall rises right behind the villain's tower.
	var stone := Gothic.stone_material()
	var dark_stone := Gothic.stone_material(Color(0.62, 0.62, 0.68))
	var castle_mat := Gothic.stone_material(Color(0.8, 0.82, 0.9), 5.0)
	castle_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var castle := MeshInstance3D.new()
	castle.mesh = CASTLE_MESH
	castle.material_override = castle_mat
	castle.scale = Vector3.ONE * CASTLE_SCALE
	castle.position = CASTLE_OFFSET
	castle.rotation.y = PI / 2.0
	add_child(castle)

	# Braziers lining the duel path.
	for x in [-ARENA_TORCH_X, ARENA_TORCH_X]:
		for z in [-6.0, 0.0, 6.0]:
			var stand := Gothic.brazier(2.4, stone)
			stand.position = Vector3(x, 0, z)
			add_child(stand)
			_add_torch(Vector3(x, 2.4, z), 1.5, 6.0)

	# Villain's tower: buttressed keep with battlements and a cursed window.
	var tower := Fx.box(Vector3(4.0, 5.8, 4.0), stone)
	tower.position = BALCONY + Vector3(0, -2.9 - 0.2, 0)
	add_child(tower)
	var plinth := Fx.box(Vector3(5.0, 0.7, 5.0), dark_stone)
	plinth.position = Vector3(BALCONY.x, 0.35, BALCONY.z)
	add_child(plinth)
	var cap := Fx.box(Vector3(4.8, 0.4, 4.8), dark_stone)
	cap.position = BALCONY + Vector3(0, -0.2, 0)
	add_child(cap)
	for x in [-2.1, 2.1]:
		for z in [-2.1, 2.1]:
			var merlon := Fx.box(Vector3(0.7, 0.8, 0.7), stone)
			merlon.position = BALCONY + Vector3(x, 0.4, z)
			add_child(merlon)
			var buttress := Gothic.tapered(0.62, 0.3, 5.4, dark_stone, 4)
			buttress.position += Vector3(BALCONY.x + x * 0.97, 0, BALCONY.z + z * 0.97)
			buttress.rotation.y = PI / 4.0
			add_child(buttress)
	var window_glow := Fx.mat(GREEN, 2.5)
	var window := Fx.box(Vector3(0.5, 1.5, 0.06), window_glow)
	window.position = Vector3(BALCONY.x, 3.2, BALCONY.z + 2.01)
	add_child(window)
	var window_tip := Fx.box(Vector3(0.36, 0.36, 0.06), window_glow)
	window_tip.position = window.position + Vector3(0, 0.75, 0)
	window_tip.rotation.z = PI / 4.0
	add_child(window_tip)
	for x in [-3.2, 3.2]:
		var at: Vector3 = BALCONY + Vector3(x, -1.0, 2.0)
		var bowl := Gothic.brazier(0.0, stone)
		bowl.position = at + Vector3(0, -0.3, 0)
		add_child(bowl)
		add_child(Gothic.strut(at + Vector3(-signf(x) * 1.25, -0.5, 0), at + Vector3(0, -0.25, 0), 0.09, Fx.mat(Gothic.IRON, 0.0, 0.5, 0.8)))
		_add_torch(at, 2.5, 7.0)

	_build_ruins(stone, dark_stone)
	_start_lightning()

	camera = Camera3D.new()
	camera.fov = 46
	add_child(camera)
	_cam_pos = CAM_FIGHT[0]
	_cam_look = CAM_FIGHT[1]
	camera.position = _cam_pos
	camera.look_at(_cam_look)


func _add_torch(at: Vector3, energy: float, reach: float) -> void:
	var flame := Gothic.fire()
	flame.position = at
	add_child(flame)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = energy * TORCH_BOOST
	light.omni_range = reach * 1.6
	light.omni_attenuation = 1.4
	light.shadow_enabled = true
	light.light_volumetric_fog_energy = 1.1
	light.position.y = 0.35
	flame.add_child(light)
	# Uneven flicker so the firelight feels alive.
	var base: float = light.light_energy
	var flicker := create_tween().set_loops()
	for _i in 6:
		flicker.tween_property(light, "light_energy",
			base * randf_range(0.72, 1.12), randf_range(0.07, 0.22))

## Ruins, dead trees and rune stones framing the arena; all outside the
## playable strip so nothing blocks movement or the camera.
func _build_ruins(stone: Material, dark_stone: Material) -> void:
	var arches := [
		[Vector3(-12.5, 0, -7.0), 0.35, true], [Vector3(12.5, 0, -7.5), -0.3, false],
		[Vector3(-14.0, 0, 1.5), 1.2, false], [Vector3(14.5, 0, 2.5), -1.25, true],
	]
	for a: Array in arches:
		var arch := Gothic.arch(3.6, 4.2, stone, a[2])
		arch.position = a[0]
		arch.rotation.y = a[1]
		add_child(arch)
	var columns := [
		[Vector3(-6.2, 0, -9.5), 3.6, false], [Vector3(6.2, 0, -9.5), 2.1, true],
		[Vector3(-10.5, 0, -3.0), 1.4, true], [Vector3(10.8, 0, -2.5), 3.2, false],
		[Vector3(-11.0, 0, 4.5), 2.6, true], [Vector3(11.2, 0, 5.0), 1.1, true],
	]
	for c: Array in columns:
		var col := Gothic.column(c[1], 0.38, dark_stone, c[2])
		col.position = c[0]
		add_child(col)
	var trees := [
		Vector3(-17.0, 0, -9.0), Vector3(17.5, 0, -8.0), Vector3(-19.0, 0, -1.0),
		Vector3(19.0, 0, 0.5), Vector3(-9.0, 0, -11.5), Vector3(9.5, 0, -11.8),
		Vector3(-16.0, 0, 6.5), Vector3(16.5, 0, 7.0),
	]
	for i in trees.size():
		var tree := Gothic.dead_tree(7.0 + (i % 3) * 1.5, 100 + i)
		tree.position = trees[i]
		add_child(tree)
	for x: float in [-4.6, 4.6]:
		var rune := Gothic.rune_stone(2.0, dark_stone, GREEN)
		rune.position = Vector3(x, 0, -7.6)
		rune.rotation.y = -signf(x) * 0.35
		add_child(rune)
	# Embers and ash drifting over the whole duelling ground.
	var drift := Gothic.embers(Vector3(13, 2.5, 9), 70, 6.0, 0.07)
	drift.position = Vector3(0, 2.5, -1.0)
	add_child(drift)


## Distant storm: a cold flash lights the grounds every few seconds.
func _start_lightning() -> void:
	var bolt := DirectionalLight3D.new()
	bolt.rotation_degrees = Vector3(-55, 160, 0)
	bolt.light_color = Color(0.75, 0.82, 1.0)
	bolt.light_energy = 0.0
	bolt.light_volumetric_fog_energy = 2.5
	bolt.shadow_enabled = true
	add_child(bolt)
	_strike(bolt)


func _strike(bolt: DirectionalLight3D) -> void:
	var tw := create_tween()
	tw.tween_interval(randf_range(LIGHTNING_GAP.x, LIGHTNING_GAP.y))
	tw.tween_callback(sfx.play.bind("thunder"))
	tw.tween_property(bolt, "light_energy", 2.6, 0.04)
	tw.tween_property(bolt, "light_energy", 0.3, 0.09)
	tw.tween_property(bolt, "light_energy", 1.8, 0.04)
	tw.tween_property(bolt, "light_energy", 0.0, 0.5)
	tw.tween_callback(_strike.bind(bolt))


func _spawn_actors() -> void:
	player = Rig.new()
	add_child(player)
	player.setup(PLAYER_SCENE, 0.0, [RUN, WALK])
	player.position = Vector3(0, 0, PLAYER_Z)
	player.rotation.y = PI
	_idle(player)

	villain = Rig.new()
	add_child(villain)
	villain.setup(VILLAIN_SCENE, 0.0, [RUN, WALK])
	villain.add_clip_from(VILLAIN_IDLE_SCENE, "Idle_02", IDLE, true)
	villain.scale = Vector3.ONE * VILLAIN_SCALE
	villain.position = BALCONY
	_idle(villain)
	var aura := OmniLight3D.new()
	aura.light_color = Color(0.5, 1.0, 0.4)
	aura.light_energy = 3.5
	aura.omni_range = 5.0
	aura.position = Vector3(0, 1.4, 0.6)
	villain.add_child(aura)

	_shield = Fx.sphere(1.25, Fx.mat(Color(0.4, 0.75, 1.0, 0.35), 2.0, 0.1))
	_shield.position = CHEST
	_shield.visible = false
	player.add_child(_shield)

	_cue_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.05
	torus.outer_radius = 1.25
	_cue_ring.mesh = torus
	_cue_ring.material_override = Fx.mat(Color(0.35, 0.75, 1.0), 6.0)
	_cue_ring.position = Vector3(0, 0.08, 0)
	_cue_ring.visible = false
	player.add_child(_cue_ring)
	_cue_label = Label3D.new()
	_cue_label.text = "NOW!"
	_cue_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_cue_label.no_depth_test = true
	_cue_label.font_size = 96
	_cue_label.outline_size = 24
	_cue_label.modulate = Color(0.55, 0.85, 1.0)
	_cue_label.position = Vector3(0, 2.4, 0)
	_cue_label.visible = false
	player.add_child(_cue_label)

	_duel_fx = DuelClash.new()
	add_child(_duel_fx)
	_duel_fx.setup(HERO_RED, GREEN)


func _idle(rig: Rig) -> void:
	if rig.has_clip(IDLE):
		rig.play(IDLE)
	else:
		rig.hold_pose(CAST, 0.0)


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	_protego_cd = max(_protego_cd - delta, 0.0)
	_spell_cd = max(_spell_cd - delta, 0.0)
	_player_lock = max(_player_lock - delta, 0.0)
	_invuln = max(_invuln - delta, 0.0)
	_debug_autoplay(delta)
	match stage:
		Stage.FIGHT:
			_update_player_move(delta, false)
			_update_fight(delta)
		Stage.DUEL:
			_update_duel(delta)
		Stage.SNITCH:
			_update_player_move(delta, true)
	if stage != Stage.END:
		player.visible = _invuln <= 0.0 or int(_invuln * 14.0) % 2 == 0
	_update_camera(delta)
	_update_crosshair()


func _update_crosshair() -> void:
	var aiming: bool = stage == Stage.FIGHT
	_crosshair.visible = aiming
	_crosshair.position = get_viewport().get_mouse_position()
	if aiming:
		_crosshair.on_target = _hits_villain(_mouse_aim_point())
	var mode: Input.MouseMode = Input.MOUSE_MODE_HIDDEN if aiming else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != mode:
		Input.mouse_mode = mode


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart") and stage == Stage.END:
		# After beating the last level, R starts the whole run again.
		if rules.phase == Rules.Phase.WON and _level >= _levels - 1:
			_level = 0
		get_tree().reload_current_scene()
		return
	match stage:
		Stage.FIGHT:
			if event.is_action_pressed("protego"):
				_cast_protego()
			elif event.is_action_pressed("cast"):
				_cast_spell(_mouse_aim_point())
		Stage.DUEL:
			if event.is_action_pressed("protego") or event.is_action_pressed("cast"):
				_mash()
		Stage.SNITCH:
			if event.is_action_pressed("protego") or event.is_action_pressed("cast"):
				_try_catch()


func _move_input(free_roam: bool) -> Vector3:
	if _dbg.has("autoplay") and free_roam and is_instance_valid(snitch):
		var to: Vector3 = snitch.global_position - player.global_position
		return Vector3(to.x, 0, to.z).normalized()
	if _dbg.has("autoplay") and not free_roam:
		# QA bot: sidestep incoming cursed pieces, otherwise drift back to centre.
		for b in bricks:
			if is_instance_valid(b) and b.cursed and b.state == Brick.State.INCOMING:
				var away: float = player.position.x - b.global_position.x
				return Vector3(1.0 if away >= 0.0 else -1.0, 0, 0) if abs(player.position.x) < 5.5 else Vector3(-sign(player.position.x), 0, 0)
		return Vector3(clamp(-player.position.x, -1.0, 1.0) if abs(player.position.x) > 0.3 else 0.0, 0, 0)
	var x: float = Input.get_axis("move_left", "move_right")
	var z: float = Input.get_axis("move_up", "move_down")
	return Vector3(x, 0, z).limit_length(1.0)


func _update_player_move(delta: float, free_roam: bool) -> void:
	var dir: Vector3 = _move_input(free_roam)
	var hw: float = float(cfg.arena_half_width)
	var p: Vector3 = player.position + dir * float(cfg.player_speed) * delta
	p.x = clamp(p.x, -hw, hw)
	p.z = clamp(p.z, -3.5, 6.0) if free_roam else clamp(p.z, FIGHT_Z_MIN, FIGHT_Z_MAX)
	player.position = p
	var yaw: float = PI
	if dir.length() > 0.1 and not free_roam:
		# Keep facing the villain while dodging, like a strafe.
		yaw = PI
		if _player_lock <= 0.0:
			player.play(RUN, 1.2)
	elif dir.length() > 0.1:
		yaw = atan2(dir.x, dir.z)
		if _player_lock <= 0.0:
			player.play(RUN, 1.2)
	elif _player_lock <= 0.0:
		_idle(player)
	if _player_lock > 0.0 and not free_roam:
		yaw = PI
	player.rotation.y = lerp_angle(player.rotation.y, yaw, 12.0 * delta)


func _update_fight(delta: float) -> void:
	_protego_left = max(_protego_left - delta, 0.0)
	_shield.visible = _protego_left > 0.0
	_update_villain_throwing(delta)
	_update_lightning(delta)
	var chest: Vector3 = player.global_position + CHEST
	_update_deflect_cue(chest)
	for b in bricks.duplicate():
		if not is_instance_valid(b) or b.state == Brick.State.DONE:
			bricks.erase(b)
			continue
		if b.state != Brick.State.INCOMING:
			continue
		var d: float = b.global_position.distance_to(chest)
		if _protego_left > 0.0 and d < float(cfg.protego_radius):
			if b.cursed:
				_protego_left = 0.0  # Cursed pieces break the shield.
				sfx.play("shield_break")
				Fx.burst(self, chest, Color(1, 0.2, 0.3), 1.0)
			else:
				# Protego is an emergency shield: it breaks the attack, no credit.
				Fx.burst(self, b.global_position, Color(0.5, 0.8, 1.0), 0.8)
				sfx.play("shield_block")
				b.smash()
				continue
		if d < 0.85:
			b.smash()
			_player_hit()


## Calls down lightning volleys on the player. Protego does not stop them:
## the only defence is stepping out of the marked circle before it lands.
func _update_lightning(delta: float) -> void:
	_lightning_timer -= delta
	if _lightning_timer > 0.0:
		return
	_lightning_timer = rules.lightning_interval()
	var half: float = float(cfg.arena_half_width)
	var spread: float = float(cfg.lightning_spread)
	for i in rules.lightning_bolts():
		var at: Vector3 = player.global_position
		if i > 0:
			# Extra bolts land around the player to cut off the escape routes.
			at += Vector3(randf_range(-spread, spread), 0, randf_range(-spread, spread))
		at.x = clampf(at.x, -half, half)
		at.z = clampf(at.z, FIGHT_Z_MIN, FIGHT_Z_MAX)
		at.y = 0.0
		get_tree().create_timer(i * float(cfg.lightning_stagger)).timeout.connect(
			_telegraph_lightning.bind(at))


## Marks where a bolt will land, then strikes after the warning time.
func _telegraph_lightning(at: Vector3) -> void:
	if stage != Stage.FIGHT:
		return
	var warning: float = float(cfg.lightning_warning)
	var radius: float = float(cfg.lightning_radius)
	var marker := Node3D.new()
	marker.position = at
	add_child(marker)
	# Raised above the grass blades so the circle is always readable.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.09
	torus.outer_radius = radius
	ring.mesh = torus
	ring.material_override = Fx.mat(LIGHTNING_COLOR, 5.0)
	ring.position.y = 0.6
	marker.add_child(ring)
	var fill := Fx.cylinder(radius, 0.02, Fx.mat(Color(LIGHTNING_COLOR, 0.28), 2.5))
	fill.position.y = 0.6
	fill.scale = Vector3(0.05, 1, 0.05)
	marker.add_child(fill)
	# A thin charging thread from the clouds shows where to look.
	var thread := Fx.cylinder(0.03, LIGHTNING_HEIGHT, Fx.mat(Color(LIGHTNING_COLOR, 0.5), 4.0))
	thread.position.y = LIGHTNING_HEIGHT * 0.5
	marker.add_child(thread)
	var charge := OmniLight3D.new()
	charge.light_color = LIGHTNING_COLOR
	charge.light_energy = 0.0
	charge.omni_range = radius * 3.0
	charge.position.y = 1.2
	marker.add_child(charge)
	sfx.play("thunder", -10.0)
	var tw := marker.create_tween().set_parallel(true)
	tw.tween_property(fill, "scale", Vector3.ONE, warning).set_ease(Tween.EASE_IN)
	tw.tween_property(charge, "light_energy", 3.0, warning)
	tw.chain().tween_callback(_lightning_strike.bind(marker, at))


## The bolt itself: jagged flash, blast, and damage if the player stayed inside.
func _lightning_strike(marker: Node3D, at: Vector3) -> void:
	if marker:
		marker.queue_free()
	var bolt := Node3D.new()
	bolt.position = at
	add_child(bolt)
	var glow := Fx.mat(Color(0.9, 0.95, 1.0), 14.0)
	var from := Vector3.ZERO
	var steps := 9
	for i in steps:
		var y: float = LIGHTNING_HEIGHT * float(i + 1) / float(steps)
		var to := Vector3(randf_range(-1.1, 1.1), y, randf_range(-1.1, 1.1))
		bolt.add_child(Gothic.strut(from, to, 0.16, glow))
		# Short side forks make it read as lightning, not a laser.
		if i % 3 == 1:
			var fork: Vector3 = to + Vector3(randf_range(-2.5, 2.5), randf_range(-2.0, 0.5), randf_range(-1.0, 1.0))
			bolt.add_child(Gothic.strut(to, fork, 0.07, glow))
		from = to
	var flash := OmniLight3D.new()
	flash.light_color = LIGHTNING_COLOR
	flash.light_energy = 14.0
	flash.omni_range = 22.0
	flash.light_volumetric_fog_energy = 3.0
	flash.position.y = 1.5
	bolt.add_child(flash)
	var scorch := Fx.cylinder(float(cfg.lightning_radius), 0.03, Fx.mat(Color(1.0, 0.6, 0.25, 0.7), 4.0))
	scorch.position.y = 0.6
	bolt.add_child(scorch)
	bolt.add_child(Gothic.embers(Vector3(0.8, 0.3, 0.8), 24, 1.2, 0.09, LIGHTNING_COLOR))
	Fx.burst(self, at + Vector3(0, 0.8, 0), LIGHTNING_COLOR, 1.4)
	sfx.play("thunder", 6.0)
	_shake = max(_shake, 0.3)
	var flat: Vector3 = player.global_position - at
	flat.y = 0.0
	if rules.lightning_hits(flat.length()):
		_player_hit()
	var tw := bolt.create_tween().set_parallel(true)
	tw.tween_property(flash, "light_energy", 0.0, 0.45)
	tw.tween_property(scorch, "scale", Vector3(1.3, 1, 1.3), 0.8)
	for child in bolt.get_children():
		if child is MeshInstance3D and child != scorch:
			tw.tween_property(child, "scale", Vector3(0.01, 1.0, 0.01), 0.22)
	tw.chain().tween_interval(0.6)
	tw.chain().tween_callback(bolt.queue_free)


## Shows the blue "NOW!" ring while a deflectable attack is inside Protego range.
func _update_deflect_cue(chest: Vector3) -> void:
	var show_cue := false
	if _protego_cd <= 0.0:
		for b in bricks:
			if is_instance_valid(b) and not b.cursed and b.state == Brick.State.INCOMING \
					and b.global_position.distance_to(chest) < float(cfg.protego_radius):
				show_cue = true
				break
	_cue_ring.visible = show_cue
	_cue_label.visible = show_cue
	if show_cue:
		var pulse: float = 1.0 + 0.12 * sin(Time.get_ticks_msec() * 0.03)
		_cue_ring.scale = Vector3(pulse, 1.0, pulse)


func _update_villain_throwing(delta: float) -> void:
	var to_player: Vector3 = player.global_position - villain.global_position
	villain.rotation.y = lerp_angle(villain.rotation.y, atan2(to_player.x, to_player.z), 6.0 * delta)
	# He paces side to side on the tower so aiming takes skill.
	_sway_t += delta * float(cfg.villain_sway_speed)
	villain.position.x = sin(_sway_t) * float(cfg.villain_sway_amplitude)
	if _stun > 0.0:
		_stun -= delta
		if _stun <= 0.0:
			_idle(villain)
		return
	# The throw clip always plays to the end: wind-up with the piece held up,
	# slam down at the release moment, recover. The next throw waits for it.
	if _release_in > 0.0:
		_release_in -= delta
		if is_instance_valid(_held_brick):
			_held_brick.global_position = villain.hand_position()
			_held_brick.rotation.y += delta * 2.0
			if _next_kind != Brick.KIND_SPELL:
				# Telekinesis: the rock rises from behind him to over his head.
				var u: float = 1.0 - clamp(_release_in / _windup_total, 0.0, 1.0)
				_held_brick.global_position = _held_from.lerp(_rock_hold_point(), ease(u, -1.8)) + Vector3.UP * sin(u * 20.0) * 0.06
				_held_brick.rotation += Vector3(1.3, 2.0, 0.7) * delta
		if _release_in <= 0.0:
			_release_brick()
	if _villain_anim_left > 0.0:
		_villain_anim_left -= delta
		if _villain_anim_left <= 0.0:
			_idle(villain)
		return
	_throw_timer -= delta
	if _throw_timer <= 0.0:
		var speed: float = float(cfg.throw_anim_speed) + float(cfg.throw_anim_speed_per_heart) * rules.hearts_lost()
		_next_kind = _pick_attack_kind()
		# Spell rays use the casting clip; solid pieces use the throw clip.
		var clip: String = CAST if _next_kind == Brick.KIND_SPELL else THROW
		var release_key: String = "villain_spell_release_clip_time" if clip == CAST else "throw_release_clip_time"
		villain.replay(clip, speed)
		if _next_kind != Brick.KIND_SPELL:
			sfx.play("rock_levitate")
		_villain_anim_left = villain.clip_length(clip) / speed
		_release_in = float(cfg[release_key]) / speed
		_throw_timer = rules.throw_interval()
		_windup_total = _release_in
		_drop_held_brick()
		_held_brick = Brick.make_visual(_next_kind)
		add_child(_held_brick)
		if _next_kind != Brick.KIND_SPELL:
			var fwd: Vector3 = (player.global_position - villain.global_position) * Vector3(1, 0, 1)
			_held_from = villain.global_position - fwd.normalized() * 3.0 + Vector3.DOWN * 4.0
			_held_brick.global_position = _held_from
		else:
			_held_brick.global_position = villain.hand_position()


## Point above the villain's head where a levitated rock waits to be hurled.
func _rock_hold_point() -> Vector3:
	return villain.global_position + Vector3.UP * 3.1


## Rolls the next villain attack: cursed rock, spell ray or a rock volley.
func _pick_attack_kind() -> String:
	if randf() < rules.cursed_chance():
		return Brick.KIND_CURSED
	if randf() < float(cfg.villain_spell_chance):
		return Brick.KIND_SPELL
	return Brick.KIND_ROCK


func _release_brick() -> void:
	_drop_held_brick()
	var from: Vector3 = _rock_hold_point() if _next_kind != Brick.KIND_SPELL else villain.hand_position()
	print("[event] attack ", _next_kind)
	sfx.play("dark_spell" if _next_kind == Brick.KIND_SPELL else "rock_throw")
	var aim: Vector3 = player.global_position + Vector3(0, 0.9, 0)
	if _next_kind == Brick.KIND_SPELL:
		# Rays fly straight at the wizard's chest.
		var to: Vector3 = player.global_position + CHEST
		_spawn_projectile(from, to, from.distance_to(to) / float(cfg.villain_spell_speed), 0.0)
	elif _next_kind == Brick.KIND_ROCK:
		# A volley fanned around the wizard: one at him, the rest to the sides.
		var count: int = int(cfg.rock_volley)
		for i in count:
			var side: float = (i - (count - 1) * 0.5) * float(cfg.rock_volley_spread)
			var t: float = rules.brick_flight_time() * randf_range(0.9, 1.15)
			_spawn_projectile(from + Vector3(side * 0.3, 0, 0), aim + Vector3(side, 0, randf_range(-0.8, 0.8)), t, 2.5)
	else:
		_spawn_projectile(from, aim, rules.brick_flight_time(), 2.5)


func _spawn_projectile(from: Vector3, to: Vector3, duration: float, arc: float) -> void:
	var b = Brick.new()
	add_child(b)
	bricks.append(b)
	b.landed.connect(_on_brick_landed)
	b.launch(from, to, duration, _next_kind, arc)


## Removes the piece shown in the villain's hand during the wind-up.
func _drop_held_brick() -> void:
	if is_instance_valid(_held_brick):
		_held_brick.queue_free()
	_held_brick = null


func _on_brick_landed(b) -> void:
	if b.state == Brick.State.INCOMING:
		var hit: bool = b.global_position.distance_to(player.global_position + CHEST) < 1.2
		b.smash()
		if b.kind != Brick.KIND_SPELL:
			sfx.play("rock_smash", -4.0)
		if hit:
			_player_hit()


func _villain_struck() -> void:
	Fx.burst(self, villain.global_position + CHEST, Color(1, 0.9, 0.5), 1.2)
	_shake = 0.25
	if stage != Stage.FIGHT:
		return
	var duel: bool = rules.register_deflect()
	hud.set_deflects(rules.deflects if not duel else int(cfg.deflects_to_duel))
	print("[event] villain struck, streak=%d" % rules.deflects)
	if duel:
		_begin_descent()
	else:
		hud.show_banner("Hit %d/%d!" % [rules.deflects, int(cfg.deflects_to_duel)], GOLD, 0.6)
		# A hit only makes him flinch: he keeps attacking.
		sfx.play("villain_hurt")
		var flinch := villain.create_tween()
		flinch.tween_property(villain, "scale", Vector3(1.15, 0.9, 1.15) * VILLAIN_SCALE, 0.06)
		flinch.tween_property(villain, "scale", Vector3.ONE * VILLAIN_SCALE, 0.12)


func _stun_villain(time: float) -> void:
	_stun = max(_stun, time)
	_release_in = -1.0
	_villain_anim_left = 0.0
	_drop_held_brick()
	villain.play(WALK, 0.0)


func _player_hit() -> void:
	if _invuln > 0.0 or stage != Stage.FIGHT:
		return
	rules.register_player_hit()
	_invuln = float(cfg.invulnerable_time)
	hud.set_player(rules.player_hearts)
	Fx.burst(self, player.global_position + CHEST, Color(1, 0.2, 0.2), 1.0)
	_shake = 0.35
	sfx.play("player_hurt")
	print("[event] player hit, hearts=%d" % rules.player_hearts)
	if rules.phase == Rules.Phase.LOST:
		_game_over()


func _cast_protego() -> void:
	if _protego_cd > 0.0:
		return
	_protego_cd = float(cfg.protego_cooldown)
	_protego_left = float(cfg.protego_window)
	_player_lock = 0.35
	player.hold_pose(CAST, 0.55)
	sfx.play("protego")
	_shield.scale = Vector3.ONE * 0.3
	_shield.create_tween().tween_property(_shield, "scale", Vector3.ONE, 0.1)


## Fires a manually aimed spell at [param aim] (no homing). It only counts if
## it reaches the villain's body.
func _cast_spell(aim: Vector3) -> void:
	if _spell_cd > 0.0:
		return
	_spell_cd = float(cfg.spell_cooldown)
	_player_lock = 0.45
	player.replay(CAST, 2.2)
	sfx.play("spell_cast")
	var bolt = Bolt.new()
	add_child(bolt)
	bolt.fire(player.wand_tip_position(), null, aim, HERO_RED, float(cfg.spell_speed))
	bolt.arrived.connect(_on_bolt_arrived)


## Point under the mouse cursor on the vertical plane through the villain.
func _mouse_aim_point() -> Vector3:
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var origin: Vector3 = camera.project_ray_origin(mouse)
	var dir: Vector3 = camera.project_ray_normal(mouse)
	var plane := Plane(Vector3.BACK, villain.global_position.z)
	var hit = plane.intersects_ray(origin, dir)
	return hit if hit != null else origin + dir * 40.0


## True when [param point] is within the villain's body (feet-to-head capsule).
func _hits_villain(point: Vector3) -> bool:
	var feet: Vector3 = villain.global_position
	var head: Vector3 = feet + Vector3.UP * 1.75 * VILLAIN_SCALE
	var closest: Vector3 = Geometry3D.get_closest_point_to_segment(point, feet, head)
	return point.distance_to(closest) <= float(cfg.villain_hit_radius)


func _on_bolt_arrived(bolt: Node3D, _target: Node3D) -> void:
	var point: Vector3 = bolt.target_point
	if stage != Stage.FIGHT:
		return
	if _hits_villain(point):
		Fx.burst(self, point, HERO_RED, 1.2)
		sfx.play("spell_hit")
		_villain_struck()
	else:
		Fx.burst(self, point, Color(0.7, 0.7, 0.7), 0.5)
		sfx.play("spell_miss")
		if rules.deflects > 0:
			hud.show_banner("Missed! Streak lost", Color(1, 0.5, 0.4), 0.7)
		rules.register_miss()
		hud.set_deflects(rules.deflects)
		print("[event] miss")


# ---------------------------------------------------------------- duel

func _begin_descent() -> void:
	stage = Stage.DESCEND
	_drop_held_brick()
	_villain_anim_left = 0.0
	for b in bricks:
		if is_instance_valid(b):
			b.smash()
	bricks.clear()
	_release_in = -1.0
	_stun = 0.0
	_protego_left = 0.0
	_shield.visible = false
	hud.show_banner("He's coming down!", GREEN, 1.2)
	villain.play(RUN, 0.0)
	var from: Vector3 = villain.global_position
	var tw := create_tween()
	tw.tween_method(func(u: float) -> void:
		villain.global_position = from.lerp(DUEL_SPOT, u) + Vector3.UP * 3.0 * 4.0 * u * (1.0 - u), 0.0, 1.0, 1.1)
	tw.parallel().tween_property(player, "position", DUEL_PLAYER, 1.1)
	tw.parallel().tween_property(player, "rotation:y", PI, 0.4)
	tw.parallel().tween_property(villain, "rotation:y", 0.0, 1.1)
	tw.tween_callback(func() -> void:
		Fx.burst(self, DUEL_SPOT + Vector3.UP * 0.2, GREEN, 2.0)
		_shake = 0.5
		sfx.play("villain_land")
		_start_duel())


func _start_duel() -> void:
	stage = Stage.DUEL
	rules.start_duel()
	_cam_goal = CAM_DUEL
	_next_surge = float(cfg.duel_surge_every)
	# Freeze both at the exact moment the arm is fully extended (measured).
	player.freeze_at(CAST, BEAM_POSE_TIME)
	villain.freeze_at(CAST, BEAM_POSE_TIME)
	_duel_fx.set_active(true)
	hud.show_duel(true)
	sfx.start_loop("duel_beam")
	hud.set_hint("")
	hud.show_banner("PRIORI INCANTATUM!", GOLD, 1.0)
	print("[event] duel start")


func _update_duel(delta: float) -> void:
	var surge: float = 0.0
	_next_surge -= delta
	if _next_surge <= 0.0:
		surge = float(cfg.duel_surge_push)
		_next_surge = float(cfg.duel_surge_every) * randf_range(0.7, 1.3)
		_duel_fx.surge(GREEN)
		_shake = 0.25
		# The storm answers every surge with a bolt behind the duellists.
		_lightning_strike(null, Vector3(randf_range(-9.0, -3.0), 0, randf_range(-7.0, 2.0)))
	var result: int = rules.tick_duel(delta, surge)
	# Wands point at each other; beams leave from the wand tips.
	player.aim_wand_at(villain.hand_position())
	villain.aim_wand_at(player.hand_position())
	var ph: Vector3 = player.wand_tip_position()
	var vh: Vector3 = villain.wand_tip_position()
	_duel_fx.update(ph, vh, rules.tug, delta)
	hud.set_tug(rules.tug)
	if result == Rules.ROUND_PLAYER_WON:
		_duel_won()
	elif result == Rules.ROUND_VILLAIN_WON:
		_duel_lost()


func _mash() -> void:
	rules.mash()
	sfx.play("duel_mash")
	_duel_fx.pulse()
	_shake = max(_shake, 0.06)


func _end_duel_visuals() -> void:
	_duel_fx.shockwave(_duel_fx.clash_position(), GOLD, 9.0)
	_duel_fx.set_active(false)
	hud.show_duel(false)
	sfx.stop_loop("duel_beam")
	_cam_goal = CAM_FIGHT


func _duel_won() -> void:
	_end_duel_visuals()
	Fx.burst(self, villain.global_position + CHEST, GOLD, 2.5)
	sfx.play("duel_win")
	_shake = 0.6
	hud.set_villain(rules.villain_hearts)
	hud.set_deflects(0)
	print("[event] duel won, villain hearts=%d" % rules.villain_hearts)
	if rules.phase == Rules.Phase.SNITCH:
		_villain_defeated()
	else:
		var left: String = "1 heart left!" if rules.villain_hearts == 1 else "%d hearts left!" % rules.villain_hearts
		hud.show_banner("Direct hit! " + left, GOLD, 1.4)
		_return_villain()


func _duel_lost() -> void:
	_end_duel_visuals()
	Fx.burst(self, player.global_position + CHEST, GREEN, 2.0)
	sfx.play("duel_lose")
	_shake = 0.6
	hud.set_player(rules.player_hearts)
	hud.set_deflects(0)
	print("[event] duel lost, player hearts=%d" % rules.player_hearts)
	if rules.phase == Rules.Phase.LOST:
		_game_over()
	else:
		hud.show_banner("He overpowered you!", GREEN, 1.4)
		_return_villain()


func _return_villain() -> void:
	stage = Stage.ASCEND
	create_tween().tween_property(player, "position", Vector3(0, 0, PLAYER_Z), 1.0)
	_idle(player)
	get_tree().create_timer(0.6).timeout.connect(func() -> void:
		_levitate(BALCONY, 2.0, func() -> void:
			_throw_timer = 0.8
			hud.set_hint(HINT_FIGHT % int(cfg.deflects_to_duel))
			stage = Stage.FIGHT))


## Floats the villain to [param to] in his idle pose with a green glow under
## his feet, then calls [param done].
func _levitate(to: Vector3, time: float, done: Callable) -> void:
	villain.play(IDLE)
	var glow := Fx.cylinder(0.9, 0.05, Fx.mat(Color(GREEN.r, GREEN.g, GREEN.b, 0.55), 5.0))
	var light := OmniLight3D.new()
	light.light_color = GREEN
	light.light_energy = 3.0
	light.omni_range = 4.0
	glow.add_child(light)
	villain.add_child(glow)
	var from: Vector3 = villain.global_position
	var tw := create_tween()
	tw.tween_method(func(u: float) -> void:
		var e: float = ease(u, -2.2)
		villain.global_position = from.lerp(to, e) + Vector3(sin(u * TAU) * 0.3, 0.0, 0.0)
		glow.rotation.y = u * TAU * 2.0
		glow.scale = Vector3.ONE * (1.0 + 0.15 * sin(u * 30.0)), 0.0, 1.0, time)
	tw.tween_callback(func() -> void:
		glow.queue_free()
		_idle(villain)
		done.call())


# ---------------------------------------------------------------- ending

func _villain_defeated() -> void:
	stage = Stage.SNITCH
	_cam_goal = CAM_SNITCH
	hud.show_banner("The Dark Mage falls! Catch the Golden Snitch!", GOLD, 2.4)
	hud.set_hint(HINT_SNITCH)
	villain.replay(DEAD)
	sfx.play("villain_defeat")
	var tw := create_tween()
	tw.tween_interval(villain.clip_length(DEAD) + 0.5)
	tw.tween_callback(func() -> void: Fx.burst(self, villain.global_position + Vector3.UP * 0.4, GREEN, 2.5))
	tw.tween_property(villain, "scale", Vector3.ZERO, 0.4)
	tw.tween_callback(func() -> void:
		villain.visible = false
		snitch = Snitch.new()
		add_child(snitch)
		snitch.global_position = DUEL_SPOT + Vector3.UP * 1.5
		snitch.speed = float(cfg.snitch_speed)
		snitch.flee_from = player
		sfx.play("snitch_appear")
		print("[event] snitch spawned"))


func _try_catch() -> void:
	_player_lock = 0.3
	player.replay(CAST, 2.5)
	if not is_instance_valid(snitch):
		return
	if snitch.global_position.distance_to(player.global_position + CHEST) <= float(cfg.snitch_catch_radius):
		rules.catch_snitch()
		_victory()


func _victory() -> void:
	stage = Stage.END
	print("[event] victory")
	sfx.play("victory")
	Fx.burst(self, snitch.global_position, GOLD, 2.0)
	snitch.set_process(false)
	var tw := create_tween()
	tw.tween_property(snitch, "global_position", camera.global_position + camera.global_basis.z * -2.5 + Vector3(0, -0.2, 0), 0.8)
	tw.parallel().tween_property(snitch, "scale", Vector3.ONE * 1.6, 0.8)
	player.replay(CAST, 1.0)
	if _level < _levels - 1:
		# More levels to go: show the result briefly, then load the next one.
		hud.show_end("LEVEL %d CLEARED!" % (_level + 1),
			"Level %d: the Dark Mage returns stronger..." % (_level + 2), GOLD)
		_level += 1
		get_tree().create_timer(LEVEL_BREAK).timeout.connect(get_tree().reload_current_scene)
		return
	hud.show_end("VICTORY!", "You defeated the Dark Mage on every level!\nPress R to play again", GOLD)
	_end_if_requested()


func _game_over() -> void:
	stage = Stage.END
	_drop_held_brick()
	print("[event] game over")
	sfx.stop_loop("duel_beam")
	sfx.play("defeat")
	for b in bricks:
		if is_instance_valid(b):
			b.smash()
	bricks.clear()
	player.visible = true
	player.replay(DEAD)
	hud.show_end("DEFEATED", "The Dark Mage wins this time.\nPress R to try again", Color(1, 0.3, 0.3))
	_end_if_requested()


# ---------------------------------------------------------------- camera

func _update_camera(delta: float) -> void:
	if is_instance_valid(snitch) and stage == Stage.SNITCH:
		_cam_goal = [player.global_position + Vector3(0, 3.2, 6.5), player.global_position.lerp(snitch.global_position, 0.5)]
	var goal_pos: Vector3 = _cam_goal[0]
	var goal_look: Vector3 = _cam_goal[1]
	if _cam_goal == CAM_FIGHT:
		# Follow the wizard sideways so he stays framed.
		goal_pos.x += player.position.x * 0.6
		goal_look.x += player.position.x * 0.25
		goal_pos.z += player.position.z - PLAYER_Z
	_cam_pos = _cam_pos.lerp(goal_pos, 3.0 * delta)
	_cam_look = _cam_look.lerp(goal_look, 3.0 * delta)
	_shake = max(_shake - delta, 0.0)
	var jitter: Vector3 = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.4
	camera.position = _cam_pos + jitter
	camera.look_at(_cam_look)


# ---------------------------------------------------------------- debug / QA

func _parse_debug_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.trim_prefix("--").split("=", true, 1)
		_dbg[parts[0]] = parts[1] if parts.size() > 1 else "1"
	if _dbg.has("shot"):
		var delay: float = float(_dbg.get("shot-delay", "3"))
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			var img: Image = get_viewport().get_texture().get_image()
			img.save_png(_dbg["shot"])
			print("[shot] saved ", _dbg["shot"])
			get_tree().quit())


func _apply_debug_phase() -> void:
	match _dbg.get("phase", ""):
		"lose":
			rules.player_hearts = 1
			_player_hit()
		"duel":
			rules.deflects = int(cfg.deflects_to_duel) - 1
			_villain_struck()
		"snitch":
			rules.villain_hearts = 0
			rules.phase = Rules.Phase.SNITCH
			hud.set_villain(0)
			villain.global_position = DUEL_SPOT
			_villain_defeated()


func _debug_autoplay(delta: float) -> void:
	if not _dbg.has("autoplay"):
		return
	match stage:
		Stage.FIGHT:
			# QA bot aims perfectly at the villain's chest.
			if _spell_cd <= 0.0:
				# Imperfect aim so misses (and streak resets) also get exercised.
				var err := Vector3(randf_range(-1.6, 1.6), randf_range(-0.6, 0.6), 0)
				_cast_spell(villain.global_position + CHEST * VILLAIN_SCALE + err)
			for b in bricks:
				if not is_instance_valid(b) or b.state != Brick.State.INCOMING:
					continue
				if not b.cursed and b.global_position.distance_to(player.global_position + CHEST) < float(cfg.protego_radius) - 0.4:
					_cast_protego()
		Stage.DUEL:
			_auto_mash_acc += delta * 13.0
			while _auto_mash_acc >= 1.0:
				_auto_mash_acc -= 1.0
				_mash()
		Stage.SNITCH:
			if _spell_cd <= 0.0:
				_spell_cd = 0.25
				_try_catch()


func _end_if_requested() -> void:
	if _dbg.has("quit-on-end"):
		get_tree().create_timer(1.5).timeout.connect(func() -> void: get_tree().quit())
