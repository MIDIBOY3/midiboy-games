extends Node

var px: float = 0.0
var py: float = 0.0
var vx: float = 0.0
var vy: float = 0.0
var mx: float = 0.0
var my: float = 0.0
var alt: float = 250.0
var tAlt: float = 250.0
const SIDE_HERO := "HERO"
const SIDE_ZAKO := "ZAKO"
var local_side: String = SIDE_HERO
var active_actor: String = SIDE_HERO
var camera_target_actor: String = SIDE_HERO
var active_actor_world_y: float = 0.0
var chunk_preload_screens: float = 10.0
var zako_prototype_mode: bool = true
var hero_unit_autopilot: bool = false
var zako_unit_active: bool = false
var zako_unit_world_y: float = 0.0

# --- World-coordinate model (ZAKO design brief §1) --------------------------------
# Hero and Zako share ONE world. X = bounded playfield, Y = forward scroll (grows as an
# actor advances). The camera follows the ACTIVE actor's world-Y (cam_y); every entity is
# placed at its true world position and the 3D camera renders it at worldY - cam_y for us.
# Zako spawns ~10 screens ahead of Hero in world-Y — its "future front".
var hero_pos: Vector2 = Vector2.ZERO          # HERO world position (x, y)
var zako_pos: Vector2 = Vector2.ZERO          # ZAKO world position (x, y)
var hero_alt: float = 1000.0                  # HERO altitude 0..ALT_MAX (continuous), eased to talt
var zako_alt: float = 1000.0
var hero_talt: float = 1000.0                 # target the stick/wheel drives; alt eases to it
var zako_talt: float = 1000.0
var cam_y: float = 0.0                         # world-Y the camera is centered on
var cam_z: float = 4.0                         # camera DEPTH (= alt_z(self) + CAM_REF_DIST)

# --- Altitude as world DEPTH (Z) ---------------------------------------------------
# Every actor/object sits at z = alt_z(its altitude). The camera rides CAM_REF_DIST above the
# SELF's altitude-z, so the SELF is always the same distance → constant on-screen size, while
# an OPPONENT at a different altitude is nearer/farther → looks bigger/smaller (altitude gap is
# readable, so dodging by altitude matters). Ground/world objects sit at alt_z(0)=0.
const ALT_DEPTH_SPAN := 3.0    # world-z the full altitude range spans. Bigger = stronger perspective
                               # (world/opponent bigger & slower low, smaller & slower high). Must
                               # stay < CAM_REF_DIST so an opponent at max gap never reaches the camera.
const CAM_REF_DIST := 4.0      # camera distance above the SELF's altitude (constant self size)
func alt_z(a: float) -> float:
	return (a / ALT_MAX) * ALT_DEPTH_SPAN

# Altitude is CONTINUOUS (0..ALT_MAX) — you can stop anywhere (no level snapping). The HUD gauge
# is graduated into ALT_GAUGE_DIV notches and shown as 0..100; two actors are "aligned" (can hit
# / ◯ marker) when within one notch (ALT_ALIGN_BAND) of each other.
# (alt_speed_mult removed: altitude no longer scales world MOVEMENT — pure-camera model; apparent
# speed comes only from per-player camera depth ÷ cam_z, incl. the background stars.)
const ALT_GAUGE_DIV := 10                 # gauge notches (altitude is CONTINUOUS — display only)
const ALT_ALIGN_BAND := ALT_MAX / 20.0    # aim band HALF-width; drawn ±this = 1 notch total.
                                          # Within this of a target = aligned (red ◯ / can hit).
func alt_display(a: float) -> int:        # 0..ALT_MAX → 0..100 for the HUD
	return int(round(clampf(a / ALT_MAX, 0.0, 1.0) * 100.0))
# Relative altitude of `other` vs `self_a`: +1 above (△), 0 aligned (◯), -1 below (▽).
func alt_rel(self_a: float, other: float) -> int:
	if absf(other - self_a) <= ALT_ALIGN_BAND:
		return 0
	return 1 if other > self_a else -1
var zako_aim: Vector2 = Vector2(0.0, -1.0)     # ZAKO fire direction (world), mouse-pointed
var zako_spawned: bool = false                 # ZAKO has been placed ahead this session
const PLAYFIELD_HALF_W := 2.4                  # world-X bound for a controllable actor
# Enemy Front (design brief): turrets/obstacles the ZAKO seeds into the SHARED world ~10
# screens ahead of the HERO. Stored as world data so the HERO meets the same front later.
# Each entry: {"x": float, "y": float}. Legacy per-turret list (superseded by front_blocks).
var enemy_front: Array = []

# Zako Front — Area Block System (design 2026-07-02). Instead of 1-cell building, the ZAKO drops
# self-connecting "area blocks" into empty world chunks AHEAD of the HERO (the Front Build Zone).
# Persisted as WORLD CHUNK DATA so the HERO meets the real stage on arrival. Managed/rendered by
# EnemyFront.gd (ZakoFront). Each entry (one per occupied band):
#   {"id":int, "band":int, "y":float, "kind":String, "open_alts":Array[int], "sock_out":String,
#    "locked":bool}
# open_alts uses altitude bands LOW=0 / MID=1 / HIGH=2 (a continuous passable route is guaranteed
# by requiring adjacent blocks to share at least one open altitude — "通行不能禁止").
var front_blocks: Array = []

# Zako terrain-paint state — the HUD (AltGauge) reads these; ZakoMode writes them each frame.
var build_kind: String = ""      # last painted part (flavour readout)
var build_layer: int = 1         # target altitude layer LOW=0 / MID=1 / HIGH=2 (from current alt)
var build_credits: float = 0.0   # terrain-paint GAUGE value (mirror of EnemyFront)
var build_gauge_max: float = 10.0
var build_reason: String = ""    # "" = paintable at the current spot; else the blocking reason
var build_painting: bool = false # R3 held (painting this frame)

# World-Y of whichever actor the player is currently piloting (camera + spawn origin).
func active_pos_y() -> float:
	return zako_pos.y if local_side == SIDE_ZAKO else hero_pos.y

# Shared move-speed multiplier (input spec v1.1): L1/Shift = precision (slow), R1/Ctrl =
# boost (fast). Both HERO and ZAKO scale their base speed by this so the feel is identical.
const MOVE_SLOW_MULT := 0.45
const MOVE_BOOST_MULT := 1.7
func move_speed_mult() -> float:
	if Input.is_action_pressed("slow"):
		return MOVE_SLOW_MULT
	if Input.is_action_pressed("boost"):
		return MOVE_BOOST_MULT
	return 1.0
var debug_pin_ship: bool = false  # set by TSG_PIN_SHIP: freeze px/py/alt, skip Unit1 mouse input
var score: int = 0
# Per-unit life (0-100, index = uid-1). Unit1's life hitting 0 = game over;
# any other unit's life hitting 0 = that unit is lost (re-acquire via mothership).
var unit_life: Array[float] = [100.0, 100.0, 100.0, 100.0, 100.0]
# Mothership landing sequence: 0 none / 1 descend / 2 runway (mouse ok) / 3 climb
var autopilot: int = 0
# True while the player rides a mothership deck: altitude locked, life repairs.
var on_carrier: bool = false
# Deck-walk hub mode (project-deck-hub-mode): while riding the deck, clicking lands
# the ship and disembarks the pea-sized pilots to walk the carrier. NOT a scene swap
# — the tree is paused (a combat lull / 実質ポーズ) and the same top-down camera just
# zooms in. Driven by DeckWalkMode (process_mode ALWAYS so it runs while paused).
var deck_walk: bool = false
# Carrier takeover event: fires periodically during space play. While active, the
# carrier's REPAIR and new-UNIT pickup are LOCKED — the player must land and clear
# the boarders (deck-walk combat) to lift it. (Future: more boarder/enemy variety.)
var carrier_takeover: bool = false
var takeover_boarders: int = 0     # boarders left to defeat (persists across board sessions)
# Carrier hull integrity: damaged by takeover events; repaired on the deck by talking
# to engineer crew and spending mined resources (a chunk at a time — no instant full heal).
const CARRIER_HULL_MAX := 100.0
var carrier_hull: float = 100.0
var docked_units: Array = []  # mirrored from FormationManager each frame

