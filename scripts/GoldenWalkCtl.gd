class_name GoldenWalkCtl
extends Node

# DEBUG — "GOLDEN walks" prototype, using the REAL transforming Golden (toggle: F5).
#
# No new model: this stands the actual in-game Golden (the 5-unit combine, via motion_debug)
# and lets you drive it on foot. Mouse-only / right-hand-only, matching the game:
#   Move          — the existing cursor-follow steers the standing Golden (it walks)
#   Left click    — single tap: JUMP (a hop). HOLD: transform into the 5-unit combined
#                   fighter (the "airplane") — release to stand back up.
#   Wheel / pan   — altitude, as usual.    F5 / ESC — exit.
#
# Click semantics + the hop arc live here; the transform & hop are applied by tiny gated
# hooks in FormationManager (robot_target) and Unit1 (draw_y) reading GameState.golden_*.

const HOLD_MS := 180          # left held longer than this → transform (else it's a jump)
const JUMP_FRAMES := 30       # length of the hop arc
const JUMP_HEIGHT := 0.62     # world-unit peak of the hop
const SPEED_REF := 0.006      # px/py move per frame that counts as "full walk speed"
const STRIDE := 3.5           # walk-cycle phase advanced per world-unit travelled (calm cadence)
const WALK_SPEED := 0.02      # max world-units/frame toward the cursor (calm, deliberate walk)
const WALK_ACCEL := 0.28      # snappier so turning toward a new heading (esp. back UP) isn't sluggish
const TURN_RATE := 0.30       # how fast the mech swings toward its travel heading (lerp_angle/frame) —
							  # high so the cannons (which fire along the facing) point where you push, fast
const WALK_STOP_DECEL := 0.35
const WALK_STOP_DEADZONE := 0.035

# --- Arena floor-walk (old cave arena: px/py = floor walk, depth pinned low) ---
const ARENA_WALK_ALT := 500.0   # pinned to the lowest arena band (ground-skimming)
const ARENA_AIR_CRUISE := 0.028  # flight form: forward world-y advanced per frame in OPEN air. The world
								 # is STATIC (like the walk) — the ship must really travel to reach the
								 # survivor, so it cruises forward through it, NOT scrolls the terrain.
const ARENA_AIR_BORE := 0.013    # forward speed while pressing INTO solid rock — slows to a grind so
								 # boring through the sealed wall has the same dig HEFT the GERWALK has.
const GERWALK_SPEED := 0.03    # GERWALK walk speed — INDEPENDENT of the fighter scroll (tune separately)
const GW_SHOOT_INTERVAL := 6     # frames between GERWALK forward shots
const GW_BULLET_SPEED := 0.16    # GERWALK shot speed (world units/frame)
const ARENA_GRAV := 0.012       # py pulled down per frame while airborne
const ARENA_JUMP_V := 0.22      # upward py velocity on a jump (clears a step)
const ARENA_MAX_FALL := 0.4     # terminal fall speed
const ARENA_FOOT := 0.14        # foot offset below py for the ground probe
const ARENA_RAD := 0.06         # terrain collision probe radius
const RAM_RADIUS := 0.46        # body-check: a block you walk/fly INTO is smashed (ガシガシ), not a wall you stick on
const JOY_DEADZONE_PX := 26.0   # cursor within this of screen centre = neutral (the mech stops)
const ARENA_FLOOR_PY := -4.0    # fallback floor line so a missing voxel floor can't drop us forever
const ARENA_Y_LIMIT := 100000.0   # Golden arena streams chunks ahead; do not stop before key-item discovery
# Retired: the old arena-walk test used a vertical screen zone that scrolled the cave while
# the Golden stayed near centre. F5 now uses the deck-pilot model instead: the Golden walks
# directly toward the cursor in X/Y and the camera follows it.
const ROBOT_SCROLL_ZONE := 1.6
const ROBOT_SCROLL_MAX := 0.018

const CAM_K_DIST := 7.0       # camera distance (× Golden scale) for the free-walk view
const CAM_K_HEIGHT := 3.2     # camera height (× Golden scale)

# Arena top-down: the camera CHASES the walking Golden (deck-pilot style) so the world scrolls
# up/down/left/right as it roams, instead of the Golden sliding inside a fixed frame.
const ARENA_CAM_FOLLOW := 0.16  # camera ease toward the Golden per frame (keeps up so there's always
								# screen room AHEAD to steer into — the cursor never pins the mech at an edge)
