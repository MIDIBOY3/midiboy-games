class_name SpaceStructures
extends Node3D

const MAX_PROPS := 5
const SPAWN_FRAMES := 78
const HIT_Z_RANGE := 0.55
const APPROACH_SPAWN_CUTOFF := 0.42
const APPROACH_CLEAR_AT := 0.88
const LANE_WARN_FRAMES := 96     # how long the AltGauge previews a lane before it appears
const LANE_ALT_TOL := 35.0       # altitude window to count as "on the lane"

# Mega-continent systems: a continuous landmass tiled from back-to-back bands at
# the front (shootable) flight plane, carrying destructible bases + a few guns.
const CONT_Z := -1.2             # in the player's shootable z range (alt_to_z spans -2..2)
const CONT_BAND_H := 3.0         # world height of one tiled band
const CONT_SPAWN_TOP := 11.0     # keep the column filled up to here (well above screen)
const CONT_WIDTH := 8.4          # full-screen-width landmass at CONT_Z
const GUN_FIRE_Z := 0.9          # a gun fires only when the player dives to its layer

static var _box_mesh: BoxMesh
static var _mat_base: StandardMaterial3D
static var _mat_shadow: StandardMaterial3D
static var _mat_edge: StandardMaterial3D
static var _mat_hive: StandardMaterial3D
static var _mat_crystal: StandardMaterial3D
static var _mat_grass: StandardMaterial3D
static var _mat_sand: StandardMaterial3D
static var _mat_city: StandardMaterial3D
static var _mat_asteroid: StandardMaterial3D
static var _mat_ruin: StandardMaterial3D
static var _mat_boost: StandardMaterial3D       # glowing chevron arrows
static var _mat_boost_base: StandardMaterial3D  # dark runway strip

var _timer: int = 18
var _lane_timer: int = 120
var _pending_lane_alt: float = -1.0
var _blocks: Array = []

func _ready() -> void:
	add_to_group("space_structures")
	add_to_group("space_terrain")
	_make_shared()

func _make_shared() -> void:
	if _box_mesh == null:
		_box_mesh = BoxMesh.new()
		_box_mesh.size = Vector3.ONE
	if _mat_base == null:
		_mat_base = _mat(Color(0.12, 0.10, 0.16))
		_mat_shadow = _mat(Color(0.055, 0.065, 0.09))
		_mat_edge = _mat(Color(0.20, 0.62, 0.88))
		_mat_hive = _mat(Color(0.78, 0.46, 0.12))
		_mat_crystal = _mat(Color(0.22, 0.90, 0.95))
		_mat_grass = _mat(Color(0.18, 0.52, 0.28))
		_mat_sand = _mat(Color(0.70, 0.56, 0.28))
		_mat_city = _mat(Color(0.36, 0.39, 0.48))
		_mat_asteroid = _mat(Color(0.27, 0.25, 0.23))
		_mat_ruin = _mat(Color(0.42, 0.36, 0.28))
		_mat_boost = _mat(Color(0.20, 0.90, 1.0))
		_mat_boost.emission_enabled = true
		_mat_boost.emission = Color(0.20, 0.90, 1.0)
		_mat_boost.emission_energy_multiplier = 3.0
		_mat_boost_base = _mat(Color(0.04, 0.06, 0.10))

# Re-tint the shared structure materials to the CONTINUOUSLY crossfaded region
# palette (sector → next by sector_blend), so the space architecture drifts in
# color from region to region with no hard switch. Materials are static/shared,
# so this re-tints every prop at once; called each frame while in space.
func _update_sector_palette() -> void:
	if _mat_base == null:
		return
	var base: Color = GameState.sector_color("base")
	var struct_c: Color = GameState.sector_color("struct")
	var accent: Color = GameState.sector_color("accent")
	_mat_base.albedo_color = base
	_mat_shadow.albedo_color = base.darkened(0.5)
	_mat_edge.albedo_color = struct_c
	_mat_crystal.albedo_color = accent
	_mat_hive.albedo_color = struct_c.lerp(accent, 0.5)
	_mat_city.albedo_color = base.lerp(struct_c, 0.4)
	_mat_asteroid.albedo_color = base.lerp(Color(0.30, 0.28, 0.26), 0.6)
	_mat_ruin.albedo_color = base.lerp(Color(0.42, 0.36, 0.28), 0.6)
	# Boost lanes glow in the region accent and pulse so they read as "ride me".
	_mat_boost.albedo_color = accent
	_mat_boost.emission = accent
	_mat_boost.emission_energy_multiplier = 2.4 + 1.6 * sin(GameState.frame * 0.18)

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.88
	m.emission_enabled = false
	return m

func _process(_delta: float) -> void:
	if GameState.stage != "space" or GameState.in_transition():
		_clear_all()
		return
	# Final boss + ending, the title/intro, and the black-hole boss system: keep
	# space empty/clean (no structures during the duel — just the dark and the boss).
	if GameState.final_phase != GameState.FINAL_NONE \
			or GameState.title_active or GameState.intro_active \
			or GameState.blackhole_active or GameState.god_phase > 0:
		_clear_all()
		return
	_update_sector_palette()
	_prune_blocks()
	var approach := _planet_approach()
	var pass_t := smoothstep(0.18, 0.86, approach)
	var altitude_flow := _altitude_flow_t()
	_timer -= 1
	if approach > APPROACH_CLEAR_AT:
		_clear_all()
		return
	if approach < APPROACH_SPAWN_CUTOFF:
		# Mega-continent systems: keep the endless landmass column filled and let its
		# ground guns fire. Scattered props become rare flyovers above the continent.
		var mega := _is_mega_continent()
		if mega:
			_maintain_continent()
			_update_guns()
			_grind_continent()
		if _timer <= 0:
			# Per-system spawn rate + on-screen count (randomized per star system).
			var th := GameState.sector_theme()
			_timer = int((SPAWN_FRAMES + randi() % 90) * float(th.get("struct_rate", 1.0)))
			if mega:
				if randf() < 0.35 and _count_non_continent() < 3:
					_spawn_prop()
			elif get_child_count() < int(th.get("struct_count", MAX_PROPS)):
				_spawn_prop()
	# Boost lanes appear at a RANDOM altitude (low ones too) ONLY while NOT homing on
	# a star. The upcoming lane's altitude is previewed on the AltGauge so the player
	# can climb/dive to meet it, then steer onto the glowing strip	_update_boost_lane_nav()
	var can_lane := GameState.target_star == "" and approach < APPROACH_SPAWN_CUTOFF \
		and not GameState.transitioning and not GameState.gate_active
	_lane_timer -= 1
	if not can_lane:
		_lane_timer = maxi(_lane_timer, LANE_WARN_FRAMES + 1)  # hold so a preview shows on resume
		GameState.boost_lane_warn_alt = -1.0
	else:
		if _pending_lane_alt < 0.0:
			_pending_lane_alt = randf_range(GameState.GROUND_ALT + 18.0, GameState.ALT_MAX - 12.0)
		GameState.boost_lane_warn_alt = _pending_lane_alt if _lane_timer <= LANE_WARN_FRAMES else -1.0
		if _lane_timer <= 0 and _count_lanes() < 2:
			_spawn_boost_lane(_pending_lane_alt)
			_pending_lane_alt = -1.0
			GameState.boost_lane_warn_alt = -1.0
			_lane_timer = 240 + randi() % 260
	for c in get_children():
		var n := c as Node3D
		if n == null:
			continue
		# Mega-continent bands are a FIXED-plane landmass: they must NOT get the flyby
		# pass_t zoom (scale ×8.5), z-rush or -4.2 compression — that ballooned them
		# (huge geometry = lag) and broke the tiling (gaps/overlap/"weird scroll") on
		# altitude changes, leaving stale bands stacked up. Scroll them simply instead.
		if n.get_meta("is_continent", false):
			var cspeed: float = float(n.get_meta("speed", 0.013)) \
				* lerpf(1.25, 0.82, GameState.sky_t()) * (1.0 + GameState.nav_boost * 2.0)
			n.position.y -= cspeed
			n.position.x = float(n.get_meta("base_x", 0.0)) \
				- GameState.px * float(n.get_meta("parallax", 0.12))
			n.position.z = float(n.get_meta("base_z", CONT_Z))   # fixed plane
			n.scale = n.get_meta("base_scale", Vector3.ONE)      # fixed size (no ×8.5)
			if n.position.y < float(n.get_meta("despawn_y", -7.0)):
				n.queue_free()
			continue
		var speed: float = n.get_meta("speed", 0.012)
		var base_x: float = n.get_meta("base_x", 0.0)
		var parallax: float = n.get_meta("parallax", 0.12)
		var phase: float = n.get_meta("phase", 0.0)
		var base_z: float = n.get_meta("base_z", n.position.z)
		var base_scale: Vector3 = n.get_meta("base_scale", n.scale)
		var flyby_speed := speed * lerpf(1.25, 0.82, GameState.sky_t()) \
			* lerpf(1.0, 14.0, pass_t) * (1.0 + GameState.nav_boost * 2.0)
		n.position.y -= flyby_speed
		n.position.x = base_x - GameState.px * parallax + sin(GameState.frame * 0.012 + phase) * 0.06
		var pass_y := lerpf(n.position.y, -4.2, pass_t * 0.16)
		n.position.y = pass_y
		# Altitude is distance: while descending into the target planet, space
		# scenery should rush past the camera and disappear before the surface.
		# When climbing back out, this relaxes and new props spawn normally again.
		var front_z := lerpf(2.2, 4.8, altitude_flow)
		n.position.z = lerpf(base_z, front_z, pass_t)
		n.scale = base_scale * lerpf(1.0, 8.5, pass_t)
		if n.get_meta("is_boost_lane", false):
			_check_boost_lane(n)
		var despawn_y: float = n.get_meta("despawn_y", -8.6)
		if n.position.y < lerpf(despawn_y, -2.1, pass_t):
			n.queue_free()

