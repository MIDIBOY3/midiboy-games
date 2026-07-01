extends Node3D

@onready var unit1: Node3D = $Unit1
const SpaceStructuresScene := preload("res://scripts/SpaceStructures.gd")

# Per-unit invincibility frames after a hit (index = uid-1).
var _unit_inv: Array[int] = [0, 0, 0, 0, 0]
var _mothership_timer: int = 600
var _takeover_cd: int = 2400   # frames until the first carrier-takeover event (~40s)
const TAKEOVER_DRAIN := 0.018  # hull lost per frame while boarded — slow, a grace window
const MAX_PLAYER_BULLETS := 64
const MAX_ENEMY_BULLETS := 32
const MAX_TERRAIN_BULLET_CHECKS := 42

# Underground (the lower stratum, always rendered beneath the surface on a planet).
# Sits just below the surface underside so the cave shows THROUGH a hole the moment
func _ready() -> void:
	GameState.apply_mouse_mode()
	unit1.position = Vector3(0, 0, 0)
	add_child(SpaceStructuresScene.new())
	# Pre-warm the emission+alpha shader variant (enemies, enemy bullets,
	# explosions all use it) so the first real one doesn't hitch on
	# GL shader compilation. A tiny brief flash near the screen corner.
	var warm := Explosion.new()
	warm.count = 2
	warm.strength = 0.2
	add_child(warm)
	warm.position = Vector3(1.6, 1.0, 0.0)

	# Headless smoke-test hook: TSG_DEBUG_PLANET=<BIOME|1> boots straight
	# into a planet stage (same path as the KEY_P debug jump below).
	var env_biome := OS.get_environment("TSG_DEBUG_PLANET")
	if env_biome != "":
		_debug_enter_planet(env_biome if PlanetTerrain.BIOMES.has(env_biome) else "")
	# Debug/tuning: TSG_PIN_SHIP="px,py,alt" freezes the ship each frame (Unit1 input
	# is skipped via GameState.debug_pin_ship) so surface visuals like the blob shadow
	# can be observed at a known position under TSG_CAPTURE_* — captures have no mouse.
	var pin := OS.get_environment("TSG_PIN_SHIP")
	if pin != "":
		var p := pin.split(",", false)
		if p.size() == 3:
			_pin_ship = Vector3(float(p[0]), float(p[1]), float(p[2]))
			GameState.debug_pin_ship = true

	_build_prof_overlay()
	_build_space_glow()
	# Deck-walk hub mode: idle until the player clicks while riding the carrier deck
	# (see project-deck-hub-mode). Runs while the tree is paused.
	add_child(preload("res://scripts/DeckWalkMode.gd").new())
	# Debug: F4 = generic articulated humanoid sandbox (kept for future pilots/NPCs);
	# F5 = walk the REAL transforming Golden (single-click jump / hold-to-transform).
	add_child(preload("res://scripts/GoldenWalkProto.gd").new())
	add_child(preload("res://scripts/GoldenWalkCtl.gd").new())
	add_child(preload("res://scripts/ZakoMode.gd").new())
	add_child(preload("res://scripts/EnemyFront.gd").new())
	add_to_group("main")
	# Boot into the GENESIS title screen (unless a debug env jumped straight into play).
	# ZAKO prototype: the title + carrier intro are GENESIS-era progression we disable here
	# (the suppression loop even deletes the intro carrier each frame). Per the design brief
	# the first loop is simply "Heroで進む", so boot straight into visible, controllable HERO
	# flight at alt1000 with the ship at the world origin.
	if env_biome != "" or GameState.is_zako_prototype_mode():
		GameState.title_active = false
	if GameState.is_zako_prototype_mode():
		GameState.intro_active = false
		GameState.alt = GameState.ALT_MAX
		GameState.tAlt = GameState.ALT_MAX
		GameState.px = 0.0
		GameState.py = 0.0
		# World-coordinate model: HERO starts at the world origin at max altitude.
		GameState.hero_pos = Vector2.ZERO
		GameState.hero_alt = GameState.ALT_MAX
		GameState.hero_talt = GameState.ALT_MAX
		GameState.zako_alt = GameState.ALT_MAX
		GameState.zako_talt = GameState.ALT_MAX
		GameState.cam_y = 0.0
		GameState.zako_spawned = false
		GameState.enemy_front.clear()
		GameState.front_blocks.clear()
		# Debug: TSG_ZAKO_MODE=1 boots straight into ZAKO play (same as pressing F9 once).
		if OS.get_environment("TSG_ZAKO_MODE") != "":
			GameState.set_local_side(GameState.SIDE_ZAKO)
	if GameState.title_active:
		_setup_title()

# Space-side bloom: a WorldEnvironment with ONLY glow (ambient disabled, fog off, black
# background hidden behind the starfield quad) so the space look is unchanged except that
# bright emissive things bloom. Disabled while on a planet so the planet's own env rules.
func _build_space_glow() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.fog_enabled = false
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	# Threshold ABOVE the background's max (it is clamped to 1.0) so the starfield/nebula
	# never bloom; only game FX whose emission exceeds this glow.
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_space_env_res = env
	_space_env = WorldEnvironment.new()
	_space_env.environment = env
	add_child(_space_env)

func _setup_title() -> void:
	GameState.alt = GameState.ALT_MAX
	GameState.tAlt = GameState.ALT_MAX
	GameState.px = 0.0
	GameState.py = 0.0
	var title := TitleScreen.new()
	add_child(title)
	title.global_position = Vector3(0.0, 0.3, GameState.alt_to_z(GameState.ALT_MAX))

# Game start: clear the title, then play the intro (carrier frames in from the bottom
# with the ship on the deck; the ship takes off; control hands over at alt1000).
func _start_game() -> void:
	if not GameState.title_active:
		return
	GameState.title_active = false
	GameState.intro_active = false
	GameState.carrier_battle = false
	GameState.on_carrier = false
	GameState.game_over = false
	for n in get_tree().get_nodes_in_group("title_screen"):
		(n as Node).queue_free()
	GameState.intro_active = true
	GameState.alt = GameState.ALT_MAX
	GameState.tAlt = GameState.ALT_MAX
	var ship := Mothership.new()
	ship.intro = true
	ship.ship_alt = GameState.ALT_MAX
	add_child(ship)
	ship.global_position = Vector3(0.0, -6.0, GameState.alt_to_z(GameState.ALT_MAX))

# Continue after a game over: revive every owned unit at full life, clear the threats,
# grant brief invincibility, and resume right where you were (run/score kept).
func _continue_game() -> void:
	GameState.game_over = false
	for i in 5:
		GameState.unit_life[i] = GameState.life_cap()
		_unit_inv[i] = 150
	_clear_enemies()

# Ending → BACK TO TITLE: wipe persistent state and reload the scene fresh.
func back_to_title() -> void:
	GameState.reset_for_title()
	get_tree().reload_current_scene()

