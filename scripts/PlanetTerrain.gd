class_name PlanetTerrain
extends Node3D

const ENEMY_SCENE := preload("res://scenes/units/Enemy.tscn")

# Minecraft-style voxel planet surface. The world is columns of 3D blocks
# (block size B): each column carries a stack of block types generated
# deterministically from the planet seed — region noise mixes local biomes
# (forest, mountains, rivers, seas, deserts, snow, canyons, cities,
# fortresses, lava fields...) inside the planet's theme, so endless varied
# planets come from one integer. Chunks of 80x4 columns scroll down at
# constant world speed and are freed below the screen; the camera's
# altitude-driven z position provides the zoom/parallax for free.
#
# Blocks protruding above the ALT0 plane (z = -2) can be destroyed by player
# bullets — the top block pops off and may drop a collectable resource
# (see ResourceItem / Main._check_collisions).
#
# Also owns the way home: hold the top of the screen at ALT99 to climb out
# of the atmosphere and return to space.

# --- Block registry ----------------------------------------------------------

enum {AIR, GRASS, DIRT, STONE, SAND, SNOW, ICE, WOOD, LEAF,
	CITY, NEON, FORT, CRYSTAL, ROCK, CLOUD, ROAD, GLASS, OOPART_BLOCK, OOPART_FOUND_BLOCK,
	BOSS_BLOCK,
	# Underground-only emissive accents (glow:true → unshaded, so they read as
	# bright landmarks against the dark cavern regardless of cave-light reach).
	UG_CRYSTAL, UG_MAGMA, UG_ALGAE, UG_EMBER, UG_GLYPH, UG_NEON, OBSIDIAN}

const BLOCK_DEFS := {
	GRASS:   {"c": Color(0.22, 0.45, 0.13), "glow": false, "res": "BIO"},
	DIRT:    {"c": Color(0.35, 0.24, 0.13), "glow": false, "res": "SOIL"},
	STONE:   {"c": Color(0.45, 0.45, 0.47), "glow": false, "res": "ORE"},
	SAND:    {"c": Color(0.76, 0.66, 0.40), "glow": false, "res": "SILICA"},
	SNOW:    {"c": Color(0.92, 0.95, 1.0),  "glow": false, "res": "ICE"},
	ICE:     {"c": Color(0.60, 0.78, 0.92), "glow": false, "res": "ICE"},
	WOOD:    {"c": Color(0.38, 0.26, 0.12), "glow": false, "res": "WOOD"},
	LEAF:    {"c": Color(0.13, 0.35, 0.10), "glow": false, "res": "BIO"},
	CITY:    {"c": Color(0.40, 0.44, 0.52), "glow": false, "res": "METAL"},
	NEON:    {"c": Color(0.15, 0.95, 1.0),  "glow": false, "res": "TECH"},
	FORT:    {"c": Color(0.25, 0.24, 0.28), "glow": false, "res": "METAL"},
	CRYSTAL: {"c": Color(0.55, 0.85, 1.0),  "glow": false, "res": "CRYSTAL"},
	ROCK:    {"c": Color(0.16, 0.12, 0.11), "glow": false, "res": "ORE"},
	CLOUD:   {"c": Color(0.85, 0.75, 0.58), "glow": false, "res": "GAS"},
	ROAD:    {"c": Color(0.17, 0.17, 0.19), "glow": false, "res": "SILICA"},
	GLASS:   {"c": Color(0.46, 0.56, 0.68), "glow": false, "res": "METAL"},
	OOPART_BLOCK: {"c": Color(0.25, 1.0, 0.92), "glow": false, "res": "TECH"},
	OOPART_FOUND_BLOCK: {"c": Color(1.0, 0.78, 0.22), "glow": false, "res": "TECH"},
	BOSS_BLOCK: {"c": Color(0.38, 0.11, 0.18), "glow": false, "res": "TECH"},
	UG_CRYSTAL: {"c": Color(0.40, 0.90, 1.00), "glow": true, "res": "CRYSTAL"},
	UG_MAGMA:   {"c": Color(1.00, 0.42, 0.10), "glow": true, "res": "ORE"},
	UG_ALGAE:   {"c": Color(0.28, 1.00, 0.66), "glow": true, "res": "BIO"},
	UG_EMBER:   {"c": Color(0.95, 0.18, 0.10), "glow": true, "res": "ORE"},
	UG_GLYPH:   {"c": Color(1.00, 0.65, 0.22), "glow": true, "res": "TECH"},
	UG_NEON:    {"c": Color(0.26, 1.00, 0.95), "glow": true, "res": "TECH"},
	OBSIDIAN:   {"c": Color(0.05, 0.05, 0.09), "glow": false, "res": "ORE"},  # glossy black (diamond arena)
}

# --- Planet themes ------------------------------------------------------------
# label/sky/accent/high are read by StarTargets / TargetPlanet / Background.
# regions: [kind, weight] mix of local biomes; water_level in blocks.

const BIOMES := {
	"VERDANT": {
		"label": "VERDANT WORLD", "sky": Color(0.30, 0.50, 0.70),
		"accent": Color(0.10, 0.30, 0.55), "high": Color(0.20, 0.40, 0.14),
		"regions": [["forest", 3.0], ["plains", 2.5], ["mountain", 2.0],
			["river", 1.5], ["sea", 1.0], ["fortress", 0.5]],
		"water_level": 2, "water_glow": 0.3, "water_alpha": 0.8, "clouds": true,
	},
	"OCEAN": {
		"label": "OCEAN WORLD", "sky": Color(0.30, 0.55, 0.75),
		"accent": Color(0.06, 0.26, 0.50), "high": Color(0.25, 0.45, 0.60),
		"regions": [["sea", 6.0], ["plains", 1.3], ["forest", 0.7], ["mountain", 0.6]],
		"water_level": 2, "water_glow": 0.35, "water_alpha": 0.8, "clouds": true,
	},
	"DESERT": {
		"label": "DESERT WORLD", "sky": Color(0.65, 0.50, 0.35),
		"accent": Color(0.20, 0.40, 0.45), "high": Color(0.62, 0.48, 0.22),
		"regions": [["desert", 5.0], ["canyon", 2.0], ["mountain", 1.0],
			["fortress", 0.7], ["sea", 0.3]],
		"water_level": 2, "water_glow": 0.3, "water_alpha": 0.85, "clouds": false,
	},
	"ICE": {
		"label": "FROZEN WORLD", "sky": Color(0.55, 0.70, 0.85),
		"accent": Color(0.40, 0.70, 0.95), "high": Color(0.80, 0.88, 0.96),
		"regions": [["snow", 4.0], ["mountain", 2.5], ["ice", 2.0], ["crystal", 1.5]],
		"water_level": 0, "water_glow": 0.0, "water_alpha": 1.0, "clouds": false,
	},
	"VOLCANIC": {
		"label": "VOLCANIC WORLD", "sky": Color(0.32, 0.16, 0.12),
		"accent": Color(1.0, 0.36, 0.04), "high": Color(0.24, 0.17, 0.14),
		"regions": [["lava", 3.0], ["mountain", 2.5], ["canyon", 1.5]],
		"water_level": 2, "water_glow": 2.4, "water_alpha": 0.95, "clouds": false,
	},
	"GAS": {
		"label": "GAS GIANT", "sky": Color(0.60, 0.45, 0.25),
		"accent": Color(0.90, 0.75, 0.50), "high": Color(0.78, 0.62, 0.38),
		"regions": [["cloud", 1.0]],
		"water_level": 0, "water_glow": 0.0, "water_alpha": 1.0, "clouds": true,
	},
	"CYBER": {
		"label": "CYBER CITY", "sky": Color(0.10, 0.12, 0.22),
		"accent": Color(0.10, 0.85, 1.0), "high": Color(0.13, 0.15, 0.22),
		"regions": [["city", 4.0], ["fortress", 1.5], ["sea", 1.2], ["canyon", 0.6]],
		"water_level": 2, "water_glow": 2.0, "water_alpha": 0.9, "clouds": false,
	},
	# --- DARK WORLDS (2026-06-26) -------------------------------------------------
	# Surface stars used to roll only the bright biomes above, so every landing was a
	# dazzling sunlit world. These are deliberately DIM: a feeble/absent sun ("dim": true
	# drives the dark lighting in _setup_atmosphere), a near-black palette, and light that
	# comes from the planet ITSELF — bioluminescent crystals (the "sparkle" colour drives
	# the emissive decor + ground glints) and the organic, shimmering water_surface pools.
	# They appear in the click-star catalogue automatically (non-abyss / non-boss).
	"BARREN": {
		"label": "BARREN WASTES", "sky": Color(0.13, 0.12, 0.14),
		"accent": Color(0.34, 0.40, 0.50), "high": Color(0.22, 0.18, 0.16),
		"regions": [["canyon", 3.0], ["mountain", 3.0], ["crystal", 1.0], ["sea", 0.4]],
		"water_level": 1, "water_glow": 0.7, "water_alpha": 0.85, "clouds": false,
		"dim": true, "dim_sun": 0.24, "sparkle": Color(0.62, 0.72, 0.88),
	},
	"EMBER": {
		"label": "DYING STAR", "sky": Color(0.12, 0.05, 0.05),
		"accent": Color(1.0, 0.36, 0.10), "high": Color(0.18, 0.10, 0.09),
		"regions": [["canyon", 3.0], ["mountain", 2.5], ["lava", 1.5], ["crystal", 0.6]],
		"water_level": 2, "water_glow": 2.2, "water_alpha": 0.95, "clouds": false,
		"dim": true, "dim_sun": 0.16, "sparkle": Color(1.0, 0.55, 0.18),
	},
	"DARKGAS": {
		"label": "VEILED GAS GIANT", "sky": Color(0.10, 0.06, 0.16),
		"accent": Color(0.58, 0.32, 0.98), "high": Color(0.22, 0.13, 0.32),
		"regions": [["cloud", 1.0]],
		"water_level": 0, "water_glow": 0.0, "water_alpha": 1.0, "clouds": true,
		"dim": true, "dim_sun": 0.26, "sparkle": Color(0.66, 0.92, 1.0),
	},
	"TUNDRA": {
		"label": "FROZEN DARK", "sky": Color(0.06, 0.10, 0.18),
		"accent": Color(0.32, 0.86, 0.96), "high": Color(0.30, 0.40, 0.55),
		"regions": [["ice", 3.0], ["crystal", 2.5], ["snow", 2.0], ["mountain", 1.5]],
		"water_level": 1, "water_glow": 1.3, "water_alpha": 0.8, "clouds": false,
		"dim": true, "dim_sun": 0.22, "sparkle": Color(0.55, 0.92, 1.0),
	},
	"VOID": {
		"label": "FORGOTTEN WORLD", "sky": Color(0.03, 0.04, 0.06),
		"accent": Color(0.26, 0.96, 0.76), "high": Color(0.09, 0.10, 0.13),
		"regions": [["crystal", 3.0], ["mountain", 2.5], ["canyon", 2.0], ["sea", 0.8]],
		"water_level": 2, "water_glow": 1.7, "water_alpha": 0.85, "clouds": false,
		"dim": true, "dim_sun": 0.10, "sparkle": Color(0.36, 1.0, 0.80),
	},
	# --- Abyss interiors (underground zones behind abyss gates; "abyss": true
	# keeps them out of the star catalogue and routes the climb-out back to
	# the surface instead of space) ---
	"CAVE": {
		"label": "DEEP CAVERN", "sky": Color(0.09, 0.07, 0.05),
		"accent": Color(0.10, 0.30, 0.45), "high": Color(0.30, 0.26, 0.22),
		"regions": [["mountain", 3.0], ["canyon", 2.5], ["crystal", 2.0], ["sea", 0.5]],
		"water_level": 2, "water_glow": 0.5, "water_alpha": 0.85, "clouds": false,
		"abyss": true,
	},
	"BASE": {
		"label": "ENEMY UNDERBASE", "sky": Color(0.05, 0.07, 0.13),
		"accent": Color(0.10, 0.85, 1.0), "high": Color(0.14, 0.16, 0.24),
		"regions": [["city", 3.5], ["fortress", 2.5], ["sea", 1.0], ["canyon", 0.5]],
		"water_level": 2, "water_glow": 2.0, "water_alpha": 0.9, "clouds": false,
		"abyss": true,
	},
	"TEMPLE": {
		"label": "SACRED TEMPLE", "sky": Color(0.20, 0.15, 0.08),
		"accent": Color(1.0, 0.82, 0.30), "high": Color(0.55, 0.45, 0.25),
		"regions": [["desert", 3.0], ["fortress", 2.5], ["crystal", 1.5], ["sea", 0.8]],
		"water_level": 2, "water_glow": 1.2, "water_alpha": 0.9, "clouds": false,
		"abyss": true,
	},
	"LAVACAVE": {
		"label": "MOLTEN DEPTHS", "sky": Color(0.16, 0.06, 0.04),
		"accent": Color(1.0, 0.36, 0.05), "high": Color(0.22, 0.14, 0.11),
		"regions": [["lava", 4.0], ["mountain", 2.0], ["canyon", 1.5]],
		"water_level": 2, "water_glow": 2.6, "water_alpha": 0.95, "clouds": false,
		"abyss": true,
	},
	# --- The boss star (appears in space once the campaign requirements are met) ---
	"BOSS": {
		"label": "OMEGA CORE", "sky": Color(0.13, 0.04, 0.06),
		"accent": Color(1.0, 0.20, 0.15), "high": Color(0.30, 0.10, 0.12),
		"regions": [["fortress", 3.0], ["city", 2.0], ["lava", 1.5], ["canyon", 1.0]],
		"water_level": 2, "water_glow": 2.2, "water_alpha": 0.95, "clouds": false,
		"boss": true,
	},
}

# --- World constants -----------------------------------------------------------

const B        := 0.2    # block size (world units)
const WIDTH    := 20.0   # wider than the view: the camera pans ±2.4 with the player
const COLS_X   := 100    # WIDTH / B
const ROWS_Y   := 4      # blocks per chunk in y
const ROW_H    := 0.8    # ROWS_Y * B
const MAX_H    := 7      # cap surface stack height; lower max block count keeps
						 # terrain-heavy planets closer to 60fps.
const ROAD_H   := 3      # road deck height (bridges ride over the water line)
const GROUND_Z := -2.45  # column base; ALT0 player flies at z = -2
const ALT0_Z   := -2.0   # blocks topping above this are destructible
# --- Single continuous voxel column (alt0 floor → crust → sky relief) ---
# Each column is NZ vertical cells on a fixed z grid: z(iz) = CELL_Z0 + iz*B.
# iz IZ_SURF maps to GROUND_Z, so surface-relief level L lives at cell IZ_SURF+L
# (unchanged surface look). iz 0..IZ_SURF-1 is the DEEP UNDERGROUND band (floor +
# pillars). iz==IZ_SURF..IZ_SURF+1 is the solid CRUST (alt900). Above = sky relief.
const NZ       := 117
const CELL_Z0  := -22.45 # z of iz=0 (alt0 floor); CELL_Z0 + IZ_SURF*B == GROUND_Z
const IZ_SURF  := 100
const IZ_CRUST := 100    # the crust block sits at the surface-relief base (alt900 layer)
const SCROLL   := 0.012  # constant world speed; turrets ride the same rate
const MAX_REBUILDS_PER_FRAME := 1  # cap dirty-chunk remeshes/frame (see _process)
const SPAWN_Y  := 11.0   # spawn far ahead so the streaming edge stays off-screen even at
const KILL_Y   := -11.0  # the top of the arena band (where the camera sees a wide y-range)

const EXIT_HOLD_FRAMES := 90   # frames holding ALT99 + top of screen to commit
const EXIT_FRAMES      := 130  # climb-out sequence length

var biome_id: String = "VERDANT"
var seed_v: int = 1

var _b: Dictionary
var _chunks: Array[Dictionary] = []  # {node, mi, cells: Array[PackedByteArray], water, breakable, dirty, idx}
var _next_row: int = 0
var _scrolled: float = 0.0
var _enemy_front_nodes: Dictionary = {}
var _exit_hold: int = 0
var _exit_t: int = -1                # -1 idle, >= 0 climbing out
var _surface_frames: int = 0

var _r_kinds: Array[String] = []
var _r_cum: Array[float] = []
var _r_total: float = 0.0
var _rscale: float = 0.055       # region noise frequency (per planet)
var _dens: float = 1.0           # structure density multiplier (per planet)
var _river_w: float = 0.0        # river band half-width (0 = dry planet)
var _cloud_chance: float = 0.0
var _surface_structure_theme: int = 0
var _underground_structure_theme: int = 0
var _decor_blocks: Array = []

# GERWALK relic hunt: a relic occasionally drops from a blasted block, throttled by frame.
var _next_relic_frame: int = 0
# No relic for the first stretch of the arena — the player must dig IN and explore first; surfacing
# one in the opening seconds breaks the hunt (you'd bank it before the dig even begins).
const RELIC_FIRST_DELAY := 1100   # frames of digging before the FIRST star relic can drop
# The sealed wall the relic hunt unlocks: a thick, breakable barrier band across the arena,
# with an open cavern cleared just beyond it (where the dormant survivor lies).
const ARENA_WALL_DEPTH := 5.5     # world-y thickness of the wall — a real bore, but not a slog
const ARENA_WALL_HEIGHT := 44     # voxel height (iz) of the wall plane
const ARENA_CAVERN_LEN := 10.0    # open clearing beyond the wall

var _light: DirectionalLight3D
var _saved_light_energy: float = 1.0
var _saved_light_color: Color = Color.WHITE
var _saved_light_tf: Transform3D
var _saved_light_shadow: bool = true

