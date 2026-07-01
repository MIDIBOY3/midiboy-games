class_name GoldenWalkProto
extends Node3D

# DEBUG SANDBOX — articulated HUMANOID FIGURE walk-cycle playground (toggle: F4).
#
# NOTE (2026-06-27): superseded as the "golden walk" prototype — the real Golden robot is
# the transforming 5-unit rig (Unit1.set_robot), NOT a separate body model. This file is
# KEPT ON PURPOSE as a reusable, box-built articulated humanoid (hips/knees/shoulders/elbows
# + a gait driver) for FUTURE PILOTS / DECK NPCs / cave dwellers. Do not delete.
#
# A self-contained playground to DIAL IN a human walking motion. Mirrors DeckWalkMode's
# integration (child of Main, PROCESS_MODE_ALWAYS, pauses the tree, owns its input) but is
# fully ISOLATED: it builds its own floor + the humanoid FAR from the live scene
# (SANDBOX_ORIGIN), hijacks the camera while active, and restores everything on exit.
#
# Controls while active:
#   WASD / Arrows — walk            SHIFT — run            Q / E — orbit the camera
#   1/2 leg-swing   3/4 knee-bend   5/6 arm-swing   7/8 body-bob   9/0 stride-rate
#   R — reset tuning to defaults    F4 / ESC — exit
# The on-screen readout shows the live gait numbers so you can tune by feel, then tell me
# the values to bake in.

const SANDBOX_ORIGIN := Vector3(0.0, 0.0, 4000.0)  # far from the live game world
const MAX_WALK := 2.4        # units/sec at a walk
const RUN_MULT := 2.0        # SHIFT multiplier
const ACCEL := 0.18          # velocity smoothing
const CAM_DIST := 4.2        # camera distance from the robot
const CAM_HEIGHT := 2.3      # camera height above the floor
const CAM_LOOK_Y := 0.9      # look-at height on the robot

# --- Tunable gait params (live-editable; R resets to these defaults) ---
const DEF_LEG_SWING := 0.62      # rad: hip fore/back swing amplitude
const DEF_KNEE_BEND := 0.95      # rad: peak knee flex during recovery
const DEF_ARM_SWING := 0.5       # rad: shoulder counter-swing amplitude
const DEF_BODY_BOB := 0.07       # units: vertical bob per step
const DEF_STRIDE_RATE := 2.6     # gait phase advance per unit walked (step frequency)

var _active := false
var _cam: Camera3D = null
var _cam_saved := Transform3D.IDENTITY
var _hud: CanvasLayer = null
var _root: Node3D = null            # holds floor + robot, parented under SANDBOX_ORIGIN
var _robot: Node3D = null
var _body: Node3D = null
var _hipL: Node3D; var _hipR: Node3D
var _kneeL: Node3D; var _kneeR: Node3D
var _shoL: Node3D; var _shoR: Node3D
var _elbL: Node3D; var _elbR: Node3D
var _gold: StandardMaterial3D
var _label: Label = null
var _overlay: CanvasLayer = null

# Runtime gait state.
var _vel := Vector3.ZERO
var _phase := 0.0
var _amp := 0.0                     # 0 idle .. 1 walking (eases the gait in/out)
var _yaw := 0.0
var _cam_orbit := 0.6
var _body_y := 1.0                  # rest hip height
var _prev_keys := {}

# Live tuning.
var _leg_swing := DEF_LEG_SWING
var _knee_bend := DEF_KNEE_BEND
var _arm_swing := DEF_ARM_SWING
var _body_bob := DEF_BODY_BOB
var _stride := DEF_STRIDE_RATE

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

# --- Enter / exit ---------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if not _active:
		if event.keycode == KEY_F4:
			_enter()
			get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F4 or event.keycode == KEY_ESCAPE:
		_exit()
		get_viewport().set_input_as_handled()

func _enter() -> void:
	_cam = get_viewport().get_camera_3d()
	if _cam == null:
		return
	_active = true
	_cam_saved = _cam.global_transform
	_hud = get_parent().get_node_or_null("HUD") as CanvasLayer
	if _hud != null:
		_hud.visible = false
	_build_world()
	_build_overlay()
	_reset_tuning()
	_vel = Vector3.ZERO
	_phase = 0.0
	_amp = 0.0
	_yaw = 0.0
	get_tree().paused = true