# Debug (gameplay tuning): KEY_P skips the targeting/approach flow — in space
# it dives straight into a random-biome planet, on a planet it jumps back out.
func _input(event: InputEvent) -> void:
	# Dev shortcuts (spec): F1 cursor show/hide · F2 mouse-capture toggle (debug) · F3
	# fullscreen toggle. Esc always restores the cursor. Cursor is never confined in play.
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1:
				GameState.toggle_cursor_visible()
				get_viewport().set_input_as_handled()
				return
			KEY_F2:
				GameState.toggle_mouse_capture()
				get_tree().call_group("star_hud", "show_message", "MOUSE CAPTURE", "debug toggle")
				get_viewport().set_input_as_handled()
				return
			KEY_F3:
				_toggle_fullscreen()
				get_viewport().set_input_as_handled()
				return
			KEY_ESCAPE:
				GameState.show_cursor()   # Esc always frees the cursor (pause TBD)
	# Title screen: choose language first; Enter/Space/click starts.
	if GameState.title_active:
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_J:
					Loc.set_language(Loc.JA)
				KEY_E:
					Loc.set_language(Loc.EN)
				KEY_LEFT, KEY_RIGHT, KEY_TAB:
					Loc.toggle_language()
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					_start_game()
		elif event is InputEventMouseButton and event.pressed:
			var mb := event as InputEventMouseButton
			var sz := get_viewport().get_visible_rect().size
			if mb.position.y > sz.y * 0.67 and mb.position.y < sz.y * 0.75:
				Loc.toggle_language()
			else:
				_start_game()
		return
	# Game over: any key or click CONTINUES (revive in place, threats cleared).
	if GameState.game_over and not GameState.ending_active:
		if (event is InputEventKey and event.pressed and not event.echo) \
				or (event is InputEventMouseButton and event.pressed):
			_continue_game()
		return
	# Mouse wheel steps the active actor up/down ONE altitude level (LOW/MID/HIGH). Handled
	# before the key-only guard below, which drops all non-key events.
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_active_alt(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_active_alt(-1)
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if GameState.in_transition():
		return
	match event.keycode:
		KEY_F10:
			# Toggle the on-screen performance/debug overlay (fps + draw calls + counts).
			# (Moved off F3, which is now fullscreen — see input spec v1.0.)
			if _prof_label != null:
				_prof_label.visible = not _prof_label.visible
		KEY_F9:
			var side := GameState.toggle_local_side()
			_sync_active_actor_chunks()
			var detail := "PILOT ZAKO: move + altitude (auto-aim)" if GameState.should_autopilot_hero_unit() else "PILOT HERO: move + altitude (fixed forward)"
			print("LOCAL SIDE: ", side, " / ", detail)
			get_tree().call_group("star_hud", "show_message", "LOCAL SIDE: %s" % side, detail)
		KEY_P:
			if GameState.suppress_genesis_progression():
				return
			if GameState.stage == "space":
				_debug_enter_planet("")
			else:
				var terr := get_tree().get_first_node_in_group("planet_terrain")
				if terr != null:
					terr.call("_finish_exit")
		KEY_O:
			# Debug: tear open a descent hole just ahead of the ship (the rare
			# natural sites are too sparse to hit reliably while testing).
			if GameState.stage == "planet" and not GameState.underground:
				var terr := get_tree().get_first_node_in_group("planet_terrain")
				if terr != null:
					terr.open_hole_at(GameState.px, GameState.py + 0.4)
		KEY_J:
			if GameState.suppress_genesis_progression():
				return
			# INTERIM trigger for the route panels (正規パネル / BOSSパネル): simulates
			# a panel reveal from mining. At ROUTE4 it finds the BOSS PANEL; otherwise
			# it arms the next boundary gate as the true gate.
			# TODO: replace with real discovery by mining surface blocks (see
			# project-core-loop-redesign / project-final-boss-sequence memory).
			GameState.arm_route_gate()
			if GameState.route_complete():
				get_tree().call_group("star_hud", "show_message",
					"BOSS PANEL FOUND", "CLIMB TO SPACE - CHOOSE A GATE")
			else:
				get_tree().call_group("star_hud", "show_message",
					"ROUTE PANEL FOUND", "CLIMB TO SPACE - CHOOSE A GATE")
		KEY_K:
			if GameState.suppress_genesis_progression():
				return
			# Debug: force the black-hole mid-boss encounter (normally triggered by 3
			# blind gate crossings). Each press CYCLES the variant (0 dragon → 1 combiner
			# → 2 fleet) so all three can be tested in space.
			if GameState.stage == "space" and not GameState.blackhole_active:
				GameState.enter_blackhole(_dbg_bh_variant)
				var names := ["DRAGON", "COMBINER", "FLEET"]
				get_tree().call_group("star_hud", "show_message",
					"DEBUG: BLACK HOLE", "MID-BOSS: %s" % names[_dbg_bh_variant])
				_dbg_bh_variant = (_dbg_bh_variant + 1) % 3
		KEY_B:
			if GameState.suppress_genesis_progression():
				return
			# Debug: jump straight to the final boss fight, skipping the route grind.
			# Marks the route complete + boss panel found and spawns THE GENESIS now.
			# On a planet it bounces out to space first (press B again once up there).
			GameState.route_progress = GameState.ROUTE_GOAL
			GameState.boss_armed = true
			if GameState.stage != "space":
				var terr := get_tree().get_first_node_in_group("planet_terrain")
				if terr != null:
					terr.call("_finish_exit")
				get_tree().call_group("star_hud", "show_message",
					"DEBUG: LEAVING PLANET", "PRESS B AGAIN IN SPACE FOR THE BOSS")
			elif GameState.final_phase == GameState.FINAL_NONE:
				GameState.final_phase = GameState.FINAL_BOSS
				_spawn_space_boss()
				get_tree().call_group("star_hud", "show_message",
					"DEBUG: GOD", "FLY THE COLUMN - STRIKE EACH ALTITUDE")
		KEY_K:
			if GameState.suppress_genesis_progression():
				return
			# Slice trigger for the boss arena: from a sphere surface, dive into the
			# reused voxel cave to fight the PolygonGuardian. Pressing it again while
			# inside force-clears the arena (debug). The real "approaching gate"
			# entity that calls enter_arena() is the next step (see HANDOFF).
			if GameState.arena_active:
				GameState.underground_boss_defeated = true
			elif GameState.stage == "planet":
				enter_arena()

func _debug_enter_planet(biome: String) -> void:
	if GameState.suppress_genesis_progression():
		return
	if biome == "":
		var biomes: Array = []
		for k: String in PlanetTerrain.BIOMES:
			var bd: Dictionary = PlanetTerrain.BIOMES[k]
			if not bd.get("abyss", false) and not bd.get("boss", false):
				biomes.append(k)
		biome = biomes[randi() % biomes.size()]
	var planet := TargetPlanet.new()
	planet.star_name = "TEST-%d" % (randi() % 1000)
	planet.biome = biome
	add_child(planet)
	planet.global_position = Vector3(0.0, 1.2, TargetPlanet.BG_Z)
	planet.call_deferred("_finish_entry", true)

# F5 Golden walk debug: spawn the legacy BOSS voxel cave directly, without requiring
# a surface star or the old KEY_K arena gate. This is a sandbox for walking the real
# 5-unit Golden on the arena floor; no boss/relic flow is armed.
func debug_enter_golden_arena() -> void:
	if GameState.arena_active:
		return
	GameState.title_active = false
	for n in get_tree().get_nodes_in_group("title_screen"):
		(n as Node).queue_free()
	for grp in ["enemies", "enemy_bullets", "bullets", "mothership", "mothership_beacon"]:
		for n in get_tree().get_nodes_in_group(grp):
			(n as Node).queue_free()
	GameState.stage = "planet"
	GameState.planet_biome = "BOSS"
	GameState.planet_seed = randi() | 1
	GameState.planet_name = "GOLDEN-WALK-ARENA"
	GameState.arena_return_biome = ""
	GameState.arena_return_seed = 0
	GameState.arena_return_name = ""
	GameState.arena_return_alt = GameState.ALT_MAX
	GameState.arena_active = true
	GameState.underground_boss_area = true
	GameState.underground_boss_defeated = false
	GameState.arena_reward_pending = false
	GameState.entry_glow = 0.35
	GameState.entry_tint = Color(0.26, 0.18, 0.42)
	GameState.alt = GameState.ARENA_FLOOR_ALT + 60.0
	GameState.tAlt = GameState.alt
	GameState.px = 0.0
	GameState.py = -2.8
	_arena_guardian_pending = false
	_arena_guardian_spawned = false
	_arena_exit_rising = false
	_arena_loot_timer = 999999
	_arena_unit_timer = 999999
	_arena_offered_unit = 0
	GameState.pending_terrain = {"biome": "BOSS", "seed": GameState.planet_seed}
	get_tree().call_group("star_hud", "show_message",
		"GOLDEN WALK DEBUG", "CLICK: ROBOT/FIGHTER  WHEEL DOWN: ZOOM  F5/ESC: EXIT")

func debug_exit_golden_arena() -> void:
	if not GameState.arena_active:
		return
	# Only the FULL run (stoneface reached → outro) continues into the GOD standoff; a bare F5/ESC
	# exit just drops back to normal space.
	var into_finale := GameState.true_route_active and GameState.arena_survivor_greeted
	GameState.true_route_active = false
	for grp in ["enemies", "enemy_bullets", "bullets", "repair_items", "key_items",
			"arena_survivor", "arena_campfire", "arena_warmth", "arena_gather"]:
		for n in get_tree().get_nodes_in_group(grp):
			(n as Node).queue_free()
	_reset_survivor_gather()
	get_tree().call_group("star_hud", "stop_monologue")
	var old := get_tree().get_first_node_in_group("planet_terrain")
	if old != null:
		old.queue_free()
	GameState.arena_relics_found = 0
	GameState.arena_wall_armed = false
	GameState.arena_survivor_spawned = false
	GameState.arena_survivor_greeted = false
	# If F5 was pressed mid-outro, don't strand the zoom; the black fade is kept and eased back
	# in over space by _update_screen_fade (so a manual exit still resolves cleanly).
	if _survivor_phase != 0:
		_survivor_phase = 0
		_fade_target = 0.0
		GameState.golden_camera_zoom = 0.0
	GameState.arena_active = false
	GameState.underground_boss_area = false
	GameState.underground_boss_defeated = false
	GameState.arena_reward_pending = false
	GameState.pending_terrain = {}
	GameState.stage = "space"
	GameState.alt = GameState.ALT_MAX
	GameState.tAlt = GameState.ALT_MAX
	GameState.px = 0.0
	GameState.py = 0.0
	_arena_guardian_pending = false
	_arena_guardian_spawned = false
	_arena_exit_rising = false
	_arena_offered_unit = 0
	if into_finale:
		call_deferred("_start_god_sequence")
	else:
		get_tree().call_group("star_hud", "show_message",
			"GOLDEN WALK DEBUG OFF", "RETURNED TO SPACE")

var _ending_start_alt: float = 0.0
var _space_env: WorldEnvironment = null
var _space_env_res: Environment = null
var _prof_label: Label = null
var _star_kind_label: Label = null
var _capture_dir: String = ""
var _capture_frames: PackedInt32Array = PackedInt32Array()
var _pin_ship: Vector3 = Vector3.INF

func _sync_active_actor_chunks() -> void:
	var terr := get_tree().get_first_node_in_group("planet_terrain")
	if terr == null:
		return
	var y := GameState.active_world_y()
	if terr.has_method("ensure_chunks_around"):
		terr.call("ensure_chunks_around", y, GameState.chunk_preload_screens)
	elif terr.has_method("ensure_generated_to"):
		terr.call("ensure_generated_to", y)
	if terr.has_method("recalculate_visible_chunks"):
		terr.call("recalculate_visible_chunks")

# Faction-specific scroll (design):
#   HERO = AUTO / forced scroll — the camera advances at a constant rate; the ship steers
#          within the frame (Unit1 clamps hero_pos to the visible band around cam_y).
#   ZAKO = FREE scroll — the camera follows the ZAKO with a deadzone (it will place terrain,
#          so the player drives the scroll). Never re-centers → no spring-back.
# F9 switch snaps the camera onto the new active actor. Entities sit at true world positions,
# so moving the camera to cam_y renders them at worldY - cam_y.
const CAM_DEADZONE := 0.35     # ZAKO: small band — the camera scrolls almost immediately as the
                              # ZAKO moves (no need to reach the screen edges), still no spring-back
const HERO_SCROLL_SPEED := 0.035  # HERO: constant forward auto-scroll (world units / frame)
var _cam_was_zako := false
func _update_faction_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var zako := GameState.is_zako_mode()
	if zako != _cam_was_zako:
		GameState.cam_y = GameState.zako_pos.y if zako else GameState.hero_pos.y  # snap on F9
		_cam_was_zako = zako
	elif zako:
		var d := GameState.zako_pos.y - GameState.cam_y   # free scroll: deadzone follow the ZAKO
		if d > CAM_DEADZONE:
			GameState.cam_y += d - CAM_DEADZONE
		elif d < -CAM_DEADZONE:
			GameState.cam_y += d + CAM_DEADZONE
	else:
		# HERO forward auto-scroll at a CONSTANT world rate (altitude does NOT change how fast you
		# traverse the shared world — pure-camera model). The apparent speed varies only via the
		# per-player camera depth (perspective ÷ cam_z) and the background scroll (also ÷ cam_z).
		GameState.cam_y += HERO_SCROLL_SPEED
	# Altitude = world DEPTH. The camera rides CAM_REF_DIST above the SELF's altitude-z, so the
	# self is a constant distance (constant size) while the opponent/world at their own altitude-z
	# appear bigger/smaller by the altitude gap. Only the world & the opponent move with altitude.
	var active_alt := GameState.zako_alt if zako else GameState.hero_alt
	GameState.cam_z = GameState.alt_z(active_alt) + GameState.CAM_REF_DIST
	cam.global_position = Vector3(0.0, GameState.cam_y, GameState.cam_z)
	# Faction-relative view: ZAKO rolls the world 180° so it plays bottom-to-top like HERO —
	# the HERO Unit (lower world-Y) then appears at the TOP of the screen facing down toward
	# the ZAKO player. (ZAKO movement is inverted to match; see ZakoMode._update_zako_unit.)
	cam.rotation = Vector3(0.0, 0.0, PI) if zako else Vector3.ZERO
	# Mirror the active actor into the legacy px/py/alt readers.
	if zako:
		GameState.px = GameState.zako_pos.x
		GameState.py = GameState.zako_pos.y
		GameState.alt = GameState.zako_alt
	else:
		GameState.px = GameState.hero_pos.x
		GameState.py = GameState.hero_pos.y
		GameState.alt = GameState.hero_alt
	GameState.tAlt = GameState.alt

# Mouse wheel nudges the active actor's altitude continuously (fine control).
const ALT_WHEEL_STEP := 60.0
func _adjust_active_alt(dir: int) -> void:
	if GameState.is_zako_mode():
		GameState.zako_talt = clampf(GameState.zako_talt + dir * ALT_WHEEL_STEP, 0.0, GameState.ALT_MAX)
	else:
		GameState.hero_talt = clampf(GameState.hero_talt + dir * ALT_WHEEL_STEP, 0.0, GameState.ALT_MAX)

# F3: toggle between borderless fullscreen (default) and a windowed view (dev convenience).
func _toggle_fullscreen() -> void:
	var m := DisplayServer.window_get_mode()
	if m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

# Altitude is CONTINUOUS — you can stop ANYWHERE (no snapping). The gauge just shows 10 notches
# for readability. The stick moves the target; the numeric altitude eases toward it.
const ALT_SMOOTH := 0.20          # ease of altitude toward the target (responsive but smooth)
const ALT_STICK_DEADZONE := 0.12
const ALT_STICK_RATE := 7.0       # target change per frame at full stick tilt
func _update_altitude() -> void:
	var stick := Input.get_action_strength("alt_up") - Input.get_action_strength("alt_down")
	var zako := GameState.is_zako_mode()
	var target: float = GameState.zako_talt if zako else GameState.hero_talt
	if absf(stick) > ALT_STICK_DEADZONE:
		target = clampf(target + stick * ALT_STICK_RATE, 0.0, GameState.ALT_MAX)
	if zako:
		GameState.zako_talt = target
		GameState.zako_alt = lerpf(GameState.zako_alt, target, ALT_SMOOTH)
	else:
		GameState.hero_talt = target
		GameState.hero_alt = lerpf(GameState.hero_alt, target, ALT_SMOOTH)

func _suppress_genesis_progression_nodes() -> void:
	for group_name in ["boundary_gate", "target_planet", "mothership", "mothership_beacon",
			"route_plate", "arena_gate", "golden_icon", "abyss_gates", "key_items",
			"offering_spark", "true_god", "space_boss", "genesis_boss"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node != null and is_instance_valid(node):
				(node as Node).queue_free()
	GameState.target_star = ""
	GameState.target_star_type = "boss"
	GameState.gate_active = false
	GameState.route_armed = false
	GameState.boss_armed = false
	GameState.final_phase = GameState.FINAL_NONE
	GameState.god_phase = 0
	GameState.true_route_active = false
	GameState.ending_active = false
	GameState.ending_cinematic = false
	GameState.survivor_monologue_active = false
	GameState.carrier_takeover = false
	GameState.takeover_boarders = 0
	GameState.on_carrier = false
	GameState.carrier_battle = false

# On-screen perf overlay: a big readable label in the top-left, hidden until F3.
func _build_prof_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_prof_label = Label.new()
	_prof_label.position = Vector2(12, 10)
	_prof_label.add_theme_font_size_override("font_size", 22)
	_prof_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	_prof_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_prof_label.add_theme_constant_override("outline_size", 6)
	_prof_label.visible = false
	layer.add_child(_prof_label)
	_star_kind_label = Label.new()
	_star_kind_label.position = Vector2(12, 92)
	_star_kind_label.add_theme_font_size_override("font_size", 26)
	_star_kind_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	_star_kind_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_star_kind_label.add_theme_constant_override("outline_size", 7)
	layer.add_child(_star_kind_label)
	_capture_dir = OS.get_environment("TSG_CAPTURE_DIR")
	var raw_frames := OS.get_environment("TSG_CAPTURE_FRAMES")
	if _capture_dir != "" and raw_frames != "":
		DirAccess.make_dir_recursive_absolute(_capture_dir)
		for part in raw_frames.split(",", false):
			_capture_frames.append(int(part.strip_edges()))

func _update_prof_overlay() -> void:
	if _star_kind_label != null:
		_star_kind_label.visible = false
	if _prof_label == null or not _prof_label.visible:
		return
	var tree := get_tree()
	var av: float = float(unit1.get("alt_velocity")) if unit1 != null else 0.0
	var alt_name: String = "%d" % GameState.alt_display(GameState.alt)
	_prof_label.text = "FPS: %.0f   DRAW CALLS: %d\nbullets:%d  enemies:%d  resources:%d  orbs:%d\npan:%d wheel:%d magnify:%d last:(%.2f,%.2f)\naltV:%.3f  alt:%s  mouse:%s\n[F1 cursor] [F3 fullscreen] [F10 hide]" % [
		Performance.get_monitor(Performance.TIME_FPS),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		tree.get_nodes_in_group("bullets").size(),
		tree.get_nodes_in_group("enemies").size(),
		tree.get_nodes_in_group("resource_items").size(),
		tree.get_nodes_in_group("power_orbs").size(),
		GameState.dbg_pan_count, GameState.dbg_wheel_count, GameState.dbg_magnify_count,
		GameState.dbg_last_pan.x, GameState.dbg_last_pan.y,
		av, alt_name,
		str(Input.get_mouse_mode())]

func _process(_delta: float) -> void:
	GameState.frame += 1
	if _pin_ship != Vector3.INF:
		GameState.px = _pin_ship.x
		GameState.py = _pin_ship.y
		GameState.alt = _pin_ship.z
		GameState.tAlt = _pin_ship.z
		GameState.hero_pos = Vector2(_pin_ship.x, _pin_ship.y)
		GameState.hero_alt = _pin_ship.z
		GameState.hero_talt = _pin_ship.z
	# World-coordinate camera: follow the ACTIVE actor's world-Y so every entity renders at
	# worldY - cam_y. Also mirrors the active actor into px/py/alt for the legacy readers
	# (enemy homing, background parallax, altitude bands).
	_update_altitude()
	_update_faction_camera()
	_update_prof_overlay()
	_capture_debug_frame()
	if GameState.suppress_genesis_progression():
		_suppress_genesis_progression_nodes()
	if not GameState.suppress_genesis_progression():
		_update_takeover_event()
	# Keep bloom through the seamless space-to-sphere transition. A planet-specific world
	# environment may take precedence later, but the current spherical surface deliberately
	# stays in this same field and must not lose its glow at the boundary.
	if _space_env != null:
		var planet_env := get_tree().get_first_node_in_group("world_env")
		_space_env.environment = null if planet_env != null else _space_env_res

	# Motion-check sandbox: keep the robot alone and fully visible (no enemy
	# contact, no invincibility blink) so any leg flicker can't be a hit-blink.
	if GameState.motion_debug:
		for i in 5:
			_unit_inv[i] = 0
		_clear_enemies()

	for i in 5:
		if _unit_inv[i] > 0:
			_unit_inv[i] -= 1
	# Golden robot: damage is pooled, so the i-frame TIMING still applies but the
	# per-limb visibility blink must NOT — flashing a single limb (esp. the legs)
	# while the others stay solid read as a flicker bug. Keep the whole robot solid.
	if GameState.title_active:
		# Title screen: only the logo + stars; the ship is offstage.
		unit1.visible = false
		for uid in [2, 3, 4, 5]:
			var u := _unit_node(uid)
			if u != null:
				u.visible = false
	elif GameState.intro_active or GameState.carrier_battle:
		# Intro takeoff / carrier-pilot finale: the hero ship is visible, wingmen stowed.
		unit1.visible = true
		for uid in [2, 3, 4, 5]:
			var u := _unit_node(uid)
			if u != null:
				u.visible = false
	elif GameState.golden_active:
		unit1.visible = true
		for uid in [2, 3, 4, 5]:
			if uid in GameState.collected_units:
				var u := _unit_node(uid)
				if u != null:
					u.visible = true
	else:
		unit1.visible = (_unit_inv[0] % 10) < 6 if _unit_inv[0] > 0 else true
		for uid in [2, 3, 4, 5]:
			if _unit_inv[uid - 1] > 0 and uid in GameState.collected_units:
				var u := _unit_node(uid)
				if u != null:
					u.visible = (_unit_inv[uid - 1] % 10) < 6

	if not GameState.pending_terrain.is_empty():
		_swap_terrain()
		# The arena's voxel cave terrain now exists → drop the boss + loot in.
		if GameState.arena_active and _arena_guardian_pending:
			_arena_guardian_pending = false
			_spawn_arena_guardian()
			_spawn_arena_loot()
	_update_underground_layer()
	_update_atmosphere()
	_update_screen_fade()
	_update_survivor_sequence()
	_update_survivor_gather()
	_update_god_sequence()
	if GameState.arena_active and GameState.golden_walk:
		_update_arena_survivor()
		_update_arena_campfire()
	if GameState.arena_active:
		# Rain loot from the top of the vault; it pools at the floor (see RepairItem
		# arena_fall / _update_arena_unit_fall). The player dives to the floor to grab it.
		_arena_loot_timer -= 1
		if _arena_loot_timer <= 0:
			_arena_loot_timer = 150 + (randi() % 150)
			_drop_arena_heal()
		_arena_unit_timer -= 1
		if _arena_unit_timer <= 0 and _arena_offered_unit == 0:
			_arena_unit_timer = 360 + (randi() % 240)   # next attempt (also if all owned)
			_offer_arena_unit()
		_update_arena_unit_fall()
		_detect_arena_boss_reward()
		_ensure_arena_boss_relic()
		if _arena_exit_rising:
			_update_arena_exit_rise()
			return
		# Cleared: the final relic pickup sets underground_boss_defeated. The boss
		# death only drops the relic to the arena floor; the player must collect it.
		if GameState.underground_boss_defeated:
			_begin_arena_exit_rise()
			return

	if not GameState.game_over and not GameState.motion_debug:
		if not GameState.suppress_genesis_progression():
			_update_final_boss()
			_update_blackhole()
			_update_ending()
			_update_mothership_spawn()
			_update_navigation()
		_check_collisions()
		_check_powerup()
		GameState.update_golden()
		if not GameState.suppress_genesis_progression():
			_update_golden_offer()
			_update_arena_gate_offer()

# Golden offer: the first moment the full 5-unit formation exists in this star system
# (and we're in open play), a single G icon frames in from the top. Collecting it fires
# the 10 s invincible Golden robot. golden_offered (reset on crossing to a new system)
# guarantees exactly one chance per system; missing it forfeits this system's Golden.
func _update_golden_offer() -> void:
	if GameState.golden_offered or GameState.golden_active:
		return
	if GameState.collected_units.size() < 5:
		return
	if GameState.in_transition() or GameState.on_carrier or GameState.arrive_lock \
			or GameState.arena_active or GameState.autopilot != 0 or GameState.star_entry \
			or GameState.god_phase > 0 or GameState.ending_cinematic \
			or GameState.final_phase != GameState.FINAL_NONE:
		return
	if GameState.stage != "space" and GameState.stage != "planet":
		return
	GameState.golden_offered = true
	var icon := GoldenIcon.new()
	add_child(icon)
	icon.global_position = Vector3(clampf(GameState.px, -1.4, 1.4), 2.4,
		GameState.alt_to_z(GameState.alt))

# The underground gate to the stoneface arena: it frames in on a FINAL-ROUTE star's surface, but
# ONLY at MAX durability. Fly into it (handled by the gate) to zoom down into the arena.
var _arena_gate_offered: bool = false
func _update_arena_gate_offer() -> void:
	if GameState.suppress_genesis_progression():
		return
	# Re-arm once the player leaves the surface, so a later qualifying star can offer it again.
	if GameState.stage != "planet" or GameState.arena_active:
		_arena_gate_offered = false
		return
	if _arena_gate_offered:
		return
	if GameState.dura_level < GameState.DURA_MAX or GameState.route_progress < GameState.ROUTE_GOAL:
		return
	if GameState.in_transition() or GameState.on_carrier or GameState.arrive_lock \
			or GameState.autopilot != 0 or GameState.star_entry or GameState.golden_walk:
		return
	if GameState.alt > GameState.GROUND_ALT + 30.0:
		return   # only once actually down on the surface, not mid-descent
	_arena_gate_offered = true
	var gate := SurfaceArenaGate.new()
	add_child(gate)
	gate.global_position = Vector3(clampf(GameState.px, -1.4, 1.4), 2.6,
		GameState.alt_to_z(GameState.alt))
	get_tree().call_group("star_hud", "show_message",
		"地中に道が開いた", "GATE TO THE DEEP - FLY INTO IT")

# Stage B: once the BOSS PANEL is found (boss_armed) and the player has climbed back
# up into open space, the final boss awakens. Spawns the SpaceBoss once and flips
# final_phase. (Carrier-strike fight = stage C; ending = stage D.)
func _update_final_boss() -> void:
	if GameState.suppress_genesis_progression():
		return
	if GameState.final_phase != GameState.FINAL_NONE or not GameState.boss_armed:
		return
	if GameState.stage != "space" or GameState.in_transition() \
			or GameState.alt < GameState.ALT_MAX - 1.0:
		return
	GameState.final_phase = GameState.FINAL_BOSS
	# AngelBoss runs its own 舞い降り entrance (hush → theme → slow descent) and posts the
	# combat banner itself once it lands; don't announce the fight here.
	_spawn_space_boss()

# Stage D: a fully hands-off ending. Called by Mothership the instant THE GENESIS dies.
# Locks player control + firing, freezes the cosmos (no structures spawn → no frame
# drops), spawns the lightweight homeworld, and rolls the ending crawl. The descent is
# then driven by the crawl's own progress (_update_ending) so it lands as the text ends.
func _start_ending_cinematic() -> void:
	if GameState.suppress_genesis_progression():
		return
	if GameState.ending_cinematic:
		return
	GameState.ending_cinematic = true
	GameState.scroll_frozen = true
	_clear_target_planets()   # remove the old (boss-panel) star so it doesn't double up
	_ending_start_alt = GameState.alt
	var play_z: float = GameState.alt_to_z(GameState.alt)
	var home := HomePlanet.new()
	add_child(home)
	home.global_position = Vector3(0.0, -2.5, play_z - 6.0)   # far/small, swells over time
	get_tree().call_group("star_hud", "start_ending")

# Drives the slow automatic descent from the ending crawl's progress (0→1): the ship
# sinks toward the homeworld over the WHOLE message, the globe swells, and its spin
# stops as the crawl reaches GAME OVER. No player input the entire time.
func _update_ending() -> void:
	if not GameState.ending_cinematic:
		return
	var hud := get_tree().get_first_node_in_group("star_hud")
	var p := 0.0
	if hud != null:
		p = float(hud.call("ending_progress"))
	# Ship descends automatically over the length of the crawl (no input).
	GameState.alt = lerpf(_ending_start_alt, GameState.GROUND_ALT, p)
	GameState.tAlt = GameState.alt
	GameState.px = lerpf(GameState.px, 0.0, 0.05)
	GameState.py = lerpf(GameState.py, 0.0, 0.05)
	GameState.vx = 0.0
	GameState.vy = 0.0
	var play_z: float = GameState.alt_to_z(GameState.alt)
	var home := get_tree().get_first_node_in_group("home_planet") as Node3D
	if home != null:
		home.call("set_grow", p)
		# The globe SWELLS (keeps looming larger) but its near face is always kept BEHIND
		# the ship so the ship never sinks into it. center_z = ship_z - (radius*scale + gap).
		var s := lerpf(0.2, 1.0, p)
		var center_z := play_z - (HomePlanet.RADIUS * s + 1.2)
		home.global_position = home.global_position.lerp(
			Vector3(0.0, -2.2, center_z), 0.05)
		# (Globe keeps spinning all the way through — never stopped.)

# Black-hole mid-boss system: once the entry crossfade completes, drop the boss into
# clean space. When every joint (and the exposed core) is destroyed, frame in a gate
# to leave for the next normal star system.
var _blackhole_boss_spawned: bool = false
var _dbg_bh_variant: int = 0   # debug: KEY_K cycles which boss variant spawns

func _update_blackhole() -> void:
	if GameState.suppress_genesis_progression():
		return
	if not GameState.blackhole_active:
		_blackhole_boss_spawned = false
		return
	if GameState.stage != "space" or GameState.in_transition():
		return
	if not _blackhole_boss_spawned:
		_blackhole_boss_spawned = true
		_clear_enemies()
		_clear_target_planets()
		var boss := BlackHoleBoss.new()
		boss.variant = GameState.blackhole_boss_variant
		add_child(boss)
		boss.global_position = Vector3(0.0, BlackHoleBoss.SPAWN_Y,
			GameState.alt_to_z(GameState.alt) - 1.5)
		get_tree().call_group("star_hud", "show_message",
			"A LEVIATHAN STIRS IN THE DARK", "DESTROY EVERY JOINT, THEN THE CORE")
		return
	# Boss destroyed → the dark releases you: frame in a boundary gate and move on.
	if get_tree().get_nodes_in_group("blackhole_boss").is_empty():
		GameState.blackhole_active = false
		_blackhole_boss_spawned = false
		get_tree().call_group("star_hud", "show_message",
			"THE DARK GIVES WAY", "A GATE OPENS - FLY THROUGH")
		if get_tree().get_nodes_in_group("boundary_gate").is_empty():
			GameState.gate_active = true
			add_child(SpaceGate.new())

func _spawn_space_boss() -> void:
	if GameState.suppress_genesis_progression():
		return
	if not get_tree().get_nodes_in_group("space_boss").is_empty():
		return
	# Clean duel: clear any rabble + the lingering discovered star so only the boss remains.
	_clear_enemies()
	_clear_target_planets()
	_clear_angel_carrier_calls()
	# The golden angel-god: a ship-killable, 3-altitude-layer boss (AngelBoss positions
	# itself in _ready and tracks the player's depth plane). Preloaded (not the global
	# class name) so it resolves before the editor has scanned the new script.
	add_child(preload("res://scripts/AngelBoss.gd").new())

# AngelBoss is the heavenly seal, not the last encounter. Once its death sequence has
# finished, THE GENESIS descends from the same uninterrupted space field and the carrier
# is called in for the established heavy-beam finale.
func _begin_genesis_battle() -> void:
	if GameState.suppress_genesis_progression():
		return
	for n in get_tree().get_nodes_in_group("space_boss"):
		if n != null and is_instance_valid(n) and not (n as Node).is_queued_for_deletion():
			return
	GameState.final_boss_defeated = false
	GameState.final_phase = GameState.FINAL_BOSS
	var genesis := SpaceBoss.new()
	add_child(genesis)
	get_tree().call_group("star_hud", "show_message",
		"THE GENESIS AWAKENS", "OPEN FIRE - FIND ITS WEAKNESS")

# The Genesis first absorbs normal fire. SpaceBoss calls this only after the player has
# witnessed that their own weapons do not work, so the carrier solution is earned.
func _release_genesis_beacon() -> void:
	if GameState.suppress_genesis_progression():
		return
	if not get_tree().get_nodes_in_group("mothership").is_empty() \
			or not get_tree().get_nodes_in_group("mothership_beacon").is_empty():
		return
	get_tree().call_group("star_hud", "show_message",
		"CARRIER WEAPON REQUIRED", "BEACON INBOUND - TAKE THE HELM")
	add_child(MothershipBeacon.new())

func _clear_angel_carrier_calls() -> void:
	for group_name in ["mothership", "mothership_beacon"]:
		for n in get_tree().get_nodes_in_group(group_name):
			if n != null and is_instance_valid(n):
				n.queue_free()

# Dispose any discovered/target star so it doesn't linger behind the boss / homeworld.
func _clear_target_planets() -> void:
	for p in get_tree().get_nodes_in_group("target_planet"):
		if p == null or not is_instance_valid(p) or (p as Node).is_queued_for_deletion():
			continue
		if p.has_method("dispose_immediate"):
			p.call("dispose_immediate")
		else:
			(p as Node).queue_free()
	GameState.target_star = ""

func _capture_debug_frame() -> void:
	if _capture_dir == "" or _capture_frames.is_empty():
		return
	if not _capture_frames.has(GameState.frame):
		return
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/frame_%05d.png" % [_capture_dir, GameState.frame])

func _clear_enemies() -> void:
	for n in get_tree().get_nodes_in_group("enemies"):
		(n as Node).queue_free()
	for n in get_tree().get_nodes_in_group("enemy_bullets"):
		(n as Node).queue_free()

# Frees the old PlanetTerrain BEFORE the new one spawns, so the per-planet
# light/atmosphere save-restore chain stays correct (abyss gates and the
# abyss climb-out can't free their own ancestor safely themselves).
func _swap_terrain() -> void:
	var req: Dictionary = GameState.pending_terrain
	GameState.pending_terrain = {}
	var old := get_tree().get_first_node_in_group("planet_terrain")
	if old != null:
		old.free()
	var terr := PlanetTerrain.new()
	terr.biome_id = req["biome"]
	terr.seed_v = req["seed"]
	add_child(terr)

# ============================================================================
# BOSS ARENA (vertical slice) — gate → scene-switch into the reused voxel cave,
# fight the PolygonGuardian, then rebuild the SAME sphere surface on win. All
# arena state is gated behind GameState.arena_active so live play is untouched.
# Trigger today = KEY_K; the real "approaching gate" entity is the next step.
# See HANDOFF_boss_arena.md for the architecture, tuning knobs, and TODOs.
# ============================================================================
var _arena_guardian_pending: bool = false
var _arena_exit_rising: bool = false
var _arena_guardian_spawned: bool = false

# Leave the sphere surface and swap in the voxel cave arena. _swap_terrain (next
# frame) frees the TargetPlanet sphere and builds the BOSS-biome voxel terrain;
# because arena_active is already true, PlanetTerrain._ready enables the cave.
func enter_arena() -> void:
	if GameState.arena_active or GameState.stage != "planet":
		return
	var surf := get_tree().get_first_node_in_group("planet_terrain")
	if not (surf is TargetPlanet):
		return  # only divable from a real sphere surface
	# Stash what's needed to rebuild the SAME orb on return.
	GameState.arena_return_biome = GameState.planet_biome
	GameState.arena_return_seed = GameState.planet_seed
	GameState.arena_return_name = GameState.planet_name
	GameState.arena_return_alt = GameState.alt
	for grp in ["enemies", "enemy_bullets", "bullets"]:
		for n in get_tree().get_nodes_in_group(grp):
			(n as Node).queue_free()
	# Flag arena ON *before* the voxel terrain's _ready so it builds the cave.
	GameState.arena_active = true
	GameState.underground_boss_area = true
	GameState.underground_boss_defeated = false
	GameState.arena_reward_pending = false
	GameState.entry_glow = 1.0
	GameState.entry_tint = Color(0.5, 0.2, 0.6)   # gate-dive wipe tint
	# Start mid-band so there's room to climb and dive (chase the boss's altitude).
	GameState.alt = GameState.ARENA_FLOOR_ALT + 120.0
	GameState.tAlt = GameState.alt
	_arena_guardian_pending = true
	_arena_exit_rising = false
	_arena_guardian_spawned = false
	# Random seed every entry → a different meandering arena each time.
	GameState.pending_terrain = {"biome": "BOSS", "seed": (randi() | 1)}

func _spawn_arena_guardian() -> void:
	var e := PolygonGuardian.new()
	var d := GameState.difficulty()
	e.hp = 190 + int(d * 90.0)
	e.max_hp = e.hp
	e.hue = 285.0
	# Spawn coplanar with the ship (z is then pinned to the ship's plane each frame).
	e.alt = clampf(GameState.alt / GameState.ALT_MAX, 0.0, 1.0)
	e.position = Vector3(0.0, GameState.py + 4.0, GameState.alt_to_z(GameState.alt))
	add_child(e)
	_arena_guardian_spawned = true
	get_tree().call_group("star_hud", "show_message",
		"GATE BOSS - POLYGON GUARDIAN", "DEFEAT IT TO RETURN")

# Cave loot: a couple of heal pickups, plus one un-owned combine-unit offered as a
# collectable (reuses the carrier collection flow via FormationManager._available).
var _arena_offered_unit: int = 0
var _arena_unit_alt: float = 0.0
var _arena_unit_xy: Vector2 = Vector2.ZERO
var _arena_loot_timer: int = 0
var _arena_unit_timer: int = 0

# Start the loot clocks; items are spawned over time by _process (rain + periodic unit).
func _spawn_arena_loot() -> void:
	_arena_loot_timer = 60
	_arena_unit_timer = 180
	_arena_offered_unit = 0

# One heal pickup raining from the top of the vault at a random x.
func _drop_arena_heal() -> void:
	var r := RepairItem.new()
	r.arena_fall = true
	r.fall_alt = GameState.ARENA_CEIL_ALT - 8.0
	add_child(r)
	r.global_position = Vector3(randf_range(-GameState.ARENA_HALF_W, GameState.ARENA_HALF_W),
		GameState.py + randf_range(4.0, 5.6), GameState.alt_to_z(r.fall_alt))

# Offer one un-owned combine-unit, raining from the top (reuses the carrier flow).
func _offer_arena_unit() -> void:
	var fm := get_node_or_null("FormationManager")
	if fm == null:
		return
	for uid in [2, 3, 4, 5]:
		if uid not in GameState.collected_units:
			_arena_offered_unit = uid
			_arena_unit_alt = GameState.ARENA_CEIL_ALT - 8.0
			_arena_unit_xy = Vector2(randf_range(-GameState.ARENA_HALF_W, GameState.ARENA_HALF_W),
				GameState.py + 5.2)
			fm._available[uid] = Vector3(_arena_unit_xy.x, _arena_unit_xy.y,
				GameState.alt_to_z(_arena_unit_alt))
			return

# The offered unit rains to the floor and rides the terrain scroll; if collected or it
# drifts off uncollected, retire it and arm the timer for the next periodic appearance.
func _update_arena_unit_fall() -> void:
	if _arena_offered_unit == 0:
		return
	var fm := get_node_or_null("FormationManager")
	if fm == null:
		return
	if _arena_offered_unit in GameState.collected_units:
		_arena_offered_unit = 0
		_arena_unit_timer = 360 + (randi() % 240)
		return
	_arena_unit_alt = maxf(GameState.ARENA_FLOOR_ALT, _arena_unit_alt - 1.2)
	_arena_unit_xy.y -= PlanetTerrain.SCROLL
	if _arena_unit_xy.y < -6.0:   # scrolled away uncollected → retire, offer again later
		fm._available.erase(_arena_offered_unit)
		_arena_offered_unit = 0
		_arena_unit_timer = 360 + (randi() % 240)
		return
	fm._available[_arena_offered_unit] = Vector3(_arena_unit_xy.x, _arena_unit_xy.y,
		GameState.alt_to_z(_arena_unit_alt))

func _detect_arena_boss_reward() -> void:
	if not _arena_guardian_spawned or GameState.arena_reward_pending \
			or GameState.underground_boss_defeated:
		return
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n) and not (n as Node).is_queued_for_deletion() \
				and str(n.get("enemy_type")) == "poly_guardian":
			return
	GameState.arena_reward_pending = true

func _ensure_arena_boss_relic() -> void:
	if not GameState.arena_reward_pending:
		return
	spawn_arena_boss_relic()

func spawn_arena_boss_relic() -> void:
	GameState.arena_reward_pending = true
	for n in get_tree().get_nodes_in_group("boss_relic"):
		if is_instance_valid(n) and not (n as Node).is_queued_for_deletion():
			return
	var relic := KeyItem.new()
	relic.item_kind = "boss_relic"
	relic.arena_floor_drop = true
	relic.fall_alt = GameState.ARENA_FLOOR_ALT
	add_child(relic)
	relic.global_position = Vector3(GameState.px, GameState.py + 1.4,
		GameState.alt_to_z(relic.fall_alt))
	get_tree().call_group("star_hud", "show_message",
		"FINAL RELIC ON LOWEST LAYER", "DESCEND AND COLLECT THE PURPLE CORE")

# --- GERWALK relic hunt → sealed wall → survivor cavern ---
const ARENA_WALL_AHEAD := 14.0       # world-y the wall band is planted ahead of the player at 3 relics
const ARENA_SURVIVOR_OFFSET := 9.0   # how far past the wall START the survivor lies (a few u into the cavern)
# Survivor outro: monologue+zoom (1) → hold on the last line (2) → black fade-out → exit (3).
var _survivor_phase: int = 0
var _survivor_hold: int = 0
var _fade_target: float = 0.0
# Zako gathering: from the "誰かの故郷..." line, ~10 random zako drift in from the top and nestle
# around the survivor, one after another.
const GATHER_TOTAL := 10
const GATHER_INTERVAL := 58          # frames between each zako framing in
var _gather_armed: bool = false
var _gather_spawned: int = 0
var _gather_timer: int = 0
var _gather: Array = []              # [{node, target: Vector3}]

func _reset_survivor_gather() -> void:
	_gather_armed = false
	_gather_spawned = 0
	_gather_timer = 0
	_gather.clear()

# Eases the full-screen black overlay toward its target every frame (runs in space too, so the
# outro can fade back IN after returning from the arena).
func _update_screen_fade() -> void:
	GameState.fade_black = move_toward(GameState.fade_black, _fade_target, 0.02)

# --- True-route finale: the silent GOD standoff in empty space ---
const FAITH_FILL := 0.0016       # FAITH gauge per frame while facing GOD (~10s to MAX)
const GOD_FADE := 0.006          # GOD's slow dissolve per frame once faith fills (~2.8s)
var _god_fade: float = 1.0

# Returning from the stoneface arena lands here: an empty, silent cosmos with the GOD idol. Neither
# side fires (Unit1 gated on god_phase; GOD is pacifist); a FAITH gauge fills instead of HP.
func _start_god_sequence() -> void:
	if GameState.suppress_genesis_progression():
		return
	GameState.true_route_active = true
	GameState.god_phase = 1
	GameState.faith_gauge = 0.0
	_god_fade = 1.0
	_genesis_fade = 1.0
	_true_ending = false
	for sp in get_tree().get_nodes_in_group("offering_spark"):
		(sp as Node).queue_free()
	_offering_sparks.clear()
	GameState.scroll_frozen = true
	GameState.stage = "space"
	GameState.alt = GameState.ALT_MAX
	GameState.tAlt = GameState.ALT_MAX
	GameState.px = 0.0
	GameState.py = 0.0
	_clear_enemies()
	_clear_target_planets()
	# Sweep the cosmos clean for the standoff: no gate rings, no in-progress takeover, no items.
	for grp in ["boundary_gate", "abyss_gates", "arena_gate", "key_items", "golden_icon",
			"power_orbs", "repair_items", "player_projectiles", "bullets"]:
		for n in get_tree().get_nodes_in_group(grp):
			(n as Node).queue_free()
	GameState.gate_active = false
	GameState.carrier_takeover = false
	var god := preload("res://scripts/AngelBoss.gd").new()
	god.pacifist = true
	god.add_to_group("true_god")
	add_child(god)

# Drives the standoff: FAITH fills → GOD slowly FADES OUT → GENESIS frames in (the beacon-offering
# that drains SCORE to the TRUE ENDING is the next stage, #4).
func _update_god_sequence() -> void:
	if GameState.suppress_genesis_progression():
		return
	if GameState.god_phase == 0:
		return
	if GameState.god_phase == 1:
		GameState.faith_gauge = clampf(GameState.faith_gauge + FAITH_FILL, 0.0, 1.0)
		if GameState.faith_gauge >= 1.0:
			GameState.god_phase = 2   # faith full → GOD begins to dissolve
	elif GameState.god_phase == 2:
		_god_fade = maxf(0.0, _god_fade - GOD_FADE)
		for n in get_tree().get_nodes_in_group("true_god"):
			if n.has_method("set_fade"):
				n.call("set_fade", _god_fade)
		if _god_fade <= 0.0:
			for n in get_tree().get_nodes_in_group("true_god"):
				(n as Node).queue_free()
			GameState.god_phase = 3
			# GOD's defeat opens the REAL Genesis battle: the tentacled THE GENESIS (SpaceBoss)
			# frames in from the top exactly like the normal final fight.
			add_child(SpaceBoss.new())
			GameState.score = maxi(GameState.score, 12000)   # DEBUG: ensure there's something to pour
			get_tree().call_group("star_hud", "show_message",
				"THE GENESIS", "DEDICATE EVERYTHING FROM THE CARRIER")
			_release_god_beacon()
	elif GameState.god_phase == 3:
		_update_god_offering()

# Phase 3: grab the beacon, board the carrier, and pour every mined point into GENESIS in a stream
# of sparkles — SCORE drains to 0, then GENESIS departs and the TRUE ENDING rolls.
const SCORE_DRAIN_MIN := 25
var _true_ending: bool = false
var _genesis_fade: float = 1.0
var _offering_sparks: Array = []

func _release_god_beacon() -> void:
	if GameState.suppress_genesis_progression():
		return
	if not get_tree().get_nodes_in_group("mothership_beacon").is_empty():
		return
	add_child(MothershipBeacon.new())   # frames in from the top; touching it summons the carrier

func _update_god_offering() -> void:
	var genesis := get_tree().get_first_node_in_group("genesis_boss") as Node3D
	if _true_ending:
		_update_offering_sparks()
		# GENESIS frames out slowly, in gratitude. Once it's gone, the closing cinematic rolls.
		if genesis == null and not GameState.ending_cinematic:
			_start_true_ending()
		return
	# Once the player has grabbed the beacon and taken the helm (母艦操縦モード = carrier_battle).
	# The carrier's beam is suppressed (Mothership gates on god_phase); resources scatter instead.
	if (GameState.carrier_battle or GameState.on_carrier) and GameState.score > 0 and genesis != null:
		var drain := maxi(SCORE_DRAIN_MIN, int(GameState.score * 0.008))   # a visible ~few-second pour
		GameState.score = maxi(0, GameState.score - drain)
		if (GameState.frame & 1) == 0:
			_emit_offering_sparkle(genesis.global_position)
		if GameState.score <= 0:
			_true_ending = true
			if genesis.has_method("begin_depart"):
				genesis.call("begin_depart")   # GENESIS rises away in gratitude — not destroyed
			get_tree().call_group("star_hud", "show_message",
				"THE GENESIS DEPARTED", "")
	_update_offering_sparks()

# The offering is complete and GENESIS has ascended: roll the TRUE ENDING — the same descent +
# crawl as the normal ending, but over a withered homeworld with the major-key music box.
func _start_true_ending() -> void:
	if GameState.suppress_genesis_progression():
		return
	if GameState.ending_cinematic:
		return
	GameState.god_phase = 0
	GameState.carrier_battle = false
	GameState.on_carrier = false
	GameState.musicbox_ending = true
	# FINAL_ENDING reuses every "ending" suppression (no enemies / structures / gates / takeover).
	# The music stays the MAJOR music box because TsgAudio checks musicbox_ending first.
	GameState.final_phase = GameState.FINAL_ENDING
	GameState.ending_cinematic = true
	GameState.scroll_frozen = true
	_fade_target = 0.0
	GameState.fade_black = 0.0
	for grp in ["mothership", "mothership_beacon", "offering_spark",
			"golden_icon", "power_orbs", "key_items", "repair_items"]:
		for n in get_tree().get_nodes_in_group(grp):
			(n as Node).queue_free()
	GameState.golden_offered = true   # belt-and-suspenders: no G-icon can frame in during the ending
	_clear_target_planets()
	_ending_start_alt = GameState.alt
	var play_z := GameState.alt_to_z(GameState.alt)
	var home := HomePlanet.new()
	home.decayed = true   # the withered, colour-drained Earth
	add_child(home)
	home.global_position = Vector3(0.0, -2.5, play_z - 6.0)
	get_tree().call_group("star_hud", "start_true_ending")

# One mote of converted resource streaming up from the ship/deck toward GENESIS.
func _emit_offering_sparkle(to: Vector3) -> void:
	var spark := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.07, 0.07, 0.07)
	spark.mesh = bm
	var hue := randf()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.from_hsv(hue, 0.35, 1.0)
	m.emission_enabled = true
	m.emission = Color.from_hsv(hue, 0.5, 1.0)
	m.emission_energy_multiplier = 4.5
	spark.material_override = m
	spark.add_to_group("offering_spark")
	add_child(spark)
	TsgAudio.pickup(randf() < 0.3)   # twinkly chime (self-rate-limited) as resources stream up
	var from := Vector3(GameState.px + randf_range(-0.7, 0.7),
		GameState.py + randf_range(-0.3, 0.4), GameState.alt_to_z(GameState.alt))
	spark.global_position = from
	_offering_sparks.append({"node": spark, "from": from, "to": to, "t": 0.0,
		"life": randf_range(26.0, 42.0), "side": 1.0 if randf() < 0.5 else -1.0})