func _planet_approach() -> float:
	var raw := get_tree().get_first_node_in_group("target_planet")
	var planet := raw as TargetPlanet
	return planet.approach if planet != null else 0.0

func _altitude_flow_t() -> float:
	return clampf((GameState.ALT_MAX - GameState.alt) \
		/ (GameState.ALT_MAX - GameState.GROUND_ALT), 0.0, 1.0)

func _clear_all() -> void:
	for c in get_children():
		c.queue_free()
	_blocks.clear()
	GameState.boost_lane_alts.clear()
	GameState.boost_lane_warn_alt = -1.0

func _prune_blocks() -> void:
	# A block's MultiMesh node is freed when its band scrolls off → drop the stale record.
	for i in range(_blocks.size() - 1, -1, -1):
		var mmi: Variant = _blocks[i].get("mmi")
		if mmi == null or not is_instance_valid(mmi) or (mmi as Node).is_queued_for_deletion():
			_blocks.remove_at(i)

func _spawn_prop() -> void:
	var root := Node3D.new()
	var roll_layer := randf()
	var z := -1.7
	if roll_layer < 0.12:
		z = -13.5
	elif roll_layer < 0.30:
		z = -9.5
	elif roll_layer < 0.58:
		z = -5.4
	elif roll_layer > 0.92:
		z = 0.9
	var near_t := clampf((z + 10.0) / 8.3, 0.0, 1.0)
	var setpiece := randf() < 0.28
	# Per-system structure size multiplier (randomized per star system).
	var sys_scale := float(GameState.sector_theme().get("struct_scale", 1.0))
	var sc := lerpf(0.62, 1.52, near_t) * (1.22 if setpiece else 1.0) * sys_scale
	root.scale = Vector3.ONE * sc
	root.position = Vector3(randf_range(-3.3, 3.3), 7.4 + randf() * 2.7 + (1.8 if setpiece else 0.0), z)
	root.set_meta("base_z", z)
	root.set_meta("base_scale", root.scale)
	root.set_meta("base_x", root.position.x)
	root.set_meta("parallax", lerpf(0.025, 0.40, near_t))
	root.set_meta("speed", lerpf(0.0038, 0.019, near_t) * (0.78 if setpiece else 1.0))
	root.set_meta("phase", randf() * TAU)
	root.set_meta("despawn_y", -11.2 if setpiece else -8.6)
	root.set_meta("damage_enabled", false)
	add_child(root)
	# Per-system flavor: in the mid/near layers, often build one of this star
	# system's signature megastructures (backdrop-weighted "struct_kinds").
	var grand: Array = GameState.sector_theme().get("struct_kinds", [])
	if not setpiece and z >= -11.0 and z <= 0.0 and not grand.is_empty() and randf() < 0.45:
		_build_grand(root, str(grand[randi() % grand.size()]), near_t)
		_finalize_batch(root)
		return
	var roll := randi() % 14
	if setpiece and roll < 5:
		_build_world_fragment(root, near_t)
	elif setpiece and roll < 9:
		_build_orbital_ruins(root, near_t)
	elif z < -11.0:
		if roll < 8:
			_build_far_mega_continent(root)
		else:
			_build_asteroid_field(root, near_t)
	elif z > 0.0:
		if roll < 8:
			_build_high_continent(root, near_t)
		else:
			_build_asteroid_field(root, near_t)
	elif roll <= 4:
		_build_open_space_terrain(root, near_t)
	elif roll <= 6:
		_build_space_canyon(root, near_t)
	elif roll <= 8:
		_build_asteroid_field(root, near_t)
	elif roll == 9:
		_build_honeycomb_field(root, near_t)
	elif roll <= 11:
		_build_truss_field(root, near_t)
	else:
		_build_station(root, near_t)
	_finalize_batch(root)

func _count_lanes() -> int:
	var n := 0
	for c in get_children():
		if (c as Node3D) != null and c.get_meta("is_boost_lane", false):
			n += 1
	return n

# Publish active lane altitudes to the HUD so the AltGauge can navigate to them.
func _update_boost_lane_nav() -> void:
	GameState.boost_lane_alts.clear()
	for c in get_children():
		var n := c as Node3D
		if n != null and n.get_meta("is_boost_lane", false):
			GameState.boost_lane_alts.append(float(n.get_meta("lane_alt", 0.0)))

