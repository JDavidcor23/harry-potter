extends Node3D
## Wraps an imported rigged character (Mixamo-style GLB): plays its clips
## in place, holds poses, and exposes the right-hand position for spells.

var anim: AnimationPlayer
var skeleton: Skeleton3D
var model: Node3D
var _hand_bone: int = -1
var _current: String = ""
## Wand tip (or fingertip) in right-hand bone space, found from the skin.
var _wand_tip_local: Vector3 = Vector3.ZERO
var _has_tip: bool = false


## Instantiates [param scene] under this node, rotated by [param yaw] so the
## model faces this node's -Z. [param looping] lists clips that should loop.
func setup(scene: PackedScene, yaw: float, looping: Array) -> void:
	model = scene.instantiate() as Node3D
	add_child(model)
	model.rotation.y = yaw
	var players: Array[Node] = model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		anim = players[0] as AnimationPlayer
	var skels: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		skeleton = skels[0] as Skeleton3D
		for i in skeleton.get_bone_count():
			if skeleton.get_bone_name(i).to_lower().ends_with("righthand"):
				_hand_bone = i
				break
	if anim:
		_prepare_animations(looping)
	_find_wand_tip()


## Imports clip [param clip] from another GLB of the same rig and registers it
## under [param as_name]. Track paths must match (same skeleton export).
func add_clip_from(scene: PackedScene, clip: String, as_name: String, looping: bool) -> void:
	if anim == null:
		return
	var donor: Node = scene.instantiate()
	var players: Array[Node] = donor.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var src: AnimationPlayer = players[0]
		if src.has_animation(clip):
			var a: Animation = src.get_animation(clip).duplicate(true)
			a.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
			var root_bone: String = skeleton.get_bone_name(0) if skeleton and skeleton.get_bone_count() > 0 else ""
			for i in (skeleton.get_bone_count() if skeleton else 0):
				if skeleton.get_bone_parent(i) == -1:
					root_bone = skeleton.get_bone_name(i)
					break
			_strip_root_motion(a, root_bone)
			var lib_name: StringName = anim.get_animation_library_list()[0]
			anim.get_animation_library(lib_name).add_animation(as_name, a)
	donor.free()


func has_clip(clip: String) -> bool:
	return anim != null and anim.has_animation(clip)


## Plays a clip (no-op if it is already playing).
func play(clip: String, speed: float = 1.0, blend: float = 0.2) -> void:
	if anim == null or not anim.has_animation(clip):
		return
	if _current == clip and anim.is_playing():
		anim.speed_scale = speed
		return
	_current = clip
	anim.speed_scale = speed
	anim.play(clip, blend)


## Restarts a clip from the beginning even if it is the current one.
func replay(clip: String, speed: float = 1.0) -> void:
	_current = ""
	play(clip, speed, 0.1)


## Freezes the character in [param clip] at [param ratio] (0..1) of its length.
func hold_pose(clip: String, ratio: float) -> void:
	if anim == null or not anim.has_animation(clip):
		return
	_current = "pose:" + clip
	anim.play(clip, 0.15)
	anim.seek(anim.get_animation(clip).length * ratio, true)
	anim.pause()


## Snaps (no blending) to [param seconds] of [param clip] and freezes there.
## Blending into a paused clip would freeze a mix of two poses.
func freeze_at(clip: String, seconds: float) -> void:
	if anim == null or not anim.has_animation(clip):
		return
	_current = "freeze:" + clip
	anim.play(clip, 0.0)
	anim.seek(seconds, true)
	anim.pause()


func clip_length(clip: String) -> float:
	if anim and anim.has_animation(clip):
		return anim.get_animation(clip).length
	return 1.0


## World position of the right hand (wand tip), with a chest fallback.
func hand_position() -> Vector3:
	if skeleton and _hand_bone >= 0:
		return skeleton.global_transform * skeleton.get_bone_global_pose(_hand_bone).origin
	return global_position + Vector3(0, 1.3, 0)