func _update_offering_sparks() -> void:
	for i in range(_offering_sparks.size() - 1, -1, -1):
		var s: Dictionary = _offering_sparks[i]
		var n := s["node"] as Node3D
		if n == null or not is_instance_valid(n):
			_offering_sparks.remove_at(i)
			continue
		s["t"] += 1.0
		var k := clampf(s["t"] / float(s["life"]), 0.0, 1.0)
		var ek := k * k * (3.0 - 2.0 * k)
		var p: Vector3 = (s["from"] as Vector3).lerp(s["to"] as Vector3, ek)
		p.x += sin(k * PI) * 0.35 * float(s["side"])   # gentle arc
		n.global_position = p
		n.scale = Vector3.ONE * lerpf(1.0, 0.15, k)
		if k >= 1.0:
			n.queue_free()
			_offering_sparks.remove_at(i)

# Drives the survivor outro once the monologue is rolling: a slow ~15% zoom over the back third
# of the crawl, a hold on the final line, then a black fade-out and a clean exit to space.
func _update_survivor_sequence() -> void:
	if _survivor_phase == 0:
		return
	var hud := get_tree().get_first_node_in_group("star_hud")
	var prog := 0.0
	if hud != null and hud.has_method("ending_progress"):
		prog = float(hud.call("ending_progress"))
	if _survivor_phase == 1:
		# golden_camera_zoom 0→0.70 maps cam distance 3.2→~2.5 (~22% closer). Ramp it across the
		# WHOLE crawl, starting right at the first line, so the view creeps in throughout.
		GameState.golden_camera_zoom = clampf(prog, 0.0, 1.0) * 0.70
		if prog >= 0.999:
			_survivor_phase = 2
			_survivor_hold = 210   # let the final line sit before the fade
	elif _survivor_phase == 2:
		_survivor_hold -= 1
		if _survivor_hold <= 0:
			_survivor_phase = 3
			_fade_target = 1.0
	elif _survivor_phase == 3 and GameState.fade_black >= 0.999:
		# Fully black → tear the arena down through the normal exit path, then fade back into space.
		get_tree().call_group("golden_ctl", "exit_to_space")
		_survivor_phase = 0
		_fade_target = 0.0

