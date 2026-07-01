class_name TargetPlanet
extends Node3D

# The discovered star, shown as a planet in the background, colored by its
# biome. It creeps closer as the player descends toward ALT0 (approach 0→1).
# Once close enough, descending to the crust altitude makes this same node become
# the spherical surface stage. There is no separate flat terrain scene swap.

const APPROACH_RATE := 0.0018   # per frame at ALT0 (~9s from far to READY)
const READY_AT      := 0.55     # approach needed before entry is allowed
const ENTRY_FRAMES  := 150
const BG_Z          := -80.0    # far behind all gameplay; screen size is compensated below
const REF_BG_Z      := -2.85    # old visual-depth reference for matching the previous size
const SURFACE_RADIUS := 0.5
const SURFACE_SCALE := 104.0
const SURFACE_CENTER_Y := 0.8
const SPHERE_ENEMY_CAP := 16  # max sphere-riding star enemies alive at once
# Colour variants for the big tanky amoeba star-enemy (each spawn picks one).
const AMOEBA_COLORS := [
	Color(1.0, 0.20, 0.22),   # blood red
	Color(0.78, 0.30, 1.0),   # void purple
	Color(0.28, 1.0, 0.52),   # toxic green
	Color(1.0, 0.55, 0.12),   # molten orange
	Color(0.20, 0.85, 1.0),   # plasma cyan
	Color(1.0, 0.30, 0.78),   # malign magenta
]
const ORBIT_ACTOR_UPDATE_NEAR := 0.28
const ORBIT_ACTOR_SPAWN_NEAR := 0.68

var star_name: String = ""
var biome: String = "VERDANT"
var star_type: String = "boss" # "boss" | "mine" | "rescue"
# Ring shape: 0 = smooth circle. Set >=3 for a deliberate POLYGON ring as a marker —
# e.g. ring_sides = 3 gives the old triangular ring to flag a mid-boss (中ボス) star.
# (Set before the planet enters the tree, like star_name/biome.)
var ring_sides: int = 0
var approach: float = 0.0

var _entry_t: int = 0
var _entry_start_scale: float = 1.0
var _seamless_entry: bool = false
var _home: Vector3
var _ball: MeshInstance3D
var _companions: Node3D       # ring + moons (their own node so planet spin doesn't tumble them)
var _ring: MeshInstance3D
var _moon_hub: Node3D
var _surface_mode: bool = false
var _surface_frames: int = 0
var _surface_seed: int = 0
var _surface_roll_root: Node3D
var _surface_root: Node3D
var _surface_actor_root: Node3D
var _atmosphere: MeshInstance3D
var _atmosphere_mat: StandardMaterial3D
var _block_mesh: BoxMesh
var _block_mats: Array[StandardMaterial3D] = []
var _prop_mats: Array[StandardMaterial3D] = []
# Dark-world "キラキラ" sparkle: a glowing crystal material in the biome's sparkle hue,
# scattered as luminous spires across the surface. Null on bright (non-dim) worlds.
var _spark_mat: StandardMaterial3D = null
# Decorative _ball structures (cities/towers/domes/spires) batched per material into a
# MultiMesh while building (Material -> Array[Transform3D]); cleared after finalize.
var _struct_buckets: Dictionary = {}
# Surface blocks live in ONE MultiMesh (see surface_block.gdshader): per-block
# MeshInstance3D nodes made dense surfaces draw-call bound. Each record is
# {xf: Transform3D (local), color: Color} and its array index IS the MultiMesh
# instance slot, so destruction is an O(1) swap-remove (see _remove_surface_instance).
var _surface_blocks: Array[Dictionary] = []
# Per-frame cache of every block's screen position (parallel to _surface_blocks). _screen_block_at
# is called once PER BULLET, and with a 5-unit formation over a dense surface that was
# O(bullets × blocks) unproject_position() calls/frame. We project all blocks ONCE per frame and
# every bullet reuses it → O(blocks)/frame. Rebuilt when the frame changes or the count changes
# (append/swap-remove); back-hemisphere blocks are stored as INF so they never match. Visual no-op.
var _blk_sp: PackedVector2Array = PackedVector2Array()
var _blk_sp_frame: int = -1
var _rescue_obstacles: Array[Dictionary] = []
var _surface_mmi: MultiMeshInstance3D
var _surface_mm: MultiMesh
var _surface_block_mat: ShaderMaterial
var _enemy_mat: StandardMaterial3D
var _enemy_core_mat: StandardMaterial3D
var _enemy_mats: Dictionary = {}
var _enemy_core_mats: Dictionary = {}
var _enemy_trim_mats: Dictionary = {}
var _repair_mat: StandardMaterial3D
var _rescue_mat: StandardMaterial3D
var _vip_mat: StandardMaterial3D
var _enemy_mesh: BoxMesh
var _enemy_timer: int = 1
var _amoeba_queue: int = 0       # amoebas still to drip in one at a time (staggered)
var _amoeba_drip: int = 0        # frames until the next queued amoeba appears
var _repair_timer: int = 150
var _key_gate_count: int = 0
var _gate_timer: int = 120
var _gate_mat: StandardMaterial3D
var _boss_gate_mat: StandardMaterial3D
var _rescue_spawned: bool = false
var _vip_spawned: bool = false
var _planet_clear_announced: bool = false
var _surface_yaw: float = 0.0
var _surface_blocks_broken: int = 0
var _surface_total: int = 0          # block count at build (for the "almost mined out" check)
var _has_plate: bool = false         # a route plate is still buried in this star
var _plate_found_here: bool = false  # the plate on this star has been unearthed
var _giveup_announced: bool = false  # showed the "no plate here" message once
var _surface_boss_spawned: bool = false
var _world_env: WorldEnvironment
var _light: DirectionalLight3D
var _saved_light_energy: float = 1.0
var _saved_light_color: Color = Color.WHITE
var _saved_light_tf: Transform3D
var _saved_light_shadow: bool = false
var _dispose_requested: bool = false
var _collapse_active: bool = false
var _collapse_t: int = 0

func _ready() -> void:
	add_to_group("target_planet")
	_home = global_position
	_build_meshes()
	_surface_seed = _stable_surface_seed()
	var rng := RandomNumberGenerator.new()
	rng.seed = _surface_seed
	_build_spherical_surface(rng)
	_surface_root.visible = true
	_atmosphere.visible = true
	scale = Vector3.ONE * 0.001

func _stable_surface_seed() -> int:
	var h := hash("%s:%s:%s" % [star_name, biome, star_type])
	return (int(abs(h)) & 0x7FFFFFFF) | 1

# One stable shader identity per discovered star. Mine/rescue keep an authored identity;
# ordinary stars rotate among the remaining styles from their permanent name/biome seed.
func _surface_shader_look() -> Dictionary:
	var style := 4 if star_type == "mine" else (3 if star_type == "rescue" \
		else int(abs(hash(star_name + ":" + biome + ":surface-style")) % 4))
	match style:
		1: # crystal
			return {"tint": Color(0.04, 0.60, 0.86), "vein": Color(0.12, 0.98, 0.76),
				"colorize": 0.62, "metal": 0.28, "rough": -0.48, "vein_strength": 1.0, "vein_emission": 0.38}
		2: # ash
			return {"tint": Color(0.13, 0.035, 0.19), "vein": Color(0.92, 0.10, 0.015),
				"colorize": 0.68, "metal": 0.0, "rough": 0.16, "vein_strength": 0.72, "vein_emission": 0.14}
		3: # relic
			return {"tint": Color(0.08, 0.42, 0.32), "vein": Color(0.95, 0.66, 0.16),
				"colorize": 0.58, "metal": 0.30, "rough": -0.38, "vein_strength": 0.86, "vein_emission": 0.20}
		4: # gold seam / mine
			return {"tint": Color(0.82, 0.30, 0.025), "vein": Color(1.0, 0.84, 0.24),
				"colorize": 0.76, "metal": 0.42, "rough": -0.50, "vein_strength": 1.0, "vein_emission": 0.28}
		_: # natural
			return {"tint": Color(0.18, 0.66, 0.20), "vein": Color(0.0, 0.0, 0.0),
				"colorize": 0.24, "metal": 0.0, "rough": 0.02, "vein_strength": 0.0, "vein_emission": 0.0}

func dispose_immediate() -> void:
	if _dispose_requested:
		return
	_dispose_requested = true
	remove_from_group("target_planet")
	remove_from_group("planet_terrain")
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	_surface_blocks.clear()
	queue_free()

func _build_meshes() -> void:
	var b: Dictionary = PlanetTerrain.BIOMES.get(biome, PlanetTerrain.BIOMES["VERDANT"])
	var high: Color = b["high"]
	var col := _vivid(high)

	# Real sphere again: this keeps the previous richer material/lighting feel.
	# It is placed far behind gameplay (BG_Z) and scaled up to preserve its old
	# screen size, so even the near face cannot reach the ship/carrier layer.
	_ball = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.5
	sph.height = 1.0
	_ball.mesh = sph

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/planet_backdrop.gdshader")
	var surf := _surface_params(biome, b)
	mat.set_shader_parameter("land_color", col)
	mat.set_shader_parameter("ocean_color", surf["ocean"])
	mat.set_shader_parameter("pole_color", surf["pole"])
	mat.set_shader_parameter("cloud_color", surf["cloud"])
	mat.set_shader_parameter("pole_amount", surf["pole_amount"])
	mat.set_shader_parameter("cloud_amount", surf["cloud_amount"])
	mat.set_shader_parameter("sea_level", surf["sea_level"])
	mat.set_shader_parameter("rotate_speed", surf["rotate_speed"])
	mat.set_shader_parameter("seed", float(hash(star_name + biome) % 4096))
	mat.set_shader_parameter("emission_energy", 0.18)
	var wt := _world_type()
	mat.set_shader_parameter("world_type", wt)
	# Water worlds (terran/ocean) get the gorgeous sun-glitter on their seas — a touch
	# softer than the ending homeworld so it stays a flourish, not a showstopper.
	if wt == 0 or wt == 1:
		mat.set_shader_parameter("ocean_glint", 0.85)
	_ball.material_override = mat
	add_child(_ball)

	_surface_roll_root = Node3D.new()
	add_child(_surface_roll_root)

	_surface_root = Node3D.new()
	_surface_root.visible = true
	_surface_roll_root.add_child(_surface_root)
	_surface_actor_root = Node3D.new()
	_surface_actor_root.visible = false
	_surface_roll_root.add_child(_surface_actor_root)

	_atmosphere = MeshInstance3D.new()
	var air := SphereMesh.new()
	air.radius = 0.515
	air.height = 1.03
	_atmosphere.mesh = air
	_atmosphere_mat = StandardMaterial3D.new()
	_atmosphere_mat.albedo_color = Color(col.r, col.g, col.b, 0.07)
	_atmosphere_mat.emission_enabled = true
	_atmosphere_mat.emission = col
	_atmosphere_mat.emission_energy_multiplier = 0.05
	_atmosphere_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_atmosphere_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_atmosphere.material_override = _atmosphere_mat
	_atmosphere.visible = true
	add_child(_atmosphere)

	_block_mesh = BoxMesh.new()
	_block_mesh.size = Vector3.ONE
	_make_surface_mats(col)
	_enemy_mesh = BoxMesh.new()
	_enemy_mesh.size = Vector3.ONE
	_enemy_mat = StandardMaterial3D.new()
	_enemy_mat.albedo_color = Color(1.0, 0.18, 0.38)
	_enemy_mat.emission_enabled = true
	_enemy_mat.emission = Color(1.0, 0.05, 0.20)
	_enemy_mat.emission_energy_multiplier = 0.9
	_enemy_core_mat = StandardMaterial3D.new()
	_enemy_core_mat.albedo_color = Color(0.08, 0.0, 0.025)
	_enemy_core_mat.emission_enabled = true
	_enemy_core_mat.emission = Color(1.0, 0.0, 0.12)
	_enemy_core_mat.emission_energy_multiplier = 0.35
	_make_enemy_mats()
	_repair_mat = StandardMaterial3D.new()
	_repair_mat.albedo_color = Color(0.25, 1.0, 0.48)
	_repair_mat.emission_enabled = true
	_repair_mat.emission = Color(0.2, 1.0, 0.45)
	_repair_mat.emission_energy_multiplier = 1.4
	_rescue_mat = _enemy_material(Color(0.18, 1.0, 0.95), Color(0.05, 0.9, 1.0), 2.0)
	_vip_mat = _enemy_material(Color(1.0, 0.92, 0.35), Color(1.0, 0.72, 0.12), 2.2)
	_gate_mat = _enemy_material(Color(0.18, 0.95, 1.0), Color(0.08, 0.85, 1.0), 1.5)
	_boss_gate_mat = _enemy_material(Color(1.0, 0.24, 0.88), Color(1.0, 0.02, 0.42), 1.8)

	# Decorate the discovered-planet sphere with non-destructible cosmic structures
	# (cities, towers, domes, orbital spires) so the world reads as inhabited/built.
	_build_ball_structures(col, biome, b)
	# Give the world companions — a ring and a few moons — so a discovered star reads
	# as a whole little system instead of one lonely orb.
	_build_companions(col, biome, b)

func _make_surface_mats(base: Color) -> void:
	_block_mats.clear()
	var cols: Array[Color] = [
			base.lightened(0.18),
			base.darkened(0.16),
			Color(0.62, 0.64, 0.62),
			Color(0.38, 0.42, 0.48),
			Color(0.78, 0.66, 0.36)]
	if star_type == "mine":
		cols = [
			Color(1.0, 0.78, 0.16),
			Color(0.92, 0.58, 0.08),
			Color(1.0, 0.90, 0.34),
			Color(0.72, 0.46, 0.08),
			Color(1.0, 0.68, 0.18)]
	for c in cols:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		if star_type == "mine":
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 0.26
		m.roughness = 0.86
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_block_mats.append(m)
	# One shared material for the whole surface MultiMesh; per-block color comes
	# from instance colors. Mine stars keep their subtle self-glow (energy 0.26).
	_surface_block_mat = ShaderMaterial.new()
	_surface_block_mat.shader = load("res://shaders/surface_block.gdshader")
	# Material look (stone/dirt/grass/ore/gold/silver) is driven per-block in the shader
	# from the instance colour (RGB tint + material id in alpha); no flat emission.
	_surface_block_mat.set_shader_parameter("emission_energy", 0.0)
	# 明るい暖色（黄/金）ブロックの自己発光をほんの少しだけ抑える（既定 2.4 → 1.8）
	_surface_block_mat.set_shader_parameter("block_glow", 1.8)
	var surface_look := _surface_shader_look()
	_surface_block_mat.set_shader_parameter("style_tint", surface_look["tint"])
	_surface_block_mat.set_shader_parameter("style_vein_color", surface_look["vein"])
	_surface_block_mat.set_shader_parameter("style_colorize", surface_look["colorize"])
	_surface_block_mat.set_shader_parameter("style_metal_boost", surface_look["metal"])
	_surface_block_mat.set_shader_parameter("style_rough_shift", surface_look["rough"])
	_surface_block_mat.set_shader_parameter("style_vein_strength", surface_look["vein_strength"])
	_surface_block_mat.set_shader_parameter("style_vein_emission", surface_look["vein_emission"])
	_prop_mats.clear()
	for c in [Color(0.12, 0.13, 0.16), Color(0.52, 0.50, 0.44), base.darkened(0.34)]:
		var pm := StandardMaterial3D.new()
		pm.albedo_color = c
		pm.roughness = 0.92
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_prop_mats.append(pm)
	# On dark worlds, build the glowing sparkle material (it blooms via the surface env).
	var bd: Dictionary = PlanetTerrain.BIOMES.get(biome, PlanetTerrain.BIOMES["VERDANT"])
	if bd.get("dim", false):
		var spark: Color = bd.get("sparkle", Color(0.5, 0.9, 1.0))
		_spark_mat = StandardMaterial3D.new()
		_spark_mat.albedo_color = spark
		_spark_mat.emission_enabled = true
		_spark_mat.emission = spark
		_spark_mat.emission_energy_multiplier = 3.4   # pushed past the env bloom threshold
		_spark_mat.roughness = 0.3
		_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	else:
		_spark_mat = null