const ARENA_CAM_LIMIT_X := 2.8  # camera centre stops scrolling past ±this in X
const ARENA_CAM_LIMIT_Y := 3.0  # ...and ±this in Y (the vertical scroll range)
const ARENA_CAM_LEAD := 0.45    # small constant upward camera bias: the Golden sits a touch below
								# centre (still near-centred), leaving a little room to aim upward

var _on := false
var _was_pressed := false
var _press_msec := 0
var _did_air := false         # this press already became a transform-hold
var _jump_frame := JUMP_FRAMES   # >= JUMP_FRAMES → not jumping
var _last_pos := Vector2.ZERO    # last frame's (px,py) → movement amount for the gait
var _cam_saved := Transform3D.IDENTITY   # camera restored on exit
var _cam_valid := false
var _cam_orbit := 0.6            # Q/E orbit angle around the Golden
var _cam_target := Vector3.ZERO  # lazily chases the Golden so walking READS as movement
var _vy := 0.0                   # arena: vertical (py) velocity
var _grounded := false           # arena: standing on terrain / floor
var _jump_edge := false          # a quick left-tap this frame (consumed by movement)
var _started_debug_arena := false # F5 spawned the old cave arena directly
var _walk_vel := Vector2.ZERO
var _gw_shoot_timer := 0           # GERWALK forward-fire cadence
var _arena_cam_xy := Vector2.ZERO   # smoothed camera follow target (arena scroll)
var _shadow: MeshInstance3D = null
var _saved_mouse_mode := Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100       # run AFTER Unit1 so our cursor-drive wins this frame
	add_to_group("golden_ctl")

# Enter the golden-walk (stoneface) arena from gameplay — the surface gate's "way down". Same
# setup path as the F5 toggle (grants the 5-unit Golden, builds the arena, takes the camera).
func enter_from_gate() -> void:
	if not _on:
		_enable()

# Proper teardown from outside (survivor outro): restores the camera, folds the Golden, and
# triggers the arena→space exit — same path as the F5/ESC toggle.
func exit_to_space() -> void:
	if _on:
		_disable()

func _input(event: InputEvent) -> void:
	# Frozen during the survivor confrontation — no airplane toggle / zoom wheel.
	if GameState.survivor_monologue_active:
		return
	if event is InputEventMouseButton and _on and GameState.arena_active and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			GameState.golden_airplane_hold = not GameState.golden_airplane_hold
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			# Airplane altitude is LOCKED (constant cruise) — the wheel is camera zoom only.
			GameState.golden_camera_zoom = clampf(GameState.golden_camera_zoom - 0.10, 0.0, 1.0)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			GameState.golden_camera_zoom = clampf(GameState.golden_camera_zoom + 0.14, 0.0, 1.0)
			get_viewport().set_input_as_handled()
			return
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if GameState.suppress_genesis_progression():
		return
	if not _on:
		if event.keycode == KEY_F5:
			_enable()
			get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F5 or event.keycode == KEY_ESCAPE:
		_disable()
		get_viewport().set_input_as_handled()

