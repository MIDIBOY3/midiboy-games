class_name HumanoidAsset
extends RefCounted

# Box-built humanoid for deck pilots/NPCs, using the same proportions as
# GoldenWalkProto's sandbox body. The body stands on the deck: source upright Y maps
# to deck +Z, so the top-down carrier camera sees the crown/head instead of a body
# lying across the floor.

static func make_figure(tint: Color, size: float, role: String = "pilot") -> Node3D:
	var root := Node3D.new()
	var figure := Node3D.new()
	figure.name = "humanoid"
	root.add_child(figure)
	root.set_meta("nose", figure)
	root.set_meta("humanoid", figure)
	root.set_meta("humanoid_size", size)
	root.set_meta("humanoid_phase", randf() * TAU)

	var body_mat := _mat(tint, 0.85, role == "vip")
	var dark_mat := _mat(tint.darkened(0.35), 0.45, false)
	var light_mat := _mat(tint.lerp(Color.WHITE, 0.45), 1.1, true)

	var torso := _box(figure, _p(0.0, 0.35, 0.0, size),
		_s(0.6, 0.7, 0.34, size), body_mat)
	torso.name = "torso"
	_box(figure, _p(0.0, 0.18, 0.16, size),
		_s(0.2, 0.2, 0.06, size), light_mat).name = "chest_core"
	_box(figure, _p(0.0, 0.85, 0.0, size),
		_s(0.36, 0.36, 0.36, size), body_mat).name = "head"
	_box(figure, _p(0.0, 0.86, 0.16, size),
		_s(0.26, 0.08, 0.05, size), light_mat).name = "visor"
	_box(figure, _p(-0.34, 0.62, 0.0, size),
		_s(0.16, 0.18, 0.4, size), dark_mat).name = "left_shoulder_pad"
	_box(figure, _p(0.34, 0.62, 0.0, size),
		_s(0.16, 0.18, 0.4, size), dark_mat).name = "right_shoulder_pad"

	var hip_l := _pivot(figure, _p(-0.18, 0.0, 0.0, size), "left_hip")
	var knee_l := _leg_original(hip_l, size, body_mat, dark_mat, "left_knee")
	var hip_r := _pivot(figure, _p(0.18, 0.0, 0.0, size), "right_hip")
	var knee_r := _leg_original(hip_r, size, body_mat, dark_mat, "right_knee")

	var sho_l := _pivot(figure, _p(-0.42, 0.55, 0.0, size), "left_shoulder")
	var elb_l := _arm_original(sho_l, size, body_mat, dark_mat, "left_elbow")
	var sho_r := _pivot(figure, _p(0.42, 0.55, 0.0, size), "right_shoulder")
	var elb_r := _arm_original(sho_r, size, body_mat, dark_mat, "right_elbow")

	root.set_meta("left_shoulder", sho_l)
	root.set_meta("right_shoulder", sho_r)
	root.set_meta("left_elbow", elb_l)
	root.set_meta("right_elbow", elb_r)
	root.set_meta("left_hip", hip_l)
	root.set_meta("right_hip", hip_r)
	root.set_meta("left_knee", knee_l)
	root.set_meta("right_knee", knee_r)
	return root

static func pose_walk(root: Node3D, moving: bool, speed: float = 1.0, lift: float = 1.0) -> void:
	if not root.has_meta("humanoid"):
		return
	var phase := float(root.get_meta("humanoid_phase", 0.0))
	if moving:
		phase += 0.22 * speed
	root.set_meta("humanoid_phase", phase)
	var motion := clampf(speed, 0.0, 1.8) if moving else 0.0
	var amp := 0.58 * motion * lift
	var s := sin(phase)
	var c := cos(phase)
	var l_arm := root.get_meta("left_shoulder") as Node3D
	var r_arm := root.get_meta("right_shoulder") as Node3D
	var l_elb := root.get_meta("left_elbow") as Node3D
	var r_elb := root.get_meta("right_elbow") as Node3D
	var l_hip := root.get_meta("left_hip") as Node3D
	var r_hip := root.get_meta("right_hip") as Node3D
	var l_knee := root.get_meta("left_knee") as Node3D
	var r_knee := root.get_meta("right_knee") as Node3D
	if l_arm != null:
		l_arm.rotation.x = -0.25 * lift + s * amp * 0.65
	if r_arm != null:
		r_arm.rotation.x = 0.25 * lift - s * amp * 0.65
	if l_elb != null:
		l_elb.rotation.x = -0.15 * lift - absf(c) * amp * 0.45
	if r_elb != null:
		r_elb.rotation.x = 0.15 * lift + absf(c) * amp * 0.45
	if l_hip != null:
		l_hip.rotation.x = s * amp
	if r_hip != null:
		r_hip.rotation.x = -s * amp
	if l_knee != null:
		l_knee.rotation.x = -absf(c) * amp * 0.7
	if r_knee != null:
		r_knee.rotation.x = absf(s) * amp * 0.7
	var fig := root.get_meta("humanoid") as Node3D
	if fig != null:
		fig.position.z = absf(s) * 0.004 * motion * lift

static func _mat(col: Color, glow: float, bright: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 0.35 if bright else 0.18
	m.roughness = 0.42
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = glow
	return m

static func _pivot(parent: Node3D, pos: Vector3, nm: String) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.position = pos
	parent.add_child(n)
	return n

static func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

static func _p(src_x: float, src_y: float, src_z: float, k: float) -> Vector3:
	return Vector3(src_x * k, src_z * k, src_y * k)

static func _s(src_x: float, src_y: float, src_z: float, k: float) -> Vector3:
	return Vector3(src_x * k, src_z * k, src_y * k)

static func _arm_original(parent: Node3D, size: float, body: Material,
		dark: Material, elbow_name: String) -> Node3D:
	_box(parent, _p(0.0, -0.22, 0.0, size), _s(0.14, 0.42, 0.14, size), body)
	var elbow := _pivot(parent, _p(0.0, -0.42, 0.0, size), elbow_name)
	_box(elbow, _p(0.0, -0.2, 0.0, size), _s(0.13, 0.4, 0.13, size), dark)
	return elbow

static func _leg_original(parent: Node3D, size: float, body: Material,
		dark: Material, knee_name: String) -> Node3D:
	_box(parent, _p(0.0, -0.26, 0.0, size), _s(0.18, 0.52, 0.18, size), body)
	var knee := _pivot(parent, _p(0.0, -0.52, 0.0, size), knee_name)
	_box(knee, _p(0.0, -0.26, 0.0, size), _s(0.16, 0.52, 0.16, size), dark)
	_box(knee, _p(0.0, -0.52, 0.07, size), _s(0.18, 0.12, 0.32, size), body)
	return knee