## World position of the wand tip; falls back to the hand.
func wand_tip_position() -> Vector3:
	if not _has_tip:
		return hand_position()
	var hand_pose: Transform3D = skeleton.get_bone_global_pose(_hand_bone)
	return skeleton.global_transform * (hand_pose * _wand_tip_local)


## Rotates the right hand so the wand points at [param world_target]. Call
## every frame while the clip is frozen; a playing clip overwrites it.
func aim_wand_at(world_target: Vector3) -> void:
	if not _has_tip:
		return
	var hand_pose: Transform3D = skeleton.get_bone_global_pose(_hand_bone)
	var tip_dir: Vector3 = (hand_pose.basis * _wand_tip_local).normalized()
	var target: Vector3 = skeleton.global_transform.affine_inverse() * world_target
	var want: Vector3 = (target - hand_pose.origin).normalized()
	if tip_dir.dot(want) > 0.9999:
		return
	var new_global: Basis = Basis(Quaternion(tip_dir, want)) * hand_pose.basis.orthonormalized()
	var parent: int = skeleton.get_bone_parent(_hand_bone)
	var parent_basis: Basis = skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis()
	skeleton.set_bone_pose_rotation(_hand_bone, (parent_basis.inverse() * new_global).get_rotation_quaternion())


## The wand is part of the skinned mesh, weighted to the right hand. Its tip is
## the hand-weighted vertex farthest from the hand joint, in bind (bone) space.
func _find_wand_tip() -> void:
	if skeleton == null or _hand_bone < 0:
		return
	var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return
	var mi := meshes[0] as MeshInstance3D
	if mi.skin == null or mi.mesh == null:
		return
	var bind_idx: int = -1
	var hand_name: StringName = skeleton.get_bone_name(_hand_bone)
	for b in mi.skin.get_bind_count():
		if mi.skin.get_bind_name(b) == hand_name or mi.skin.get_bind_bone(b) == _hand_bone:
			bind_idx = b
			break
	if bind_idx < 0:
		return
	var bind: Transform3D = mi.skin.get_bind_pose(bind_idx)
	var best: float = 0.0
	for s in mi.mesh.get_surface_count():
		var arrays: Array = mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		if bones == null or weights == null or verts.is_empty():
			continue
		var per: int = bones.size() / verts.size()
		for v in verts.size():
			for k in per:
				if bones[v * per + k] == bind_idx and weights[v * per + k] > 0.8:
					var local: Vector3 = bind * verts[v]
					if local.length() > best:
						best = local.length()
						_wand_tip_local = local
					break
	_has_tip = best > 0.0


func _prepare_animations(looping: Array) -> void:
	var root_bone: String = ""
	if skeleton:
		for i in skeleton.get_bone_count():
			if skeleton.get_bone_parent(i) == -1:
				root_bone = skeleton.get_bone_name(i)
				break
	for lib_name in anim.get_animation_library_list():
		var lib: AnimationLibrary = anim.get_animation_library(lib_name)
		for clip_name in lib.get_animation_list():
			var a: Animation = lib.get_animation(clip_name)
			a.loop_mode = Animation.LOOP_LINEAR if looping.has(String(clip_name)) else Animation.LOOP_NONE
			_strip_root_motion(a, root_bone)


## Keeps the root bone's height but pins its X/Z to the first key, so running
## clips play in place and the script owns movement.
func _strip_root_motion(a: Animation, root_bone: String) -> void:
	if root_bone.is_empty():
		return
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		if a.track_get_path(t).get_concatenated_subnames() != root_bone:
			continue
		var keys: int = a.track_get_key_count(t)
		if keys == 0:
			continue
		var first: Vector3 = a.track_get_key_value(t, 0)
		for k in keys:
			var v: Vector3 = a.track_get_key_value(t, k)
			a.track_set_key_value(t, k, Vector3(first.x, v.y, first.z))
