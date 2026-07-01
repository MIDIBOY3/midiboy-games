extends Node3D

@onready var _nose_tip: MeshInstance3D = $body/nose_tip
@onready var _nose_mid: MeshInstance3D = $body/nose_mid
@onready var _nose_lower: MeshInstance3D = $body/nose_lower
@onready var _left_wing_pivot:    Node3D = $left_wing_pivot
@onready var _right_wing_pivot:   Node3D = $right_wing_pivot
@onready var _left_wing_outer:    Node3D = $left_wing_pivot/left_wing_outer
@onready var _right_wing_outer:   Node3D = $right_wing_pivot/right_wing_outer
@onready var _left_engine_group:  Node3D = $left_engine_group
@onready var _right_engine_group: Node3D = $right_engine_group
@onready var _left_engine:  Node3D = $left_engine_group/left_engine
@onready var _right_engine: Node3D = $right_engine_group/right_engine
@onready var _left_arm:  Node3D = $left_arm
@onready var _right_arm: Node3D = $right_arm
@onready var _left_missile:  MeshInstance3D = $left_engine_group/left_missile
@onready var _right_missile: MeshInstance3D = $right_engine_group/right_missile
@onready var _body:  Node3D = $body
@onready var _body_main: MeshInstance3D = $body/body_main   # chest/torso — thickened in F5 only
@onready var _left_nozzle:  MeshInstance3D = $left_engine_group/left_nozzle
@onready var _right_nozzle:  MeshInstance3D = $right_engine_group/right_nozzle
@onready var _robot_crest:     MeshInstance3D = $body/robot_crest
@onready var _robot_eye_left:  MeshInstance3D = $body/robot_eye_left
@onready var _robot_eye_right: MeshInstance3D = $body/robot_eye_right
@onready var _helmet_core:     MeshInstance3D = $body/helmet_core
@onready var _helmet_left:     MeshInstance3D = $body/helmet_left
@onready var _helmet_right:    MeshInstance3D = $body/helmet_right

@export var bullet_scene: PackedScene

var wide_mode: bool = false
var wide_t: float = 0.0
var shoot_enabled: bool = true
var shoot_timer: int = 0
var alt_velocity: float = 0.0
var _alt_armed: bool = true  # gates screen-edge climb/dive input after a deck leave
const TOPDOWN_PITCH := 76.0 # F5 top-down: lean off vertical so the chest/front shows (volume)
const TOPDOWN_CHEST := Vector3(1.875, 1.0, 1.5)  # F5-only chest scale (wider X + deeper Z)
var robot_t: float = 0.0
var _pitch: float = 0.0     # smoothed stand-up pitch, kept as a CLEAN scalar (not read back
							# off the basis — see the top-down robot orientation below)
var _cam_dist: float = 4.0  # camera closes in while riding the mothership deck
var _rb_melee: int = 0      # Golden melee swing timer
var _rb_laser: int = 0      # Golden shoulder-laser timer
var _rb_rocket: int = 0     # Golden omega-rocket timer
var _rb_side: int = 1       # alternates punch(+)/kick(-) and L/R shoulder
var _rb_aura: int = 0       # Golden aura pulse timer
var _aura_vt: int = 0       # aura visual-burst counter (dims/spaces the flashy ring)
const GOLDEN_AURA_RADIUS := 2.0   # world units (×scale) the aura vaporizes within
var _sphere_view_smooth: float = 0.0
var _sphere_yaw_input: float = 0.0
var _active_ground_bomb: GroundBomb = null
var _ground_bomb_cd: int = 0
var _terrain_atk_cd: int = 0   # dive/pull-up terrain-attack cooldown

# Dive-attack: a hard nose-dive or pull-up (|alt_velocity| past this, of a max
# 1.2) craters the terrain it's plunging into — space mega-continents AND planet
# surfaces. Gentle altitude drift never triggers it. Radius widens with the
# mothership DURABILITY upgrade ("TERRAIN ATTACK WIDENED").
const TERRAIN_ATK_VEL := 0.5
const TERRAIN_ATK_RADIUS := 0.42
const TERRAIN_ATK_CD := 22

func set_robot(p_robot_t: float) -> void:
	robot_t = clamp(p_robot_t, 0.0, 1.0)

func _input(event: InputEvent) -> void:
	# ZAKO prototype: the HERO uses the shared WASD/wheel scheme (Main + _proto_process);
	# skip ALL the GENESIS mouse/wheel/keyboard handling here (e.g. KEY_S would clash with
	# 'S' = move down, and the wheel is now altitude in Main).
	if GameState.is_zako_prototype_mode():
		return
	if GameState.should_autopilot_hero_unit():
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				# The click belongs to the star-target sight: no wide-shot misfire.
				if GameState.reticle_hover or GameState.in_transition():
					return
				# Riding the deck: a click disembarks the pilots (DeckWalkMode),
				# so don't also toggle wide-shot here.
				if GameState.on_carrier or GameState.deck_walk:
					return
				if robot_t < 0.5 and GameState.formation_count == 1:
					wide_mode = !wide_mode
					GameState.wide_shot = wide_mode
			MOUSE_BUTTON_WHEEL_UP:
				alt_velocity += 0.6
			MOUSE_BUTTON_WHEEL_DOWN:
				alt_velocity -= 0.6
	# macOS trackpads deliver two-finger scroll as a pan gesture, NOT mouse-wheel
	# button events, so the wheel-based climb/dive above never fires on a laptop.
	# Feed the pan's vertical delta into the same altitude impulse. delta.y and the
	# wheel come from the same OS scroll delta (delta.y < 0 == wheel up), so this
	# climbs/dives in the same direction the wheel does. macOS pan deltas are TINY
	# (engine bug godot#72242), so the per-event gain is large; the clamp still
	# keeps a long continuous scroll from running the velocity away.
	if event is InputEventPanGesture:
		alt_velocity = clampf(alt_velocity - event.delta.y * 0.6, -1.2, 1.2)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_S:
			shoot_enabled = !shoot_enabled
	if event is InputEventMouseMotion and GameState.stage == "planet":
		_sphere_yaw_input += event.relative.x

# Runs in _process (not _physics_process) so the player, camera and every other
# frame-driven object (enemies/bullets/formation) update on the same tick —
# avoids 60Hz-physics vs render-frame judder on high-refresh displays.
const PROTO_SPEED := 0.05
const PROTO_SHIP_SCALE := 0.5   # HERO size at the reference camera depth (constant on-screen)

# ZAKO prototype HERO controller: bypass ALL the GENESIS ship logic (mouse steering, its own
# camera control, altitude-by-screen-edge, mothership autopilot, sphere view…). The HERO is a
# simple WASD world-coord actor; the camera is owned by Main (_update_faction_camera). This is
# the "disable TSG position/camera anchoring in prototype mode" the design/input brief calls for.
const HERO_AUTOPILOT_SPEED := 0.03
const HERO_AUTOPILOT_WEAVE := 1.2
const HERO_FRAME_HALF := 1.7   # how far up/down the HERO can steer within the auto-scroll frame
var _hero_screen_y := -0.8     # HERO's on-screen Y offset from cam_y (steered by the player)
var _was_zako := false         # was in ZAKO last frame → resync the screen offset on return

