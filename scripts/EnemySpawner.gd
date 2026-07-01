extends Node3D

@export var enemy_scene: PackedScene
const SpaceDreadnoughtScene := preload("res://scripts/SpaceDreadnought.gd")

# Ground forces per planet theme — tanks roll on open worlds, radar masts and
# depots cluster around the built-up ones, gun turrets are everywhere.
const GROUND_TYPES := ["turret", "tank", "radar", "depot"]
const GROUND_SETS := {
	"VERDANT":  ["tank", "tank", "turret", "radar", "depot"],
	"OCEAN":    ["turret", "turret", "depot"],
	"DESERT":   ["tank", "tank", "turret", "depot"],
	"ICE":      ["radar", "turret", "tank"],
	"VOLCANIC": ["turret", "tank"],
	"GAS":      ["turret"],
	"CYBER":    ["tank", "radar", "depot", "turret", "turret"],
	# Abyss interiors and the boss star
	"CAVE":     ["turret"],
	"BASE":     ["turret", "tank", "radar", "depot", "depot"],
	"TEMPLE":   ["turret", "turret", "depot"],
	"LAVACAVE": ["turret", "tank"],
	"LAKE":     ["turret", "radar"],
	"RUINS":    ["turret", "depot", "radar"],
	"BOSS":     ["turret", "tank", "radar"],
}

# Boss schedule: the OMEGA CORE planet spawns the final boss after this long.
const BOSS_DELAY := 800
const GUARDIAN_MIN_DEPTH := 0.35
const WAVE_CHANCE := 0.76
const SPACE_DREAD_DELAY := 3000

var _spawn_timer: int = 0
var _spawn_interval: int = 80
var _stage_key: String = ""
var _stage_frames: int = 0
var _boss_spawned: bool = false
var _space_dread_timer: int = 1600
var _combiner_timer: int = 900

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			GameState.debug_endless_spawn = not GameState.debug_endless_spawn

func _process(_delta: float) -> void:
	if GameState.game_over or GameState.in_transition() or GameState.motion_debug:
		return
	if GameState.suppress_genesis_progression() or GameState.is_zako_mode():
		return
	# Boss arena = a clean duel: Main spawns the PolygonGuardian itself, so suppress
	# the normal rabble/boss spawners here.
	if GameState.arena_active:
		return
	# Final boss (space) + ending = a clean duel against THE GENESIS: no rabble at all.
	# Title screen + intro takeoff are also enemy-free. The black-hole boss system
	# stops normal spawns too — only the boss and its joints are present.
	if GameState.final_phase != GameState.FINAL_NONE \
			or GameState.title_active or GameState.intro_active \
			or GameState.blackhole_active or GameState.god_phase > 0:
		return
	var low_orbit_star := GameState.stage == "planet" \
			and get_tree().get_first_node_in_group("planet_terrain") is TargetPlanet

	# Per-stage clock (resets on every stage/biome change, and on each descent into
	# / return from the underground) drives the bosses.
	var sk := GameState.stage + "/" + GameState.planet_biome \
		+ ("/UG" if GameState.underground else "")
	if sk != _stage_key:
		_stage_key = sk
		_stage_frames = 0
		_boss_spawned = false
	_stage_frames += 1
	if not _boss_spawned:
		var ug_depth := clampf((GameState.GROUND_ALT - GameState.alt) / GameState.GROUND_ALT, 0.0, 1.0)
		if GameState.underground and GameState.underground_boss_unlocked \
				and not GameState.underground_boss_defeated \
				and ug_depth >= GUARDIAN_MIN_DEPTH:
			_boss_spawned = true
			GameState.underground_boss_area = true
			GameState.underground_biome = "BASE"
			_spawn_polygon_guardian()
		elif GameState.stage == "planet" and GameState.planet_biome == "BOSS" \
				and not GameState.game_clear and _stage_frames > BOSS_DELAY:
			_boss_spawned = true
			_spawn_boss("boss")
	if GameState.stage == "space" and not _space_dread_alive() and not _descending_into_star():
		_space_dread_timer -= 1
		if _space_dread_timer <= 0:
			_space_dread_timer = SPACE_DREAD_DELAY + randi() % 2400
			if _enemy_count() <= 16:
				_spawn_space_dreadnought()
	else:
		_space_dread_timer = mini(_space_dread_timer, 900)
	if GameState.stage == "space" and not _boss_alive() and not _space_dread_alive() \
			and not _combiner_alive() and not _descending_into_star():
		_combiner_timer -= 1
		if _combiner_timer <= 0:
			_combiner_timer = 1500 + randi() % 1200
			if _enemy_count() <= 14:
				_spawn_combiner()
	else:
		_combiner_timer = mini(_combiner_timer, 900)

	_spawn_timer += 1
	if _spawn_timer >= _spawn_interval:
		_spawn_timer = 0
		var d := GameState.difficulty()
		if GameState.debug_endless_spawn:
			_spawn_interval = 18
		else:
			# Spawn faster as the player grows: 60-110f at start → 18-30f at full power.
			_spawn_interval = int(lerpf(85.0 + randf() * 55.0, 34.0 + randf() * 18.0, d))
			if GameState.underground:
				var depth_t := clampf((GameState.GROUND_ALT - GameState.alt) / GameState.GROUND_ALT, 0.0, 1.0)
				_spawn_interval = int(float(_spawn_interval) * lerpf(1.05, 0.75, depth_t))
			# A live radar mast calls in extra raiders — destroy it to calm the sky.
			if GameState.stage != "space" and not low_orbit_star and _radar_alive():
				_spawn_interval = int(_spawn_interval * 0.75)
			if GameState.stage == "space" or low_orbit_star:
				_spawn_interval = int(float(_spawn_interval) * 0.72)
			elif GameState.stage == "planet" and GameState.surface_festival_planet and not GameState.underground:
				_spawn_interval = int(float(_spawn_interval) * 0.68)
			# A boss on screen owns the fight: the rabble backs off.
			if _boss_alive():
				_spawn_interval *= 2
		if _enemy_count() < _enemy_cap():
			if not _boss_alive() and randf() < WAVE_CHANCE:
				_spawn_wave()
			else:
				_spawn_enemy()
		# At higher difficulty, sometimes spawn an extra enemy in the same wave.
		var extra_chance := d * 0.22
		if GameState.underground:
			extra_chance += clampf((GameState.GROUND_ALT - GameState.alt) / GameState.GROUND_ALT, 0.0, 1.0) * 0.08
		if randf() < extra_chance and _enemy_count() < _enemy_cap():
			_spawn_enemy()

func _enemy_count() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			n += 1
	return n

func _descending_into_star() -> bool:
	var tp := get_tree().get_first_node_in_group("target_planet") as TargetPlanet
	return tp != null and GameState.target_star != "" and tp.star_name == GameState.target_star

func _enemy_cap() -> int:
	if _boss_alive():
		return 2
	if GameState.underground:
		return 12
	var low_orbit_star := GameState.stage == "planet" \
			and get_tree().get_first_node_in_group("planet_terrain") is TargetPlanet
	if GameState.stage == "space" or low_orbit_star:
		return 22
	if GameState.surface_festival_planet:
		return 22
	return 18