# A glowing F-Zero-style runway sitting at its own altitude plane that drifts down
# the screen. Match its altitude (AltGauge) and steer onto it (see _check_boost_lane)
# to vroom forward and bank nav distance.
func _spawn_boost_lane(lane_alt: float) -> void:
	var root := Node3D.new()
	var z := GameState.alt_to_z(lane_alt)
	root.position = Vector3(randf_range(-2.6, 2.6), 7.8, z)
	root.set_meta("base_z", z)
	root.set_meta("base_scale", Vector3.ONE)
	root.set_meta("base_x", root.position.x)
	root.set_meta("parallax", 0.34)
	root.set_meta("speed", 0.020)
	root.set_meta("phase", randf() * TAU)
	root.set_meta("despawn_y", -8.8)
	root.set_meta("damage_enabled", false)
	root.set_meta("is_boost_lane", true)
	root.set_meta("lane_alt", lane_alt)
	add_child(root)
	_build_boost_lane(root)
	_finalize_batch(root)

func _build_boost_lane(root: Node3D) -> void:
	_box(root, Vector3(0.0, 0.0, -0.05), Vector3(0.92, 2.1, 0.05), _mat_boost_base)
	# Forward-pointing chevrons (apex up = the direction of travel).
	for i in range(5):
		var y := -0.84 + float(i) * 0.42
		_box(root, Vector3(-0.20, y, 0.03), Vector3(0.40, 0.10, 0.07), _mat_boost,
			false, "ORE", Color.WHITE, 38.0)
		_box(root, Vector3(0.20, y, 0.03), Vector3(0.40, 0.10, 0.07), _mat_boost,
			false, "ORE", Color.WHITE, -38.0)

func _check_boost_lane(n: Node3D) -> void:
	# Ridden when the ship matches the lane's altitude AND lines up with it on screen.
	var lane_alt := float(n.get_meta("lane_alt", 0.0))
	if absf(GameState.alt - lane_alt) < LANE_ALT_TOL \
			and absf(GameState.px - n.position.x) < 0.62 \
			and absf(GameState.py - n.position.y) < 1.05:
		GameState.trigger_nav_boost(1.0)

func try_block_hit(p: Vector3) -> Dictionary:
	if GameState.stage != "space":
		return {}
	for i in range(_blocks.size() - 1, -1, -1):
		var rec: Dictionary = _blocks[i]
		if not rec.get("destructible", false):
			continue
		if rec.get("heavy", false):
			continue  # foundation crust: only area attacks (blast) break it, not bullets
		var gp := _block_world_pos(rec)
		if gp == Vector3.INF:                 # its band (MultiMesh) was freed
			_blocks.remove_at(i)
			continue
		if absf(p.z - gp.z) > HIT_Z_RANGE:
			continue
		var r := _world_hit_radius(rec)
		var dx := p.x - gp.x
		var dy := p.y - gp.y
		if dx * dx + dy * dy <= r * r:
			var color: Color = rec.get("color", Color(0.6, 0.7, 0.8))
			var res: String = rec.get("res", "ORE")
			_kill_instance(rec)
			_blocks.remove_at(i)
			return {"res": res, "color": color, "pos": gp}
	return {}

# Area terrain-attack (bombs / robot powers / ship grind): destroys every
# destructible block within radius of p on its z-layer and returns the drops, so
# the player can carve a hole through the mega-continent and descend through it.
# Matches PlanetTerrain.blast()'s drop format so the same _collect_drops works.
func blast(p: Vector3, radius: float) -> Array:
	var drops: Array = []
	if GameState.stage != "space":
		return drops
	var z_range := maxf(radius, HIT_Z_RANGE)
	for i in range(_blocks.size() - 1, -1, -1):
		var rec: Dictionary = _blocks[i]
		if not rec.get("destructible", false):
			continue
		var gp := _block_world_pos(rec)
		if gp == Vector3.INF:                 # its band (MultiMesh) was freed
			_blocks.remove_at(i)
			continue
		if absf(p.z - gp.z) > z_range:
			continue
		if Vector2(gp.x, gp.y).distance_to(Vector2(p.x, p.y)) > radius:
			continue
		drops.append({"res": rec.get("res", "ORE"), "color": rec.get("color", Color(0.6, 0.7, 0.8)),
			"pos": gp, "rare": rec.get("rare", false)})
		_kill_instance(rec)
		_blocks.remove_at(i)
	return drops

func _world_hit_radius(rec: Dictionary) -> float:
	# Check validity on the raw Variant BEFORE casting: `freed_object as Node3D` throws
	# "Trying to cast a freed object" (the band's MultiMesh may already be freed).
	var raw: Variant = rec.get("mmi")
	var sz: Vector3 = rec.get("size", Vector3.ONE)
	var b := Basis.IDENTITY
	if raw != null and is_instance_valid(raw):
		b = (raw as Node3D).global_transform.basis
	return maxf(0.18, maxf(b.x.length() * sz.x, b.y.length() * sz.y) * 0.72)

# Collapse the temporary per-block MeshInstance3D nodes this root just built into one
# MultiMesh per material. Godot Forward+ does NOT auto-batch MeshInstance3D, so a mega-
# continent band of ~150 boxes was ~150 draw calls; this makes it ~(materials used).
# The temps carry each block's FINAL local transform (builders set extra rotation on the
# returned node after _box), so we read transform, pack it, rewire any destructible
# block's _blocks record from {node} to {mmi, slot}, then free the temps. Pixel-identical.
func _finalize_batch(root: Node3D) -> void:
	var temps: Array = []
	for c in root.get_children():
		if c is MeshInstance3D:
			temps.append(c)
	if temps.is_empty():
		return
	# node -> its _blocks record (only destructible blocks have one).
	var rec_by_node := {}
	for rec in _blocks:
		var rn: Variant = rec.get("node")
		if rn != null:
			rec_by_node[rn] = rec
	# Group temps by material, preserving creation order so slot indices are stable.
	var groups: Dictionary = {}
	var order: Array = []
	for t: MeshInstance3D in temps:
		var mat: Material = t.material_override
		if not groups.has(mat):
			groups[mat] = []
			order.append(mat)
		(groups[mat] as Array).append(t)
	for mat: Material in order:
		var grp: Array = groups[mat]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _box_mesh
		mm.instance_count = grp.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		root.add_child(mmi)
		for slot in grp.size():
			var t: MeshInstance3D = grp[slot]
			var xf := t.transform
			mm.set_instance_transform(slot, xf)
			if rec_by_node.has(t):
				var rec: Dictionary = rec_by_node[t]
				rec.erase("node")
				rec["mmi"] = mmi
				rec["slot"] = slot
				rec["lpos"] = xf.origin
				var b := xf.basis
				rec["size"] = Vector3(b.x.length(), b.y.length(), b.z.length())
	for t: MeshInstance3D in temps:
		t.free()

# Destroy a block visually: zero-scale its MultiMesh instance (slots stay stable, so no
# reindex; the whole MultiMesh is freed when its band scrolls off). World position is
# recovered from the instance's stored local origin via the MultiMesh node.
func _kill_instance(rec: Dictionary) -> void:
	var raw: Variant = rec.get("mmi")
	if raw == null or not is_instance_valid(raw):
		return
	var mmi := raw as MultiMeshInstance3D
	var mm := mmi.multimesh
	var slot: int = rec.get("slot", -1)
	if mm == null or slot < 0 or slot >= mm.instance_count:
		return
	var t: Transform3D = mm.get_instance_transform(slot)
	mm.set_instance_transform(slot, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), t.origin))

func _block_world_pos(rec: Dictionary) -> Vector3:
	var raw: Variant = rec.get("mmi")
	if raw == null or not is_instance_valid(raw):
		return Vector3.INF
	return (raw as Node3D).to_global(rec.get("lpos", Vector3.ZERO))