var _palette: Dictionary = {}    # block id → per-planet tinted color
var _hue_shift: float = 0.0
var _jitter_amp: float = 0.16
var _checker: float = 0.0

# Breakable crust: the surface is mostly UNBREAKABLE; only rare, organically
# shaped clusters of columns can be destroyed, and tearing one open is the only
# way down into the underground. Patches come from low-frequency value noise over
# absolute block coords, so a cluster spans chunk seams naturally. They are NOT
# visually marked — you discover them by attacking the ground. Surface only;
# the underground layer is fully breakable (handled in try_block_hit/blast).
const BREAK_FREQ   := 0.045   # cluster noise frequency (lower = bigger patches)
const BREAK_THRESH := 0.74    # higher = rarer / smaller breakable patches
# The alt900 crust = the bottom blocks at/below the deck plane (ALT0_Z). On a
# normal surface column these are UNBREAKABLE (the floor that gates descent);
# everything stacked above is ordinary breakable relief. A breakable cluster
# clears its crust too, opening a hole down to the underground.
const CRUST_KEEP := int((ALT0_Z - GROUND_Z) / B)   # = 2 blocks (z -2.45..-2.05)
var _abyss_enabled: bool = true   # true on a normal surface (not an abyss/boss biome)
var _has_underground: bool = true
var _arena_phase: float = 0.0     # boss-arena: random per-entry phase → a different snake
var _surface_festival: bool = false
var _quiet_surface: bool = false

var _relief: float = 1.0         # per-planet vertical drama (peaks & canyon depth)
var _roads_on: bool = false      # block road/bridge grid across the surface
var _underground_kind_id: String = "cave"
var _decor: Dictionary = {}      # shared decoration meshes & materials

var _ground_mat: StandardMaterial3D
var _glow_mat: Material   # StandardMaterial3D normally; a ShaderMaterial (vox_glow) in the diamond arena
var _water_mat: ShaderMaterial
var _cloud_mat: StandardMaterial3D
var _cloud_mesh: SphereMesh