func _proto_process() -> void:
	# The player pilots the ACTIVE actor. In ZAKO mode the HERO is NON-active but still moves
	# under AUTOPILOT — it keeps advancing FORWARD (+Y) through the shared world, TOWARD the
	# ZAKO deployed ~10 screens ahead, so the two genuinely converge (not a mere screen flip).
	# Full Vector2 assignment (don't mutate .x/.y through the autoload).
	if GameState.is_zako_mode():
		_was_zako = true
		var t := float(GameState.frame) * 0.02
		var hp := GameState.hero_pos
		hp.x = lerpf(hp.x, sin(t) * HERO_AUTOPILOT_WEAVE, 0.04)
		hp.y += HERO_AUTOPILOT_SPEED
		GameState.hero_pos = hp
	else:
		# HERO = forced auto-scroll: the camera advances on its own (Main). The player steers a
		# SCREEN OFFSET (_hero_screen_y = hero's position relative to cam_y). hero_pos.y is
		# cam_y + offset, so the ship keeps its on-screen spot as the world scrolls — no spring
		# back to the edge when you release (the earlier world-position clamp caused that).
		if _was_zako:
			_hero_screen_y = clampf(GameState.hero_pos.y - GameState.cam_y, -HERO_FRAME_HALF, HERO_FRAME_HALF)
			_was_zako = false
		var mv := Vector2(
			Input.get_action_strength("mv_right") - Input.get_action_strength("mv_left"),
			Input.get_action_strength("mv_up") - Input.get_action_strength("mv_down"))
		if mv.length() > 1.0:
			mv = mv.normalized()
		var spd := PROTO_SPEED * GameState.move_speed_mult()
		var hx := clampf(GameState.hero_pos.x + mv.x * spd, -GameState.PLAYFIELD_HALF_W, GameState.PLAYFIELD_HALF_W)
		_hero_screen_y = clampf(_hero_screen_y + mv.y * spd, -HERO_FRAME_HALF, HERO_FRAME_HALF)
		GameState.hero_pos = Vector2(hx, GameState.cam_y + _hero_screen_y)
	# Altitude = world DEPTH (z). The HERO sits at alt_z(hero_alt). When it's the SELF the camera
	# rides above it (constant size); when it's the ZAKO's opponent, a HIGHER HERO is nearer the
	# camera → looks BIGGER (altitude gap is readable). Scale is FIXED.
	global_position = Vector3(GameState.hero_pos.x, GameState.hero_pos.y, GameState.alt_z(GameState.hero_alt))
	rotation = Vector3.ZERO   # faces +Y; the ZAKO's 180° faction view shows it bearing down
	scale = Vector3(PROTO_SHIP_SCALE, PROTO_SHIP_SCALE, PROTO_SHIP_SCALE)
	# HERO fires straight forward only while player-piloted (spec: fixed-forward shot).
	if not GameState.is_zako_mode():
		_proto_fire()

const PROTO_FIRE_INTERVAL := 6
const PROTO_BULLET_SPEED := 0.11
var _proto_fire_cd := 0

func _proto_fire() -> void:
	if _proto_fire_cd > 0:
		_proto_fire_cd -= 1
	# □ / left-click, hold to autofire (spec). Forward-fixed, no aiming.
	if not Input.is_action_pressed("fire") or bullet_scene == null or _proto_fire_cd > 0:
		return
	_proto_fire_cd = PROTO_FIRE_INTERVAL
	var col := Color(0.667, 0.933, 1, 1)
	_fire(Vector3(0.0, 0.22 * scale.x, 0.0), Vector3(0.0, PROTO_BULLET_SPEED, 0.0), col)