# --- Mercenaries (hired from ヒカリ商人 below deck for resources) ---------------
# Up to 5 hired guns DEFEND the carrier during a takeover even if the player never
# returns: they cut down boarders (absorbing most of the hull drain) but take damage
# and can die. Their HP feeds the takeover alert.
const MERC_MAX := 5
const MERC_HP_MAX := 100.0
const MERC_HIRE_COST := 45        # res_pool spent per mercenary
# Each entry = {"name": String, "hp": float}; 0..MERC_MAX of them. Names are drawn from
# MERC_NAMES (unused ones first) so every hired gun is identifiable on the deck & roster.
var mercs: Array = []
const MERC_NAMES := ["ガロ", "ジグ", "ヴァン", "ザイル", "ブロウ", "ディーゴ",
	"ライガ", "クロウ", "バルド", "ゲイル"]
var _merc_combat_t: int = 0

# --- Auto-repair (カナ博士's 資源研究所 below deck) ----------------------------
# The lab continuously rebuilds the hull over time, FUELLED BY THE STOCKPILE (備蓄):
# every tick spends some stockpiled resources to heal. When the stockpile runs dry it
# simply stops until you bank more (switch to 備蓄モード at カナ博士). Durability/mercs
# are a separate line funded by res_pool.
const AUTO_REPAIR_COST := 6       # stockpile spent per repair tick
const AUTO_REPAIR_AMOUNT := 5.0   # hull restored per tick
const AUTO_REPAIR_PERIOD := 90    # frames between ticks
var _auto_repair_t: int = 0

func merc_count() -> int:
	return mercs.size()

func merc_hp(i: int) -> float:
	return float(mercs[i]["hp"])

func merc_name(i: int) -> String:
	return String(mercs[i]["name"])

# Index of the hired gun with this name, or -1 (names are unique, so this is a stable
# handle the deck NPCs use as HP shifts and mercs die).
func merc_find(nm: String) -> int:
	for i in mercs.size():
		if String(mercs[i]["name"]) == nm:
			return i
	return -1

# Apply combat damage to a named merc; returns true if it just died (entry removed).
func damage_merc(nm: String, dmg: float) -> bool:
	var i := merc_find(nm)
	if i < 0:
		return false
	mercs[i]["hp"] = float(mercs[i]["hp"]) - dmg
	if float(mercs[i]["hp"]) <= 0.0:
		mercs.remove_at(i)
		return true
	return false

# Pick a fresh name (unused ones first, then fall back to the pool) for a new hire.
func _next_merc_name() -> String:
	var used := []
	for m in mercs:
		used.append(String(m["name"]))
	var free := []
	for n in MERC_NAMES:
		if n not in used:
			free.append(n)
	if free.is_empty():
		return MERC_NAMES[randi() % MERC_NAMES.size()]
	return free[randi() % free.size()]

func hire_merc() -> bool:
	if mercs.size() >= MERC_MAX or res_pool < MERC_HIRE_COST:
		return false
	res_pool -= MERC_HIRE_COST
	mercs.append({"name": _next_merc_name(), "hp": MERC_HP_MAX})
	return true

# --- 食堂 (mess hall, below deck): a meal restores every guard's HP for a flat resource cost.
const MESS_HEAL_COST := 20         # res_pool spent to feed the whole guard roster
func mercs_need_heal() -> bool:
	for m in mercs:
		if float(m["hp"]) < MERC_HP_MAX:
			return true
	return false

func heal_all_mercs() -> void:
	for m in mercs:
		m["hp"] = MERC_HP_MAX

# Mercs fight the boarders during a takeover. Returns the fraction [0..1] of the assault
# they're holding off (used to cut the hull drain). Call once per frame while boarded.
func tick_merc_defense() -> float:
	if mercs.is_empty() or takeover_boarders <= 0:
		return 0.0
	_merc_combat_t += 1
	if _merc_combat_t >= 70:
		_merc_combat_t = 0
		takeover_boarders = maxi(0, takeover_boarders - 1)        # a merc cuts one down
		var idx := randi() % mercs.size()                         # a boarder wounds a merc
		mercs[idx]["hp"] = float(mercs[idx]["hp"]) - randf_range(8.0, 18.0)
		if float(mercs[idx]["hp"]) <= 0.0:
			mercs.remove_at(idx)
	if mercs.is_empty():
		return 0.0
	return clampf(float(mercs.size()) / maxf(1.0, float(takeover_boarders)), 0.0, 1.0)

# Lab auto-repair tick. Call once per frame; spends STOCKPILE to heal the hull. Stops when
# the stockpile is empty (no fuel) or the hull is full.
func tick_auto_repair() -> void:
	if carrier_hull >= CARRIER_HULL_MAX or stockpile < AUTO_REPAIR_COST:
		return
	_auto_repair_t -= 1
	if _auto_repair_t > 0:
		return
	_auto_repair_t = AUTO_REPAIR_PERIOD
	stockpile -= AUTO_REPAIR_COST
	carrier_hull = minf(CARRIER_HULL_MAX, carrier_hull + AUTO_REPAIR_AMOUNT)
var frame: int = 0
# Trackpad diagnostics (shown in the F3 overlay): how many pan-gesture events the
# ship's _input has seen and the last delta, so a "no altitude on trackpad" report
# can be split into "events never arrive" vs "arrive but altitude is gated".
var dbg_pan_count: int = 0
var dbg_wheel_count: int = 0
var dbg_magnify_count: int = 0
var dbg_last_pan: Vector2 = Vector2.ZERO
# Cursor is NEVER confined/captured in normal play (spec): the mouse is free to leave the
# window / move to another monitor. Normal = VISIBLE; F1 toggles VISIBLE↔HIDDEN; F2 is a
# debug-only CAPTURED toggle; Esc always restores VISIBLE.
var mouse_confine_enabled: bool = false   # legacy flag, kept false (no confinement)

const SETTINGS_PATH := "user://settings.cfg"

func load_options() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		pass   # no confinement option to load anymore

func save_options() -> void:
	pass

func apply_mouse_mode() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

# --- Cursor / capture helpers (used by the dev shortcuts F1/F2, and Esc) ---
func show_cursor() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func toggle_cursor_visible() -> void:   # F1
	var m := Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN if m == Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_VISIBLE)

func toggle_mouse_capture() -> void:    # F2 (debug only)
	var m := Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if m == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED)

func set_local_side(side: String) -> void:
	local_side = SIDE_ZAKO if side == SIDE_ZAKO else SIDE_HERO
	hero_unit_autopilot = local_side == SIDE_ZAKO
	set_active_actor(local_side, zako_pos.y if local_side == SIDE_ZAKO else hero_pos.y)

func toggle_local_side() -> String:
	set_local_side(SIDE_ZAKO if local_side == SIDE_HERO else SIDE_HERO)
	return local_side

func is_zako_mode() -> bool:
	return local_side == SIDE_ZAKO

func should_autopilot_hero_unit() -> bool:
	return hero_unit_autopilot and is_zako_mode()

func set_active_actor(actor: String, world_y: float) -> void:
	active_actor = SIDE_ZAKO if actor == SIDE_ZAKO else SIDE_HERO
	camera_target_actor = active_actor
	active_actor_world_y = world_y

func update_active_actor_world_y(world_y: float) -> void:
	active_actor_world_y = world_y
	if active_actor == SIDE_ZAKO:
		zako_unit_world_y = world_y

func active_world_y() -> float:
	if active_actor == SIDE_ZAKO and zako_unit_active:
		return zako_pos.y
	return hero_pos.y

func is_zako_prototype_mode() -> bool:
	return zako_prototype_mode

func suppress_genesis_progression() -> bool:
	return zako_prototype_mode