func _enable() -> void:
	_started_debug_arena = false
	if not GameState.arena_active:
		var main := get_parent()
		if main != null and main.has_method("debug_enter_golden_arena"):
			main.call("debug_enter_golden_arena")
			_started_debug_arena = true
	_on = true
	_saved_mouse_mode = Input.get_mouse_mode()
	if GameState.arena_active:
		GameState.apply_mouse_mode()
		# Start the virtual joystick NEUTRAL: cursor at the screen centre so the mech stands still.
		Input.warp_mouse(get_viewport().get_visible_rect().size * 0.5)
	# Arm the dura-max finale: after the stoneface outro returns to space, the GOD standoff runs.
	# (Set on every entry incl. F5 so the whole chain stays debuggable.)
	GameState.true_route_active = true
	GameState.golden_walk = true
	GameState.golden_airplane_hold = false
	GameState.golden_jump_offset = 0.0
	GameState.golden_gait = 0.0
	GameState.golden_gait_amp = 0.0
	GameState.golden_arena_scroll = Vector2.ZERO
	GameState.golden_walk_facing_deg = 0.0
	GameState.golden_camera_zoom = 0.0
	_walk_vel = Vector2.ZERO
	_arena_cam_xy = Vector2(
		clampf(GameState.px, -ARENA_CAM_LIMIT_X, ARENA_CAM_LIMIT_X),
		GameState.py)
	_last_pos = Vector2(GameState.px, GameState.py)
	_was_pressed = false
	_did_air = false
	_jump_frame = JUMP_FRAMES
	_cam_orbit = 0.6
	# Free-walk camera: cache the live camera so we can restore it on exit, then take it over
	# each frame (below) to frame the walking Golden — the F4 free-walk feel for the real model.
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		_cam_saved = cam.global_transform
		_cam_valid = true
	var u0 := get_parent().get_node_or_null("Unit1") as Node3D
	if u0 != null:
		_cam_target = u0.global_position
	_ensure_shadow()
	# Stand the REAL Golden via the existing motion-check sandbox (grants the 5 units,
	# clears enemies, holds robot_t=1).
	if not GameState.motion_debug:
		var fm := _formation()
		if fm != null:
			fm.call("_toggle_motion_debug")
	var fm2 := _formation()
	if fm2 != null and fm2.has_method("force_golden_walk_ready"):
		fm2.call("force_golden_walk_ready")

func _disable() -> void:
	_on = false
	GameState.apply_mouse_mode()
	GameState.golden_walk = false
	GameState.golden_airplane_hold = false
	GameState.golden_jump_offset = 0.0
	GameState.golden_gait = 0.0
	GameState.golden_gait_amp = 0.0
	GameState.golden_arena_scroll = Vector2.ZERO
	GameState.golden_walk_facing_deg = 0.0
	GameState.golden_camera_zoom = 0.0
	_walk_vel = Vector2.ZERO
	if _cam_valid:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			cam.global_transform = _cam_saved   # hand the camera back to Unit1
		_cam_valid = false
	if _shadow != null and is_instance_valid(_shadow):
		_shadow.queue_free()
	_shadow = null
	if GameState.motion_debug:
		var fm := _formation()
		if fm != null:
			fm.call("_toggle_motion_debug")   # drop motion_debug → Golden folds back down
	if _started_debug_arena:
		var main := get_parent()
		if main != null and main.has_method("debug_exit_golden_arena"):
			main.call_deferred("debug_exit_golden_arena")
		_started_debug_arena = false

func _formation() -> Node:
	var direct := get_parent().get_node_or_null("FormationManager")
	if direct != null:
		return direct
	for c in get_parent().get_children():
		if c.has_method("_toggle_motion_debug"):
			return c
	return null

func _process(_delta: float) -> void:
	if not _on:
		return
	# Movement: in the boss arena it flies/walks freely; elsewhere it's the open
	# free-walk (cursor steers px/py, visual hop).
	# Arena altitude is pinned to the floor band — GERWALK and fighter both skim the ground at
	# this one height, so the transform carries no vertical movement (and the legs sit on the floor).
	if GameState.arena_active:
		GameState.alt = ARENA_WALK_ALT
		GameState.tAlt = GameState.alt

	# Confronting the survivor: the Golden halts and holds its fire — it just stands and listens
	# (the camera still follows/zooms below). Skip all walking and shooting.
	var frozen := GameState.survivor_monologue_active
	if frozen:
		_walk_vel = Vector2.ZERO
		_vy = 0.0

	var moved := 0.0
	if frozen:
		moved = 0.0
	elif GameState.arena_active:
		moved = _arena_airplane() if GameState.golden_airplane_hold else _arena_walk()
	else:
		moved = _free_walk()
	_jump_edge = false

	# GERWALK fires forward along its facing to blast the diamond blocks apart (hunt for key items).
	if not frozen and GameState.arena_active and not GameState.golden_airplane_hold:
		_gw_shoot_timer += 1
		if _gw_shoot_timer >= GW_SHOOT_INTERVAL:
			_gw_shoot_timer = 0
			_gerwalk_fire()

	# Walk cycle driven by ACTUAL travel; amplitude fades to 0 when stopped (idle = stand still).
	var amp_target := 0.0 if GameState.golden_airplane_hold else clampf(moved / SPEED_REF, 0.0, 1.0)
	GameState.golden_gait_amp = lerpf(GameState.golden_gait_amp, amp_target, 0.2)
	GameState.golden_gait = fmod(GameState.golden_gait + moved * STRIDE, TAU)

	# The camera runs through _arena_camera_follow in BOTH arena modes, easing _arena_cam_xy each
	# frame. GERWALK chases the Golden; the FIGHTER eases toward a centred frame while the terrain
	# scrolls past. Because the cam position is always lerped from its CURRENT value, the transform
	# never snaps the view (that handoff was the jump). Free-walk keeps its orbit camera.
	if GameState.arena_active:
		_arena_camera_follow()
	elif not GameState.arena_active:
		_update_camera(_delta)
	_update_shadow()

