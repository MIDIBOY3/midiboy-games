extends Node3D

var sep_target: float   = 0.0
var sep_t: float        = 0.0
var robot_target: float = 0.0
var robot_t: float      = 0.0

var _collected: Array    = [1]   # unit IDs owned by player (Unit1 always present)
var _available: Dictionary = {}  # uid → Vector3 world pos (static pickup at screen bottom)
var _docked_units: Array = []    # joined mid-formation; held at combined pos until group merges

@onready var unit1: Node3D = $"../Unit1"
@onready var unit2: Node3D = $"../Unit2"
@onready var unit3: Node3D = $"../Unit3"
@onready var unit4: Node3D = $"../Unit4"
@onready var unit5: Node3D = $"../Unit5"

const COMBINED := {
	2: Vector3(0.0,  0.08, -0.04),
	3: Vector3(0.0,  0.08, -0.01),
	4: Vector3(0.0,  0.08, -0.02),
	5: Vector3(0.0,  0.08, -0.06),
}

const SEPARATED := {
	2: Vector3( 0.0,  -0.55, -0.04),
	3: Vector3(-0.85,  0.0,  -0.01),
	4: Vector3( 0.0,   0.55, -0.02),
	5: Vector3( 0.85,  0.0,  -0.06),
}

# GOLDEN robot form (backview humanoid flying up).
# Unit1 (blue)   → chest / core  (rises +0.06; nose tip protrudes upward as head crest).
# Unit4 (green)  → back / spine  (descends to back level; cannons at fuselage sides).
# Unit3 (gold)   → arms          (rotate 90° + scale → wide horizontal arms).
# Unit2 (purple) → waist         (pivots + body compress to center → waist block).
# Unit5 (orange) → legs          (180°X flip through back; halves spread = L/R legs).
const ROBOT := {
	4: Vector3( 0.0,  -0.10, -0.03),
	3: Vector3( 0.0,   0.00, -0.01),
	2: Vector3( 0.0,  -0.25, -0.04),
	5: Vector3( 0.0,  -1.07, -0.06),
}

# TOP-DOWN walk arena (F5) ONLY - separate from the flight/robot stack.
# This is the confirmed "crown + shoulders + arms" layout: arms flank the head,
# shoulders sit close behind it, and waist/legs stay tucked behind the crown.
# x/y are screen-space offsets rotated by heading; z is depth toward the overhead camera.
const ROBOT_TOPDOWN := {
	3: Vector3( 0.0,   0.00,  0.05),   # arms flank the crown through Unit3's own rig
	4: Vector3( 0.0,  -0.07,  0.00),   # back/shoulders close behind the crown
	2: Vector3( 0.0,   0.00, -0.45),   # waist hidden behind the head
	5: Vector3( 0.0,  -0.42, -0.12),   # GERWALK: legs deploy behind/below, kept visible (was hidden tuck)
}

const COLLECT_RADIUS := 0.5  # world units (scaled by base_scale)

# --- Organic formation motion ---
# Each unit orbits the player (common slow revolution + per-unit angle wobble
# and radius breathing at different frequencies) and follows its orbit point
# with spring-damper inertia, so no two units ever move alike.
const ORBIT_BASE_ANGLE := {2: -PI / 2, 3: PI, 4: PI / 2, 5: 0.0}
const ORBIT_WOBBLE_F   := {2: 0.013, 3: 0.017, 4: 0.011, 5: 0.019}
const ORBIT_RAD_F      := {2: 0.021, 3: 0.015, 4: 0.018, 5: 0.012}
const ORBIT_SPEED      := 0.015   # rad/frame, full revolution ~13s
const SPRING           := 0.08    # acceleration toward orbit point
const DAMPING          := 0.55    # velocity retention per frame

var _form_state: Dictionary = {}  # uid -> {"pos": Vector3, "vel": Vector3}
var _prev_sep: float = 0.0
var _prev_robot: bool = false