func _process(_delta: float) -> void:
	if GameState.is_zako_prototype_mode():
		_proto_process()
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	_update_hole_sense()

	var mouse_pos := get_viewport().get_mouse_position()
	# Deck start after an arrival: snap the mouse onto the ship's spot at the
	# rear of the carrier runway, so control resumes right there.
	if GameState.deck_start:
		GameState.deck_start = false
		mouse_pos = camera.unproject_position(Vector3(GameState.px, GameState.py,
			GameState.alt_to_z(GameState.alt)))
		get_viewport().warp_mouse(mouse_pos)
	var sz        := get_viewport().get_visible_rect().size
	var sy        := mouse_pos.y / sz.y
	GameState.sy = sy
	var sphere_control := GameState.stage == "planet" \
		and get_tree().get_first_node_in_group("planet_terrain") is TargetPlanet

	# Mothership landing sequence: 1/3 = full autopilot (ship drives px/py/alt),
	# 2 = runway (mouse steering allowed, altitude locked by the ship).
	var ap := GameState.autopilot
	if GameState.entry_intro > 0:
		# Entry intro: forced descent from the atmosphere top toward cruising
		# altitude while the ship shrinks down from screen-filling size.
		GameState.entry_intro -= 1
		var it := float(GameState.entry_intro) / float(GameState.ENTRY_INTRO_FRAMES)
		GameState.tAlt = lerpf(GameState.PLANET_SURFACE_ALT + 42.0,
			GameState.GROUND_ALT - 4.0, it)
		GameState.alt = GameState.tAlt
		alt_velocity = 0.0
	elif ap == 0 and not GameState.on_carrier and not GameState.in_transition() \
			and not GameState.arrive_lock and not GameState.carrier_battle \
			and not GameState.ending_cinematic and not GameState.golden_walk \
			and not GameState.title_active and not GameState.intro_active:
		# golden_walk excluded: GoldenWalkCtl owns altitude in the arena (it drives a fixed
		# walk/airplane band via robot_t). Letting the screen-edge climb/dive also write alt
		# here fought that each frame and made the airplane↔golden transform jump.
		if not _alt_armed:
			# Just left the deck: FREEZE altitude entirely — no climb or dive
			# motion at all — so the ship departs straight and never sinks into
			# the carrier hull. The screen-edge climb/dive input only re-arms
			# once the cursor returns to the neutral middle band.
			alt_velocity = 0.0
			if sy > 0.25 and sy < 0.75:
				_alt_armed = true
		else:
			alt_velocity *= 0.92
			if absf(alt_velocity) < 0.0008:
				alt_velocity = 0.0   # settle exactly so altitude→camera.z stops creeping
			_apply_altitude(alt_velocity)
	elif GameState.on_carrier:
		# Riding the deck disarms altitude input, so the hand-back on leaving
		# always waits for a neutral cursor (see the branch above).
		_alt_armed = false
	var alt_t: float = GameState.sky_t()   # 0 at/below crust … 1 at alt1000 (size/zoom)
	var sphere_depth_t := 0.0
	if sphere_control:
		sphere_depth_t = clampf((GameState.GROUND_ALT - GameState.alt) \
			/ (GameState.GROUND_ALT - GameState.PLANET_SURFACE_ALT), 0.0, 1.0)
		alt_t = 0.0
	var player_z := GameState.alt_to_z(GameState.alt)
	if GameState.active_actor == GameState.SIDE_HERO:
		GameState.update_active_actor_world_y(GameState.py)
	# Deck-skim zoom: the camera moves in close while on the carrier, making
	# the huge deck loom; it eases back out on release so the carrier reads
	# at its normal size as it passes by.
	var cam_dist_target: float = 2.4 if GameState.on_carrier else 4.0
	if GameState.arena_active:
		cam_dist_target = 5.0   # slight pull-back to frame the floor + pillars (TUNE LIVE)
		if GameState.golden_walk:
			cam_dist_target = lerpf(3.2, 2.2, GameState.golden_camera_zoom)   # close in on the GERWALK
	_cam_dist = lerpf(_cam_dist, cam_dist_target, 0.06)
	if absf(_cam_dist - cam_dist_target) < 0.0015:
		_cam_dist = cam_dist_target   # settle exactly so the camera stops creeping (kills at-rest z-fight)
	var target_planet := get_tree().get_first_node_in_group("target_planet") as TargetPlanet
	var sphere_target := 0.0
	_sphere_view_smooth = sphere_target
	var sphere_view := _sphere_view_smooth
	var top_cam := Vector3(camera.global_position.x, 0.0, player_z + _cam_dist)
	var rear_cam := top_cam
	var cam_goal := top_cam.lerp(rear_cam, sphere_view)
	var cam_follow := 0.036
	camera.global_position.y = lerpf(camera.global_position.y, cam_goal.y, cam_follow)
	camera.global_position.z = lerpf(camera.global_position.z, cam_goal.z, cam_follow)
	# Planet surfaces and abysses are wider than the screen: the camera pans
	# with the player (clamped), giving the stage a horizontal scroll band.
	# In space we normally hold center (so the star reticle aims true), but
	# while riding a carrier the deck is wider than the screen — pan there too,
	# or the outer express lanes (and the units waiting on them) stay out of
	# reach off the screen edges.
	var cam_x := 0.0
	# Boss arena: a GENTLE pan (boss stays mostly centred but the view follows a little);
	# elsewhere pan with the player as before.
	if GameState.arena_active:
		cam_x = GameState.px * 0.25
	elif GameState.stage != "space" or GameState.on_carrier:
		cam_x = camera.global_position.x if sphere_control else GameState.px * 0.55
	cam_x = lerpf(cam_x, cam_goal.x, sphere_view)
	camera.global_position.x = lerpf(camera.global_position.x, cam_x, 0.05)
	if absf(camera.global_position.x - cam_x) < 0.0008:
		camera.global_position.x = cam_x   # settle exactly (no sideways creep)
	if sphere_view > 0.001:
		# Third-person rear view without world spin. Compute the target look
		# rotation, then restore and ease toward it so ALT900 never snaps.
		var cam_ship_y := GameState.py
		var look := Vector3(camera.global_position.x, cam_ship_y + 1.70,
			player_z - 0.55)
		var current_rot := camera.rotation
		camera.look_at(look, Vector3.UP)
		var target_rot := camera.rotation
		camera.rotation = current_rot
		var rot_follow := lerpf(0.010, 0.045, sphere_view)
		camera.rotation.x = lerp_angle(camera.rotation.x, target_rot.x, rot_follow)
		camera.rotation.y = lerp_angle(camera.rotation.y, 0.0, rot_follow)
		camera.rotation.z = lerp_angle(camera.rotation.z, 0.0, rot_follow)
	else:
		var top_rot_follow := 0.16 if GameState.stage == "space" else 0.08
		camera.rotation.x = lerpf(camera.rotation.x, 0.0, top_rot_follow)
		camera.rotation.y = lerpf(camera.rotation.y, 0.0, top_rot_follow)
		camera.rotation.z = lerpf(camera.rotation.z, 0.0, top_rot_follow)

	if GameState.in_transition() or GameState.arrive_lock:
		# Atmosphere transition / arrival: controls locked. When a carrier
		# flies it, it OWNS px/py (the ship is rigidly bolted to its deck);
		# otherwise (abyss climb-out) ease toward screen center.
		GameState.vx = lerpf(GameState.vx, 0.0, 0.1)
		GameState.vy = lerpf(GameState.vy, 0.0, 0.1)
		if GameState.boost_ship == null or not is_instance_valid(GameState.boost_ship):
			GameState.px = lerpf(GameState.px, 0.0, 0.04)
			GameState.py = lerpf(GameState.py, -0.5 if GameState.star_entry else 0.6, 0.03)
	elif GameState.should_autopilot_hero_unit() and _can_run_hero_unit_autopilot(ap):
		_run_hero_unit_autopilot(_delta)
	elif (ap == 0 or ap == 2) and not GameState.ending_cinematic \
			and not GameState.title_active and not GameState.intro_active:
		var world_pos := camera.project_position(mouse_pos, _cam_dist)
		var sphere_planet := get_tree().get_first_node_in_group("planet_terrain") as TargetPlanet
		if sphere_planet != null and GameState.stage == "planet":
			var edge_drive := clampf((mouse_pos.x / maxf(sz.x, 1.0) - 0.5) * 2.0, -1.0, 1.0)
			if sphere_planet.has_method("set_surface_yaw"):
				sphere_planet.call("set_surface_yaw", -edge_drive * 18.0)
			_sphere_yaw_input = 0.0
			# Lateral room widens toward the lowest layer (sphere_depth_t: 0 at
			# ALT760 → 1 at ALT560) so the cramped feeling near the surface eases;
			# the sphere still rolls with the same side input.
			var x_half := lerpf(2.65, 3.1, sphere_depth_t)
			world_pos.x = clampf(edge_drive * x_half, -x_half, x_half)
			world_pos.y = camera.project_position(Vector2(sz.x * 0.5, mouse_pos.y), _cam_dist).y
			GameState.underground = false
			GameState.over_hole = false
		else:
			_sphere_yaw_input = 0.0
			# Space-side horizontal control is the mouse projection; the planet
			# surface uses an edge-drive clamp. Ease space → surface mapping by
			# altitude (app_t: 0 high → 1 at ALT760) so px is continuous across the
			# stage flip. Gate ONLY on the star node existing — NOT on target_star:
			# target_star is cleared after the first entry, so gating on it left
			# EXIT (climb past ALT760) and RE-DESCENT with no blend → the ship
			# jumped sideways every time after the first descent. app_t weights the
			# lerp (0 = no-op high up) so this is a smooth no-op far from the star.
			if target_planet != null:
				var app_t := clampf((GameState.ALT_MAX - GameState.alt) \
					/ (GameState.ALT_MAX - GameState.GROUND_ALT), 0.0, 1.0)
				var ed := clampf((mouse_pos.x / maxf(sz.x, 1.0) - 0.5) * 2.0, -1.0, 1.0)
				world_pos.x = lerpf(world_pos.x, clampf(ed * 2.65, -2.65, 2.65), app_t)
				# Drive the star's longitude yaw from horizontal input in space too
				# (scaled by near_t inside _roll_sphere_surface) so it equals the
				# surface value at ALT760 — no yaw kick on entry/exit/re-entry.
				if target_planet.has_method("set_surface_yaw"):
					target_planet.call("set_surface_yaw", -ed * 18.0)
		# Terrain blocks are solid: no damage, but the ship can't pass through.
		# Stop at walls (sliding along whichever axis stays free); if the
		# scrolling ground catches the ship inside a block, climb out fast.
		# One continuous voxel terrain covers sky relief, crust, and underground.
		var terr := get_tree().get_first_node_in_group("planet_terrain")
		if terr != null and ap == 0 and not GameState.on_carrier:
			var rad: float = 0.08 * scale.x
			var nx := world_pos.x
			var ny := world_pos.y
			if terr.collides(nx, ny, player_z, rad):
				if not terr.collides(nx, GameState.py, player_z, rad):
					ny = GameState.py
				elif not terr.collides(GameState.px, ny, player_z, rad):
					nx = GameState.px
				else:
					nx = GameState.px
					ny = GameState.py
			# Caught by a wall the scroll is carrying: simply shoved along
			# with it — never auto-climb; climbing out is the player's call.
			if terr.collides(nx, ny, player_z, rad):
				ny = GameState.py
			world_pos.x = nx
			world_pos.y = ny
		# GERWALK / fighter arena: GoldenWalkCtl OWNS px/py (cursor-follow capped at GERWALK_SPEED /
		# the forced scroll). Writing the raw cursor projection here too would teleport the ship to
		# the cursor, so the speed cap never applied — "move speed ignores GERWALK_SPEED".
		var golden_arena := GameState.golden_walk and GameState.arena_active
		if not GameState.debug_pin_ship and not golden_arena:
			GameState.vx = lerpf(GameState.vx, world_pos.x - GameState.px, 0.25)
			GameState.vy = lerpf(GameState.vy, world_pos.y - GameState.py, 0.25)
			GameState.px = world_pos.x
			GameState.py = world_pos.y
		# Boss arena: keep the ship in the central band so it can't fly (or shoot)
		# out through the side walls and lose the boss off-screen.
		if GameState.arena_active:
			GameState.px = clampf(GameState.px, -GameState.ARENA_HALF_W, GameState.ARENA_HALF_W)
	else:
		GameState.vx = lerpf(GameState.vx, 0.0, 0.1)
		GameState.vy = lerpf(GameState.vy, 0.0, 0.1)
	var draw_y := GameState.py + GameState.golden_jump_offset   # walk-proto hop (0 normally)
	global_position = Vector3(GameState.px, draw_y + robot_t * 0.06, player_z)

	var s: float = lerp(0.5, 1.0, clampf(alt_t, 0.0, 1.0))  # underground (alt<0) holds min size
	# Atmosphere cinematics: entering, the ship starts huge near the camera
	# and shrinks down to the surface; leaving, it swells past the camera.
	var zoom_t := 0.0
	if GameState.entry_intro > 0:
		zoom_t = pow(float(GameState.entry_intro) / float(GameState.ENTRY_INTRO_FRAMES), 2.0)
	elif GameState.star_exit:
		zoom_t = GameState.exit_anim * GameState.exit_anim
	if zoom_t > 0.0:
		s *= 1.0 + 2.8 * zoom_t
		global_position.z += 1.9 * zoom_t
	# Riding a carrier through entry or an arrival cinematic: the ship's
	# size tracks the hull exactly (huge on the screen-filling descent,
	# small rising from below, settling to normal together).
	if (GameState.star_entry or GameState.arrive_lock) \
			and GameState.boost_ship != null \
			and is_instance_valid(GameState.boost_ship):
		s *= clampf((GameState.boost_ship as Node3D).scale.x, 0.2, 3.5)
	var sphere_depth_planet := get_tree().get_first_node_in_group("planet_terrain") as TargetPlanet
	if sphere_depth_planet != null and GameState.stage == "planet":
		s = lerpf(0.5, 0.72, smoothstep(0.0, 1.0, sphere_depth_t))
	scale = Vector3(s, s, s)

	# Final boss: the hero ship is parked on the battle carrier's deck (set by
	# Mothership._run_battle). Sit on the deck, scaled to the (shrinking) hull, and
	# stay visible — the player rides the carrier from here to the ending.
	if GameState.carrier_battle:
		global_position = GameState.carrier_dock_pos
		var ds: float = GameState.carrier_dock_scale * 0.85
		scale = Vector3(ds, ds, ds)
		visible = true

	var pitch_deg: float
	pitch_deg = clampf(alt_velocity * 45.0, -45.0, 45.0)
	if GameState.in_transition() or GameState.arrive_lock:
		# Carrier transitions/arrivals: the ship sits LEVEL on the deck — the
		# carrier does the diving/climbing. Only the carrier-less abyss climb pitches.
		if GameState.boost_ship != null and is_instance_valid(GameState.boost_ship):
			pitch_deg = 0.0
		elif GameState.star_exit:
			pitch_deg = 50.0
		else:
			pitch_deg = -50.0
	elif GameState.entry_intro > 0:
		pitch_deg = -45.0  # nose-down dive into an abyss pit
	# Robot: stand up to face the enemies ahead (+Y), keeping a slight backward lean.
	pitch_deg = lerpf(pitch_deg, 40.0, robot_t)
	# Top-down walk arena: lay the robot FLAT (pitch 90°) so its head points straight at the
	# overhead camera — you look down on the crown. Travel direction is a spin about the
	# camera axis (Z), so the crown stays put while the mech turns like a tank.
	# Stays true through the fighter too (matches FormationManager) so the body keeps the SAME
	# orientation path across the transform — no rotation/placement snap on fold-up.
	var topdown_walk := GameState.golden_walk and GameState.arena_active
	if topdown_walk:
		pitch_deg = lerpf(pitch_deg, TOPDOWN_PITCH, robot_t)
	# Chest depth/width grows with robot_t — so it eases in/out with the transform (NO pop when
	# folding to the fighter or unfolding back) and the fighter form is never thickened. Gated to
	# the F5 arena, so the normal in-flight ship and the golden aura robot keep their size.
	var chest_t: float = robot_t if (GameState.golden_walk and GameState.arena_active) else 0.0
	_body_main.scale = Vector3.ONE.lerp(TOPDOWN_CHEST, chest_t)
	# On the carrier deck the nose stays level (no pitch while taxiing / piloting it).
	if GameState.on_carrier or GameState.carrier_battle:
		pitch_deg = 0.0
	var pitch_t := 0.45 if absf(pitch_deg) >= absf(_pitch) else 0.03
	_pitch = lerpf(_pitch, pitch_deg, pitch_t)
	GameState.golden_robot_pitch_deg = _pitch   # clean source for the other units' parts
	if topdown_walk:
		# Compose Rz(facing) · Rx(pitch) EXPLICITLY (not via euler components): pitch first to
		# lay it flat, THEN spin about world Z. The euler-component path (Rx·Rz) swings the
		# crown off-camera as you turn — that was the "can't control it" bug. Bake scale in,
		# since assigning basis would otherwise reset it to 1.
		var facing_rad := deg_to_rad(GameState.golden_walk_facing_deg)
		var rb := Basis(Vector3(0.0, 0.0, 1.0), facing_rad) \
			* Basis(Vector3(1.0, 0.0, 0.0), deg_to_rad(_pitch))
		basis = rb.scaled(scale)
	else:
		rotation_degrees = Vector3(_pitch, 0.0, rotation_degrees.z)

	_update_robot_combat(player_z)
	_update_ground_bomb(player_z)
	_update_terrain_attack(player_z)

	if robot_t > 0.5 or GameState.formation_count > 1:
		wide_mode = false
		GameState.wide_shot = false
	wide_t = lerp(wide_t, 1.0 if wide_mode else 0.0, 0.08)

	# Wing fold: 90° folded at alt=0, flat at alt=99.
	# Robot mode: wings lock at 30° — shoulder-armor flare flanking the chest.
	var wing_fold_flight: float = lerpf(90.0, 52.0, smoothstep(0.0, 1.0, sphere_depth_t)) \
		if sphere_control else lerpf(90.0, 0.0, alt_t)
	var wing_fold        := lerpf(wing_fold_flight, 30.0, robot_t)

	# Wing inertia only — the screen-position raise/lower pose was removed (user:
	# the shoulder armor shouldn't swing up/down as the ship nears screen edges).
	var vx_c: float = clampf(GameState.vx, -0.03, 0.03)
	var wing_inertia: float = 0.0 if GameState.robot_static else vx_c * robot_t * 150.0  # ±4.5° max
	_left_wing_pivot.rotation_degrees  = Vector3(0, 0, lerp(wing_fold,  90.0, wide_t) + wing_inertia)
	_right_wing_pivot.rotation_degrees = Vector3(0, 0, lerp(-wing_fold, -90.0, wide_t) - wing_inertia)

	_left_wing_outer.position.x = lerp(-0.16, -0.12, wide_t)
	_right_wing_outer.position.x = lerp(0.16, 0.12, wide_t)

	var engine_bulge := sin(wide_t * PI) * 0.08

	_left_engine_group.position.x = lerp(-0.03, -0.18, wide_t)
	_right_engine_group.position.x = lerp(0.03, 0.18, wide_t)
	_left_engine_group.position.y  = lerp(-0.08, -0.03, wide_t) - engine_bulge
	_right_engine_group.position.y = lerp(-0.08, -0.03, wide_t) - engine_bulge

	_left_engine.scale.y  = lerp(3.0, 3.0, wide_t)
	_right_engine.scale.y = lerp(3.0, 3.0, wide_t)
	_left_engine.position.y  = lerp(0.03, 0.03, wide_t)
	_right_engine.position.y = lerp(0.03, 0.03, wide_t)

	_left_nozzle.position.y  = lerp(-0.07, -0.1, wide_t)
	_right_nozzle.position.y = lerp(-0.07, -0.1, wide_t)
	_left_nozzle.scale.y  = lerp(2.0, 3.0, wide_t)
	_right_nozzle.scale.y = lerp(2.0, 3.0, wide_t)

	var body_edge: float = -0.04
	var engine_x: float  = lerp(-0.03, -0.18, wide_t)
	var arm_len: float   = abs(engine_x - body_edge)
	var arm_cx: float    = (body_edge + engine_x) / 2.0
	_left_arm.position.x  = arm_cx
	_right_arm.position.x = -arm_cx
	_left_arm.position.y  = lerp(-0.05, -0.03, wide_t)
	_right_arm.position.y = lerp(-0.05, -0.03, wide_t)
	_left_arm.scale.x  = max(0.01, arm_len / 0.02)
	_right_arm.scale.x = max(0.01, arm_len / 0.02)

	_body.position.y = lerp(0.00, -0.12, wide_t)

	# Robot head: nose_tip drops as chin; nose_mid rises as face; crest and eyes emerge.
	var nose_down: float = robot_t * 0.025
	_nose_tip.position.y   = lerpf(0.225, 0.225, wide_t) - nose_down
	_nose_tip.scale.y      = lerpf(2.0, 2.0, wide_t)
	var nose_mid_y: float  = lerpf(0.185, 0.26, wide_t) + robot_t * 0.05
	_nose_mid.position.y   = nose_mid_y
	_nose_lower.position.y = 0.145

	# Red central crest: grows upward from the crown of the helmet (back of head).
	_robot_crest.position.y = nose_mid_y + robot_t * 0.08
	_robot_crest.scale.y    = robot_t

	# Helmet volume: back-of-head core + gold side pods (Combattler-style) grow in robot mode.
	var helm_y: float = nose_mid_y + robot_t * 0.025
	_helmet_core.position.y = helm_y
	_helmet_core.scale.y    = robot_t
	_helmet_left.position.y  = helm_y - 0.008
	_helmet_left.scale.y     = robot_t
	_helmet_right.position.y = helm_y - 0.008
	_helmet_right.scale.y    = robot_t

	# Yellow side fins: two fins rise alongside the central crest — rear helmet fin style.
	var fin_y: float = nose_mid_y + robot_t * 0.035
	_robot_eye_left.position  = Vector3(-0.036, fin_y, 0.012)
	_robot_eye_left.scale.y   = robot_t
	_robot_eye_right.position = Vector3( 0.036, fin_y, 0.012)
	_robot_eye_right.scale.y  = robot_t

	var missile_t: float = clamp((wide_t - 0.6) / 0.4, 0.0, 1.0)
	_left_missile.visible  = missile_t > 0.0
	_right_missile.visible = missile_t > 0.0
	_left_missile.scale.y  = missile_t
	_right_missile.scale.y = missile_t

	# GERWALK fires its own terrain-busting shots from GoldenWalkCtl (along its facing), so the
	# normal forward spray is suppressed there; the fighter still fires normally.
	var gerwalk_now := GameState.golden_walk and GameState.arena_active \
		and not GameState.golden_airplane_hold
	if shoot_enabled and bullet_scene != null and robot_t < 0.5 and not gerwalk_now \
			and not GameState.carrier_battle and not GameState.ending_cinematic \
			and not GameState.on_carrier \
			and not GameState.title_active and not GameState.intro_active \
			and not GameState.boss_intro_active \
			and GameState.god_phase == 0 \
			and not GameState.hubris_blocking_fire():   # 慢心MAX → the units won't fire
		shoot_timer += 1
		var lv := GameState.unit_level(1)
		var n_interval: int = 6 if lv <= 2 else (5 if lv <= 4 else 4)
		var w_interval: int = 3 if lv <= 4 else 2
		if not wide_mode:
			if shoot_timer >= n_interval:
				shoot_timer = 0
				_shoot()
		else:
			if shoot_timer >= w_interval:
				shoot_timer = 0
				_shoot()