# Counted at the autoload (most-upstream _input) so the F3 overlay tells us which
# event macOS actually delivers for a two-finger trackpad scroll — pan vs wheel vs
# nothing — independent of whether any gameplay node consumes it.
func _input(event: InputEvent) -> void:
	if event is InputEventPanGesture:
		dbg_pan_count += 1
		dbg_last_pan = event.delta
	elif event is InputEventMagnifyGesture:
		dbg_magnify_count += 1
	elif event is InputEventMouseButton and event.pressed \
			and (event.button_index == MOUSE_BUTTON_WHEEL_UP \
			or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		dbg_wheel_count += 1
var god_mode: bool = false
var wide_shot: bool = false
var sep_t: float = 0.0
var robot_t: float = 0.0   # authoritative robot-transform progress (set by FormationManager)
var formation_count: int = 1
var game_over: bool = false

# --- Power-up / growth system ---
var exp_points: int = 0
var exp_next: int = 500              # threshold for the next orb spawn
var powerups_taken: int = 0
var unit_levels: Array[int] = [1, 1, 1, 1, 1]  # per-unit level 1–5 (index = uid-1)
var collected_units: Array = [1]     # mirrored from FormationManager each frame
var sy: float = 0.5
var formation: Array = []
var docking = null
var dock_zoom: float = 0.0
var escape_fx: float = 0.0
var biome = null

const STAR_WORLD = 14000
const GAME_SPEED = 1.06

# --- Star targeting / planet stages (open-world loop) ---
# "space": the starfield stage. Named stars drift in the background; the player
# discovers one with the target sight, descends to ALT0 and dives into the
# bottom 20% of the screen to enter its atmosphere → "planet" stage: an endless
# procedurally generated polygon surface (biome per planet). Ground enemies are
# attackable while skimming at ALT0. Climb to ALT99 and hold the top of the
# screen to leave the atmosphere and return to space — forever, planet after planet.
var stage: String = "space"      # "space" | "planet"
var planet_name: String = ""     # star name of the current planet stage
var planet_biome: String = ""    # biome id (key of PlanetTerrain.BIOMES)
var planet_type: String = "boss" # "boss" | "mine" | "rescue"
var target_star: String = ""     # discovered star being approached ("" = none)
var target_star_type: String = "boss"
var star_entry: bool = false     # true during the atmosphere-entry dive (controls locked)
var star_exit: bool = false      # true during the climb back out to space
var exit_hold: float = 0.0       # 0..1 progress of holding the top of the screen at ALT99
var reticle_hover: bool = false  # target sight is over a star name → left click discovers,
								 # and must NOT toggle combine/separate or wide shot
var reticle_ground: Vector2 = Vector2.ZERO  # planet stage: world XY under the sight (ALT0_Z plane),
								 # where Unit1 drops its auto ground-strike bombs
var entry_glow: float = 0.0      # full-screen atmosphere transition flash (drawn by StarTargets)
var entry_tint: Color = Color(1.0, 0.5, 0.2)  # atmosphere haze color of the planet being entered
var planet_camera_exit: float = 0.0 # short smooth return from sphere rear-view to space top-view

# Atmosphere transition cinematics (Unit1): after entry the ship starts
# screen-filling and shrinks down toward the surface; during exit it pitches
# up and swells past the camera.
const ENTRY_INTRO_FRAMES := 140
var entry_intro: int = 0         # frames left of the shrink-down intro
var exit_anim: float = 0.0       # 0..1 climb-out zoom progress
var launch_count: float = 0.0    # 0..1 carrier launch-lane countdown (HUD)
# The carrier flying the current enter/launch boost. While set, it OWNS the
# ship's px/py (rigid link: the ship rides the deck through the transition).
var boost_ship: Node3D = null
# One-shot: after an arrival, Unit1 warps the mouse so the ship starts at the
# REAR of the new carrier's central runway (room to taxi forward and repair).
var deck_start: bool = false
# True while the arrival carrier flies its settle-in cinematic (planet: shrinks
# from screen-filling; space: rises from below) with the ship locked aboard.
var arrive_lock: bool = false

func in_transition() -> bool:
	return star_entry or star_exit

# --- Campaign: abysses → guardians → relics → the boss star ---
# Blasting the surface (bullets or a terrain attack) can reveal an ABYSS gate;
# touch it at low altitude to descend into a cave / underbase / temple / lava
# depth. Each abyss hides a GUARDIAN mid-boss that drops a RELIC. Defeat
# BOSS_REQ_BOSSES guardians and secure BOSS_REQ_ITEMS relics → the OMEGA CORE
# boss star appears in space; destroy its boss to clear the game.
const BOSS_REQ_BOSSES := 3
const BOSS_REQ_ITEMS := 3
var mid_bosses: int = 0          # guardians defeated
var key_items: int = 0           # relics secured
var game_clear: bool = false
var planet_seed: int = 0         # seed of the current planet surface
var abyss_return_biome: String = ""  # surface to climb back out to
var abyss_return_seed: int = 0
# Terrain swap request {biome, seed}: Main frees the old PlanetTerrain and
# spawns the new one (safe ordering for the per-planet light save/restore).
var pending_terrain: Dictionary = {}
var underground_ooparts: int = 0
var underground_boss_unlocked: bool = false
var underground_oopart_found_keys: Dictionary = {}

# --- Seamless altitude bands ---
# Altitude runs 0..ALT_MAX. The playable space/star band starts at GROUND_ALT:
#   space/star bombing: alt760..1000
# The retired rear-view surface dive below GROUND_ALT is no longer used.
const ALT_MAX    := 1000.0
const GROUND_ALT := 760.0
const PLANET_SURFACE_ALT := 560.0
const SKY_Z      := 2.0      # alt1000 (high surface air)
const DECK_Z     := -2.0     # low orbit / atmosphere boundary
const FLOOR_Z    := -5.2     # legacy name; no underground gameplay remains.
var underground: bool = false        # retired; kept false for old callers.
var over_hole: bool = false          # retired; kept false for old callers.
var hole_pos: Vector2 = Vector2.ZERO
var underground_biome: String = "CAVE"  # retired legacy state
var underground_base_biome: String = "CAVE"
var underground_boss_area: bool = false # future underground chunks switch to boss biome
var underground_boss_defeated: bool = false
var descent_gauge: float = 0.0       # retired; kept at 0.
var surface_festival_planet: bool = false
var planet_has_underground: bool = false
var star_kind: String = ""           # Dev label retained for old UI hooks.
var cleared_stars: Dictionary = {}   # star name -> true; cleared planets vanish from space

# --- Star-system regions (boundary gates + seamless region transitions) ---
# Each region is a STABLE star system. Navigation distance accrues while cruising
# open space; when a leg (NAV_LEG) fills, a GATE — the boundary between systems —
# crosses space (see SpaceGate / Main._update_navigation). Fly through it and the
# star system TRANSITIONS NATURALLY into the next: over REGION_FADE_FRAMES the
# nebula, the structures and the enemy palette/roster crossfade across (sector_blend
# 0→1) — no warp, no wipe, just the cosmos drifting into a new system. Mining banks
# extra distance, bringing the next gate sooner. Regions cycle endlessly.
const NAV_LEG := 3600.0           # distance to the next boundary gate (~minutes cruising)
const NAV_RATE := 1.0             # base distance per frame while cruising open space
const NAV_HI_BONUS := 0.7         # low-altitude accrual fraction (cruising high is a bit faster)
# While a star is displayed, nav pauses below the alt-gauge midpoint (lower half) at
# ANY time — climbing back above it resumes. Midpoint = (GROUND_ALT + ALT_MAX) / 2.
func nav_star_floor_alt() -> float:
	return (GROUND_ALT + ALT_MAX) * 0.5
const NAV_PER_RESOURCE := 18.0    # a mined block brings the gate a little sooner
const NAV_PER_RARE := 80.0        # a rare gem brings it a lot sooner
const REGION_FADE_FRAMES := 200   # length of the natural crossfade after a crossing
var nav_distance: float = 0.0     # 0..NAV_LEG progress to the boundary gate
var sector: int = 0               # current (resolved) system index (procedurally generated)
var sector_blend: float = 0.0     # 0..1 crossfade into the NEXT region during a transition
var gate_active: bool = false     # a boundary gate is on screen, waiting to be crossed
var transitioning: bool = false   # crossfading into the next system after a crossing

# --- True route (正規ルート) progress -------------------------------------
# New core loop: mining a star's blocks reveals a ROUTE PANEL (正規パネル). Finding one
# UNLOCKS the route option (`route_armed`) and summons a gate immediately. While unlocked,
# EVERY boundary gate appears as a SIDE-BY-SIDE CHOICE: take the 正規ルート (advance the
# route, which consumes the unlock) or keep exploring (unlock STAYS — the next gate is a
# choice again). Reach ROUTE_GOAL true-route steps and the final boss (宇宙俯瞰戦) opens.
const ROUTE_GOAL := 3             # true-route steps needed to reach the final boss
var route_progress: int = 0       # 0..ROUTE_GOAL true-route gates crossed
var route_armed: bool = false     # a route panel was found → gates present the 2-way choice

# Called when a route/boss panel is discovered (mining a plate block, or debug). Unlocks the
# route choice AND summons a gate at once (fill the nav leg so it appears as soon as we're
# back in open space — the plate IS the trigger).
func arm_route_gate() -> void:
	if suppress_genesis_progression():
		return
	route_armed = true
	nav_distance = NAV_LEG

# Which "proceed" gate the choice offers right now: the final BOSS once the route is complete
# (ROUTE4 + boss plate), else the next ROUTE step.
func route_proceed_kind() -> String:
	return "boss" if route_complete() else "route"

# Crossing the true gate: bank one true-route step and disarm (need a fresh plate for the
# next step). Returns the new progress so the HUD can announce it. Caps at ROUTE_GOAL.
func advance_route() -> int:
	if suppress_genesis_progression():
		return route_progress
	route_armed = false
	route_progress = mini(route_progress + 1, ROUTE_GOAL)
	return route_progress

func route_complete() -> bool:
	return route_progress >= ROUTE_GOAL

# Display route number: first stage is ROUTE1, reaching the boss-star route is ROUTE4
# (= ROUTE_GOAL + 1). route_progress 0..ROUTE_GOAL maps to ROUTE 1..ROUTE_GOAL+1.
func route_number() -> int:
	return route_progress + 1

# --- Final boss (宇宙俯瞰戦) panel ---------------------------------------
# Once at ROUTE4 (route_complete) the boss star's blocks can reveal the BOSS PANEL
# (a separate find from the route panels). Finding it arms the final sequence:
# climbing back to space then spawns the space boss (stage B, not built yet).
var boss_armed: bool = false       # boss panel found at the ROUTE4 star
# Big center-screen "ROUTE PLATE FOUND" announcement (set when a plate is mined).
var plate_announce_t: int = 0      # frames remaining to show the plate banner
var plate_announce_num: int = 0    # the ROUTE number it opens (0 = boss plate)

func arm_boss_panel() -> void:
	if suppress_genesis_progression():
		return
	if route_complete():
		boss_armed = true

# --- Black-hole mid-boss encounter (off-route fallback) ---------------------
# Crossing boundary gates WITHOUT finding a route plate counts as a "blind" jump.
# After BLIND_GATE_LIMIT blind crossings the next gate drops you into a dark
# black-hole star system holding a multi-jointed block boss; beating it frames in
# a gate to move on. Finding a route plate resets the blind streak.
const BLIND_GATE_LIMIT := 3
var blind_gate_count: int = 0
var blackhole_active: bool = false      # inside the black-hole boss system
var blackhole_boss_variant: int = 0     # 0 dragon, 1 combine/split, 2 fleet

func enter_blackhole(force_variant: int = -1) -> void:
	if suppress_genesis_progression():
		return
	blackhole_active = true
	blind_gate_count = 0
	# Random encounter (0 dragon, 1 combiner, 2 fleet); a debug key may force one.
	blackhole_boss_variant = force_variant if force_variant >= 0 else (randi() % 3)

# Final sequence phases (see project-final-boss-sequence memory).
const FINAL_NONE := 0
const FINAL_BOSS := 1              # space boss present; strike it via the carrier (B/C)
const FINAL_ENDING := 2           # boss dead → home planet appears, land, ending (D)
var final_phase: int = FINAL_NONE
var final_boss_defeated: bool = false
# Stage C: the player has landed on the carrier during FINAL_BOSS and now PILOTS the
# carrier (mouse-steered but sluggish) — it shrinks, descends to the boss and auto-
# fires a giant beam. Decoupled from the normal on_carrier deck/repair flow.
var carrier_battle: bool = false
# Where the hero ship sits while docked on the battle carrier (Mothership writes it
# each frame; Unit1 reads it to park itself on the deck, scaled to the carrier).
var carrier_dock_pos: Vector3 = Vector3.ZERO
var carrier_dock_scale: float = 1.0
# Stage D ending: the carrier has landed on the homeworld → freeze the scroll and
# play the ending text crawl (StarTargets). ending_active hides the live HUD.
var scroll_frozen: bool = false
var ending_active: bool = false
# After the boss, the whole ending is a hands-off cinematic: player control + firing are
# locked while the ship descends automatically toward the homeworld over the length of
# the ending crawl (Main._update_ending drives it from the crawl's progress).
var ending_cinematic: bool = false

# Final-boss ENTRANCE beat: the moment the boss gate is crossed the player's guns fall
# silent, a short hush passes, the music swells, and GOD descends from high above to its
# anchored pose. The whole figure is invulnerable and holds its own fire until it lands;
# only then does the duel begin. AngelBoss owns the timeline and clears this flag when set.
var boss_intro_active: bool = false
# The brief total HUSH at the very start of the entrance: every voice cuts out so the
# music can swell from genuine silence as GOD begins its descent. AngelBoss raises it the
# instant it spawns and lowers it when the hush ends (which is when the boss theme starts).
var boss_intro_hush: bool = false

# --- Title / intro ---
# The game boots into a title screen (GENESIS block logo over the starfield). Pressing
# start clears the title and plays the intro: a carrier frames in from the bottom with
# the ship on its deck, and the ship takes off from the runway. Then normal play at alt1000.
var title_active: bool = true
var intro_active: bool = false

# Full reset back to a fresh title (used by the ending's BACK TO TITLE). Main then
# reloads the scene; this clears the autoload state that would otherwise persist.
func reset_for_title() -> void:
	title_active = true
	intro_active = false
	game_over = false
	stage = "space"
	alt = ALT_MAX
	tAlt = ALT_MAX
	px = 0.0
	py = 0.0
	vx = 0.0
	vy = 0.0
	frame = 0
	score = 0
	# Final sequence
	final_phase = FINAL_NONE
	final_boss_defeated = false
	carrier_battle = false
	on_carrier = false
	deck_walk = false
	carrier_takeover = false
	takeover_boarders = 0
	carrier_hull = CARRIER_HULL_MAX
	mercs = []
	_merc_combat_t = 0
	_auto_repair_t = 0
	stockpile = 0
	ending_active = false
	ending_cinematic = false
	scroll_frozen = false
	# True-route finale flags.
	god_phase = 0
	faith_gauge = 0.0
	true_route_active = false
	survivor_monologue_active = false
	musicbox_ending = false
	fade_black = 0.0
	route_progress = 0
	route_armed = false
	boss_armed = false
	blind_gate_count = 0
	blackhole_active = false
	blackhole_boss_variant = 0
	# Navigation / region
	nav_distance = 0.0
	nav_boost = 0.0
	sector = 0
	sector_blend = 0.0
	gate_active = false
	transitioning = false
	target_star = ""
	# Run progression → fresh game
	collected_units = [1]
	unit_levels = [1, 1, 1, 1, 1]
	unit_life = [100.0, 100.0, 100.0, 100.0, 100.0]
	res_pool = 0
	rare_pool = 0
	dura_level = 0
	hubris = 0.0
	hubris_msg_t = 0
	golden_active = false
	golden_timer = 0
	golden_offered = false

# Boost lanes (F-Zero / Mario-Kart style pads that drift past in the nav-gauge
# altitude band): riding one banks extra navigation distance AND rushes the scroll.
# nav_boost is refreshed to 1.0 while on a lane, then decays over ~0.8s.
const NAV_BOOST_GAIN := 9.0       # extra nav distance/frame at full boost
const NAV_BOOST_DECAY := 0.02     # boost fades out after leaving the lane
var nav_boost: float = 0.0        # 0..1 current boost strength
var boost_lane_alts: Array[float] = []  # altitudes of active boost lanes (AltGauge nav)
var boost_lane_warn_alt: float = -1.0   # altitude of the next incoming lane (-1 = none)

func trigger_nav_boost(amount: float = 1.0) -> void:
	if nav_boost <= 0.05:
		TsgAudio.nav_boost_sfx()  # rising edge → play the "vroom" once per mount
	nav_boost = clampf(maxf(nav_boost, amount), 0.0, 1.0)

func nav_t() -> float:
	return clampf(nav_distance / NAV_LEG, 0.0, 1.0)

# Player flew through the boundary gate → begin the natural crossfade into the next
# star system (no warp/wipe; the nebula/structures/enemies just drift over).
func begin_region_transition() -> void:
	if suppress_genesis_progression():
		return
	if transitioning:
		return
	transitioning = true
	gate_active = false
	sector_blend = 0.0
	nav_distance = NAV_LEG          # hold the gauge full until the fade completes

# Advance the crossfade; when it completes the next system becomes the current one
# and the leg resets so distance builds toward the following gate.
func update_transition() -> void:
	if suppress_genesis_progression():
		transitioning = false
		gate_active = false
		return
	if not transitioning:
		return
	sector_blend = minf(1.0, sector_blend + 1.0 / float(REGION_FADE_FRAMES))
	if sector_blend >= 1.0:
		sector += 1
		sector_blend = 0.0
		transitioning = false
		nav_distance = 0.0
		# A DESTROYED carrier (hull<=0) is rebuilt on crossing into a fresh star system, so a
		# carrier lost in one system isn't lost forever — you meet a fresh one next system.
		# A merely DAMAGED hull is NOT topped up (damage carries over; repair it via カナ博士's
		# fund or on the deck).
		if carrier_hull <= 0.0:
			carrier_hull = CARRIER_HULL_MAX
		_prune_sector_cache()

# --- Infinite procedural star systems ---
# Every system is generated on demand from its index (deterministic per index +
# run_seed), so the journey never repeats and never runs out. A system's identity:
#   name, nebula sky (neb/neb2), structure palette (base/struct/accent), a random
#   enemy roster (foes), and structure variation (struct_scale/count/rate/neb_str).
# Generated themes are cached (so index→theme is stable across frames and the
# crossfade between sector and sector+1 is consistent), and old entries are pruned.
const AIR_FOES := ["invader", "weaver", "zigzag", "drifter", "diver", "hunter",
	"swooper", "shooter", "tracker", "climber", "spiraler", "sniper",
	"blade", "caster", "pod", "classic_invader", "fighter", "saucer",
	"toroid", "crab", "manta", "wisp", "orbiter", "splitter", "lancer", "mirror",
	"ghost", "quad_ring", "sam_missile", "gyro_drone", "pyramid"]
# Grand space megastructures, weighted into a system's prop pool by its backdrop
# (see _generate_sector → "struct_kinds"). "shard" is internal-only (splitter death).
const STRUCT_KINDS_BY_BACKDROP := {
	"sun":       ["dyson_swarm", "tether_spire"],
	"twin_suns": ["dyson_swarm", "tether_spire"],
	"lunar":     ["shattered_moon", "wreck_fleet"],
	"blackhole": ["shattered_moon", "wreck_fleet"],
	"aurora":    ["crystal_spire_field", "ringworld_arc"],
	"nebula":    ["crystal_spire_field", "ringworld_arc"],
	"cluster":   ["megacity_sprawl", "wreck_fleet"],
	"galaxy":    ["ringworld_arc", "dyson_swarm"],
	"supernova": ["ringworld_arc", "dyson_swarm"],
}
const SYS_SYL := ["ZA", "VEL", "KOR", "TAU", "RIN", "SOL", "ARK", "NEB", "ULA",
	"THE", "XEN", "OMA", "QUI", "DRA", "BEL", "NOV", "CYG", "LYR", "ORI", "PYX",
	"HEL", "VOR", "MYR", "ZEN", "KAI", "TYR"]
const SYS_SUFFIX := [" CLUSTER", " NEBULA", " EXPANSE", " REACH", " VEIL", " FIELD",
	" RIFT", " VOID", " DRIFT", " BELT", " SPUR", " ABYSS"]

var run_seed: int = 0               # randomized per playthrough → different journey each run
var _sector_cache: Dictionary = {}  # index → generated theme (pruned around the current sector)

func _ready() -> void:
	load_options()
	apply_mouse_mode()
	run_seed = randi()
	var _sd := OS.get_environment("TSG_SEED")   # debug: force a fixed journey/sector
	if _sd != "":
		run_seed = int(_sd)
	_ensure_input_actions()

# Shared input map (input spec v1.0). Hero and Zako use the SAME controls — only one actor
# is ever player-controlled, so the manual one reads this set. Keyboard+mouse and gamepad
# bind to the same actions. Behaviour for the "future" actions is not wired yet.
func _ensure_input_actions() -> void:
	# Move: WASD/arrows + left stick.
	_act_key("mv_left", KEY_A); _act_key("mv_left", KEY_LEFT); _act_axis("mv_left", JOY_AXIS_LEFT_X, -1.0)
	_act_key("mv_right", KEY_D); _act_key("mv_right", KEY_RIGHT); _act_axis("mv_right", JOY_AXIS_LEFT_X, 1.0)
	_act_key("mv_up", KEY_W); _act_key("mv_up", KEY_UP); _act_axis("mv_up", JOY_AXIS_LEFT_Y, -1.0)
	_act_key("mv_down", KEY_S); _act_key("mv_down", KEY_DOWN); _act_axis("mv_down", JOY_AXIS_LEFT_Y, 1.0)
	# Altitude: right stick (analog; read in code) + mouse wheel (Main._input).
	_act_axis("alt_up", JOY_AXIS_RIGHT_Y, -1.0)
	_act_axis("alt_down", JOY_AXIS_RIGHT_Y, 1.0)
	# Input spec v1.1: SHOT moved off the face buttons onto the TRIGGERS so the right thumb
	# never leaves the altitude stick. Godot uses Xbox names: □=X, ○=B, △=Y, ×=A.
	# fire = L2 + R2 (either/both fire the same shot) + left-click.
	_act_mouse("fire", MOUSE_BUTTON_LEFT)
	_act_axis("fire", JOY_AXIS_TRIGGER_LEFT, 1.0)      # L2
	_act_axis("fire", JOY_AXIS_TRIGGER_RIGHT, 1.0)     # R2
	# Movement speed: L1/Shift = precision (slow), R1/Ctrl = boost (fast).
	_act_key("slow", KEY_SHIFT); _act_btn("slow", JOY_BUTTON_LEFT_SHOULDER)
	_act_key("boost", KEY_CTRL); _act_btn("boost", JOY_BUTTON_RIGHT_SHOULDER)
	# Future / unwired: □ special (+ right-click), ○ sub-action, △ interact (+ Space).
	_act_mouse("special", MOUSE_BUTTON_RIGHT); _act_btn("special", JOY_BUTTON_X)
	_act_btn("subaction", JOY_BUTTON_B)
	_act_key("interact", KEY_SPACE); _act_btn("interact", JOY_BUTTON_Y)
	_act_key("decision", KEY_ENTER); _act_btn("decision", JOY_BUTTON_A)     # × decision
	_act_key("pause", KEY_ESCAPE); _act_btn("pause", JOY_BUTTON_START)      # OPTIONS pause
	# Zako Front build (paint terrain by flying): HOLD build_paint = R3 (right-stick click) / F and
	# move (incl. altitude) to lay seamless random terrain along the path. △ (interact / Space / Y)
	# erases while moving. Build layer = current altitude (HI/MID/LO). No part-picking — it's random.
	_act_btn("build_paint", JOY_BUTTON_RIGHT_STICK); _act_key("build_paint", KEY_F)

func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)   # small deadzone (for stick/trigger axes)

