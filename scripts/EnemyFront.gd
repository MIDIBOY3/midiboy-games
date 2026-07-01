extends Node3D

# =====================================================================================
# Zako Front — Area Block System (design 2026-07-02)
# -------------------------------------------------------------------------------------
# The ZAKO travels the HERO's FUTURE side (free-scroll) and drops self-connecting "area blocks"
# into empty world CHUNKS ahead of the HERO — not 1-cell building, but slotting whole nasty AREAS
# into the future stage. Placements are persisted as WORLD CHUNK DATA (GameState.front_blocks), so
# when the HERO later advances into them they ARE the real stage (turrets fire, barriers block…).
#
# Front Build Zone (relative to the HERO — keeps the ZAKO from paving infinitely alongside it):
#   • HERO within 3 screens : LOCKED — no add/remove (and never buildable)
#   • 6–12 screens ahead    : buildable
#   • 15+ screens ahead     : too far — not buildable
#
# Area blocks carry HIGH / MID / LOW route info (open_alts): a continuous passable route is
# guaranteed by only placing a block that shares an open altitude with its neighbour ("通行不能禁止").
# Constraints: 1 block per band (per-chunk cap), placement cooldown + build credits (cost), turret
# density cap over a sliding window, socket-shape match, active-camera-only live nodes, off-screen
# sleep. NOTHING is naturally generated — the ZAKO places everything.
#
# NOTE: a first foundation. Lateral (side-socket) multi-block bands, manual ZAKO-driven placement
# UI, and final art are future work; here an auto-placer drives the ZAKO's construction.
# =====================================================================================

# --- Altitude routes -----------------------------------------------------------------
const LOW := 0
const MID := 1
const HIGH := 2

# --- World chunking ------------------------------------------------------------------
const CHUNK_H := 6.0          # one band / chunk row (~one screen of world-Y)
func _band_of(y: float) -> int: return int(floor(y / CHUNK_H))
func _band_y(b: int) -> float: return (float(b) + 0.5) * CHUNK_H
func _alt_norm(a: int) -> float: return float(a) * 0.5      # LOW 0.0 · MID 0.5 · HIGH 1.0
func _alt_z(a: int) -> float: return GameState.alt_z(_alt_norm(a) * GameState.ALT_MAX)

# --- Front Build Zone (spec 推奨距離) ------------------------------------------------
const SCREEN_H := 6.0
const LOCK_DIST := 3.0 * SCREEN_H     # 18 — HERO within this locks/forbids the front
const BUILD_NEAR := 6.0 * SCREEN_H    # 36 — nearest buildable
const BUILD_FAR := 12.0 * SCREEN_H    # 72 — farthest buildable
const HARD_FAR := 15.0 * SCREEN_H     # 90 — beyond this never buildable

# --- Placement limits ----------------------------------------------------------------
const GAUGE_MAX := 16.0               # terrain-paint gauge cap
const CREDIT_REGEN := 8               # +1 gauge every N frames — only while NOT painting
const MAX_PER_BAND := 6               # structures stacked per band (headroom; distance pacing limits)
const TURRET_WINDOW := 4              # bands
const TURRET_WINDOW_CAP := 8          # max turret pieces within any TURRET_WINDOW-band span (density)
const TURRET_SPACING := 4             # auto-drop a turret emplacement every Nth painted terrain piece

# --- Live node lifecycle (perf) ------------------------------------------------------
const LIVE_RANGE := 11.0              # spawn a block's nodes within this of cam_y
const DESPAWN_RANGE := 13.0           # free them past this (hysteresis)

# --- Turret combat -------------------------------------------------------------------
const TURRET_UPDATE_RANGE := 9.0
const TURRET_SCREEN_HALF := 3.6
const TURRET_DETECT_RANGE := 4.5
const TURRET_FIRE_PERIOD := 55
const TURRET_BULLET_SPEED := 0.045