# Underground descent has been retired. Keep the legacy flags pinned off so old
# terrain helpers cannot re-enable cave behavior.
const HOLE_R := 0.35
func _update_hole_sense() -> void:
	GameState.over_hole = false
	GameState.underground = false
	GameState.descent_gauge = 0.0

# Apply an altitude delta with the 2-layer rules: away from a hole the ground
# crust (alt GROUND_ALT) is a solid floor/ceiling; inside a hole the clamp opens
# down to the underground floor (alt0) so the ship sinks into / climbs out of the
# underground stratum.
func _apply_altitude(dv: float) -> void:
	var g := GameState.GROUND_ALT
	var proposed := GameState.tAlt + dv
	var surf := get_tree().get_first_node_in_group("planet_terrain")
	# Boss arena: the ship flies the cave vault, clamped BETWEEN the floor and a
	# ceiling kept under the crust — climbing can't punch out to the surface. (You
	# leave the arena only by beating the boss.)
	if GameState.arena_active:
		GameState.tAlt = clampf(proposed, GameState.ARENA_FLOOR_ALT, GameState.ARENA_CEIL_ALT)
		GameState.alt = GameState.tAlt
		return
	if GameState.stage == "planet" and surf is TargetPlanet:
		# Star play is the space shooter at low orbit: ALT760 is the floor.
		# There is no separate rear-view/surface-depth mode below it.
		if proposed > g + 1.0:
			GameState.tAlt = g
			GameState.alt = g
			surf.call("begin_exit")
			return
		GameState.tAlt = g
		GameState.alt = GameState.tAlt
		GameState.underground = false
		GameState.over_hole = false
		GameState.descent_gauge = 0.0
		return
	if GameState.stage == "planet":
		GameState.tAlt = clampf(proposed, GameState.PLANET_SURFACE_ALT, g)
	else:
		var target := get_tree().get_first_node_in_group("target_planet") as TargetPlanet
		if proposed < g and target != null and target.approach > 0.94 \
				and not GameState.in_transition() and not GameState.on_carrier:
			GameState.tAlt = g
			GameState.alt = g
			target.call("begin_entry", false)
			return
		GameState.tAlt = clampf(proposed, g, GameState.ALT_MAX)
	GameState.alt = GameState.tAlt
	GameState.underground = false
	GameState.over_hole = false
	GameState.descent_gauge = 0.0