func _act_key(action: String, keycode: Key) -> void:
	_ensure_action(action)
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and e.keycode == keycode:
			return
	var k := InputEventKey.new(); k.keycode = keycode
	InputMap.action_add_event(action, k)

func _act_mouse(action: String, button: MouseButton) -> void:
	_ensure_action(action)
	for e in InputMap.action_get_events(action):
		if e is InputEventMouseButton and e.button_index == button:
			return
	var m := InputEventMouseButton.new(); m.button_index = button
	InputMap.action_add_event(action, m)

func _act_btn(action: String, button: JoyButton) -> void:
	_ensure_action(action)
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and e.button_index == button:
			return
	var b := InputEventJoypadButton.new(); b.button_index = button
	InputMap.action_add_event(action, b)

func _act_axis(action: String, axis: JoyAxis, value: float) -> void:
	_ensure_action(action)
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadMotion and e.axis == axis and signf(e.axis_value) == signf(value):
			return
	var a := InputEventJoypadMotion.new(); a.axis = axis; a.axis_value = value
	InputMap.action_add_event(action, a)

func sector_theme() -> Dictionary:
	return sector_at(sector)

func next_sector_theme() -> Dictionary:
	return sector_at(sector + 1)

# The (cached) generated theme for a system index.
func sector_at(idx: int) -> Dictionary:
	if not _sector_cache.has(idx):
		_sector_cache[idx] = _generate_sector(idx)
	return _sector_cache[idx]