# Once the monologue hits its cue line, random zako drift in from above and settle in a loose
# ring around the survivor — slow, one at a time. They are dormant (Main eases them to their spot).
func _update_survivor_gather() -> void:
	if _survivor_phase == 0:
		return
	if not _gather_armed:
		var hud := get_tree().get_first_node_in_group("star_hud")
		if hud != null and hud.has_method("mono_at_gather_cue") and bool(hud.call("mono_at_gather_cue")):
			_gather_armed = true
			_gather_timer = 0
	if _gather_armed and _gather_spawned < GATHER_TOTAL:
		_gather_timer -= 1
		if _gather_timer <= 0:
			_gather_timer = GATHER_INTERVAL
			_spawn_gather_one()
	for rec in _gather:
		var n := rec.get("node") as Node3D
		if n != null and is_instance_valid(n):
			n.global_position = n.global_position.lerp(rec["target"], 0.022)   # ease to its spot

func _spawn_gather_one() -> void:
	var sp := get_node_or_null("EnemySpawner")
	var survivor := get_tree().get_first_node_in_group("arena_survivor") as Node3D
	if sp == null or survivor == null or not sp.has_method("spawn_gather_zako"):
		return
	var floor_z := GameState.alt_to_z(GameState.ARENA_FLOOR_ALT)
	var c := survivor.global_position
	var target := _pick_gather_target(c, floor_z)
	# Enter from just off the top (close, so they reach frame fast) straight down onto the spot.
	var spawn_pos := Vector3(target.x + randf_range(-0.2, 0.2), c.y + randf_range(2.2, 3.0), floor_z)
	var e := sp.call("spawn_gather_zako", spawn_pos) as Node3D
	if e != null:
		_gather.append({"node": e, "target": target})
		_gather_spawned += 1