func _update_ground_bomb(_player_z: float) -> void:
	# Disabled on star surfaces (user request): Unit1 no longer auto-drops the
	# ground bomb. Terrain is cracked open by the dive-attack instead.
	pass

# GOLDEN robot AURA — while the 10 s Golden state is active the robot channels an
# omni-directional aura: a pulsing gold shockwave that vaporizes every enemy around
# it into resources and brushes terrain aside. No aiming, no tiers — pure overwhelming
# power. (Invincibility + enemy-bullet burn are passive, handled in Main.)
func _update_robot_combat(player_z: float) -> void:
	# Decay the humanoid attack-pose envelopes every frame; the channel pose below
	# snaps the arms back up. The limb units (U3/U5) read these to animate.
	GameState.robot_punch       = maxf(0.0, GameState.robot_punch - 0.06)
	GameState.robot_kick        = maxf(0.0, GameState.robot_kick - 0.05)
	GameState.robot_laser_pose  = maxf(0.0, GameState.robot_laser_pose - 0.045)
	GameState.robot_rocket_pose = maxf(0.0, GameState.robot_rocket_pose - 0.03)
	if GameState.motion_debug:
		return  # sandbox: poses fire only from the manual Z/X/V/B keys
	if not GameState.golden_active:
		return
	if GameState.in_transition() or GameState.on_carrier \
			or GameState.arrive_lock or GameState.game_over:
		return
	# Brace the robot in a channel pose (arms raised) as the aura radiates.
	GameState.robot_laser_pose = 1.0
	_rb_aura += 1
	if _rb_aura >= 8:
		_rb_aura = 0
		_aura_pulse(player_z)