func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material,
		destructible: bool = false, res: String = "ORE", color: Color = Color.WHITE,
		rz: float = 0.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = _box_mesh
	m.position = pos
	m.scale = size
	m.rotation_degrees.z = rz
	m.material_override = mat
	parent.add_child(m)
	if destructible and bool(parent.get_meta("damage_enabled", false)):
		_blocks.append({"node": m, "destructible": true, "res": res, "color": color})
	return m

func _top_mat(idx: int) -> Dictionary:
	match idx % 5:
		0:
			return {"mat": _mat_grass, "res": "BIO", "color": Color(0.18, 0.75, 0.32)}
		1:
			return {"mat": _mat_sand, "res": "ORE", "color": Color(0.82, 0.64, 0.30)}
		2:
			return {"mat": _mat_crystal, "res": "CRYSTAL", "color": Color(0.20, 0.90, 0.95)}
		3:
			return {"mat": _mat_city, "res": "ALLOY", "color": Color(0.50, 0.55, 0.68)}
		_:
			return {"mat": _mat_hive, "res": "ENERGY", "color": Color(0.95, 0.55, 0.16)}

func _build_far_mega_continent(root: Node3D) -> void:
	var cols := 16 + randi() % 7
	var rows := 10 + randi() % 5
	var cell := 0.46
	var void_a := randf_range(-1.6, 0.2)
	var void_b := randf_range(0.4, 1.8)
	for y in range(rows):
		var fy := (float(y) - float(rows - 1) * 0.5) * cell
		var bank := sin(float(y) * 0.45 + randf()) * 0.55
		for x in range(cols):
			if randf() < 0.32:
				continue
			var fx := (float(x) - float(cols - 1) * 0.5) * cell + bank
			var edge := absf(float(x) - float(cols - 1) * 0.5) / (float(cols) * 0.5)
			var rift := absf(fx - void_a - sin(float(y) * 0.6) * 0.35) < 0.35 \
				or absf(fx - void_b + cos(float(y) * 0.45) * 0.28) < 0.30
			if edge > 0.88 or rift:
				continue
			var h := randf_range(0.12, 0.30)
			_box(root, Vector3(fx, fy, randf_range(-0.05, 0.06)),
				Vector3(randf_range(0.34, 0.52), randf_range(0.32, 0.50), h), _mat_shadow)
	for i in range(9):
		var fx := randf_range(-3.2, 3.2)
		var fy := randf_range(-2.2, 2.2)
		_box(root, Vector3(fx, fy, 0.25), Vector3(0.05, randf_range(0.45, 0.95), 0.05),
			_mat_edge, false, "ORE", Color.WHITE, randf_range(-40.0, 40.0))

func _build_world_fragment(root: Node3D, near_t: float) -> void:
	var cols := 12 + randi() % 5
	var rows := 9 + randi() % 4
	var cell := 0.38
	var crater := Vector2(randf_range(-1.0, 1.0), randf_range(-0.8, 0.8))
	for y in range(rows):
		var fy := (float(y) - float(rows - 1) * 0.5) * cell
		for x in range(cols):
			var fx := (float(x) - float(cols - 1) * 0.5) * cell
			var oval := pow(fx / (float(cols) * cell * 0.50), 2.0) \
				+ pow(fy / (float(rows) * cell * 0.48), 2.0)
			var crater_d := Vector2(fx, fy).distance_to(crater)
			if oval > 1.0 or crater_d < 0.48 or randf() < 0.24:
				continue
			var h := randf_range(0.16, 0.42)
			var mat := _mat_base if randf() < 0.70 else _mat_ruin
			_box(root, Vector3(fx, fy, 0.0), Vector3(0.34, 0.34, h), mat)
			if randf() < 0.58:
				_box(root, Vector3(fx, fy - 0.04, -0.25), Vector3(0.23, 0.23, h * 0.85), _mat_shadow)
			if near_t > 0.36 and randf() < 0.38:
				var td := _top_mat(x + y + randi() % 6)
				_box(root, Vector3(fx, fy, 0.30), Vector3(0.22, 0.22, 0.14),
					td["mat"], true, td["res"], td["color"])
	for i in range(7):
		var a := randf() * TAU
		var r := randf_range(0.45, 1.7)
		_box(root, Vector3(crater.x + cos(a) * r, crater.y + sin(a) * r, 0.42),
			Vector3(0.08, randf_range(0.45, 1.0), 0.08), _mat_edge,
			false, "ORE", Color.WHITE, rad_to_deg(a) + 90.0)

func _build_orbital_ruins(root: Node3D, near_t: float) -> void:
	var span := 4.6 + near_t * 1.5
	for i in range(9):
		var t := float(i) / 8.0
		var x := lerpf(-span * 0.5, span * 0.5, t)
		var y := sin(t * PI) * 1.15 - 0.45
		var seg := _box(root, Vector3(x, y, 0.08), Vector3(0.62, 0.08, 0.08), _mat_ruin)
		seg.rotation_degrees.z = lerpf(34.0, -34.0, t)
		if i % 2 == 0:
			_box(root, Vector3(x, y + 0.22, 0.22), Vector3(0.12, 0.36, 0.10), _mat_edge)
	for i in range(5):
		var x := randf_range(-span * 0.45, span * 0.45)
		var y := randf_range(-1.2, 1.2)
		_box(root, Vector3(x, y, -0.05), Vector3(randf_range(0.22, 0.42), randf_range(0.20, 0.38), 0.18),
			_mat_shadow)
		if near_t > 0.45 and randf() < 0.55:
			var td := _top_mat(i + randi() % 4)
			_box(root, Vector3(x, y, 0.25), Vector3(0.16, 0.16, 0.12),
				td["mat"], true, td["res"], td["color"])

func _build_high_continent(root: Node3D, near_t: float) -> void:
	var cols := 8 + randi() % 4
	var rows := 6 + randi() % 3
	var cell := 0.36
	for y in range(rows):
		var fy := (float(y) - float(rows - 1) * 0.5) * cell
		for x in range(cols):
			var fx := (float(x) - float(cols - 1) * 0.5) * cell
			var oval := pow(fx / (float(cols) * cell * 0.48), 2.0) \
				+ pow(fy / (float(rows) * cell * 0.48), 2.0)
			if oval > 1.0 or randf() < 0.36:
				continue
			var h := randf_range(0.16, 0.34)
			_box(root, Vector3(fx, fy, 0.0), Vector3(0.32, 0.32, h), _mat_base)
			if randf() < 0.50:
				_box(root, Vector3(fx, fy - 0.03, -0.22), Vector3(0.22, 0.22, h * 0.80), _mat_shadow)
			if randf() < 0.46:
				var td := _top_mat(x + y + randi() % 5)
				_box(root, Vector3(fx, fy, 0.27), Vector3(0.22, 0.22, 0.13),
					td["mat"], true, td["res"], td["color"])
	for i in range(3):
		_box(root, Vector3(randf_range(-1.4, 1.4), randf_range(-1.0, 1.0), 0.36),
			Vector3(0.055, 0.55 + near_t * 0.25, 0.055), _mat_edge,
			false, "ORE", Color.WHITE, randf_range(-55.0, 55.0))