func _ensure_shadow() -> void:
	if _shadow != null and is_instance_valid(_shadow):
		return
	var q := QuadMesh.new()
	q.size = Vector2(1.35, 0.82)
	_shadow = MeshInstance3D.new()
	_shadow.name = "GoldenBlobShadow"
	_shadow.mesh = q
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/blob_shadow.gdshader")
	mat.set_shader_parameter("strength", 0.18)
	mat.set_shader_parameter("shadow_color", Vector3(0.0, 0.0, 0.018))
	_shadow.material_override = mat
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(_shadow)

func _update_shadow() -> void:
	if not (_on and GameState.golden_walk and GameState.arena_active \
			and not GameState.golden_airplane_hold):
		if _shadow != null and is_instance_valid(_shadow):
			_shadow.visible = false
		return
	_ensure_shadow()
	if _shadow == null:
		return
	_shadow.visible = true
	_shadow.global_position = Vector3(GameState.px + 0.04, GameState.py - 0.06,
		GameState.alt_to_z(ARENA_WALK_ALT) - 0.08)
	_shadow.rotation = Vector3.ZERO
	var amp := clampf(GameState.golden_gait_amp, 0.0, 1.0)
	_shadow.scale = Vector3(1.0 + amp * 0.08, 1.0 - amp * 0.04, 1.0)

# Open free-walk: cursor steers px/py on the Golden's plane; quick tap = a visual hop.
# Returns the distance travelled (for the gait).
func _free_walk() -> float:
	var prev := Vector2(GameState.px, GameState.py)
	var cam := get_viewport().get_camera_3d()
	if cam != null and not GameState.golden_airplane_hold:
		var mp := get_viewport().get_mouse_position()
		var pz := GameState.alt_to_z(GameState.alt)
		var hit: Variant = Plane(Vector3(0.0, 0.0, 1.0), pz).intersects_ray(
			cam.project_ray_origin(mp), cam.project_ray_normal(mp))
		if hit != null:
			var tgt := Vector2((hit as Vector3).x, (hit as Vector3).y)
			var nxt := prev.move_toward(tgt, WALK_SPEED)
			GameState.px = clampf(nxt.x, -GameState.ARENA_HALF_W, GameState.ARENA_HALF_W)
			GameState.py = nxt.y
	if _jump_edge and _jump_frame >= JUMP_FRAMES:
		_jump_frame = 0
	if _jump_frame < JUMP_FRAMES:
		_jump_frame += 1
		GameState.golden_jump_offset = sin(PI * float(_jump_frame) / float(JUMP_FRAMES)) * JUMP_HEIGHT
	else:
		GameState.golden_jump_offset = 0.0
	return prev.distance_to(Vector2(GameState.px, GameState.py))