func _make_enemy_mats() -> void:
	_enemy_mats.clear()
	_enemy_core_mats.clear()
	_enemy_trim_mats.clear()
	_enemy_mats["formation"] = _enemy_material(Color(0.25, 0.78, 1.0), Color(0.08, 0.55, 1.0), 0.75)
	_enemy_core_mats["formation"] = _enemy_material(Color(0.02, 0.10, 0.22), Color(0.1, 0.8, 1.0), 0.55)
	_enemy_trim_mats["formation"] = _enemy_material(Color(0.92, 0.98, 1.0), Color(0.35, 0.95, 1.0), 1.1)
	_enemy_mats["swooper"] = _enemy_material(Color(1.0, 0.48, 0.12), Color(1.0, 0.24, 0.04), 0.85)
	_enemy_core_mats["swooper"] = _enemy_material(Color(0.24, 0.06, 0.02), Color(1.0, 0.5, 0.04), 0.55)
	_enemy_trim_mats["swooper"] = _enemy_material(Color(1.0, 0.88, 0.32), Color(1.0, 0.6, 0.08), 1.15)
	_enemy_mats["missile"] = _enemy_material(Color(1.0, 0.86, 0.18), Color(1.0, 0.64, 0.05), 0.9)
	_enemy_core_mats["missile"] = _enemy_material(Color(0.24, 0.16, 0.02), Color(1.0, 0.85, 0.1), 0.6)
	_enemy_trim_mats["missile"] = _enemy_material(Color(0.18, 0.12, 0.06), Color(1.0, 0.18, 0.02), 1.4)
	_enemy_mats["hunter"] = _enemy_material(Color(1.0, 0.16, 0.58), Color(1.0, 0.02, 0.32), 1.0)
	_enemy_core_mats["hunter"] = _enemy_material(Color(0.14, 0.0, 0.06), Color(1.0, 0.0, 0.18), 0.65)
	_enemy_trim_mats["hunter"] = _enemy_material(Color(0.85, 0.92, 1.0), Color(0.55, 0.75, 1.0), 1.2)
	_enemy_mats["turret"] = _enemy_material(Color(0.35, 0.95, 0.36), Color(0.18, 1.0, 0.25), 0.9)
	_enemy_core_mats["turret"] = _enemy_material(Color(0.02, 0.16, 0.04), Color(0.45, 1.0, 0.25), 0.75)
	_enemy_trim_mats["turret"] = _enemy_material(Color(0.95, 1.0, 0.62), Color(0.7, 1.0, 0.2), 1.2)
	_enemy_mats["rammer"] = _enemy_material(Color(0.95, 0.18, 0.12), Color(1.0, 0.12, 0.04), 1.1)
	_enemy_core_mats["rammer"] = _enemy_material(Color(0.22, 0.02, 0.01), Color(1.0, 0.2, 0.02), 0.7)
	_enemy_trim_mats["rammer"] = _enemy_material(Color(0.12, 0.12, 0.14), Color(1.0, 0.32, 0.02), 0.9)
	_enemy_mats["weaver"] = _enemy_material(Color(0.62, 0.28, 1.0), Color(0.45, 0.08, 1.0), 0.95)
	_enemy_core_mats["weaver"] = _enemy_material(Color(0.10, 0.02, 0.22), Color(0.70, 0.20, 1.0), 0.7)
	_enemy_trim_mats["weaver"] = _enemy_material(Color(0.30, 1.0, 0.78), Color(0.1, 1.0, 0.75), 1.3)
	_enemy_mats["bomber"] = _enemy_material(Color(0.88, 0.72, 0.28), Color(1.0, 0.48, 0.08), 0.85)
	_enemy_core_mats["bomber"] = _enemy_material(Color(0.22, 0.12, 0.02), Color(1.0, 0.68, 0.12), 0.65)
	_enemy_trim_mats["bomber"] = _enemy_material(Color(0.58, 0.66, 0.78), Color(0.9, 0.6, 0.16), 0.85)
	_enemy_mats["saucer"] = _enemy_material(Color(0.46, 0.92, 0.86), Color(0.08, 0.95, 0.85), 1.0)
	_enemy_core_mats["saucer"] = _enemy_material(Color(0.05, 0.18, 0.20), Color(0.0, 0.95, 0.75), 0.75)
	_enemy_trim_mats["saucer"] = _enemy_material(Color(1.0, 0.34, 0.92), Color(1.0, 0.05, 0.8), 1.4)
	_enemy_mats["asteroid"] = _enemy_material(Color(0.44, 0.40, 0.35), Color(0.18, 0.12, 0.08), 0.12)
	_enemy_core_mats["asteroid"] = _enemy_material(Color(0.28, 0.24, 0.20), Color(0.7, 0.32, 0.08), 0.35)
	_enemy_trim_mats["asteroid"] = _enemy_material(Color(0.72, 0.62, 0.45), Color(0.9, 0.45, 0.1), 0.45)

func _enemy_material(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.emission_enabled = true
	m.emission = emission
	m.emission_energy_multiplier = energy
	m.roughness = 0.72
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return m

func _depth_compensated_scale(base_size: float) -> float:
	return base_size

func _screen_safe_scale(base_size: float, max_scale: float) -> float:
	return minf(base_size, max_scale)

# Saturate + brighten a biome colour with plain RGB math (Color.from_hsv gave
# gray on the user's build). Push each channel away from the grayscale average,
# then lift dark biomes so they don't read as muddy.
func _vivid(col: Color) -> Color:
	var m: float = (col.r + col.g + col.b) / 3.0
	var sat := 1.7
	var r := m + (col.r - m) * sat
	var g := m + (col.g - m) * sat
	var b := m + (col.b - m) * sat
	var lift := lerpf(1.6, 1.0, clampf(m, 0.0, 1.0))
	return Color(clampf(r * lift, 0.0, 1.0),
		clampf(g * lift, 0.0, 1.0), clampf(b * lift, 0.0, 1.0))

# Per-biome surface look for the discovered-planet sphere shader (ocean/pole/cloud
# Surface STYLE for the discovered-planet shader (see planet_backdrop.gdshader world_type).
# Mostly from biome, but ordinary biomes occasionally roll a night-city or dark/barren
# variant so frequently-visited stars keep looking different. Deterministic per star.
func _world_type() -> int:
	match biome:
		"GAS", "DARKGAS": return 2
		"OCEAN": return 1
		"VOLCANIC", "EMBER": return 5
		"CYBER": return 3
		"BARREN", "VOID": return 4   # dark / barren rock from space
		"TUNDRA": return 1           # cold dark water-ice world
		_:
			var roll := hash(star_name + biome + "wt") % 100
			if roll < 20:
				return 3   # night city
			elif roll < 34:
				return 4   # barren / dark
			elif roll < 44:
				return 1   # water world
			return 0       # terran
	return 0

# colors + how much sea, ice and cloud cover, plus spin speed).
func _surface_params(b_id: String, b: Dictionary) -> Dictionary:
	var accent: Color = b.get("accent", Color(0.06, 0.26, 0.50))
	# Sensible default: cool blue seas, white caps, white clouds, balanced cover.
	var p := {
		"ocean": Color(0.04, 0.16, 0.34), "pole": Color(0.92, 0.96, 1.0),
		"cloud": Color(1.0, 1.0, 1.0), "pole_amount": 0.55, "cloud_amount": 0.32,
		"sea_level": 0.48, "rotate_speed": 0.02,
	}
	match b_id:
		"OCEAN":
			p["ocean"] = Color(0.03, 0.16, 0.38); p["sea_level"] = 0.62
			p["cloud_amount"] = 0.42; p["pole_amount"] = 0.5
		"VERDANT":
			p["ocean"] = Color(0.04, 0.18, 0.36); p["sea_level"] = 0.50
		"DESERT":
			p["ocean"] = Color(0.18, 0.32, 0.38); p["sea_level"] = 0.38
			p["pole_amount"] = 0.3; p["cloud_amount"] = 0.16
		"ICE":
			p["ocean"] = Color(0.30, 0.50, 0.66); p["sea_level"] = 0.44
			p["pole_amount"] = 0.85; p["cloud_amount"] = 0.30
		"VOLCANIC":
			p["ocean"] = Color(0.65, 0.13, 0.02)   # lava seas
			p["cloud"] = Color(0.32, 0.28, 0.26)   # ash
			p["pole_amount"] = 0.0; p["cloud_amount"] = 0.22; p["sea_level"] = 0.46
		"GAS":
			p["ocean"] = accent; p["cloud"] = Color(1.0, 0.95, 0.82)
			p["pole_amount"] = 0.0; p["cloud_amount"] = 0.7; p["sea_level"] = 0.4
			p["rotate_speed"] = 0.05
		"CYBER":
			p["ocean"] = Color(0.05, 0.09, 0.18); p["cloud"] = Color(0.20, 0.85, 1.0)
			p["pole_amount"] = 0.2; p["cloud_amount"] = 0.18; p["sea_level"] = 0.5
		"BARREN":
			p["ocean"] = Color(0.10, 0.12, 0.16); p["cloud"] = Color(0.4, 0.4, 0.44)
			p["pole_amount"] = 0.12; p["cloud_amount"] = 0.10; p["sea_level"] = 0.30
		"EMBER":
			p["ocean"] = Color(0.55, 0.11, 0.02)   # cooling lava seas
			p["cloud"] = Color(0.26, 0.18, 0.16)   # ash veil
			p["pole_amount"] = 0.0; p["cloud_amount"] = 0.34; p["sea_level"] = 0.44
		"DARKGAS":
			p["ocean"] = accent; p["cloud"] = Color(0.72, 0.56, 1.0)
			p["pole_amount"] = 0.0; p["cloud_amount"] = 0.72; p["sea_level"] = 0.4
			p["rotate_speed"] = 0.05
		"TUNDRA":
			p["ocean"] = Color(0.05, 0.18, 0.32); p["sea_level"] = 0.46
			p["pole_amount"] = 0.9; p["cloud_amount"] = 0.24
		"VOID":
			p["ocean"] = accent.darkened(0.25); p["cloud"] = Color(0.2, 0.4, 0.34)
			p["pole_amount"] = 0.1; p["cloud_amount"] = 0.08; p["sea_level"] = 0.40
		_:
			p["ocean"] = accent.darkened(0.35)
	return p

# Scatter non-destructible "built world" structures across the discovered-planet
# sphere — children of _ball, so they rotate with the planet and grow as it nears.
# Their lit windows glow on the night side (emission ignores the terminator), so a
# civilised world twinkles in the dark. Density/flavour vary by biome; gas giants
# get none (no solid ground).
func _build_ball_structures(col: Color, b_id: String, b: Dictionary) -> void:
	if _ball == null:
		return
	var density := 1.0
	match b_id:
		"CYBER", "BASE":
			density = 2.3
		"TEMPLE":
			density = 1.5
		"VERDANT", "OCEAN", "DESERT", "ICE":
			density = 1.0
		"VOLCANIC", "CAVE", "MOLTEN":
			density = 0.6
		"BARREN", "VOID", "EMBER", "TUNDRA":
			density = 0.45   # forgotten/dead worlds: sparse ruins twinkling in the dark
		"GAS", "DARKGAS":
			return   # gas giant: no surface to build on
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(star_name + "|struct|" + b_id)
	_struct_buckets = {}
	var accent: Color = b.get("accent", Color(0.2, 0.85, 1.0))
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = col.darkened(0.45)
	body_mat.roughness = 0.85
	var metal_mat := StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.55, 0.58, 0.64)
	metal_mat.metallic = 0.7
	metal_mat.roughness = 0.4
	var light_mat := StandardMaterial3D.new()   # glowing windows / beacons (night-side twinkle)
	light_mat.albedo_color = accent
	light_mat.emission_enabled = true
	light_mat.emission = accent
	light_mat.emission_energy_multiplier = 2.2
	var count := int(round(26.0 * density))
	for i in count:
		var lat := asin(rng.randf_range(-0.92, 0.92))
		var lon := rng.randf_range(0.0, TAU)
		var frame := _surface_frame(lat, lon)
		match rng.randi() % 4:
			0:
				_struct_city(frame, rng, body_mat, light_mat)
			1:
				_struct_tower(frame, rng, body_mat, light_mat)
			2:
				_struct_dome(frame, rng, body_mat, light_mat)
			_:
				_struct_spire(frame, rng, metal_mat, light_mat)
	# All those little blocks share _block_mesh and just 3 materials, so collapse the
	# ~150-300 individual MeshInstance3D (one draw call each — the cost spike when a star
	# fills the screen on approach) into one MultiMesh per material. Identical look.
	_finalize_struct_multimeshes()

# A tangent frame sitting on the _ball surface at (lat,lon): local +x/+y run along
# the surface, +z points straight out, so structures rise along +z. Returns the frame
# transform (relative to _ball); boxes compose against it into the structure MultiMesh.
func _surface_frame(lat: float, lon: float) -> Transform3D:
	var n := Vector3(sin(lon) * cos(lat), sin(lat), cos(lon) * cos(lat)).normalized()
	var right := Vector3.UP.cross(n)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := n.cross(right).normalized()
	return Transform3D(Basis(right, up, n), n * 0.5)

func _struct_box(frame: Transform3D, lx: float, ly: float, w: float, d: float, h: float,
		mat: StandardMaterial3D, base_z: float = 0.0) -> void:
	# Collect the box's final (per-_ball) transform into its material's bucket instead of
	# spawning a node; _finalize_struct_multimeshes() packs each bucket into one MultiMesh.
	var local := Transform3D(Basis.IDENTITY.scaled(Vector3(w, d, maxf(h, 0.002))),
		Vector3(lx, ly, base_z + h * 0.5))
	if not _struct_buckets.has(mat):
		_struct_buckets[mat] = ([] as Array[Transform3D])
	(_struct_buckets[mat] as Array[Transform3D]).append(frame * local)

# Pack each material's collected box transforms into one MultiMeshInstance3D under _ball
# (so they rotate/grow with the planet exactly as the old per-box children did).
func _finalize_struct_multimeshes() -> void:
	for mat: StandardMaterial3D in _struct_buckets:
		var xfs: Array[Transform3D] = _struct_buckets[mat]
		if xfs.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _block_mesh
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		_ball.add_child(mmi)
	_struct_buckets = {}

func _struct_city(frame: Transform3D, rng: RandomNumberGenerator,
		body: StandardMaterial3D, light: StandardMaterial3D) -> void:
	var n := 2 + rng.randi() % 2
	var step := 0.016
	for gx in range(n):
		for gy in range(n):
			if rng.randf() < 0.2:
				continue
			var lx := (float(gx) - float(n - 1) * 0.5) * step
			var ly := (float(gy) - float(n - 1) * 0.5) * step
			var h := rng.randf_range(0.010, 0.040)
			_struct_box(frame, lx, ly, 0.011, 0.011, h, body)
			if rng.randf() < 0.5:
				_struct_box(frame, lx, ly, 0.007, 0.007, 0.004, light, h)  # rooftop light

func _struct_tower(frame: Transform3D, rng: RandomNumberGenerator,
		body: StandardMaterial3D, light: StandardMaterial3D) -> void:
	var h := rng.randf_range(0.045, 0.085)
	_struct_box(frame, 0.0, 0.0, 0.018, 0.018, 0.012, body)          # base
	_struct_box(frame, 0.0, 0.0, 0.010, 0.010, h, body)             # shaft
	_struct_box(frame, 0.0, 0.0, 0.014, 0.014, 0.006, light, h)     # glowing crown on top

func _struct_dome(frame: Transform3D, rng: RandomNumberGenerator,
		body: StandardMaterial3D, light: StandardMaterial3D) -> void:
	# Stacked tiers read as a dome/ziggurat with a glowing apex.
	var w := rng.randf_range(0.028, 0.046)
	_struct_box(frame, 0.0, 0.0, w, w, 0.008, body)
	_struct_box(frame, 0.0, 0.0, w * 0.6, w * 0.6, 0.010, body, 0.008)
	_struct_box(frame, 0.0, 0.0, w * 0.28, w * 0.28, 0.008, light, 0.018)

func _struct_spire(frame: Transform3D, rng: RandomNumberGenerator,
		metal: StandardMaterial3D, light: StandardMaterial3D) -> void:
	# A tall orbital spire / space-elevator stub — the megastructure flourish.
	var h := rng.randf_range(0.10, 0.18)
	_struct_box(frame, 0.0, 0.0, 0.020, 0.020, 0.010, metal)         # anchor
	_struct_box(frame, 0.0, 0.0, 0.006, 0.006, h, metal)            # mast
	_struct_box(frame, 0.0, 0.0, 0.012, 0.012, 0.008, light, h * 0.82)  # beacon near the top