func _view_bounds(depth: float = 4.0) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var sz := get_viewport().get_visible_rect().size
	var top_w := camera.project_position(Vector2(sz.x * 0.5, 0.0), depth)
	var bot_w := camera.project_position(Vector2(sz.x * 0.5, sz.y), depth)
	var lft_w := camera.project_position(Vector2(0.0, sz.y * 0.5), depth)
	var rgt_w := camera.project_position(Vector2(sz.x, sz.y * 0.5), depth)
	return {
		"top": top_w.y + 0.15,
		"bottom": bot_w.y - 0.15,
		"left": lft_w.x - 0.15,
		"right": rgt_w.x + 0.15,
	}

func _spawn_wave() -> void:
	if enemy_scene == null:
		return
	var b := _view_bounds()
	if b.is_empty():
		return
	var cap_left := _enemy_cap() - _enemy_count()
	if cap_left <= 0:
		return
	var d := GameState.difficulty()
	var top_y: float = b["top"]
	var bot_y: float = b["bottom"]
	var left_x: float = b["left"]
	var right_x: float = b["right"]
	var center_x := (left_x + right_x) * 0.5
	var player_alt_n := GameState.alt / GameState.ALT_MAX
	var g_n := GameState.GROUND_ALT / GameState.ALT_MAX
	var lo := 0.0 if GameState.underground else g_n
	var hi := g_n if GameState.underground else 1.0
	var theme_wave_chance := 0.72 if GameState.surface_festival_planet else 0.48
	# Star-specific (biome-themed) enemies mix into the generic waves: on ANY planet
	# surface (incl. the TargetPlanet low-orbit star, which used to be excluded) AND
	# while approaching/leaving a star in space — so the star's own enemies fade in
	# during the descent and out during the climb instead of switching all at once
	# at ALT760.
	var theme_biome := ""
	if GameState.stage == "planet" and not GameState.underground:
		theme_biome = GameState.planet_biome
	elif GameState.stage == "space":
		var tp := get_tree().get_first_node_in_group("target_planet") as TargetPlanet
		var near_t := clampf((GameState.ALT_MAX - GameState.alt) \
			/ (GameState.ALT_MAX - GameState.GROUND_ALT), 0.0, 1.0)
		if tp != null and near_t > 0.2:
			theme_biome = tp.biome
			theme_wave_chance *= smoothstep(0.2, 0.95, near_t)  # ramp with proximity
	if theme_biome != "" and randf() < theme_wave_chance:
		if _spawn_planet_theme_wave(cap_left, top_y, bot_y, left_x, right_x, center_x,
				player_alt_n, lo, hi, d, theme_biome):
			return
	# Designed "zoo" set (corkscrew squadron / stoneface / bacura / splitcannon): mix in
	# occasionally across space + surface so they show up in normal play.
	if not GameState.underground and randf() < 0.40:
		if _spawn_special_wave(cap_left, top_y, left_x, right_x, center_x, player_alt_n, lo, hi):
			return
	var wave := randi() % (7 if GameState.underground else 31)
	match wave:
		0:
			# V formation: readable Xevious-style wave, aimed to be shot down in order.
			var n := mini(5, cap_left)
			for i in n:
				var off := float(i) - float(n - 1) * 0.5
				_spawn_air("invader",
					Vector3(center_x + off * 0.34, top_y + absf(off) * 0.18, 0.0),
					Vector2(off * 0.0008, -(0.010 + d * 0.004)),
					clampf(player_alt_n + randf_range(-0.04, 0.04), lo, hi))
		1:
			# Horizontal sweep: Star Soldier popcorn line.
			var n := mini(6, cap_left)
			for i in n:
				var typ := "weaver" if (i % 2) == 0 else "zigzag"
				_spawn_air(typ,
					Vector3(lerpf(left_x + 0.3, right_x - 0.3, float(i) / maxf(float(n - 1), 1.0)),
						top_y + randf_range(0.0, 0.22), 0.0),
					Vector2(0.010 + d * 0.004, -(0.007 + d * 0.003)),
					clampf(player_alt_n + randf_range(-0.07, 0.03), lo, hi))
		2:
			# Side pincer from both edges.
			var n := mini(4, cap_left)
			for i in n:
				var side := -1.0 if (i % 2) == 0 else 1.0
				_spawn_air("drifter",
					Vector3(left_x if side < 0.0 else right_x,
						lerpf(bot_y + 0.35, top_y - 0.25, float(i) / maxf(float(n - 1), 1.0)), 0.0),
					Vector2(-side * (0.011 + d * 0.004), -(0.004 + d * 0.002)),
					clampf(player_alt_n + randf_range(-0.10, 0.06), lo, hi))
		3:
			# Sniper escort: one charger with two small guards.
			var n := mini(3, cap_left)
			for i in n:
				var typ := "sniper" if i == 1 else ("shooter" if i == 0 else "tracker")
				var off := float(i - 1)
				_spawn_air(typ,
					Vector3(center_x + off * 0.42, top_y + absf(off) * 0.16, 0.0),
					Vector2(0.0, -0.004 if typ == "sniper" else 0.008),
					clampf(player_alt_n + randf_range(-0.06, 0.06), lo, hi))
		4:
			# Low hunters: stronger underground/deep pressure without many nodes.
			var n := mini(3 + int(d > 0.45), cap_left)
			for i in n:
				var typ := "diver" if i == 0 else "hunter"
				_spawn_air(typ,
					Vector3(lerpf(left_x + 0.4, right_x - 0.4, randf()), top_y + float(i) * 0.18, 0.0),
					Vector2(0.0, -0.003),
					lerpf(lo + 0.04, minf(hi, player_alt_n), randf()))
		5:
			# Galaga-style lower-layer climb: a fan rises from below toward the player.
			var n := mini(6, cap_left)
			for i in n:
				var off := float(i) - float(n - 1) * 0.5
				_spawn_air("climber",
					Vector3(GameState.px + off * 0.34, bot_y - 0.35 - absf(off) * 0.08, 0.0),
					Vector2(-off * 0.0015, 0.010 + d * 0.004),
					clampf(player_alt_n - randf_range(0.10, 0.22), lo, hi))
		6:
			# Twin swoop: two mirrored hooks cross the playfield like classic arcade bugs.
			var n := mini(6, cap_left)
			for i in n:
				var side := -1.0 if (i % 2) == 0 else 1.0
				var lane := float(i / 2)
				_spawn_air("swooper",
					Vector3((left_x - 0.25) if side < 0.0 else (right_x + 0.25),
						top_y - 0.10 + lane * 0.24, 0.0),
					Vector2(-side * (0.017 + d * 0.004), -(0.004 + lane * 0.001)),
					clampf(player_alt_n + randf_range(-0.05, 0.08), lo, hi))
		7:
			# Star Force-style vertical columns: two lanes stream in, then peel inward.
			var n := mini(8, cap_left)
			for i in n:
				var lane_side := -1.0 if i < n / 2 else 1.0
				var rank := float(i % max(1, n / 2))
				_spawn_air("zigzag",
					Vector3(center_x + lane_side * 0.62, top_y + rank * 0.22, 0.0),
					Vector2(-lane_side * (0.004 + d * 0.002), -(0.012 + d * 0.004)),
					clampf(player_alt_n + randf_range(-0.04, 0.04), lo, hi))
		8:
			# Crescent ambush: lower enemies arc up in a shallow U around the ship.
			var n := mini(7, cap_left)
			for i in n:
				var t := float(i) / maxf(float(n - 1), 1.0)
				var a := lerpf(PI * 0.12, PI * 0.88, t)
				_spawn_air("climber",
					Vector3(GameState.px + cos(a) * 1.35, bot_y - 0.25 + sin(a) * 0.28, 0.0),
					Vector2(-cos(a) * 0.006, 0.011 + d * 0.003),
					clampf(player_alt_n - randf_range(0.08, 0.20), lo, hi))
		9:
			# Escort diamond: hard center shooter protected by fast popcorn.
			var n := mini(5, cap_left)
			for i in n:
				var off := Vector2.ZERO
				match i:
					1:
						off = Vector2(-1.0, 1.0)
					2:
						off = Vector2(1.0, 1.0)
					3:
						off = Vector2(-1.0, 2.0)
					4:
						off = Vector2(1.0, 2.0)
				var typ := "shooter" if i == 0 else "invader"
				_spawn_air(typ,
					Vector3(center_x + off.x * 0.34, top_y + off.y * 0.24, 0.0),
					Vector2(off.x * 0.001, -(0.010 + d * 0.004)),
					clampf(player_alt_n + randf_range(-0.04, 0.05), lo, hi))
		10:
			# Side-to-bottom rake: enemies enter high from a side, then dive toward the lower lane.
			var n := mini(5, cap_left)
			var side := -1.0 if randf() < 0.5 else 1.0
			for i in n:
				_spawn_air("swooper",
					Vector3((left_x - 0.35) if side < 0.0 else (right_x + 0.35),
						top_y + float(i) * 0.18, 0.0),
					Vector2(-side * (0.018 + d * 0.004), -(0.006 + float(i) * 0.001)),
					clampf(player_alt_n - randf_range(0.02, 0.14), lo, hi))
		11:
			# Color-lock escort: only the matching unit damages the core.
			if GameState.stage != "space":
				_spawn_enemy()
				return
			var uid := _owned_unit_for_guard()
			if uid == 0:
				_spawn_enemy()
				return
			var n := mini(3, cap_left)
			for i in n:
				var off := float(i) - float(n - 1) * 0.5
				var typ := "unit_guard_%d" % uid if i == 1 else "tracker"
				_spawn_air(typ,
					Vector3(center_x + off * 0.42, top_y + absf(off) * 0.18, 0.0),
					Vector2(off * 0.001, -(0.008 + d * 0.003)),
					clampf(player_alt_n + randf_range(-0.04, 0.05), lo, hi))
		12:
			# Alternating arcade braid: two recognizable enemy families cross through each other.
			var n := mini(8, cap_left)
			for i in n:
				var side := -1.0 if (i & 1) == 0 else 1.0
				var typ := "weaver" if i < n / 2 else "swooper"
				_spawn_air(typ,
					Vector3(center_x + side * (0.28 + float(i / 2) * 0.20),
						top_y + float(i / 2) * 0.18, 0.0),
					Vector2(-side * (0.010 + d * 0.004), -(0.010 + d * 0.003)),
					clampf(player_alt_n + randf_range(-0.05, 0.06), lo, hi))
		13:
			# Spear charge: thin blade ships line up, pause, then dive at the player.
			var n := mini(5, cap_left)
			for i in n:
				var off := float(i) - float(n - 1) * 0.5
				_spawn_air("blade",
					Vector3(center_x + off * 0.34, top_y + absf(off) * 0.10, 0.0),
					Vector2(off * 0.0006, -(0.005 + d * 0.002)),
					clampf(player_alt_n + randf_range(-0.03, 0.05), lo, hi))
		14:
			# Caster with pods: a slow ring-shooter protected by small escorts.
			var n := mini(5, cap_left)
			for i in n:
				var off := float(i) - float(n - 1) * 0.5
				var typ := "caster" if i == n / 2 else "pod"
				_spawn_air(typ,
					Vector3(center_x + off * 0.30, top_y + absf(off) * 0.16, 0.0),
					Vector2(off * 0.0008, -(0.006 + d * 0.002)),
					clampf(player_alt_n + randf_range(-0.05, 0.05), lo, hi))
		15:
			# Pod curtain: small enemies that fire paired shots while weaving.
			var n := mini(7, cap_left)
			for i in n:
				var t2 := float(i) / maxf(float(n - 1), 1.0)
				_spawn_air("pod",
					Vector3(lerpf(left_x + 0.25, right_x - 0.25, t2),
						top_y + sin(t2 * TAU) * 0.16, 0.0),
					Vector2((t2 - 0.5) * 0.004, -(0.007 + d * 0.003)),
					clampf(player_alt_n + randf_range(-0.08, 0.06), lo, hi))
		16:
			# Classic invader block: instantly readable arcade silhouettes.
			var n := mini(8, cap_left)
			for i in n:
				var col := float(i % 4) - 1.5
				var row := float(i / 4)
				_spawn_air("classic_invader",
					Vector3(center_x + col * 0.34, top_y + row * 0.22, 0.0),
					Vector2((0.006 + d * 0.002) * (-1.0 if row < 0.5 else 1.0),
						-(0.007 + d * 0.003)),
					clampf(player_alt_n + randf_range(-0.04, 0.05), lo, hi))
		17:
			# Saucer patrol: glossy UFOs drift slowly, then throw ring shots.
			var n := mini(5, cap_left)
			for i in n:
				var off := float(i) - float(n - 1) * 0.5
				_spawn_air("saucer",
					Vector3(center_x + off * 0.42, top_y + sin(float(i)) * 0.14, 0.0),
					Vector2(off * 0.0009, -(0.005 + d * 0.002)),
					clampf(player_alt_n + randf_range(-0.06, 0.07), lo, hi))
		18:
			# Creature mix: crab pincers and manta gliders cross at different speeds.
			var n := mini(6, cap_left)
			for i in n:
				var side := -1.0 if (i & 1) == 0 else 1.0
				var typ := "crab" if i < 3 else "manta"
				_spawn_air(typ,
					Vector3(center_x + side * (0.26 + float(i / 2) * 0.22),
						top_y + float(i / 2) * 0.18, 0.0),
					Vector2(-side * (0.007 + d * 0.003), -(0.007 + d * 0.003)),
					clampf(player_alt_n + randf_range(-0.07, 0.05), lo, hi))
		19:
			# Fighter squadron: player-like block fighters sweep in fast and fire bursts.
			var n := mini(7, cap_left)
			for i in n:
				var off := float(i) - float(n - 1) * 0.5
				_spawn_air("fighter",
					Vector3(center_x + off * 0.30, top_y + absf(off) * 0.08, 0.0),
					Vector2(off * 0.0012, -(0.017 + d * 0.006)),
					clampf(player_alt_n + randf_range(0.03, 0.12), lo, hi))
		20:
			# Metallic toroid chain: chunky rings drift like armored Xevious targets.
			var n := mini(8, cap_left)
			for i in n:
				var off := float(i) - float(n - 1) * 0.5
				_spawn_air("toroid",
					Vector3(center_x + off * 0.30, top_y + float(i % 3) * 0.15, 0.0),
					Vector2(off * 0.0009, -(0.011 + d * 0.004)),
					clampf(player_alt_n + randf_range(0.06, 0.18), lo, hi))
		21:
			# Ribbon swarm: a dense line of wisps weaving down in a sine ribbon.
			var n := mini(10, cap_left)
			for i in n:
				var t2 := float(i) / maxf(float(n - 1), 1.0)
				_spawn_air("wisp",
					Vector3(lerpf(left_x + 0.2, right_x - 0.2, t2),
						top_y + 0.10 + sin(t2 * TAU) * 0.10, 0.0),
					Vector2((t2 - 0.5) * 0.006, -(0.012 + d * 0.004)),
					clampf(player_alt_n + randf_range(-0.06, 0.06), lo, hi))
		22:
			# Rosette: orbiters share a common drift lane, circling as they descend.
			var n := mini(6, cap_left)
			for i in n:
				var ang := TAU * float(i) / float(maxi(n, 1))
				_spawn_air("orbiter",
					Vector3(center_x + cos(ang) * 0.30, top_y + 0.25 + sin(ang) * 0.20, 0.0),
					Vector2(0.0, -(0.007 + d * 0.003)),
					clampf(player_alt_n + randf_range(-0.05, 0.05), lo, hi))
		23:
			# Splitter vanguard: shoot them and the screen fills with shards.
			var n := mini(4, cap_left)
			for i in n:
				var off := float(i) - float(n - 1) * 0.5
				_spawn_air("splitter",
					Vector3(center_x + off * 0.46, top_y + absf(off) * 0.16, 0.0),
					Vector2(off * 0.0008, -(0.008 + d * 0.003)),
					clampf(player_alt_n + randf_range(-0.05, 0.05), lo, hi))
		24:
			# Lancer charge: a line forms up, then dashes at the player in a ripple.
			var n := mini(5, cap_left)
			for i in n:
				var off := float(i) - float(n - 1) * 0.5
				_spawn_air("lancer",
					Vector3(center_x + off * 0.36, top_y + absf(off) * 0.10, 0.0),
					Vector2(0.0, -(0.005 + d * 0.002)),
					clampf(player_alt_n + randf_range(-0.04, 0.05), lo, hi))
		25:
			# Mirror formation: symmetric pairs sweep in and breathe in unison.
			var n := mini(6, cap_left)
			for i in n:
				var side := -1.0 if (i & 1) == 0 else 1.0
				var rank := float(i / 2)
				_spawn_air("mirror",
					Vector3(center_x + side * (0.30 + rank * 0.22), top_y + rank * 0.20, 0.0),
					Vector2(-side * (0.005 + d * 0.002), -(0.009 + d * 0.003)),
					clampf(player_alt_n + randf_range(-0.05, 0.06), lo, hi))
		26:
			# Ghost blobs: soft yellow monsters wobble down in a loose pack.
			var n := mini(6, cap_left)
			for i in n:
				var off := float(i) - float(n - 1) * 0.5
				_spawn_air("ghost",
					Vector3(center_x + off * 0.26, top_y + absf(off) * 0.12, 0.0),
					Vector2(off * 0.0012, -(0.008 + d * 0.003)),
					clampf(player_alt_n + randf_range(-0.05, 0.06), lo, hi))
		27:
			# Quad-ring shuriken: a hard snake chain frames in from the side.
			var n := mini(8, cap_left)
			var side := -1.0 if randf() < 0.5 else 1.0
			var entry_x := left_x - 0.45 if side < 0.0 else right_x + 0.45
			for i in n:
				var rank := float(i)
				_spawn_air("quad_ring",
					Vector3(entry_x - side * rank * 0.18, GameState.py + 0.45 - rank * 0.13, 0.0),
					Vector2(-side * (0.018 + d * 0.005), randf_range(-0.002, 0.002)),
					clampf(player_alt_n + randf_range(-0.04, 0.08), lo, hi))
		28:
			# Surface-to-air missiles: emerge inside the screen and punch straight upward.
			var n := mini(5, cap_left)
			for i in n:
				var off := float(i) - float(n - 1) * 0.5
				_spawn_air("sam_missile",
					Vector3(GameState.px + off * 0.32, GameState.py - 0.78 - absf(off) * 0.06, 0.0),
					Vector2(-off * 0.0012, 0.048 + d * 0.014),
					clampf(player_alt_n - randf_range(0.16, 0.30), lo, hi))
		29:
			# Gyro drones: twin rotors sweep across as a small patrol.
			var n := mini(4, cap_left)
			for i in n:
				var off := float(i) - float(n - 1) * 0.5
				_spawn_air("gyro_drone",
					Vector3(center_x + off * 0.50, top_y + absf(off) * 0.16, 0.0),
					Vector2(off * 0.0010, -(0.006 + d * 0.002)),
					clampf(player_alt_n + randf_range(-0.05, 0.08), lo, hi))
		30:
			# Falling pyramids: heavy rotating gold blocks drop through depth.
			var n := mini(4, cap_left)
			for i in n:
				var off := float(i) - float(n - 1) * 0.5
				_spawn_air("pyramid",
					Vector3(center_x + off * 0.42, top_y + float(i % 2) * 0.22, 0.0),
					Vector2(off * 0.0006, -(0.011 + d * 0.004)),
					clampf(player_alt_n + randf_range(-0.05, 0.12), lo, hi))
		_:
			# Ground convoy: sparse but themed targets on planet surfaces.
			if GameState.stage == "space":
				_spawn_enemy()
				return
			var theme := GameState.underground_biome if GameState.underground else GameState.planet_biome
			var ground: Array = GROUND_SETS.get(theme, ["turret"])
			var n := mini(4, cap_left)
			for i in n:
				var typ: String = ground[i % ground.size()]
				_spawn_air(typ,
					Vector3(lerpf(left_x + 0.4, right_x - 0.4, float(i) / maxf(float(n - 1), 1.0)),
						top_y + randf_range(0.0, 0.18), 0.0),
					Vector2(0.0, -PlanetTerrain.SCROLL),
					(lo + 0.02) if GameState.underground else (g_n + 0.02))