# Per-unit transform amount (0 fighter … 1 robot). Normally every part equals robot_t, but in
# the arena GERWALK only arms(3)/legs(5) reach 1 while chest/waist/back stay folded as a fighter.
var _unit_rt: Dictionary = {1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0, 5: 0.0}

func _ready() -> void:
	call_deferred("_init_bullet_scenes")

func _init_bullet_scenes() -> void:
	pass  # bullet_scene is assigned only on collection via _collect_unit

func _process(delta: float) -> void:
	sep_t   = move_toward(sep_t,   sep_target,   delta * 3.0)
	robot_t = move_toward(robot_t, robot_target, delta * 2.0)
	GameState.robot_t         = robot_t
	GameState.sep_t           = sep_t
	GameState.formation_count = _collected.size()
	GameState.collected_units = _collected
	GameState.docked_units    = _docked_units

	# Life merge: the moment the formation fully combines, every member's
	# life equalizes to the average (the combined body shares one pool).
	if _prev_sep >= 0.05 and sep_t < 0.05 and _collected.size() > 1:
		var total := 0.0
		for uid in _collected:
			total += GameState.unit_life[uid - 1]
		var avg := total / float(_collected.size())
		for uid in _collected:
			GameState.unit_life[uid - 1] = avg
	_prev_sep = sep_t

	# Golden robot is driven entirely by the timed Golden state (the G-icon power) —
	# no manual transform. robot_t=1 fully overrides the pose, so we DON'T touch
	# sep_target: whatever formation the player was in when they grabbed the G (combined
	# or separated) is preserved and restored the instant the timer ends.
	var want_robot := GameState.golden_active or GameState.motion_debug
	robot_target = 1.0 if want_robot else 0.0
	# Walk prototype: base shape is the combined 5-unit fighter; standing = robot, and
	# HOLDING left click melts it back down to the fighter (the "airplane"). robot_t drives
	# the existing space transform either way.
	if GameState.golden_walk:
		sep_target = 0.0
		robot_target = 0.0 if GameState.golden_airplane_hold else 1.0
	_prev_robot = want_robot

	# Per-part transform targets. In the arena Golden the FIGHTER folds every part (0) and the
	# GERWALK (Valkyrie half-transform) deploys only arms(3)/legs(5) while chest/waist/back stay
	# folded; elsewhere parts track the shared robot_t. The fighter is keyed on airplane_hold
	# (immediate), NOT on robot_t (which lags 1→0) — otherwise the chest/back briefly bulge toward
	# full-robot as robot_t eased down, the "jumps to robot then morphs" glitch on fold-up.
	var arena_golden := GameState.golden_walk and GameState.arena_active
	for gid in [1, 2, 3, 4, 5]:
		var rt_tgt: float = robot_t
		if arena_golden:
			if GameState.golden_airplane_hold:
				rt_tgt = 0.0
			else:
				rt_tgt = 1.0 if gid == 3 or gid == 5 else 0.0
		_unit_rt[gid] = move_toward(_unit_rt[gid], rt_tgt, delta * 2.0)

	# Once fully combined, docked units are integrated — unlock.
	if _docked_units.size() > 0 and sep_t < 0.05:
		_docked_units.clear()

	var alt_t: float = 1.0 - (GameState.sky_t())
	var base_pos   := unit1.global_position
	var base_scale := unit1.scale.x

	if unit1.has_method("set_robot"):
		unit1.set_robot(_unit_rt[1])

	GameState.god_mode = robot_t > 0.5
	var walk_facing_deg := GameState.golden_walk_facing_deg \
		if GameState.golden_walk and not GameState.golden_airplane_hold else 0.0
	# In the top-down walk arena Unit1 owns its FULL basis (Rz·Rx, crown-to-camera) — don't
	# also poke its euler .z here or it re-decomposes the basis and the order-fix is undone.
	# NOTE: stays true through the fighter too (not gated on airplane_hold). Otherwise the arms/legs
	# r_world would snap from ROBOT_TOPDOWN to ROBOT the instant you fold up, jerking them while
	# _unit_rt is still ~1. Keeping it on lets _unit_rt linearly fold the parts to centre instead.
	var topdown_walk := GameState.golden_walk and GameState.arena_active
	if not topdown_walk:
		unit1.rotation_degrees.z = walk_facing_deg

	var picked := false  # at most ONE pickup per frame (see the collect guard below)
	for uid in [2, 3, 4, 5]:
		var u: Node3D = _get_unit(uid)
		if u == null:
			continue

		# --- Pickup: waits on a carrier pad, player flies in to collect ---
		if uid in _available:
			u.visible = true
			# Track the carrier's LIVE pad position — it scrolls every frame, so the
			# stale stored pos let the pickup trail the deck and the outer lanes
			# overhang the hull. (Boss-arena offers have no carrier and keep their pos.)
			var ship := get_tree().get_first_node_in_group("mothership")
			if ship != null and ship.has_method("offered_slot_pos"):
				var sp: Variant = ship.offered_slot_pos(uid)
				if sp != null:
					_available[uid] = sp
			u.global_position = _available[uid]
			u.scale = unit1.scale
			# Sit flat on the pad (a re-offered unit may carry a stale bank / flip).
			u.rotation_degrees = Vector3(unit1.rotation_degrees.x, 0.0, 0.0)
			if u.has_method("set_robot"): u.set_robot(0.0)
			if u.has_method("set_rig"):   u.set_rig(alt_t, 0.0)
			# Only ONE pickup per frame: adjacent lane pads sit within COLLECT_RADIUS,
			# so flying up the gap between two lanes used to grab BOTH in one frame
			# (the one-per-pass gate runs a frame later — too late to stop it).
			if not picked and _available[uid].distance_to(base_pos) < COLLECT_RADIUS * base_scale:
				_collect_unit(uid)
				picked = true
			continue

		# --- Not yet revealed ---
		if uid not in _collected:
			u.visible = false
			continue

		# --- Active: part of formation / combined / robot ---
		var c: Vector3 = COMBINED[uid]
		var r: Vector3 = ROBOT[uid]
		var eff_sep: float = 0.0 if uid in _docked_units else sep_t
		# Read the pitch from the shared clean scalar: in the top-down arena Unit1's basis is
		# Rz·Rx, so reading unit1.rotation_degrees.x back would give a turn-corrupted angle.
		var pitch_rad := deg_to_rad(GameState.golden_robot_pitch_deg) if topdown_walk \
			else deg_to_rad(unit1.rotation_degrees.x)
		var turn_rad := deg_to_rad(walk_facing_deg)

		# Fixed anchor poses (combined / robot).
		var c_off := Vector3(c.x * base_scale, c.y * base_scale, c.z)
		var r_off := Vector3(r.x * base_scale, r.y * base_scale, r.z)
		if GameState.golden_walk and not GameState.golden_airplane_hold:
			c_off = c_off.rotated(Vector3(0.0, 0.0, 1.0), turn_rad)
			r_off = r_off.rotated(Vector3(0.0, 0.0, 1.0), turn_rad)
		var c_world := base_pos + c_off.rotated(Vector3.RIGHT, pitch_rad)
		var r_world := base_pos + r_off.rotated(Vector3.RIGHT, pitch_rad)
		if topdown_walk:
			# Place parts in SCREEN space (see ROBOT_TOPDOWN): the planar x/y turn with the
			# mech's heading; z is kept along the camera axis so the depth tuck (what hides
			# behind the crown) is independent of which way the mech faces.
			var td: Vector3 = ROBOT_TOPDOWN.get(uid, Vector3.ZERO)
			var planar := Vector3(td.x * base_scale, td.y * base_scale, 0.0) \
				.rotated(Vector3(0.0, 0.0, 1.0), turn_rad)
			r_world = base_pos + planar + Vector3(0.0, 0.0, td.z * base_scale)

		# Organic formation: orbit point around the player + inertia.
		var f := float(GameState.frame)
		var ang: float = ORBIT_BASE_ANGLE[uid] + f * ORBIT_SPEED \
			+ sin(f * ORBIT_WOBBLE_F[uid] + uid * 1.7) * 0.5
		var rad: float = 0.62 + sin(f * ORBIT_RAD_F[uid] + uid * 2.1) * 0.15
		var orbit_off := Vector3(cos(ang) * rad * base_scale, sin(ang) * rad * base_scale, SEPARATED[uid].z)
		var target := base_pos + orbit_off.rotated(Vector3.RIGHT, pitch_rad)

		var st: Dictionary = _form_state.get(uid, {})
		if st.is_empty():
			st = {"pos": u.global_position, "vel": Vector3.ZERO}
			_form_state[uid] = st
		st["vel"] = st["vel"] * DAMPING + (target - st["pos"]) * SPRING
		st["pos"] = st["pos"] + st["vel"]

		u.global_position = c_world.lerp(st["pos"], eff_sep).lerp(r_world, _unit_rt[uid])
		u.scale = unit1.scale

		# Bank into lateral motion while in formation (never in combined/robot).
		var bank: float = clampf(-st["vel"].x * 600.0, -10.0, 10.0) * eff_sep * (1.0 - _unit_rt[uid])

		if u.has_method("set_robot"): u.set_robot(_unit_rt[uid])
		if u.has_method("set_rig"):   u.set_rig(alt_t, 0.0)
		# Unit5 is the legs: flipped 180° about X for the robot pose, then leaned
		# with the whole robot. Assign the FULL euler in ONE write — interleaved
		# partial rotation_degrees.x/.z writes thrash the euler decomposition once
		# |x| passes 90° (the -140° flip): Godot re-normalizes (x≈-40, y/z≈±180)
		# on read-back, so the next .z partial-write collapsed the flip and the
		# legs came out statically 90°-mis-tilted (root Y seen oscillating 0/-1).
		var flip_deg: float = lerpf(0.0, -180.0, _unit_rt[uid]) if uid == 5 else 0.0
		if GameState.golden_walk and not GameState.golden_airplane_hold:
			# Emulate a single parent group rotating around Z: rotate the already
			# placed robot part as a whole, instead of asking each unit's Euler angles
			# to combine X-flip + Z-turn independently. This keeps Unit5's -180° flip
			# and the arm/leg internals from decomposing into strange per-part twists.
			var group_basis := Basis(Vector3(0.0, 0.0, 1.0), turn_rad)
			var local_basis := Basis.from_euler(
				Vector3(pitch_rad + deg_to_rad(flip_deg), 0.0, 0.0))
			u.global_transform = Transform3D(
				(group_basis * local_basis).scaled(Vector3(base_scale, base_scale, base_scale)),
				u.global_position)
		else:
			u.rotation_degrees = Vector3(unit1.rotation_degrees.x + flip_deg, 0.0, bank)