# A resting spot hugging the survivor, biased to the STONEFACE side (at/above its y, never down
# toward the player below) and kept clear of the survivor and of every already-placed zako.
func _pick_gather_target(c: Vector3, floor_z: float) -> Vector3:
	const MIN_SEP := 0.42
	var best := Vector3(c.x, c.y + 0.7, floor_z)
	var best_d := -1.0
	for _attempt in 18:
		# A TIGHT huddle hugging the stoneface — around and just above it (never down toward the
		# player below), close enough that all ten read as nestling against the survivor.
		var cand := Vector3(c.x + randf_range(-1.0, 1.0), c.y + randf_range(-0.3, 1.1), floor_z)
		var nearest := Vector2(cand.x, cand.y).distance_to(Vector2(c.x, c.y))
		if nearest < 0.34:
			continue
		for rec in _gather:
			var t: Vector3 = rec["target"]
			nearest = minf(nearest, Vector2(cand.x, cand.y).distance_to(Vector2(t.x, t.y)))
		if nearest >= MIN_SEP:
			return cand
		if nearest > best_d:
			best_d = nearest
			best = cand
	return best

# Called by the 3rd arena_relic pickup: plant the sealed wall ahead (it generates into the not-
# yet-spawned chunks, so it frames in from the top as the player advances) and lay the survivor
# in the cavern beyond it.
func on_arena_relics_complete() -> void:
	if GameState.arena_wall_armed:
		return
	GameState.arena_wall_armed = true
	GameState.arena_wall_y = GameState.py + ARENA_WALL_AHEAD
	var survivor_y := GameState.arena_wall_y + ARENA_SURVIVOR_OFFSET
	var floor_z := GameState.alt_to_z(GameState.ARENA_FLOOR_ALT)
	var sp := get_node_or_null("EnemySpawner")
	if sp != null and sp.has_method("spawn_arena_survivor"):
		sp.call("spawn_arena_survivor", Vector3(0.0, survivor_y, floor_z))
		GameState.arena_survivor_spawned = true
	_spawn_arena_campfire(Vector3(0.55, survivor_y - 0.5, floor_z))
	get_tree().call_group("star_hud", "show_message",
		"A SEALED WALL BARS THE WAY", "BREAK THROUGH IT")

# A soft, warm campfire beside the survivor: a flickering warm light + a small ember glow,
# plus a big steady warm wash so the whole cavern reads as a warm little world.
func _spawn_arena_campfire(pos: Vector3) -> void:
	var floor_z := pos.z
	# Glossy floor slab. NOT metallic — a metal mirrors the near-black cave env and goes pure
	# black; a warm DIELECTRIC is lit by the firelight (never black) and its sharp specular throws
	# bright warm glints (a wet, light-catching floor).
	var slab := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(8.0, 7.0)
	slab.mesh = quad
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.16, 0.09, 0.06)
	smat.metallic = 0.0
	smat.metallic_specular = 1.0
	smat.roughness = 0.12
	slab.material_override = smat
	slab.position = Vector3(pos.x, pos.y + 0.7, floor_z - 0.06)
	slab.add_to_group("arena_warmth")
	add_child(slab)
	var warmth := OmniLight3D.new()
	warmth.light_color = Color(1.0, 0.66, 0.38)
	warmth.omni_range = 26.0
	warmth.omni_attenuation = 0.8
	warmth.light_energy = 6.0                       # strong warm wash so the dim cave glows warm
	warmth.shadow_enabled = false
	warmth.position = pos + Vector3(-0.55, 1.0, 2.0)   # broad fill over the whole chamber
	warmth.add_to_group("arena_warmth")
	add_child(warmth)
	var fire := OmniLight3D.new()
	fire.light_color = Color(1.0, 0.55, 0.22)
	fire.omni_range = 9.0
	fire.omni_attenuation = 1.2
	fire.light_energy = 9.0                         # the fire itself: bright, flickering hot core
	fire.shadow_enabled = false
	fire.position = pos + Vector3(0.0, 0.0, 0.7)   # lift toward the camera so it lights the floor
	fire.add_to_group("arena_campfire")
	add_child(fire)
	# A tiny self-lit ember so there's a visible source, not just cast light.
	var ember := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.16, 0.16, 0.10)
	ember.mesh = bm
	var em := StandardMaterial3D.new()
	em.albedo_color = Color(1.0, 0.5, 0.18)
	em.emission_enabled = true
	em.emission = Color(1.0, 0.55, 0.2)
	em.emission_energy_multiplier = 3.0
	ember.material_override = em
	ember.position = pos + Vector3(0.0, 0.0, 0.12)
	ember.add_to_group("arena_campfire")
	add_child(ember)

# Gentle campfire flicker — warm energy wobbles each frame on a couple of out-of-phase sines.
func _update_arena_campfire() -> void:
	# Hot, lively flicker around a bright base (the cave is dim — the fire should clearly glow).
	var flick := 9.0 + 1.9 * sin(float(GameState.frame) * 0.31) \
		+ 1.0 * sin(float(GameState.frame) * 0.73 + 1.3)
	for n in get_tree().get_nodes_in_group("arena_campfire"):
		if n is OmniLight3D:
			(n as OmniLight3D).light_energy = flick
		elif n is MeshInstance3D:
			var mat := (n as MeshInstance3D).material_override as StandardMaterial3D
			if mat != null:
				mat.emission_energy_multiplier = 6.0 + 0.7 * (flick - 9.0)
	_update_cavern_warmth()

# Bathe the cavern in a warm, dreamlike glow as the player nears the survivor: the dim cave
# ambient/fog/sky blend toward firelight, SSR mirrors the warm scene on the glossy floor, and the
# cold cave sun fades out. Far from the survivor it stays the cold cave.
func _update_cavern_warmth() -> void:
	var survivor := get_tree().get_first_node_in_group("arena_survivor") as Node3D
	if survivor == null:
		return
	var we := get_tree().get_first_node_in_group("world_env") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var d := Vector2(GameState.px, GameState.py).distance_to(
		Vector2(survivor.global_position.x, survivor.global_position.y))
	var t := clampf((11.0 - d) / 11.0, 0.0, 1.0)
	var t2 := t * t
	var env := we.environment
	env.ambient_light_color = Color(0.09, 0.09, 0.14).lerp(Color(1.0, 0.6, 0.34), t2)
	env.ambient_light_energy = lerpf(0.26, 1.25, t2)
	env.background_color = Color(0.02, 0.02, 0.05).lerp(Color(0.12, 0.05, 0.03), t2)
	env.fog_light_color = Color(0.06, 0.06, 0.10).lerp(Color(1.0, 0.6, 0.35), t2 * 0.7)
	env.ssr_enabled = t2 > 0.12
	var dl := get_tree().current_scene.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if dl != null:
		dl.light_energy = lerpf(0.50, 0.12, t2)