func _ready() -> void:
	add_to_group("planet_terrain")
	_b = BIOMES.get(biome_id, BIOMES["VERDANT"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var surface_world: bool = not (bool(_b.get("abyss", false)) or bool(_b.get("boss", false)))
	# Underground/cave geometry only ever builds for the boss ARENA (a swapped-in
	# voxel terrain on a "boss" biome). The normal seamless surface is a TargetPlanet
	# sphere and never instantiates this class — so live play stays untouched.
	_has_underground = GameState.arena_active and bool(_b.get("boss", false))
	if _has_underground:
		_arena_phase = rng.randf() * 1000.0   # seeded by seed_v → random arena each entry
	_surface_festival = surface_world
	_quiet_surface = false
	GameState.planet_has_underground = _has_underground
	GameState.surface_festival_planet = _surface_festival
	GameState.star_kind = ""
	_abyss_enabled = false
	_underground_kind_id = _pick_underground_kind(rng)
	GameState.underground_boss_area = _has_underground
	GameState.underground_ooparts = 0
	GameState.underground_boss_unlocked = false
	GameState.underground_boss_defeated = false
	GameState.underground_oopart_found_keys = {}
	# Fresh GERWALK relic-hunt state every arena entry.
	GameState.arena_relics_found = 0
	GameState.arena_wall_armed = false
	GameState.arena_wall_y = 0.0
	GameState.arena_survivor_spawned = false
	GameState.arena_survivor_greeted = false
	_next_relic_frame = GameState.frame + RELIC_FIRST_DELAY   # gate the first relic behind real digging
	GameState.underground_base_biome = _enemy_theme_for_underground(_underground_kind_id)
	GameState.underground_biome = GameState.underground_base_biome

	# Region mix is reshuffled per planet so no two worlds repeat the same
	# spread — and sometimes a planet is a "mono" world of a single material.
	var regions: Array = _b["regions"]
	if rng.randf() < 0.15:
		var pick: Array = regions[rng.randi() % regions.size()]
		_r_kinds.append(pick[0])
		_r_cum.append(1.0)
		_r_total = 1.0
	else:
		for r: Array in regions:
			var w := float(r[1]) * rng.randf_range(0.35, 1.8)
			_r_total += w
			_r_kinds.append(r[0])
			_r_cum.append(_r_total)
	_rscale = rng.randf_range(0.035, 0.085)
	_dens = rng.randf_range(0.75, 1.25) * (0.45 if _quiet_surface else (1.22 if _surface_festival else 1.0))
	_surface_structure_theme = rng.randi() % 8
	_underground_structure_theme = rng.randi() % 7
	if int(_b["water_level"]) > 0 and rng.randf() < 0.75:
		_river_w = rng.randf_range(0.03, 0.06)  # winding rivers (lava rivers on VOLCANIC)
	_cloud_chance = 0.0

	# Per-planet surface texture: every block color is re-tinted from the seed
	# (hue/saturation/value drift), with its own noise amplitude and an
	# optional faint checker — no two worlds share the exact same look.
	_hue_shift = rng.randf_range(-0.10, 0.10)
	var sat_m := rng.randf_range(0.75, 1.3)
	var val_m := rng.randf_range(0.85, 1.12)
	for bid: int in BLOCK_DEFS:
		var c: Color = BLOCK_DEFS[bid]["c"]
		# Emissive accents (and the boss block) keep their raw vivid color so the
		# per-planet hue/value drift can't desaturate the underground landmarks.
		if BLOCK_DEFS[bid]["glow"]:
			_palette[bid] = c
		else:
			_palette[bid] = Color.from_hsv(fposmod(c.h + _hue_shift, 1.0),
				clampf(c.s * sat_m, 0.0, 1.0), clampf(c.v * val_m, 0.05, 1.0))
	_jitter_amp = rng.randf_range(0.08, 0.28)
	_checker = rng.randf_range(0.0, 0.07)
	# Vertical drama: some worlds are gentle, some are all peaks and chasms.
	_relief = rng.randf_range(0.85, 1.25) * (1.20 if _surface_festival else 1.0) \
		* (0.62 if _quiet_surface else 1.0)
	_roads_on = biome_id != "GAS" and rng.randf() < (0.12 if _quiet_surface else 0.88)

	_make_materials()
	_make_decor()
	_setup_atmosphere(rng)
	while _row_top_y() < SPAWN_Y:
		_spawn_chunk()

# Per-planet sunlight and air: a blazing sun means hard block shadows and low
# ambient fill; a dim one goes flat and shadowless. Depth fog in the sky color
# hazes the ground when flying high (the camera backs away with altitude) and
# thickens on gas giants. Everything restores itself when the planet is left.
func _setup_atmosphere(rng: RandomNumberGenerator) -> void:
	var sky: Color = _b["sky"]
	# Sunlight: surface worlds lean BRIGHT — 35% are brilliant clear days with
	# a blazing star overhead, and the rest are biased sunny; only the abyss
	# interiors stay in the dark.
	# Golden-walk arena reads as a dark click-star: force the dim (own-glow) lighting model
	# regardless of the underlying BOSS biome.
	var diamond_arena := GameState.golden_walk and GameState.arena_active
	var dim := bool(_b.get("dim", false)) or diamond_arena
	var sun: float
	var clear_day := false
	if _b.get("abyss", false):
		sun = rng.randf_range(0.05, 0.35)
	elif dim:
		# Dark worlds: a feeble or dead star. The world is lit mostly by its OWN glow
		# (crystals, embers, auroras) rather than a sun overhead. dim_sun caps how much
		# starlight reaches it (VOID ~ pitch dark, BARREN a faint dusk).
		sun = rng.randf_range(0.0, float(_b.get("dim_sun", 0.2)))
	elif rng.randf() < 0.35:
		clear_day = true
		sun = rng.randf_range(0.85, 1.0)
	else:
		sun = 1.0 - pow(rng.randf(), 1.6)
	_light = get_tree().current_scene.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if _light != null:
		_saved_light_energy = _light.light_energy
		_saved_light_color = _light.light_color
		_saved_light_tf = _light.transform
		_saved_light_shadow = _light.shadow_enabled
		_light.light_energy = lerpf(0.55, 1.0, sun)
		# Dark worlds skew to a cold, moody starlight; sunny worlds stay mostly warm.
		var warm := rng.randf() < (0.15 if dim else 0.6)
		var hue := rng.randf_range(0.04, 0.12) if warm else rng.randf_range(0.55, 0.66)
		_light.light_color = Color.from_hsv(hue, rng.randf_range(0.05, 0.3), 1.0)
		# Each planet has its own sun position: shadows fall at a different
		# angle every landing (low evening suns throw long shadows).
		_light.rotation_degrees = Vector3(
			rng.randf_range(-62.0, -34.0), rng.randf_range(-50.0, 50.0), 0.0)
		# Dynamic shadows over thousands of voxel faces are one of the biggest
		# surface-stage costs. Keep the sunlight, but make block shading cheap.
		_light.shadow_enabled = false
		if diamond_arena:
			# Faint, cool diamond starlight — low energy so the player ship is never over-lit
			# (the white-flare came from a bright BOSS-biome sun); the diamonds light the scene.
			_light.shadow_enabled = true
			_light.light_energy = 0.50
			_light.light_color = Color(0.68, 0.76, 1.0)
			_light.rotation_degrees = Vector3(-52.0, -28.0, 0.0)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(sky.r * 0.15, sky.g * 0.15, sky.b * 0.15)
	env.fog_enabled = true
	env.fog_light_color = sky if not clear_day else sky.lightened(0.3)
	var fog := rng.randf_range(0.02, 0.04) if clear_day else rng.randf_range(0.035, 0.065)
	if _b.get("abyss", false):
		fog *= 1.6  # heavy underground air
	if biome_id == "GAS" or biome_id == "DARKGAS":
		fog *= 1.8  # soupy gas-giant atmosphere
	if dim:
		fog *= 1.4  # thick, fantastical murk that the planet's own glow bleeds into
	env.fog_density = fog
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = sky
	# Dark worlds get a low flat fill so silhouettes stay readable but the scene stays
	# genuinely dark — the emissive crystals / pools provide the actual sparkle.
	env.ambient_light_energy = 0.26 if dim else lerpf(0.6, 0.28, sun)
	# Keep emissive colours, but skip Bloom/Glow post-processing on terrain-heavy
	# stages. It varies a lot by biome (neon/crystal/lava) and causes uneven FPS.
	env.glow_enabled = false
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_intensity = 0.0
	env.glow_bloom = 0.0
	if diamond_arena:
		# AGX tonemapping rolls highlights off smoothly → kills the player-ship white-flare.
		# (Background/ambient/glow are owned per-frame by Main._update_atmosphere, which is where
		# the rich diamond bloom grade lives; tonemap is set here once and persists.)
		env.tonemap_mode = Environment.TONE_MAPPER_AGX
		env.tonemap_exposure = 0.98
	var we := WorldEnvironment.new()
	we.environment = env
	we.add_to_group("world_env")  # Main blends it toward the underground sky by depth
	add_child(we)  # freed with the terrain → space stays crystal clear

func _exit_tree() -> void:
	if _light != null and is_instance_valid(_light):
		_light.light_energy = _saved_light_energy
		_light.light_color = _saved_light_color
		_light.transform = _saved_light_tf
		_light.shadow_enabled = _saved_light_shadow

func _process(_delta: float) -> void:
	_surface_frames += 1
	if _exit_t >= 0:
		_run_exit()
	if _surface_frames > 150 and _exit_t < 0 and not GameState.in_transition() \
			and not GameState.arrive_lock and not GameState.on_carrier \
			and GameState.entry_intro <= 0 and not GameState.underground \
			and GameState.alt >= GameState.ALT_MAX - 0.5:
		begin_exit("", "", true)
		return
	if (GameState.frame & 31) == 0:
		_prune_decor_blocks()

	var spd := SCROLL
	if GameState.golden_walk and GameState.arena_active:
		spd = GameState.golden_arena_scroll.y
	elif GameState.star_exit:
		spd *= 3.0  # the surface falls away as the ship climbs
	_scrolled += spd
	# Mesh rebuilds are the dominant CPU cost (a full ~400-column remesh, ~20ms
	# each). When many blocks are torn at once — common underground,
	# where the auto-bomb carves dense rock — several chunks go dirty per frame and
	# rebuilding them all in one frame tanks the framerate. Cap rebuilds per frame
	# and let the rest wait a frame; collision reads the cells array (updated
	# immediately), so only the VISUAL mesh lags a frame or two — invisible in play.
	var rebuilt := 0
	for ch in _chunks:
		(ch["node"] as Node3D).position.y -= spd
		var active := _chunk_is_active(ch)
		(ch["node"] as Node3D).visible = active
		_update_enemy_front_runtime(ch, active)
		if active and ch["dirty"] and rebuilt < MAX_REBUILDS_PER_FRAME:
			ch["dirty"] = false
			_rebuild_mesh(ch)
			rebuilt += 1
	var spawn_y := SPAWN_Y
	var kill_y := KILL_Y
	if GameState.golden_walk and GameState.arena_active:
		spawn_y = maxf(SPAWN_Y, GameState.py + 10.0)
		kill_y = minf(KILL_Y, GameState.py - 14.0)
	elif GameState.is_zako_mode() and GameState.zako_unit_active:
		spawn_y = maxf(SPAWN_Y, _active_actor_y() + _screen_world_height() * GameState.chunk_preload_screens)
		kill_y = minf(KILL_Y, GameState.zako_unit_world_y - 14.0)
	while _row_top_y() < spawn_y:
		_spawn_chunk()
	while not _chunks.is_empty() \
			and (_chunks[0]["node"] as Node3D).position.y < kill_y - ROW_H:
		(_chunks[0]["node"] as Node3D).queue_free()
		_chunks.remove_at(0)

func _prune_decor_blocks() -> void:
	for i in range(_decor_blocks.size() - 1, -1, -1):
		var raw: Variant = _decor_blocks[i].get("node")
		if raw == null or not is_instance_valid(raw):
			_decor_blocks.remove_at(i)
			continue
		var n := raw as Node
		if n == null or n.is_queued_for_deletion():
			_decor_blocks.remove_at(i)

func _row_top_y() -> float:
	return float(_next_row) * ROW_H - 6.5 - _scrolled

# World-y for a column's noise-space y. A chunk node sits at _next_row*ROW_H - 6.5 - _scrolled
# and noise sgy = _next_row*ROW_H + cell offset, so the two spaces differ by this constant.
func _col_world_y(sgy: float) -> float:
	return sgy - 6.5 - _scrolled

func ensure_generated_to(world_y: float) -> void:
	while _row_top_y() < world_y:
		_spawn_chunk()
	recalculate_visible_chunks()

func ensure_chunks_around(world_y: float, preload_screens: float) -> void:
	var ahead := _screen_world_height() * maxf(preload_screens, 1.0)
	ensure_generated_to(world_y + ahead)
	recalculate_visible_chunks()

func ensureChunksAround(world_y: float, preload_screens: float) -> void:
	ensure_chunks_around(world_y, preload_screens)

func generate_enemy_front_chunk(hero_world_y: float, screens_ahead: float) -> float:
	var front_y := hero_world_y + _screen_world_height() * maxf(screens_ahead, 1.0)
	ensure_chunks_around(front_y, 1.5)
	for ch in _chunks:
		var node_y: float = (ch["node"] as Node3D).position.y
		if absf((node_y + ROW_H * 0.5) - front_y) <= _screen_world_height() * 0.85:
			_ensure_enemy_front_data(ch)
	recalculate_visible_chunks()
	return front_y

func generateEnemyFrontChunk(hero_world_y: float, screens_ahead: float) -> float:
	return generate_enemy_front_chunk(hero_world_y, screens_ahead)

func recalculate_visible_chunks() -> void:
	for ch in _chunks:
		var active := _chunk_is_active(ch)
		(ch["node"] as Node3D).visible = active
		_update_enemy_front_runtime(ch, active)

func _active_actor_y() -> float:
	return GameState.active_world_y()

func _active_chunk_half_height() -> float:
	return maxf(12.0, _screen_world_height() * 1.35)

func _chunk_is_active(ch: Dictionary) -> bool:
	var node_y: float = (ch["node"] as Node3D).position.y
	var center_y := node_y + ROW_H * 0.5
	return absf(center_y - _active_actor_y()) <= _active_chunk_half_height()

func _screen_world_height() -> float:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return 8.0
	var sz := get_viewport().get_visible_rect().size
	var depth := camera.global_position.z - GameState.alt_to_z(GameState.alt)
	var top := camera.project_position(Vector2(sz.x * 0.5, 0.0), depth)
	var bottom := camera.project_position(Vector2(sz.x * 0.5, sz.y), depth)
	return absf(bottom.y - top.y)

func _ensure_enemy_front_data(ch: Dictionary) -> void:
	var existing: Dictionary = ch.get("enemy_front", {})
	if not existing.is_empty():
		return
	var idx := int(ch["idx"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 170003 + idx * 9176 + 41
	var turrets: Array = []
	var spawn_points: Array = []
	var obstacles: Array = []
	var hazards: Array = []
	for i in 2:
		turrets.append({
			"x": rng.randf_range(-2.2, 2.2),
			"local_y": rng.randf_range(0.12, ROW_H - 0.12),
			"type": "turret",
			"destroyed": false,
		})
	for i in 3:
		spawn_points.append({
			"x": rng.randf_range(-3.0, 3.0),
			"local_y": rng.randf_range(0.05, ROW_H - 0.05),
			"type": "zako_spawn",
		})
	for i in 3:
		obstacles.append({
			"x": rng.randf_range(-3.6, 3.6),
			"local_y": rng.randf_range(0.05, ROW_H - 0.05),
			"kind": "block_cluster",
		})
	for i in 1:
		hazards.append({
			"x": rng.randf_range(-2.8, 2.8),
			"local_y": rng.randf_range(0.10, ROW_H - 0.10),
			"kind": "hazard_beacon",
		})
	ch["enemy_front"] = {
		"world_y": (ch["node"] as Node3D).position.y,
		"terrain_tiles": true,
		"turret_placements": turrets,
		"enemy_spawn_points": spawn_points,
		"obstacles": obstacles,
		"hazard_objects": hazards,
	}
	_stamp_enemy_front_blocks(ch, obstacles, hazards)

func _stamp_enemy_front_blocks(ch: Dictionary, obstacles: Array, hazards: Array) -> void:
	var cells: Array = ch["cells"]
	for rec: Dictionary in obstacles:
		var ix := clampi(int((float(rec.get("x", 0.0)) + WIDTH * 0.5) / B), 0, COLS_X - 1)
		var iy := clampi(int(float(rec.get("local_y", 0.0)) / B), 0, ROWS_Y - 1)
		for ox in range(-1, 2):
			var x2 := clampi(ix + ox, 0, COLS_X - 1)
			var ci := iy * COLS_X + x2
			var col: PackedByteArray = cells[ci]
			for iz in range(IZ_CRUST + 2, mini(NZ, IZ_CRUST + 6)):
				col[iz] = ROCK
			cells[ci] = col
	for rec: Dictionary in hazards:
		var ix := clampi(int((float(rec.get("x", 0.0)) + WIDTH * 0.5) / B), 0, COLS_X - 1)
		var iy := clampi(int(float(rec.get("local_y", 0.0)) / B), 0, ROWS_Y - 1)
		var ci := iy * COLS_X + ix
		var col: PackedByteArray = cells[ci]
		for iz in range(IZ_CRUST + 2, mini(NZ, IZ_CRUST + 5)):
			col[iz] = UG_MAGMA
		cells[ci] = col
	ch["cells"] = cells
	ch["dirty"] = true

func _update_enemy_front_runtime(ch: Dictionary, active: bool) -> void:
	var key := int(ch["idx"])
	if not active:
		_clear_enemy_front_runtime(key)
		return
	var data: Dictionary = ch.get("enemy_front", {})
	if data.is_empty():
		return
	if _enemy_front_nodes.has(key):
		return
	var nodes: Array[Node] = []
	var node_y: float = (ch["node"] as Node3D).position.y
	for rec: Dictionary in data.get("turret_placements", []):
		if rec.get("destroyed", false):
			continue
		var e := ENEMY_SCENE.instantiate() as Enemy
		e.name = "EnemyFrontTurret_%d" % key
		e.enemy_type = str(rec.get("type", "turret"))
		e.alt = 0.0
		e.hp = 2
		e.max_hp = 2
		e.position = Vector3(float(rec.get("x", 0.0)), node_y + float(rec.get("local_y", 0.0)), GameState.enemy_z(e.alt))
		get_parent().add_child(e)
		nodes.append(e)
	_enemy_front_nodes[key] = nodes

func _clear_enemy_front_runtime(key: int) -> void:
	if not _enemy_front_nodes.has(key):
		return
	for node in _enemy_front_nodes[key]:
		if node != null and is_instance_valid(node):
			(node as Node).queue_free()
	_enemy_front_nodes.erase(key)

# --- Bullet vs blocks ---------------------------------------------------------
# A bullet at p destroys the top block of the column under it when that block
# protrudes above the ALT0 plane and the bullet isn't flying clear over it.
# Returns {} on miss, else {res, color, pos} of the destroyed block.

func try_block_hit(p: Vector3) -> Dictionary:
	if p.x < -WIDTH * 0.5 or p.x >= WIDTH * 0.5:
		return {}
	# Boss arena terrain is NON-destructible (the meandering walls stay solid).
	if _has_underground:
		if GameState.golden_walk and GameState.arena_active:
			var rubble := blast(p, 0.58)
			if rubble.is_empty():
				return {}
			var first: Dictionary = rubble[0]
			return {"res": first.get("res", "ORE"),
				"color": first.get("color", Color(1.0, 0.55, 0.18)),
				"rare": first.get("rare", false),
				"pos": p,
				"drops": rubble.slice(1),
				"effect_count": 32,
				"effect_strength": 2.0}
		return {}
	var decor_hit := _try_decor_block_hit(p)
	if not decor_hit.is_empty():
		return decor_hit
	for ch in _chunks:
		if not _chunk_is_active(ch):
			continue
		var ly: float = p.y - (ch["node"] as Node3D).position.y
		if ly < 0.0 or ly >= ROW_H:
			continue
		var ix := int((p.x + WIDTH * 0.5) / B)
		var iy := clampi(int(ly / B), 0, ROWS_Y - 1)
		var ci := iy * COLS_X + ix
		var col: PackedByteArray = ch["cells"][ci]
		# Bullets only hit blocks in THEIR altitude slice. The old "topmost
		# block below bullet z" rule made high-altitude shots dig the ground,
		# so surface-air combat collapsed into accidental terrain mining.
		# Surface combat hits only the relief band (above the crust). (The arena
		# returns early above — its terrain is non-destructible.)
		var bullet_iz := clampi(int((p.z - CELL_Z0) / B), IZ_CRUST, NZ - 1)
		var iz_hi := mini(NZ - 1, bullet_iz + 1)
		var iz_lo := maxi(IZ_CRUST, bullet_iz - 1)
		for iz in range(iz_hi, iz_lo - 1, -1):
			if col[iz] != 0:
				var cell_z := CELL_Z0 + (float(iz) + 0.5) * B
				if absf(p.z - cell_z) > B * 0.82:
					continue
				var bid: int = col[iz]
				col[iz] = 0
				ch["cells"][ci] = col
				ch["dirty"] = true
				_destroy_decor(ch, ci)
				var bd: Dictionary = BLOCK_DEFS[bid]
				var bx_center := -WIDTH * 0.5 + (float(ix) + 0.5) * B
				return {"res": bd["res"], "color": _palette.get(bid, bd["c"]),
					"rare": randf() < 0.025,
					"pos": Vector3(bx_center,
						(ch["node"] as Node3D).position.y + (float(iy) + 0.5) * B,
						CELL_Z0 + (float(iz) + 0.5) * B)}
		return {}
	return {}

func _try_decor_block_hit(p: Vector3) -> Dictionary:
	for i in range(_decor_blocks.size() - 1, -1, -1):
		var rec: Dictionary = _decor_blocks[i]
		var raw: Variant = rec.get("node")
		if raw == null or not is_instance_valid(raw):
			_decor_blocks.remove_at(i)
			continue
		var node := raw as Node3D
		if node == null or node.is_queued_for_deletion():
			_decor_blocks.remove_at(i)
			continue
		var gp := node.global_position
		var bx := node.global_transform.basis.x.length()
		var by := node.global_transform.basis.y.length()
		var bz := node.global_transform.basis.z.length()
		var z_half := maxf(0.18, bz * 0.78 + 0.12)
		if absf(p.z - gp.z) > z_half:
			continue
		var r := maxf(0.12, maxf(bx, by) * 0.78)
		var dx := p.x - gp.x
		var dy := p.y - gp.y
		if dx * dx + dy * dy <= r * r:
			node.queue_free()
			_decor_blocks.remove_at(i)
			return {"res": rec.get("res", "ALLOY"),
				"color": rec.get("color", Color(0.55, 0.55, 0.60)),
				"rare": false, "pos": gp}
	return {}

# Terrain attack: blow a crater — every column whose center lies within
# radius of p loses its whole stack; hidden abyss sites in the crater open.
# Returns a few resource drops harvested from the rubble.
# True if any non-empty block stack sits within radius of (x, y) — i.e. there
# is real surface to crater there. Unit1's ground bomb flies on over gaps and
# water until this reports a target, so it never wastes a drop on empty ground.
# True if the CRUST (alt900 block layer) is intact within radius of (x,y) — i.e.
# no descent opening here. Unit1's _update_hole_sense uses `not has_block` to detect
# a torn-open hole (a destroyed breakable cluster) to drop through.
func has_block(x: float, y: float, radius: float) -> bool:
	for ch in _chunks:
		if not _chunk_is_active(ch):
			continue
		var node_y: float = (ch["node"] as Node3D).position.y
		if y + radius < node_y or y - radius > node_y + ROW_H:
			continue
		for iy in ROWS_Y:
			var cy := node_y + (float(iy) + 0.5) * B
			if absf(cy - y) > radius:
				continue
			for ix in COLS_X:
				var cx := -WIDTH * 0.5 + (float(ix) + 0.5) * B
				if Vector2(cx, cy).distance_to(Vector2(x, y)) > radius:
					continue
				var col: PackedByteArray = ch["cells"][iy * COLS_X + ix]
				if col[IZ_CRUST] != 0 or col[IZ_CRUST + 1] != 0:
					return true
	return false

# Bomb / terrain-attack crater within radius of p (a single z-plane band around p.z):
# clears solid cells to empty — EXCEPT the unbreakable crust, which only yields on a
# breakable-cluster column (that's how the descent hole is torn open).
func blast(p: Vector3, radius: float, _dmg: int = -1) -> Array:
	var drops: Array = []
	var destroyed := 0
	var arena_mining := GameState.golden_walk and GameState.arena_active and _has_underground
	var drop_cap := 14 if arena_mining else 4
	var drop_chance := 0.48 if arena_mining else 0.3
	var rare_chance := 0.04 if arena_mining else 0.025
	var iz_lo := clampi(int((p.z - radius - CELL_Z0) / B), 0, NZ - 1)
	var iz_hi := clampi(int((p.z + radius - CELL_Z0) / B), 0, NZ - 1)
	var touches_crust := iz_hi >= IZ_CRUST - 1 and iz_lo <= IZ_CRUST + 2
	for ch in _chunks:
		if not _chunk_is_active(ch):
			continue
		var node_y: float = (ch["node"] as Node3D).position.y
		if p.y + radius < node_y or p.y - radius > node_y + ROW_H:
			continue
		for iy in ROWS_Y:
			var cy := node_y + (float(iy) + 0.5) * B
			if absf(cy - p.y) > radius:
				continue
			for ix in COLS_X:
				var cx := -WIDTH * 0.5 + (float(ix) + 0.5) * B
				if Vector2(cx, cy).distance_to(Vector2(p.x, p.y)) > radius:
					continue
				# Spare the arena's flank walls — they are the one indestructible structure.
				if arena_mining and is_arena_wall(cx):
					continue
				var ci := iy * COLS_X + ix
				var col: PackedByteArray = ch["cells"][ci]
				var bx := ix
				var by := int(ch["idx"]) * ROWS_Y + iy
				var crust_breakable := (ch["breakable"] as PackedByteArray)[ci] == 1
				var changed := false
				if col[0] == 0:
					col[0] = _underground_floor(_underground_kind(cx, cy))
					changed = true
				if GameState.underground and _reveal_oopart_tile(col, bx, by):
					changed = true
				var clear_lo := iz_lo
				var clear_hi := iz_hi
				if touches_crust and crust_breakable:
					# A destroyed breakable crust cluster is a real SHAFT through the
					# alt900 shell, not a shallow crater. Clear the column down into
					# the underground air band AND up through any surface relief, so
					# the lower world is visible through the hole immediately and the
					# ship can actually descend.
					clear_lo = 1
					clear_hi = NZ - 1
				elif arena_mining and GameState.arena_wall_armed and is_sealed_wall_at(cx, cy):
					# Sealed relic wall: bore a FULL-HEIGHT archway, not just a pocket at the ship's
					# flight level. The chase camera rides ABOVE the ship (z≈-16.3, iz≈31); a
					# ship-level pocket leaves the wall solid AROUND the camera, which then clips
					# through it — the void above ("天井") and the abyss below show through. Clearing
					# the whole dug column keeps the camera in open space AND removes the overhead
					# lintel that would otherwise hide the ship. Depth in Y is still a real bore (the
					# flight form grinds through it slowly), so it keeps its dig heft — only the Z
					# slice of each dug column is opened fully.
					clear_lo = 1
					clear_hi = ARENA_WALL_HEIGHT
				for iz in range(clear_lo, clear_hi + 1):
					if iz == 0:
						continue
					if col[iz] == 0:
						continue
					var bid: int = col[iz]
					if bid == OOPART_BLOCK or bid == OOPART_FOUND_BLOCK:
						if _reveal_oopart_tile(col, bx, by):
							changed = true
						continue
					col[iz] = 0
					destroyed += 1
					changed = true
					if drops.size() < drop_cap and randf() < drop_chance:
						drops.append({"res": BLOCK_DEFS[bid]["res"],
							"color": _palette.get(bid, BLOCK_DEFS[bid]["c"]),
							"pos": Vector3(cx, cy, CELL_Z0 + (float(iz) + 0.5) * B),
							"rare": randf() < rare_chance})
					# A relic is buried in the field: it trickles out of blasted blocks until
					# the player has all three, then the sealed wall frames in (handled in Main).
					if arena_mining and not GameState.arena_wall_armed \
							and GameState.arena_relics_found < GameState.ARENA_RELIC_GOAL \
							and GameState.frame >= _next_relic_frame and randf() < 0.006:
						# Long floor between drops so the three feel earned (a real dig, not a shower).
						_next_relic_frame = GameState.frame + 600
						_spawn_arena_relic(Vector3(cx, cy, GameState.alt_to_z(GameState.ARENA_FLOOR_ALT)))
				if changed:
					ch["cells"][ci] = col
					ch["dirty"] = true
					_destroy_decor(ch, ci)
	GameState.score += destroyed * (8 if arena_mining else 5)
	return drops

# Drop one relic of the buried set at the freshly cleared spot, hovering on the floor plane
# for the GERWALK to walk over. KeyItem("arena_relic") tallies them and arms the wall at 3.
func _spawn_arena_relic(pos: Vector3) -> void:
	var relic := KeyItem.new()
	relic.item_kind = "arena_relic"
	var scene := get_tree().current_scene
	if scene == null:
		return
	scene.add_child(relic)
	relic.global_position = pos
	# Punch a clean shaft straight up from the relic — destroy EVERY block above it (its column up
	# through the field/ceiling) so the top-down chase camera actually SEES it, instead of it
	# surfacing buried under rock where you'd only collect it by walking over it blind. Deferred:
	# we're mid-blast() (which writes back its own cached column for the cell that spawned us), so
	# clearing now would be overwritten for that very column — run it once blast() has returned.
	call_deferred("clear_descent_shaft", pos.x, pos.y, 0.78)
	# Announce it — these were being collected unnoticed. A bright alert + a HUD cue so the player
	# knows a STAR RELIC surfaced and goes to find the glowing beacon.
	TsgAudio.star_relic_appear()
	get_tree().call_group("star_hud", "show_message", "STAR RELIC APPEARED", "FOLLOW THE LIGHT")

func clear_descent_shaft(wx: float, wy: float, radius: float) -> void:
	for ch in _chunks:
		if not _chunk_is_active(ch):
			continue
		var node_y: float = (ch["node"] as Node3D).position.y
		if wy + radius < node_y or wy - radius > node_y + ROW_H:
			continue
		var any := false
		for iy in ROWS_Y:
			var cy := node_y + (float(iy) + 0.5) * B
			if absf(cy - wy) > radius:
				continue
			for ix in COLS_X:
				var cx := -WIDTH * 0.5 + (float(ix) + 0.5) * B
				if Vector2(cx, cy).distance_to(Vector2(wx, wy)) > radius:
					continue
				var ci := iy * COLS_X + ix
				var col: PackedByteArray = ch["cells"][ci]
				col[0] = _underground_floor(_underground_kind(cx, cy))
				for iz in range(1, NZ):
					col[iz] = 0
				ch["cells"][ci] = col
				_destroy_decor(ch, ci)
				any = true
		if any:
			ch["dirty"] = true

# Small scenery clusters per chunk, matched to the local region: houses and
# bushes on the plains, cars and street lamps along the roads, rocks in the
# wastes. Each piece is anchored to its ground column ("decor" dict), so
# destroying the ground block underneath smashes the object with it.
func _add_decor(ch: Dictionary, idx: int, rng: RandomNumberGenerator) -> void:
	if _decor.is_empty():
		return
	var node: Node3D = ch["node"]
	var decor_count := 4 if _surface_festival else (1 if _quiet_surface else 5)
	for i in decor_count:
		var ix := rng.randi_range(2, COLS_X - 3)
		var iy := rng.randi_range(0, ROWS_Y - 1)
		var bx := ix
		var by := idx * ROWS_Y + iy
		var gx := (float(bx) + 0.5) * B - WIDTH * 0.5
		var gy := (float(by) + 0.5) * B
		var region := _region(gx, gy)
		if region == "cloud" or region == "lava" or region == "sea":
			continue
		var ly := (float(iy) + 0.5) * B
		var gz := GROUND_Z + float(_ground_h(bx, by)) * B
		var root := Node3D.new()
		root.position = Vector3(gx, ly, 0.0)
		node.add_child(root)
		var made := true
		if _road_col(bx, by, region):
			var vertical := posmod(bx, 14 if (region == "city" or region == "fortress") else 26) < 2
			var roll := rng.randf()
			if roll < 0.30:
				_decor_car(root, gz, vertical, rng)
			elif roll < 0.55:
				_decor_lamp(root, gz)
			elif roll < 0.68 and (region == "city" or region == "fortress"):
				_decor_billboard(root, gz, rng)
			else:
				made = false
		else:
			match region:
				"plains", "forest", "snow", "ice":
					var roll := rng.randf()
					if region == "forest" and roll < 0.42:
						_decor_tree(root, gz, rng)
					elif roll < 0.18:
						_decor_house(root, gz, rng)
					elif roll < 0.40 and (region == "plains" or region == "forest"):
						_decor_flowers(root, gz, rng)
					elif roll < 0.62:
						_decor_box(root, Vector3(0.05, 0.05, 0.04),
							Vector3(0, 0, gz + 0.02), _decor["pebble"],
							rng.randf_range(0.0, 90.0))
					else:
						var mi := MeshInstance3D.new()
						mi.mesh = _decor["sphere"]
						mi.scale = Vector3(0.09, 0.09, 0.07) * rng.randf_range(0.7, 1.4)
						mi.position = Vector3(0, 0, gz + 0.03)
						mi.material_override = _decor["bush"]
						root.add_child(mi)
				"city":
					# Suburbs get little houses; downtown gets glowing billboards.
					var dt := clampf((_vnoise(gx * 0.09 + 7.0, gy * 0.09) - 0.25) * 1.6, 0.0, 1.0)
					if dt < 0.30 and rng.randf() < 0.5:
						_decor_house(root, gz, rng)
					elif dt > 0.5 and rng.randf() < 0.3:
						_decor_billboard(root, gz, rng)
					elif dt > 0.35 and rng.randf() < 0.55:
						_decor_tower(root, gz, rng)
					else:
						made = false
				"desert":
					if rng.randf() < 0.50:
						_decor_cactus(root, gz, rng)
					else:
						_decor_box(root, Vector3(0.06, 0.06, 0.05),
							Vector3(0, 0, gz + 0.025), _decor["pebble"],
							rng.randf_range(0.0, 90.0))
				"mountain":
					if rng.randf() < 0.7:
						_decor_box(root, Vector3(0.06, 0.06, 0.05),
							Vector3(0, 0, gz + 0.025), _decor["pebble"],
							rng.randf_range(0.0, 90.0))
					else:
						made = false
				"crystal", "ice":
					_decor_crystal_spikes(root, gz, rng)
				"lava":
					if rng.randf() < 0.55:
						_decor_lava_vent(root, gz, rng)
					else:
						made = false
				_:
					made = false
		if made:
			var dd: Dictionary = ch["decor"]
			var ci := iy * COLS_X + ix
			if not dd.has(ci):
				dd[ci] = []
			(dd[ci] as Array).append(root)
		else:
			root.queue_free()

# The ground under a decoration was destroyed: the object goes with it.
func _destroy_decor(ch: Dictionary, ci: int) -> void:
	var dd: Dictionary = ch["decor"]
	if not dd.has(ci):
		return
	for n in dd[ci]:
		if is_instance_valid(n):
			n.queue_free()
	dd.erase(ci)

func _track_decor_root(ch: Dictionary, ci: int, root: Node3D) -> void:
	var dd: Dictionary = ch["decor"]
	if not dd.has(ci):
		dd[ci] = []
	(dd[ci] as Array).append(root)

func _decor_house(root: Node3D, gz: float, rng: RandomNumberGenerator) -> void:
	var w := rng.randf_range(0.12, 0.18)
	var d := rng.randf_range(0.10, 0.14)
	var hh := rng.randf_range(0.07, 0.11)
	_decor_box(root, Vector3(w, d, hh), Vector3(0, 0, gz + hh * 0.5), _decor["wall"])
	# Gabled roof: a diamond prism laid along the house's long axis.
	_decor_box(root, Vector3(w * 1.1, d * 0.72, d * 0.72),
		Vector3(0, 0, gz + hh), _decor["roof"], 0.0, 45.0)

func _decor_car(root: Node3D, gz: float, vertical: bool,
		rng: RandomNumberGenerator) -> void:
	var cars: Array = _decor["cars"]
	var mat: Material = cars[rng.randi() % cars.size()]
	var rot := 90.0 if vertical else 0.0
	_decor_box(root, Vector3(0.11, 0.05, 0.03), Vector3(0, 0, gz + 0.018), mat, rot)
	_decor_box(root, Vector3(0.055, 0.042, 0.024), Vector3(0, 0, gz + 0.042), mat, rot)

func _decor_lamp(root: Node3D, gz: float) -> void:
	_decor_box(root, Vector3(0.014, 0.014, 0.13), Vector3(0, 0, gz + 0.065), _decor["pole"])
	_decor_box(root, Vector3(0.04, 0.04, 0.022), Vector3(0, 0, gz + 0.135), _decor["lamp"])

# A patch of tiny wildflowers in mixed colors.
func _decor_flowers(root: Node3D, gz: float, rng: RandomNumberGenerator) -> void:
	var flowers: Array = _decor["flowers"]
	for i in 3 + rng.randi() % 3:
		var mat: Material = flowers[rng.randi() % flowers.size()]
		_decor_box(root, Vector3(0.018, 0.018, 0.022),
			Vector3(rng.randf_range(-0.07, 0.07), rng.randf_range(-0.07, 0.07),
				gz + 0.011), mat)

# Roadside billboard: pole + glowing ad panel.
func _decor_billboard(root: Node3D, gz: float, rng: RandomNumberGenerator) -> void:
	var bbs: Array = _decor["billboards"]
	_decor_box(root, Vector3(0.016, 0.016, 0.11), Vector3(0, 0, gz + 0.055), _decor["pole"])
	_decor_box(root, Vector3(0.10, 0.018, 0.055), Vector3(0, 0, gz + 0.13),
		bbs[rng.randi() % bbs.size()])

func _decor_tree(root: Node3D, gz: float, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(0.13, 0.22)
	_decor_box(root, Vector3(0.025, 0.025, h), Vector3(0, 0, gz + h * 0.5), _decor["trunk"])
	var crown := MeshInstance3D.new()
	crown.mesh = _decor["sphere"]
	crown.scale = Vector3(0.12, 0.12, 0.10) * rng.randf_range(0.8, 1.25)
	crown.position = Vector3(0, 0, gz + h + 0.07)
	crown.material_override = _decor["bush"]
	root.add_child(crown)

func _decor_cactus(root: Node3D, gz: float, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(0.13, 0.24)
	_decor_box(root, Vector3(0.035, 0.035, h), Vector3(0, 0, gz + h * 0.5), _decor["bush"])
	for side in [-1.0, 1.0]:
		if rng.randf() < 0.65:
			_decor_box(root, Vector3(0.025, 0.025, 0.08),
				Vector3(side * 0.04, 0, gz + h * rng.randf_range(0.45, 0.75)), _decor["bush"],
				0.0, 90.0)

func _decor_tower(root: Node3D, gz: float, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(0.16, 0.32)
	_decor_box(root, Vector3(rng.randf_range(0.06, 0.10), rng.randf_range(0.06, 0.10), h),
		Vector3(0, 0, gz + h * 0.5), _decor["wall"])
	if rng.randf() < 0.65:
		_decor_billboard(root, gz + h * 0.65, rng)

func _decor_crystal_spikes(root: Node3D, gz: float, rng: RandomNumberGenerator) -> void:
	for i in 2 + rng.randi() % 3:
		_decor_box(root, Vector3(rng.randf_range(0.025, 0.055), rng.randf_range(0.025, 0.055),
				rng.randf_range(0.11, 0.24)),
			Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.08, 0.08),
				gz + rng.randf_range(0.06, 0.12)), _decor["crystal"],
			rng.randf_range(0.0, 90.0), rng.randf_range(8.0, 25.0))

func _decor_lava_vent(root: Node3D, gz: float, rng: RandomNumberGenerator) -> void:
	_decor_box(root, Vector3(0.10, 0.10, 0.035), Vector3(0, 0, gz + 0.018), _decor["pebble"])
	_decor_box(root, Vector3(0.045, 0.045, rng.randf_range(0.10, 0.18)),
		Vector3(0, 0, gz + 0.08), _decor["lava"])

func _add_underground_landmark(ch: Dictionary, idx: int, rng: RandomNumberGenerator) -> void:
	if _decor.is_empty() or not _has_underground:
		return
	var node: Node3D = ch["node"]
	var count := (3 + rng.randi() % 3) if _quiet_surface else (1 + rng.randi() % 2)
	for i in count:
		var ix := rng.randi_range(4, COLS_X - 5)
		var iy := rng.randi_range(0, ROWS_Y - 1)
		var bx := ix
		var by := idx * ROWS_Y + iy
		var gx := (float(bx) + 0.5) * B - WIDTH * 0.5
		var gy := (float(by) + 0.5) * B
		var kind := _underground_kind(gx, gy)
		var root := Node3D.new()
		root.position = Vector3(gx, (float(iy) + 0.5) * B, 0.0)
		node.add_child(root)
		# Anchor to its column so blasting the ground under it smashes the prop too.
		_track_decor_root(ch, iy * COLS_X + ix, root)
		var floor_z := CELL_Z0 + B * 0.55
		match kind:
			"magma":
				_decor_lava_vent(root, floor_z, rng)
				if rng.randf() < 0.55:
					_decor_box(root, Vector3(0.03, 0.03, rng.randf_range(0.26, 0.48)),
						Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.10, 0.10), floor_z + 0.18),
						_decor["lava"])
			"lake":
				for j in 3:
					_decor_box(root, Vector3(0.045, 0.045, rng.randf_range(0.16, 0.30)),
						Vector3((float(j) - 1.0) * 0.09, rng.randf_range(-0.08, 0.08), floor_z + 0.11),
						_decor["crystal"], rng.randf_range(0.0, 80.0), rng.randf_range(8.0, 24.0))
			"temple", "ruins":
				for j in 2 + rng.randi() % 2:
					_decor_box(root, Vector3(0.055, 0.055, rng.randf_range(0.25, 0.48)),
						Vector3((float(j) - 0.8) * 0.15, rng.randf_range(-0.08, 0.08), floor_z + 0.17),
						_decor["wall"])
				_decor_box(root, Vector3(0.24, 0.035, 0.035), Vector3(0, 0, floor_z + 0.36), _decor["lamp"])
			"base":
				_decor_box(root, Vector3(0.34, 0.045, 0.045), Vector3(0, 0, floor_z + 0.15), _decor["pole"],
					rng.randf_range(-25.0, 25.0))
				_decor_box(root, Vector3(0.08, 0.08, 0.06), Vector3(0, 0, floor_z + 0.24), _decor["lamp"])
			_:
				if rng.randf() < 0.60:
					_decor_crystal_spikes(root, floor_z, rng)
				else:
					for j in 3:
						_decor_box(root, Vector3(0.06, 0.06, rng.randf_range(0.08, 0.20)),
							Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.10, 0.10), floor_z + 0.06),
							_decor["pebble"], rng.randf_range(0.0, 90.0))

func _add_surface_landmark(ch: Dictionary, idx: int, rng: RandomNumberGenerator) -> void:
	if _decor.is_empty():
		return
	var node: Node3D = ch["node"]
	var site := _pick_structure_site(idx, rng, 3, false)
	if not bool(site.get("ok", false)):
		return
	var ix: int = site["ix"]
	var iy: int = site["iy"]
	var bx := ix
	var by: int = site["by"]
	var gx: float = site["gx"]
	var region: String = site["region"]
	var gz := GROUND_Z + float(_ground_h(bx, by)) * B
	var root := Node3D.new()
	root.position = Vector3(gx, (float(iy) + 0.5) * B, 0.0)
	root.set_meta("destructible_structure", true)
	root.set_meta("drop_res", "ALLOY")
	root.set_meta("drop_color", Color(0.55, 0.58, 0.64))
	node.add_child(root)
	_track_decor_root(ch, iy * COLS_X + ix, root)
	match region:
		"city", "fortress":
			for i in 3 + rng.randi() % 3:
				var x := (float(i) - 1.5) * 0.13
				var h := rng.randf_range(0.22, 0.48)
				_decor_box(root, Vector3(rng.randf_range(0.07, 0.12), rng.randf_range(0.07, 0.12), h),
					Vector3(x, rng.randf_range(-0.08, 0.08), gz + h * 0.5), _decor["wall"])
			_decor_billboard(root, gz + 0.30, rng)
		"forest", "plains", "snow":
			for i in 5 + rng.randi() % 4:
				var sub := Node3D.new()
				sub.position = Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.20, 0.20), 0.0)
				root.add_child(sub)
				_decor_tree(sub, gz, rng)
		"desert", "canyon":
			for i in 3:
				_decor_box(root, Vector3(0.08, 0.08, rng.randf_range(0.18, 0.34)),
					Vector3((float(i) - 1.0) * 0.16, rng.randf_range(-0.08, 0.08), gz + 0.09),
					_decor["pebble"], rng.randf_range(0.0, 90.0), rng.randf_range(4.0, 18.0))
		"crystal", "ice":
			_decor_crystal_spikes(root, gz, rng)
			_decor_crystal_spikes(root, gz + 0.04, rng)
		"lava":
			for i in 3:
				var sub := Node3D.new()
				sub.position = Vector3(rng.randf_range(-0.18, 0.18), rng.randf_range(-0.16, 0.16), 0.0)
				root.add_child(sub)
				_decor_lava_vent(sub, gz, rng)
		_:
			_decor_box(root, Vector3(0.14, 0.14, 0.10), Vector3(0, 0, gz + 0.05), _decor["pebble"])