# --- Area Block catalogue ------------------------------------------------------------
# open_alts : altitudes that pass end-to-end (adjacent blocks must share one → route survives).
# turrets/mines/platforms : how many parts the recipe spawns. sock_in/out : connector shape.
# cost : build credits. danger : per-altitude threat (telemetry/flavour, drives turret altitudes).
const BLOCKS := {
	"canyon_block":            {"cost": 1, "turrets": 0, "mines": 0, "platforms": 0, "sock_in": "corridor", "sock_out": "corridor"},
	"turret_base_block":       {"cost": 2, "turrets": 3, "mines": 0, "platforms": 0, "sock_in": "corridor", "sock_out": "corridor"},
	"minefield_block":         {"cost": 1, "turrets": 0, "mines": 6, "platforms": 0, "sock_in": "corridor", "sock_out": "corridor"},
	"barrier_gate_block":      {"cost": 1, "turrets": 1, "mines": 0, "platforms": 0, "sock_in": "corridor", "sock_out": "gate"},
	"floating_platform_block": {"cost": 1, "turrets": 0, "mines": 0, "platforms": 3, "sock_in": "corridor", "sock_out": "platform"},
	"supply_trap_block":       {"cost": 2, "turrets": 2, "mines": 0, "platforms": 0, "sock_in": "corridor", "sock_out": "corridor"},
	# Organic / reused-terrain pieces (see _build_block_nodes → _reuse_terrain).
	"island_block":            {"cost": 1, "turrets": 0, "mines": 0, "platforms": 0, "sock_in": "corridor", "sock_out": "corridor"},
	"rock_cluster_block":      {"cost": 1, "turrets": 0, "mines": 0, "platforms": 0, "sock_in": "corridor", "sock_out": "corridor"},
}
# Paint palette by ALTITUDE LAYER — the build layer (from the ZAKO's altitude) selects a FAMILY, and
# a stroke keeps one kind so it lays a CONTINUOUS feature: fly LOW to run roads / city grids / reefs
# along the ground, MID for rails & truss spans, HIGH for sky megastructures. Roads & rails are
# path-connected SEGMENTS (prev→cur); the rest are placed clumps. Turrets ride on top at intervals.
# "land" = a SOLID, gapless full-width continent ribbon (Star Soldier / Star Force scrolling terrain
# with tiled relief + bases), weighted heavily so a stroke lays a continuous landmass. Kept on both
# LOW (ground continent) and MID (floating continent) families.
const POOL_LOW := ["land", "land", "road", "city_district", "reef"]
const POOL_MID := ["land", "rail", "truss_field", "asteroid_field"]
const POOL_HIGH := ["mega_continent", "ringworld_arc", "tether_spire", "dyson_swarm",
	"crystal_spire_field", "floating_continent", "high_continent", "megacity_sprawl"]
const SEGMENT_KINDS := ["road", "rail"]   # drawn as a strip connecting the previous paint point

func _layer_pool(layer: int) -> Array:
	if layer == LOW:
		return POOL_LOW
	if layer == MID:
		return POOL_MID
	return POOL_HIGH

var _live: Dictionary = {}    # block id -> Array[Node] (spawned recipe nodes)
var _by_band: Dictionary = {} # band -> block entry (occupancy index)
var _next_id := 0
var _credits := GAUGE_MAX     # terrain-paint gauge (starts full)
var _credit_t := 0
var _paint_run := 0           # painted terrain pieces since the last auto turret emplacement
var _seed_f := 0.0            # per-run phase for the coastline noise (continuous landmass shape)

func _ready() -> void:
	add_to_group("enemy_front_mgr")
	_seed_f = float(GameState.run_seed % 1000) * 0.017
	# Rebuild the per-band piece index from any persisted data (a continuing run).
	for e: Dictionary in GameState.front_blocks:
		var b := int(e["band"])
		if not _by_band.has(b):
			_by_band[b] = []
		(_by_band[b] as Array).append(e)
		_next_id = maxi(_next_id, int(e["id"]) + 1)