# One-shot proximity hook: when the GERWALK reaches the dormant survivor, fire the discovery
# beat. (Future dialogue / cutscene can hang off this.)
func _update_arena_survivor() -> void:
	if not GameState.arena_survivor_spawned or GameState.arena_survivor_greeted:
		return
	var here := Vector2(GameState.px, GameState.py)
	for n in get_tree().get_nodes_in_group("arena_survivor"):
		var s := n as Node3D
		if s == null or not is_instance_valid(s):
			continue
		if here.distance_to(Vector2(s.global_position.x, s.global_position.y)) < 0.9:
			GameState.arena_survivor_greeted = true
			# Roll the survivor's words with the ending crawl + ending music, and start the
			# outro sequence (freeze handled in GoldenWalkCtl, zoom + fade here).
			get_tree().call_group("star_hud", "start_survivor_monologue")
			_survivor_phase = 1
			_reset_survivor_gather()
			break

func _begin_arena_exit_rise() -> void:
	if not GameState.arena_active:
		return
	_arena_exit_rising = false
	_arena_loot_timer = 999999
	_arena_unit_timer = 999999
	for grp in ["enemies", "enemy_bullets", "bullets"]:
		for n in get_tree().get_nodes_in_group(grp):
			(n as Node).queue_free()
	GameState.entry_glow = 0.0
	GameState.entry_tint = Color(0.4, 0.7, 1.0)
	get_tree().call_group("star_hud", "show_message", "RELIC SECURED", "RETURNING TO SURFACE")
	_exit_arena()

func _update_arena_exit_rise() -> void:
	GameState.tAlt = minf(GameState.GROUND_ALT, GameState.tAlt + 18.0)
	GameState.alt = lerpf(GameState.alt, GameState.tAlt, 0.34)
	GameState.entry_glow = 0.0
	if GameState.alt >= GameState.GROUND_ALT - 2.0:
		_exit_arena()

# Arena cleared: tear down the cave and rebuild the sphere surface we left.
# (Done directly, NOT via pending_terrain — that path builds a voxel PlanetTerrain,
# but the surface is a TargetPlanet sphere.)
func _exit_arena() -> void:
	if GameState.arena_return_name != "":
		GameState.cleared_stars[GameState.arena_return_name] = true
	GameState.arena_active = false
	GameState.arena_reward_pending = false
	GameState.underground_boss_defeated = false
	GameState.underground_boss_area = false
	GameState.underground = false
	_arena_guardian_pending = false
	_arena_exit_rising = false
	# Don't leave an un-collected arena unit offer lingering on the surface.
	if _arena_offered_unit != 0:
		var fm := get_node_or_null("FormationManager")
		if fm != null and _arena_offered_unit not in GameState.collected_units:
			fm._available.erase(_arena_offered_unit)
		_arena_offered_unit = 0
	GameState.entry_glow = 0.0
	GameState.entry_tint = Color(0.4, 0.7, 1.0)   # surfacing wipe tint
	# Snap the ship back up to low orbit immediately (don't wait on the deferred
	# _finish_entry) so it visibly leaves the cave even if anything below is delayed.
	GameState.alt = GameState.GROUND_ALT
	GameState.tAlt = GameState.GROUND_ALT
	var old := get_tree().get_first_node_in_group("planet_terrain")
	if old != null:
		old.free()
	for grp in ["enemies", "enemy_bullets", "bullets"]:
		for n in get_tree().get_nodes_in_group(grp):
			(n as Node).queue_free()
	# Rebuild the SAME orb: the surface seed is _stable_surface_seed() = hash(name+
	# biome), so restoring star_name + biome deterministically regenerates the very
	# same surface we left. Called directly (we're in _process) so the return is
	# immediate and can't be lost to deferred-call timing.
	var planet := TargetPlanet.new()
	planet.star_name = GameState.arena_return_name
	planet.biome = GameState.arena_return_biome
	planet.star_type = "boss"
	add_child(planet)
	planet.global_position = Vector3(0.0, 1.2, TargetPlanet.BG_Z)
	planet._finish_entry(true)   # sets stage=planet, alt=GROUND_ALT, builds the sphere

# The world is ONE continuous voxel terrain (alt0 floor → crust → sky relief), so
# there is no second terrain to manage — just light the cavern while below the crust.
func _update_underground_layer() -> void:
	GameState.over_hole = false
	GameState.descent_gauge = 0.0
	if GameState.arena_active:
		# In the cave arena the lower world is lit and "underground" is on so the
		# cave light / dark atmosphere engage (see _update_atmosphere).
		GameState.underground = true
		_update_cave_light(true)
		return
	GameState.underground = false
	_update_cave_light(false)
var _cave_light: OmniLight3D = null
var _arena_ember_light: OmniLight3D = null
var _arena_key_light: SpotLight3D = null

# As the ship sinks below alt0 the world's "sky" (the env background), haze and
# ambient blend from the bright surface toward a dark underground cavern — so the
# scenery visibly CHANGES into the lower world (and through a hole from the
# surface you look down into the underground's dark sky).
var _env_we: Node = null
var _env_bg0: Color = Color.BLACK
var _env_fog0: float = 0.0
var _env_amb_e0: float = 0.0
var _env_amb_c0: Color = Color.BLACK
var _env_glow0: bool = false
func _update_atmosphere() -> void:
	if not GameState.arena_active:
		GameState.underground = false  # arena keeps it on (set in _update_underground_layer)
	GameState.over_hole = false
	var terrain := get_tree().get_first_node_in_group("planet_terrain")
	if terrain is TargetPlanet:
		return
	var we := get_tree().get_first_node_in_group("world_env")
	if we == null:
		_env_we = null
		return
	var env: Environment = (we as WorldEnvironment).environment
	if env == null:
		return
	if we != _env_we:   # new planet → cache its surface originals
		_env_we = we
		_env_bg0 = env.background_color
		_env_fog0 = env.fog_density
		_env_amb_e0 = env.ambient_light_energy
		_env_amb_c0 = env.ambient_light_color
		_env_glow0 = env.glow_enabled
	# Ramp into the cave look FAST: full dark-cavern bg/ambient by ~alt160, so just
	# under the crust the world is already the cave (not the surface's bright biome
	# bg, which made the underground read as a flat brown wash).
	var depth_t := 1.0 if GameState.arena_active else 0.0   # full cavern look in the arena
	# Dark blue-violet cavern void. Keep the ambient low so the Golden and blocks do not
	# white-bloom; local cave light below gives the "shaft of light in darkness" read.
	var ug_sky := Color(0.045, 0.052, 0.095) if GameState.golden_walk else Color(0.035, 0.045, 0.075)
	var ug_amb := Color(0.30, 0.32, 0.46) if GameState.golden_walk else Color(0.16, 0.18, 0.25)
	env.background_color = _env_bg0.lerp(ug_sky, depth_t)
	# In the arena, a MILD distance fog (coloured to the void) fades the far streaming
	# edge into the dark so terrain/objects don't visibly pop in at the top/bottom of
	# the screen when flying high. Density is low enough to leave the near play clear.
	if GameState.arena_active:
		env.fog_enabled = true
		env.fog_density = 0.018 if GameState.golden_walk else 0.025
		if "fog_light_color" in env:
			env.fog_light_color = Color(0.20, 0.16, 0.30) if GameState.golden_walk else ug_sky
	else:
		env.fog_density = lerpf(_env_fog0, 0.0, clampf(depth_t * 3.0, 0.0, 1.0))
	var arena_ambient := 0.48 if GameState.golden_walk else 0.34
	env.ambient_light_energy = lerpf(_env_amb_e0, arena_ambient, depth_t)
	env.ambient_light_color = _env_amb_c0.lerp(ug_amb, depth_t)
	# Arena richness: low bloom only. Strong bloom made the Golden and glowing blocks blow out.
	if GameState.arena_active:
		env.glow_enabled = true
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		if GameState.golden_walk:
			# Diamond arena: richer, sparklier bloom on the embedded diamonds. The AGX tonemap
			# (PlanetTerrain._setup_atmosphere) keeps the ship from white-flaring, so a lower
			# HDR threshold lets more crystals catch the light.
			env.glow_intensity = 0.32
			env.glow_bloom = 0.06
			env.glow_strength = 0.42
			if "glow_hdr_threshold" in env:
				env.glow_hdr_threshold = 1.35
		else:
			env.glow_intensity = 0.28
			env.glow_bloom = 0.08
			env.glow_strength = 0.35
			if "glow_hdr_threshold" in env:
				env.glow_hdr_threshold = 1.45
	else:
		env.glow_enabled = _env_glow0

# A big soft light sitting IN the underground beneath the ship, so the lower
# stratum is visible both from above (down a hole) and while flying through it.
func _update_cave_light(on: bool) -> void:
	if not on:
		if _cave_light != null:
			_cave_light.visible = false
		if _arena_ember_light != null:
			_arena_ember_light.visible = false
		if _arena_key_light != null:
			_arena_key_light.visible = false
		return
	if _cave_light == null:
		_cave_light = OmniLight3D.new()
		_cave_light.omni_range = 12.0
		_cave_light.light_color = Color(0.42, 0.54, 1.0)
		_cave_light.shadow_enabled = true
		_cave_light.shadow_bias = 0.018
		add_child(_cave_light)
	if _arena_ember_light == null:
		_arena_ember_light = OmniLight3D.new()
		_arena_ember_light.omni_range = 5.0
		_arena_ember_light.light_color = Color(1.0, 0.20, 0.10)
		_arena_ember_light.light_energy = 0.16
		_arena_ember_light.shadow_enabled = true
		_arena_ember_light.shadow_bias = 0.03
		add_child(_arena_ember_light)
	if _arena_key_light == null:
		_arena_key_light = SpotLight3D.new()
		_arena_key_light.name = "GoldenArenaKeyLight"
		_arena_key_light.light_color = Color(0.92, 0.94, 1.0)
		_arena_key_light.light_energy = 5.5
		_arena_key_light.spot_range = 9.0
		_arena_key_light.spot_angle = 54.0
		_arena_key_light.shadow_enabled = true
		_arena_key_light.shadow_bias = 0.012
		add_child(_arena_key_light)
	_cave_light.visible = true
	_arena_ember_light.visible = GameState.arena_active
	_arena_key_light.visible = GameState.golden_walk and GameState.arena_active
	var pz := GameState.alt_to_z(GameState.alt)
	var light_xy := Vector2(GameState.px, GameState.py)
	if _arena_key_light.visible:
		# A real positioned key light over the Golden, offset to upper-left, aimed at the
		# floor so the robot and blocks cast readable shadows onto the terrain.
		_arena_key_light.global_position = Vector3(GameState.px - 1.45, GameState.py + 1.85, pz + 4.2)
		_arena_key_light.look_at(Vector3(GameState.px + 0.15, GameState.py - 0.15, pz - 0.18), Vector3.UP)
	if GameState.over_hole and not GameState.underground:
		# Light the real shaft below the open crust so the surface hole reads as a
		# window into the same underground world before the player dives through.
		light_xy = GameState.hole_pos
		pz = GameState.alt_to_z(GameState.GROUND_ALT - 90.0)
		_cave_light.light_energy = 2.2
	else:
		# A cool light shaft slightly above/left of the Golden. This keeps the arena dark
		# but readable and lets the robot/blocks cast a visible floor shadow.
		var depth_t := clampf((GameState.GROUND_ALT - GameState.alt) / 40.0, 0.0, 1.0)
		_cave_light.light_energy = lerpf(1.25, 2.10, depth_t) if GameState.golden_walk else lerpf(0.95, 1.9, depth_t)
		light_xy += Vector2(-0.85, 1.10) if GameState.golden_walk else Vector2(-0.55, 0.85)
	_cave_light.global_position = Vector3(light_xy.x, light_xy.y, pz + 1.35)
	if _arena_ember_light != null:
		_arena_ember_light.global_position = Vector3(GameState.px + 1.0, GameState.py - 1.2, pz + 0.45)

func _unit_node(uid: int) -> Node3D:
	match uid:
		1: return unit1
		2: return $Unit2
		3: return $Unit3
		4: return $Unit4
		5: return $Unit5
	return null

func _update_mothership_spawn() -> void:
	if GameState.is_zako_mode():
		return
	if GameState.in_transition() or GameState.stage != "space" or GameState.on_carrier:
		return
	# No carriers during the title/intro, or once the player has taken the helm / won.
	if GameState.title_active or GameState.intro_active \
			or GameState.carrier_battle or GameState.final_phase == GameState.FINAL_ENDING:
		return
	# AngelBoss phase one has its own frequent heal drops. No carrier or beacon can dilute
	# that combat loop, including a signal left over from the previous open-space segment.
	if not get_tree().get_nodes_in_group("angel_boss").is_empty():
		return
	# Hull destroyed: the carrier is out of action for THIS system (no signal/repair/units).
	# It comes back a fresh carrier on crossing into the next star system (gate revival in
	# GameState.update_transition), or sooner if カナ博士's auto-repair fund rebuilds it >0.
	if GameState.carrier_hull <= 0.0:
		return
	# Carrier signal appears at ALL altitudes in space (was gated to the very top band).
	# In a CRISIS (乗っ取り中 / 慢心MAXで撃てない / 編隊が瀕死) the carrier answers IMMEDIATELY so
	# the player can reach it (defend it / repair / onsen) instead of being stranded —
	# collapse any pending wait to the next frame.
	var crisis := _carrier_crisis()
	if crisis:
		_mothership_timer = mini(_mothership_timer, 1)
	_mothership_timer -= 1
	if _mothership_timer > 0:
		return
	# Don't stack: hold off while a carrier or an un-answered signal is around.
	if not get_tree().get_nodes_in_group("mothership").is_empty() \
			or not get_tree().get_nodes_in_group("mothership_beacon").is_empty():
		_mothership_timer = 60 if crisis else 300
		return
	# Carriers are no longer planet-entry/exit gates. They remain occasional
	# repair / unit-recovery platforms only — but rush back during a crisis.
	_mothership_timer = 180 if crisis else 1800
	add_child(MothershipBeacon.new())