func _add_poly_structure(ch: Dictionary, idx: int, rng: RandomNumberGenerator, underground: bool) -> void:
	if _decor.is_empty():
		return
	var node: Node3D = ch["node"]
	var site := _pick_structure_site(idx, rng, 4, underground)
	if not bool(site.get("ok", false)):
		return
	var ix: int = site["ix"]
	var iy: int = site["iy"]
	var bx := ix
	var by: int = site["by"]
	var gx: float = site["gx"]
	var root := Node3D.new()
	root.position = Vector3(gx, (float(iy) + 0.5) * B, 0.0)
	var scale_roll := rng.randf_range(0.88, 1.55)
	if not underground and _surface_festival and rng.randf() < 0.30:
		scale_roll = rng.randf_range(1.65, 2.35)
	elif underground and rng.randf() < 0.24:
		scale_roll = rng.randf_range(1.35, 1.95)
	root.scale = Vector3.ONE * scale_roll
	root.set_meta("destructible_structure", true)
	root.set_meta("drop_res", "ALLOY" if not underground else "ORE")
	root.set_meta("drop_color", Color(0.62, 0.58, 0.48) if not underground else Color(0.45, 0.50, 0.56))
	node.add_child(root)
	_track_decor_root(ch, iy * COLS_X + ix, root)
	var base_z := (CELL_Z0 + B * 0.65) if underground else (GROUND_Z + float(_ground_h(bx, by)) * B)
	_structure_shadow(root, base_z, 0.65, 0.46)
	var roll := rng.randi() % 6
	if underground:
		roll = rng.randi() % 5
	match roll:
		0:
			_poly_base_or_warehouse(root, base_z, rng, underground)
		1:
			_poly_truss(root, base_z, rng)
		2:
			_poly_honeycomb(root, base_z, rng)
		3:
			_poly_ruin_gate(root, base_z, rng, underground)
		4:
			_poly_mystery_totem(root, base_z, rng, underground)
		_:
			_poly_rock_cluster(root, base_z, rng)

func _add_large_block_structure(ch: Dictionary, idx: int, rng: RandomNumberGenerator,
		underground: bool, forced_theme: int = -1) -> void:
	if _decor.is_empty():
		return
	var node: Node3D = ch["node"]
	var site := _pick_structure_site(idx, rng, 5, underground)
	if not bool(site.get("ok", false)):
		return
	var ix: int = site["ix"]
	var iy: int = site["iy"]
	var bx := ix
	var by: int = site["by"]
	var gx: float = site["gx"]
	var root := Node3D.new()
	root.position = Vector3(gx, (float(iy) + 0.5) * B, 0.0)
	var scale_roll := rng.randf_range(1.05, 1.85)
	if not underground and _surface_festival:
		scale_roll = rng.randf_range(2.15, 3.30)
		if forced_theme == 6 or rng.randf() < 0.16:
			scale_roll = rng.randf_range(3.40, 5.20)
	elif underground and rng.randf() < 0.34:
		scale_roll = rng.randf_range(1.45, 2.50)
	root.scale = Vector3.ONE * scale_roll
	root.set_meta("destructible_structure", true)
	root.set_meta("drop_res", "ALLOY" if not underground else "ORE")
	root.set_meta("drop_color", Color(0.66, 0.62, 0.50) if not underground else Color(0.42, 0.47, 0.54))
	node.add_child(root)
	_track_decor_root(ch, iy * COLS_X + ix, root)
	var z := (CELL_Z0 + B * 0.75) if underground else (GROUND_Z + float(_ground_h(bx, by)) * B)
	_structure_shadow(root, z, 1.35, 0.92)
	var theme := _underground_structure_theme if underground else _surface_structure_theme
	if forced_theme >= 0:
		theme = forced_theme
	elif rng.randf() < 0.72:
		theme = rng.randi() % (7 if underground else 8)
	match theme:
		0:
			_large_block_island(root, z, rng, underground)
		1:
			_large_fortress(root, z, rng, underground)
		2:
			_large_warehouse_yard(root, z, rng, underground)
		3:
			_large_ruin_complex(root, z, rng, underground)
		4:
			_large_rock_mesa(root, z, rng)
		5:
			_large_crystal_machine(root, z, rng, underground)
		6:
			_large_stepped_pyramid(root, z, rng, underground)
		_:
			_large_mixed_settlement(root, z, rng)