func _spawn_planet_theme_wave(cap_left: int, top_y: float, bot_y: float,
		left_x: float, right_x: float, center_x: float, player_alt_n: float,
		lo: float, hi: float, d: float, biome: String = "") -> bool:
	var theme := biome if biome != "" else GameState.planet_biome
	var n: int
	match theme:
		"VERDANT":
			n = mini(6, cap_left)
			for i in n:
				var off := float(i) - float(n - 1) * 0.5
				_spawn_air("weaver",
					Vector3(center_x + off * 0.30, top_y + absf(off) * 0.14, 0.0),
					Vector2(off * 0.001, -(0.009 + d * 0.003)),
					clampf(player_alt_n + randf_range(-0.05, 0.04), lo, hi))
			return true
		"OCEAN":
			n = mini(5, cap_left)
			for i in n:
				var side := -1.0 if (i & 1) == 0 else 1.0
				_spawn_air("swooper",
					Vector3((left_x - 0.25) if side < 0.0 else (right_x + 0.25),
						top_y + float(i) * 0.20, 0.0),
					Vector2(-side * (0.013 + d * 0.003), -(0.004 + d * 0.002)),
					clampf(player_alt_n - randf_range(0.02, 0.10), lo, hi))
			return true
		"DESERT":
			# A tight V of shooters that descends in formation, then dives on the
			# ship together (see "shooter" charge in Enemy.gd).
			n = mini(5, cap_left)
			for i in n:
				var off := float(i) - float(n - 1) * 0.5
				_spawn_air("shooter",
					Vector3(center_x + off * 0.30, top_y + absf(off) * 0.16, 0.0),
					Vector2(off * 0.001, -(0.008 + d * 0.003)),
					clampf(player_alt_n + randf_range(-0.04, 0.04), lo, hi))
			return true
		"ICE":
			# A V of snipers: they take aim in formation, then dive on the ship together.
			n = mini(5, cap_left)
			for i in n:
				var off := float(i) - float(n - 1) * 0.5
				_spawn_air("sniper",
					Vector3(center_x + off * 0.32, top_y + absf(off) * 0.16, 0.0),
					Vector2(off * 0.001, -(0.006 + d * 0.002)),
					clampf(player_alt_n + randf_range(-0.04, 0.04), lo, hi))
			return true
		"VOLCANIC":
			n = mini(6, cap_left)
			for i in n:
				_spawn_air("diver",
					Vector3(lerpf(left_x + 0.35, right_x - 0.35, randf()), top_y + float(i) * 0.12, 0.0),
					Vector2(0.0, -(0.012 + d * 0.005)),
					clampf(player_alt_n + randf_range(-0.10, 0.02), lo, hi))
			return true
		"GAS":
			n = mini(7, cap_left)
			for i in n:
				var off := float(i) - float(n - 1) * 0.5
				_spawn_air("drifter",
					Vector3(center_x + off * 0.28, top_y + sin(float(i)) * 0.22, 0.0),
					Vector2(off * 0.002, -(0.005 + d * 0.002)),
					clampf(player_alt_n + randf_range(-0.12, 0.10), lo, hi))
			return true
		"CYBER":
			n = mini(5, cap_left)
			for i in n:
				var typ := "shooter" if i == 2 else "tracker"
				_spawn_air(typ,
					Vector3(lerpf(left_x + 0.35, right_x - 0.35, float(i) / maxf(float(n - 1), 1.0)),
						top_y + (0.22 if (i & 1) == 0 else 0.0), 0.0),
					Vector2(0.0, -(0.008 + d * 0.003)),
					clampf(player_alt_n + randf_range(-0.04, 0.06), lo, hi))
			return true
		_:
			return false