# A crisis worth calling the carrier in immediately: the carrier is being boarded
# (乗っ取り), the ship is locked out of firing by 慢心MAX (only an onsen soak fixes it), or
# the whole owned formation is badly wounded.
func _carrier_crisis() -> bool:
	if GameState.carrier_takeover or GameState.hubris_blocking_fire():
		return true
	var alive := 0
	var sum := 0.0
	for uid in GameState.collected_units:
		var l: float = GameState.unit_life[int(uid) - 1]
		if l > 0.0:
			alive += 1
			sum += l
	return alive > 0 and sum <= GameState.life_cap() * 0.4 * float(alive)

# Navigation distance: accrues while cruising high in open space (diving toward a
# star pauses it). When a leg fills, a boundary GATE crosses space; flying through
# it (SpaceGate) begins a natural crossfade into the next star system. The fade is
# driven here every frame via update_transition(). Mining banks extra distance
# (ResourceItem._collect), bringing the next gate sooner.
func _update_navigation() -> void:
	if GameState.is_zako_mode():
		return
	if GameState.god_phase > 0 or GameState.ending_cinematic:
		return   # the finale cosmos / ending crawl has no nav legs or boundary gate rings
	GameState.update_transition()
	# Finding a plate while a plain gate is ALREADY on screen used to leave that gate single
	# (the spawn path below only runs when no gate exists, and it's skipped entirely once a
	# gate is up). Result: no route choice, and crossing the lone gate wasted the plate. So
	# the moment the route is armed, swap any un-crossed plain gate(s) for the choice set.
	_upgrade_gate_to_route_choice()
	# Boost always decays (even mid-gate / off-band) so a grabbed lane fades out.
	GameState.nav_boost = maxf(0.0, GameState.nav_boost - GameState.NAV_BOOST_DECAY)
	if GameState.transitioning or GameState.gate_active:
		return  # gate is up / mid-transition: stop accruing until it's resolved
	if GameState.stage != "space" or GameState.in_transition() or GameState.arena_active:
		return
	# Final boss + ending: no boundary gates appear, and nav stops accruing entirely.
	# Title/intro also accrue nothing. The black-hole fight freezes nav too — the exit
	# gate is framed in by _update_blackhole only once the boss is dead.
	if GameState.final_phase != GameState.FINAL_NONE \
			or GameState.title_active or GameState.intro_active \
			or GameState.blackhole_active:
		return
	# A ridden boost lane banks distance at ANY altitude (lanes now appear low too).
	GameState.nav_distance += GameState.nav_boost * GameState.NAV_BOOST_GAIN
	# Base cruising accrues at ALL altitudes — EXCEPT while a star is displayed, when
	# the lower half of the alt gauge (below its midpoint) never accrues, at any time
	# (including climbing back out, where target_star is already cleared). Climb above
	# the midpoint to resume. "Star displayed" = a target-planet node exists.
	var star_shown := get_tree().get_first_node_in_group("target_planet") != null
	var nav_paused := star_shown and GameState.alt < GameState.nav_star_floor_alt()
	if not nav_paused:
		var hi_t := clampf((GameState.alt - GameState.GROUND_ALT) \
			/ (GameState.ALT_MAX - GameState.GROUND_ALT), 0.0, 1.0)
		GameState.nav_distance += GameState.NAV_RATE * lerpf(GameState.NAV_HI_BONUS, 1.0, hi_t)
	if GameState.nav_distance >= GameState.NAV_LEG \
			and get_tree().get_nodes_in_group("boundary_gate").is_empty():
		GameState.gate_active = true
		if GameState.route_armed:
			# Route unlocked → this gate is a side-by-side CHOICE (proceed vs keep exploring).
			_spawn_route_choice([GameState.route_proceed_kind(), "explore"])
		else:
			add_child(SpaceGate.new())

# A plate was found while a plain nav gate was already cruising space (or parked invisible
# while we dove to the star). That gate never offers the route choice, so replace any
# un-crossed plain gate with the side-by-side choice set — so a plate ALWAYS yields a choice,
# no re-mining needed. Runs even on the star surface; the new gates stay hidden until we climb
# back to space. No-op once a choice set is present (or no plain gate to upgrade).
func _upgrade_gate_to_route_choice() -> void:
	if not GameState.route_armed:
		return
	# Don't disturb an in-progress crossing/transition or special encounters.
	if GameState.transitioning or GameState.blackhole_active \
			or GameState.final_phase != GameState.FINAL_NONE:
		return
	var gates := get_tree().get_nodes_in_group("boundary_gate")
	if gates.is_empty():
		return  # none up yet — the normal spawn path will build the choice set
	var stale: Array = []
	for g in gates:
		if g.is_choice_gate():
			return  # already a choice set; nothing to do
		if not g.was_crossed():
			stale.append(g)
	if stale.is_empty():
		return  # only an already-crossed gate framing out — leave it
	for g in stale:
		g.queue_free()
	_spawn_route_choice([GameState.route_proceed_kind(), "explore"])

# Present a side-by-side set of choice gates (one per kind). They scroll down together;
# steer the ship (the LEAD) through whichever hoop you want — the chosen gate resolves and
# the rest vanish. Lanes auto-space across the play width, so 2 today / 3 later just works.
func _spawn_route_choice(kinds: Array) -> void:
	var n := kinds.size()
	if n <= 0:
		return
	# Wide lanes + smaller holes so there's a clear central "neutral" zone (you must lean
	# left/right to commit) and the rings read as distinct.
	var span := 1.7 if n <= 2 else 2.0     # outermost lane offset from centre
	var hole := 0.95 if n <= 2 else 0.72   # per-gate hole radius (kept < half the lane gap)
	for i in n:
		var slot_x := 0.0 if n == 1 else lerpf(-span, span, float(i) / float(n - 1))
		var g := SpaceGate.new()
		g.setup_choice(String(kinds[i]), slot_x, hole)
		add_child(g)
	GameState.gate_active = true
	# Early heads-up (English) so the choice is clear well before the gates arrive.
	get_tree().call_group("star_hud", "show_message", "GATE AHEAD - CHOOSE", _choice_hint(kinds))

# One-line English hint naming each lane left→right (matches the spawn order).
func _choice_hint(kinds: Array) -> String:
	var names := {"route": "ROUTE", "boss": "BOSS", "explore": "EXPLORE"}
	var parts: Array[String] = []
	for k in kinds:
		parts.append(Loc.t(String(names.get(String(k), String(k).to_upper()))))
	return " | ".join(parts)

# Carrier takeover event: fires periodically during normal space play. Announces
# itself and LOCKS the carrier's repair + new-unit pickup (handled in Mothership)
# until the player lands and clears the boarders on the deck (DeckWalkMode). While
# an event is active the countdown is frozen; it restarts once the event clears.
func _update_takeover_event() -> void:
	if GameState.stage != "space" or GameState.in_transition() or GameState.deck_walk \
			or GameState.title_active or GameState.intro_active or GameState.game_over \
			or GameState.ending_active or GameState.final_phase != GameState.FINAL_NONE \
			or GameState.god_phase > 0:
		return
	# The lab (カナ博士) rebuilds the hull over time, even mid-raid.
	GameState.tick_auto_repair()
	if GameState.carrier_takeover:
		# Hired mercs (ヒカリ商人) defend the carrier even if the player never returns —
		# they cut down boarders and absorb most of the hull drain. The boarders keep
		# wrecking what's left until repelled. (Drain pauses while you're on the deck.)
		var defended := GameState.tick_merc_defense()
		GameState.carrier_hull = maxf(0.0,
			GameState.carrier_hull - TAKEOVER_DRAIN * (1.0 - 0.85 * defended))
		if GameState.takeover_boarders <= 0:
			# Mercs (or the player) cleared the boarders → the raid is broken.
			GameState.carrier_takeover = false
			get_tree().call_group("star_hud", "show_message",
				"BOARDERS REPELLED",
				"MERCENARIES HELD THE CARRIER" if not GameState.mercs.is_empty() else "CARRIER SECURED")
		elif GameState.carrier_hull <= 0.0:
			GameState.carrier_takeover = false
			GameState.takeover_boarders = 0
			get_tree().call_group("star_hud", "show_message",
				"CARRIER LOST TO BOARDERS",
				"NO CARRIER SUPPORT UNTIL THE NEXT STAR SYSTEM")
		return
	_takeover_cd -= 1
	if _takeover_cd <= 0:
		_takeover_cd = randi_range(3000, 5000)   # next event ~50–83s after this one clears
		GameState.carrier_takeover = true
		GameState.takeover_boarders = randi_range(5, 8)
		# The boarding damages the hull → gives the player something to repair on the deck.
		GameState.carrier_hull = maxf(0.0, GameState.carrier_hull - randf_range(20.0, 35.0))
		if GameState.carrier_hull <= 0.0:
			get_tree().call_group("star_hud", "show_message",
				"CARRIER HULL DESTROYED",
				"NO CARRIER SUPPORT UNTIL THE NEXT STAR SYSTEM")
		else:
			get_tree().call_group("star_hud", "show_message",
				"WARNING: CARRIER BOARDED",
				"LAND & REPEL THEM - REPAIRS / NEW UNITS LOCKED")

# Summoned by a beacon the player flew into: the carrier frames in from above
# and scrolls down to be ridden.
func spawn_carrier() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var ship := Mothership.new()
	ship.ship_alt = GameState.ALT_MAX
	ship.auto_engage = false
	add_child(ship)
	var sz := get_viewport().get_visible_rect().size
	var ship_z := GameState.alt_to_z(ship.ship_alt)
	var depth: float = camera.global_position.z - ship_z
	var top_w := camera.project_position(Vector2(sz.x * 0.5, 0.0), depth)
	ship.global_position = Vector3((randf() - 0.5) * 1.0, top_w.y + 3.2, ship_z)

const FRONT_TURRET_HIT_R2 := 0.075   # HERO fire vs a ZAKO front turret (box half ~0.17 + bullet)
const HERO_HIT_R2 := 0.09            # ZAKO fire vs the HERO ship