func _pick_structure_site(idx: int, rng: RandomNumberGenerator, margin: int,
		underground: bool) -> Dictionary:
	for attempt in 12:
		var ix := rng.randi_range(margin, COLS_X - margin - 1)
		var iy := rng.randi_range(0, ROWS_Y - 1)
		var by := idx * ROWS_Y + iy
		var gx := (float(ix) + 0.5) * B - WIDTH * 0.5
		var gy := (float(by) + 0.5) * B
		var region := _underground_kind(gx, gy) if underground else _region(gx, gy)
		if underground or (region != "sea" and region != "cloud"):
			return {"ok": true, "ix": ix, "iy": iy, "by": by, "gx": gx, "region": region}
	if _surface_festival and not underground:
		var f_ix := rng.randi_range(margin, COLS_X - margin - 1)
		var f_iy := rng.randi_range(0, ROWS_Y - 1)
		var f_by := idx * ROWS_Y + f_iy
		var f_gx := (float(f_ix) + 0.5) * B - WIDTH * 0.5
		var f_gy := (float(f_by) + 0.5) * B
		return {"ok": true, "ix": f_ix, "iy": f_iy, "by": f_by, "gx": f_gx,
			"region": _region(f_gx, f_gy)}
	return {"ok": false}

func _structure_shadow(parent: Node3D, z: float, w: float, d: float) -> void:
	var sh := Node3D.new()
	parent.add_child(sh)
	_decor_box(sh, Vector3(w, d, 0.018), Vector3(0.05, -0.04, z + 0.012), _decor["shadow"], -7.0)
	_decor_box(sh, Vector3(w * 0.55, d * 0.35, 0.016), Vector3(-w * 0.22, d * 0.18, z + 0.015),
		_decor["shadow"], 12.0)

func _large_block_island(root: Node3D, z: float, rng: RandomNumberGenerator, underground: bool) -> void:
	var mat: Material = _decor["pebble"] if underground else _decor["wall"]
	var rx := 4 if not underground else 4
	var ry := 2
	for y in range(-ry, ry + 1):
		for x in range(-rx, rx + 1):
			var edge := absf(float(x)) / float(rx) + absf(float(y)) / float(ry + 1)
			if edge > 1.20 or rng.randf() < (0.20 if not underground else 0.24):
				continue
			var h := rng.randf_range(0.12, 0.36 if not underground else 0.26)
			_decor_box(root, Vector3(0.22, 0.22, h),
				Vector3(float(x) * 0.21, float(y) * 0.21, z + h * 0.5), mat)
			if rng.randf() < 0.18:
				_decor_box(root, Vector3(0.12, 0.12, 0.12),
					Vector3(float(x) * 0.21, float(y) * 0.21, z + h + 0.06),
					_decor["crystal"] if underground else _decor["lamp"])

func _large_fortress(root: Node3D, z: float, rng: RandomNumberGenerator, underground: bool) -> void:
	var mat: Material = _decor["pole"] if underground else _decor["wall"]
	for x in range(-3, 4):
		_decor_box(root, Vector3(0.13, 0.09, 0.14), Vector3(float(x) * 0.14, -0.32, z + 0.07), mat)
		_decor_box(root, Vector3(0.13, 0.09, 0.14), Vector3(float(x) * 0.14, 0.32, z + 0.07), mat)
	for y in range(-2, 3):
		_decor_box(root, Vector3(0.09, 0.13, 0.14), Vector3(-0.48, float(y) * 0.14, z + 0.07), mat)
		_decor_box(root, Vector3(0.09, 0.13, 0.14), Vector3(0.48, float(y) * 0.14, z + 0.07), mat)
	for p in [Vector2(-0.48, -0.32), Vector2(0.48, -0.32), Vector2(-0.48, 0.32), Vector2(0.48, 0.32)]:
		_decor_box(root, Vector3(0.16, 0.16, rng.randf_range(0.28, 0.52)),
			Vector3(p.x, p.y, z + 0.18), mat)
	_decor_box(root, Vector3(0.24, 0.18, 0.16), Vector3(0, 0, z + 0.08), _decor["lamp"])

func _large_warehouse_yard(root: Node3D, z: float, rng: RandomNumberGenerator, underground: bool) -> void:
	var mat: Material = _decor["pole"] if underground else _decor["wall"]
	for i in 4:
		var x := (float(i) - 1.5) * 0.24
		_decor_box(root, Vector3(0.20, 0.34, rng.randf_range(0.13, 0.24)),
			Vector3(x, rng.randf_range(-0.08, 0.08), z + 0.08), mat)
	for i in 5:
		_decor_box(root, Vector3(0.08, 0.08, 0.08),
			Vector3(rng.randf_range(-0.55, 0.55), rng.randf_range(-0.42, 0.42), z + 0.04),
			_decor["pebble"])
	for i in 3:
		_decor_box(root, Vector3(0.045, 0.42, 0.045),
			Vector3((float(i) - 1.0) * 0.34, 0.0, z + 0.20), _decor["lamp"],
			rng.randf_range(-12.0, 12.0))

func _large_ruin_complex(root: Node3D, z: float, rng: RandomNumberGenerator, underground: bool) -> void:
	var mat: Material = _decor["pebble"] if underground else _decor["wall"]
	for i in 7:
		var x := (float(i) - 3.0) * 0.16
		var h := rng.randf_range(0.24, 0.55)
		if rng.randf() < 0.22:
			continue
		_decor_box(root, Vector3(0.06, 0.06, h), Vector3(x, rng.randf_range(-0.18, 0.18), z + h * 0.5), mat)
	for i in 3:
		_decor_box(root, Vector3(0.42, 0.045, 0.05),
			Vector3(rng.randf_range(-0.18, 0.18), (float(i) - 1.0) * 0.19, z + rng.randf_range(0.22, 0.46)),
			mat, rng.randf_range(-10.0, 10.0))
	if rng.randf() < 0.7:
		_poly_mystery_totem(root, z + 0.02, rng, underground)

func _large_rock_mesa(root: Node3D, z: float, rng: RandomNumberGenerator) -> void:
	for i in 12:
		var x := rng.randf_range(-0.55, 0.55)
		var y := rng.randf_range(-0.42, 0.42)
		var h := rng.randf_range(0.14, 0.50) * (1.0 - clampf(absf(x) * 0.8, 0.0, 0.55))
		_decor_box(root, Vector3(rng.randf_range(0.10, 0.22), rng.randf_range(0.10, 0.22), h),
			Vector3(x, y, z + h * 0.5), _decor["pebble"], rng.randf_range(0.0, 90.0),
			rng.randf_range(-10.0, 18.0))

func _large_crystal_machine(root: Node3D, z: float, rng: RandomNumberGenerator, underground: bool) -> void:
	var frame: Material = _decor["pole"] if underground else _decor["wall"]
	_decor_box(root, Vector3(0.72, 0.08, 0.08), Vector3(0, 0, z + 0.12), frame)
	_decor_box(root, Vector3(0.08, 0.72, 0.08), Vector3(0, 0, z + 0.12), frame)
	for i in 5:
		var a := TAU * float(i) / 5.0
		_decor_box(root, Vector3(0.08, 0.08, rng.randf_range(0.18, 0.38)),
			Vector3(cos(a) * 0.30, sin(a) * 0.30, z + 0.18), _decor["crystal"],
			rad_to_deg(a), rng.randf_range(8.0, 25.0))

func _large_stepped_pyramid(root: Node3D, z: float, rng: RandomNumberGenerator, underground: bool) -> void:
	var mat: Material = _decor["pebble"] if underground else _decor["wall"]
	var levels := 4 if underground else 5
	var block := 0.145 if underground else 0.20
	var step_h := 0.10 if underground else 0.15
	for level in levels:
		var span := levels - level
		for x in range(-span, span + 1):
			for y in range(-span, span + 1):
				if absi(x) == span or absi(y) == span or (level >= levels - 2 and rng.randf() < 0.16):
					_decor_box(root, Vector3(block, block, step_h),
						Vector3(float(x) * block, float(y) * block,
							z + step_h * 0.5 + float(level) * step_h),
						mat)
	if rng.randf() < 0.8:
		_decor_box(root, Vector3(0.12, 0.12, 0.16),
			Vector3(0, 0, z + float(levels) * step_h + 0.08), _decor["lamp"])

func _large_mixed_settlement(root: Node3D, z: float, rng: RandomNumberGenerator) -> void:
	for i in 8:
		var h := rng.randf_range(0.12, 0.38)
		_decor_box(root, Vector3(rng.randf_range(0.09, 0.18), rng.randf_range(0.09, 0.18), h),
			Vector3(rng.randf_range(-0.55, 0.55), rng.randf_range(-0.38, 0.38), z + h * 0.5),
			_decor["wall"] if rng.randf() < 0.7 else _decor["lamp"])

func _poly_base_or_warehouse(root: Node3D, z: float, rng: RandomNumberGenerator, underground: bool) -> void:
	var mat: Material = _decor["pole"] if underground else _decor["wall"]
	_decor_box(root, Vector3(0.34, 0.20, 0.12), Vector3(0, 0, z + 0.06), mat)
	_decor_box(root, Vector3(0.16, 0.14, 0.13), Vector3(-0.12, 0.06, z + 0.18), mat)
	_decor_box(root, Vector3(0.12, 0.12, 0.10), Vector3(0.13, -0.04, z + 0.17), mat)
	if rng.randf() < 0.8:
		_decor_box(root, Vector3(0.07, 0.03, 0.05), Vector3(0.0, -0.12, z + 0.16), _decor["lamp"])
	for i in 2:
		_decor_box(root, Vector3(0.05, 0.05, 0.07),
			Vector3((float(i) - 0.5) * 0.25, 0.14, z + 0.035), _decor["pebble"])

func _poly_truss(root: Node3D, z: float, rng: RandomNumberGenerator) -> void:
	var w := rng.randf_range(0.44, 0.72)
	var h := rng.randf_range(0.28, 0.52)
	for si in range(2):
		var side := -1.0 if si == 0 else 1.0
		_decor_box(root, Vector3(0.025, h, 0.025), Vector3(side * w * 0.5, 0, z + 0.18),
			_decor["pole"], 0.0, rng.randf_range(-8.0, 8.0))
	for i in 4:
		var y := lerpf(-0.20, 0.20, float(i) / 3.0)
		_decor_box(root, Vector3(w, 0.022, 0.022), Vector3(0, y, z + 0.17 + float(i & 1) * 0.04),
				(_decor["lamp"] as Material) if (i & 1) == 0 else (_decor["pole"] as Material),
				rng.randf_range(-28.0, 28.0))

func _poly_honeycomb(root: Node3D, z: float, rng: RandomNumberGenerator) -> void:
	for x in range(-2, 3):
		for y in range(-1, 2):
			if rng.randf() < 0.25:
				continue
			var cx := float(x) * 0.105 + (0.052 if (y & 1) != 0 else 0.0)
			var cy := float(y) * 0.095
			for i in 6:
				var a := TAU * float(i) / 6.0
				_decor_box(root, Vector3(0.075, 0.012, 0.018),
					Vector3(cx + cos(a) * 0.055, cy + sin(a) * 0.055, z + 0.12),
					_decor["lamp"], rad_to_deg(a))

func _poly_ruin_gate(root: Node3D, z: float, rng: RandomNumberGenerator, underground: bool) -> void:
	var mat: Material = _decor["wall"] if not underground else _decor["pebble"]
	for si in range(2):
		var side := -1.0 if si == 0 else 1.0
		_decor_box(root, Vector3(0.055, 0.055, rng.randf_range(0.28, 0.46)),
			Vector3(side * 0.18, 0, z + 0.17), mat)
	_decor_box(root, Vector3(0.46, 0.045, 0.055), Vector3(0, 0, z + 0.42), mat)
	if rng.randf() < 0.7:
		_decor_box(root, Vector3(0.11, 0.025, 0.08), Vector3(0, 0, z + 0.24), _decor["lamp"])

func _poly_mystery_totem(root: Node3D, z: float, rng: RandomNumberGenerator, underground: bool) -> void:
	var mat: Material = _decor["crystal"] if underground or rng.randf() < 0.45 else _decor["lamp"]
	for i in 4:
		var s := 0.13 - float(i) * 0.018
		var b := Vector3(s, s, 0.055)
		_decor_box(root, b, Vector3(0, 0, z + 0.055 + float(i) * 0.070),
			mat, 45.0 * float(i), 0.0)
	for i in 3:
		_decor_box(root, Vector3(0.025, 0.20, 0.025),
			Vector3((float(i) - 1.0) * 0.15, 0, z + 0.14), _decor["pole"],
			rng.randf_range(-35.0, 35.0))

func _poly_rock_cluster(root: Node3D, z: float, rng: RandomNumberGenerator) -> void:
	for i in 5 + rng.randi() % 4:
		_decor_box(root, Vector3(rng.randf_range(0.07, 0.16), rng.randf_range(0.07, 0.16),
				rng.randf_range(0.12, 0.32)),
			Vector3(rng.randf_range(-0.22, 0.22), rng.randf_range(-0.18, 0.18), z + rng.randf_range(0.06, 0.16)),
			_decor["pebble"], rng.randf_range(0.0, 90.0), rng.randf_range(-12.0, 18.0))

# Re-opens a lost gate: a fresh pit appears in this newly generated chunk.
# Debug/manual: FORCE a descent hole at a world position (KEY_O) even through the
# unbreakable crust — flag the columns in range breakable, then blast them open,
# wide enough for the ship to dive through to the underground.
func open_hole_at(wx: float, wy: float, _kind_id: String = "") -> void:
	if not _has_underground:
		get_tree().call_group("star_hud", "show_message",
			"NO UNDERGROUND ON THIS WORLD", "SURFACE-RICH PLANET")
		return
	var r := 1.0
	for ch in _chunks:
		if not _chunk_is_active(ch):
			continue
		var node_y: float = (ch["node"] as Node3D).position.y
		if wy + r < node_y or wy - r > node_y + ROW_H:
			continue
		var br: PackedByteArray = ch["breakable"]
		for iy in ROWS_Y:
			var cy := node_y + (float(iy) + 0.5) * B
			if absf(cy - wy) > r:
				continue
			for ix in COLS_X:
				var cx := -WIDTH * 0.5 + (float(ix) + 0.5) * B
				if Vector2(cx, cy).distance_to(Vector2(wx, wy)) <= r:
					br[iy * COLS_X + ix] = 1
		ch["breakable"] = br
	for i in 4:
		blast(Vector3(wx + randf_range(-0.3, 0.3), wy + randf_range(-0.3, 0.3),
			ALT0_Z), randf_range(0.4, 0.6))
	clear_descent_shaft(wx, wy, r)
	get_tree().call_group("star_hud", "show_message",
		"HOLE OPENED (debug)", "DIVE THROUGH TO THE UNDERGROUND")

# Read-only: is the voxel cell at world (x,y,z) solid?
func _solid_at(x: float, y: float, z: float) -> bool:
	if x < -WIDTH * 0.5 or x >= WIDTH * 0.5:
		return false
	var iz := int((z - CELL_Z0) / B)
	if iz < 0 or iz >= NZ:
		return false
	for ch in _chunks:
		if not _chunk_is_active(ch):
			continue
		var ly: float = y - (ch["node"] as Node3D).position.y
		if ly < 0.0 or ly >= ROW_H:
			continue
		var ix := int((x + WIDTH * 0.5) / B)
		var iy := clampi(int(ly / B), 0, ROWS_Y - 1)
		return (ch["cells"][iy * COLS_X + ix] as PackedByteArray)[iz] != 0
	return false

# Blocks are solid for the ship (no damage, no pass-through): true when a ship of
# radius r at (x,y,z) overlaps a solid voxel cell. Used by Unit1 to stop at walls /
# pillars and to trigger the emergency climb when caught inside.
func collides(x: float, y: float, z: float, r: float) -> bool:
	for off: Vector2 in [Vector2.ZERO, Vector2(r, 0.0), Vector2(-r, 0.0),
			Vector2(0.0, r), Vector2(0.0, -r)]:
		if _solid_at(x + off.x, y + off.y, z):
			return true
	return false

# The arena's flank cave walls are a PERMANENT barrier: terrain-busting bolts stop on
# them and blast() spares them, while the central block field stays breakable. The |x|
# thresholds mirror the flank edges in _fill_diamond_column / _fill_boss_column.
func is_arena_wall(x: float) -> bool:
	if not _has_underground:
		return false
	var edge := absf(x)
	return edge > (2.6 if GameState.golden_walk else 3.0)

# True when (x,y) lies in the sealed relic-gate wall band. Bolts do NOT tunnel through this one
# the way they do the field — it stops them and only chips at close range (see Bullet), so the
# GERWALK has to press up against it and grind a passage rather than pre-drilling from afar.
func is_sealed_wall_at(x: float, y: float) -> bool:
	if not GameState.arena_wall_armed:
		return false
	if absf(x) > 2.6:   # flanks are the permanent cave wall, handled by is_arena_wall
		return false
	var rel := y - GameState.arena_wall_y
	return rel >= -0.1 and rel < ARENA_WALL_DEPTH + 0.1

# --- Leaving the atmosphere -----------------------------------------------------

# Leaving a planet for space is altitude-driven: climb to ALT1000. Returning
# from the underground is done by rising back up through a hole.

# Starts the legacy launch sequence, or returns immediately for seamless exits.
func begin_exit(_msg: String = "", _sub: String = "", _seamless: bool = true) -> void:
	if _exit_t >= 0 or GameState.in_transition():
		return
	_finish_exit(true)

func _run_exit() -> void:
	_exit_t += 1
	GameState.exit_anim = float(_exit_t) / float(EXIT_FRAMES)
	GameState.entry_glow = smoothstep(0.45, 0.9, float(_exit_t) / float(EXIT_FRAMES))
	if _exit_t >= EXIT_FRAMES:
		_finish_exit(false)