func _owned_unit_for_guard() -> int:
	var candidates: Array[int] = []
	for uid in GameState.collected_units:
		var id := int(uid)
		if id >= 1 and id <= 5:
			candidates.append(id)
	if candidates.is_empty():
		return 0
	return candidates[randi() % candidates.size()]

func _unit_guard_id(t: String) -> int:
	if not t.begins_with("unit_guard_"):
		return 0
	return clampi(int(t.substr(t.length() - 1, 1)), 1, 5)

func _unit_hue(uid: int) -> float:
	match uid:
		1:
			return 195.0
		2:
			return 28.0
		3:
			return 54.0
		4:
			return 126.0
		5:
			return 215.0
		_:
			return randf() * 360.0

# The four hand-designed foes from enemy_design/. Returns true if it spawned something.
func _spawn_special_wave(cap_left: int, top_y: float, left_x: float, right_x: float,
		center_x: float, player_alt_n: float, lo: float, hi: float) -> bool:
	if cap_left <= 0:
		return false
	var alt_n := clampf(player_alt_n, lo + 0.04, hi - 0.04)
	var z := GameState.enemy_z(alt_n)
	match randi() % 4:
		0:
			# 'a' corkscrew squadron: a spread row that forms up, then corkscrew-charges.
			var n := mini(5, cap_left)
			for i in n:
				var fx := lerpf(left_x + 0.6, right_x - 0.6, float(i) / float(maxi(1, n - 1)))
				_spawn_air("corkscrew", Vector3(fx, top_y, z),
					Vector2((center_x - fx) * 0.004, -0.010), alt_n)
		1:
			# 'b' stoneface: a GROUP of slow, very tough rock faces drifting down, each at a
			# DIFFERENT altitude so they spread through depth (not a flat row).
			var n := mini(3 + randi() % 2, cap_left)   # 3-4
			for i in n:
				var fx := lerpf(left_x + 0.7, right_x - 0.7, float(i) / float(maxi(1, n - 1))) \
					+ randf_range(-0.3, 0.3)
				# At least one is guaranteed in the player's EXACT altitude plane (hittable —
				# no inset, which at alt1000 would push it out of the ±12 range); rest spread.
				var ea := clampf(player_alt_n, lo, hi) if i == 0 \
					else clampf(player_alt_n + randf_range(-0.24, 0.24), lo + 0.03, hi - 0.03)
				_spawn_air("stoneface", Vector3(fx, top_y + randf_range(0.0, 1.4), GameState.enemy_z(ea)),
					Vector2(0.0, -0.006), ea)
		2:
			# 'c' bacura: a DENSE scatter of indestructible slabs raining down at random x AND
			# random altitude — a deep dodge field (Xevious-style), staggered in height.
			var n := mini(7 + randi() % 4, cap_left)   # 7-10
			for i in n:
				var fx := randf_range(left_x + 0.3, right_x - 0.3)
				# At least one slab is guaranteed in the player's EXACT altitude plane (a real
				# obstacle — no inset, so it works at alt1000 too); the rest scatter in depth.
				var ea := clampf(player_alt_n, lo, hi) if i == 0 \
					else clampf(player_alt_n + randf_range(-0.26, 0.26), lo + 0.03, hi - 0.03)
				_spawn_air("bacura", Vector3(fx, top_y + randf_range(0.0, 3.0), GameState.enemy_z(ea)),
					Vector2(0.0, -0.016), ea)
		_:
			# 'd' splitcannon: drops onto the player's lane, splits, fires a curtain, flees.
			_spawn_air("splitcannon", Vector3(GameState.px + randf_range(-0.4, 0.4), top_y, z),
				Vector2(0.0, -0.024), alt_n)
	return true