func _collect_unit(uid: int) -> void:
	_available.erase(uid)
	_collected.append(uid)
	GameState.unit_life[uid - 1] = GameState.life_cap()
	var bs: PackedScene = unit1.get("bullet_scene") as PackedScene
	if bs != null:
		var u := _get_unit(uid)
		if u != null and u.has_method("set_bullet_scene"):
			u.set_bullet_scene(bs)
	if sep_t > 0.1:
		_docked_units.append(uid)

# A unit's life hit 0: it is destroyed and must be re-acquired (mothership).
func lose_unit(uid: int) -> void:
	_collected.erase(uid)
	_docked_units.erase(uid)
	_form_state.erase(uid)
	var u := _get_unit(uid)
	if u != null:
		u.visible = false
		if u.has_method("set_bullet_scene"):
			u.set_bullet_scene(null)

func _get_unit(uid: int) -> Node3D:
	match uid:
		2: return unit2
		3: return unit3
		4: return unit4
		5: return unit5
	return null

# Returns world position for uid's slot in the bottom row.
# Slots for uid 2,3,4,5 are evenly spaced across screen width, near the bottom.
func _bottom_row_pos(uid: int) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3((uid - 3.5) * 0.6, -2.0, 0.0)
	var sz    := get_viewport().get_visible_rect().size
	var depth := 4.0
	var idx: int = uid - 2  # uid 2→0, 3→1, 4→2, 5→3
	var x_frac: float = (idx + 0.5) / 4.0  # 0.125, 0.375, 0.625, 0.875
	var sp := Vector2(sz.x * x_frac, sz.y * 0.88)
	var wp := camera.project_position(sp, depth)
	wp.z = 0.0
	return wp

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# The click belongs to the star-target sight: no combine/separate misfire.
			if GameState.reticle_hover or GameState.in_transition():
				return
			if GameState.golden_walk:
				return   # left click is owned by the walk proto (jump / transform-hold)
			if _collected.size() > 1 and robot_t < 0.5:
				if _docked_units.size() > 0:
					sep_target = 0.0
				else:
					sep_target = 0.0 if sep_target > 0.5 else 1.0
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_TAB:
			var known := _collected.size() + _available.size()
			if known >= 5:
				return
			var next_uid: int = known + 1
			_available[next_uid] = _bottom_row_pos(next_uid)
		KEY_C:
			# Clear all acquired units and reset to Unit1 only.
			_collected    = [1]
			_available.clear()
			_docked_units.clear()
			_form_state.clear()
			sep_target   = 0.0
			robot_target = 0.0
			for u: Node3D in [unit2, unit3, unit4, unit5]:
				if u.has_method("set_bullet_scene"):
					u.set_bullet_scene(null)
		KEY_F:
			if _collected.size() > 1:
				sep_target = 1.0
		KEY_1: _debug_set_levels(1)
		KEY_2: _debug_set_levels(2)
		KEY_3: _debug_set_levels(3)
		KEY_4: _debug_set_levels(4)
		KEY_5: _debug_set_levels(5)
		KEY_G: _toggle_motion_debug()
		# Manual pose triggers (motion-check sandbox only).
		KEY_Z:
			if GameState.motion_debug:
				GameState.robot_punch = 1.0
				GameState.robot_punch_side = -GameState.robot_punch_side
		KEY_X:
			if GameState.motion_debug:
				GameState.robot_kick = 1.0
				GameState.robot_kick_side = -GameState.robot_kick_side
		KEY_V:
			if GameState.motion_debug:
				GameState.robot_laser_pose = 1.0
		KEY_B:
			if GameState.motion_debug:
				GameState.robot_rocket_pose = 1.0