func _finish_exit(seamless: bool = false) -> void:
	GameState.star_exit = false
	GameState.entry_glow = 0.0 if seamless else 1.0
	GameState.exit_hold = 0.0
	GameState.exit_anim = 0.0
	if seamless:
		GameState.alt = GameState.ALT_MAX
		GameState.tAlt = GameState.ALT_MAX
	for grp in ["enemies", "enemy_bullets", "bullets"]:
		for n in get_tree().get_nodes_in_group(grp):
			n.queue_free()
	if _b.get("abyss", false) and GameState.abyss_return_biome != "":
		# Climbing out of an abyss returns to the planet surface above.
		GameState.stage = "planet"
		GameState.planet_biome = GameState.abyss_return_biome
		GameState.planet_seed = GameState.abyss_return_seed
		GameState.abyss_return_biome = ""
		GameState.pending_terrain = {"biome": GameState.planet_biome,
			"seed": GameState.planet_seed}
		get_tree().call_group("star_hud", "show_message",
			Loc.pair("%s の地表へ帰還", "BACK TO THE SURFACE OF %s") % GameState.planet_name, "")
		return  # Main swaps the terrain nodes (frees this one) next frame
	GameState.stage = "space"
	GameState.planet_name = ""
	GameState.planet_biome = ""
	GameState.surface_festival_planet = false
	GameState.planet_has_underground = false
	GameState.star_kind = ""
	if seamless:
		get_tree().call_group("star_hud", "show_message",
			"OPEN SPACE", "SEAMLESS ORBIT")
		queue_free()
		return
	for m in get_tree().get_nodes_in_group("mothership"):
		m.queue_free()
	get_tree().call_group("star_hud", "show_message",
		"BACK TO OPEN SPACE", "AIM THE SIGHT AT A STAR NAME AND CLICK TO TARGET")
	queue_free()

# --- Materials -------------------------------------------------------------------

func _make_materials() -> void:
	_ground_mat = StandardMaterial3D.new()
	_ground_mat.vertex_color_use_as_albedo = true
	_ground_mat.roughness = 0.95
	_ground_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Self-lit blocks (neon / crystal): unshaded so they read as glowing.
	var glow_sm := StandardMaterial3D.new()
	glow_sm.vertex_color_use_as_albedo = true
	glow_sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_sm.emission_enabled = true
	glow_sm.emission = Color(0.75, 0.18, 0.10)
	glow_sm.emission_energy_multiplier = 0.42
	glow_sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow_mat = glow_sm

	# Golden-walk arena: a richer dark-diamond grade. Faceted near-black bedrock with a faint
	# metallic sheen, and the glow blocks use the vox_glow shader so each lights in ITS OWN colour
	# (red lava, blue diamond) with per-block shimmer + veins — no single tint (which made the lava
	# pink) and far less flat mosaic.
	if GameState.golden_walk and GameState.arena_active:
		_ground_mat.roughness = 0.62
		_ground_mat.metallic = 0.10
		var gm := ShaderMaterial.new()
		gm.shader = load("res://shaders/vox_glow.gdshader")
		gm.set_shader_parameter("energy", 1.25)
		_glow_mat = gm


	# Animated water/lava/neon-canal surface: waves, swell and sparkle.
	var acc: Color = _b["accent"]
	acc = Color.from_hsv(fposmod(acc.h + _hue_shift * 0.5, 1.0), acc.s, acc.v)
	var glow: float = _b["water_glow"]
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = load("res://shaders/water_surface.gdshader")
	_water_mat.set_shader_parameter("base_color", Vector3(acc.r, acc.g, acc.b))
	_water_mat.set_shader_parameter("glow", maxf(glow, 0.25))
	_water_mat.set_shader_parameter("alpha", _b["water_alpha"])
	# Lava and thick neon flow slower than open water.
	_water_mat.set_shader_parameter("wave_speed", 0.35 if glow > 1.5 else 1.0)

	_cloud_mat = StandardMaterial3D.new()
	_cloud_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.22)
	_cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cloud_mesh = SphereMesh.new()
	_cloud_mesh.radius = 0.5
	_cloud_mesh.height = 1.0
	_cloud_mesh.radial_segments = 6
	_cloud_mesh.rings = 3

# Shared meshes/materials for small scenery voxels: houses, cars, street
# lamps, bushes and pebbles that dress up the block terrain.
func _make_decor() -> void:
	var wall := StandardMaterial3D.new()
	wall.albedo_color = _tint_c(Color(0.78, 0.70, 0.58))
	var roof := StandardMaterial3D.new()
	roof.albedo_color = _tint_c(Color(0.55, 0.20, 0.15))
	var pole := StandardMaterial3D.new()
	pole.albedo_color = Color(0.35, 0.37, 0.40)
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1.0, 0.85, 0.5)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.8, 0.45)
	lamp.emission_energy_multiplier = 2.2
	var bush := StandardMaterial3D.new()
	bush.albedo_color = _tint_c(Color(0.10, 0.28, 0.10))
	var trunk := StandardMaterial3D.new()
	trunk.albedo_color = _tint_c(Color(0.32, 0.20, 0.10))
	var pebble := StandardMaterial3D.new()
	pebble.albedo_color = Color(0.42, 0.40, 0.37)
	var shadow := StandardMaterial3D.new()
	shadow.albedo_color = Color(0.02, 0.025, 0.035, 0.42)
	shadow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Crystals are the "キラキラ" sparkle. On a dark world they are the brightest thing in
	# view, so they glow hard in the biome's own sparkle hue; on sunlit worlds they stay a
	# subtle tinted glint.
	# Golden-walk arena reads as a dark click-star, so its crystal decor glows hard like the
	# dim worlds (the BOSS biome it rides has no "dim" flag of its own).
	var dim := bool(_b.get("dim", false)) or (GameState.golden_walk and GameState.arena_active)
	var crystal := StandardMaterial3D.new()
	crystal.albedo_color = _b.get("sparkle", _tint_c(Color(0.55, 0.85, 1.0))) if dim \
		else _tint_c(Color(0.35, 0.85, 1.0))
	crystal.emission_enabled = true
	crystal.emission = crystal.albedo_color
	crystal.emission_energy_multiplier = 2.6 if dim else 0.8
	var lava := StandardMaterial3D.new()
	lava.albedo_color = Color(1.0, 0.25, 0.06)
	lava.emission_enabled = true
	lava.emission = Color(1.0, 0.18, 0.04)
	lava.emission_energy_multiplier = 1.1
	var sph := SphereMesh.new()
	sph.radius = 0.5
	sph.height = 1.0
	sph.radial_segments = 8
	sph.rings = 4
	var car_cols: Array = []
	for c: Color in [Color(0.8, 0.15, 0.1), Color(0.15, 0.4, 0.85),
			Color(0.9, 0.9, 0.92), Color(0.9, 0.75, 0.15)]:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = 0.4
		m.roughness = 0.35
		car_cols.append(m)
	var flower_cols: Array = []
	for c: Color in [Color(1.0, 0.5, 0.7), Color(1.0, 0.9, 0.3), Color(0.95, 0.95, 1.0)]:
		var fm := StandardMaterial3D.new()
		fm.albedo_color = c
		flower_cols.append(fm)
	var bb_cols: Array = []
	for c: Color in [Color(1.0, 0.3, 0.7), Color(0.2, 0.9, 1.0), Color(1.0, 0.8, 0.2)]:
		var bm := StandardMaterial3D.new()
		bm.albedo_color = c * 0.4
		bm.emission_enabled = true
		bm.emission = c
		bm.emission_energy_multiplier = 1.8
		bb_cols.append(bm)
	_decor = {"wall": wall, "roof": roof, "pole": pole, "lamp": lamp,
		"bush": bush, "trunk": trunk, "pebble": pebble, "shadow": shadow,
		"crystal": crystal, "lava": lava,
		"cars": car_cols,
		"flowers": flower_cols, "billboards": bb_cols,
		"box": BoxMesh.new(), "sphere": sph}

func _tint_c(c: Color) -> Color:
	return Color.from_hsv(fposmod(c.h + _hue_shift, 1.0), c.s, c.v)

func _decor_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		rot_z: float = 0.0, rot_x: float = 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _decor["box"]
	mi.scale = size
	mi.position = pos
	mi.rotation_degrees = Vector3(rot_x, 0.0, rot_z)
	mi.material_override = mat
	parent.add_child(mi)
	if bool(parent.get_meta("destructible_structure", false)):
		_decor_blocks.append({"node": mi, "res": parent.get_meta("drop_res", "ALLOY"),
			"color": parent.get_meta("drop_color", Color(0.55, 0.55, 0.60))})

# --- Seeded noise -----------------------------------------------------------------

func _hash2(ix: int, iy: int) -> float:
	var n: int = ix * 374761393 + iy * 668265263 + seed_v * 1013904223
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0xFFFFF) / 1048575.0

func _vnoise(x: float, y: float) -> float:
	var ix := floori(x)
	var iy := floori(y)
	var fx := x - float(ix)
	var fy := y - float(iy)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := _hash2(ix, iy)
	var b := _hash2(ix + 1, iy)
	var c := _hash2(ix, iy + 1)
	var d := _hash2(ix + 1, iy + 1)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)

# --- Column generation (deterministic per seed + global block coords) -------------

# Local biome region for a column, from large-scale warped noise bands.
func _region(gx: float, gy: float) -> String:
	var r := _vnoise(gx * _rscale + 31.7, gy * _rscale)
	r = clampf(r + (_vnoise(gx * 0.23, gy * 0.23 + 9.0) - 0.5) * 0.18, 0.0, 0.999)
	var target := r * _r_total
	for i in _r_cum.size():
		if target < _r_cum[i]:
			return _r_kinds[i]
	return _r_kinds[_r_kinds.size() - 1]

# One full vertical voxel column (NZ cells, cells[iz]=0 means empty/air):
# alt0 FLOOR + rock PILLARS rising toward the crust (gaps = flyable corridors),
# the solid CRUST at the surface base, and the surface RELIEF rising into the sky.
# ONE continuous block field — no second terrain, no fade.
func _gen_column(bx: int, by: int, out_water: Array) -> PackedByteArray:
	var cells := PackedByteArray()
	cells.resize(NZ)
	var sgx := (float(bx) + 0.5) * B - WIDTH * 0.5
	var sgy := (float(by) + 0.5) * B
	# Boss ARENA = cave ONLY: skip every bit of overhead surface relief (the voxel
	# surface is legacy and unused — the real surface is the TargetPlanet sphere),
	# both to fix "starts on the surface" and to drop that generation/mesh cost. The
	# chamber is capped by just a crust CEILING; the vault is built below.
	if not _has_underground:
		# Non-arena voxel terrain (not instantiated in live play) keeps the old surface.
		var surf := _surface_stack(bx, by, out_water)
		for L in surf.size():
			var iz := IZ_SURF + L
			if iz < NZ:
				cells[iz] = surf[L]
		return cells
	# No solid crust ceiling plane here — a full ROCK lid read as a "surface grid"
	# when the ship rose near it. The vault is open-topped into the dark cavern void;
	# the altitude clamp (ARENA_CEIL_ALT) keeps the ship inside.
	var ug := _underground_kind(sgx, sgy)
	cells[0] = _underground_floor(ug)
	if ug == "boss":
		_fill_boss_column(cells, sgx, sgy)
	elif ug == "diamond":
		_fill_diamond_column(cells, sgx, sgy)
	else:
		var pn := _vnoise(sgx * 0.46, sgy * 0.46)
		var dn := _vnoise(sgx * 1.15 + 19.0, sgy * 1.15 + 43.0)
		if pn > 0.48:
			var mound_t := clampf((pn - 0.48) / 0.52, 0.0, 1.0)
			var ph: int = clampi(2 + int(mound_t * 5.0) + int(dn * 2.0), 2, 9)
			for iz in range(1, ph):
				cells[iz] = _underground_wall(ug, iz, ph, dn)
	if _has_oopart_tile(bx, by):
		cells[1] = OOPART_BLOCK
		cells[2] = OOPART_BLOCK
		for iz in range(3, mini(IZ_SURF, 18)):
			cells[iz] = 0
	return cells

func _fill_diamond_column(cells: PackedByteArray, sgx: float, sgy: float) -> void:
	# Relic hunt gate: once 3 relics are dug up, a thick breakable wall fills a band across
	# the whole arena, with an open cavern cleared just beyond it. Both override the normal
	# field for the rows they cover. (The terrain ahead of the player is generated fresh, so
	# arming the wall before its chunks spawn is what makes it "frame in" from the top.)
	if GameState.arena_wall_armed:
		# Compare in WORLD-y: noise sgy and the live collision/player y differ by the chunk
		# offset (see _row_top_y → _col_world_y), so arming uses GameState.py (world) directly.
		var rel := _col_world_y(sgy) - GameState.arena_wall_y
		if rel >= 0.0 and rel < ARENA_WALL_DEPTH:
			for iz in range(1, ARENA_WALL_HEIGHT + 1):
				cells[iz] = OBSIDIAN   # sealed barrier — breakable, but a long bore
			return
		if rel >= ARENA_WALL_DEPTH and rel < ARENA_WALL_DEPTH + ARENA_CAVERN_LEN:
			return   # cavern clearing beyond the wall: open floor only (cells[0] already set)
	# Dark click-star DIAMOND cave (golden-walk arena). Undulating bedrock studded with
	# glowing diamonds and NO flat patches anywhere — every column carries rolling relief,
	# framed by rough, blocky cave walls toward the flanks. Random per entry (_arena_phase).
	var ph := _arena_phase
	var base_n := _vnoise(sgx * 0.60 + ph, sgy * 0.60 - ph)
	var fine_n := _vnoise(sgx * 1.90 - ph, sgy * 1.90 + ph)
	var roll_n := _vnoise(sgx * 0.32 + ph * 0.4, sgy * 0.32)
	var edge := absf(sgx)
	# Rolling ground EVERYWHERE — always at least a couple of blocks, never a flat plane.
	var ground_h := 3 + int(base_n * 6.0) + int(fine_n * 4.0)
	if edge > 2.6:
		if edge >= 6.0:
			return   # off-screen flank: leave empty (hidden by the distance fog)
		# Rough cave walls climbing toward the flanks: uneven buttresses + chimneys.
		var rise := (edge - 2.6) * 5.2
		var bump := _vnoise(sgx * 1.25 + ph, sgy * 1.25 + ph * 0.7) * 22.0
		ground_h = clampi(ground_h + int(rise + bump), 6, 58)
	else:
		# Centre play zone: chunkier rolling dunes + MORE frequent tall spires — a real 3D field
		# of blocks to weave through and blast apart.
		ground_h = clampi(ground_h + int(roll_n * 10.0), 3, 22)
		var spire := _vnoise(sgx * 0.95 + ph + 5.0, sgy * 0.95 + ph)
		if spire > 0.72:
			ground_h = clampi(24 + int((spire - 0.72) / 0.28 * 28.0), 24, 52)
	for iz in range(1, ground_h + 1):
		var dn := _vnoise(sgx * 2.30 + float(iz) * 0.7, sgy * 2.30 - float(iz) * 0.7)
		cells[iz] = _underground_wall("diamond", iz, ground_h, dn)

func _fill_boss_column(cells: PackedByteArray, sgx: float, sgy: float) -> void:
	# Boss ARENA: BUMPY filled side walls frame a fairly open centre. Random per entry
	# (_arena_phase). The flanks (|x|>3) are FILLED with rough rolling blocky relief (no
	# sparse void); the centre has only MODEST low bumps. Beyond |x|=6 is empty (off-screen,
	# hidden by the distance fog).
	var ph := _arena_phase
	var floor_n := _vnoise(sgx * 1.8 + ph, sgy * 1.8 - ph)
	cells[1] = UG_GLYPH if floor_n > 0.88 else (UG_EMBER if floor_n < 0.08 else _underground_wall("boss", 1, 2, 1.0))
	var edge := absf(sgx)
	if edge > 3.0:
		if edge >= 6.0:
			return   # off-screen flank: leave empty
		# Rough carved wall: high uneven buttresses and chimneys, not a flat side plane.
		var rise := (edge - 3.0) * 4.4
		var bump := _vnoise(sgx * 1.3 + ph, sgy * 1.3 + ph * 0.7) * 22.0
		var tooth := _vnoise(sgx * 3.7 - ph, sgy * 2.6 + ph)
		var wh := clampi(8 + int(rise + bump + tooth * 16.0), 5, 58)
		var nv := _vnoise(sgx * 0.5 + ph, sgy * 0.5)
		for iz in range(1, wh + 1):
			cells[iz] = _underground_wall("boss", iz, wh, nv)
	else:
		# Centre play zone: sparse tall pillars. The arena has no enemy swarm, so large
		# sculptural columns can safely create a real cavern skyline.
		var pn := _vnoise(sgx * 0.9 + ph + 5.0, sgy * 0.9 + ph)
		if pn > 0.80:
			var h_t := clampf((pn - 0.80) / 0.20, 0.0, 1.0)
			var sh := clampi(22 + int(h_t * 28.0), 22, 52)
			for iz in range(1, sh + 1):
				cells[iz] = _underground_wall("boss", iz, sh, h_t)

func restore_boss_area_to_normal() -> void:
	for ch in _chunks:
		if not _chunk_is_active(ch):
			continue
		var any := false
		var cells_arr: Array = ch["cells"]
		for iy in ROWS_Y:
			for ix in COLS_X:
				var ci := iy * COLS_X + ix
				var col: PackedByteArray = cells_arr[ci]
				for iz in range(1, IZ_SURF):
					if col[iz] == BOSS_BLOCK:
						col[iz] = ROCK if iz == 1 else 0
						any = true
				cells_arr[ci] = col
		if any:
			ch["dirty"] = true