# One aura shockwave: vaporize every in-range enemy within AURA_RADIUS into resources,
# burst a big gold ring, and crack any terrain underneath for the 迫力.
func _aura_pulse(player_z: float) -> void:
	var s := scale.x
	var center := global_position
	var radius := GOLDEN_AURA_RADIUS * s
	_aura_vaporize(center, radius)
	TsgAudio.aura_pulse()   # flashy shockwave SFX
	# Toned-down so the ROBOT stays visible: no white core, a thinner gold shockwave spread
	# around the PERIMETER (centre kept clear), and only every other pulse so the bursts
	# don't pile into a blinding cloud. Gameplay (vaporize cadence) is unchanged.
	_aura_vt += 1
	if (_aura_vt % 2) == 0:
		var ring_n := 7
		for i in ring_n:
			var a := TAU * float(i) / float(ring_n) + float(_aura_vt) * 0.30
			var pex := Explosion.new()
			pex.color = Color(1.0, 0.82, 0.32)
			pex.count = 5
			pex.strength = 1.5
			get_parent().add_child(pex)
			pex.global_position = center + Vector3(cos(a) * radius * 0.92, sin(a) * radius * 0.92, 0.0)
	# Smash ground blocks under the aura. High damage so they actually BREAK (not just
	# chip), full radius, and NOT gated by stage — hit both the planet surface and any
	# space mega-continent so blocks shatter at every altitude the aura covers.
	var bp := Vector3(center.x, center.y, player_z)
	var terr := get_tree().get_first_node_in_group("planet_terrain")
	if terr != null and terr.has_method("blast"):
		_collect_drops(terr.blast(bp, radius, 99))
	var st := get_tree().get_first_node_in_group("space_structures")
	if st != null and st.has_method("blast"):
		_collect_drops(st.blast(bp, radius))

# Kill every in-range enemy within radius and turn each into a resource pickup.
func _aura_vaporize(center: Vector3, radius: float) -> void:
	var c2 := Vector2(center.x, center.y)
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Node3D
		if e == null or not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		# Golden aura ignores the altitude band — it vaporizes every enemy within
		# the 2D radius at ALL altitudes (blocks included), not just the player's band.
		if c2.distance_to(Vector2(e.global_position.x, e.global_position.y)) > radius:
			continue
		var hue_v: Variant = e.get("hue")
		var hue: float = float(hue_v) if hue_v != null else 200.0
		var mh: Variant = e.get("max_hp")
		var pos: Vector3 = e.global_position
		GameState.score += 100
		GameState.add_exp(40 * (int(mh) if mh != null else 1))
		var bex := Explosion.new()
		bex.color = Color.from_hsv(hue / 360.0, 0.7, 1.0)
		bex.count = 10
		bex.strength = 1.2
		get_parent().add_child(bex)
		bex.global_position = pos
		# Vaporized enemy → resource (ResourceItem caps/auto-banks commons itself).
		ResourceItem.spawn(get_parent(), {"res": "ENERGY",
			"color": Color.from_hsv(hue / 360.0, 0.6, 1.0), "pos": pos})
		e.queue_free()

# Alternating punch (high) / kick (low): a short-reach AoE off one fist that
# also cracks the terrain it drives into.
func _robot_melee(player_z: float) -> void:
	_rb_side = -_rb_side
	var s := scale.x
	var hi := _rb_side > 0
	# Drive the matching limb: high swing = a punch (arm), low swing = a kick (leg).
	if hi:
		GameState.robot_punch = 1.0
		GameState.robot_punch_side = _rb_side
	else:
		GameState.robot_kick = 1.0
		GameState.robot_kick_side = _rb_side
	var center := global_position + Vector3(_rb_side * 0.18 * s,
		(0.22 if hi else -0.04) * s, 0.0)
	_aoe_hit_enemies(center, 0.34 * s, 3, true)
	var ex := Explosion.new()
	ex.color = Color(1.0, 0.95, 0.7) if hi else Color(1.0, 0.8, 0.45)
	ex.count = 10
	ex.strength = 1.1
	get_parent().add_child(ex)
	ex.global_position = center
	if GameState.stage != "space":
		var terr := get_tree().get_first_node_in_group("planet_terrain")
		if terr != null:
			_collect_drops(terr.blast(Vector3(center.x, center.y, player_z), 0.32 * s))
	else:
		var sterr := get_tree().get_first_node_in_group("space_terrain")
		if sterr != null and sterr.has_method("blast"):
			_collect_drops(sterr.blast(Vector3(center.x, center.y, player_z), 0.32 * s))