func _build_asteroid_field(root: Node3D, near_t: float) -> void:
	root.set_meta("damage_enabled", true)
	var count := 9 + randi() % 9
	for i in range(count):
		var p := Vector3(randf_range(-2.4, 2.4), randf_range(-1.8, 1.8), randf_range(-0.55, 0.55))
		var s := randf_range(0.10, 0.28) * lerpf(0.85, 1.25, near_t)
		var m := _box(root, p, Vector3(s * randf_range(0.8, 1.6), s * randf_range(0.75, 1.45), s),
			_mat_asteroid, near_t > 0.48 and randf() < 0.20, "ORE", Color(0.55, 0.50, 0.45),
			randf_range(0.0, 180.0))
		m.rotation_degrees.x = randf_range(-35.0, 35.0)
		m.rotation_degrees.y = randf_range(-35.0, 35.0)
		if randf() < 0.22:
			_box(root, p + Vector3(randf_range(-0.10, 0.10), randf_range(-0.10, 0.10), s * 0.8),
				Vector3(s * 0.45, s * 0.35, s * 0.35), _mat_crystal,
				near_t > 0.55, "CRYSTAL", Color(0.35, 0.90, 0.95))

func _build_open_space_terrain(root: Node3D, near_t: float) -> void:
	var cols := 9 + randi() % 4
	var rows := 7 + randi() % 4
	var cell := 0.31
	var cut_x := randf_range(-0.9, 0.9)
	var cut_w := randf_range(0.55, 0.90)
	for y in range(rows):
		var fy := (float(y) - float(rows - 1) * 0.5) * cell
		var wobble := sin(float(y) * 0.9 + root.get_instance_id() * 0.01) * 0.35
		for x in range(cols):
			var fx := (float(x) - float(cols - 1) * 0.5) * cell
			var edge := absf(fx + wobble) / (float(cols) * cell * 0.5)
			var corridor := absf(fx - cut_x - sin(float(y) * 0.75) * 0.24) < cut_w * 0.5
			var broken := randf() < lerpf(0.42, 0.30, near_t)
			if corridor or broken or edge > 0.96:
				continue
			var height := 0.10 + randf() * 0.20
			var zoff := randf_range(-0.05, 0.10)
			_box(root, Vector3(fx, fy, zoff), Vector3(0.27, 0.27, height), _mat_base)
			if randf() < 0.35:
				_box(root, Vector3(fx, fy - 0.05, zoff - 0.18), Vector3(0.20, 0.20, height * 0.75), _mat_shadow)
			if near_t > 0.42 and randf() < 0.36:
				var td := _top_mat(x + y + randi() % 4)
				_box(root, Vector3(fx, fy, zoff + 0.22), Vector3(0.20, 0.20, 0.13),
					td["mat"], true, td["res"], td["color"])
	for i in range(4):
		var fx := randf_range(-float(cols) * cell * 0.42, float(cols) * cell * 0.42)
		var fy := randf_range(-float(rows) * cell * 0.42, float(rows) * cell * 0.42)
		_box(root, Vector3(fx, fy, 0.30), Vector3(0.045, randf_range(0.35, 0.70), 0.045), _mat_edge,
			false, "ORE", Color.WHITE, randf_range(-35.0, 35.0))

func _build_space_canyon(root: Node3D, near_t: float) -> void:
	var rows := 10 + randi() % 5
	var cell := 0.32
	for y in range(rows):
		var fy := (float(y) - float(rows - 1) * 0.5) * cell
		var gap := 0.65 + sin(float(y) * 0.8) * 0.22
		for si in range(2):
			var side := -1.0 if si == 0 else 1.0
			var ridge_cols := 2 + randi() % 2
			for x in range(ridge_cols):
				if randf() < 0.22:
					continue
				var fx: float = side * (gap + float(x) * 0.30 + randf() * 0.12)
				var h := randf_range(0.18, 0.38)
				_box(root, Vector3(fx, fy, 0.0), Vector3(0.30, 0.28, h), _mat_base)
				if near_t > 0.45 and randf() < 0.42:
					var td := _top_mat(y + x)
					_box(root, Vector3(fx, fy, 0.27), Vector3(0.20, 0.18, 0.12),
						td["mat"], true, td["res"], td["color"])
		if (y & 3) == 0:
			var bridge := _box(root, Vector3(0.0, fy, 0.15), Vector3(gap * 1.5, 0.035, 0.045), _mat_edge)
			bridge.rotation_degrees.z = randf_range(-10.0, 10.0)

func _build_floating_continent(root: Node3D, near_t: float) -> void:
	var w := 8 + randi() % 5
	for i in range(w):
		var x := (float(i) - float(w - 1) * 0.5) * 0.34
		var ridge := sin(float(i) * 0.9) * 0.08
		_box(root, Vector3(x, ridge - 0.12, 0.0),
			Vector3(0.38, randf_range(0.18, 0.34), 0.22), _mat_base)
		_box(root, Vector3(x, ridge - 0.32, -0.05),
			Vector3(0.22, randf_range(0.18, 0.36), 0.16), _mat_shadow)
		if near_t > 0.45 and randf() < 0.72:
			var td := _top_mat(i + randi() % 3)
			_box(root, Vector3(x, ridge + 0.15, 0.18),
				Vector3(0.26, 0.13, 0.17), td["mat"], true, td["res"], td["color"])
	for i in range(3):
		_box(root, Vector3(randf_range(-1.6, 1.6), randf_range(-0.48, 0.12), 0.28),
			Vector3(0.06, 0.40 + randf() * 0.24, 0.06), _mat_edge)

func _build_ridge_islands(root: Node3D, near_t: float) -> void:
	for j in range(3):
		var cx := (float(j) - 1.0) * randf_range(0.75, 1.05)
		for i in range(4):
			var x := cx + (float(i) - 1.5) * 0.24
			var y := sin(float(i + j) * 1.4) * 0.09
			_box(root, Vector3(x, y, 0.0), Vector3(0.30, 0.22, 0.18), _mat_base)
			if near_t > 0.50 and randf() < 0.62:
				var td := _top_mat(i + j)
				_box(root, Vector3(x, y + 0.20, 0.18), Vector3(0.20, 0.12, 0.15),
					td["mat"], true, td["res"], td["color"])

func _build_honeycomb_field(root: Node3D, near_t: float) -> void:
	for x in range(-3, 4):
		for y in range(-2, 3):
			if randf() < 0.18:
				continue
			var p := Vector3(float(x) * 0.32 + (0.16 if (y & 1) != 0 else 0.0),
				float(y) * 0.27, 0.0)
			_hex_cell(root, p, 0.15)
			if near_t > 0.48 and randf() < 0.30:
				var td := _top_mat(x + y)
				_box(root, p + Vector3(0.0, 0.0, 0.18), Vector3(0.15, 0.15, 0.14),
					td["mat"], true, td["res"], td["color"])

func _hex_cell(root: Node3D, pos: Vector3, r: float) -> void:
	for i in range(6):
		var a := TAU * float(i) / 6.0
		var p := pos + Vector3(cos(a) * r, sin(a) * r, 0.0)
		_box(root, p, Vector3(0.16, 0.026, 0.055), _mat_hive, false, "ORE", Color.WHITE, rad_to_deg(a))