# Build the planet's companions: an optional tilted ring + a few orbiting moons, so
# arriving at a star feels like finding a whole system. All a handful of meshes,
# parented to a node separate from _ball so the planet's spin doesn't tumble them.
func _build_companions(col: Color, b_id: String, b: Dictionary) -> void:
	_companions = Node3D.new()
	add_child(_companions)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(star_name + "|companions|" + b_id)
	var accent: Color = b.get("accent", Color(0.6, 0.7, 0.9))

	# Ring — gas giants always wear one; rocky worlds sometimes do.
	var ring_chance := 0.45
	if b_id == "GAS":
		ring_chance = 1.0
	elif b_id == "VOLCANIC" or b_id == "CAVE" or b_id == "MOLTEN":
		ring_chance = 0.25
	if rng.randf() < ring_chance:
		var torus := TorusMesh.new()
		# Planet ball radius is 0.5; keep a clear gap from the surface (inner well above
		# 0.5) and a THIN band (Saturn-like), not a fat ring hugging the planet.
		var ring_in := rng.randf_range(0.80, 0.88)
		torus.inner_radius = ring_in
		torus.outer_radius = ring_in + rng.randf_range(0.12, 0.18)
		# segments AROUND the ring: high = smooth circle; ring_sides>=3 makes a deliberate
		# polygon ring (3 = triangle) to mark special stars (e.g. mid-boss).
		torus.rings = ring_sides if ring_sides >= 3 else 64
		torus.ring_segments = 8  # tube cross-section (thin flat ring; few needed)
		# Random vivid ring colour per star (rng is per-star deterministic → stable for a
		# given star, colourful across the galaxy).
		var ring_col := Color.from_hsv(rng.randf(), rng.randf_range(0.65, 0.95), 1.0)
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(ring_col.r, ring_col.g, ring_col.b, 0.6)
		rmat.emission_enabled = true
		rmat.emission = ring_col
		rmat.emission_energy_multiplier = 0.5
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_ring = MeshInstance3D.new()
		_ring.mesh = torus
		_ring.material_override = rmat
		# Per-star 3-axis tilt. X leans the ring both ways (kept within ±1.2 so it never
		# goes fully face-on = a flat marking ◯); Y and Z spin its orientation so every
		# star's ring sits at its own angle.
		_ring.rotation = Vector3(
			rng.randf_range(-1.2, 1.2),
			rng.randf_range(-PI, PI),
			rng.randf_range(-PI, PI))
		_companions.add_child(_ring)

	# Moons — 1..3 small shaded worlds sharing one tilted orbital plane.
	_moon_hub = Node3D.new()
	_moon_hub.rotation = Vector3(rng.randf_range(0.9, 1.3), 0.0, rng.randf_range(-0.2, 0.2))
	_companions.add_child(_moon_hub)
	var moons := 1 + rng.randi() % 3
	for i in moons:
		var moon := MeshInstance3D.new()
		var ms := SphereMesh.new()
		var rad := rng.randf_range(0.04, 0.085)
		ms.radius = rad
		ms.height = rad * 2.0
		moon.mesh = ms
		var mmat := StandardMaterial3D.new()
		mmat.albedo_color = col.lerp(Color(0.6, 0.6, 0.62), 0.6).darkened(rng.randf_range(0.0, 0.25))
		mmat.roughness = 0.95
		moon.material_override = mmat
		var orb := rng.randf_range(0.85, 1.35)
		var ang := rng.randf_range(0.0, TAU)
		moon.position = Vector3(cos(ang) * orb, 0.0, sin(ang) * orb)
		moon.set_meta("orbit", orb)
		moon.set_meta("ang", ang)
		moon.set_meta("spd", rng.randf_range(0.15, 0.45) * (1.0 if rng.randf() < 0.8 else -1.0))
		_moon_hub.add_child(moon)

func _update_companions(delta: float, near_t: float) -> void:
	if _companions == null:
		return
	# Hide once the world fills the screen on final approach (they'd be off-screen huge).
	_companions.visible = near_t < 0.9
	if not _companions.visible:
		return
	if _ring != null:
		_ring.rotate_object_local(Vector3.UP, delta * 0.10)
	if _moon_hub != null:
		for c in _moon_hub.get_children():
			var m := c as Node3D
			if m == null:
				continue
			var a := float(m.get_meta("ang", 0.0)) + delta * float(m.get_meta("spd", 0.3))
			m.set_meta("ang", a)
			var orb := float(m.get_meta("orbit", 1.0))
			m.position = Vector3(cos(a) * orb, 0.0, sin(a) * orb)

func _process(_delta: float) -> void:
	if _dispose_requested:
		return
	if _collapse_active:
		_run_collapse_space()
		return
	if _surface_mode:
		_run_surface_mode(_delta)
		return
	if GameState.star_entry:
		_run_entry()
		return

	# Size follows altitude directly: climb higher => smaller immediately, descend
	# lower => larger. No lagging approach value, so it never swells on its own.
	var near_t := clampf((GameState.ALT_MAX - GameState.alt) \
		/ (GameState.ALT_MAX - GameState.GROUND_ALT), 0.0, 1.0)
	approach = near_t
	var s := lerpf(0.9, SURFACE_SCALE, smoothstep(0.0, 1.0, near_t))
	scale = Vector3.ONE * s
	# The discovered planet is the destination. As altitude drops, the same orb
	# slides under the camera and swells into the surface instead of being replaced.
	var camera := get_viewport().get_camera_3d()
	var cx := camera.global_position.x if camera != null else 0.0
	var center_t := smoothstep(0.35, 1.0, near_t)
	var target_y := lerpf(_home.y, SURFACE_CENTER_Y, center_t)
	var bob := sin(GameState.frame * 0.01) * 0.05 * (1.0 - center_t)
	global_position = Vector3(lerpf(_home.x, cx, center_t), target_y + bob, BG_Z)
	_update_atmosphere_alpha(near_t)
	_roll_sphere_surface(near_t)
	if _surface_actor_root != null and _surface_actor_root.visible:
		if near_t >= ORBIT_ACTOR_UPDATE_NEAR:
			_update_sphere_actors(false)
			if near_t >= ORBIT_ACTOR_SPAWN_NEAR:
				_update_sphere_enemy_spawns()
		else:
			_surface_actor_root.visible = false
			for c in _surface_actor_root.get_children():
				c.queue_free()
	_maybe_begin_seamless_entry()
	_update_companions(_delta, near_t)

# Entry is altitude-driven: descend into the discovered planet.
func begin_entry(_carrier_boost: bool = false) -> void:
	if GameState.in_transition():
		return
	# A cleared star is collapsing/disposing — it must not be re-entered, or the
	# altitude logic flip-flops it (and resets the collapse), locking the ship.
	if _collapse_active or _dispose_requested:
		return
	_finish_entry(true)

# Legacy dive fallback. It now resolves into the same spherical surface mode.
func _run_entry() -> void:
	_entry_t += 1
	var k := float(_entry_t) / float(ENTRY_FRAMES)
	var ek := k * k   # rush: slow approach, then the star rapidly fills the view
	# Swell from far until it nearly fills the screen, staying far behind all
	# gameplay. Centre it as it grows.
	scale = Vector3.ONE * _screen_safe_scale(lerpf(_entry_start_scale, 72.0, ek), 86.0)
	global_position = Vector3(lerpf(global_position.x, 0.0, 0.06),
		lerpf(global_position.y, 0.0, 0.06), BG_Z)
	# Haze (and the cloud sea, gated on this in Mothership) hold off until the
	# star is almost full-screen, then billow up — "もくもく as the star fills it".
	GameState.entry_glow = smoothstep(0.55, 1.0, k)
	if _entry_t >= ENTRY_FRAMES:
		_finish_entry(true)

func _maybe_begin_seamless_entry() -> void:
	if GameState.stage != "space" or GameState.in_transition() or GameState.on_carrier:
		return
	if GameState.target_star != star_name:
		return
	if approach < 0.98:
		return
	if GameState.alt > GameState.GROUND_ALT + 0.6:
		return
	begin_entry(false)

func _finish_entry(seamless: bool = false) -> void:
	var b: Dictionary = PlanetTerrain.BIOMES.get(biome, PlanetTerrain.BIOMES["VERDANT"])
	GameState.stage = "planet"
	GameState.planet_name = star_name
	GameState.planet_biome = biome
	GameState.planet_type = star_type
	GameState.target_star = ""
	GameState.star_entry = false
	GameState.entry_glow = 0.0 if seamless else 1.0
	# Settle at low orbit. Star play stays in the top-down shooter camera; there
	# is no separate rear-view surface dive below ALT760.
	GameState.tAlt = GameState.GROUND_ALT
	GameState.alt = GameState.tAlt
	# The sky is wiped clean by re-entry: space enemies and bullets vanish, the
	# space-side carrier (the booster) is replaced by the arrival one, and any
	# DISCOVERED-STAR orbs / carrier beacons (space-only props) are cleared so they
	# don't linger inside the planet.
	# Keep space enemies/bullets/clouds ALIVE across the boundary so they flow onto
	# the surface — the star's biome enemies are already mixing into the approach
	# (EnemySpawner theme waves), so there's no "everything vanishes" pop at ALT760.
	# Only the space-navigation props (carrier + its beacons) are retired here.
	for grp in ["mothership", "mothership_beacon"]:
		for n in get_tree().get_nodes_in_group(grp):
			if n != self:
				n.queue_free()
	if not seamless:
		for n in get_tree().get_nodes_in_group("target_planet"):
			if n != self:
				n.queue_free()
	GameState.planet_seed = _surface_seed
	GameState.abyss_return_biome = ""  # fresh surface: no stale return target
	_enter_surface_mode()
	if not seamless:
		get_tree().call_group("star_hud", "show_message",
			Loc.pair("惑星 %s - %s", "PLANET %s - %s") % [star_name, b["label"]],
			"SPHERE STAR / SAME ORB SURFACE")
	if not seamless:
		queue_free()

func _enter_surface_mode() -> void:
	_surface_mode = true
	_surface_frames = 0
	_surface_blocks_broken = 0
	_surface_boss_spawned = false
	_enemy_timer = 18   # brief grace before the first sphere-enemy trickle
	add_to_group("planet_terrain")
	var rng := RandomNumberGenerator.new()
	rng.seed = _surface_seed
	GameState.planet_has_underground = false
	GameState.surface_festival_planet = true
	GameState.star_kind = star_type.to_upper()
	GameState.underground = false
	GameState.over_hole = false
	GameState.entry_glow = 0.0
	_key_gate_count = 0
	_gate_timer = 90
	_rescue_spawned = false
	_vip_spawned = false
	_planet_clear_announced = GameState.cleared_stars.has(star_name)
	# Do not swap lighting/environment here. The target planet is already the
	# live stage in space; changing shadows or ambience at ALT900 exposes a fake
	# mode switch.
	_surface_root.visible = true
	_surface_actor_root.visible = true
	_atmosphere.visible = true
	_update_atmosphere_alpha(approach)
	if star_type == "rescue":
		_spawn_rescue_signal()
	get_tree().call_group("star_hud", "show_message",
		"%s %s" % [star_type.to_upper(), star_name],
		_objective_text())

func _objective_text() -> String:
	match star_type:
		"mine":
			return Loc.t("DESTROY EVERY GOLD BLOCK")
		"rescue":
			return Loc.t("FIND SIGNAL - RESCUE THE VIP")
		_:
			return Loc.t("PASS 3 KEY GATES - ENTER BOSS GATE")

func _update_atmosphere_alpha(near_t: float) -> void:
	if _atmosphere_mat == null:
		return
	var a := lerpf(0.035, 0.004, clampf(near_t, 0.0, 1.0))
	_atmosphere_mat.albedo_color.a = a
	_atmosphere_mat.emission_energy_multiplier = lerpf(0.025, 0.0, clampf(near_t, 0.0, 1.0))

func _build_spherical_surface(rng: RandomNumberGenerator) -> void:
	for c in _surface_root.get_children():
		c.queue_free()
	_surface_blocks.clear()
	_rescue_obstacles.clear()
	# Null until _finalize_surface_multimesh: while building, _sphere_block just
	# collects records; once the MultiMesh exists, _sphere_block adds live (horizon).
	_surface_mm = null
	_surface_mmi = null
	# Lower block density (≈half the count) + bigger blocks below: fewer instances
	# keep the per-shot hit scan and vertex count down while the larger blocks fill
	# the same surface.
	var lat_rows := 24 if star_type == "mine" else (18 if star_type == "rescue" else 21)
	var lon_cols := 58 if star_type == "mine" else (44 if star_type == "rescue" else 50)
	var mountains: Array[Dictionary] = []
	var valleys: Array[Dictionary] = []
	var mountain_count := 7 if star_type == "mine" else 9
	var valley_count := 5 if star_type == "mine" else 7
	for i in mountain_count:
		mountains.append({
			"lat": rng.randf_range(-1.05, 1.05),
			"lon": rng.randf_range(-PI, PI),
			"r": rng.randf_range(0.24, 0.52),
			"h": rng.randf_range(0.70, 1.55),
		})
	for i in valley_count:
		valleys.append({
			"lat": rng.randf_range(-1.10, 1.10),
			"lon": rng.randf_range(-PI, PI),
			"r": rng.randf_range(0.22, 0.46),
			"h": rng.randf_range(0.45, 1.20),
		})
	for row in lat_rows:
		var rv := float(row) / float(maxi(1, lat_rows - 1))
		var lat := lerpf(-1.22, 1.22, rv)
		var row_cols := maxi(12, int(float(lon_cols) * cos(absf(lat) * 0.62)))
		for col in row_cols:
			var u := (float(col) + 0.5 * float(row % 2)) / float(row_cols)
			var lon := -PI + TAU * u + rng.randf_range(-0.018, 0.018)
			var terrain := _terrain_profile(lat, lon, mountains, valleys)
			var height_field := float(terrain["height"])
			var valley_field := float(terrain["valley"])
			var mountain_field := float(terrain["mountain"])
			if valley_field > 0.56 and rng.randf() < (0.08 if star_type == "mine" else (0.30 if star_type == "rescue" else 0.18)):
				continue
			var tall_chance := clampf((0.10 if star_type == "mine" else (0.09 if star_type == "rescue" else 0.17))
				+ mountain_field * 0.34 - valley_field * 0.12, 0.04, 0.58)
			var tall := rng.randf() < tall_chance
			var h := rng.randf_range(0.008, 0.026) if not tall else rng.randf_range(0.032, 0.072)
			var w := rng.randf_range(0.013, 0.032) if not tall else rng.randf_range(0.030, 0.075)
			h *= height_field
			w *= lerpf(0.72, 1.55, clampf(mountain_field + height_field * 0.18, 0.0, 1.0))
			if star_type == "mine":
				h *= rng.randf_range(0.88, 1.22)
				w *= rng.randf_range(1.06, 1.42)
			_sphere_block(lat, lon, Vector3(w, rng.randf_range(0.009, 0.026), h),
				_pick_block_material(rng))
	_finalize_surface_multimesh()
	_seed_route_plate(rng)
	var prop_count := 18 if star_type == "mine" else (34 if star_type == "rescue" else 44)
	for i in prop_count:
		var prop_lat := rng.randf_range(-1.02, 1.04)
		var prop_lon := rng.randf_range(-PI, PI)
		_sphere_prop(prop_lat, prop_lon, rng)
	if star_type == "rescue":
		_build_rescue_obstacles(rng)

func _terrain_profile(lat: float, lon: float, mountains: Array[Dictionary],
		valleys: Array[Dictionary]) -> Dictionary:
	var mountain := 0.0
	for m in mountains:
		var dlat := lat - float(m["lat"])
		var dlon := _angle_delta(lon, float(m["lon"]))
		var d := sqrt(dlat * dlat + dlon * dlon)
		var r := float(m["r"])
		var influence := (1.0 - smoothstep(0.0, r, d)) * float(m["h"])
		mountain = maxf(mountain, influence)
	var valley := 0.0
	for v in valleys:
		var dlat := lat - float(v["lat"])
		var dlon := _angle_delta(lon, float(v["lon"]))
		var d := sqrt(dlat * dlat + dlon * dlon)
		var r := float(v["r"])
		var influence := (1.0 - smoothstep(0.0, r, d)) * float(v["h"])
		valley = maxf(valley, influence)
	var ridge := 0.5 + 0.5 * sin(lon * 2.3 + lat * 3.8 + float(_surface_seed % 97) * 0.031)
	ridge *= 0.5 + 0.5 * sin(lon * 5.1 - lat * 1.7)
	var height := clampf(0.72 + mountain * 1.25 + ridge * 0.55 - valley * 0.62, 0.32, 2.65)
	return {"height": height, "mountain": mountain, "valley": valley}

func _angle_delta(a: float, b: float) -> float:
	return atan2(sin(a - b), cos(a - b))