# Pull U4's beam blades from both shoulders and hurl them forward — each pierces
# every same-band enemy along its flight (LaserBlade), sweeping the lane.
# Is any enemy within melee reach of the robot's body?
func _enemy_near(radius: float) -> bool:
	var p := Vector2(global_position.x, global_position.y)
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Node3D
		if e == null or not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		if p.distance_to(Vector2(e.global_position.x, e.global_position.y)) <= radius:
			return true
	return false

func _robot_shoulder_laser() -> void:
	GameState.robot_laser_pose = 1.0
	var s := scale.x
	for sgn: float in [-1.0, 1.0]:
		var blade := LaserBlade.new()
		blade.dir = Vector3(0.0, 1.0, 0.0)
		blade.speed = 0.13
		blade.blade_len = 1.2 * s
		blade.width = 0.09 * s
		blade.vis_scale = 1.4 * s
		get_parent().add_child(blade)
		blade.global_position = global_position + Vector3(sgn * 0.22 * s, 0.18 * s, 0.0)

# Omega rocket: a wide, hard blast centered on the nearest enemy ahead (or
# straight up if none) — big damage radius, and it craters the terrain.
func _robot_rocket(player_z: float) -> void:
	GameState.robot_rocket_pose = 1.0
	var s := scale.x
	var target := global_position + Vector3(0.0, 1.3 * s, 0.0)
	var near := _find_screen_enemies(1, false)
	if not near.is_empty():
		target = near[0].global_position
	target.z = global_position.z
	_aoe_hit_enemies(target, 0.7 * s, 5, false)
	var ex := Explosion.new()
	ex.color = Color(1.0, 0.6, 0.2)
	ex.count = 40
	ex.strength = 2.8
	get_parent().add_child(ex)
	ex.global_position = target
	if GameState.stage != "space":
		var terr := get_tree().get_first_node_in_group("planet_terrain")
		if terr != null:
			_collect_drops(terr.blast(Vector3(target.x, target.y, player_z), 0.6 * s))
	else:
		var sterr := get_tree().get_first_node_in_group("space_terrain")
		if sterr != null and sterr.has_method("blast"):
			_collect_drops(sterr.blast(Vector3(target.x, target.y, player_z), 0.6 * s))

# Damage every (in-range) enemy within radius — awards score/EXP and bursts each
# like a bullet kill. dmg is the number of hit-points dealt per enemy.
func _aoe_hit_enemies(center: Vector3, radius: float, dmg: int, in_range_only: bool) -> void:
	var c2 := Vector2(center.x, center.y)
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Node3D
		if e == null or not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		if in_range_only and e.has_method("is_in_player_range") \
				and not e.call("is_in_player_range"):
			continue
		if c2.distance_to(Vector2(e.global_position.x, e.global_position.y)) > radius:
			continue
		var hue: Variant = e.get("hue")
		var hit_pos: Vector3 = e.global_position
		for di in dmg:
			if e.has_method("take_hit") and e.call("take_hit", 1):
				GameState.score += 100
				var mh: Variant = e.get("max_hp")
				GameState.add_exp(40 * (int(mh) if mh != null else 1))
				var bex := Explosion.new()
				if hue != null:
					bex.color = Color.from_hsv(float(hue) / 360.0, 0.7, 1.0)
				get_parent().add_child(bex)
				bex.global_position = hit_pos
				break

# Dive-attack (revived): a hard nose-dive / pull-up plunges the ship into the
# terrain it is rushing toward and craters it. In space this carves the mega-
# continent (or any space terrain) it's diving through; on a planet it cracks the
# surface open like the old mothership-era attack. Only a deliberate hard input
# fires it — gentle altitude drift never does.
func _update_terrain_attack(player_z: float) -> void:
	if _terrain_atk_cd > 0:
		_terrain_atk_cd -= 1
		return
	if absf(alt_velocity) < TERRAIN_ATK_VEL:
		return
	if GameState.autopilot != 0 or GameState.on_carrier or GameState.in_transition() \
			or GameState.arrive_lock or robot_t > 0.5:
		return
	# On a planet only crater once actually down on the surface (below the crust),
	# never mid-air during the descent. In space the blast self-gates by z-depth.
	if GameState.stage != "space" and GameState.alt >= GameState.GROUND_ALT:
		return
	var radius := TERRAIN_ATK_RADIUS + 0.06 * float(GameState.dura_level)
	var center := Vector3(global_position.x, global_position.y, player_z)
	var group := "space_terrain" if GameState.stage == "space" else "planet_terrain"
	var terr := get_tree().get_first_node_in_group(group)
	if terr == null or not terr.has_method("blast"):
		return
	var drops: Array = terr.blast(center, radius)
	# blast() returns the rubble it knocked loose; if nothing was there (wrong
	# depth / open sky), don't burn the cooldown or flash an empty hit.
	if drops.is_empty():
		return
	_collect_drops(drops)
	var ex := Explosion.new()
	ex.color = Color(1.0, 0.85, 0.42)
	ex.count = 22
	ex.strength = 1.9
	get_parent().add_child(ex)
	ex.global_position = center
	TsgAudio.dive_smash()
	_terrain_atk_cd = TERRAIN_ATK_CD

# Spawn the magnet-pickup resource cubes a terrain blast knocked loose.
func _collect_drops(drops: Array) -> void:
	for drop: Dictionary in drops:
		ResourceItem.spawn(get_parent(), drop)

func _find_screen_enemies(max_count: int, rear_only: bool = false) -> Array[Node3D]:
	var camera := get_viewport().get_camera_3d()
	var sz := get_viewport().get_visible_rect().size
	var candidates: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Node3D
		if e == null or not is_instance_valid(e): continue
		if not e.has_method("is_in_player_range") or not e.call("is_in_player_range"): continue
		if rear_only and e.global_position.y >= global_position.y: continue
		if camera != null:
			var sp := camera.unproject_position(e.global_position)
			if sp.x < 0.0 or sp.x > sz.x or sp.y < 0.0 or sp.y > sz.y:
				continue
		candidates.append(e)
	var my_pos := global_position
	candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return my_pos.distance_to(a.global_position) < my_pos.distance_to(b.global_position))
	return candidates.slice(0, max_count)

func _fire(offset: Vector3, vel: Vector3, col: Color, homing: bool = false) -> void:
	if get_tree().get_nodes_in_group("bullets").size() >= 54:
		return
	var b := bullet_scene.instantiate()
	b.color = col
	b.velocity = vel
	b.homing = homing
	b.source_unit_id = 1
	b.base_scale = 0.8   # a touch smaller so the spray reads cleaner
	get_parent().add_child(b)
	b.global_position = global_position + offset
	TsgAudio.player_shot()