func _build_truss_field(root: Node3D, near_t: float) -> void:
	var h := 2.9 + randf() * 1.1
	for x in [-0.82, 0.0, 0.82]:
		_box(root, Vector3(x, 0.0, 0.0), Vector3(0.055, h, 0.055), _mat_edge)
	for i in range(9):
		var y := -h * 0.5 + float(i) * h / 8.0
		var b := _box(root, Vector3(0.0, y, 0.0), Vector3(1.9, 0.04, 0.045), _mat_base)
		b.rotation_degrees.z = 22.0 if (i & 1) == 0 else -22.0
		if near_t > 0.45 and (i & 3) == 0:
			var td := _top_mat(i)
			_box(root, Vector3(randf_range(-0.65, 0.65), y, 0.18), Vector3(0.18, 0.15, 0.14),
				td["mat"], true, td["res"], td["color"])

func _build_station(root: Node3D, near_t: float) -> void:
	_box(root, Vector3.ZERO, Vector3(0.58, 0.58, 0.22), _mat_shadow)
	_box(root, Vector3(0.0, 0.0, 0.20), Vector3(0.26, 0.26, 0.22), _mat_edge)
	for i in range(8):
		var a := TAU * float(i) / 8.0
		var arm := _box(root, Vector3(cos(a) * 0.76, sin(a) * 0.76, 0.02),
			Vector3(1.1, 0.055, 0.055), _mat_base)
		arm.rotation_degrees.z = rad_to_deg(a)
		if near_t > 0.42 and (i & 1) == 0:
			var td := _top_mat(i)
			_box(root, Vector3(cos(a) * 1.18, sin(a) * 1.18, 0.20),
				Vector3(0.18, 0.18, 0.14), td["mat"], true, td["res"], td["color"])

# ---------------------------------------------------------------------------
# Grand megastructures. Chosen per star system via its backdrop-weighted
# "struct_kinds" pool (GameState.STRUCT_KINDS_BY_BACKDROP) — see _spawn_prop.
# All reuse the shared, region-crossfaded materials so they re-tint each frame.
# ---------------------------------------------------------------------------

func _build_grand(root: Node3D, kind: String, near_t: float) -> void:
	match kind:
		"ringworld_arc":
			_build_ringworld_arc(root, near_t)
		"dyson_swarm":
			_build_dyson_swarm(root, near_t)
		"tether_spire":
			_build_tether_spire(root, near_t)
		"shattered_moon":
			_build_shattered_moon(root, near_t)
		"crystal_spire_field":
			_build_crystal_spire_field(root, near_t)
		"megacity_sprawl":
			_build_megacity_sprawl(root, near_t)
		"wreck_fleet":
			_build_wreck_fleet(root, near_t)
		_:
			_build_station(root, near_t)

# A colossal curved band sweeping across the whole screen — a slice of a
# ringworld arcing away into the distance.
func _build_ringworld_arc(root: Node3D, near_t: float) -> void:
	var span := 7.2
	var bow := 1.7 + near_t * 0.6   # how far the arc bows up
	var segs := 26
	for i in range(segs):
		var t := float(i) / float(segs - 1)
		var x := lerpf(-span * 0.5, span * 0.5, t)
		var y := -sin(t * PI) * bow + bow * 0.5
		var band := _box(root, Vector3(x, y, 0.0), Vector3(span / float(segs) * 1.15, 0.55, 0.16), _mat_base)
		band.rotation_degrees.z = lerpf(28.0, -28.0, t)
		# Inner habitation strip glows along the ring.
		var strip := _box(root, Vector3(x, y + 0.12, 0.10), Vector3(span / float(segs) * 1.05, 0.10, 0.05), _mat_edge)
		strip.rotation_degrees.z = band.rotation_degrees.z
		if (i % 4) == 0:
			_box(root, Vector3(x, y - 0.30, 0.06), Vector3(0.10, 0.45, 0.10), _mat_shadow)
		if near_t > 0.5 and randf() < 0.35:
			var td := _top_mat(i)
			_box(root, Vector3(x, y + 0.22, 0.18), Vector3(0.18, 0.16, 0.14),
				td["mat"], true, td["res"], td["color"])

# A central star/collector ringed by orbiting solar panels — a Dyson swarm.
func _build_dyson_swarm(root: Node3D, near_t: float) -> void:
	var core := _box(root, Vector3.ZERO, Vector3(0.7, 0.7, 0.7), _mat_crystal)
	core.rotation_degrees = Vector3(35.0, 0.0, 35.0)
	for ring in range(2):
		var r := 1.25 + float(ring) * 0.85
		var count := 14 + ring * 6
		for i in range(count):
			var a := TAU * float(i) / float(count) + float(ring) * 0.3
			var p := Vector3(cos(a) * r, sin(a) * r * 0.62, sin(a * 1.3) * 0.25)
			var panel := _box(root, p, Vector3(0.34, 0.20, 0.03), _mat_edge)
			panel.rotation_degrees.z = rad_to_deg(a) + 90.0
			panel.rotation_degrees.x = 24.0
			if near_t > 0.5 and (i % 5) == 0:
				_box(root, p + Vector3(0.0, 0.0, 0.06), Vector3(0.10, 0.10, 0.08),
					_mat_hive, true, "ENERGY", Color(0.95, 0.55, 0.16))

# A towering orbital tether / space elevator stretching far up the screen.
func _build_tether_spire(root: Node3D, near_t: float) -> void:
	var h := 5.4 + near_t * 1.8
	_box(root, Vector3(0.0, 0.0, 0.0), Vector3(0.22, h, 0.22), _mat_base)
	_box(root, Vector3(0.0, 0.0, 0.06), Vector3(0.08, h, 0.08), _mat_edge)
	# Counterweight at the top, anchor platform at the base.
	_box(root, Vector3(0.0, h * 0.5, 0.0), Vector3(0.62, 0.42, 0.30), _mat_city)
	_box(root, Vector3(0.0, -h * 0.5, 0.0), Vector3(0.95, 0.30, 0.40), _mat_shadow)
	var rungs := 9
	for i in range(rungs):
		var y := lerpf(-h * 0.42, h * 0.42, float(i) / float(rungs - 1))
		var side := 0.34 + 0.10 * sin(float(i))
		_box(root, Vector3(-side, y, 0.0), Vector3(0.30, 0.05, 0.06), _mat_edge)
		_box(root, Vector3(side, y, 0.0), Vector3(0.30, 0.05, 0.06), _mat_edge)
		if near_t > 0.5 and (i % 3) == 0:
			var td := _top_mat(i)
			_box(root, Vector3(side * 1.4, y, 0.14), Vector3(0.16, 0.14, 0.12),
				td["mat"], true, td["res"], td["color"])