func _spawn_air(t: String, pos: Vector3, vel: Vector2, alt_n: float) -> Enemy:
	var e: Enemy = enemy_scene.instantiate() as Enemy
	e.enemy_type = t
	e.required_unit_id = _unit_guard_id(t)
	var hp := 1
	match t:
		"combiner":
			hp = 16
		"unit_guard_1", "unit_guard_2", "unit_guard_3", "unit_guard_4", "unit_guard_5":
			hp = 4
		"caster":
			hp = 5
		"toroid":
			hp = 4
		"saucer", "manta":
			hp = 3
		"fighter":
			hp = 3
		"classic_invader", "crab":
			hp = 2
		"blade", "pod":
			hp = 2
		"sniper", "hunter", "tank", "shooter", "weaver", "diver", "climber", "swooper":
			hp = 3
		"depot":
			hp = 5
		"tracker", "turret", "radar":
			hp = 2
		"splitter":
			hp = 3
		"orbiter", "lancer", "mirror":
			hp = 2
		"ghost", "gyro_drone":
			hp = 3
		"quad_ring":
			hp = 7
		"pyramid":
			hp = 8
		"sam_missile":
			hp = 6
		"corkscrew":
			hp = 2
		"splitcannon":
			hp = 26      # tanky enough to survive ~2s and actually perform its split + fire
		"stoneface":
			hp = 58      # めちゃくちゃ硬い: a wall you can't reasonably chew through quickly
		"bacura":
			hp = 1       # indestructible anyway (take_hit blocks); value is irrelevant
		"wisp", "shard":
			hp = 1
		_:
			hp = 1
	# Zako durability bump: the player's close-range power grew, so light enemies
	# were melting instantly. Give the small fry a bit more staying power.
	if hp <= 4:
		hp += 1
	var d := GameState.difficulty()
	if d >= 0.6:
		hp += 1
	if GameState.underground:
		hp += int(floor(clampf((GameState.GROUND_ALT - GameState.alt) / GameState.GROUND_ALT, 0.0, 1.0) * 2.0))
	e.hp = hp
	e.max_hp = hp
	e.hue = _unit_hue(e.required_unit_id) if e.required_unit_id > 0 else _sector_hue(_hue_for_type(t))
	e.alt = alt_n
	e.position = pos
	e.vx = vel.x
	e.vy = vel.y
	e.add_to_group("enemies")
	get_parent().add_child(e)
	return e