# Arena floor-walk: cursor steers px/py across the old cave arena's lowest band.
# Depth (alt) is pinned so the Golden reads as walking on the bottom layer, not flying.
# Returns floor distance travelled (drives the gait).
func _arena_walk() -> float:
	# (altitude is driven by robot_t in _process — symmetric fold/unfold, no jump)
	var z := GameState.alt_to_z(GameState.alt)
	var terr := get_tree().get_first_node_in_group("planet_terrain")
	var prev := Vector2(GameState.px, GameState.py)

	# VIRTUAL JOYSTICK: steer by the cursor's offset from the SCREEN CENTRE — a DIRECTION, not an
	# absolute world point. Pushing the cursor off-centre walks that way at full speed and never
	# "runs out" at a screen edge; bring the cursor back to the centre (the marker) to stop. This
	# replaces the old walk-to-the-projected-point model that pinned the cursor against the edges.
	var sz := get_viewport().get_visible_rect().size
	var off := get_viewport().get_mouse_position() - sz * 0.5
	if off.length() > JOY_DEADZONE_PX:
		# Screen-Y is down; world-Y is up — flip it so "cursor above centre" walks forward.
		var dir := Vector2(off.x, -off.y).normalized()
		_walk_vel = _walk_vel.lerp(dir * GERWALK_SPEED, WALK_ACCEL)
	else:
		_walk_vel = _walk_vel.lerp(Vector2.ZERO, WALK_ACCEL)
	if _walk_vel.length() < 0.0008:
		_walk_vel = Vector2.ZERO
	# Slide axis-by-axis so a pillar stops you on one axis without freezing the other.
	var nx := clampf(prev.x + _walk_vel.x, -GameState.ARENA_HALF_W, GameState.ARENA_HALF_W)
	var ny := clampf(prev.y + _walk_vel.y, -ARENA_Y_LIMIT, ARENA_Y_LIMIT)
	# Blocked on an axis? Don't stick — SMASH the block you walked into (it clears, so you grind
	# through next frame). The flank cave walls survive (blast spares them), so they still bound you.
	if not (terr != null and terr.collides(nx, GameState.py, z, ARENA_RAD)):
		GameState.px = nx
	else:
		_ram_break(terr, nx, GameState.py, z)
	if not (terr != null and terr.collides(GameState.px, ny, z, ARENA_RAD)):
		GameState.py = ny
	else:
		_ram_break(terr, GameState.px, ny, z)
	var after := Vector2(GameState.px, GameState.py)

	GameState.golden_arena_scroll = Vector2.ZERO

	# Tank-style facing eases toward travel (lerp_angle = smooth, 180° swings the short way).
	if _walk_vel.length() > 0.0008:
		var target_deg := rad_to_deg(atan2(_walk_vel.y, _walk_vel.x)) - 90.0
		GameState.golden_walk_facing_deg = rad_to_deg(lerp_angle(
			deg_to_rad(GameState.golden_walk_facing_deg), deg_to_rad(target_deg), TURN_RATE))

	GameState.golden_jump_offset = 0.0
	return prev.distance_to(after)

# Body-check: if a solid block sits at (x,y), smash it (ramming through, not sticking on it).
# Spares the flank cave walls (blast leaves is_arena_wall columns). Drops + score come from blast.
func _ram_break(terr: Node, x: float, y: float, z: float) -> void:
	if terr == null or not terr.has_method("collides") or not terr.has_method("blast"):
		return
	if not terr.collides(x, y, z, ARENA_RAD):
		return
	var drops: Array = terr.blast(Vector3(x, y, z), RAM_RADIUS)
	if (GameState.frame % 5) == 0:
		TsgAudio.arena_block_break()
	for drop: Dictionary in drops:
		ResourceItem.spawn(get_tree().current_scene, drop)

## GERWALK forward shots: terrain-busting bolts from Unit4's TWO cannon muzzles, along the facing.
func _gerwalk_fire() -> void:
	var u1 := get_parent().get_node_or_null("Unit1")
	if u1 == null:
		return
	var bs: Variant = u1.get("bullet_scene")
	if bs == null:
		return
	if get_tree().get_nodes_in_group("bullets").size() >= 52:
		return
	# Facing 0° = nose toward +Y; rotate that unit forward vector by the heading.
	var facing_rad := deg_to_rad(GameState.golden_walk_facing_deg)
	var dir := Vector2(-sin(facing_rad), cos(facing_rad))
	var vel := Vector3(dir.x, dir.y, 0.0) * GW_BULLET_SPEED
	# Muzzle world positions: Unit4's two cannon glows (fall back to Unit1's nose if missing).
	var muzzles: Array[Vector3] = []
	var u4 := get_parent().get_node_or_null("Unit4")
	if u4 != null:
		var ml := u4.get_node_or_null("left_cannon_group/left_muzzle_glow") as Node3D
		var mr := u4.get_node_or_null("right_cannon_group/right_muzzle_glow") as Node3D
		if ml != null:
			muzzles.append(ml.global_position)
		if mr != null:
			muzzles.append(mr.global_position)
	if muzzles.is_empty():
		muzzles.append((u1 as Node3D).global_position)
	for mp in muzzles:
		var b: Variant = bs.instantiate()
		b.color = Color(1.0, 0.86, 0.35)
		b.velocity = vel
		b.breaks_terrain = true
		b.base_scale = 0.95
		get_parent().add_child(b)
		b.global_position = mp + Vector3(dir.x, dir.y, 0.0) * 0.2
	TsgAudio.gerwalk_shot()