func _process(_delta: float) -> void:
	_regen_credits()
	_update_locks()
	# Placement is by PAINTING (ZakoMode: hold R3 + fly → paint_at / erase). No auto-building.
	_sync_live_blocks()       # only chunks near the active camera hold live nodes
	_update_turrets()
	if OS.has_environment("TSG_DEBUG_FRONT") and (GameState.frame % 120) == 0:
		var meshes := 0
		for c in get_children():
			meshes += 1 + (c as Node).get_child_count()
		print("[FRONT] f=%d pieces=%d live=%d liveMeshes=%d cam_y=%.1f hero_y=%.1f" % [
			GameState.frame, GameState.front_blocks.size(), _live.size(), meshes,
			GameState.cam_y, GameState.hero_pos.y])

# -------------------------------------------------------------------------------------
# Placement (Front Build Zone + constraints)
# -------------------------------------------------------------------------------------
func _regen_credits() -> void:
	if GameState.build_painting:
		return                       # the gauge only refills while you're NOT painting
	_credit_t += 1
	if _credit_t >= CREDIT_REGEN:
		_credit_t = 0
		_credits = minf(GAUGE_MAX, _credits + 1.0)

# Lock any front the HERO has closed within LOCK_DIST of — spec: 編集ロック (no add/remove after).
func _update_locks() -> void:
	var hy := GameState.hero_pos.y
	for e: Dictionary in GameState.front_blocks:
		if not bool(e["locked"]) and float(e["y"]) - hy < LOCK_DIST:
			e["locked"] = true

# --- Paint API (driven by ZakoMode: hold-to-paint by flying + erase) ------------------
# Painting drops REAL TSG megastructures/terrain along the ZAKO's flight path (distance-paced, not
# per-frame), so a run of them overlaps into one big continuous mega-map. Persisted as world data;
# the HERO meets it for real on arrival.
func build_credits() -> float: return _credits     # current gauge value
func gauge_max() -> float: return GAUGE_MAX
func band_at(y: float) -> int: return _band_of(y)

const PIECE_COST := 1.2

# Can we still paint at this band? "" = yes; else why not. Cap is generous (distance pacing in
# ZakoMode is the real limiter) so the player rarely hits "full".
func can_paint(band: int, _layer: int) -> String:
	var ahead := _band_y(band) - GameState.hero_pos.y
	if ahead < LOCK_DIST:
		return "locked"
	if ahead < BUILD_NEAR:
		return "too_close"
	if ahead > BUILD_FAR:
		return "too_far"
	if (_by_band.get(band, []) as Array).size() >= MAX_PER_BAND:
		return "full"
	if _by_band.has(band) and _band_locked(band):
		return "locked"
	if _credits < PIECE_COST:
		return "no_gauge"
	return ""

# Paint one feature spanning from_pos→to_pos at `layer`. The kind is stable per (stroke, layer) so a
# held stroke lays a CONTINUOUS feature; roads/rails connect the two points into an unbroken ribbon.
# A turret rides on top every TURRET_SPACING pieces (spec: 砲台も地形の間隔で自動配置).
func paint_at(from_pos: Vector2, to_pos: Vector2, layer: int, stroke_id: int) -> String:
	var band := _band_of(to_pos.y)
	if can_paint(band, layer) != "":
		return ""
	var pool := _layer_pool(layer)
	var kind: String = pool[absi(stroke_id * 31 + layer * 7) % pool.size()]
	var turret := false
	if _paint_run >= TURRET_SPACING and _turret_count_in_window(band) < TURRET_WINDOW_CAP:
		turret = true
		_paint_run = 0
	else:
		_paint_run += 1
	var mid := (from_pos + to_pos) * 0.5
	var d := to_pos - from_pos
	var e := {
		"id": _next_id, "band": band, "y": mid.y,
		"x": clampf(mid.x, -GameState.PLAYFIELD_HALF_W, GameState.PLAYFIELD_HALF_W),
		"ang": atan2(d.y, d.x), "len": d.length(),
		"kind": kind, "layer": layer, "turret": turret, "locked": false,
	}
	_next_id += 1
	_credits = maxf(0.0, _credits - PIECE_COST)
	GameState.front_blocks.append(e)
	if not _by_band.has(band):
		_by_band[band] = []
	(_by_band[band] as Array).append(e)
	GameState.build_kind = kind
	return kind