# Burst a dead splitter into 2-3 fast shards that scatter outward, so killing one
# fills the screen with brief popcorn (called from Main on a splitter kill).
# The dormant "星の生き残り" — a stoneface laid out flat in the cavern beyond the sealed
# wall. Not in "enemies": it is a scenic landmark, not a target (the GERWALK bolts pass it).
func spawn_arena_survivor(world_pos: Vector3) -> void:
	if enemy_scene == null:
		return
	var e: Enemy = enemy_scene.instantiate() as Enemy
	e.enemy_type = "stoneface"
	e.dormant = true
	e.hue = 26.0
	e.hp = 9999
	e.max_hp = 9999
	e.alt = clampf(GameState.ARENA_FLOOR_ALT / GameState.ALT_MAX, 0.0, 1.0)
	e.position = world_pos
	e.add_to_group("arena_survivor")
	get_parent().add_child(e)
	# Reclined on its back but only part-way, so the face still tilts up toward the top-down
	# camera, and rolled on a diagonal so it reads as fallen/lying rather than hovering.
	e.rotation_degrees = Vector3(62.0, 0.0, 22.0)

# A random dormant zako that drifts in from the top to gather around the survivor (Main moves
# it). Not in "enemies" — it's part of the scene, never a threat or a target.
const GATHER_ZAKO := ["fighter", "saucer", "toroid", "crab", "manta", "invader", "drifter",
	"shooter", "weaver", "diver", "climber", "swooper", "wisp", "orbiter"]
func spawn_gather_zako(spawn_pos: Vector3) -> Node:
	if enemy_scene == null:
		return null
	var e: Enemy = enemy_scene.instantiate() as Enemy
	e.enemy_type = GATHER_ZAKO[randi() % GATHER_ZAKO.size()]
	e.dormant = true
	e.hue = randf() * 360.0
	e.hp = 9999
	e.max_hp = 9999
	e.alt = clampf(GameState.ARENA_FLOOR_ALT / GameState.ALT_MAX, 0.0, 1.0)
	e.position = spawn_pos
	e.add_to_group("arena_gather")
	get_parent().add_child(e)
	return e

func spawn_shards(pos: Vector3, hue: float, alt_n: float) -> void:
	if enemy_scene == null:
		return
	var count := 2 + randi() % 2
	for i in count:
		var ang := TAU * (float(i) + randf_range(-0.15, 0.15)) / float(count) - PI * 0.5
		var spd := randf_range(0.013, 0.020)
		var e: Enemy = enemy_scene.instantiate() as Enemy
		e.enemy_type = "shard"
		e.hue = hue
		e.hp = 1
		e.max_hp = 1
		e.alt = alt_n
		e.position = pos
		e.vx = cos(ang) * spd
		e.vy = sin(ang) * spd
		e.add_to_group("enemies")
		get_parent().add_child(e)

# In open space, bias the rolled enemy toward the region's roster — and crossfade
# that roster across a region boundary (the next region's foes mix in more and
# more as sector_blend rises), so the enemy mix drifts seamlessly with distance.
func _sector_foe(fallback: String) -> String:
	if GameState.stage != "space":
		return fallback
	if randf() > 0.6:
		return fallback
	var th: Dictionary = GameState.next_sector_theme() if randf() < GameState.sector_blend \
		else GameState.sector_theme()
	var foes: Array = th.get("foes", [])
	if foes.is_empty():
		return fallback
	return str(foes[randi() % foes.size()])

# Space enemies wear the region's accent hue (crossfaded between regions) so a
# whole stretch of the journey reads as one palette that drifts as you travel
# (planets keep their per-type hues).
func _sector_hue(default_hue: float) -> float:
	if GameState.stage != "space":
		return default_hue
	var acc: Color = GameState.sector_color("accent")
	return fmod(acc.h * 360.0 + randf_range(-30.0, 30.0) + 360.0, 360.0)

func _hue_for_type(t: String) -> float:
	match t:
		"combiner":
			return 300.0 + randf() * 40.0
		"tank":
			return 70.0 + randf() * 50.0
		"radar":
			return 195.0 + randf() * 25.0
		"depot":
			return 30.0 + randf() * 25.0
		"turret":
			return 25.0 + randf() * 70.0
		"sniper":
			return 350.0 + randf() * 20.0
		"shooter":
			return 15.0 + randf() * 30.0
		"weaver":
			return 165.0 + randf() * 45.0
		"diver":
			return 260.0 + randf() * 35.0
		"climber":
			return 205.0 + randf() * 35.0
		"swooper":
			return 325.0 + randf() * 30.0
		"hunter":
			return 300.0 + randf() * 35.0
		"blade":
			return randf() * 20.0
		"caster":
			return 278.0 + randf() * 34.0
		"pod":
			return 182.0 + randf() * 45.0
		"classic_invader":
			return 86.0 + randf() * 54.0
		"fighter":
			return 197.0 + randf() * 12.0
		"saucer":
			return 205.0 + randf() * 42.0
		"toroid":
			return 0.0
		"crab":
			return 330.0 + randf() * 35.0
		"manta":
			return 150.0 + randf() * 55.0
		"tracker":
			return 110.0 + randf() * 35.0
		"zigzag":
			return 45.0 + randf() * 25.0
		"wisp":
			return 50.0 + randf() * 30.0
		"orbiter":
			return 185.0 + randf() * 40.0
		"splitter", "shard":
			return 130.0 + randf() * 30.0
		"lancer":
			return 0.0 + randf() * 18.0
		"mirror":
			return 270.0 + randf() * 40.0
		"ghost":
			return 52.0 + randf() * 8.0
		"quad_ring":
			return 0.0
		"sam_missile":
			return 5.0
		"gyro_drone":
			return 205.0
		"pyramid":
			return 48.0 + randf() * 10.0
		"corkscrew":
			return 30.0      # palette is overridden per-type; base hue tints the marker
		"splitcannon":
			return 205.0
		"stoneface":
			return 20.0
		"bacura":
			return 285.0
		_:
			return randf() * 360.0