# A cracked planetoid with a debris ring — shootable rubble drifts around it.
func _build_shattered_moon(root: Node3D, near_t: float) -> void:
	root.set_meta("damage_enabled", true)
	var rad := 1.5
	var cell := 0.40
	var n := int(rad / cell) + 1
	var rift := randf_range(-0.4, 0.4)
	for ix in range(-n, n + 1):
		for iy in range(-n, n + 1):
			var fx := float(ix) * cell
			var fy := float(iy) * cell
			if fx * fx + fy * fy > rad * rad:
				continue
			if absf(fx - rift - fy * 0.3) < 0.30:   # the fracture cleaving the moon
				continue
			var depth := sqrt(maxf(rad * rad - fx * fx - fy * fy, 0.0)) * 0.4
			_box(root, Vector3(fx, fy, -0.1), Vector3(cell * 0.96, cell * 0.96, 0.18 + depth), _mat_asteroid)
			if near_t > 0.5 and randf() < 0.18:
				_box(root, Vector3(fx, fy, 0.12 + depth * 0.5), Vector3(0.16, 0.16, 0.12),
					_mat_crystal, true, "CRYSTAL", Color(0.35, 0.90, 0.95))
	for i in range(16):
		var a := TAU * float(i) / 16.0
		var rr := rad + 0.55 + randf_range(-0.1, 0.25)
		var s := randf_range(0.10, 0.24)
		var chunk := _box(root, Vector3(cos(a) * rr, sin(a) * rr * 0.5, randf_range(-0.2, 0.2)),
			Vector3(s, s * randf_range(0.7, 1.3), s), _mat_asteroid, true, "ORE", Color(0.55, 0.50, 0.45))
		chunk.rotation_degrees = Vector3(randf_range(-40, 40), randf_range(-40, 40), randf_range(-40, 40))

# A forest of towering glowing crystal spires.
func _build_crystal_spire_field(root: Node3D, near_t: float) -> void:
	var count := 7 + randi() % 4
	for i in range(count):
		var x := randf_range(-2.6, 2.6)
		var base_y := randf_range(-1.4, -0.4)
		var h := randf_range(1.6, 3.6) * lerpf(0.85, 1.2, near_t)
		var spire := _box(root, Vector3(x, base_y + h * 0.5, randf_range(-0.4, 0.3)),
			Vector3(randf_range(0.18, 0.34), h, randf_range(0.18, 0.30)), _mat_crystal,
			near_t > 0.55, "CRYSTAL", Color(0.30, 0.90, 0.95))
		spire.rotation_degrees.z = randf_range(-9.0, 9.0)
		# A bright shard tip.
		_box(root, Vector3(x, base_y + h, 0.0), Vector3(0.12, h * 0.28, 0.12), _mat_edge)
		# A few satellite shards at the base.
		for j in range(2):
			_box(root, Vector3(x + randf_range(-0.30, 0.30), base_y + randf_range(0.0, 0.4), 0.1),
				Vector3(0.10, randf_range(0.4, 0.9), 0.10), _mat_crystal).rotation_degrees.z = randf_range(-25, 25)

# A vast multi-layer megacity grid with glowing windows.
func _build_megacity_sprawl(root: Node3D, near_t: float) -> void:
	var cols := 12 + randi() % 6
	var rows := 8 + randi() % 4
	var cell := 0.42
	for y in range(rows):
		var fy := (float(y) - float(rows - 1) * 0.5) * cell
		for x in range(cols):
			if randf() < 0.14:
				continue
			var fx := (float(x) - float(cols - 1) * 0.5) * cell
			var th := randf_range(0.20, 0.85)
			_box(root, Vector3(fx, fy, 0.0), Vector3(cell * 0.82, cell * 0.82, th), _mat_city)
			# Glowing window/antenna on taller blocks.
			if th > 0.5 and randf() < 0.6:
				_box(root, Vector3(fx, fy, th * 0.5 + 0.06), Vector3(0.12, 0.12, 0.10), _mat_edge)
			if near_t > 0.55 and randf() < 0.10:
				var td := _top_mat(x + y)
				_box(root, Vector3(fx, fy, th * 0.5 + 0.14), Vector3(0.14, 0.14, 0.12),
					td["mat"], true, td["res"], td["color"])

# A drifting graveyard of broken capital-ship hulls.
func _build_wreck_fleet(root: Node3D, near_t: float) -> void:
	root.set_meta("damage_enabled", true)
	var count := 4 + randi() % 3
	for i in range(count):
		var c := Vector3(randf_range(-2.4, 2.4), randf_range(-1.6, 1.6), randf_range(-0.5, 0.4))
		var len := randf_range(1.0, 2.2) * lerpf(0.85, 1.2, near_t)
		var hull := _box(root, c, Vector3(len, randf_range(0.22, 0.40), randf_range(0.22, 0.40)), _mat_ruin)
		var tilt := randf_range(-50.0, 50.0)
		hull.rotation_degrees = Vector3(randf_range(-30, 30), randf_range(-30, 30), tilt)
		# Snapped sections and exposed ribs.
		for j in range(2 + randi() % 2):
			var off := Vector3(randf_range(-len * 0.4, len * 0.4), randf_range(-0.2, 0.2), randf_range(-0.15, 0.15))
			var rib := _box(root, c + off.rotated(Vector3.FORWARD, deg_to_rad(tilt)),
				Vector3(0.10, randf_range(0.35, 0.6), 0.10), _mat_shadow, true, "ALLOY", Color(0.50, 0.55, 0.68))
			rib.rotation_degrees.z = tilt
		# A flickering reactor light on some hulls.
		if randf() < 0.5:
			_box(root, c, Vector3(0.14, 0.14, 0.14), _mat_edge)

# ---------------------------------------------------------------------------
# Mega-continent: a Star Force / Star Soldier endless landmass. Bands are tiled
# back-to-back at the front flight plane so the ground never gaps as it scrolls,
# carrying destructible bases and the occasional reactive gun turret.
# ---------------------------------------------------------------------------

func _is_mega_continent() -> bool:
	return bool(GameState.sector_theme().get("mega_continent", false))

func _count_non_continent() -> int:
	var n := 0
	for c in get_children():
		var node := c as Node3D
		if node != null and not node.get_meta("is_continent", false):
			n += 1
	return n

# Keep the continent column filled up to CONT_SPAWN_TOP by abutting new bands onto
# the current top edge (they all share speed/phase, so the tiling stays seamless).
func _maintain_continent() -> void:
	var top := -1000.0
	var any := false
	for c in get_children():
		var node := c as Node3D
		if node != null and node.get_meta("is_continent", false):
			any = true
			top = maxf(top, node.position.y + float(node.get_meta("band_half", 0.0)))
	if not any:
		# First appearance: seed ONE band just above the screen so the continent
		# frames IN from the top and scrolls down to fill, instead of popping in
		# fully-formed across the whole screen.
		top = CONT_SPAWN_TOP - CONT_BAND_H
	var guard := 0
	while top < CONT_SPAWN_TOP and guard < 8:
		_spawn_continent_band(top)
		top += CONT_BAND_H
		guard += 1

func _spawn_continent_band(bottom_y: float) -> void:
	var root := Node3D.new()
	var near_t := clampf((CONT_Z + 10.0) / 8.3, 0.0, 1.0)
	root.position = Vector3(0.0, bottom_y + CONT_BAND_H * 0.5, CONT_Z)
	root.set_meta("base_z", CONT_Z)
	root.set_meta("base_scale", Vector3.ONE)
	root.set_meta("base_x", 0.0)
	root.set_meta("parallax", 0.12)
	root.set_meta("speed", 0.013)
	root.set_meta("phase", 0.0)          # shared phase → bands sway together, no shear
	root.set_meta("despawn_y", -7.0)
	root.set_meta("damage_enabled", true)
	root.set_meta("is_continent", true)
	root.set_meta("band_half", CONT_BAND_H * 0.5)
	add_child(root)
	_build_continent_band(root, near_t)
	_finalize_batch(root)