func _band_locked(band: int) -> bool:
	for e: Dictionary in _by_band.get(band, []):
		if bool(e["locked"]):
			return true
	return false

# Erase every UNLOCKED piece in a band (scrub terrain as you fly over). Returns true if any went.
func remove_at_band(band: int) -> bool:
	var pieces: Array = _by_band.get(band, [])
	if pieces.is_empty():
		return false
	var kept: Array = []
	var removed := false
	for e: Dictionary in pieces:
		if bool(e["locked"]):
			kept.append(e)
			continue
		var id := int(e["id"])
		if _live.has(id):
			for n in _live[id]:
				if is_instance_valid(n):
					(n as Node).queue_free()
			_live.erase(id)
		GameState.front_blocks.erase(e)
		removed = true
	if kept.is_empty():
		_by_band.erase(band)
	else:
		_by_band[band] = kept
	return removed

func _turret_count_in_window(b: int) -> int:
	var n := 0
	for i in range(b - TURRET_WINDOW, b + 1):
		for e: Dictionary in _by_band.get(i, []):
			if bool(e.get("turret", false)):
				n += 1
	return n

# -------------------------------------------------------------------------------------
# Live nodes: only blocks near the active camera get spawned; off-screen ones sleep (freed).
# -------------------------------------------------------------------------------------
func _sync_live_blocks() -> void:
	var cam_y := GameState.cam_y
	for e: Dictionary in GameState.front_blocks:
		var id := int(e["id"])
		var dist := absf(float(e["y"]) - cam_y)
		var live: bool = _live.has(id)
		if dist < LIVE_RANGE and not live:
			_live[id] = _build_block_nodes(e)
			for n in _live[id]:
				_tag_destructible(n as Node)      # HERO's TERRAIN ATTACK can blast these
		elif live and dist > DESPAWN_RANGE:
			for n in _live[id]:
				if is_instance_valid(n):
					(n as Node).queue_free()
			_live.erase(id)

# Instantiate a piece: connected road/rail segment, a city grid / reef, or a REUSED real TSG
# megastructure/terrain built into a root at the piece's spot. Turrets ride on top if flagged.
func _build_block_nodes(e: Dictionary) -> Array:
	var kind := String(e["kind"])
	var id := int(e["id"])
	var by := float(e["y"])
	var px := float(e.get("x", 0.0))
	var la := int(e.get("layer", MID))
	var z := _alt_z(la)
	var pos := Vector3(px, by, z)
	var ang := float(e.get("ang", 0.0))
	var seg_len := float(e.get("len", 0.0))
	var nodes: Array = []
	match kind:
		"land":
			nodes.append(_build_land(pos, seg_len, id))
		"road":
			nodes.append(_build_road(pos, ang, seg_len, id))
		"rail":
			nodes.append(_build_rail(pos, ang, seg_len, id))
		"city_district":
			nodes.append(_build_city(pos, id))
		"reef":
			nodes.append(_build_reef(pos, id))
		_:
			var built := _reuse_structure(kind, pos, id)
			nodes.append(built if built != null else _spawn_blob(pos, id, Color(0.34, 0.42, 0.36)))
	if bool(e.get("turret", false)):
		nodes.append(_spawn_turret(pos + Vector3(0.0, 0.0, 0.0), id, _alt_norm(la)))
	return nodes