func _exit() -> void:
	_active = false
	get_tree().paused = false       # Unit1 resumes; we also hard-restore the camera below
	if _cam != null and is_instance_valid(_cam):
		_cam.global_transform = _cam_saved
	if _hud != null and is_instance_valid(_hud):
		_hud.visible = true
	if _root != null:
		_root.queue_free()
		_root = null
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
	_robot = null

# --- World + robot build --------------------------------------------------

func _build_world() -> void:
	_root = Node3D.new()
	add_child(_root)
	_root.global_position = SANDBOX_ORIGIN

	# A key light so the gold catches highlights regardless of the scene environment.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 1.1
	_root.add_child(sun)

	# Dark floor.
	var flr := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60.0, 60.0)
	flr.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.05, 0.05, 0.07)
	fmat.roughness = 0.95
	flr.material_override = fmat
	_root.add_child(flr)

	# Scattered glowing crystals — spatial reference + the "dim cave" theme.
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.3, 0.8, 1.0)
	cmat.emission_enabled = true
	cmat.emission = Color(0.35, 0.85, 1.0)
	cmat.emission_energy_multiplier = 2.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in 40:
		var a := rng.randf() * TAU
		var rad := rng.randf_range(5.0, 26.0)
		var h := rng.randf_range(0.3, 1.1)
		var cr := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.18, h, 0.18)
		cr.mesh = bm
		cr.material_override = cmat
		cr.position = Vector3(cos(a) * rad, h * 0.5, sin(a) * rad)
		cr.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf(), rng.randf_range(-0.3, 0.3))
		_root.add_child(cr)

	_build_robot()

func _gold_mat(bright: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.62, 0.16) * bright
	m.metallic = 0.95
	m.metallic_specular = 0.9
	m.roughness = 0.22
	m.emission_enabled = true
	m.emission = Color(0.9, 0.62, 0.12)
	m.emission_energy_multiplier = 1.4 * bright
	return m

func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n

# A blocky golden humanoid with REAL articulated hips/knees/shoulders/elbows so a walk
# cycle can be driven by rotating the pivots. Built standing; foot point at robot origin.
func _build_robot() -> void:
	_gold = _gold_mat()
	var dark := _gold_mat(0.45)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.45, 1.0, 0.66)
	glow.emission_enabled = true
	glow.emission = Color(0.45, 1.0, 0.66)
	glow.emission_energy_multiplier = 3.5

	_robot = Node3D.new()
	_root.add_child(_robot)
	_robot.position = Vector3.ZERO

	_body = Node3D.new()
	_robot.add_child(_body)
	_body.position = Vector3(0.0, _body_y, 0.0)   # hip plane; bob is applied here

	# Torso + head + chest core.
	_box(_body, Vector3(0.0, 0.35, 0.0), Vector3(0.6, 0.7, 0.34), _gold)
	_box(_body, Vector3(0.0, 0.18, 0.16), Vector3(0.2, 0.2, 0.06), glow)   # chest core
	_box(_body, Vector3(0.0, 0.85, 0.0), Vector3(0.36, 0.36, 0.36), _gold) # head
	_box(_body, Vector3(0.0, 0.86, 0.16), Vector3(0.26, 0.08, 0.05), glow) # visor
	_box(_body, Vector3(-0.34, 0.62, 0.0), Vector3(0.16, 0.18, 0.4), dark) # shoulder pad L
	_box(_body, Vector3(0.34, 0.62, 0.0), Vector3(0.16, 0.18, 0.4), dark)  # shoulder pad R

	# Legs: hip pivot → thigh → knee pivot → shin → foot.
	_hipL = _pivot(_body, Vector3(-0.18, 0.0, 0.0))
	_box(_hipL, Vector3(0.0, -0.26, 0.0), Vector3(0.18, 0.52, 0.18), _gold)
	_kneeL = _pivot(_hipL, Vector3(0.0, -0.52, 0.0))
	_box(_kneeL, Vector3(0.0, -0.26, 0.0), Vector3(0.16, 0.52, 0.16), dark)
	_box(_kneeL, Vector3(0.0, -0.52, 0.07), Vector3(0.18, 0.12, 0.32), _gold)

	_hipR = _pivot(_body, Vector3(0.18, 0.0, 0.0))
	_box(_hipR, Vector3(0.0, -0.26, 0.0), Vector3(0.18, 0.52, 0.18), _gold)
	_kneeR = _pivot(_hipR, Vector3(0.0, -0.52, 0.0))
	_box(_kneeR, Vector3(0.0, -0.26, 0.0), Vector3(0.16, 0.52, 0.16), dark)
	_box(_kneeR, Vector3(0.0, -0.52, 0.07), Vector3(0.18, 0.12, 0.32), _gold)

	# Arms: shoulder pivot → upper → elbow pivot → forearm.
	_shoL = _pivot(_body, Vector3(-0.42, 0.55, 0.0))
	_box(_shoL, Vector3(0.0, -0.22, 0.0), Vector3(0.14, 0.42, 0.14), _gold)
	_elbL = _pivot(_shoL, Vector3(0.0, -0.42, 0.0))
	_box(_elbL, Vector3(0.0, -0.2, 0.0), Vector3(0.13, 0.4, 0.13), dark)

	_shoR = _pivot(_body, Vector3(0.42, 0.55, 0.0))
	_box(_shoR, Vector3(0.0, -0.22, 0.0), Vector3(0.14, 0.42, 0.14), _gold)
	_elbR = _pivot(_shoR, Vector3(0.0, -0.42, 0.0))
	_box(_elbR, Vector3(0.0, -0.2, 0.0), Vector3(0.13, 0.4, 0.13), dark)