func _spawn_enemy() -> void:
	if enemy_scene == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var sz    := get_viewport().get_visible_rect().size
	var depth := 4.0
	var top_w := camera.project_position(Vector2(sz.x * 0.5, 0.0),        depth)
	var bot_w := camera.project_position(Vector2(sz.x * 0.5, sz.y),       depth)
	var lft_w := camera.project_position(Vector2(0.0,         sz.y * 0.5), depth)
	var rgt_w := camera.project_position(Vector2(sz.x,        sz.y * 0.5), depth)

	var top_y  := top_w.y  + 0.15
	var bot_y  := bot_w.y  - 0.15
	var left_x := lft_w.x  - 0.15
	var right_x:= rgt_w.x  + 0.15
	var w      := right_x - left_x

	var types := ["invader", "invader", "classic_invader", "fighter", "drifter", "tracker", "shooter",
				  "weaver", "diver", "climber", "swooper", "spiraler",
				  "zigzag", "sniper", "hunter", "blade", "caster", "pod",
				  "saucer", "toroid", "crab", "manta", "ghost",
				  "quad_ring", "quad_ring", "quad_ring",
				  "sam_missile", "sam_missile", "sam_missile",
				  "gyro_drone", "pyramid"]
	if GameState.underground:
		types = ["drifter", "tracker", "shooter", "weaver", "diver",
			"climber", "spiraler", "zigzag", "sniper", "hunter", "hunter"]
	var t: String = types[randi() % types.size()]
	t = _sector_foe(t)
	if GameState.stage == "space" and randf() < 0.16:
		var uid := _owned_unit_for_guard()
		if uid > 0:
			t = "unit_guard_%d" % uid
	# Planet/abyss stages: a good share of spawns are ground forces riding the
	# terrain scroll (attack them by skimming at ALT0, Xevious style),
	# picked to match the planet's theme.
	# Underground draws from its own (abyss) biome set; surface uses the planet theme.
	var theme := GameState.underground_biome if GameState.underground else GameState.planet_biome
	var ground_chance := 0.45
	if GameState.underground:
		ground_chance = 0.18
	var low_orbit_star := GameState.stage == "planet" \
			and get_tree().get_first_node_in_group("planet_terrain") is TargetPlanet
	if GameState.stage != "space" and not low_orbit_star and randf() < ground_chance:
		var ground: Array = GROUND_SETS.get(theme, ["turret"])
		t = ground[randi() % ground.size()]
	var hp: int
	match t:
		"combiner":
			hp = 16
		"unit_guard_1", "unit_guard_2", "unit_guard_3", "unit_guard_4", "unit_guard_5":
			hp = 4
		"caster":
			hp = 5
		"toroid":
			hp = 4
		"saucer", "manta":
			hp = 3
		"fighter":
			hp = 3
		"classic_invader", "crab":
			hp = 2
		"blade", "pod":
			hp = 2
		"sniper", "hunter", "tank", "shooter", "weaver", "diver", "climber", "swooper":
			hp = 3
		"depot":
			hp = 5
		"tracker", "turret", "radar":
			hp = 2
		"splitter":
			hp = 3
		"orbiter", "lancer", "mirror":
			hp = 2
		"ghost", "gyro_drone":
			hp = 3
		"quad_ring":
			hp = 7
		"pyramid":
			hp = 8
		"sam_missile":
			hp = 6
		"wisp", "shard":
			hp = 1
		_:
			hp = 1
	var d := GameState.difficulty()
	if d >= 0.6:
		hp += 1
	var underground_depth := 0.0
	if GameState.underground:
		underground_depth = clampf((GameState.GROUND_ALT - GameState.alt) / GameState.GROUND_ALT, 0.0, 1.0)
		hp += int(floor(underground_depth * 3.0))

	var e: Enemy = enemy_scene.instantiate() as Enemy
	e.enemy_type = t
	e.required_unit_id = _unit_guard_id(t)
	e.hp         = hp
	e.max_hp     = hp
	e.hue        = _unit_hue(e.required_unit_id) if e.required_unit_id > 0 else _sector_hue(_hue_for_type(t))
	# Altitude distribution favors the lower layers (Unit3/Unit4's hunting
	# grounds): 35% near player / 35% clearly BELOW the player (15-45 under,
	# outside the ±12 attack band → counts as "lower") / 20% absolute low
	# layer (alt 0-0.25, present even at ALT 0) / 10% fully random.
	var player_alt_n := GameState.alt / GameState.ALT_MAX
	# Active stratum (normalized 0..1 over ALT_MAX): surface air is [g_n, 1];
	# underground is [0, g_n]. Enemies distribute within whichever the player's in.
	var g_n := GameState.GROUND_ALT / GameState.ALT_MAX   # crust boundary (~0.667)
	var lo := 0.0 if GameState.underground else g_n
	var hi := g_n if GameState.underground else 1.0
	var alt_roll := randf()
	if t in GROUND_TYPES:
		# Sit on the floor of the active stratum: the cave floor (alt0) underground,
		# or the surface crust (alt900) on top.
		e.alt = (lo + 0.02) if GameState.underground else (g_n + 0.02)
	elif alt_roll < 0.35:
		e.alt = clampf(player_alt_n + (randf() - 0.5) * 0.2, lo, hi)
	elif alt_roll < 0.7:
		e.alt = clampf(player_alt_n - (0.15 + randf() * 0.3), lo, hi)
	elif alt_roll < 0.9:
		e.alt = lo + randf() * 0.25
	else:
		e.alt = lerpf(lo, hi, randf())
	if GameState.underground and t not in GROUND_TYPES:
		e.alt = clampf(player_alt_n + randf_range(-0.18, 0.12), lo + 0.04, hi - 0.04)
	e.add_to_group("enemies")

	match t:
		"turret", "tank", "radar", "depot":
			match t:
				"tank":  e.hue = 70.0 + randf() * 50.0    # olive drab
				"radar": e.hue = 195.0 + randf() * 25.0   # signal blue
				"depot": e.hue = 30.0 + randf() * 25.0    # container brown
				_:       e.hue = 25.0 + randf() * 70.0    # earthy gun emplacement
			e.position = Vector3(left_x + randf() * w, top_y, 0.0)
			e.vy = -PlanetTerrain.SCROLL  # rides the terrain scroll
		"drifter":
			var from_left := randf() < 0.5
			e.position = Vector3(
				left_x if from_left else right_x,
				bot_y + randf() * (top_y - bot_y) * 0.7 + (top_y - bot_y) * 0.1,
				0.0
			)
			e.vx = (1.0 if from_left else -1.0) * (0.009 + randf() * 0.005)
			e.vy = -(0.005 + randf() * 0.005)
		"tracker":
			e.position = Vector3(left_x + randf() * w, bot_y, 0.0)
			e.vy = 0.008 + randf() * 0.003
		"climber":
			e.position = Vector3(left_x + randf() * w, bot_y - 0.25, 0.0)
			e.vy = 0.010 + randf() * 0.004
		"swooper":
			var from_left_s := randf() < 0.5
			e.position = Vector3(left_x - 0.25 if from_left_s else right_x + 0.25,
				top_y + randf() * 0.6, 0.0)
			e.vx = (1.0 if from_left_s else -1.0) * (0.014 + randf() * 0.006)
			e.vy = -(0.004 + randf() * 0.005)
		"classic_invader":
			e.position = Vector3(left_x + randf() * w, top_y + randf() * 0.18, 0.0)
			e.vx = (0.007 + randf() * 0.006) * (-1.0 if randf() < 0.5 else 1.0)
			e.vy = -(0.006 + randf() * 0.004)
		"fighter":
			e.position = Vector3(left_x + randf() * w, top_y + randf() * 0.12, 0.0)
			e.vx = randf_range(-0.006, 0.006)
			e.vy = -(0.018 + randf() * 0.007)
		"saucer":
			e.position = Vector3(left_x + randf() * w, top_y + randf() * 0.25, 0.0)
			e.vx = randf_range(-0.004, 0.004)
			e.vy = -(0.004 + randf() * 0.003)
		"toroid":
			e.position = Vector3(left_x + randf() * w, top_y + randf() * 0.18, 0.0)
			e.vx = randf_range(-0.004, 0.004)
			e.vy = -(0.011 + randf() * 0.005)
		"crab":
			e.position = Vector3(left_x + randf() * w, top_y + randf() * 0.12, 0.0)
			e.vx = randf_range(-0.008, 0.008)
			e.vy = -(0.007 + randf() * 0.004)
		"manta":
			var from_left_m := randf() < 0.5
			e.position = Vector3(left_x - 0.20 if from_left_m else right_x + 0.20,
				top_y + randf() * 0.45, 0.0)
			e.vx = (1.0 if from_left_m else -1.0) * (0.010 + randf() * 0.005)
			e.vy = -(0.006 + randf() * 0.004)
		"ghost":
			e.position = Vector3(left_x + randf() * w, top_y + randf() * 0.22, 0.0)
			e.vx = randf_range(-0.006, 0.006)
			e.vy = -(0.007 + randf() * 0.004)
		"quad_ring":
			var from_left_q := randf() < 0.5
			e.position = Vector3(left_x - 0.45 if from_left_q else right_x + 0.45,
				GameState.py + randf_range(-0.45, 0.55), 0.0)
			e.vx = (1.0 if from_left_q else -1.0) * (0.018 + randf() * 0.007)
			e.vy = randf_range(-0.0025, 0.0025)
		"sam_missile":
			# Space SAM: born in-screen from a lower layer, then climbs at the player.
			e.position = Vector3(GameState.px + randf_range(-0.85, 0.85),
				GameState.py - randf_range(0.62, 0.95), 0.0)
			e.alt = clampf(player_alt_n - randf_range(0.16, 0.32), lo, hi)
			e.vx = randf_range(-0.004, 0.004)
			e.vy = 0.050 + randf() * 0.018
		"gyro_drone":
			e.position = Vector3(left_x + randf() * w, top_y + randf() * 0.22, 0.0)
			e.vx = randf_range(-0.006, 0.006)
			e.vy = -(0.006 + randf() * 0.003)
		"pyramid":
			e.position = Vector3(left_x + randf() * w, top_y + randf() * 0.18, 0.0)
			e.vx = randf_range(-0.003, 0.003)
			e.vy = -(0.010 + randf() * 0.005)
		"sniper":
			e.position = Vector3(left_x + randf() * w, top_y, 0.0)
			e.vy = -0.004
		"hunter":
			e.position = Vector3(left_x + randf() * w, top_y, 0.0)
			e.vy = -0.003
		_:
			e.position = Vector3(left_x + randf() * w, top_y, 0.0)
			e.vy = -(0.009 + randf() * 0.006)
			if t == "zigzag":
				e.vx = 0.016 + randf() * 0.005

	# Enemies move faster as the player grows (ground forces stay glued to the
	# terrain scroll).
	if t not in GROUND_TYPES:
		var spd_mult := 1.0 + 0.5 * d + underground_depth * 0.45
		e.vx *= spd_mult
		e.vy *= spd_mult

	get_parent().add_child(e)