func _has_oopart_tile(bx: int, by: int) -> bool:
	if GameState.underground_boss_area or GameState.underground_boss_defeated:
		return false
	var gx := floori(float(bx) / 18.0)
	var gy := floori(float(by) / 18.0)
	if _hash2(gx * 91 + 17, gy * 97 + 31) > 0.72:
		return false
	var ox := 4 + int(_hash2(gx * 43 + 5, gy * 47 + 9) * 8.0)
	var oy := 4 + int(_hash2(gx * 53 + 7, gy * 59 + 13) * 8.0)
	var lx := posmod(bx, 18)
	var ly := posmod(by, 18)
	return lx >= ox and lx <= ox + 5 and ly >= oy and ly <= oy + 5

func _oopart_tile_key(bx: int, by: int) -> String:
	return "%d:%d" % [floori(float(bx) / 18.0), floori(float(by) / 18.0)]

func _reveal_oopart_tile(col: PackedByteArray, bx: int, by: int) -> bool:
	# Only an UNDISCOVERED (blue) tile is a real change. An already-found tile must
	# return false: reveal_oopart_near() runs EVERY FRAME underground (Unit1), so
	# returning true here re-dirtied the chunk every frame while lingering near a
	# revealed oopart → a full remesh per frame (the "FPS drops when colouring
	# ooparts" hitch). No blue block to flip ⇒ nothing changed ⇒ no remesh.
	if col[1] != OOPART_BLOCK and col[2] != OOPART_BLOCK:
		return false
	col[1] = OOPART_FOUND_BLOCK
	col[2] = OOPART_FOUND_BLOCK
	var key := _oopart_tile_key(bx, by)
	if not GameState.underground_oopart_found_keys.has(key):
		GameState.underground_oopart_found_keys[key] = true
		GameState.underground_ooparts = mini(GameState.underground_ooparts + 1, 3)
		if GameState.underground_ooparts >= 3:
			GameState.underground_boss_unlocked = true
			GameState.underground_boss_defeated = false
			GameState.underground_boss_area = true
			GameState.underground_biome = "BASE"
		get_tree().call_group("star_hud", "show_message",
			Loc.pair("オーパーツタイル露出  %d / 3", "OOPART TILE REVEALED  %d / 3") % GameState.underground_ooparts,
			"BOSS AREA SIGNAL - PROCEED DEEPER" if GameState.underground_boss_unlocked else "")
	return true

func reveal_oopart_near(x: float, y: float, radius: float, z: float) -> void:
	if GameState.underground_boss_unlocked:
		return
	var tile_z := CELL_Z0 + 2.5 * B
	if absf(z - tile_z) > 1.25:
		return
	for ch in _chunks:
		if not _chunk_is_active(ch):
			continue
		var node_y: float = (ch["node"] as Node3D).position.y
		if y + radius < node_y or y - radius > node_y + ROW_H:
			continue
		var any := false
		for iy in ROWS_Y:
			var cy := node_y + (float(iy) + 0.5) * B
			if absf(cy - y) > radius:
				continue
			for ix in COLS_X:
				var cx := -WIDTH * 0.5 + (float(ix) + 0.5) * B
				if Vector2(cx, cy).distance_to(Vector2(x, y)) > radius:
					continue
				var ci := iy * COLS_X + ix
				var col: PackedByteArray = ch["cells"][ci]
				var bx := ix
				var by := int(ch["idx"]) * ROWS_Y + iy
				if _reveal_oopart_tile(col, bx, by):
					ch["cells"][ci] = col
					any = true
		if any:
			ch["dirty"] = true

func oopart_signal_near(x: float, y: float, radius: float) -> float:
	var best := 0.0
	for ch in _chunks:
		if not _chunk_is_active(ch):
			continue
		var node_y: float = (ch["node"] as Node3D).position.y
		if y + radius < node_y or y - radius > node_y + ROW_H:
			continue
		var cells: Array = ch["cells"]
		for iy in ROWS_Y:
			var cy := node_y + (float(iy) + 0.5) * B
			if absf(cy - y) > radius:
				continue
			for ix in COLS_X:
				var cx := -WIDTH * 0.5 + (float(ix) + 0.5) * B
				var d := Vector2(cx, cy).distance_to(Vector2(x, y))
				if d > radius:
					continue
				var col: PackedByteArray = cells[iy * COLS_X + ix]
				if col[1] == OOPART_BLOCK:
					best = maxf(best, 1.0 - d / radius)
				elif col[1] == OOPART_FOUND_BLOCK:
					best = maxf(best, (1.0 - d / radius) * 0.35)
	return best

func _underground_kind(gx: float, gy: float) -> String:
	# Golden-walk arena: a dark click-star floor — near-black rock with embedded glowing
	# diamonds — instead of the red boss-core greeble. (Scoped to golden_walk so the real
	# boss duel keeps its OMEGA-CORE look.)
	if GameState.golden_walk and GameState.arena_active:
		return "diamond"
	if GameState.underground_boss_area:
		return "boss"
	return _underground_kind_id

func _pick_underground_kind(rng: RandomNumberGenerator) -> String:
	var kinds := ["cave", "magma", "lake", "ruins", "temple", "base"]
	return kinds[rng.randi() % kinds.size()]

func _enemy_theme_for_underground(kind: String) -> String:
	match kind:
		"magma":
			return "LAVACAVE"
		"lake":
			return "LAKE"
		"ruins":
			return "RUINS"
		"temple":
			return "TEMPLE"
		"base", "boss":
			return "BASE"
		_:
			return "CAVE"

func _underground_floor(kind: String) -> int:
	match kind:
		"magma":
			return UG_MAGMA  # glowing lava bed
		"lake":
			return GLASS
		"ruins":
			return FORT
		"temple":
			return SAND
		"base":
			return CITY
		"boss":
			return BOSS_BLOCK
		"diamond":
			return ROCK  # near-black bedrock; the glowing diamonds sit IN it (see _underground_wall)
		_:
			return ROCK

func _underground_wall(kind: String, iz: int, ph: int, noise_v: float) -> int:
	# noise_v is the per-column value-noise (0..1): gating accents by it makes the
	# emissive veins SPARSE (scattered glowing pillars) so dark rock still dominates.
	match kind:
		"magma":
			return UG_MAGMA if iz == 1 or (iz == ph - 1 and noise_v > 0.62) else ROCK
		"lake":
			return UG_ALGAE if iz <= 2 and noise_v > 0.45 else ROCK
		"ruins":
			return UG_EMBER if iz == 1 and noise_v > 0.5 else (FORT if iz % 3 == 0 else ROCK)
		"temple":
			return UG_GLYPH if iz % 4 == 1 else (SAND if iz == ph - 1 else STONE)
		"base":
			return UG_NEON if iz == ph - 1 and noise_v > 0.58 else (CITY if iz % 2 == 0 else FORT)
		"boss":
			# Greebled spire surface: glowing base/cap + scattered glow blocks, dark
			# recesses and grey blocks among the dark FORT — so it isn't a flat wall.
			if iz == 1 or iz == ph - 1:
				return BOSS_BLOCK
			var hsh := iz * 7 + int(noise_v * 130.0)
			if hsh % 6 == 0:
				return BOSS_BLOCK   # scattered glowing studs
			if hsh % 5 == 0:
				return ROCK         # dark recess
			if hsh % 4 == 0:
				return STONE        # grey block variation
			return FORT
		"diamond":
			# Dark click-star VARIETY (no more black/white zebra): mostly dark bedrock and glossy
			# obsidian, with embedded transparent diamonds (blue glow) and the odd red-glowing
			# lava vein scattered through.
			if noise_v > 0.84:
				return UG_CRYSTAL   # transparent diamond — blue-white glow
			if noise_v > 0.76:
				return UG_EMBER     # red-glowing lava vein
			if noise_v > 0.44:
				return OBSIDIAN     # glossy black obsidian
			return ROCK             # dark bedrock
		_:  # cave — scattered glowing crystal pillars among dark rock
			return UG_CRYSTAL if noise_v > 0.80 else ROCK

# Surface-relief block stack (from GROUND_Z up): hills, cities, water, structures.
func _surface_stack(bx: int, by: int, out_water: Array) -> Array:
	var gx := (float(bx) + 0.5) * B - WIDTH * 0.5
	var gy := (float(by) + 0.5) * B
	var region := _region(gx, gy)
	var hn := _vnoise(gx * 0.35, gy * 0.35) * 0.65 \
		+ _vnoise(gx * 0.9 + 13.0, gy * 0.9 + 7.0) * 0.35
	var ridge := 1.0 - absf(hn * 2.0 - 1.0)
	var sh := _hash2(bx * 3 + 7, by * 5 + 11)  # structure dice
	var water := false
	var h: int

	match region:
		"sea":
			h = 1
			water = true
		"river":
			if absf(_vnoise(gx * 0.15 + 71.0, gy * 0.15) - 0.5) < 0.08:
				h = 1
				water = true
			else:
				h = 2 + int(hn * 2.5)
				region = "plains"
		"mountain":
			# Sharply peaked ranges; the tallest summits block low-alt flight.
			h = clampi(3 + int(ridge * ridge * 13.0 * _relief), 3, MAX_H - 1)
		"canyon":
			# High plateau split by chasms cutting all the way down.
			h = clampi(int(10.0 * minf(_relief, 1.3)) - int(ridge * 13.0 * _relief), 1, MAX_H - 2)
		"snow":
			h = 2 + int(hn * 3.5 * _relief)
		"city":
			h = 1
		"fortress":
			h = 2
		"lava":
			h = 1 + int(ridge * 4.5)
			if h <= 1:
				water = true  # lava pool (rendered with the glowing accent material)
		"cloud":
			var band := 0.5 + 0.5 * sin(gy * 0.5 + hn * 2.0)
			h = 1 + int(band * 2.5)
		_:
			h = 2 + int(hn * 2.5)  # plains / forest / desert / ice / crystal

	# Rivers wind across any land region (lava rivers on volcanic worlds),
	# with sandy banks hugging the waterline.
	var bank := false
	if _river_w > 0.0 and region != "cloud":
		var riv := absf(_vnoise(gx * 0.11 + 71.0, gy * 0.11) - 0.5)
		if not water and riv < _river_w:
			h = 1
			water = true
		elif not water and riv < _river_w * 2.2:
			bank = true

	# Road grid: asphalt strips across the lowlands; where they cross water
	# they ride on as causeway bridges above the surface.
	if _road_col(bx, by, region):
		var stack_r: Array = []
		for i in ROAD_H:
			stack_r.append(ROAD)
		out_water[0] = water and int(_b["water_level"]) > 0
		return stack_r

	var stack: Array = []
	for level in h:
		stack.append(_ground_block(region, level, h))
	if bank and not water and not stack.is_empty() \
			and (region == "plains" or region == "forest" or region == "snow"):
		stack[stack.size() - 1] = SAND  # river beach
	if not water:
		_add_structure(region, sh, stack, bx, by)
	out_water[0] = water and int(_b["water_level"]) > 0
	return stack

# Is this column part of the road network? Dense grid through built-up
# regions, sparse highways elsewhere; never through peaks, chasms or clouds.
func _road_col(bx: int, by: int, region: String) -> bool:
	if not _roads_on:
		return false
	if region == "mountain" or region == "canyon" or region == "cloud" or region == "lava":
		return false
	var m := 14 if (region == "city" or region == "fortress") else 26
	return posmod(bx, m) < 2 or posmod(by, m) < 2

func _ground_block(region: String, level: int, h: int) -> int:
	match region:
		"desert":
			return SAND
		"sea":
			return SAND
		"mountain":
			if level == h - 1 and h >= 8:
				return SNOW
			return ROCK if level % 4 == 1 else STONE  # rocky strata bands
		"canyon":
			return SAND if level % 3 == 2 else STONE
		"snow":
			return SNOW if level == h - 1 else (DIRT if level == h - 2 else STONE)
		"city":
			return CITY
		"fortress":
			return FORT
		"lava":
			return ROCK
		"cloud":
			return CLOUD
		"ice":
			return ICE
		"crystal":
			return ICE if level == h - 1 else STONE
		_:  # plains / forest / river-bank
			if level == h - 1:
				return GRASS
			return DIRT if level == h - 2 else STONE

# Trees, towers, fortress walls, crystal spikes... appended onto the stack.
func _add_structure(region: String, sh: float, stack: Array, bx: int, by: int) -> void:
	var gx := (float(bx) + 0.5) * B - WIDTH * 0.5
	var gy := (float(by) + 0.5) * B
	match region:
		"forest":
			# Trees clump into dense groves with open clearings between.
			var grove := clampf((_vnoise(gx * 0.16 + 5.0, gy * 0.16) - 0.32) * 2.2, 0.0, 1.0)
			if sh < 0.20 * _dens * grove:
				_push(stack, WOOD, 2 + (int(sh * 1000.0) % 2))
				_push(stack, LEAF, 2)
		"plains":
			if sh < 0.012 * _dens:
				_push(stack, WOOD, 2)
				_push(stack, LEAF, 2)
		"snow":
			if sh < 0.02 * _dens:
				_push(stack, WOOD, 2)
				_push(stack, SNOW, 1)
		"desert":
			if sh < 0.015 * _dens:
				_push(stack, STONE, 2)
		"city":
			# Districts: pocket parks (lawn + trees), a downtown core where
			# fat 2x2-footprint towers spike into the mid-altitude band, and
			# low suburbs that the decor houses fill in. Mixed facades
			# (concrete / dark steel / glass), some neon-capped.
			var park := _vnoise(gx * 0.06 + 41.0, gy * 0.06)
			var dt := clampf((_vnoise(gx * 0.09 + 7.0, gy * 0.09) - 0.25) * 1.6, 0.0, 1.0)
			var bh := _hash2((bx >> 1) * 5 + 1, (by >> 1) * 9 + 2)
			if park > 0.76:
				stack[stack.size() - 1] = GRASS
				if sh < 0.06 * _dens:
					_push(stack, WOOD, 2)
					_push(stack, LEAF, 2)
			elif dt > 0.30:
				if bh < (0.18 + 0.22 * dt) * _dens:
					var pick := int(bh * 1000.0) % 3
					var bld := CITY if pick == 0 else (FORT if pick == 1 else GLASS)
					var maxh := maxi(4, 3 + int(11.0 * dt))
					_push(stack, bld, 3 + int(bh * 470.0) % maxh)
					if _hash2(bx * 3, by + 99) < 0.4:
						_push(stack, NEON, 1)
				elif sh < 0.10 * _dens:
					_push(stack, NEON, 2)
			else:
				# Suburbs: sparse low blocks; small houses arrive as decor.
				if bh < 0.15 * _dens:
					_push(stack, CITY, 1 + int(bh * 300.0) % 2)
		"fortress":
			# Walled compounds offset between the roads, with tall corner keeps.
			var mx := posmod(bx + 7, 14)
			var my := posmod(by + 7, 14)
			if mx <= 1 or my <= 1:
				_push(stack, FORT, 6 if (mx <= 1 and my <= 1) else 4)
			elif sh < 0.03:
				_push(stack, FORT, 2)  # inner keep blocks
		"crystal":
			if sh < 0.06 * _dens:
				_push(stack, CRYSTAL, 2 + (int(sh * 500.0) % 3))
		"ice":
			if sh < 0.02 * _dens:
				_push(stack, CRYSTAL, 2)
		"mountain":
			pass
		"lava":
			if sh < 0.04 * _dens:
				_push(stack, ROCK, 3)

func _push(stack: Array, bid: int, n: int) -> void:
	for i in n:
		if stack.size() >= MAX_H:
			return
		stack.append(bid)

# Deterministic water test for seam neighbours (mirrors _gen_column's rules).
func _is_water_col(bx: int, by: int) -> bool:
	if int(_b["water_level"]) <= 0:
		return false
	var gx := (float(bx) + 0.5) * B - WIDTH * 0.5
	var gy := (float(by) + 0.5) * B
	var region := _region(gx, gy)
	if region == "cloud":
		return false
	var water := false
	match region:
		"sea":
			water = true
		"river":
			water = absf(_vnoise(gx * 0.15 + 71.0, gy * 0.15) - 0.5) < 0.08
		"lava":
			var hn := _vnoise(gx * 0.35, gy * 0.35) * 0.65 \
				+ _vnoise(gx * 0.9 + 13.0, gy * 0.9 + 7.0) * 0.35
			water = (1 + int((1.0 - absf(hn * 2.0 - 1.0)) * 4.5)) <= 1
	if not water and _river_w > 0.0 \
			and absf(_vnoise(gx * 0.11 + 71.0, gy * 0.11) - 0.5) < _river_w:
		water = true
	return water

# Ground-only height for seam neighbors in the next/previous chunk (structures
# ignored — their missing side faces at seams are practically invisible).
const CORRIDOR_HALF := 0.9   # underground: half-width of the flyable cave passage (world units;
							 # well under the ±2.4 view so rock walls fill most of the screen)

# UNDERGROUND cave column height: a wandering vertical corridor the ship flies,
# framed by tall rock WALLS on both sides that rise to the crust. Collision/mesh
# render and block these tall side stacks unchanged.
func _cave_h(gx: float, gy: float) -> int:
	var cx := (_vnoise(gy * 0.03, 7.3) - 0.5) * 1.5             # passage center gently wanders in x
															   # (kept near center so walls frame both sides)
	var dist := absf(gx - cx)
	if dist < CORRIDOR_HALF:
		return 1 + int(_vnoise(gx * 0.5, gy * 0.5) * 2.5)        # open floor, 1..3 high
	var t := clampf((dist - CORRIDOR_HALF) / 2.0, 0.0, 1.0)      # wall ramps up to the crust
	return clampi(4 + int(t * float(MAX_H - 5)) + int(_vnoise(gx * 0.6, gy * 0.6) * 2.0),
		4, MAX_H - 1)