func _check_collisions() -> void:
	var bullets := get_tree().get_nodes_in_group("bullets")
	var enemies := get_tree().get_nodes_in_group("enemies")
	var enemy_bullets := get_tree().get_nodes_in_group("enemy_bullets")
	var front_turrets := get_tree().get_nodes_in_group("enemy_front")
	# HERO's TERRAIN ATTACK can blast the ZAKO-built front terrain (only the HERO, not the ZAKO).
	var front_mgr: Node = null
	if not GameState.is_zako_mode():
		front_mgr = get_tree().get_first_node_in_group("enemy_front_mgr")
	_trim_nodes(bullets, MAX_PLAYER_BULLETS)
	_trim_nodes(enemy_bullets, MAX_ENEMY_BULLETS)
	var terrain := get_tree().get_first_node_in_group("planet_terrain")
	if terrain == null and GameState.stage == "space":
		terrain = get_tree().get_first_node_in_group("space_terrain")
	var terrain_checks := 0

	for b_node in bullets:
		var b := b_node as Node3D
		if b == null or not is_instance_valid(b) or b.is_queued_for_deletion():
			continue
		var bp: Vector3 = b.global_position
		var b_hits_lower: bool = b.get("hits_lower_alt") == true

		var can_check_terrain := true
		# Terrain-busting GERWALK bolts own their terrain interaction in Bullet._process
		# (plow through the breakable field, stop only on the arena's flank walls). Letting
		# try_block_hit also blast+free them here would kill the bolt on the first ground
		# block, so it could never reach across the floor.
		if b.get("breaks_terrain") == true:
			can_check_terrain = false
		if GameState.stage == "planet" and not (terrain is TargetPlanet) \
				and bp.z > PlanetTerrain.GROUND_Z + PlanetTerrain.B * 8.0:
			can_check_terrain = false
		if terrain != null and can_check_terrain and terrain.has_method("try_block_hit") \
				and terrain_checks < MAX_TERRAIN_BULLET_CHECKS:
			terrain_checks += 1
			var hit: Dictionary = terrain.call("try_block_hit", bp)
			if not hit.is_empty():
				b.queue_free()
				GameState.score += 10
				var bex := Explosion.new()
				bex.color = hit["color"]
				bex.count = int(hit.get("effect_count", 5))
				bex.strength = float(hit.get("effect_strength", 0.5))
				add_child(bex)
				bex.global_position = hit["pos"]
				if hit.get("chip", false):
					TsgAudio.block_chip()
				else:
					TsgAudio.block_break()
				if not hit.get("no_drop", false) and (terrain is TargetPlanet or randf() < 0.5):
					ResourceItem.spawn(self, hit)
				for extra_drop: Dictionary in hit.get("drops", []):
					ResourceItem.spawn(self, extra_drop)
				continue

		# HERO's TERRAIN ATTACK: blast the painted front terrain (land tiles, roads, structures…).
		if front_mgr != null:
			var fhit: Dictionary = front_mgr.call("try_block_hit", bp)
			if not fhit.is_empty():
				b.queue_free()
				GameState.score += 10
				var fex := Explosion.new()
				fex.color = fhit["color"]
				fex.count = int(fhit.get("effect_count", 6))
				fex.strength = float(fhit.get("effect_strength", 0.6))
				add_child(fex)
				fex.global_position = fhit["pos"]
				TsgAudio.block_break()
				continue

		# HERO fire vs the ZAKO's seeded front turrets (faction combat: the Hero arrives at the
		# battlefield the Zako built ahead and can tear it down). Turrets aren't Enemy nodes, so
		# they need their own hit test here.
		var struck_turret := false
		for tn in front_turrets:
			var tt := tn as Node3D
			if tt == null or not is_instance_valid(tt) or tt.is_queued_for_deletion():
				continue
			var tdx := bp.x - tt.global_position.x
			var tdy := bp.y - tt.global_position.y
			if tdx * tdx + tdy * tdy < FRONT_TURRET_HIT_R2:
				b.queue_free()
				_destroy_front_turret(tt)
				struck_turret = true
				break
		if struck_turret:
			continue

		for e_node in enemies:
			var e := e_node as Node3D
			if e == null or not is_instance_valid(e) or e.is_queued_for_deletion():
				continue
			if GameState.is_zako_mode() and e.has_meta("local_zako_unit"):
				continue
			if not _bullet_can_hit(b_hits_lower, e):
				continue
			var dx := bp.x - e.global_position.x
			var dy := bp.y - e.global_position.y
			var hit_r_v: Variant = e.get("hit_radius")
			var hit_r: float = float(hit_r_v) if hit_r_v != null else 0.09
			if dx * dx + dy * dy < hit_r * hit_r:
				b.queue_free()
				var hit_pos: Vector3 = e.global_position
				var hue: Variant = e.get("hue")
				var dmg_v: Variant = b.get("damage")
				var dmg: int = maxi(1, int(dmg_v) if dmg_v != null else 1)
				var source_uid: int = maxi(1, int(b.get("source_unit_id")))
				for di in dmg:
					TsgAudio.enemy_hit()
					if e.has_method("take_hit") and e.call("take_hit", source_uid):
						GameState.score += 100
						var mh: Variant = e.get("max_hp")
						GameState.add_exp(40 * (int(mh) if mh != null else 1))
						GameState.on_enemy_killed()   # feeds the 慢心 gauge
						_split_enemy(e, hit_pos, hue)
						_spawn_explosion(hit_pos, hue)
						TsgAudio.enemy_destroy()
						break
				break

	if GameState.autopilot != 0 or GameState.on_carrier \
			or GameState.in_transition() or GameState.arrive_lock:
		return  # mothership sequence or atmosphere transition: the player side is safe

	# --- Player-side hitboxes ---
	# Formation: every active unit has its own hitbox and life.
	# Combined: only Unit1, with a radius that grows with the combined size.
	var s: float = unit1.scale.x
	var targets: Array[Dictionary] = []
	if GameState.sep_t > 0.5:
		targets.append({"uid": 1, "node": unit1, "r": s * 0.12})
		for uid in GameState.collected_units:
			if uid == 1 or uid in GameState.docked_units:
				continue
			var u := _unit_node(uid)
			if u != null:
				targets.append({"uid": uid, "node": u, "r": s * 0.13})
	else:
		targets.append({"uid": 1, "node": unit1,
			"r": s * (0.11 + 0.04 * (GameState.formation_count - 1))})

	# ZAKO prototype: the ZAKO IS the active "player" (px/py) and it fires enemy bullets, so the
	# standard enemy-bullet→player loop below would make the ZAKO shoot itself. Instead resolve the
	# ZAKO's fire against the HERO (the auto-piloting opponent), then skip the self-hit pass.
	if GameState.is_zako_mode():
		_resolve_zako_fire_vs_hero(enemy_bullets)
		enemy_bullets = []
	for eb_node in enemy_bullets:
		var eb := eb_node as Node3D
		if eb == null or not is_instance_valid(eb) or eb.is_queued_for_deletion():
			continue
		if not eb.call("is_in_player_range"):
			continue
		# Golden robot: even heavy enemy fire is burned away the instant it reaches the
		# robot's wide aura, so nothing lands during the 10 s power.
		if GameState.golden_active:
			var bp := Vector2(eb.global_position.x, eb.global_position.y)
			if bp.distance_squared_to(Vector2(GameState.px, GameState.py)) < 1.7:
				eb.queue_free()
				continue
		var ep := Vector2(eb.global_position.x, eb.global_position.y)
		for t in targets:
			if _unit_inv[int(t["uid"]) - 1] > 0:
				continue
			var tn: Node3D = t["node"]
			var rr := float(t["r"]) + 0.03
			if ep.distance_squared_to(Vector2(tn.global_position.x, tn.global_position.y)) < rr * rr:
				eb.queue_free()
				_damage_unit(int(t["uid"]), 25.0, tn)
				break

	for e_node in enemies:
		var e := e_node as Node3D
		if e == null or not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		if not e.has_method("is_in_player_range") or not e.call("is_in_player_range"):
			continue
		var ep := Vector2(e.global_position.x, e.global_position.y)
		for t in targets:
			if _unit_inv[int(t["uid"]) - 1] > 0:
				continue
			var tn: Node3D = t["node"]
			var rr := float(t["r"]) + 0.04
			if ep.distance_squared_to(Vector2(tn.global_position.x, tn.global_position.y)) < rr * rr:
				_split_enemy(e, e.global_position, e.get("hue"))
				_spawn_explosion(e.global_position, e.get("hue"))
				TsgAudio.enemy_destroy()
				GameState.on_enemy_killed()   # feeds the 慢心 gauge
				e.queue_free()
				_damage_unit(int(t["uid"]), 34.0, tn)
				break

# HERO bullet destroyed a ZAKO front turret: burst, score, and drop it from the persistent
# world front so it stays gone for the rest of the run.
func _destroy_front_turret(t: Node3D) -> void:
	GameState.score += 150
	var ex := Explosion.new()
	ex.color = Color(1.0, 0.45, 0.14)
	ex.count = 16
	ex.strength = 1.4
	add_child(ex)
	ex.global_position = t.global_position
	TsgAudio.enemy_destroy()
	var mgr := get_tree().get_first_node_in_group("enemy_front_mgr")
	if mgr != null and mgr.has_method("remove_turret"):
		mgr.call("remove_turret", t)   # strips the {x,y} data entry
	t.queue_free()

# ZAKO prototype faction hit: the ZAKO (active player) fires EnemyBullets at the HERO (unit1,
# auto-piloting toward the ZAKO). A bullet only connects when it reaches the HERO's altitude band
# (dodging by altitude is the tactical point) — then it bursts on the HERO and is consumed.
func _resolve_zako_fire_vs_hero(bullets: Array) -> void:
	if unit1 == null or not is_instance_valid(unit1):
		return
	var hp := Vector2(GameState.hero_pos.x, GameState.hero_pos.y)
	var hero_alt_n := clampf(GameState.hero_alt / GameState.ALT_MAX, 0.0, 1.0)
	var band := GameState.ALT_ALIGN_BAND / GameState.ALT_MAX
	for eb_node in bullets:
		var eb := eb_node as Node3D
		if eb == null or not is_instance_valid(eb) or eb.is_queued_for_deletion():
			continue
		var eb_alt_v: Variant = eb.get("alt")
		var eb_alt: float = float(eb_alt_v) if eb_alt_v != null else hero_alt_n
		if absf(eb_alt - hero_alt_n) > band:
			continue                                  # wrong altitude → passes the HERO by
		if Vector2(eb.global_position.x, eb.global_position.y).distance_squared_to(hp) < HERO_HIT_R2:
			eb.queue_free()
			GameState.score += 20
			var ex := Explosion.new()
			ex.color = Color(0.6, 0.85, 1.0)
			ex.count = 10
			ex.strength = 1.0
			add_child(ex)
			ex.global_position = unit1.global_position
			TsgAudio.enemy_hit()

func _trim_nodes(nodes: Array, max_count: int) -> void:
	var overflow := nodes.size() - max_count
	if overflow <= 0:
		return
	for i in overflow:
		var n := nodes[i] as Node
		if n != null and is_instance_valid(n) and not n.is_queued_for_deletion():
			n.queue_free()

# A unit took a hit: burst, invincibility, life loss. Unit1 at 0 = game over
# (refilled under debug_no_death); any other unit at 0 is destroyed.
func _damage_unit(uid: int, amount: float, node: Node3D) -> void:
	# Golden robot (the 10 s G-icon power) is fully invincible — it shrugs off every
	# blow with no damage and no flinch.
	if GameState.golden_active:
		return
	_unit_inv[uid - 1] = 180 if uid == 1 else 120
	var ex := Explosion.new()
	ex.color = Color(1.0, 0.75, 0.4)
	ex.count = 12
	ex.strength = 1.3
	add_child(ex)
	ex.global_position = node.global_position

	# Spread formation soaks hits: Unit1 in a SEPARATED formation takes only a share of
	# the blow (÷ unit count). Solo (1 unit) or COMBINED (one body) = full damage.
	if uid == 1 and GameState.sep_t > 0.5 and GameState.formation_count > 1:
		amount /= float(GameState.formation_count)
	GameState.unit_life[uid - 1] -= amount
	if GameState.unit_life[uid - 1] > 0.0:
		return
	if uid == 1:
		if GameState.debug_no_death:
			GameState.unit_life[0] = GameState.life_cap()
			return
		GameState.unit_life[0] = 0.0
		GameState.game_over = true
		unit1.visible = true
	else:
		GameState.unit_life[uid - 1] = 0.0
		var bex := Explosion.new()
		bex.color = PowerOrb.UNIT_COLORS.get(uid, Color.WHITE)
		bex.count = 18
		bex.strength = 1.6
		add_child(bex)
		bex.global_position = node.global_position
		$FormationManager.lose_unit(uid)

func _bullet_can_hit(hits_lower: bool, e: Node3D) -> bool:
	# ZAKO prototype: HERO fire hits the opponent ZAKO only when their altitudes are aligned within
	# the same band the HUD marker uses (±ALT_ALIGN_BAND) — matching the red ◯ "aligned" cue, so
	# the player must close the altitude gap to land shots (GENESIS's fixed ±12 band is too tight).
	if GameState.is_zako_prototype_mode() and e.is_in_group("zako_units"):
		var za_v: Variant = e.get("alt")
		var za: float = float(za_v) * GameState.ALT_MAX if za_v != null else GameState.alt
		return absf(GameState.alt - za) <= GameState.ALT_ALIGN_BAND
	if not e.has_method("is_in_player_range"):
		return true
	if e.call("is_in_player_range"):
		return true
	if hits_lower:
		var e_alt: Variant = e.get("alt")
		if e_alt != null:
			return float(e_alt) * GameState.ALT_MAX < GameState.alt - 5.0
	return false

var _powerup_rounds: int = 0

# When enough EXP is banked, spawn one numbered orb per upgradeable unit at
# random on-screen spots. The player picks ONE — the rest vanish (see PowerOrb).
func _check_powerup() -> void:
	if GameState.exp_points < GameState.exp_next:
		return
	if get_tree().get_nodes_in_group("power_orbs").size() > 0:
		return
	var eligible: Array[int] = []
	for uid in GameState.collected_units:
		if GameState.unit_levels[uid - 1] < 5:
			eligible.append(uid)
	if eligible.is_empty():
		return
	GameState.exp_points -= GameState.exp_next
	_powerup_rounds += 1
	GameState.exp_next = 500 + 300 * _powerup_rounds
	_spawn_power_orbs(eligible)

# Orbs frame in from the top of the screen, each in its own lane
# (screen width / 5, lane N = unit N) so they never overlap and the player
# can pick one deliberately by flying into its lane.
func _spawn_power_orbs(eligible: Array[int]) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var sz := get_viewport().get_visible_rect().size
	var player_z := GameState.alt_to_z(GameState.alt)
	var depth: float = camera.global_position.z - player_z
	# On the star surface the ship's x is clamped (edge-drive), so the outermost
	# lanes (units 1 & 5) sat past the reachable edge and couldn't be collected.
	# Pull all 5 lanes inward there. Space keeps the full 0.1–0.9 spread.
	var on_sphere := GameState.stage == "planet" \
		and get_tree().get_first_node_in_group("planet_terrain") is TargetPlanet
	var lo_frac := 0.20 if on_sphere else 0.1
	var hi_frac := 0.80 if on_sphere else 0.9
	for uid in eligible:
		var x_frac := lerpf(lo_frac, hi_frac, (float(uid) - 1.0) / 4.0)
		var sp := Vector2(sz.x * x_frac, -60.0)
		var wp := camera.project_position(sp, depth)
		var orb := PowerOrb.new()
		orb.unit_id = uid
		add_child(orb)
		orb.global_position = Vector3(wp.x, wp.y, player_z)

# A dying splitter bursts into a handful of fast shards (see EnemySpawner).
func _split_enemy(e: Node3D, pos: Vector3, hue: Variant) -> void:
	if str(e.get("enemy_type")) != "splitter":
		return
	var sp := get_node_or_null("EnemySpawner")
	if sp == null or not sp.has_method("spawn_shards"):
		return
	var alt_v: Variant = e.get("alt")
	sp.call("spawn_shards", pos, float(hue) if hue != null else 140.0,
		float(alt_v) if alt_v != null else 0.5)

func _spawn_explosion(pos: Vector3, hue: Variant) -> void:
	var ex := Explosion.new()
	if hue != null:
		ex.color = Color.from_hsv(float(hue) / 360.0, 0.7, 1.0)
	# Smaller enemy-death burst so the screen stays readable when kills pile up.
	ex.count = 10
	ex.strength = 0.5
	add_child(ex)
	ex.global_position = pos