# --- SOLID continent (Star Soldier / Star Force style, gapless) ----------------------
# A full-width, axis-aligned solid ground SLAB spanning the segment length, so consecutive land
# pieces overlap into ONE unbroken scrolling landmass. On top: a tiled biome relief (green/rock/
# sand/water) + a few bases/domes/walls. Turrets come from the piece's turret flag.
func _build_land(pos: Vector3, seg_len: float, id: int) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = Vector3(0.0, pos.y, pos.z)   # full-width → centre on X
	var l := maxf(seg_len, 1.0) + 0.5
	var cols := 10
	var rows := maxi(2, int(l / 0.5))
	var cw := (GameState.PLAYFIELD_HALF_W * 2.0) / float(cols)
	var rh := l / float(rows)
	# Fill every cell INSIDE a wandering coastline (a function of world-Y, so segments line up),
	# with jagged peninsulas/coves at the edges — the interior stays solid, the outline is organic.
	for gy in rows:
		var ty := (float(gy) - float(rows - 1) * 0.5) * rh
		var wy := pos.y + ty
		var el := _coast_edge(wy, -1.0)
		var er := _coast_edge(wy, 1.0)
		for gx in cols:
			var fx := (float(gx) - float(cols - 1) * 0.5) / (float(cols) * 0.5)   # -1..1
			var hn := _hash2(floor(wy / rh) + float(gy) * 0.0, float(gx))
			var inside := fx >= el and fx <= er
			if not inside:
				# peninsula: a cell just outside the coast that juts out
				var near := (fx < el and fx > el - 0.30) or (fx > er and fx < er + 0.30)
				if near and hn > 0.66:
					inside = true
				else:
					continue
			else:
				# cove: occasionally bite a notch out of the coastal fringe
				var fringe := fx < el + 0.28 or fx > er - 0.28
				if fringe and hn < 0.12:
					continue
			var tx := fx * GameState.PLAYFIELD_HALF_W
			var th := 0.18 + hn * 0.16
			var tile := _mesh_box(Vector3(cw * 1.03, rh * 1.03, th), _land_tile_color_h(hn), 0.0)
			tile.position = Vector3(tx, ty, th * 0.5 - 0.1)
			root.add_child(tile)
	# Sparse bases / cores on the land (deterministic per row so overlapping slabs agree).
	var bh := _hash2(floor(pos.y), 91.0)
	if bh > 0.55:
		var sx := (_hash2(floor(pos.y), 17.0) - 0.5) * GameState.PLAYFIELD_HALF_W * 1.4
		if bh > 0.82:
			var core := _mesh_box(Vector3(0.26, 0.26, 0.26), Color(1.0, 0.55, 0.2), 1.2)
			core.position = Vector3(sx, 0.0, 0.18)
			root.add_child(core)
		else:
			var dome := _mesh_box(Vector3(0.36, 0.36, 0.24), Color(0.62, 0.58, 0.5), 0.12)
			dome.position = Vector3(sx, 0.0, 0.16)
			root.add_child(dome)
	return root

# Wandering coastline edge (fraction of half-width) as a smooth function of world-Y — continuous
# across segments. `side` = -1 (left) / +1 (right). Layered sines make bays and headlands.
func _coast_edge(wy: float, side: float) -> float:
	var e := 0.66 + 0.30 * sin(wy * 0.31 + _seed_f * 0.7 + side * 1.3) + 0.16 * sin(wy * 0.83 + side * 3.1)
	return side * clampf(e, 0.18, 1.0)

func _hash2(a: float, b: float) -> float:
	var v := sin(a * 12.9898 + b * 78.233 + _seed_f) * 43758.5453
	return v - floor(v)

func _land_tile_color_h(hn: float) -> Color:
	if hn < 0.42:
		return Color(0.18, 0.44, 0.24)       # green land
	elif hn < 0.66:
		return Color(0.5, 0.44, 0.28)        # sand
	elif hn < 0.85:
		return Color(0.32, 0.32, 0.35)       # rock
	return Color(0.10, 0.26, 0.42)           # water

# --- Connected / urban recipes -------------------------------------------------------
# A road ribbon spanning the segment (prev→cur): dark asphalt + centre dashes. Consecutive segments
# share endpoints, so a held stroke draws one continuous road.
func _build_road(pos: Vector3, ang: float, seg_len: float, id: int) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	var seg := Node3D.new()
	seg.rotation.z = ang
	root.add_child(seg)
	var length := maxf(seg_len, 0.6) + 0.5   # overlap so segments join seamlessly
	var road := _mesh_box(Vector3(length, 0.9, 0.08), Color(0.14, 0.14, 0.16), 0.0)
	seg.add_child(road)
	var dashes := int(length / 0.5)
	for i in dashes:
		var dx := -length * 0.5 + (float(i) + 0.5) * 0.5
		var m := _mesh_box(Vector3(0.22, 0.06, 0.02), Color(0.9, 0.85, 0.4), 0.6)
		m.position = Vector3(dx, 0.0, 0.06)
		seg.add_child(m)
	return root