func _build_continent_band(root: Node3D, near_t: float) -> void:
	var cols := 22
	var rows := 8
	var cw := CONT_WIDTH / float(cols)
	var ch := CONT_BAND_H / float(rows)
	# 0 = full width, ±1 = land hugs one edge with a wandering coastline (open space
	# on the other side). Coastline keys off absolute y so it flows across band seams.
	var edge := int(GameState.sector_theme().get("cont_edge", 0))
	var by0 := root.position.y
	for r in range(rows):
		var fy := (float(r) - float(rows - 1) * 0.5) * ch
		var coast := -0.2 + 0.9 * sin((by0 + fy) * 0.55)   # coastline x (world)
		for c in range(cols):
			var fx := (float(c) - float(cols - 1) * 0.5) * cw
			# One-sided coast: cull the open-sea half so only the continent edge shows.
			if edge > 0 and fx < coast:
				continue
			if edge < 0 and fx > -coast:
				continue
			# A mostly-solid crust with the odd inlet, so the land reads as continuous.
			if randf() < 0.08:
				continue
			var h := 0.12 + 0.16 * (0.5 + 0.5 * sin(fx * 0.7 + fy * 0.6 + root.position.y))
			var mat := _mat_base if randf() < 0.72 else _mat_shadow
			# The foundation crust is a HEAVY block: shrugs off single bullets, but
			# area terrain-attacks (dive-bomb / grind / robot blasts) punch a big hole
			# through it so the player can blow the continent open and drop down.
			var cb := _box(root, Vector3(fx, fy, 0.0), Vector3(cw * 0.98, ch * 0.98, h),
				mat, true, "ORE", Color(0.46, 0.43, 0.40))
			if not _blocks.is_empty() and _blocks[-1].get("node") == cb:
				_blocks[-1]["heavy"] = true
			var roll := randf()
			if roll < 0.16:
				# Destructible ground base — shoot it for resources.
				var td := _top_mat(c + r)
				_box(root, Vector3(fx, fy, 0.14), Vector3(cw * 0.66, ch * 0.66, 0.16),
					td["mat"], true, td["res"], td["color"])
			elif roll < 0.21:
				# A reactive gun turret embedded in the ground.
				_gun_block(root, Vector3(fx, fy, 0.16), Vector3(cw * 0.6, ch * 0.6, 0.20),
					Color(0.95, 0.45, 0.18))
	# Buried treasure vault: about a third of bands hide a rare cache mid-field that
	# only a dive-attack / grind can crack open (see _build_treasure_chamber).
	if randf() < 0.32:
		var tc := 3 + randi() % (cols - 6)
		if edge > 0:
			tc = cols / 2 + randi() % (cols / 2 - 2)   # keep it on the land (right) side
		elif edge < 0:
			tc = 2 + randi() % (cols / 2 - 2)           # land (left) side
		var tr := 1 + randi() % (rows - 2)
		var tx := (float(tc) - float(cols - 1) * 0.5) * cw
		var ty := (float(tr) - float(rows - 1) * 0.5) * ch
		_build_treasure_chamber(root, tx, ty, cw, ch)

# A buried rare-resource vault sunk into the continent: a glowing crystal core
# encased in HEAVY crust with only a glint poking through the surface. Bullets
# can't crack it — you must DIG it open with a dive-attack (or grind into it),
# and the blast harvests the rare core. This is the "dig down → treasure" payoff.
func _build_treasure_chamber(root: Node3D, cx: float, cy: float, cw: float, ch: float) -> void:
	for ox in range(-1, 2):
		for oy in range(-1, 2):
			var px := cx + float(ox) * cw
			var py := cy + float(oy) * ch
			if ox == 0 and oy == 0:
				# Glowing rare core (heavy + rare): only an area attack frees it.
				var core := _box(root, Vector3(px, py, -0.06), Vector3(cw * 0.8, ch * 0.8, 0.26),
					_mat_crystal, true, "CRYSTAL", Color(0.40, 0.95, 1.0))
				if not _blocks.is_empty() and _blocks[-1].get("node") == core:
					_blocks[-1]["heavy"] = true
					_blocks[-1]["rare"] = true
			# Heavy crust lid sealing the vault (front layer over/around the core).
			var lid := _box(root, Vector3(px, py, 0.04), Vector3(cw * 0.98, ch * 0.98, 0.30),
				_mat_shadow, true, "ORE", Color(0.42, 0.40, 0.40))
			if not _blocks.is_empty() and _blocks[-1].get("node") == lid:
				_blocks[-1]["heavy"] = true
	# A bright glint on the surface so a sharp-eyed pilot can spot the cache to dig.
	_box(root, Vector3(cx, cy, 0.22), Vector3(cw * 0.34, ch * 0.34, 0.12), _mat_boost)

# A destructible block that also fires aimed shots at the player when they dive to
# its layer. Tagged onto the _blocks record so try_block_hit destroys it normally.
func _gun_block(root: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var m := _box(root, pos, size, _mat_city, true, "ALLOY", color)
	# A small glowing barrel so it reads as a gun, not just rubble.
	_box(root, pos + Vector3(0.0, 0.0, size.z * 0.5 + 0.05), Vector3(size.x * 0.4, size.y * 0.4, 0.10), _mat_edge)
	if not _blocks.is_empty() and _blocks[-1].get("node") == m:
		_blocks[-1]["gun"] = true
		_blocks[-1]["fire_period"] = 110 + randi() % 80
		_blocks[-1]["fire_t"] = 60 + randi() % 100

func _update_guns() -> void:
	for rec in _blocks:
		if not rec.get("gun", false):
			continue
		var gp := _block_world_pos(rec)
		if gp == Vector3.INF:
			continue
		# Only fire when the player has descended to this ground layer's depth.
		if absf(GameState.alt_to_z(GameState.alt) - gp.z) > GUN_FIRE_Z:
			continue
		rec["fire_t"] = int(rec.get("fire_t", 0)) - 1
		if rec["fire_t"] <= 0:
			rec["fire_t"] = int(rec.get("fire_period", 130))
			_fire_gun(gp)

# The ship drills through the continent: when it pushes into the landmass at the
# continent's depth, blocks in contact are carved away (dropping resources) so the
# player can grind a tunnel down/up through it instead of phasing through.
func _grind_continent() -> void:
	var pz := GameState.alt_to_z(GameState.alt)
	var drops := blast(Vector3(GameState.px, GameState.py, pz), 0.17)
	if drops.is_empty():
		return
	for d: Dictionary in drops:
		ResourceItem.spawn(get_parent(), d)
	GameState.score += 5 * drops.size()
	if GameState.frame % 3 == 0:
		var ex := Explosion.new()
		ex.color = Color(0.95, 0.72, 0.4)
		ex.count = 6
		ex.strength = 0.5
		get_parent().add_child(ex)
		ex.global_position = Vector3(GameState.px, GameState.py, pz)

func _fire_gun(pos: Vector3) -> void:
	var b := EnemyBullet.new()
	b.bullet_type = "shot"
	var spd := 0.020 * (1.0 + 0.4 * GameState.difficulty())
	var ang := atan2(GameState.py - pos.y, GameState.px - pos.x)
	b.velocity = Vector3(cos(ang), sin(ang), 0.0) * spd
	b.alt = clampf(GameState.alt / GameState.ALT_MAX, 0.0, 1.0)
	b.position = pos
	get_parent().add_child(b)