# Continuous crossfade of a color key between the current system and the next, by
# sector_blend — drives the seamless nebula + structure recolor.
func sector_color(key: String) -> Color:
	var a: Color = sector_at(sector)[key]
	var b: Color = sector_at(sector + 1)[key]
	return a.lerp(b, sector_blend)

# Deterministically synthesize a star system from its index. Random hues, dark
# nebula core + brighter highlight, a structure palette, a random foe roster, and
# random structure size/count/rate so each system looks and plays differently.
func _generate_sector(idx: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d_%d" % [run_seed, idx])
	var hue := rng.randf()
	var hue2 := fposmod(hue + rng.randf_range(-0.12, 0.12), 1.0)
	var shue := fposmod(hue + rng.randf_range(-0.30, 0.30), 1.0)
	var ahue := fposmod(shue + rng.randf_range(-0.15, 0.15), 1.0)
	var pool := AIR_FOES.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp: Variant = pool[i]; pool[i] = pool[j]; pool[j] = tmp
	# Each system rolls a backdrop kind so the void is never the same twice: blazing
	# suns, spiral galaxies, black holes, harsh lunar voids, binary stars, supernovae,
	# auroras, dense star clusters, or vivid nebulae.
	var roll := rng.randf()
	var backdrop := "nebula"
	if roll < 0.12:
		backdrop = "sun"
	elif roll < 0.24:
		backdrop = "galaxy"
	elif roll < 0.34:
		backdrop = "blackhole"
	elif roll < 0.46:
		backdrop = "lunar"
	elif roll < 0.54:
		backdrop = "twin_suns"
	elif roll < 0.60:
		backdrop = "supernova"
	elif roll < 0.67:
		backdrop = "aurora"
	elif roll < 0.72:
		backdrop = "cluster"
	# Main light: energy, colour AND angle vary per system. Default is a soft light
	# from above; harsh kinds graze in from a low diagonal for hard terminator shadows.
	var light_energy := rng.randf_range(0.8, 1.6)
	var light_col := Color(1.0, 1.0, 1.0).lerp(Color.from_hsv(ahue, 0.55, 1.0), 0.16)
	var light_pitch := rng.randf_range(-62.0, -34.0)   # negative = light from above
	var light_yaw := rng.randf_range(-35.0, 80.0)
	var feat_col := Color.from_hsv(ahue, rng.randf_range(0.55, 0.85), 1.0)
	match backdrop:
		"sun":
			light_energy = rng.randf_range(2.4, 3.8)
			var sun_hue := rng.randf_range(0.03, 0.11)
			light_col = Color.from_hsv(sun_hue, rng.randf_range(0.20, 0.42), 1.0)
			feat_col = Color.from_hsv(sun_hue, rng.randf_range(0.35, 0.6), 1.0)
		"galaxy":
			feat_col = Color.from_hsv(ahue, rng.randf_range(0.45, 0.7), 1.0)
		"blackhole":
			light_energy = rng.randf_range(0.6, 1.1)
			feat_col = Color.from_hsv(fposmod(ahue + 0.05, 1.0), rng.randf_range(0.75, 1.0), 1.0)
		"lunar":
			# Moon-surface look: very bright key light grazing in from a low diagonal,
			# pitch-black sky, no fill — one side blazes, the other falls into shadow.
			light_energy = rng.randf_range(3.0, 4.2)
			light_col = Color.from_hsv(rng.randf_range(0.0, 0.10), rng.randf_range(0.0, 0.12), 1.0)
			light_pitch = rng.randf_range(-22.0, -8.0)
			light_yaw = rng.randf_range(32.0, 62.0)
			feat_col = Color.from_hsv(rng.randf_range(0.55, 0.65), 0.18, 1.0)  # faint cold moon
		"twin_suns":
			light_energy = rng.randf_range(2.0, 3.2)
			var th := rng.randf_range(0.05, 0.14)
			light_col = Color.from_hsv(th, rng.randf_range(0.18, 0.36), 1.0)
			feat_col = Color.from_hsv(th, rng.randf_range(0.4, 0.62), 1.0)
		"supernova":
			light_energy = rng.randf_range(1.6, 2.6)
			feat_col = Color.from_hsv(fposmod(ahue + 0.5, 1.0), rng.randf_range(0.5, 0.8), 1.0)
		"aurora":
			feat_col = Color.from_hsv(ahue, rng.randf_range(0.55, 0.85), 1.0)
		"cluster":
			feat_col = Color.from_hsv(ahue, rng.randf_range(0.2, 0.5), 1.0)
	# Nebula clouds are lush on a nebula system, faint interstellar gas otherwise,
	# and nearly gone in the harsh lunar void.
	var neb_lo := 0.06 if backdrop == "lunar" else 0.22
	var neb_str := rng.randf_range(0.80, 1.10) if backdrop == "nebula" \
		else rng.randf_range(neb_lo, 0.48)
	var neb2_val := rng.randf_range(0.55, 0.80) if backdrop == "nebula" \
		else rng.randf_range(0.35, 0.62)
	# Some systems are dominated by an endless continuous landmass scrolling past
	# (Star Force / Star Soldier style), with shootable ground bases on it. More
	# likely over moonscapes, dense clusters and galactic/supernova fronts.
	var mega_chance := 0.16
	match backdrop:
		"lunar", "cluster", "galaxy", "supernova":
			mega_chance = 0.55
		"nebula", "aurora":
			mega_chance = 0.30
	var mega_continent := rng.randf() < mega_chance
	# Some mega-continent systems show only a coastline on ONE side of the screen
	# (open space on the other), like one-sided Star Soldier stages. 0=full width,
	# -1=land hugs the left edge, +1=land hugs the right edge.
	var cont_edge := 0
	if mega_continent and rng.randf() < 0.5:
		cont_edge = -1 if rng.randf() < 0.5 else 1
	return {
		"name": _gen_system_name(rng),
		"neb": Color.from_hsv(hue, rng.randf_range(0.5, 0.9), rng.randf_range(0.10, 0.22)),
		"neb2": Color.from_hsv(hue2, rng.randf_range(0.4, 0.85), neb2_val),
		"base": Color.from_hsv(shue, rng.randf_range(0.3, 0.7), rng.randf_range(0.08, 0.20)),
		"struct": Color.from_hsv(shue, rng.randf_range(0.5, 0.95), rng.randf_range(0.70, 1.0)),
		"accent": Color.from_hsv(ahue, rng.randf_range(0.6, 1.0), rng.randf_range(0.85, 1.0)),
		"foes": pool.slice(0, 3 + (rng.randi() % 2)),
		"struct_scale": rng.randf_range(0.8, 1.7),   # structure size multiplier
		"struct_kinds": STRUCT_KINDS_BY_BACKDROP.get(backdrop, ["ringworld_arc", "megacity_sprawl"]),
		"mega_continent": mega_continent,            # endless continuous landmass system
		"cont_edge": cont_edge,                      # 0 full / -1 left coast / +1 right coast

		"struct_count": 3 + (rng.randi() % 5),       # 3..7 props on screen
		"struct_rate": rng.randf_range(0.7, 1.4),    # spawn-interval multiplier
		"neb_str": neb_str,                          # nebula intensity
		"backdrop": backdrop,                        # sun | galaxy | blackhole | nebula
		"feat": feat_col,                            # feature highlight color
		"feat_x": rng.randf_range(0.28, 0.72),       # feature screen position
		"feat_y": rng.randf_range(0.30, 0.70),
		"feat_seed": rng.randf() * 50.0,             # per-system shape variation
		"light_energy": light_energy,                # main DirectionalLight energy
		"light_col": light_col,                      # main DirectionalLight color
		"light_pitch": light_pitch,                  # main light elevation (deg, neg = above)
		"light_yaw": light_yaw,                      # main light azimuth (deg)
	}

func _gen_system_name(rng: RandomNumberGenerator) -> String:
	var core := ""
	for i in 2 + (rng.randi() % 2):
		core += SYS_SYL[rng.randi() % SYS_SYL.size()]
	return core + SYS_SUFFIX[rng.randi() % SYS_SUFFIX.size()]

# Keep the cache small: only the systems near the current one are ever needed.
func _prune_sector_cache() -> void:
	for k in _sector_cache.keys():
		if int(k) < sector - 1 or int(k) > sector + 2:
			_sector_cache.erase(k)

# --- Boss arena (gate → scene-switch into the reused voxel cave, fight the
# PolygonGuardian, then pop back to the sphere surface). The live seamless surface
# is a TargetPlanet sphere; the voxel PlanetTerrain (with its deep cave) is otherwise
# legacy, so we reuse it here as a separate, swapped-in arena. EVERYTHING arena is
# gated behind arena_active so the normal surface/space path is untouched.
# See HANDOFF_boss_arena.md. ---
var arena_active: bool = false        # true while inside the swapped voxel-cave arena
var arena_return_biome: String = ""   # surface biome to rebuild on win
var arena_return_seed: int = 0        # surface seed to restore (same orb on return)
var arena_return_name: String = ""    # surface star name to restore
var arena_return_alt: float = 0.0     # surface altitude to pop back to
var arena_reward_pending: bool = false # boss down, final-boss item waiting on the arena floor
# --- GERWALK relic hunt → sealed wall → survivor cavern (golden-walk arena) ---
const ARENA_RELIC_GOAL := 3           # relics to dig up before the sealed wall frames in
var arena_relics_found: int = 0       # 0..ARENA_RELIC_GOAL, collected from blasted blocks
var arena_wall_armed: bool = false    # the sealed breakable wall band now exists ahead
var arena_wall_y: float = 0.0         # its world-y (terrain fills a barrier across the band)
var arena_survivor_spawned: bool = false  # the dormant "星の生き残り" sits in the cavern beyond
var arena_survivor_greeted: bool = false  # one-shot proximity hook fired
var survivor_monologue_active: bool = false  # the survivor's ending-style monologue is playing (music + crawl)
var fade_black: float = 0.0           # full-screen black overlay alpha (survivor outro fade → space)
# True route (dura-max gate): after the stoneface arena, a silent standoff in empty space — GOD
# appears, neither side fires, a FAITH gauge fills, GOD fades → GENESIS, then the beacon-offering ending.
var true_route_active: bool = false   # the whole dura-max finale is running (set on arena entry)
var god_phase: int = 0                # 0 none · 1 GOD facing (gauge fills) · 2 GOD fading · 3 GENESIS
var faith_gauge: float = 0.0          # 0..1 standoff meter shown in place of HP
var musicbox_ending: bool = false     # TRUE END: a major-key music box instead of the organ ending
# Arena dive band: in the arena the ship descends BELOW the crust into the reused
# deep voxel cave. TUNE LIVE (no engine here to verify these): the floor altitude
# and its camera-z so the ship skims just above the cave walls/floor.
const ARENA_FLOOR_ALT := 500.0        # lowest altitude the ship dives to in the arena
const ARENA_FLOOR_Z   := -19.5        # camera-z at ARENA_FLOOR_ALT (cave floor ≈ -22.45)
# Ceiling clamp: kept BELOW GROUND_ALT so climbing can't punch through the crust roof
# back to the surface z-band (alt900 maps to z≈-2, the old surface). You leave the
# arena only by beating the boss. alt_to_z(870) ≈ -3.5, ~1u under the ceiling.
const ARENA_CEIL_ALT  := 720.0        # tall play band below low orbit: real vertical
									  # movement — weave among spires, chase the boss's altitude
const ARENA_HALF_W    := 2.8          # wide horizontal play band (spires are sparse, fly around)

# Single source of truth for the altitude → camera-z curve (continuous, piecewise
# at the crust). Everything that needs ship/camera z should call this instead.
func alt_to_z(a: float) -> float:
	# Boss arena: below the crust the ship dives into the reused deep cave band,
	# mapping ARENA_FLOOR_ALT→ARENA_FLOOR_Z up to the crust at GROUND_ALT→DECK_Z.
	if arena_active and a < GROUND_ALT:
		var dive_t := clampf((a - ARENA_FLOOR_ALT) / (GROUND_ALT - ARENA_FLOOR_ALT), 0.0, 1.0)
		return lerpf(ARENA_FLOOR_Z, DECK_Z, dive_t)
	if a < GROUND_ALT and a >= PLANET_SURFACE_ALT:
		var surface_t := clampf((a - PLANET_SURFACE_ALT) / (GROUND_ALT - PLANET_SURFACE_ALT),
			0.0, 1.0)
		return lerpf(DECK_Z - 3.2, DECK_Z, surface_t)
	if a >= GROUND_ALT:
		return lerpf(DECK_Z, SKY_Z, (a - GROUND_ALT) / (ALT_MAX - GROUND_ALT))
	return DECK_Z - 3.2

# Enemies/items store altitude normalized to [0,1] over the full range.
func enemy_z(alt_n: float) -> float:
	return alt_to_z(alt_n * ALT_MAX)

# "How high in the surface air" 0..1 (old "alt/99"): 0 at/below the crust, 1 at alt1000.
func sky_t() -> float:
	return clampf((alt - GROUND_ALT) / (ALT_MAX - GROUND_ALT), 0.0, 1.0)

func boss_star_ready() -> bool:
	return mid_bosses >= BOSS_REQ_BOSSES and key_items >= BOSS_REQ_ITEMS \
		and not game_clear

# --- Resources mined from planet terrain blocks ---
var resources: Dictionary = {}     # type name → count (ORE, WOOD, CRYSTAL, ...)
var resources_total: int = 0
var res_pool: int = 0              # unspent common resources (durability fund)
var rare_pool: int = 0             # unspent RARE resources (Golden fund)

# --- Repair bank (カナ博士's 資源研究所 = a BANK) -----------------------------
# The player DEPOSITS resources with Kana; the deposited balance (`stockpile`, capped) is
# the carrier's auto-repair fund — the lab burns it to rebuild the hull. Mining always
# funds res_pool as usual; only a deliberate deposit moves resources into the repair bank.
var stockpile: int = 0             # repair-bank balance (auto-repair fuel)
const STOCKPILE_MAX := 300
const KANA_DEPOSIT := 40           # resources moved res_pool → bank per deposit

# Deposit a chunk of res_pool into the repair bank (capped). Returns the amount moved.
func deposit_repair_bank() -> int:
	var room := STOCKPILE_MAX - stockpile
	var amt := mini(KANA_DEPOSIT, mini(res_pool, room))
	if amt <= 0:
		return 0
	res_pool -= amt
	stockpile += amt
	return amt

func add_resource(rname: String, n: int = 1, rare: bool = false) -> void:
	resources[rname] = int(resources.get(rname, 0)) + n
	resources_total += n
	if rare:
		rare_pool += n
	else:
		res_pool += n

# --- Durability upgrades: visit a carrier to spend mined resources and raise
# every owned unit's MAX life. Earned gradually, capped at DURA_MAX (~lvl 25). ---
const DURA_MAX := 25
const LIFE_PER_DURA := 16.0        # +max life per durability level (lvl25 → 500)
var dura_level: int = 0

# Max life per unit at the current durability level. All "heal to full" and
# repair caps use this instead of a hard 100.
func life_cap() -> float:
	return 100.0 + float(dura_level) * LIFE_PER_DURA

# Common resources needed to buy a GIVEN durability level (rises per level).
func dura_cost_at(level: int) -> int:
	return 25 + level * 18

# Common resources needed to buy the NEXT durability level (rises per level).
func dura_cost() -> int:
	return dura_cost_at(dura_level)

# --- 慢心 Hubris: once the FULL 5-unit formation reaches durability Lv15+, overconfidence
# builds with every kill. At max the units stop firing — you must soak in the below-deck
# 温泉 to humble yourself and reset it. Suspended during boss / mid-boss / final fights so
# the big moments stay winnable. ---
const HUBRIS_MAX := 100.0
const HUBRIS_PER_KILL := 0.25       # gauge gained per enemy killed (slow — ~500 kills to max)
const HUBRIS_DURA_REQ := 15        # durability level that unlocks the mechanic
var hubris: float = 0.0
# Center-screen "慢心した" announcement: frames remaining (set the moment the gauge maxes).
const HUBRIS_MSG_FRAMES := 300
var hubris_msg_t: int = 0
# Proverbs shown (with 和訳) when the onsen soak humbles you and clears the gauge.
const HUBRIS_PROVERBS := [
	{"en": "Pride goes before a fall.", "ja": "驕れる者久しからず。"},
	{"en": "Complacency is the enemy of progress.", "ja": "慢心は進歩の敵。"},
	{"en": "The bigger they are, the harder they fall.", "ja": "大きい奴ほど派手に転ぶ。"},
]

# Live only with the full formation at high durability.
func hubris_unlocked() -> bool:
	return collected_units.size() >= 5 and dura_level >= HUBRIS_DURA_REQ

# Boss / mid-boss / final fights suspend the effect (gauge frozen, fire allowed).
func hubris_suspended() -> bool:
	return blackhole_active or arena_active or carrier_battle \
		or final_phase != FINAL_NONE

func on_enemy_killed() -> void:
	if not hubris_unlocked() or hubris_suspended():
		return
	var was_below := hubris < HUBRIS_MAX
	hubris = minf(HUBRIS_MAX, hubris + HUBRIS_PER_KILL)
	# Rising edge → fire the symbolic center-screen message once (until reset re-arms it).
	if was_below and hubris >= HUBRIS_MAX:
		hubris_msg_t = HUBRIS_MSG_FRAMES

# True when overconfidence has peaked → the units refuse to fire (unless suspended).
func hubris_blocking_fire() -> bool:
	return hubris_unlocked() and not hubris_suspended() and hubris >= HUBRIS_MAX

# Soaking in the onsen clears it. Returns true if there was anything to reset (so the
# caller shows the proverb only when it actually mattered).
func reset_hubris() -> bool:
	if hubris <= 0.0:
		return false
	hubris = 0.0
	return true

# --- Golden (robot form): a G icon frames in ONCE per star system (only with the
# full 5-unit formation). Collecting it auto-transforms into the invincible Golden
# robot for GOLDEN_DURATION frames — it shrugs off everything, burns away even heavy
# enemy fire, and pulses an omni-directional aura that vaporizes enemies into
# resources. No tiers, no upkeep: a brief, total power spike, then back to formation. ---
const GOLDEN_DURATION := 600       # 10 s at 60 fps
var golden_active: bool = false    # robot stood up → invincible aura mode
var golden_timer: int = 0          # frames left of the Golden state
var golden_offered: bool = false   # G icon already shown in THIS star system

# --- Golden WALK prototype (debug, F5 — see GoldenWalkCtl) -----------------
# Drives the REAL transforming Golden as a ground-walking mech: mouse steers it (existing
# px/py follow), a single left-click HOPS it, and HOLDING left transforms it into the
# 5-unit combined fighter (the "airplane"). All gated behind golden_walk so live play is
# untouched.
var golden_walk: bool = false           # walk-test mode active (implies motion_debug stand)
var golden_airplane_hold: bool = false  # left held → transform to the combined fighter
var golden_jump_offset: float = 0.0     # transient vertical hop offset (world units)
var golden_gait: float = 0.0            # walk-cycle phase (0..TAU); legs/arms read it in F5
var golden_gait_amp: float = 0.0        # 0 idle .. 1 walking — gait fades out when stopped
var golden_walk_side_mode: bool = false # F6 debug: old horizontal arena-walk mode
var golden_arena_scroll: Vector2 = Vector2.ZERO # F5 arena: manual terrain scroll delta/frame
var golden_walk_facing_deg: float = 0.0 # F5 arena robot facing around screen Z
var golden_robot_pitch_deg: float = 0.0 # F5 robot stand-up pitch (clean scalar source,
										# shared so parts compose Rz(facing)·Rx(pitch) — NOT
										# read back off unit1's basis, which euler-thrashes)
var golden_camera_zoom: float = 0.0     # F5 airplane wheel zoom-in amount, 0..1

# Fire the Golden state (G icon collected). Requires the full 5-unit formation.
func activate_golden() -> void:
	if golden_active:
		return
	golden_active = true
	golden_timer = GOLDEN_DURATION

# Tick the Golden countdown; ends the state when it runs out (FormationManager then
# drops the robot back into formation). Call once per frame from Main.
func update_golden() -> void:
	if not golden_active:
		return
	golden_timer -= 1
	if golden_timer <= 0:
		golden_timer = 0
		golden_active = false

# --- Golden robot humanoid animation: attack poses set by Unit1 each time a
# power fires, read by the limb units (U3 = arms, U5 = legs) to drive a human-
# like motion on top of the static robot rig. Each is a 0..1 envelope that
# snaps to 1 on the strike and Unit1 decays back toward 0. ---
var robot_punch: float = 0.0       # punching-arm thrust envelope
var robot_punch_side: int = 1      # +1 right arm punches, -1 left
var robot_kick: float = 0.0        # kicking-leg swing envelope
var robot_kick_side: int = 1       # +1 right leg kicks, -1 left
var robot_laser_pose: float = 0.0  # both arms raised to project the shoulder lasers
var robot_rocket_pose: float = 0.0 # brace/recoil for the omega rocket

func add_score(n: int):
	score += n

# --- Gameplay-testing debug flags (ON while tuning game feel) ---
var debug_endless_spawn: bool = false  # KEY_E toggles: forced fast enemy spawning
var debug_no_death: bool = false       # real game over now (CONTINUE flow handles revival)
# KEY_G motion-check sandbox: force the Golden robot to stand (5 units, all
# powers), freeze enemy spawns/contact, and trigger each pose by hand (Z punch /
# X kick / V laser / B rocket) — for inspecting the humanoid motions in isolation.
var motion_debug: bool = false
# Golden robot MOTION REVERTED (user request 2026-06-14): the Golden robot stands
# as a static combined shape — no limb animation at all. In robot mode every limb
# holds a fixed pose: no velocity banking, no idle sway, no punch/kick/laser/rocket
# pose motion. Only the combine/flip/scale SHAPE remains. (Kept as a single switch
# in case the animated robot is ever wanted again — leave true for the static one.)
var robot_static: bool = true

func add_exp(n: int) -> void:
	exp_points += n

func unit_level(uid: int) -> int:
	return unit_levels[uid - 1]

# 0.0 (start) → 1.0 (full power): half from collected units, half from total
# power-up levels. Drives enemy count and enemy attack strength.
func difficulty() -> float:
	var unit_d := float(formation_count - 1) / 4.0
	var lv_sum := 0
	for l in unit_levels:
		lv_sum += l
	var lv_d := float(lv_sum - 5) / 20.0
	# Deeper sectors ramp the baseline pressure (capped) so exploration escalates.
	var sector_d := clampf(float(sector) * 0.04, 0.0, 0.25)
	return clampf(unit_d * 0.5 + lv_d * 0.5 + sector_d, 0.0, 1.0)

# Enemies currently locked by Unit3's missile system (drawn by the HUD).
var lock_targets: Array = []
# Lock-on circle radius around the player (0 = hidden). Set by Unit3.
var lock_ring_radius: float = 0.0

# Per-frame cache of enemies inside the player's altitude band ("marked").
# Built once per frame on first request, then shared by every homing bullet —
# avoids each bullet scanning the whole enemies group itself.
var _marked_cache: Array = []
var _marked_cache_frame: int = -1

func marked_enemies() -> Array:
	if _marked_cache_frame == frame:
		return _marked_cache
	_marked_cache_frame = frame
	_marked_cache = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Node3D
		if e == null or not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		if e.has_method("is_in_player_range") and e.call("is_in_player_range"):
			_marked_cache.append(e)
	return _marked_cache

# Same idea for enemies clearly below the player's altitude band (Unit4 targets).
var _lower_cache: Array = []
var _lower_cache_frame: int = -1

func lower_enemies() -> Array:
	if _lower_cache_frame == frame:
		return _lower_cache
	_lower_cache_frame = frame
	_lower_cache = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Node3D
		if e == null or not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		var ea: Variant = e.get("alt")
		if ea != null and float(ea) * ALT_MAX < alt - 5.0:
			_lower_cache.append(e)
	return _lower_cache