func _ground_h(bx: int, by: int) -> int:
	var gx := (float(bx) + 0.5) * B - WIDTH * 0.5
	var gy := (float(by) + 0.5) * B
	var region := _region(gx, gy)
	var hn := _vnoise(gx * 0.35, gy * 0.35) * 0.65 \
		+ _vnoise(gx * 0.9 + 13.0, gy * 0.9 + 7.0) * 0.35
	var ridge := 1.0 - absf(hn * 2.0 - 1.0)
	var h: int
	match region:
		"sea": h = 1
		"river": h = 1 if absf(_vnoise(gx * 0.15 + 71.0, gy * 0.15) - 0.5) < 0.08 else 2 + int(hn * 2.5)
		"mountain": h = clampi(3 + int(ridge * ridge * 13.0 * _relief), 3, MAX_H - 1)
		"canyon": h = clampi(int(10.0 * minf(_relief, 1.3)) - int(ridge * 13.0 * _relief), 1, MAX_H - 2)
		"snow": h = 2 + int(hn * 3.5 * _relief)
		"city": h = 1
		"fortress": h = 2
		"lava": h = 1 + int(ridge * 4.5)
		"cloud": h = 1 + int((0.5 + 0.5 * sin(gy * 0.5 + hn * 2.0)) * 2.5)
		_: h = 2 + int(hn * 2.5)
	if _river_w > 0.0 and region != "cloud" \
			and absf(_vnoise(gx * 0.11 + 71.0, gy * 0.11) - 0.5) < _river_w:
		h = 1
	if _road_col(bx, by, region):
		h = ROAD_H
	return h

# --- Chunk lifecycle ----------------------------------------------------------------

func _spawn_chunk() -> void:
	var node := Node3D.new()
	node.position = Vector3(0.0, _row_top_y(), 0.0)
	add_child(node)
	var mi := MeshInstance3D.new()
	node.add_child(mi)

	var cells: Array = []   # per column: PackedByteArray(NZ) of block ids (0 = empty)
	var water := PackedByteArray()
	water.resize(COLS_X * ROWS_Y)
	var breakable := PackedByteArray()
	breakable.resize(COLS_X * ROWS_Y)
	var wflag := [false]
	for iy in ROWS_Y:
		for ix in COLS_X:
			var by := _next_row * ROWS_Y + iy
			var ci := iy * COLS_X + ix
			cells.append(_gen_column(ix, by, wflag))
			water[ci] = 1 if wflag[0] else 0
			# Rare breakable-crust cluster (the only descent points). Organic
			# noise patches that span chunk seams; invisible to the player.
			if _abyss_enabled and not wflag[0] \
					and _vnoise(float(ix) * BREAK_FREQ, float(by) * BREAK_FREQ) > BREAK_THRESH:
				breakable[ci] = 1

	var ch := {"node": node, "mi": mi, "cells": cells, "water": water,
		"breakable": breakable, "decor": {}, "enemy_front": {}, "dirty": false, "idx": _next_row}
	_chunks.append(ch)
	_rebuild_mesh(ch)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 92821 + _next_row
	var decor_chance := 1.0 if _surface_festival else (0.18 if _quiet_surface else 0.72)
	if not _b.get("abyss", false) and not _b.get("boss", false) and rng.randf() < decor_chance:
		_add_decor(ch, _next_row, rng)
	if _surface_festival:
		if rng.randf() < 0.38:
			_add_surface_landmark(ch, _next_row, rng)
		var large_count := 1
		if rng.randf() < 0.18:
			large_count += 1
		for i in large_count:
			var theme := 6 if (_next_row % 6 == 2 and i == 0) else ((rng.randi() + _next_row + i * 3) % 8)
			_add_large_block_structure(ch, _next_row, rng, false, theme)
		if rng.randf() < 0.26:
			_add_poly_structure(ch, _next_row, rng, false)
	elif _quiet_surface and rng.randf() < 0.26:
		_add_large_block_structure(ch, _next_row, rng, false)
	if _has_underground and rng.randf() < (0.96 if _quiet_surface else 0.42):
		_add_underground_landmark(ch, _next_row, rng)
	if _has_underground:
		var ug_large := 0
		if rng.randf() < (0.88 if _quiet_surface else 0.30):
			ug_large += 1
		if _quiet_surface and rng.randf() < 0.46:
			ug_large += 1
		for i in ug_large:
			_add_large_block_structure(ch, _next_row, rng, true)
		if rng.randf() < (0.52 if _quiet_surface else 0.20):
			_add_poly_structure(ch, _next_row, rng, true)

	# Drifting cloud puffs in the air layers — flying high puts the player
	# above (or through) them, with the fogged ground far below.
	if rng.randf() < _cloud_chance:
		var n_puffs := 1
		for i in n_puffs:
			var puff := MeshInstance3D.new()
			puff.mesh = _cloud_mesh
			puff.material_override = _cloud_mat
			puff.scale = Vector3(rng.randf_range(0.8, 1.9), rng.randf_range(0.3, 0.6), 0.2)
			puff.position = Vector3(rng.randf_range(-WIDTH * 0.4, WIDTH * 0.4),
				rng.randf_range(0.0, ROW_H), rng.randf_range(-1.2, 0.6))
			node.add_child(puff)
	_next_row += 1

# --- Meshing: exposed faces only, flat shaded, vertex colors -------------------------

# Exposed-face voxel meshing. Vertical runs of the same block id are merged into
# tall quads, which keeps the deep alt1000 underground cheap to render.
# Direct mesh buffer — accumulates triangles into packed arrays and commits one
# ArrayMesh surface. Replaces SurfaceTool, which is ~3-8× slower (per-vertex call
# + dedup overhead); the full-chunk remesh on every block destroyed was the main
# CPU cost (esp. dense underground). Vertices are NOT deduplicated (flat-shaded
# voxel faces don't share), so a plain index list per quad is all we need.
class _Buf extends RefCounted:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var tris := PackedInt32Array()

	# Quad a,b,c,d (matching the old _quad winding: tris a,b,c + a,c,d), one color.
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3, col: Color) -> void:
		var base := verts.size()
		verts.push_back(a); verts.push_back(b); verts.push_back(c); verts.push_back(d)
		norms.push_back(nrm); norms.push_back(nrm); norms.push_back(nrm); norms.push_back(nrm)
		cols.push_back(col); cols.push_back(col); cols.push_back(col); cols.push_back(col)
		tris.push_back(base); tris.push_back(base + 1); tris.push_back(base + 2)
		tris.push_back(base); tris.push_back(base + 2); tris.push_back(base + 3)

	# Same quad with a per-corner color (for ambient occlusion).
	func quad4(a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3,
			ca: Color, cb: Color, cc: Color, cd: Color) -> void:
		var base := verts.size()
		verts.push_back(a); verts.push_back(b); verts.push_back(c); verts.push_back(d)
		norms.push_back(nrm); norms.push_back(nrm); norms.push_back(nrm); norms.push_back(nrm)
		cols.push_back(ca); cols.push_back(cb); cols.push_back(cc); cols.push_back(cd)
		tris.push_back(base); tris.push_back(base + 1); tris.push_back(base + 2)
		tris.push_back(base); tris.push_back(base + 2); tris.push_back(base + 3)

	func commit_to(mesh: ArrayMesh, mat: Material) -> void:
		if tris.is_empty():
			return
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = tris
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)

func _rebuild_mesh(ch: Dictionary) -> void:
	var st := _Buf.new()
	var st_glow := _Buf.new()
	var st_water := _Buf.new()

	var cells: Array = ch["cells"]
	var idx: int = ch["idx"]
	var water_arr: PackedByteArray = ch["water"]
	var wlevel := int(_b["water_level"])
	var water_z := GROUND_Z + float(wlevel) * B

	for iy in ROWS_Y:
		for ix in COLS_X:
			var ci := iy * COLS_X + ix
			var col_cells: PackedByteArray = cells[ci]
			var x0 := -WIDTH * 0.5 + float(ix) * B
			var y0 := float(iy) * B
			var by := idx * ROWS_Y + iy
			var jitter := 1.0 - _jitter_amp * 0.5 \
				+ _jitter_amp * _hash2(ix * 13 + 1, by * 29 + 5)
			var iz := 0
			while iz < NZ:
				var id: int = col_cells[iz]
				if id == 0:
					iz += 1
					continue
				var run0 := iz
				while iz + 1 < NZ and col_cells[iz + 1] == id:
					iz += 1
				var run1 := iz
				iz += 1
				var z0 := CELL_Z0 + float(run0) * B
				var z1 := CELL_Z0 + float(run1 + 1) * B
				var target := st_glow if bool(BLOCK_DEFS[id].get("glow", false)) else st
				var base := _mul(_palette.get(id, BLOCK_DEFS[id]["c"]), jitter)
				if run1 == NZ - 1 or col_cells[run1 + 1] == 0:       # +z top
					_quad_top(target, x0, y0, z1, base)
				_emit_side_run(target, cells, ix, iy, run0, run1, x0, y0, 0, _mul(base, 0.78))
				_emit_side_run(target, cells, ix, iy, run0, run1, x0, y0, 1, _mul(base, 0.78))
				_emit_side_run(target, cells, ix, iy, run0, run1, x0, y0, 2, _mul(base, 0.6))
				_emit_side_run(target, cells, ix, iy, run0, run1, x0, y0, 3, _mul(base, 0.88))
			if water_arr[ci] == 1:
				_emit_water_column(st_water, water_arr, ix, iy, x0, y0, water_z)

	_emit_underground_boundary_walls(st)

	var mesh := ArrayMesh.new()
	st.commit_to(mesh, _ground_mat)        # surface 0: lit terrain
	st_glow.commit_to(mesh, _glow_mat)     # surface 1: unshaded emissive accents
	st_water.commit_to(mesh, _water_mat)   # surface 2: animated water/lava
	var mi := ch["mi"] as MeshInstance3D
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

# Per-corner ambient occlusion for a +z top face: a corner darkens when the
# cells around it in the air layer just above (az) are solid (a taller neighbour).
func _ao(s1: bool, s2: bool, c: bool) -> float:
	if s1 and s2:
		return 0.6   # boxed-in corner (two orthogonal neighbours) = deepest shade
	var n := (1 if s1 else 0) + (1 if s2 else 0) + (1 if c else 0)
	return 1.0 - 0.14 * float(n)

# AO factors for the 4 top corners, order (x0,y0) (x1,y0) (x1,y1) (x0,y1).
func _top_ao(cells: Array, ix: int, iy: int, az: int) -> Array[float]:
	var xm := _cell_solid(cells, ix - 1, iy, az)
	var xp := _cell_solid(cells, ix + 1, iy, az)
	var ym := _cell_solid(cells, ix, iy - 1, az)
	var yp := _cell_solid(cells, ix, iy + 1, az)
	return [_ao(xm, ym, _cell_solid(cells, ix - 1, iy - 1, az)),
		_ao(xp, ym, _cell_solid(cells, ix + 1, iy - 1, az)),
		_ao(xp, yp, _cell_solid(cells, ix + 1, iy + 1, az)),
		_ao(xm, yp, _cell_solid(cells, ix - 1, iy + 1, az))]

# Animated water/lava surface for one water column: a translucent top plane at
# the waterline plus short shore walls wherever it meets dry land inside the chunk.
func _emit_water_column(st: _Buf, water_arr: PackedByteArray,
		ix: int, iy: int, x0: float, y0: float, z_water: float) -> void:
	_quad_top(st, x0, y0, z_water, Color(1, 1, 1))  # color comes from _water_mat

# Is the cell at (ix,iy,iz) solid? Out-of-range (chunk x/y edges, z ends) = empty,
# so edge faces are drawn (seam faces overlap the neighbour chunk harmlessly).
func _cell_solid(cells: Array, ix: int, iy: int, iz: int) -> bool:
	if ix < 0 or ix >= COLS_X or iy < 0 or iy >= ROWS_Y or iz < 0 or iz >= NZ:
		return false
	return (cells[iy * COLS_X + ix] as PackedByteArray)[iz] != 0

func _emit_underground_boundary_walls(st: _Buf) -> void:
	var z0 := CELL_Z0 + B
	var z1 := CELL_Z0 + float(IZ_SURF) * B
	var y0 := 0.0
	var y1 := ROW_H
	var x_left := -5.4
	var x_right := 5.4
	var wall_id := BOSS_BLOCK if GameState.underground_boss_area else ROCK
	var col := _mul(_palette.get(wall_id, BLOCK_DEFS[wall_id]["c"]), 0.72)
	_quad(st, Vector3(x_left, y0, z0), Vector3(x_left, y1, z0),
		Vector3(x_left, y1, z1), Vector3(x_left, y0, z1), Vector3(1, 0, 0), col)
	_quad(st, Vector3(x_right, y0, z0), Vector3(x_right, y1, z0),
		Vector3(x_right, y1, z1), Vector3(x_right, y0, z1), Vector3(-1, 0, 0), col)

func _emit_side_run(st: _Buf, cells: Array, ix: int, iy: int,
		run0: int, run1: int, x0: float, y0: float, side: int, col: Color) -> void:
	var nx := ix
	var ny := iy
	match side:
		0: nx -= 1
		1: nx += 1
		2: ny -= 1
		3: ny += 1
	# Fetch the neighbour column ONCE (was a _cell_solid() call per z — the hottest
	# inner loop of the whole remesh). Out-of-range neighbour = all air → fully
	# exposed (seam faces overlap the next chunk harmlessly, as before).
	var have := nx >= 0 and nx < COLS_X and ny >= 0 and ny < ROWS_Y
	var ncol: PackedByteArray = cells[ny * COLS_X + nx] if have else PackedByteArray()
	var open0 := -1
	for iz in range(run0, run1 + 1):
		var exposed := (not have) or ncol[iz] == 0
		if exposed:
			if open0 < 0:
				open0 = iz
		elif open0 >= 0:
			_quad_side_span(st, x0, y0, CELL_Z0 + float(open0) * B,
				CELL_Z0 + float(iz) * B, side, col)
			open0 = -1
	if open0 >= 0:
		_quad_side_span(st, x0, y0, CELL_Z0 + float(open0) * B,
			CELL_Z0 + float(run1 + 1) * B, side, col)

func _mul(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k)

# Horizontal block-top quad (normal +z, toward the camera).
func _quad_top(st: _Buf, x0: float, y0: float, z: float, col: Color) -> void:
	var a := Vector3(x0, y0, z)
	var b := Vector3(x0 + B, y0, z)
	var c := Vector3(x0 + B, y0 + B, z)
	var d := Vector3(x0, y0 + B, z)
	_quad(st, a, b, c, d, Vector3(0, 0, 1), col)

# Top quad with per-corner AO factors (order: (x0,y0) (x1,y0) (x1,y1) (x0,y1)).
func _quad_top_ao(st: _Buf, x0: float, y0: float, z: float,
		col: Color, oc: Array[float]) -> void:
	st.quad4(Vector3(x0, y0, z), Vector3(x0 + B, y0, z),
		Vector3(x0 + B, y0 + B, z), Vector3(x0, y0 + B, z), Vector3(0, 0, 1),
		Color(col.r * oc[0], col.g * oc[0], col.b * oc[0]),
		Color(col.r * oc[1], col.g * oc[1], col.b * oc[1]),
		Color(col.r * oc[2], col.g * oc[2], col.b * oc[2]),
		Color(col.r * oc[3], col.g * oc[3], col.b * oc[3]))

# Vertical water wall spanning z0..z1 on the given side of a water column.
func _water_wall(st: _Buf, x0: float, y0: float, side: int,
		z0: float, z1: float) -> void:
	var c := Color(0.85, 0.9, 1.0)  # slight cool tint on the glassy walls
	match side:
		0:
			_quad(st, Vector3(x0, y0, z0), Vector3(x0, y0 + B, z0),
				Vector3(x0, y0 + B, z1), Vector3(x0, y0, z1), Vector3(-1, 0, 0), c)
		1:
			_quad(st, Vector3(x0 + B, y0, z0), Vector3(x0 + B, y0 + B, z0),
				Vector3(x0 + B, y0 + B, z1), Vector3(x0 + B, y0, z1), Vector3(1, 0, 0), c)
		2:
			_quad(st, Vector3(x0, y0, z0), Vector3(x0 + B, y0, z0),
				Vector3(x0 + B, y0, z1), Vector3(x0, y0, z1), Vector3(0, -1, 0), c)
		3:
			_quad(st, Vector3(x0, y0 + B, z0), Vector3(x0 + B, y0 + B, z0),
				Vector3(x0 + B, y0 + B, z1), Vector3(x0, y0 + B, z1), Vector3(0, 1, 0), c)

# Side face spanning an arbitrary vertical run. side: 0=-x 1=+x 2=-y 3=+y
func _quad_side_span(st: _Buf, x0: float, y0: float,
		z0: float, z1: float, side: int, col: Color) -> void:
	match side:
		0:
			_quad(st, Vector3(x0, y0, z0), Vector3(x0, y0 + B, z0),
				Vector3(x0, y0 + B, z1), Vector3(x0, y0, z1), Vector3(-1, 0, 0), col)
		1:
			_quad(st, Vector3(x0 + B, y0, z0), Vector3(x0 + B, y0 + B, z0),
				Vector3(x0 + B, y0 + B, z1), Vector3(x0 + B, y0, z1), Vector3(1, 0, 0), col)
		2:
			_quad(st, Vector3(x0, y0, z0), Vector3(x0 + B, y0, z0),
				Vector3(x0 + B, y0, z1), Vector3(x0, y0, z1), Vector3(0, -1, 0), col)
		3:
			_quad(st, Vector3(x0, y0 + B, z0), Vector3(x0 + B, y0 + B, z0),
				Vector3(x0 + B, y0 + B, z1), Vector3(x0, y0 + B, z1), Vector3(0, 1, 0), col)

func _quad(st: _Buf, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		n: Vector3, col: Color) -> void:
	st.quad(a, b, c, d, n, col)