# Twin rails + sleepers spanning the segment.
func _build_rail(pos: Vector3, ang: float, seg_len: float, id: int) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	var seg := Node3D.new()
	seg.rotation.z = ang
	root.add_child(seg)
	var length := maxf(seg_len, 0.6) + 0.5
	for side in [-0.24, 0.24]:
		var rail := _mesh_box(Vector3(length, 0.06, 0.09), Color(0.6, 0.62, 0.68), 0.2)
		rail.position = Vector3(0.0, side, 0.05)
		seg.add_child(rail)
	var ties := int(length / 0.32)
	for i in ties:
		var tx := -length * 0.5 + (float(i) + 0.5) * 0.32
		var t := _mesh_box(Vector3(0.1, 0.62, 0.06), Color(0.3, 0.22, 0.16), 0.0)
		t.position = Vector3(tx, 0.0, 0.0)
		seg.add_child(t)
	return root

# A city district: a grid of buildings with street gaps — the "街の区画".
func _build_city(pos: Vector3, id: int) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var cols := 4 + rng.randi() % 3
	var rows := 3 + rng.randi() % 3
	var cell := 0.5
	for gy in rows:
		for gx in cols:
			if (gx % 3) == 2 or (gy % 3) == 2:
				continue                                  # leave street lanes
			var bx := (float(gx) - float(cols - 1) * 0.5) * cell
			var byy := (float(gy) - float(rows - 1) * 0.5) * cell
			var h := rng.randf_range(0.18, 0.6)
			var lit := rng.randf() < 0.5
			var col := Color(0.4, 0.45, 0.55).lerp(Color(0.5, 0.55, 0.62), rng.randf())
			var b := _mesh_box(Vector3(cell * 0.72, cell * 0.72, h), col, 0.1 if lit else 0.0)
			b.position = Vector3(bx, byy, h * 0.5)
			root.add_child(b)
	return root

# A rocky reef ridge (岩礁): a jagged cluster of tilted rock spikes.
func _build_reef(pos: Vector3, id: int) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	for _i in 5 + rng.randi() % 5:
		var h := rng.randf_range(0.25, 0.85)
		var w := rng.randf_range(0.14, 0.3)
		var m := _mesh_box(Vector3(w, w, h), Color(0.30, 0.27, 0.24).lerp(Color(0.16, 0.16, 0.18), rng.randf() * 0.6), 0.0)
		m.position = Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(-CHUNK_H * 0.35, CHUNK_H * 0.35), h * 0.4)
		m.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3), rng.randf_range(0.0, TAU))
		root.add_child(m)
	return root