func _arena_airplane() -> float:
	# Flight form FLIES FORWARD through the same static world the GERWALK walks — the terrain does
	# NOT stream (the sealed wall + survivor sit at fixed world-y, so the ship has to actually
	# travel to reach them). A forced scroller flew in place forever past a looping dark cave (the
	# old "黒でループ"); instead a forward cruise advances py while the camera chases it (see
	# _arena_camera_follow). The hull RAMS forward and, when it's pressing into solid rock, grinds
	# ahead only slowly (ARENA_AIR_BORE) so boring the sealed wall has real dig HEFT — the same feel
	# the GERWALK has — instead of gliding through. (Altitude is driven by robot_t in _process.)
	GameState.golden_arena_scroll = Vector2.ZERO
	GameState.golden_walk_facing_deg = 0.0
	GameState.golden_jump_offset = 0.0
	var prev := Vector2(GameState.px, GameState.py)
	var z := GameState.alt_to_z(GameState.alt)
	var terr := get_tree().get_first_node_in_group("planet_terrain")
	# Cursor steers X toward the aimed point only — the forward cruise is a CONSTANT (a cursor-y
	# "surge" was tried but it fed the moving camera's ray-projection back into the speed and made
	# the view thrash; a fixed cruise can't oscillate).
	var nx := prev.x
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var mp := get_viewport().get_mouse_position()
		var hit: Variant = Plane(Vector3(0.0, 0.0, 1.0), z).intersects_ray(
			cam.project_ray_origin(mp), cam.project_ray_normal(mp))
		if hit != null:
			var hp := hit as Vector3
			nx = move_toward(prev.x,
				clampf(hp.x, -GameState.ARENA_HALF_W, GameState.ARENA_HALF_W), WALK_SPEED * 1.6)
	nx = clampf(nx, -GameState.ARENA_HALF_W, GameState.ARENA_HALF_W)
	# X stays bounded by the permanent flank walls (ram clears breakable blocks in the way; the
	# is_arena_wall columns survive blast and stop the ship).
	if terr == null or not terr.collides(nx, prev.y, z, ARENA_RAD):
		GameState.px = nx
	else:
		_ram_break(terr, nx, prev.y, z)
	# Forward: the hull bulldozes through (no permanent wall blocks forward), but when it's pressing
	# INTO solid rock it RAMS and grinds ahead only slowly — so boring the sealed wall has weight and
	# resistance, the same dig HEFT the GERWALK has, instead of gliding straight through. Open air =
	# full cruise. The bore carves a ship-level tunnel exactly the way the GERWALK does.
	var boring: bool = terr != null and terr.collides(GameState.px, prev.y + ARENA_RAD, z, ARENA_RAD)
	if boring:
		_ram_break(terr, GameState.px, prev.y + ARENA_RAD, z)
		GameState.py = prev.y + ARENA_AIR_BORE
	else:
		GameState.py = prev.y + ARENA_AIR_CRUISE
	return prev.distance_to(Vector2(GameState.px, GameState.py))