func _sphere_block(lat: float, lon: float, size: Vector3, color: Color) -> void:
	var n := Vector3(sin(lon) * cos(lat), sin(lat), cos(lon) * cos(lat)).normalized()
	var right := Vector3.UP.cross(n)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := n.cross(right).normalized()
	# scaled_local (NOT scaled): scale along the block's OWN axes so it stays a
	# proper box. Basis.scaled() scales the global axes (rows), which shears a
	# rotated box into a trapezoid/parallelepiped — the old per-node `m.scale`
	# applied a local scale, which this matches.
	var xf := Transform3D(Basis(right, up, n).scaled_local(size),
		n * (SURFACE_RADIUS + size.z * 0.5))
	var h := _block_hp()
	if _surface_mm == null:
		# Build phase: collect; the MultiMesh is filled in one pass at finalize.
		_surface_blocks.append({"xf": xf, "color": color, "hp": h, "maxhp": h, "base": color})
		return
	# Live add during play (horizon respawn): drop the block into a free slot.
	var slot := _surface_blocks.size()
	if slot >= _surface_mm.instance_count:
		return  # buffer full (should not happen: each break frees one slot)
	_surface_blocks.append({"xf": xf, "color": color, "hp": h, "maxhp": h, "base": color})
	_surface_mm.set_instance_transform(slot, xf)
	_surface_mm.set_instance_color(slot, color)
	_surface_mm.visible_instance_count = _surface_blocks.size()

# Pack the blocks collected during _build_spherical_surface into one MultiMesh.
func _finalize_surface_multimesh() -> void:
	_surface_mmi = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _block_mesh
	var n := _surface_blocks.size()
	mm.instance_count = n + 128   # headroom for live horizon respawns
	mm.visible_instance_count = n
	for i in n:
		var rec: Dictionary = _surface_blocks[i]
		mm.set_instance_transform(i, rec["xf"])
		mm.set_instance_color(i, rec["color"])
	_surface_mmi.multimesh = mm
	_surface_mmi.material_override = _surface_block_mat
	_surface_root.add_child(_surface_mmi)
	_surface_mm = mm

# Hide the block in slot `i` by swapping the last active instance into it and
# shrinking the visible count — O(1) and keeps array index == instance slot.
func _remove_surface_instance(i: int) -> void:
	var last := _surface_blocks.size() - 1
	if last < 0:
		return
	if i != last:
		var lr: Dictionary = _surface_blocks[last]
		_surface_blocks[i] = lr
		_surface_mm.set_instance_transform(i, lr["xf"])
		_surface_mm.set_instance_color(i, lr["color"])
	_surface_blocks.resize(last)
	_surface_mm.visible_instance_count = last
	_blk_sp_frame = -1   # block layout changed → force the screen cache to rebuild next hit-test

func _spawn_horizon_surface_block() -> void:
	if star_type == "mine" or star_type == "rescue" or _block_mats.is_empty():
		return
	# Thin the respawn: breaking a cluster shouldn't flood a stream of blocks back
	# in. Only some breaks respawn, keeping the count light (the surface gently
	# depletes, which is fine and avoids frame drops).
	var respawn_chance := 0.22 if star_type == "rescue" else 0.4
	if randf() > respawn_chance:
		return
	# Respawn OFF-SCREEN above the top horizon, then let the surface roll frame it
	# in — never pop a block into a visible spot. Blocks live in _surface_root's
	# rotating local frame (rotation_degrees.x accumulates), so a fixed lat/lon
	# would land at an arbitrary on-screen position (the old bug). Aim at a world
	# direction just past the incoming (back-)top edge, then UN-rotate by the
	# current spin/yaw so that once the live rotation re-applies, the block sits
	# off-screen-top now and rolls down into frame. nx is the LEFT-RIGHT spread and
	# is roll-invariant (X-roll preserves x), so spread it WIDE so blocks scatter
	# across the width instead of lining up in a column in front of the ship.
	var theta := deg_to_rad(_surface_root.rotation_degrees.x)
	var yaw := deg_to_rad(_surface_roll_root.rotation_degrees.y) if _surface_roll_root != null else 0.0
	var nx := randf_range(-0.72, 0.72)                 # wide horizontal scatter
	var rem := sqrt(maxf(0.0, 1.0 - nx * nx))
	var beta := deg_to_rad(randf_range(18.0, 40.0))    # up/back tilt (also varies arrival timing)
	var world_n := Vector3(nx, rem * cos(beta), -rem * sin(beta))
	# Block world = R_y(yaw) · R_x(theta) · local, so invert in reverse order.
	var local_n := world_n.rotated(Vector3.UP, -yaw).rotated(Vector3.RIGHT, -theta).normalized()
	var lat := asin(clampf(local_n.y, -1.0, 1.0))
	var lon := atan2(local_n.x, local_n.z)
	var ridge := 0.5 + 0.5 * sin(lon * 4.7 + float(_surface_seed % 113) * 0.021
		+ float(_surface_blocks_broken) * 0.17)
	var tall := randf() < lerpf(0.16, 0.44, ridge)
	var h := randf_range(0.009, 0.029) if not tall else randf_range(0.038, 0.084)
	var w := randf_range(0.015, 0.038) if not tall else randf_range(0.035, 0.084)
	var y := randf_range(0.009, 0.029)
	_sphere_block(lat, lon, Vector3(w, y, h),
		(_block_mats[randi() % _block_mats.size()]).albedo_color)

func _sphere_prop(lat: float, lon: float, rng: RandomNumberGenerator) -> void:
	if _prop_mats.is_empty():
		return
	var n := Vector3(sin(lon) * cos(lat), sin(lat), cos(lon) * cos(lat)).normalized()
	var right := Vector3.UP.cross(n)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := n.cross(right).normalized()
	var root := Node3D.new()
	root.transform = Transform3D(Basis(right, up, n), n * (SURFACE_RADIUS + 0.036))
	root.rotation_degrees.z = rng.randf_range(-28.0, 28.0)
	_surface_root.add_child(root)
	# Dark worlds: ~40% of props become a cluster of glowing crystal spires (キラキラ) that
	# twinkle in the gloom instead of dull rocks.
	if _spark_mat != null and rng.randf() < 0.4:
		var spikes := 2 + rng.randi() % 3
		for i in spikes:
			var s := MeshInstance3D.new()
			s.mesh = _block_mesh
			s.material_override = _spark_mat
			s.position = Vector3(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03),
				0.02 + rng.randf_range(0.0, 0.04))
			s.rotation_degrees = Vector3(rng.randf_range(-22.0, 22.0), 0.0,
				rng.randf_range(-22.0, 22.0))
			s.scale = Vector3(rng.randf_range(0.010, 0.022), rng.randf_range(0.010, 0.022),
				rng.randf_range(0.045, 0.110))
			root.add_child(s)
		return
	var count := 1 + rng.randi() % 3
	for i in count:
		var m := MeshInstance3D.new()
		m.mesh = _block_mesh
		m.material_override = _prop_mats[rng.randi() % _prop_mats.size()]
		m.position = Vector3((float(i) - float(count - 1) * 0.5) * 0.035, 0.0,
			0.018 + float(i) * 0.012)
		m.scale = Vector3(rng.randf_range(0.018, 0.045), rng.randf_range(0.018, 0.060),
			rng.randf_range(0.035, 0.095))
		root.add_child(m)

func _build_rescue_obstacles(rng: RandomNumberGenerator) -> void:
	if _prop_mats.is_empty():
		return
	var count := 132
	for i in count:
		var central_lane := rng.randf() < 0.48
		var lat := rng.randf_range(-0.46, 0.46) if central_lane else rng.randf_range(-1.08, 1.08)
		var lon := -PI + TAU * (float(i) / float(count)) + rng.randf_range(-0.16, 0.16)
		var n := Vector3(sin(lon) * cos(lat), sin(lat), cos(lon) * cos(lat)).normalized()
		var right := Vector3.UP.cross(n)
		if right.length_squared() < 0.0001:
			right = Vector3.RIGHT
		right = right.normalized()
		var up := n.cross(right).normalized()
		var root := Node3D.new()
		root.transform = Transform3D(Basis(right, up, n), n * (SURFACE_RADIUS + 0.050))
		root.rotation_degrees.z = rng.randf_range(-12.0, 12.0)
		_surface_root.add_child(root)
		var floors := (3 + rng.randi() % 5) if central_lane else (2 + rng.randi() % 4)
		var mat := _prop_mats[rng.randi() % _prop_mats.size()]
		for f in floors:
			var m := MeshInstance3D.new()
			m.mesh = _block_mesh
			m.material_override = mat
			m.position = Vector3(0.0, 0.0, 0.026 + float(f) * 0.038)
			var bulk := 1.22 if central_lane else 1.0
			m.scale = Vector3(rng.randf_range(0.026, 0.058) * bulk,
				rng.randf_range(0.026, 0.058) * bulk,
				rng.randf_range(0.060, 0.115) * bulk)
			root.add_child(m)
		if rng.randf() < (0.76 if central_lane else 0.55):
			var arm := MeshInstance3D.new()
			arm.mesh = _block_mesh
			arm.material_override = mat
			arm.position = Vector3(rng.randf_range(-0.038, 0.038), 0.0,
				0.080 + float(floors) * 0.026)
			arm.scale = Vector3(rng.randf_range(0.080, 0.155) * (1.18 if central_lane else 1.0),
				rng.randf_range(0.020, 0.040), rng.randf_range(0.034, 0.060))
			root.add_child(arm)
		_rescue_obstacles.append({
			"node": root,
			"radius": rng.randf_range(70.0, 105.0) if central_lane else rng.randf_range(48.0, 75.0),
		})

func _setup_surface_air(rng: RandomNumberGenerator) -> void:
	var b: Dictionary = PlanetTerrain.BIOMES.get(biome, PlanetTerrain.BIOMES["VERDANT"])
	var sky: Color = b["sky"]
	var dim := bool(b.get("dim", false))
	# Dark worlds: a feeble/dead star. Drop the sun low and cool, and lean on the planet's
	# own emissive glow (sparkle crystals, lava, beacons) for the light — bloom is on.
	var sun := rng.randf_range(0.0, float(b.get("dim_sun", 0.2))) if dim \
		else 1.0 - pow(rng.randf(), 1.8)
	_light = get_tree().current_scene.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if _light != null:
		_saved_light_energy = _light.light_energy
		_saved_light_color = _light.light_color
		_saved_light_tf = _light.transform
		_saved_light_shadow = _light.shadow_enabled
		_light.light_energy = lerpf(0.18, 0.6, sun) if dim else lerpf(0.65, 1.65, sun)
		_light.light_color = sky.lightened(0.32) if dim \
			else Color(1.0, 0.94, 0.82).lerp(sky.lightened(0.25), 0.22)
		_light.rotation_degrees = Vector3(-48.0, rng.randf_range(-34.0, 34.0), 0.0)
		_light.shadow_enabled = false
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.018)
	env.fog_enabled = dim
	env.fog_light_color = sky.lightened(0.18)
	env.fog_density = 0.05 if dim else 0.0   # soft murk that the emissive glow bleeds into
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = sky
	env.ambient_light_energy = 0.18 if dim else 0.34
	# Bloom: bright emissive parts (lamps, lava, beacons, FX) softly glow.
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	# High threshold so ordinary white surface (snow/ice/bright stone) does NOT bloom;
	# only the warm-boosted gold/ore/lava (emission pushed well above 1) glows.
	env.glow_hdr_threshold = 1.4
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_world_env = WorldEnvironment.new()
	_world_env.environment = env
	_world_env.add_to_group("world_env")
	add_child(_world_env)

func _run_surface_mode(_delta: float) -> void:
	_surface_frames += 1
	var camera := get_viewport().get_camera_3d()
	var cx := camera.global_position.x if camera != null else 0.0
	var air_t := clampf((GameState.alt - GameState.PLANET_SURFACE_ALT) \
		/ (GameState.GROUND_ALT - GameState.PLANET_SURFACE_ALT), 0.0, 1.0)
	var low_t := 1.0 - air_t
	# The surface band lives below ALT900. At ALT900 the same sphere is still
	# large in low orbit; climbing after exit shrinks it through the space band.
	scale = Vector3.ONE * SURFACE_SCALE * (1.0 + low_t * 0.24)
	global_position = Vector3(cx, SURFACE_CENTER_Y - low_t * 2.8, BG_Z)
	# The planet always rolls from horizon to foreground. Side input only turns
	# longitude; it never changes the forward flow.
	_roll_sphere_surface(1.0)
	_update_sphere_actors()
	_update_sphere_enemy_spawns()
	# Exit is input-driven from Unit1: ALT900 is a playable low-orbit edge, not
	# an automatic scene boundary. Scroll up from there to return to space.

func _roll_sphere_surface(strength: float) -> void:
	var k := clampf(strength, 0.0, 1.0)
	if _surface_roll_root == null or _surface_root == null:
		return
	# Yaw the parent first, then roll the surface child forward. That makes the
	# forward roll axis follow the ship's current longitude instead of flipping
	# after the sphere has spun for a while.
	_surface_roll_root.rotation_degrees.y = lerpf(_surface_roll_root.rotation_degrees.y,
		_surface_yaw * k, 0.075)
	_surface_root.rotation_degrees.y = lerpf(_surface_root.rotation_degrees.y, 0.0, 0.12)
	var side := clampf(_surface_yaw / 18.0, -1.0, 1.0) * 0.014
	_surface_roll_root.position.x = lerpf(_surface_roll_root.position.x, side, 0.11)
	_surface_root.position.x = 0.0
	var depth_push := clampf((GameState.GROUND_ALT - GameState.alt) \
		/ (GameState.GROUND_ALT - GameState.PLANET_SURFACE_ALT), 0.0, 1.0)
	var spin := (0.150 + depth_push * 0.035) * k
	_surface_root.rotation_degrees.x += spin
	if _surface_actor_root != null:
		_surface_actor_root.rotation_degrees.x = _surface_root.rotation_degrees.x
		_surface_actor_root.rotation_degrees.y = 0.0
		_surface_actor_root.position.x = 0.0
	if _ball != null:
		_ball.rotation_degrees.x = _surface_root.rotation_degrees.x
		_ball.rotation_degrees.y = _surface_roll_root.rotation_degrees.y
		_ball.rotation_degrees.z = 0.0
		_ball.position.x = _surface_roll_root.position.x
	if _atmosphere != null:
		_atmosphere.rotation_degrees.x = _surface_root.rotation_degrees.x
		_atmosphere.rotation_degrees.y = _surface_roll_root.rotation_degrees.y
		_atmosphere.rotation_degrees.z = 0.0
		_atmosphere.position.x = _surface_roll_root.position.x

func _update_sphere_actors(allow_objective_spawns: bool = true) -> void:
	if allow_objective_spawns:
		if star_type == "boss":
			_update_surface_gate_spawns()
		elif star_type == "rescue" and not _rescue_spawned:
			_spawn_rescue_signal()
	for c in _surface_actor_root.get_children():
		var n := c as Node3D
		if n == null or n.is_queued_for_deletion():
			continue
		var kind := String(n.get_meta("kind", "enemy"))
		var lat := float(n.get_meta("lat", 0.0))
		var lon := float(n.get_meta("lon", 0.0))
		var lane := float(n.get_meta("lane", 0.0))
		if kind == "enemy":
			var moved := _update_sphere_enemy_motion(n, lat, lon, lane)
			lat = moved.x
			lon = moved.y
			_update_sphere_enemy_fire(n)
		elif kind == "key_gate" or kind == "boss_gate":
			lat -= 0.0037
			lon += lane * 0.0011
		elif kind == "rescue_signal" or kind == "vip":
			lat -= 0.00058
			lon += lane * 0.00035
		else:
			lat -= 0.0046
			lon += lane * 0.0015
		n.set_meta("lat", lat)
		n.set_meta("lon", lon)
		_place_sphere_actor(n, lat, lon, _actor_surface_lift(kind, String(n.get_meta("mode", ""))))
		var sc := clampf(inverse_lerp(0.72, -0.55, lat), 0.0, 1.0)
		if kind == "key_gate" or kind == "boss_gate":
			n.scale = Vector3.ONE * lerpf(0.22, 0.52, sc)
		elif kind == "enemy" and String(n.get_meta("mode", "")) == "turret":
			n.scale = Vector3.ONE * lerpf(0.09, 0.23, sc)
		elif kind == "enemy" and String(n.get_meta("mode", "")) == "bomber":
			n.scale = Vector3.ONE * lerpf(0.09, 0.22, sc)
		elif kind == "enemy" and String(n.get_meta("mode", "")) == "saucer":
			n.scale = Vector3.ONE * lerpf(0.09, 0.22, sc)
		elif kind == "enemy" and String(n.get_meta("mode", "")) == "asteroid":
			n.scale = Vector3.ONE * lerpf(0.13, 0.32, sc)
		elif kind == "enemy" and String(n.get_meta("mode", "")) == "amoeba":
			n.scale = Vector3.ONE * lerpf(0.13, 0.34, sc)   # a bit bigger than the rabble
		elif kind == "enemy" and String(n.get_meta("mode", "")) == "surface_boss":
			n.scale = Vector3.ONE * lerpf(0.48, 1.08, sc)
		elif kind == "rescue_signal" or kind == "vip":
			n.scale = Vector3.ONE * lerpf(0.16, 0.34, sc)
		else:
			n.scale = Vector3.ONE * (lerpf(0.18, 0.36, sc) if kind == "repair" else lerpf(0.08, 0.20, sc))
		if kind == "repair" and _sphere_repair_collects(n):
			_collect_sphere_repair(n)
			continue
		if (kind == "rescue_signal" or kind == "vip") and _sphere_repair_collects(n):
			_collect_rescue_actor(n, kind)
			continue
		if (kind == "key_gate" or kind == "boss_gate") and _sphere_gate_collects(n):
			_collect_surface_gate(n, kind)
			continue
		var top_limit := 1.12 if (kind == "rescue_signal" or kind == "vip") else 0.86
		if lat < -0.76 or lat > top_limit:
			if kind == "rescue_signal":
				_rescue_spawned = false
			elif kind == "vip":
				_vip_spawned = false
			n.queue_free()