# --- Loop -----------------------------------------------------------------

func _process(delta: float) -> void:
	if not _active or _robot == null:
		return
	delta = minf(delta, 0.05)   # clamp so a hitch can't fling the figure

	# --- Movement: walk toward the cursor (mouse-only, like the game); WASD/arrows override. ---
	var spd := MAX_WALK * (RUN_MULT if (_key(KEY_SHIFT)) else 1.0)
	var dir := Vector3.ZERO
	if _key(KEY_W) or _key(KEY_UP):    dir.z -= 1.0
	if _key(KEY_S) or _key(KEY_DOWN):  dir.z += 1.0
	if _key(KEY_A) or _key(KEY_LEFT):  dir.x -= 1.0
	if _key(KEY_D) or _key(KEY_RIGHT): dir.x += 1.0
	var want := Vector3.ZERO
	if dir.length() > 0.001:
		want = dir.normalized() * spd
	else:
		# Steer toward the cursor's point on the floor; stop when it's right under us.
		var cur := _cursor_ground()
		var to := Vector3(cur.x - _robot.position.x, 0.0, cur.z - _robot.position.z)
		var d := to.length()
		if d > 0.3:
			want = to / d * spd
	_vel = _vel.lerp(want, ACCEL)
	if _vel.length() < 0.02:
		_vel = Vector3.ZERO
	_robot.position += _vel * delta

	# Face the travel direction (visor = +Z, so atan2(x, z) — fixes the earlier reversed facing).
	if _vel.length() > 0.05:
		_yaw = lerp_angle(_yaw, atan2(_vel.x, _vel.z), 0.2)
	_robot.rotation.y = _yaw

	# --- Gait drive ---
	var speed := _vel.length()
	_amp = lerpf(_amp, (1.0 if speed > 0.05 else 0.0), 0.15)
	_phase += speed * delta * _stride          # advance with distance walked
	if _phase > TAU:
		_phase -= TAU

	var s := sin(_phase)
	var so := sin(_phase + PI)
	# Hips swing fore/back, opposite phase.
	_hipL.rotation.x = s * _leg_swing * _amp
	_hipR.rotation.x = so * _leg_swing * _amp
	# Knees flex during the recovery (forward) swing — only bend, never hyperextend.
	_kneeL.rotation.x = maxf(0.0, sin(_phase + PI * 0.5)) * _knee_bend * _amp
	_kneeR.rotation.x = maxf(0.0, sin(_phase + PI * 1.5)) * _knee_bend * _amp
	# Arms counter-swing (opposite the same-side leg).
	_shoL.rotation.x = so * _arm_swing * _amp
	_shoR.rotation.x = s * _arm_swing * _amp
	_elbL.rotation.x = -0.25 - maxf(0.0, so) * 0.4 * _amp
	_elbR.rotation.x = -0.25 - maxf(0.0, s) * 0.4 * _amp
	# Body bob (twice per stride) + tiny lateral sway.
	_body.position.y = _body_y + absf(sin(_phase)) * _body_bob * _amp
	_body.position.x = sin(_phase) * 0.02 * _amp
	_body.rotation.z = -sin(_phase) * 0.04 * _amp

	_update_camera(delta)
	_handle_tuning()
	_update_overlay()