func _radar_alive() -> bool:
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.get("enemy_type") == "radar":
			return true
	return false

func _boss_alive() -> bool:
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and str(e.get("enemy_type")) in ["midboss", "boss", "poly_guardian"]:
			return true
	return false

func _space_dread_alive() -> bool:
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and str(e.get("enemy_type")) == "space_dreadnought":
			return true
	return false

func _combiner_alive() -> bool:
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and str(e.get("enemy_type")) == "combiner":
			return true
	return false

func _spawn_combiner() -> void:
	if enemy_scene == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var sz := get_viewport().get_visible_rect().size
	var top_w := camera.project_position(Vector2(sz.x * 0.5, -90.0), 4.0)
	var e: Enemy = enemy_scene.instantiate() as Enemy
	e.enemy_type = "combiner"
	var d := GameState.difficulty()
	e.hp = 18 + int(d * 10.0)
	e.max_hp = e.hp
	e.hue = _sector_hue(_hue_for_type("combiner"))
	e.alt = clampf(GameState.alt / GameState.ALT_MAX + randf_range(-0.04, 0.04), 0.68, 1.0)
	e.position = Vector3(randf_range(-0.7, 0.7), top_w.y + 0.7, 0.0)
	e.vy = -0.004
	e.add_to_group("enemies")
	get_parent().add_child(e)
	get_tree().call_group("star_hud", "show_message",
		"COMBINER CONTACT", "SEPARATION PATTERN DETECTED")

func _spawn_space_dreadnought() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var sz := get_viewport().get_visible_rect().size
	var d: Node3D = SpaceDreadnoughtScene.new()
	d.hp = 70 + int(GameState.difficulty() * 70.0)
	d.max_hp = d.hp
	var top_w := camera.project_position(Vector2(sz.x * 0.5, -120.0), 4.0)
	d.position = Vector3(randf_range(-1.4, 1.4), top_w.y + 1.0, -18.0)
	get_parent().add_child(d)
	get_tree().call_group("star_hud", "show_message",
		"ENEMY CARRIER APPROACHING", "DEEP SPACE INTERCEPT")

func _spawn_polygon_guardian() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var sz := get_viewport().get_visible_rect().size
	var e := PolygonGuardian.new()
	var d := GameState.difficulty()
	e.hp = 190 + int(d * 90.0)
	e.max_hp = e.hp
	e.hue = 285.0
	e.alt = minf(GameState.alt / GameState.ALT_MAX, 0.42)
	var top_w := camera.project_position(Vector2(sz.x * 0.5, -100.0), 4.0)
	e.position = Vector3(camera.global_position.x, top_w.y + 0.8, 0.0)
	get_parent().add_child(e)
	get_tree().call_group("star_hud", "show_message",
		"WARNING - UNDERGROUND POLYGON BOSS", "OOPARTS RESONATING")

func _spawn_boss(kind: String) -> void:
	if enemy_scene == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var sz := get_viewport().get_visible_rect().size
	var e: Enemy = enemy_scene.instantiate() as Enemy
	e.enemy_type = kind
	var d := GameState.difficulty()
	e.hp = (40 + int(d * 25.0)) if kind == "midboss" else 150
	e.max_hp = e.hp
	e.hue = 285.0 if kind == "midboss" else 0.0
	e.alt = GameState.alt / GameState.ALT_MAX
	e.add_to_group("enemies")
	var top_w := camera.project_position(Vector2(sz.x * 0.5, -80.0), 4.0)
	e.position = Vector3(camera.global_position.x, top_w.y + 0.6, 0.0)
	get_parent().add_child(e)
	get_tree().call_group("star_hud", "show_message",
		"WARNING - GUARDIAN APPROACHING" if kind == "midboss"
		else "WARNING - THE OMEGA CORE AWAKENS", "")