func add_surface_yaw(delta: float) -> void:
	_surface_yaw = clampf(_surface_yaw + delta, -18.0, 18.0)

func set_surface_yaw(target: float) -> void:
	_surface_yaw = clampf(target, -18.0, 18.0)

func _sphere_enemy_count() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("sphere_enemies"):
		if is_instance_valid(e) and not (e as Node).is_queued_for_deletion():
			n += 1
	return n

func _amoeba_alive() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("sphere_enemies"):
		if is_instance_valid(e) and not (e as Node).is_queued_for_deletion() \
				and String((e as Node).get_meta("mode", "")) == "amoeba":
			n += 1
	return n

# Re-enabled rear-view-era star enemies: the sphere-riding set trickles in on a
# cadence (capped), running ALONGSIDE the EnemySpawner biome air waves. The boss
# star also keeps its gates/surface boss from _update_sphere_actors; the cap keeps
# the rabble from piling up on top of those.
func _update_sphere_enemy_spawns() -> void:
	# The final-boss sequence + ending are peaceful — no surface rabble.
	if GameState.final_phase != GameState.FINAL_NONE:
		return
	# Amoebas drip in ONE AT A TIME on random gaps (never a wall all at once), and only
	# while few are alive — so the player's shots always have room to get through.
	if _amoeba_queue > 0:
		_amoeba_drip -= 1
		if _amoeba_drip <= 0:
			if _sphere_enemy_count() < SPHERE_ENEMY_CAP and _amoeba_alive() < 4:
				_spawn_sphere_enemy("amoeba", randf_range(-0.40, 0.40),
					randf_range(0.26, 0.44), randf_range(-0.16, 0.16))
				_amoeba_queue -= 1
			_amoeba_drip = randi_range(55, 140)   # random gap before the next one
	_enemy_timer -= 1
	if _enemy_timer > 0:
		return
	_enemy_timer = int(lerpf(18.0, 10.0, GameState.difficulty())) + randi() % 8
	var live := _sphere_enemy_count()
	if live >= SPHERE_ENEMY_CAP:
		return
	if randf() < 0.42 and live <= SPHERE_ENEMY_CAP - 4:
		_spawn_sphere_enemy_wave()
	else:
		_spawn_sphere_enemy_trickle()

func _spawn_sphere_enemy_trickle() -> void:
	var modes := ["formation", "hunter", "swooper", "missile", "rammer",
		"weaver", "bomber", "saucer", "asteroid"]
	var mode := String(modes[randi() % modes.size()])
	var lon := randf_range(-0.52, 0.52)
	var lat := randf_range(0.20, 0.52)
	var lane := randf_range(-0.45, 0.45)
	match mode:
		"swooper":
			var side := -1.0 if randf() < 0.5 else 1.0
			lon = side * randf_range(0.42, 0.58)
			lane = -side * randf_range(0.35, 0.62)
			lat = randf_range(0.16, 0.44)
		"turret":
			lat = randf_range(0.30, 0.55)
			lane = 0.0
		"asteroid":
			lat = randf_range(0.25, 0.58)
			lane = randf_range(-0.26, 0.26)
		"saucer":
			lat = randf_range(0.16, 0.48)
			lane = randf_range(-0.58, 0.58)
		"rammer":
			lat = randf_range(0.28, 0.58)
			lane = randf_range(-0.24, 0.24)
	_spawn_sphere_enemy(mode, lon, lat, lane)

func _spawn_sphere_enemy_wave() -> int:
	var wave := randi() % 11
	match wave:
		0:
			var n := 5
			var base_lon := randf_range(-0.24, 0.24)
			var base_lat := randf_range(0.18, 0.40)
			for i in n:
				var off := float(i) - float(n - 1) * 0.5
				_spawn_sphere_enemy("formation", base_lon + off * 0.080,
					base_lat + absf(off) * 0.030, off * 0.08)
			return n
		1:
			var n := 3
			var side := -1.0 if randf() < 0.5 else 1.0
			for i in n:
				_spawn_sphere_enemy("swooper", side * (0.50 + float(i) * 0.050),
					randf_range(0.12, 0.34) + float(i) * 0.020, -side * 0.55)
			return n
		2:
			var n := 2
			for i in n:
				_spawn_sphere_enemy("missile", randf_range(-0.34, 0.34),
					randf_range(0.08, 0.30), randf_range(-0.18, 0.18))
			return n
		3:
			var n := 4
			for i in n:
				_spawn_sphere_enemy("hunter", randf_range(-0.44, 0.44),
					randf_range(0.12, 0.38), randf_range(-0.35, 0.35))
			return n
		4:
			var n := 4
			var base_lat := randf_range(0.30, 0.52)
			for i in n:
				var off := float(i) - float(n - 1) * 0.5
				_spawn_sphere_enemy("turret", off * 0.18, base_lat + absf(off) * 0.018, 0.0)
			return n
		5:
			var n := 3
			for i in n:
				_spawn_sphere_enemy("rammer", randf_range(-0.34, 0.34),
					0.30 + float(i) * 0.040, randf_range(-0.20, 0.20))
			return n
		6:
			var n := 6
			var side := -1.0 if randf() < 0.5 else 1.0
			for i in n:
				_spawn_sphere_enemy("weaver", side * (0.52 - float(i) * 0.12),
					0.24 + sin(float(i) * 0.9) * 0.07, -side * 0.50)
			return n
		7:
			var n := 3
			for i in n:
				_spawn_sphere_enemy("saucer", randf_range(-0.42, 0.42),
					randf_range(0.16, 0.42), randf_range(-0.45, 0.45))
			return n
		8:
			var n := 3
			for i in n:
				_spawn_sphere_enemy("asteroid", randf_range(-0.48, 0.48),
					randf_range(0.22, 0.50), randf_range(-0.28, 0.28))
			return n
		9:
			# Don't wall the screen: QUEUE a random number of amoebas to drip in one at a
			# time over random gaps (handled in _update_sphere_enemy_spawns).
			_amoeba_queue = maxi(_amoeba_queue, randi_range(1, 3))
			_amoeba_drip = randi_range(20, 70)
			return 0
		_:
			var n := 2
			for i in n:
				_spawn_sphere_enemy("bomber", randf_range(-0.38, 0.38),
					randf_range(0.24, 0.48), randf_range(-0.10, 0.10))
			return n

func _spawn_sphere_enemy(mode: String = "hunter", lon_override := INF,
		lat_override := INF, lane_override := INF) -> void:
	var root := Node3D.new()
	var lon := randf_range(-0.42, 0.42) if is_inf(lon_override) else lon_override
	var lat := randf_range(0.18, 0.48) if is_inf(lat_override) else lat_override
	root.add_to_group("sphere_enemies")
	root.set_meta("kind", "enemy")
	root.set_meta("mode", mode)
	root.set_meta("lat", lat)
	root.set_meta("lon", lon)
	root.set_meta("lane", randf_range(-0.5, 0.5) if is_inf(lane_override) else lane_override)
	root.set_meta("age", 0)
	# Zako durability bump (light surface fry survive a couple more hits now).
	root.set_meta("hp", 2 if mode in ["formation", "swooper", "weaver"] \
		else (18 if mode == "amoeba" \
		else (5 if mode == "asteroid" else (4 if mode in ["turret", "bomber", "saucer"] else 3))))
	root.set_meta("fire_cd", 35 + randi() % 50)
	if mode == "amoeba":
		# Each amoeba is a different malevolent hue, and squirms on its own phase.
		root.set_meta("amoeba_col", AMOEBA_COLORS[randi() % AMOEBA_COLORS.size()])
		root.set_meta("phase", randf() * TAU)
	_surface_actor_root.add_child(root)
	_build_sphere_enemy_body(root, mode)
	root.scale = Vector3.ONE * 0.18
	_place_sphere_actor(root, lat, lon, _actor_surface_lift("enemy", mode))

func _spawn_surface_harrier_boss() -> void:
	if _surface_actor_root == null or _surface_boss_spawned:
		return
	_surface_boss_spawned = true
	var root := Node3D.new()
	root.add_to_group("sphere_enemies")
	root.set_meta("kind", "enemy")
	root.set_meta("mode", "surface_boss")
	root.set_meta("lat", 0.86)
	root.set_meta("lon", 0.0)
	root.set_meta("lane", 0.0)
	root.set_meta("age", 0)
	root.set_meta("hp", 34)
	root.set_meta("fire_cd", 28)
	_surface_actor_root.add_child(root)
	_build_surface_harrier_boss_body(root)
	root.scale = Vector3.ONE * 0.48
	_place_sphere_actor(root, 0.86, 0.0, 0.12)
	get_tree().call_group("star_hud", "show_message",
		"SURFACE BOSS APPROACHING", "BREAK THROUGH THE STAR DEFENSE")

func _build_surface_harrier_boss_body(root: Node3D) -> void:
	var shell := _enemy_material(Color(0.78, 0.10, 0.22), Color(1.0, 0.05, 0.18), 1.0)
	var core := _enemy_material(Color(0.10, 0.02, 0.04), Color(1.0, 0.55, 0.08), 1.2)
	var trim := _enemy_material(Color(0.98, 0.70, 0.20), Color(1.0, 0.42, 0.06), 1.4)
	_add_enemy_part(root, Vector3(0.0, 0.0, 0.010), Vector3(0.085, 0.170, 0.045), 0.0, core)
	_add_enemy_part(root, Vector3(0.0, -0.090, 0.026), Vector3(0.050, 0.052, 0.032), 0.0, shell)
	_add_enemy_part(root, Vector3(0.0, 0.088, 0.028), Vector3(0.048, 0.040, 0.026), 0.0, trim)
	for side in [-1.0, 1.0]:
		_add_enemy_part(root, Vector3(side * 0.116, -0.020, 0.012),
			Vector3(0.135, 0.038, 0.026), -side * 18.0, shell)
		_add_enemy_part(root, Vector3(side * 0.175, -0.064, 0.024),
			Vector3(0.075, 0.026, 0.024), -side * 32.0, trim)
		_add_enemy_part(root, Vector3(side * 0.055, 0.115, 0.000),
			Vector3(0.032, 0.040, 0.030), side * 12.0, core)
		_add_enemy_part(root, Vector3(side * 0.040, 0.150, -0.020),
			Vector3(0.026, 0.020, 0.026), 0.0, shell)

func _build_sphere_enemy_body(root: Node3D, mode: String) -> void:
	if mode == "amoeba":
		_build_amoeba_body(root, root.get_meta("amoeba_col", Color(1.0, 0.2, 0.22)))
		return
	var mat: Material = _enemy_mats.get(mode, _enemy_mat)
	var core: Material = _enemy_core_mats.get(mode, _enemy_core_mat)
	var trim: Material = _enemy_trim_mats.get(mode, _enemy_core_mat)
	match mode:
		"formation":
			_add_enemy_part(root, Vector3(0.0, 0.000, 0.006), Vector3(0.022, 0.060, 0.018), 0.0, mat)
			_add_enemy_part(root, Vector3(0.0, -0.026, 0.020), Vector3(0.018, 0.018, 0.012), 0.0, trim)
			_add_enemy_part(root, Vector3(-0.036, -0.004, 0.004), Vector3(0.052, 0.010, 0.012), 15.0, mat)
			_add_enemy_part(root, Vector3(0.036, -0.004, 0.004), Vector3(0.052, 0.010, 0.012), -15.0, mat)
			_add_enemy_part(root, Vector3(0.0, 0.038, -0.002), Vector3(0.018, 0.018, 0.014), 0.0, core)
			_add_enemy_part(root, Vector3(0.0, 0.032, 0.034), Vector3(0.010, 0.018, 0.032), 0.0, trim)
		"swooper":
			_add_enemy_part(root, Vector3(0.0, 0.000, 0.006), Vector3(0.026, 0.048, 0.018), 0.0, core)
			_add_enemy_part(root, Vector3(-0.052, -0.006, 0.004), Vector3(0.072, 0.010, 0.014), 30.0, mat)
			_add_enemy_part(root, Vector3(0.052, -0.006, 0.004), Vector3(0.072, 0.010, 0.014), -30.0, mat)
			_add_enemy_part(root, Vector3(0.0, -0.030, 0.020), Vector3(0.034, 0.016, 0.012), 0.0, trim)
			_add_enemy_part(root, Vector3(0.0, 0.034, -0.002), Vector3(0.030, 0.020, 0.014), 0.0, mat)
			_add_enemy_part(root, Vector3(0.0, 0.030, 0.032), Vector3(0.012, 0.018, 0.038), 0.0, mat)
		"missile":
			_add_enemy_part(root, Vector3(0.0, 0.000, 0.006), Vector3(0.018, 0.076, 0.018), 0.0, mat)
			_add_enemy_part(root, Vector3(0.0, 0.044, -0.002), Vector3(0.026, 0.018, 0.018), 0.0, core)
			_add_enemy_part(root, Vector3(0.0, -0.044, 0.020), Vector3(0.014, 0.020, 0.012), 0.0, trim)
			_add_enemy_part(root, Vector3(-0.022, 0.018, 0.004), Vector3(0.030, 0.006, 0.010), -22.0, mat)
			_add_enemy_part(root, Vector3(0.022, 0.018, 0.004), Vector3(0.030, 0.006, 0.010), 22.0, mat)
			_add_enemy_part(root, Vector3(0.0, 0.042, 0.030), Vector3(0.010, 0.020, 0.035), 0.0, trim)
		"turret":
			_add_enemy_part(root, Vector3(0.0, 0.0, 0.009), Vector3(0.085, 0.060, 0.018), 0.0, core)
			_add_enemy_part(root, Vector3(0.0, 0.0, 0.034), Vector3(0.040, 0.034, 0.032), 0.0, mat)
			_add_enemy_part(root, Vector3(0.0, 0.0, 0.080), Vector3(0.016, 0.016, 0.070), 0.0, mat)
			_add_enemy_part(root, Vector3(-0.052, 0.0, 0.010), Vector3(0.048, 0.012, 0.017), 0.0, mat)
			_add_enemy_part(root, Vector3(0.052, 0.0, 0.010), Vector3(0.048, 0.012, 0.017), 0.0, mat)
		"rammer":
			_add_enemy_part(root, Vector3(0.0, 0.000, 0.008), Vector3(0.032, 0.090, 0.022), 0.0, core)
			_add_enemy_part(root, Vector3(0.0, -0.052, 0.026), Vector3(0.044, 0.026, 0.018), 0.0, mat)
			_add_enemy_part(root, Vector3(-0.040, 0.012, 0.004), Vector3(0.050, 0.008, 0.014), -28.0, mat)
			_add_enemy_part(root, Vector3(0.040, 0.012, 0.004), Vector3(0.050, 0.008, 0.014), 28.0, mat)
			_add_enemy_part(root, Vector3(0.0, 0.052, -0.004), Vector3(0.026, 0.022, 0.014), 0.0, trim)
			_add_enemy_part(root, Vector3(0.0, 0.042, 0.038), Vector3(0.014, 0.030, 0.044), 0.0, mat)
		"weaver":
			_add_enemy_part(root, Vector3(0.0, 0.000, 0.006), Vector3(0.020, 0.052, 0.016), 0.0, core)
			_add_enemy_part(root, Vector3(-0.060, -0.002, 0.004), Vector3(0.082, 0.007, 0.012), 10.0, mat)
			_add_enemy_part(root, Vector3(0.060, -0.002, 0.004), Vector3(0.082, 0.007, 0.012), -10.0, mat)
			_add_enemy_part(root, Vector3(0.0, -0.030, 0.018), Vector3(0.030, 0.014, 0.010), 0.0, trim)
			_add_enemy_part(root, Vector3(0.0, 0.034, -0.004), Vector3(0.034, 0.018, 0.014), 0.0, mat)
			_add_enemy_part(root, Vector3(0.0, 0.030, 0.028), Vector3(0.010, 0.018, 0.032), 0.0, trim)
		"bomber":
			_add_enemy_part(root, Vector3(0.0, 0.000, 0.010), Vector3(0.055, 0.075, 0.026), 0.0, core)
			_add_enemy_part(root, Vector3(-0.078, -0.004, 0.006), Vector3(0.095, 0.017, 0.020), 16.0, mat)
			_add_enemy_part(root, Vector3(0.078, -0.004, 0.006), Vector3(0.095, 0.017, 0.020), -16.0, mat)
			_add_enemy_part(root, Vector3(0.0, -0.046, 0.026), Vector3(0.046, 0.022, 0.016), 0.0, trim)
			_add_enemy_part(root, Vector3(-0.025, 0.048, -0.004), Vector3(0.022, 0.025, 0.014), 0.0, mat)
			_add_enemy_part(root, Vector3(0.025, 0.048, -0.004), Vector3(0.022, 0.025, 0.014), 0.0, mat)
			_add_enemy_part(root, Vector3(0.0, 0.034, 0.044), Vector3(0.016, 0.032, 0.046), 0.0, trim)
		"saucer":
			_add_enemy_part(root, Vector3(0.0, 0.000, 0.004), Vector3(0.118, 0.060, 0.018), 0.0, mat)
			_add_enemy_part(root, Vector3(0.0, 0.000, 0.026), Vector3(0.052, 0.038, 0.028), 0.0, core)
			_add_enemy_part(root, Vector3(-0.072, 0.000, 0.014), Vector3(0.026, 0.026, 0.014), 0.0, trim)
			_add_enemy_part(root, Vector3(0.072, 0.000, 0.014), Vector3(0.026, 0.026, 0.014), 0.0, trim)
			_add_enemy_part(root, Vector3(0.0, -0.050, 0.012), Vector3(0.046, 0.012, 0.014), 0.0, trim)
			_add_enemy_part(root, Vector3(0.0, 0.050, 0.012), Vector3(0.046, 0.012, 0.014), 0.0, trim)
		"asteroid":
			_add_enemy_part(root, Vector3(0.000, 0.000, 0.012), Vector3(0.070, 0.065, 0.055), 11.0, mat)
			_add_enemy_part(root, Vector3(-0.040, 0.022, 0.036), Vector3(0.042, 0.050, 0.038), -18.0, core)
			_add_enemy_part(root, Vector3(0.045, -0.018, 0.030), Vector3(0.052, 0.040, 0.046), 26.0, mat)
			_add_enemy_part(root, Vector3(-0.010, -0.046, 0.052), Vector3(0.040, 0.030, 0.032), 8.0, trim)
			_add_enemy_part(root, Vector3(0.020, 0.038, -0.004), Vector3(0.034, 0.036, 0.026), -31.0, core)
		_:
			_add_enemy_part(root, Vector3(0.0, 0.000, 0.006), Vector3(0.026, 0.058, 0.018), 0.0, mat)
			_add_enemy_part(root, Vector3(0.0, 0.032, -0.002), Vector3(0.020, 0.020, 0.014), 0.0, core)
			_add_enemy_part(root, Vector3(-0.036, -0.002, 0.004), Vector3(0.048, 0.009, 0.014), 22.0, mat)
			_add_enemy_part(root, Vector3(0.036, -0.002, 0.004), Vector3(0.048, 0.009, 0.014), -22.0, mat)
			_add_enemy_part(root, Vector3(0.0, -0.030, 0.020), Vector3(0.024, 0.012, 0.010), 0.0, trim)
			_add_enemy_part(root, Vector3(0.0, 0.030, 0.032), Vector3(0.012, 0.018, 0.034), 0.0, trim)