# The cursor's point on the floor plane (sandbox-local), for mouse-walk steering.
func _cursor_ground() -> Vector3:
	if _cam == null:
		return _robot.position
	var mp := get_viewport().get_mouse_position()
	var from := _cam.project_ray_origin(mp)
	var rd := _cam.project_ray_normal(mp)
	var hit: Variant = Plane(Vector3.UP, SANDBOX_ORIGIN.y).intersects_ray(from, rd)
	if hit == null:
		return _robot.global_position - SANDBOX_ORIGIN
	return (hit as Vector3) - SANDBOX_ORIGIN

func _key(k: int) -> bool:
	return Input.is_key_pressed(k)

# Edge-detected tap (true only on the frame the key goes down).
func _tap(k: int) -> bool:
	var down: bool = Input.is_key_pressed(k)
	var was: bool = _prev_keys.get(k, false)
	_prev_keys[k] = down
	return down and not was

func _update_camera(_delta: float) -> void:
	if _cam == null:
		return
	if _key(KEY_Q):
		_cam_orbit -= 1.5 * _delta
	if _key(KEY_E):
		_cam_orbit += 1.5 * _delta
	var focus := _robot.global_position + Vector3(0.0, CAM_LOOK_Y, 0.0)
	var off := Vector3(sin(_cam_orbit) * CAM_DIST, CAM_HEIGHT, cos(_cam_orbit) * CAM_DIST)
	_cam.global_position = _robot.global_position + off
	_cam.look_at(focus, Vector3.UP)

# --- Live tuning + overlay ------------------------------------------------

func _reset_tuning() -> void:
	_leg_swing = DEF_LEG_SWING
	_knee_bend = DEF_KNEE_BEND
	_arm_swing = DEF_ARM_SWING
	_body_bob = DEF_BODY_BOB
	_stride = DEF_STRIDE_RATE

func _handle_tuning() -> void:
	if _tap(KEY_1): _leg_swing = maxf(0.0, _leg_swing - 0.05)
	if _tap(KEY_2): _leg_swing += 0.05
	if _tap(KEY_3): _knee_bend = maxf(0.0, _knee_bend - 0.05)
	if _tap(KEY_4): _knee_bend += 0.05
	if _tap(KEY_5): _arm_swing = maxf(0.0, _arm_swing - 0.05)
	if _tap(KEY_6): _arm_swing += 0.05
	if _tap(KEY_7): _body_bob = maxf(0.0, _body_bob - 0.01)
	if _tap(KEY_8): _body_bob += 0.01
	if _tap(KEY_9): _stride = maxf(0.2, _stride - 0.1)
	if _tap(KEY_0): _stride += 0.1
	if _tap(KEY_R): _reset_tuning()

func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 120
	add_child(_overlay)
	_label = Label.new()
	_label.position = Vector2(16, 14)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_overlay.add_child(_label)

func _update_overlay() -> void:
	if _label == null:
		return
	_label.text = Loc.pair(
		"ヒューマノイド歩行サンドボックス  [F4/ESC 終了]\n"
			+ "移動: カーソル（またはWASD/矢印）  SHIFT 走る  Q/E 旋回\n"
			+ "脚振り 1/2: %.2f   膝曲げ 3/4: %.2f\n"
			+ "腕振り 5/6: %.2f   体上下 7/8: %.2f\n"
			+ "歩幅速度 9/0: %.1f   [R リセット]",
		"HUMANOID WALK SANDBOX  [F4/ESC exit]\n"
			+ "move: cursor (or WASD/arrows)  SHIFT run  Q/E orbit\n"
			+ "leg-swing 1/2: %.2f   knee-bend 3/4: %.2f\n"
			+ "arm-swing 5/6: %.2f   body-bob 7/8: %.2f\n"
			+ "stride-rate 9/0: %.1f   [R reset]"
	) % [_leg_swing, _knee_bend, _arm_swing, _body_bob, _stride]