# Shared little mesh-box helper for the recipes above.
func _mesh_box(size: Vector3, col: Color, emis: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.7
	if emis > 0.0:
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = emis
	m.material_override = mat
	return m

# Reuse a REAL builder from SpaceStructures (megastructures/continents/truss) or PlanetTerrain (large
# terrain), building into a scaled root at `world_pos`. Guarded — if the source node or its shared
# materials aren't ready, returns null so the caller falls back to a procedural blob.
func _reuse_structure(kind: String, world_pos: Vector3, id: int) -> Node3D:
	var ss := get_tree().get_first_node_in_group("space_structures")
	var pt := get_tree().get_first_node_in_group("planet_terrain")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var t := 0.6 + rng.randf() * 0.35
	var root := Node3D.new()
	add_child(root)
	root.global_position = world_pos
	var scale := 0.7
	var ss_ok: bool = ss != null and ss.get("_box_mesh") != null
	var pt_ok: bool = pt != null and (pt.get("_decor") is Dictionary) and not (pt.get("_decor") as Dictionary).is_empty()
	match kind:
		"mega_continent":
			if ss_ok: ss.call("_build_far_mega_continent", root)
			scale = 0.62
		"truss_field":
			if ss_ok: ss.call("_build_truss_field", root, t)
		"asteroid_field":
			if ss_ok: ss.call("_build_asteroid_field", root, t)
		"ridge_islands":
			if ss_ok: ss.call("_build_ridge_islands", root, t)
		"space_canyon":
			if ss_ok: ss.call("_build_space_canyon", root, t)
		"floating_continent":
			if ss_ok: ss.call("_build_floating_continent", root, t)
			scale = 0.66
		"honeycomb":
			if ss_ok: ss.call("_build_honeycomb_field", root, t)
		"high_continent":
			if ss_ok: ss.call("_build_high_continent", root, t)
			scale = 0.66
		"ringworld_arc", "tether_spire", "dyson_swarm", "crystal_spire_field", "megacity_sprawl":
			if ss_ok: ss.call("_build_grand", root, kind, t)
		"block_island":
			if pt_ok: pt.call("_large_block_island", root, 0.0, rng, false)
			scale = 2.2
		"rock_mesa":
			if pt_ok: pt.call("_large_rock_mesa", root, 0.0, rng)
			scale = 2.2
		"rock_cluster":
			if pt_ok: pt.call("_poly_rock_cluster", root, 0.0, rng)
			scale = 2.2
	root.scale = Vector3.ONE * scale
	if root.get_child_count() == 0:      # source unavailable → let the caller draw a blob instead
		root.queue_free()
		return null
	root.rotation.z = rng.randf_range(-0.15, 0.15)
	return root

# Procedural organic blob (island/rock fallback): a random clump of scaled cubes.
func _spawn_blob(center: Vector3, id: int, col: Color) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = center
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	for _i in 6 + rng.randi() % 5:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		var s := rng.randf_range(0.18, 0.46)
		box.size = Vector3(s, s, s * rng.randf_range(0.6, 1.2))
		m.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col.lerp(Color(0.1, 0.1, 0.12), rng.randf() * 0.4)
		mat.roughness = 0.8
		m.material_override = mat
		m.position = Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-CHUNK_H * 0.35, CHUNK_H * 0.35), rng.randf_range(-0.2, 0.2))
		m.rotation.z = rng.randf_range(0.0, TAU)
		root.add_child(m)
	return root

# -------------------------------------------------------------------------------------
# Recipe part spawners
# -------------------------------------------------------------------------------------
func _spawn_turret(pos: Vector3, block_id: int, alt_norm: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.34, 0.34, 0.30)
	m.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.16, 0.10)
	mat.metallic = 0.4
	mat.roughness = 0.35
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.12)
	mat.emission_energy_multiplier = 1.5
	m.material_override = mat
	m.position = pos
	m.add_to_group("enemy_front")
	m.set_meta("fire_cd", randi() % TURRET_FIRE_PERIOD)   # stagger so they don't fire in sync
	m.set_meta("front_id", block_id)
	m.set_meta("alt", alt_norm)                           # threat altitude (for fire + markers)
	add_child(m)
	return m

func _spawn_box(pos: Vector3, size: Vector3, col: Color, emis: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = 0.2
	mat.roughness = 0.6
	if emis > 0.0:
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = emis
	m.material_override = mat
	m.position = pos
	m.add_to_group("front_obstacle")
	add_child(m)
	return m

func _spawn_mine(pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.11
	sph.height = 0.22
	m.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.18)
	mat.metallic = 0.7
	mat.roughness = 0.3
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.1)
	mat.emission_energy_multiplier = 0.6
	m.material_override = mat
	m.position = pos
	m.add_to_group("front_hazard")
	add_child(m)
	return m