func _update_sphere_enemy_motion(n: Node3D, lat: float, lon: float, lane: float) -> Vector2:
	var age := int(n.get_meta("age", 0)) + 1
	n.set_meta("age", age)
	var mode := String(n.get_meta("mode", "hunter"))
	match mode:
		"surface_boss":
			var desired_lon := clampf(GameState.px * 0.07, -0.26, 0.26)
			lane = lerpf(lane, clampf(desired_lon - lon, -0.22, 0.22), 0.014)
			lon += lane * 0.0018 + sin(float(age) * 0.025) * 0.0010
			lat -= 0.0016
			if lat < 0.18:
				lat = 0.18 + 0.045 * sin(float(age) * 0.018)
		"formation":
			lat -= 0.0032
			lon += lane * 0.0024 + sin(float(age) * 0.055) * 0.0010
		"swooper":
			lat -= 0.0030
			lon += lane * 0.0048 + sin(float(age) * 0.085) * 0.0032
			if age > 86:
				lat += 0.0042
		"missile":
			var desired_lon := clampf(GameState.px * 0.11, -0.52, 0.52)
			lane = lerpf(lane, clampf(desired_lon - lon, -0.8, 0.8), 0.024)
			lon += lane * 0.0036
			lat -= 0.0034 if age < 120 else -0.0060
		"turret":
			lat -= 0.0021
			lon += sin(float(age) * 0.018 + lon * 3.0) * 0.0008
		"rammer":
			var desired_lon := clampf(GameState.px * 0.12, -0.54, 0.54)
			lane = lerpf(lane, clampf(desired_lon - lon, -1.0, 1.0), 0.038)
			lon += lane * 0.0042
			lat -= 0.0052 + clampf(float(age - 35) * 0.00004, 0.0, 0.004)
		"weaver":
			lat -= 0.0035
			lon += lane * 0.0035 + sin(float(age) * 0.12) * 0.0046
		"bomber":
			var desired_lon := clampf(GameState.px * 0.09, -0.42, 0.42)
			lane = lerpf(lane, clampf(desired_lon - lon, -0.55, 0.55), 0.014)
			lon += lane * 0.0018 + sin(float(age) * 0.032) * 0.0012
			lat -= 0.0019
		"saucer":
			var desired_lon := clampf(GameState.px * 0.10, -0.48, 0.48)
			lane = lerpf(lane, clampf(desired_lon - lon, -0.70, 0.70), 0.020)
			lon += lane * 0.0025 + sin(float(age) * 0.070) * 0.0036
			lat -= 0.0024 + sin(float(age) * 0.045) * 0.0007
			n.rotation_degrees.z = sin(float(age) * 0.085) * 10.0
		"asteroid":
			lon += lane * 0.0016 + sin(float(age) * 0.034 + lon) * 0.0010
			lat -= 0.0038 + clampf(float(age - 45) * 0.00003, 0.0, 0.0024)
			n.rotation_degrees.x += 1.8
			n.rotation_degrees.y += 1.1
			n.rotation_degrees.z += 2.4
		"amoeba":
			# A tanky roadblock: descends SLOWLY (so it lingers on screen far longer than
			# the rabble), eases toward the player's longitude and wanders left/right at
			# random. Same proven lat/lon model as the other enemies, so it reliably frames
			# in. It exits normally at the bottom (no off-screen hovering tricks).
			var ph := float(n.get_meta("phase", 0.0))
			var desired_lon := clampf(GameState.px * 0.09, -0.5, 0.5)
			var wcd := int(n.get_meta("wlon_cd", 0)) - 1
			if wcd <= 0:
				n.set_meta("wlon", clampf(desired_lon + randf_range(-0.40, 0.40), -0.55, 0.55))
				wcd = randi_range(60, 130)
			n.set_meta("wlon_cd", wcd)
			var wlon := float(n.get_meta("wlon", desired_lon))
			lane = lerpf(lane, clampf(wlon - lon, -0.5, 0.5), 0.02)
			lon += lane * 0.0024 + sin(float(age) * 0.04 + ph) * 0.0016
			lat -= 0.0012   # slow creep down (rabble uses 0.002–0.005 → amoeba lingers ~2-3x)
			_wriggle_amoeba(n, age)
		_:
			var desired_lon := clampf(GameState.px * 0.11, -0.52, 0.52)
			lane = lerpf(lane, clampf(desired_lon - lon, -0.9, 0.9), 0.018)
			lat -= 0.0029 + clampf((0.38 - lat) * 0.0010, 0.0, 0.0015)
			lon += lane * 0.0036 + sin(float(_surface_frames) * 0.045 + lat * 5.0) * 0.0010
	n.set_meta("lane", lane)
	return Vector2(lat, lon)

func _update_sphere_enemy_fire(n: Node3D) -> void:
	var cd := int(n.get_meta("fire_cd", 60)) - 1
	if cd > 0:
		n.set_meta("fire_cd", cd)
		return
	var mode := String(n.get_meta("mode", "hunter"))
	if mode in ["swooper", "rammer", "weaver", "asteroid", "amoeba"]:
		n.set_meta("fire_cd", 999)
		return
	n.set_meta("fire_cd", (22 + randi() % 18) if mode == "surface_boss" \
		else ((26 + randi() % 22) if mode == "turret" \
		else ((38 + randi() % 26) if mode == "bomber" \
		else ((32 + randi() % 24) if mode == "saucer" \
		else int(56.0 - 18.0 * GameState.difficulty()) + randi() % 34))))
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var sp := camera.unproject_position(n.global_position)
	if sp.x < -80.0 or sp.x > get_viewport().get_visible_rect().size.x + 80.0:
		return
	if sp.y < -80.0 or sp.y > get_viewport().get_visible_rect().size.y + 120.0:
		return
	var from := n.global_position
	var to := Vector3(GameState.px, GameState.py, GameState.alt_to_z(GameState.alt))
	var dir := to - from
	dir.z = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3(0.0, -1.0, 0.0)
	var spd := 0.030 * (1.0 + 0.35 * GameState.difficulty())
	if mode == "surface_boss":
		for off in [-0.22, -0.11, 0.0, 0.11, 0.22]:
			var ang: float = atan2(dir.y, dir.x) + float(off)
			_spawn_sphere_enemy_bullet(from, Vector3(cos(ang), sin(ang), 0.0) * (spd * 0.92))
	elif mode == "turret":
		for off in [-0.08, 0.08]:
			var ang: float = atan2(dir.y, dir.x) + float(off)
			_spawn_sphere_enemy_bullet(from, Vector3(cos(ang), sin(ang), 0.0) * (spd * 0.95))
	elif mode == "bomber":
		for off in [-0.22, 0.0, 0.22]:
			var ang: float = atan2(dir.y, dir.x) + float(off)
			_spawn_sphere_enemy_bullet(from, Vector3(cos(ang), sin(ang), 0.0) * (spd * 0.82))
	elif mode == "saucer":
		for off in [-0.16, 0.16]:
			var ang: float = atan2(dir.y, dir.x) + float(off + sin(float(_surface_frames) * 0.06) * 0.08)
			_spawn_sphere_enemy_bullet(from, Vector3(cos(ang), sin(ang), 0.0) * (spd * 0.88))
	elif mode == "formation":
		_spawn_sphere_enemy_bullet(from, dir.normalized() * (spd * 0.92))
	elif mode == "missile":
		for off in [-0.11, 0.0, 0.11]:
			var ang: float = atan2(dir.y, dir.x) + float(off)
			_spawn_sphere_enemy_bullet(from, Vector3(cos(ang), sin(ang), 0.0) * (spd * 1.16))
	else:
		_spawn_sphere_enemy_bullet(from, dir.normalized() * spd)

func _spawn_sphere_enemy_bullet(from: Vector3, vel: Vector3) -> void:
	if get_tree().get_nodes_in_group("enemy_bullets").size() >= 42:
		return
	var b := EnemyBullet.new()
	b.velocity = vel
	b.alt = GameState.alt / GameState.ALT_MAX
	b.position = from
	get_tree().current_scene.add_child(b)

# A big, tanky amoeba: a lumpy glowing blob ringed with oozing pseudopods (squirmed each
# frame by _wriggle_amoeba). Bigger than the rabble, in one of the AMOEBA_COLORS.
func _build_amoeba_body(root: Node3D, col: Color) -> void:
	var body := _enemy_material(col * 0.5, col, 1.7)
	body.roughness = 0.18      # wet, slimy sheen
	body.metallic = 0.1
	var blob := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.06
	sph.height = 0.12
	sph.radial_segments = 9    # low-poly = organic/lumpy
	sph.rings = 6
	blob.mesh = sph
	blob.material_override = body
	root.add_child(blob)
	root.set_meta("blob", blob)
	var pods := []
	var n := 5
	for i in n:
		var a := float(i) / float(n) * TAU + randf() * 0.5
		var pod := MeshInstance3D.new()
		var ps := SphereMesh.new()
		ps.radius = 0.029
		ps.height = 0.058
		ps.radial_segments = 7
		ps.rings = 5
		pod.mesh = ps
		pod.material_override = body
		var dir := Vector3(cos(a), sin(a), 0.0)
		pod.position = dir * 0.06
		root.add_child(pod)
		pods.append({"node": pod, "base": dir * 0.06, "phase": randf() * TAU})
	root.set_meta("pods", pods)

# Pulse the amoeba body unevenly and ooze its pseudopods in/out (child transforms — the
# root's own placement/scale on the sphere is untouched).
func _wriggle_amoeba(n: Node3D, age: int) -> void:
	var t := float(age) * 0.12
	var phase := float(n.get_meta("phase", 0.0))
	# Hit reaction: a quick decaying jiggle + emission flash so bullets clearly LAND.
	var hit := int(n.get_meta("hit", 0))
	var punch := 0.0
	if hit > 0:
		n.set_meta("hit", hit - 1)
		punch = float(hit) / 9.0                       # 1 → 0 over the reaction
		punch *= absf(sin(float(hit) * 1.7))           # ぶりぶり wobble while it decays
	var blob := n.get_meta("blob", null) as MeshInstance3D
	if blob != null:
		var swell := 1.0 + 0.5 * punch                 # squish bigger on impact
		blob.scale = Vector3(
			(1.0 + 0.30 * sin(t + phase)) * swell,
			(1.0 + 0.30 * sin(t + phase + 2.1)) * swell,
			(1.0 + 0.24 * sin(t * 0.8 + phase + 4.2)) * swell)
		var bm := blob.material_override as StandardMaterial3D
		if bm != null:
			bm.emission_energy_multiplier = 1.7 + 3.4 * punch   # white-hot flash on hit
	var pods: Array = n.get_meta("pods", [])
	for pd: Dictionary in pods:
		var node := pd["node"] as MeshInstance3D
		if is_instance_valid(node):
			var ext: float = 0.7 + 0.55 * (0.5 + 0.5 * sin(t * 0.9 + float(pd["phase"])))
			node.position = (pd["base"] as Vector3) * (ext + 0.5 * punch)   # pods recoil out

func _add_enemy_part(root: Node3D, pos: Vector3, sc: Vector3, rz: float,
		mat: Material) -> void:
	var part := MeshInstance3D.new()
	part.mesh = _enemy_mesh
	part.material_override = mat
	part.position = pos
	part.scale = sc
	part.rotation_degrees.z = rz
	root.add_child(part)

func _spawn_sphere_repair() -> void:
	var root := Node3D.new()
	var lon := randf_range(-0.55, 0.55)
	var lat := randf_range(0.48, 0.82)
	root.set_meta("kind", "repair")
	root.set_meta("lat", lat)
	root.set_meta("lon", lon)
	root.set_meta("lane", randf_range(-0.5, 0.5))
	_surface_actor_root.add_child(root)
	for axis in 2:
		var part := MeshInstance3D.new()
		part.mesh = _enemy_mesh
		part.material_override = _repair_mat
		part.scale = Vector3(0.075, 0.022, 0.026)
		part.rotation_degrees.z = 90.0 if axis == 1 else 0.0
		root.add_child(part)
	root.scale = Vector3.ONE * 0.20
	_place_sphere_actor(root, lat, lon, 0.046)