# Motion-check sandbox: stand the Golden robot up on demand (all 5 units, every
# power unlocked) so the humanoid poses can be inspected without grinding or
# enemies. Toggling off just leaves the robot standing — press R to drop it.
func _toggle_motion_debug() -> void:
	GameState.motion_debug = not GameState.motion_debug
	if not GameState.motion_debug:
		return
	force_golden_walk_ready()

func force_golden_walk_ready() -> void:
	_collected = [1, 2, 3, 4, 5]
	_available.clear()
	_docked_units.clear()
	_form_state.clear()
	for i in 5:
		GameState.unit_life[i] = GameState.life_cap()
	for u: Node3D in [unit1, unit2, unit3, unit4, unit5]:
		if u != null:
			u.visible = true
	sep_t = 0.0
	GameState.sep_t = sep_t
	robot_target = 1.0
	robot_t = 1.0
	GameState.robot_t = robot_t
	sep_target = 0.0
	# Snap the per-unit transform amounts to their GERWALK target too, or F5 pops from a folded
	# fighter (all parts overlapping at centre) out to the deployed pose — the "5 don't line up /
	# shape jumps" on entry.
	var gerwalk := GameState.golden_walk and GameState.arena_active \
		and not GameState.golden_airplane_hold
	for gid in [1, 2, 3, 4, 5]:
		_unit_rt[gid] = (1.0 if gid == 3 or gid == 5 else 0.0) if gerwalk else 1.0
	GameState.formation_count = _collected.size()
	GameState.collected_units = _collected.duplicate()
	GameState.docked_units = _docked_units.duplicate()

func _debug_set_levels(lv: int) -> void:
	for i in 5:
		GameState.unit_levels[i] = lv