# -------------------------------------------------------------------------------------
# Turret fire — only turrets near the ACTIVE camera update; only on-screen ones that detect the
# HERO fire (spec: off-screen turrets sleep). They shoot the HERO at their own threat altitude.
# -------------------------------------------------------------------------------------
func _update_turrets() -> void:
	var cam_y := GameState.cam_y
	var hero := GameState.hero_pos
	for n in get_tree().get_nodes_in_group("enemy_front"):
		var t := n as Node3D
		if t == null or not is_instance_valid(t):
			continue
		var ty := t.position.y
		if absf(ty - cam_y) > TURRET_UPDATE_RANGE:
			continue                                  # far from the active camera → asleep
		var cd := int(t.get_meta("fire_cd", TURRET_FIRE_PERIOD)) - 1
		var on_screen := absf(ty - cam_y) < TURRET_SCREEN_HALF
		var to_hero := hero - Vector2(t.position.x, ty)
		if cd <= 0 and on_screen and to_hero.length() < TURRET_DETECT_RANGE:
			cd = TURRET_FIRE_PERIOD
			_turret_fire(t, to_hero.normalized())
		t.set_meta("fire_cd", cd)

func _turret_fire(t: Node3D, dir: Vector2) -> void:
	var b := EnemyBullet.new()
	b.bullet_type = "shot"
	b.velocity = Vector3(dir.x, dir.y, 0.0) * TURRET_BULLET_SPEED
	b.alt = float(t.get_meta("alt", clampf(GameState.hero_alt / GameState.ALT_MAX, 0.0, 1.0)))
	b.position = t.position
	add_child(b)

# -------------------------------------------------------------------------------------
# Editing
# -------------------------------------------------------------------------------------
# --- HERO TERRAIN ATTACK (destructible front terrain) --------------------------------
# Tag every recipe MeshInstance (not the shootable turrets) as a destructible "front_block" with a
# cached world radius, so the HERO's bullets can blast the painted terrain via try_block_hit.
func _tag_destructible(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if not mi.is_in_group("enemy_front"):     # turrets keep their own shootable path
			var ab := mi.get_aabb()
			var sc := mi.global_transform.basis.get_scale()
			mi.set_meta("wr", 0.5 * maxf(ab.size.x * sc.x, ab.size.y * sc.y) + 0.04)
			mi.add_to_group("front_block")
	for c in node.get_children():
		_tag_destructible(c)

# GENESIS terrain-attack hook: a player bullet at `p` blasts the nearest live front block it
# overlaps (matching altitude/layer). Returns hit info (Main frees the bullet + spark), or {}.
func try_block_hit(p: Vector3) -> Dictionary:
	var p2 := Vector2(p.x, p.y)
	for n in get_tree().get_nodes_in_group("front_block"):
		var m := n as MeshInstance3D
		if m == null or not is_instance_valid(m) or m.is_queued_for_deletion():
			continue
		var mp := m.global_position
		var wr := float(m.get_meta("wr", 0.15))
		if absf(mp.y - p.y) > wr + 0.1 or absf(mp.z - p.z) > 0.9:
			continue                               # y band + altitude/layer must roughly match
		if p2.distance_squared_to(Vector2(mp.x, mp.y)) < wr * wr:
			var col := Color(0.5, 0.5, 0.55)
			var mat := m.material_override
			if mat is StandardMaterial3D:
				col = (mat as StandardMaterial3D).albedo_color
			m.queue_free()
			return {"pos": mp, "color": col, "effect_count": 6, "effect_strength": 0.6}
	return {}

# A turret sub-part was destroyed by HERO fire: drop it from its block's live node list (the block
# data persists — a wrecked turret stays wrecked while its area block remains the stage).
func remove_turret(t: Node3D) -> void:
	if t == null:
		return
	var id := int(t.get_meta("front_id", -1))
	if _live.has(id):
		(_live[id] as Array).erase(t)
	# The node itself is freed by the caller.

# Clear the whole front (new run / reset).
func clear_front() -> void:
	for arr in _live.values():
		for n in arr:
			if is_instance_valid(n):
				(n as Node).queue_free()
	_live.clear()
	_by_band.clear()
	GameState.front_blocks.clear()
	GameState.enemy_front.clear()
	_next_id = 0
	_credits = 4.0