func _sphere_repair_collects(n: Node3D) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var item_sp := camera.unproject_position(n.global_position)
	var ship_sp := camera.unproject_position(Vector3(GameState.px, GameState.py,
		GameState.alt_to_z(GameState.alt)))
	var kind := String(n.get_meta("kind", "repair"))
	if kind == "rescue_signal" or kind == "vip":
		var lat := float(n.get_meta("lat", 0.0))
		var vp := get_viewport().get_visible_rect().size
		if lat > 0.36 or item_sp.y < vp.y * 0.28:
			return false
		return item_sp.distance_to(ship_sp) < 82.0
	var radius := 86.0
	return item_sp.distance_to(ship_sp) < radius

func _collect_sphere_repair(n: Node3D) -> void:
	for i in 5:
		if (i + 1) in GameState.collected_units:
			GameState.unit_life[i] = minf(GameState.life_cap(), GameState.unit_life[i] + 18.0)
	var ex := Explosion.new()
	ex.color = Color(0.25, 1.0, 0.48)
	ex.count = 10
	ex.strength = 0.72
	get_tree().current_scene.add_child(ex)
	ex.global_position = n.global_position
	n.queue_free()

func _spawn_rescue_signal() -> void:
	if _surface_actor_root == null or _rescue_spawned:
		return
	_rescue_spawned = true
	var root := Node3D.new()
	root.set_meta("kind", "rescue_signal")
	root.set_meta("lat", randf_range(1.04, 1.10))
	root.set_meta("lon", randf_range(-0.22, 0.22))
	root.set_meta("lane", randf_range(-0.08, 0.08))
	_surface_actor_root.add_child(root)
	_build_rescue_signal_body(root)
	_place_sphere_actor(root, float(root.get_meta("lat")), float(root.get_meta("lon")), 0.070)
	get_tree().call_group("star_hud", "show_message",
		"RESCUE SIGNAL DETECTED", "INTERCEPT THE CYAN BEACON")

func _build_rescue_signal_body(root: Node3D) -> void:
	for axis in 2:
		var part := MeshInstance3D.new()
		part.mesh = _enemy_mesh
		part.material_override = _rescue_mat
		part.scale = Vector3(0.090, 0.018, 0.024)
		part.rotation_degrees.z = 90.0 if axis == 1 else 0.0
		root.add_child(part)
	var core := MeshInstance3D.new()
	core.mesh = _enemy_mesh
	core.material_override = _vip_mat
	core.scale = Vector3(0.035, 0.035, 0.035)
	root.add_child(core)

func _spawn_vip() -> void:
	if _surface_actor_root == null or _vip_spawned:
		return
	_vip_spawned = true
	var root := Node3D.new()
	root.set_meta("kind", "vip")
	root.set_meta("lat", randf_range(1.04, 1.10))
	root.set_meta("lon", randf_range(-0.18, 0.18))
	root.set_meta("lane", randf_range(-0.07, 0.07))
	_surface_actor_root.add_child(root)
	for i in 3:
		var part := MeshInstance3D.new()
		part.mesh = _enemy_mesh
		part.material_override = _vip_mat
		part.position = Vector3((float(i) - 1.0) * 0.032, 0.0, 0.0)
		part.scale = Vector3(0.030, 0.030, 0.052)
		root.add_child(part)
	_place_sphere_actor(root, float(root.get_meta("lat")), float(root.get_meta("lon")), 0.070)
	get_tree().call_group("star_hud", "show_message",
		"VIP TRANSPONDER LOCKED", "RESCUE THE GOLD UNIT")

func _collect_rescue_actor(n: Node3D, kind: String) -> void:
	var gp := n.global_position
	n.queue_free()
	var ex := Explosion.new()
	ex.color = Color(0.35, 1.0, 0.95) if kind == "rescue_signal" else Color(1.0, 0.86, 0.25)
	ex.count = 18
	ex.strength = 1.0
	get_tree().current_scene.add_child(ex)
	ex.global_position = gp
	if kind == "rescue_signal":
		_spawn_vip()
		return
	GameState.score += 2500
	GameState.add_exp(120)
	_mark_planet_cleared("VIP RESCUED", "CLIMB TO SPACE - STAR WILL VANISH")

func _update_surface_gate_spawns() -> void:
	if GameState.suppress_genesis_progression():
		return
	var has_key_gate := false
	var has_boss_gate := false
	for c in _surface_actor_root.get_children():
		var n := c as Node3D
		if n == null or not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		var kind := String(n.get_meta("kind", ""))
		has_key_gate = has_key_gate or kind == "key_gate"
		has_boss_gate = has_boss_gate or kind == "boss_gate"
	if _key_gate_count >= 3:
		if not has_boss_gate:
			_spawn_surface_gate(true)
		return
	_gate_timer -= 1
	if _gate_timer <= 0 and not has_key_gate:
		_gate_timer = 230 + randi() % 180
		_spawn_surface_gate(false)

func _spawn_surface_gate(boss_gate: bool) -> void:
	if GameState.suppress_genesis_progression():
		return
	var root := Node3D.new()
	root.set_meta("kind", "boss_gate" if boss_gate else "key_gate")
	root.set_meta("lat", randf_range(0.58, 0.82))
	root.set_meta("lon", randf_range(-0.38, 0.38))
	root.set_meta("lane", randf_range(-0.35, 0.35))
	_surface_actor_root.add_child(root)
	_build_surface_gate_body(root, boss_gate)
	_place_sphere_actor(root, float(root.get_meta("lat")), float(root.get_meta("lon")), 0.086)
	get_tree().call_group("star_hud", "show_message",
		"BOSS GATE OPEN" if boss_gate else "KEY GATE APPROACHING",
		"ENTER THE GATE" if boss_gate else Loc.pair("ゲート %d / 3", "GATE %d / 3") % [_key_gate_count + 1])

func _build_surface_gate_body(root: Node3D, boss_gate: bool) -> void:
	var mat := _boss_gate_mat if boss_gate else _gate_mat
	var half_w := 0.30 if boss_gate else 0.24
	var height := 0.48 if boss_gate else 0.40
	var block := 0.056 if boss_gate else 0.048
	var depth := 0.052 if boss_gate else 0.044
	# Local Z is the surface normal. Build the frame in XZ so it stands upright
	# from the spherical ground, leaving a clear opening to fly through.
	var rows := 7 if boss_gate else 6
	for side in [-1.0, 1.0]:
		for i in rows:
			_add_gate_block(root, Vector3(side * half_w, 0.0, block * 0.5 + float(i) * block),
				Vector3(block, depth, block), mat)
	var top_cols := 7 if boss_gate else 6
	for i in top_cols:
		var u := (float(i) / float(top_cols - 1)) * 2.0 - 1.0
		_add_gate_block(root, Vector3(u * half_w, 0.0, height),
			Vector3(block * 1.05, depth, block), mat)
	for side in [-1.0, 1.0]:
		_add_gate_block(root, Vector3(side * half_w, 0.0, -block * 0.20),
			Vector3(block * 1.5, depth * 1.1, block * 0.65), mat)