# Previous test mode kept for comparison: cursor controls X only, Y is a side-view
# floor line with a jump. It is useful for checking the raw leg cycle without free-floor
# camera/terrain motion. Toggle with F6 while F5 is active.
func _arena_side_walk() -> float:
	GameState.golden_arena_scroll = Vector2.ZERO
	GameState.alt = ARENA_WALK_ALT + 60.0
	GameState.tAlt = GameState.alt
	var z := GameState.alt_to_z(GameState.alt)
	var terr := get_tree().get_first_node_in_group("planet_terrain")
	var prev_x := GameState.px
	var cam := get_viewport().get_camera_3d()
	var target_x := GameState.px
	if cam != null:
		var mp := get_viewport().get_mouse_position()
		var hit: Variant = Plane(Vector3(0.0, 0.0, 1.0), z).intersects_ray(
			cam.project_ray_origin(mp), cam.project_ray_normal(mp))
		if hit != null:
			target_x = (hit as Vector3).x
	var nx := clampf(move_toward(GameState.px, target_x, WALK_SPEED),
		-GameState.ARENA_HALF_W, GameState.ARENA_HALF_W)
	if not (terr != null and terr.collides(nx, GameState.py, z, ARENA_RAD)):
		GameState.px = nx
	if _jump_edge and _grounded:
		_vy = ARENA_JUMP_V
		_grounded = false
	_vy = maxf(_vy - ARENA_GRAV, -ARENA_MAX_FALL)
	var ny := GameState.py + _vy
	_grounded = false
	if terr != null and _vy <= 0.0 and terr.collides(GameState.px, ny - ARENA_FOOT, z, ARENA_RAD):
		var guard := 0
		while terr.collides(GameState.px, ny - ARENA_FOOT, z, ARENA_RAD) and guard < 50:
			ny += 0.02
			guard += 1
		_vy = 0.0
		_grounded = true
	if ny <= ARENA_FLOOR_PY:
		ny = ARENA_FLOOR_PY
		_vy = 0.0
		_grounded = true
	GameState.py = ny
	GameState.golden_jump_offset = 0.0
	return absf(GameState.px - prev_x)

# Arena top-down: chase the Golden so the view scrolls up/down/left/right as it roams (the
# deck-pilot feel). Only X/Y are taken over here — Z (the alt-driven height) and the straight-
# down rotation stay with Unit1. Clamped so the scroll never runs off the play area. Runs after
# Unit1 (priority 100) so this wins each frame; the camera is restored on exit.
func _arena_camera_follow() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# The camera follows the Golden in X and Y in BOTH modes (deck-pilot feel), eased from its
	# CURRENT value, so the fold/unfold transform never moves the view (no "camera lurch"). The
	# fighter still reads as a scroller because the terrain streams past via golden_arena_scroll.
	# Keep a small, CONSTANT upward bias so the Golden sits just below screen centre — room to
	# push the cursor further up without it pinning to the top edge. A velocity-based lead was
	# tried but it fed back through the cursor projection and swung the ship wildly; a fixed bias
	# is stable (it shifts the frame, never amplifies motion).
	var cam_lim_x := minf(ARENA_CAM_LIMIT_X, GameState.ARENA_HALF_W)
	# Both modes chase the Golden in X and Y now: the flight form flies FORWARD through the static
	# world (advancing py), so the camera must follow it to keep it framed — exactly the same framing
	# as the walk (same lead), so the fighter sits at the GERWALK screen position, not lower.
	var tgt := Vector2(
		clampf(GameState.px, -cam_lim_x, cam_lim_x),
		GameState.py + ARENA_CAM_LEAD)
	_arena_cam_xy = _arena_cam_xy.lerp(tgt, ARENA_CAM_FOLLOW)
	cam.global_position.x = _arena_cam_xy.x
	cam.global_position.y = _arena_cam_xy.y
	cam.rotation = cam.rotation.lerp(Vector3.ZERO, 0.2)

# Free-walk camera: orbit (Q/E) around the walking Golden and frame it, scaled to its size.
# Runs after Unit1 (process_priority 100) so this view wins each frame; restored on exit.
func _update_camera(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var u := get_parent().get_node_or_null("Unit1") as Node3D
	if cam == null or u == null:
		return
	if Input.is_key_pressed(KEY_Q):
		_cam_orbit -= 1.5 * delta
	if Input.is_key_pressed(KEY_E):
		_cam_orbit += 1.5 * delta
	# LAZY follow: the look-point trails the Golden, so as it walks it leads in the frame
	# (you see the travel) and re-centres when you stop — and Q/E orbit reads cleanly because
	# the target isn't glued to every step.
	_cam_target = _cam_target.lerp(u.global_position, 0.06)
	var s: float = maxf(u.scale.x, 0.0001)
	var dist := s * CAM_K_DIST
	var h := s * CAM_K_HEIGHT
	cam.global_position = _cam_target + Vector3(sin(_cam_orbit) * dist, h, cos(_cam_orbit) * dist)
	cam.look_at(_cam_target + Vector3(0.0, h * 0.45, 0.0), Vector3.UP)