func _shoot() -> void:
	var lv  := GameState.unit_level(1)
	var s   := scale.x
	var spd: float = 0.08 if lv <= 2 else (0.10 if lv <= 4 else 0.12)

	if GameState.formation_count > 1:
		var col := Color(0.667, 0.933, 1, 1) if lv <= 2 else \
				   (Color(0.4, 0.85, 1, 1) if lv <= 4 else Color(1, 0.95, 0.4, 1))
		if GameState.sep_t > 0.5:
			# Formation: radial spread, grows by level
			match lv:
				1:
					_fire(Vector3(0, 0.22*s, 0), Vector3(           0,          spd, 0), col)
				2:
					_fire(Vector3(-0.04*s, 0.22*s, 0), Vector3(0, spd, 0), col)
					_fire(Vector3( 0.04*s, 0.22*s, 0), Vector3(0, spd, 0), col)
				3:
					_fire(Vector3(0, 0.22*s, 0), Vector3(           0,          spd, 0), col)
					_fire(Vector3(0, 0.22*s, 0), Vector3( 0.259 * spd, 0.966 * spd, 0), col)
					_fire(Vector3(0, 0.22*s, 0), Vector3(-0.259 * spd, 0.966 * spd, 0), col)
				4:
					_fire(Vector3(0, 0.22*s, 0), Vector3(           0,          spd, 0), col)
					_fire(Vector3(0, 0.22*s, 0), Vector3( 0.423 * spd, 0.906 * spd, 0), col)
					_fire(Vector3(0, 0.22*s, 0), Vector3(-0.423 * spd, 0.906 * spd, 0), col)
				5:
					_fire(Vector3(0, 0.22*s, 0), Vector3(           0,          spd, 0), col)
					_fire(Vector3(0, 0.22*s, 0), Vector3( 0.259 * spd, 0.966 * spd, 0), col)
					_fire(Vector3(0, 0.22*s, 0), Vector3(-0.259 * spd, 0.966 * spd, 0), col)
					_fire(Vector3(0, 0.22*s, 0), Vector3( 0.5   * spd, 0.866 * spd, 0), col)
					_fire(Vector3(0, 0.22*s, 0), Vector3(-0.5   * spd, 0.866 * spd, 0), col)
		else:
			# Combined: 1 straight forward only
			_fire(Vector3(0, 0.22*s, 0), Vector3(0, spd, 0), col)
	elif wide_mode:
		var col := Color(0.267, 1.0, 0.8, 1) if lv <= 2 else \
				   (Color(0, 1, 0.6, 1) if lv <= 4 else Color(1, 0.7, 0, 1))
		# Read nozzle world positions directly from animated nodes
		var gp    := global_position
		var n_off := _nose_tip.global_position      - gp
		var l_off := _left_missile.global_position  - gp
		var r_off := _right_missile.global_position - gp
		match lv:
			1:
				_fire(l_off, Vector3(0.0, spd, 0.0), col)
				_fire(r_off, Vector3(0.0, spd, 0.0), col)
			2:
				_fire(n_off, Vector3(0.0, spd, 0.0), col)
				_fire(l_off, Vector3(0.0, spd, 0.0), col)
				_fire(r_off, Vector3(0.0, spd, 0.0), col)
			3:
				_fire(n_off, Vector3(0.0,          spd,         0.0), col)
				_fire(l_off, Vector3(-0.259 * spd, 0.966 * spd, 0.0), col)
				_fire(r_off, Vector3( 0.259 * spd, 0.966 * spd, 0.0), col)
			4:
				_fire(n_off, Vector3(0.0,          spd,         0.0), col)
				_fire(l_off, Vector3(-0.259 * spd, 0.966 * spd, 0.0), col)
				_fire(r_off, Vector3( 0.259 * spd, 0.966 * spd, 0.0), col)
				_fire(l_off, Vector3(-0.5   * spd, 0.866 * spd, 0.0), col)
				_fire(r_off, Vector3( 0.5   * spd, 0.866 * spd, 0.0), col)
			5:
				_fire(n_off, Vector3(0.0,          spd,         0.0), col)
				_fire(l_off, Vector3(-0.259 * spd, 0.966 * spd, 0.0), col)
				_fire(r_off, Vector3( 0.259 * spd, 0.966 * spd, 0.0), col)
				_fire(l_off, Vector3(-0.5   * spd, 0.866 * spd, 0.0), col)
				_fire(r_off, Vector3( 0.5   * spd, 0.866 * spd, 0.0), col)
	else:
		# Solo normal mode: parallel bullets that home onto marked (alt-band) enemies
		var col := Color(0.667, 0.933, 1, 1) if lv <= 2 else \
				   (Color(0.4, 0.85, 1, 1) if lv <= 4 else Color(1, 0.95, 0.4, 1))
		match lv:
			1:
				_fire(Vector3(0, 0.25*s, 0), Vector3(0, spd, 0), col, true)
			2:
				_fire(Vector3(-0.04*s, 0.22*s, 0), Vector3(0, spd, 0), col, true)
				_fire(Vector3( 0.04*s, 0.22*s, 0), Vector3(0, spd, 0), col, true)
			3, 4:
				_fire(Vector3(      0, 0.25*s, 0), Vector3(0, spd, 0), col, true)
				_fire(Vector3(-0.08*s, 0.20*s, 0), Vector3(0, spd, 0), col, true)
				_fire(Vector3( 0.08*s, 0.20*s, 0), Vector3(0, spd, 0), col, true)
			5:
				for ox: float in [0.0, -0.06*s, 0.06*s, -0.12*s, 0.12*s]:
					_fire(Vector3(ox, 0.22*s, 0), Vector3(0, spd, 0), col, true)

func _can_run_hero_unit_autopilot(ap: int) -> bool:
	return (ap == 0 or ap == 2) \
		and not GameState.ending_cinematic \
		and not GameState.title_active \
		and not GameState.intro_active \
		and not GameState.in_transition() \
		and not GameState.arrive_lock \
		and not GameState.on_carrier \
		and not GameState.debug_pin_ship \
		and not (GameState.golden_walk and GameState.arena_active)

func _run_hero_unit_autopilot(delta: float) -> void:
	var t := float(GameState.frame) * 0.028
	var target_x := sin(t) * 1.35 + sin(t * 0.43 + 1.2) * 0.42
	var target_y := 0.15 + sin(t * 0.67) * 0.42
	if GameState.stage == "planet":
		target_x *= 0.72
		target_y = clampf(target_y, -0.25, 0.85)
	var old := Vector2(GameState.px, GameState.py)
	var follow := clampf(delta * 2.8, 0.0, 0.18)
	GameState.px = lerpf(GameState.px, target_x, follow)
	GameState.py = lerpf(GameState.py, target_y, follow)
	GameState.vx = GameState.px - old.x
	GameState.vy = GameState.py - old.y
	GameState.tAlt = lerpf(GameState.tAlt, GameState.ALT_MAX, 0.035)
	GameState.alt = lerpf(GameState.alt, GameState.tAlt, 0.12)
	alt_velocity = 0.0