func _add_gate_block(root: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var part := MeshInstance3D.new()
	part.mesh = _enemy_mesh
	part.material_override = mat
	part.position = pos
	part.scale = size
	root.add_child(part)

func _sphere_gate_collects(n: Node3D) -> bool:
	var lat := float(n.get_meta("lat", 0.0))
	return lat <= -0.58

func _collect_surface_gate(n: Node3D, kind: String) -> void:
	n.queue_free()
	if kind == "boss_gate":
		var main := get_tree().current_scene
		if main != null and main.has_method("enter_arena") and not GameState.arena_active:
			main.call_deferred("enter_arena")
		return
	_key_gate_count = mini(3, _key_gate_count + 1)
	get_tree().call_group("star_hud", "show_message",
		Loc.pair("キーゲート %d / 3", "KEY GATE %d / 3") % [_key_gate_count],
		"BOSS GATE UNLOCKING" if _key_gate_count >= 3 else "KEEP DIVING")

func _place_sphere_actor(root: Node3D, lat: float, lon: float, lift: float) -> void:
	var n := Vector3(sin(lon) * cos(lat), sin(lat), cos(lon) * cos(lat)).normalized()
	var right := Vector3.UP.cross(n)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := n.cross(right).normalized()
	root.transform = Transform3D(Basis(right, up, n), n * (SURFACE_RADIUS + lift))
	if String(root.get_meta("kind", "")) == "enemy":
		var mode := String(root.get_meta("mode", ""))
		var age := float(root.get_meta("age", 0))
		if mode == "asteroid":
			root.rotate_object_local(Vector3.RIGHT, age * 0.030)
			root.rotate_object_local(Vector3.UP, age * 0.021)
			root.rotate_object_local(Vector3.FORWARD, age * 0.044)
		elif mode == "saucer":
			root.rotate_object_local(Vector3.FORWARD, sin(age * 0.085) * 0.18)
		elif mode == "amoeba":
			root.rotate_object_local(Vector3.FORWARD, age * 0.010)   # slow ominous swirl

func _actor_surface_lift(kind: String, mode: String = "") -> float:
	if kind == "repair":
		return 0.046
	if kind == "enemy" and mode == "turret":
		return 0.0
	if kind == "enemy" and mode == "surface_boss":
		return 0.12
	if kind == "enemy" and mode == "amoeba":
		return 0.10   # bigger body sits a touch higher off the surface
	return 0.078

func _finish_surface_exit() -> void:
	var vanish_on_exit := GameState.cleared_stars.has(star_name)
	_surface_mode = false
	remove_from_group("planet_terrain")
	if _world_env != null and is_instance_valid(_world_env):
		_world_env.queue_free()
	_world_env = null
	if _surface_root != null:
		_surface_root.visible = true
	if _surface_actor_root != null:
		_surface_actor_root.visible = not vanish_on_exit
		if vanish_on_exit:
			for c in _surface_actor_root.get_children():
				c.queue_free()
	if _atmosphere != null:
		_atmosphere.visible = true
	if _light != null and is_instance_valid(_light):
		_light.light_energy = _saved_light_energy
		_light.light_color = _saved_light_color
		_light.transform = _saved_light_tf
		_light.shadow_enabled = _saved_light_shadow
	GameState.stage = "space"
	GameState.planet_name = ""
	GameState.planet_biome = ""
	GameState.planet_type = "boss"
	GameState.surface_festival_planet = false
	GameState.planet_has_underground = false
	GameState.star_kind = ""
	GameState.underground = false
	GameState.over_hole = false
	GameState.descent_gauge = 0.0
	GameState.exit_hold = 0.0
	GameState.entry_glow = 0.0
	GameState.planet_camera_exit = 0.0
	# Leaving a planet means crossing back through the orbital boundary, not
	# warping to the top of space. Keep the sphere large at ALT900; normal
	# altitude-driven space logic will shrink it as the player climbs away.
	GameState.alt = GameState.GROUND_ALT
	GameState.tAlt = GameState.GROUND_ALT
	approach = 1.0
	scale = Vector3.ONE * SURFACE_SCALE
	var camera := get_viewport().get_camera_3d()
	var cx := camera.global_position.x if camera != null else 0.0
	global_position = Vector3(cx, SURFACE_CENTER_Y, BG_Z)
	_update_atmosphere_alpha(1.0)
	# Normal climb-out keeps enemies/bullets alive so they flow back into space (no
	# pop at the boundary, and the star's enemies fade out via the approach ramp).
	# A CLEARED star collapses, so wipe the field for that finale only.
	if vanish_on_exit:
		for grp in ["enemies", "enemy_bullets", "bullets"]:
			for n in get_tree().get_nodes_in_group(grp):
				if n != self:
					n.queue_free()
		_begin_collapse_in_space()
		get_tree().call_group("star_hud", "show_message",
			Loc.pair("%s クリア", "%s CLEARED") % star_name, "CLIMB AWAY - STAR COLLAPSING")
		return
	var main := get_tree().current_scene
	if main != null:
		main.set("_mothership_timer", 1800)
	get_tree().call_group("star_hud", "show_message", "LOW ORBIT",
		Loc.pair("ALT%d - 上昇離脱", "ALT%d - CLIMB AWAY") % int(GameState.GROUND_ALT))

func _finish_exit(_seamless: bool = true) -> void:
	_finish_surface_exit()

func begin_exit(_msg: String = "", _sub: String = "", _seamless: bool = true) -> void:
	_finish_surface_exit()

func _begin_collapse_in_space() -> void:
	_collapse_active = true
	_collapse_t = 0
	_surface_mode = false
	# Stop being an entry target the instant we start collapsing: otherwise the
	# space altitude logic (Unit1._apply_altitude) sees approach=1.0 and keeps
	# re-entering this dying star, pinning alt at 760 and resetting the collapse so
	# the ship can never climb away ("mineで爆発させたら高度移動できない").
	remove_from_group("target_planet")
	remove_from_group("planet_terrain")
	approach = 1.0
	_surface_root.visible = true
	if _surface_actor_root != null:
		_surface_actor_root.visible = false
	if _atmosphere != null:
		_atmosphere.visible = true
	var col := _collapse_color()
	if _atmosphere_mat != null:
		_atmosphere_mat.albedo_color = Color(col.r, col.g, col.b, 0.18)
		_atmosphere_mat.emission = col
		_atmosphere_mat.emission_energy_multiplier = 0.65
	_spawn_collapse_burst(2.4, 46)

func _run_collapse_space() -> void:
	_collapse_t += 1
	var near_t := clampf((GameState.ALT_MAX - GameState.alt) \
		/ (GameState.ALT_MAX - GameState.GROUND_ALT), 0.0, 1.0)
	var life_t := clampf(float(_collapse_t) / 190.0, 0.0, 1.0)
	var camera := get_viewport().get_camera_3d()
	var cx := camera.global_position.x if camera != null else 0.0
	global_position = Vector3(lerpf(global_position.x, cx, 0.08),
		lerpf(global_position.y, SURFACE_CENTER_Y, 0.06), BG_Z)
	var base_s := lerpf(0.65, SURFACE_SCALE, smoothstep(0.0, 1.0, near_t))
	var pulse := 1.0 + 0.08 * sin(float(_collapse_t) * 0.55)
	var crumble := lerpf(1.0, 0.08, life_t)
	scale = Vector3.ONE * base_s * pulse * crumble
	if _surface_roll_root != null:
		_surface_roll_root.rotation_degrees.y += 0.34
	_surface_root.rotation_degrees.x += 0.42
	if _ball != null:
		_ball.rotation_degrees.x = _surface_root.rotation_degrees.x
		_ball.rotation_degrees.y = _surface_roll_root.rotation_degrees.y if _surface_roll_root != null else 0.0
	if _atmosphere != null:
		_atmosphere.rotation_degrees.x = _surface_root.rotation_degrees.x
		_atmosphere.rotation_degrees.y = _surface_roll_root.rotation_degrees.y if _surface_roll_root != null else 0.0
	if _atmosphere_mat != null:
		var col := _collapse_color()
		var a := lerpf(0.22, 0.0, life_t)
		_atmosphere_mat.albedo_color = Color(col.r, col.g, col.b, a)
		_atmosphere_mat.emission_energy_multiplier = lerpf(1.2, 0.0, life_t)
	if _collapse_t % 14 == 0:
		_spawn_collapse_burst(lerpf(1.8, 0.6, life_t), 18)
	if _collapse_t > 210 or (GameState.alt > GameState.ALT_MAX - 6.0 and _collapse_t > 70):
		dispose_immediate()

func _spawn_collapse_burst(strength: float, count: int) -> void:
	var ex := Explosion.new()
	ex.color = _collapse_color()
	ex.count = count
	ex.strength = strength
	get_tree().current_scene.add_child(ex)
	ex.global_position = global_position

func _collapse_color() -> Color:
	if star_type == "mine":
		return Color(1.0, 0.78, 0.18)
	if star_type == "rescue":
		return Color(0.35, 1.0, 0.95)
	return Color(1.0, 0.45, 0.18)

# Mining damage scales with the combined ship: more units = blocks break faster.
func _mining_damage() -> int:
	return 1 + int((GameState.formation_count - 1) * 0.5)   # 1u=1, 3u=2, 5u=3

func try_block_hit(p: Vector3, dmg: int = -1) -> Dictionary:
	var actor_hit := _screen_actor_at(p, 112.0)
	if not actor_hit.is_empty():
		return actor_hit
	var idx := _screen_block_at(p, 138.0)
	if idx < 0:
		return {}
	# One shot chips ONE block (no instant cluster wipe); damage scales with units.
	return _damage_surface_block_at(idx, dmg if dmg > 0 else _mining_damage())

# Break the block under a world point (tighter radius) and spawn its FX + drops here.
# Used by the formation special attacks (missiles / blades / bombs) to mine too.
func mine_at(p: Vector3, dmg: int = -1) -> bool:
	var idx := _screen_block_at(p, 78.0)
	if idx < 0:
		return false
	var hit := _damage_surface_block_at(idx, dmg if dmg > 0 else _mining_damage())
	if hit.is_empty():
		return false
	_apply_mine_fx(hit)
	return true

# World position of the nearest surface block to p (for Unit3 missiles to lock onto
# blocks when there's no enemy). Returns Vector3.INF when there are no blocks.
func nearest_block_world(p: Vector3) -> Vector3:
	if _surface_mmi == null or _surface_blocks.is_empty():
		return Vector3.INF
	var xf := _surface_mmi.global_transform
	var best := Vector3.INF
	var best_d := 1.0e20
	for i in _surface_blocks.size():
		var wp: Vector3 = xf * (_surface_blocks[i]["xf"] as Transform3D).origin
		var d := wp.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = wp
	return best

func _apply_mine_fx(hit: Dictionary) -> void:
	var sc := get_tree().current_scene
	if sc == null:
		return
	var ex := Explosion.new()
	ex.color = hit.get("color", Color(0.8, 0.85, 0.9))
	ex.count = int(hit.get("effect_count", 8))
	ex.strength = float(hit.get("effect_strength", 0.6))
	sc.add_child(ex)
	ex.global_position = hit["pos"]
	if hit.get("chip", false):
		TsgAudio.block_chip()
	else:
		TsgAudio.block_break()
	if not hit.get("no_drop", false):
		ResourceItem.spawn(sc, hit)
	for d: Dictionary in hit.get("drops", []):
		ResourceItem.spawn(sc, d)

func _screen_actor_at(p: Vector3, radius_px: float) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _surface_actor_root == null:
		return {}
	var sp := camera.unproject_position(p)
	var sz := get_viewport().get_visible_rect().size
	var acenter := _surface_actor_root.global_transform.origin
	var to_cam := camera.global_position - acenter
	for c in _surface_actor_root.get_children():
		var node := c as Node3D
		if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if String(node.get_meta("kind", "")) != "enemy":
			continue
		# Skip the far hemisphere (behind the planet) — same reason as _screen_block_at.
		if (node.global_position - acenter).dot(to_cam) <= 0.0:
			continue
		var mode := String(node.get_meta("mode", "hunter"))
		var ap := camera.unproject_position(node.global_position)
		# Off-screen actors can't be shot either (an enemy that scrolled past the bottom
		# horizon but isn't despawned yet) — this was the "bullets hit nothing" bug.
		if ap.x < -40.0 or ap.x > sz.x + 40.0 or ap.y < -40.0 or ap.y > sz.y + 40.0:
			continue
		# Amoebas use a TIGHT, size-matched hit radius (only bullets that actually overlap
		# the blob are blocked) — the flat radius_px is far too wide for a big body and
		# would swallow shots that never touched it.
		var r_px := radius_px
		if mode == "amoeba":
			var world_r := 0.11 * node.scale.x
			var edge := node.global_position + camera.global_transform.basis.x * world_r
			r_px = maxf(ap.distance_to(camera.unproject_position(edge)), 14.0)
		if ap.distance_to(sp) <= r_px:
			var hp := int(node.get_meta("hp", 1)) - 1
			var col := _sphere_enemy_color(mode)
			if mode == "amoeba":
				col = node.get_meta("amoeba_col", col)
			if hp > 0:
				node.set_meta("hp", hp)
				node.scale *= 1.08
				if mode == "amoeba":
					node.set_meta("hit", 9)   # squish + flash reaction (see _wriggle_amoeba)
				return {
					"res": "",
					"color": col.lightened(0.18),
					"pos": node.global_position,
					"no_drop": true,
					"effect_count": 16,
					"effect_strength": 0.95,
				}
			var gp := node.global_position
			node.queue_free()
			if mode == "surface_boss":
				GameState.score += 3500
				GameState.add_exp(160)
				_mark_planet_cleared("SURFACE BOSS DESTROYED", "CLIMB TO SPACE - STAR WILL VANISH")
			elif mode == "amoeba":
				GameState.score += 300
				GameState.add_exp(70)
			else:
				GameState.score += 80
				GameState.add_exp(20)
			GameState.on_enemy_killed()   # feeds the 慢心 gauge
			var rare := true if mode == "surface_boss" \
				else randf() < (0.42 if mode == "amoeba" else 0.18)
			return {
				"res": "RARE" if rare else "ORE",
				"color": Color(1.0, 0.82, 0.2) if rare else col,
				"pos": gp,
				"rare": rare,
				"effect_count": 54 if mode == "surface_boss" else 36,
				"effect_strength": 2.7 if mode == "surface_boss" else 1.9,
			}
	return {}

func _sphere_enemy_color(mode: String) -> Color:
	match mode:
		"surface_boss":
			return Color(1.0, 0.25, 0.12)
		"formation":
			return Color(0.25, 0.78, 1.0)
		"swooper":
			return Color(1.0, 0.48, 0.12)
		"missile":
			return Color(1.0, 0.86, 0.18)
		_:
			return Color(1.0, 0.16, 0.58)

func blast(p: Vector3, radius: float, dmg: int = -1) -> Array:
	var drops: Array = []
	var camera := get_viewport().get_camera_3d()
	if camera == null or _surface_mmi == null:
		return drops
	var sp := camera.unproject_position(p)
	var hit_px := clampf(radius * 115.0, 72.0, 180.0)
	var xf := _surface_mmi.global_transform
	var center := xf.origin
	var to_cam := camera.global_position - center
	var victims: Array[int] = []
	for i in _surface_blocks.size():
		var wp: Vector3 = xf * (_surface_blocks[i]["xf"] as Transform3D).origin
		if (wp - center).dot(to_cam) <= 0.0:
			continue   # far hemisphere — behind the planet
		if camera.unproject_position(wp).distance_to(sp) <= hit_px:
			victims.append(i)
			if victims.size() >= 10:
				break
	# Remove highest index first so swap-remove never invalidates a pending victim.
	victims.sort()
	victims.reverse()
	# Ground/area blasts hit harder than bullets but still respect block hp, so a single
	# blast chips a patch rather than vaporising it. Only broken blocks drop.
	var bd := dmg if dmg > 0 else (_mining_damage() + 1)
	for i in victims:
		var drop := _damage_surface_block_at(i, bd)
		if not drop.is_empty() and not drop.get("no_drop", false):
			drops.append(drop)
	return drops

func _break_surface_cluster(primary_idx: int) -> Dictionary:
	var first := _break_surface_block_at(primary_idx)
	if first.is_empty():
		return {}
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return first
	var center_sp := camera.unproject_position(first["pos"])
	var xf := _surface_mmi.global_transform
	var victims: Array[int] = []
	for i in _surface_blocks.size():
		var wp: Vector3 = xf * (_surface_blocks[i]["xf"] as Transform3D).origin
		if camera.unproject_position(wp).distance_to(center_sp) <= 145.0:
			victims.append(i)
			if victims.size() >= 9:
				break
	# Remove highest index first so swap-remove never invalidates a pending victim.
	victims.sort()
	victims.reverse()
	var extra_drops: Array[Dictionary] = []
	for i in victims:
		var drop := _break_surface_block_at(i)
		if not drop.is_empty():
			extra_drops.append(drop)
	first["drops"] = extra_drops
	first["effect_count"] = 42
	first["effect_strength"] = 2.0
	return first

# Project every surface block to the screen ONCE for the current frame (parallel to
# _surface_blocks). Back-hemisphere blocks (behind the planet) get INF so they never match —
# same near-hemisphere rule as before (the "弾が伸びない" fix). Reused by every bullet this frame.
func _rebuild_block_screen_cache(camera: Camera3D) -> void:
	var n := _surface_blocks.size()
	_blk_sp.resize(n)
	var xf := _surface_mmi.global_transform
	var center := xf.origin
	var to_cam := camera.global_position - center
	for i in n:
		var wp: Vector3 = xf * (_surface_blocks[i]["xf"] as Transform3D).origin
		if (wp - center).dot(to_cam) <= 0.0:
			_blk_sp[i] = Vector2(INF, INF)   # behind the planet
		else:
			_blk_sp[i] = camera.unproject_position(wp)
	_blk_sp_frame = Engine.get_process_frames()

func _screen_block_at(p: Vector3, radius_px: float) -> int:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _surface_mmi == null:
		return -1
	# Build the per-frame screen-position cache on the first call of the frame (or after the
	# block count changed via append / swap-remove). Every later bullet this frame reuses it.
	if _blk_sp_frame != Engine.get_process_frames() or _blk_sp.size() != _surface_blocks.size():
		_rebuild_block_screen_cache(camera)
	var sp := camera.unproject_position(p)
	var best := -1
	var best_d2 := radius_px * radius_px
	for i in _blk_sp.size():
		var bsp := _blk_sp[i]
		if bsp.x == INF:
			continue   # behind the planet
		var d2 := bsp.distance_squared_to(sp)
		if d2 < best_d2:
			best_d2 = d2
			best = i
	return best

# Per-block durability: enough that even a full 5-unit ship (mining damage 3) needs a
# couple of hits per block — a little resistance stays — and a lone Unit1 chips through
# over several shots. Tougher deeper into the run.
func _block_hp() -> int:
	return 6 + (randi() % 3) + int(clampf(GameState.difficulty(), 0.0, 1.0) * 3.0)

# Picks a block MATERIAL: rgb = base tint, ALPHA = material id (0 stone, 1 dirt, 2 grass,
# 3 ore, 4 gold, 5 silver) encoded as (id+0.5)/8 so surface_block.gdshader can switch look.
func _pick_block_material(rng: RandomNumberGenerator) -> Color:
	var r := rng.randf()
	var id := 0
	var c := Color(0.50, 0.52, 0.56)              # stone
	if r < 0.32:
		id = 0; c = Color(0.50, 0.52, 0.56)       # stone
	elif r < 0.56:
		id = 1; c = Color(0.46, 0.34, 0.22)       # dirt
	elif r < 0.72:
		id = 2; c = Color(0.26, 0.50, 0.26)       # grass
	elif r < 0.86:
		id = 3; c = Color(0.32, 0.36, 0.42)       # ore (dark host rock, mineral specks)
	elif r < 0.94:
		id = 4; c = Color(1.0, 0.80, 0.26)        # gold
	else:
		id = 5; c = Color(0.80, 0.83, 0.88)       # silver
	c.a = (float(id) + 0.5) / 8.0
	return c

# Some stars hide a ROUTE PLATE in one of their blocks (others are resource-only). Mining
# that block reveals it → arms the true gate (or the BOSS panel at ROUTE4). Deterministic
# per star via the surface-seed rng. (Replaces the KEY_J debug for real play.)
const PLATE_CHANCE := 0.28
const PLATE_HP := 30        # the plate block is a TOUGH special block — slow to crack open
func _seed_route_plate(rng: RandomNumberGenerator) -> void:
	_surface_total = _surface_blocks.size()
	if GameState.suppress_genesis_progression():
		return
	if _surface_blocks.is_empty() or rng.randf() >= PLATE_CHANCE:
		return
	var idx := rng.randi() % _surface_blocks.size()
	_surface_blocks[idx]["plate"] = true
	# Much higher durability so it survives incidental/area fire and must be deliberately
	# dug out — slows down how fast a plate is revealed within a star.
	_surface_blocks[idx]["hp"] = PLATE_HP
	_surface_blocks[idx]["maxhp"] = PLATE_HP
	_has_plate = true

# Damage one block. Chips it (darkens, no drop) until hp runs out, then breaks + drops.
func _damage_surface_block_at(i: int, dmg: int) -> Dictionary:
	if i < 0 or i >= _surface_blocks.size():
		return {}
	var rec: Dictionary = _surface_blocks[i]
	var hp := int(rec.get("hp", 1)) - dmg
	if hp <= 0:
		return _break_surface_block_at(i)
	rec["hp"] = hp
	# Wear: darken the instance toward a cracked look as it loses hp.
	var base: Color = rec.get("base", rec.get("color", Color(0.7, 0.75, 0.8)))
	var maxhp: float = maxf(1.0, float(rec.get("maxhp", 1)))
	var worn := base.lerp(base.darkened(0.55), 1.0 - float(hp) / maxhp)
	rec["color"] = worn
	if _surface_mm != null and i < _surface_mm.instance_count:
		_surface_mm.set_instance_color(i, worn)
	return {
		"res": "",
		"no_drop": true,
		"chip": true,
		"color": Color(base.r, base.g, base.b).lightened(0.25),
		"pos": _surface_mmi.global_transform * (rec["xf"] as Transform3D).origin,
		"effect_count": 7,
		"effect_strength": 0.5,
	}

func _break_surface_block_at(i: int) -> Dictionary:
	if i < 0 or i >= _surface_blocks.size():
		return {}
	var rec: Dictionary = _surface_blocks[i]
	var col: Color = rec.get("color", Color(0.7, 0.75, 0.8))
	var gp: Vector3 = _surface_mmi.global_transform * (rec["xf"] as Transform3D).origin
	var is_plate: bool = rec.get("plate", false)
	_remove_surface_instance(i)
	_surface_blocks_broken += 1
	var rare_chance := 0.34 if star_type == "mine" else 0.12
	var rare := randf() < rare_chance
	if star_type == "mine" and _surface_blocks.is_empty():
		_mark_planet_cleared("MINE STAR DEPLETED", "CLIMB TO SPACE - STAR WILL VANISH")
	elif star_type != "mine":
		_spawn_horizon_surface_block()
	# A ROUTE PLATE was buried in this block: reveal it (big centre-screen plate + SE).
	if is_plate and not GameState.suppress_genesis_progression():
		_has_plate = false
		_plate_found_here = true
		# Unlock the gate choice (BOSS if the route's already complete, else the next ROUTE)
		# and summon the gate at once. The choice stays open until the route gate is taken.
		GameState.arm_route_gate()
		GameState.plate_announce_num = 0 if GameState.route_complete() else GameState.route_number() + 1
		GameState.plate_announce_t = 180
		# The reveal is a 3D golden MONOLITH that flies from this block to screen-centre and
		# frames the message on its face (replaces the old flat HUD banner).
		var plate := RoutePlate.new()
		plate.setup(gp, GameState.plate_announce_num <= 0, GameState.plate_announce_num)
		get_parent().add_child(plate)
		TsgAudio.route_plate_sfx()
		return {
			"res": "", "no_drop": true, "color": Color(0.45, 1.0, 0.65), "pos": gp,
			"effect_count": 52, "effect_strength": 2.8,
		}
	# Dug a real crater (≈12% of the star, ~150 blocks on a typical ~1240-block star) with
	# no plate → closure: move on. Well above incidental digging so it needs real effort.
	if not _has_plate and not _plate_found_here and not _giveup_announced \
			and _surface_total > 0 \
			and _surface_blocks_broken >= maxi(120, int(_surface_total * 0.12)):
		_giveup_announced = true
		get_tree().call_group("star_hud", "show_message",
			"NO ROUTE PLATE HERE", "THIS STAR IS RESOURCES ONLY - MOVE ON")
	var drop_col := Color(col.r, col.g, col.b)   # drop the tint opaque (alpha holds matid)
	return {
		"res": "RARE" if rare else ("GOLD" if star_type == "mine" else "ORE"),
		"color": Color(1.0, 0.82, 0.2) if rare else drop_col,
		"pos": gp,
		"rare": rare,
		"effect_count": 30 if rare else 24,
		"effect_strength": 1.75 if rare else 1.35,
	}

func _mark_planet_cleared(title: String, sub: String) -> void:
	if _planet_clear_announced:
		return
	_planet_clear_announced = true
	GameState.cleared_stars[star_name] = true
	get_tree().call_group("star_hud", "show_message", title, sub)

func collides(x: float, y: float, z: float, r: float) -> bool:
	if star_type != "rescue" or _rescue_obstacles.is_empty():
		return false
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var psp := camera.unproject_position(Vector3(x, y, z))
	var screen_size := get_viewport().get_visible_rect().size
	for rec in _rescue_obstacles:
		var node := rec.get("node") as Node3D
		if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var osp := camera.unproject_position(node.global_position)
		if osp.x < -80.0 or osp.x > screen_size.x + 80.0 \
				or osp.y < -80.0 or osp.y > screen_size.y + 80.0:
			continue
		var radius := float(rec.get("radius", 44.0)) + r * 260.0
		if osp.distance_to(psp) <= radius:
			return true
	return false

func has_block(_x: float, _y: float, _radius: float) -> bool:
	return true

func open_hole_at(_x: float, _y: float) -> void:
	pass

func reveal_oopart_near(_x: float, _y: float, _radius: float, _z: float) -> void:
	pass

func restore_boss_area_to_normal() -> void:
	pass
