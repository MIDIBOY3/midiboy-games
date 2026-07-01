class_name Enemy
extends Node3D

var enemy_type: String = "invader"
var hp: int = 1
var max_hp: int = 1
var hue: float = 180.0
var required_unit_id: int = 0
var hit_radius: float = 0.09
var alt: float = 0.5   # 0.0 (low/ground) … 1.0 (high/space)
var t: int = 0
var vx: float = 0.0
var vy: float = -0.012
var dormant: bool = false   # "星の生き残り": lies motionless — no AI, no fire, no scroll-kill

var _spiral_cx: float = 0.0
var _spiral_radius: float = 0.0
var _spiral_angle: float = 0.0
var _zag_dir: int = 1
var _zag_t: int = 0
var _zag_period: int = 30
var _hit_flash: int = 0
var _shield_flash: int = 0
var _charge_t: int = 0
var _fired: bool = false
var _fire_period: int = 0   # timed-shooter cadence; visuals telegraph just before it
var _dive_armed: bool = false
var _orbit_cy: float = 0.0       # orbiter: guide-center y (drifts down)
var _orbit_ready: bool = false
var _dash_at: int = 44           # lancer: frame it breaks formation and charges
var _split_l: Node3D = null      # splitcannon: left  half (separates, fires, recloses)
var _split_r: Node3D = null      # splitcannon: right half
var _sc_core: Node3D = null      # splitcannon: link-bar reactor brain (charge glow)
var _sc_barrels: Array = []      # splitcannon: two barrels (recoil kick)
var _sc_muzzles: Array = []      # splitcannon: two muzzles (charge swell + fire flash)
var _quad_rings: Array[Node3D] = []
var _gyro_l: Node3D = null
var _gyro_r: Node3D = null
var _anim_parts: Array[Dictionary] = []
var _glow_parts: Array[MeshInstance3D] = []

static var _box_cache: Dictionary = {}

# Rabble (zako) enemies are rendered at 80% size; bosses/installations keep theirs.
const ZAKO_SCALE := 0.8
const ZAKO_SCALE_EXCLUDE := ["boss", "midboss", "combiner", "stoneface", "bacura",
	"splitcannon", "sam_missile", "pyramid"]

@onready var _mesh: MeshInstance3D = $MeshInstance3D
var _mat: StandardMaterial3D
var _accent_mat: StandardMaterial3D
var _dark_mat: StandardMaterial3D
var _metal_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D
var _label: Label3D

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.emission_enabled = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.roughness = 0.22
	_mat.metallic = 0.08
	_accent_mat = StandardMaterial3D.new()
	_accent_mat.emission_enabled = true
	_accent_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_accent_mat.roughness = 0.18
	_accent_mat.metallic = 0.18
	_dark_mat = StandardMaterial3D.new()
	_dark_mat.emission_enabled = true
	_dark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dark_mat.roughness = 0.30
	_dark_mat.metallic = 0.05
	_metal_mat = StandardMaterial3D.new()
	_metal_mat.emission_enabled = true
	_metal_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_metal_mat.roughness = 0.12
	_metal_mat.metallic = 0.82
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.emission_enabled = true
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.roughness = 0.08
	_mesh.set_surface_override_material(0, _mat)
	_build_voxel_model()
	position.z = GameState.enemy_z(alt)
	_spiral_cx = position.x
	if enemy_type == "lancer":
		# Stagger the dash so a line of lancers strikes in a ripple, not in unison.
		_dash_at = 38 + randi() % 55
	# Per-type fire cadence, computed once (difficulty is ~constant over an enemy's
	# short life). _update_movement fires on it; _update_visuals telegraphs the
	# last frames before it so timed shots are readable, not surprise hits.
	var fd := GameState.difficulty()
	match enemy_type:
		"shooter": _fire_period = int(115.0 - 45.0 * fd)
		"weaver": _fire_period = int(130.0 - 50.0 * fd)
		"classic_invader": _fire_period = int(118.0 - 35.0 * fd)
		"fighter": _fire_period = int(82.0 - 28.0 * fd)
		"saucer": _fire_period = int(105.0 - 34.0 * fd)
		"toroid": _fire_period = int(118.0 - 30.0 * fd)
		"crab": _fire_period = int(112.0 - 32.0 * fd)
		"manta": _fire_period = int(96.0 - 30.0 * fd)
		"caster": _fire_period = int(105.0 - 35.0 * fd)
		"pod": _fire_period = int(95.0 - 35.0 * fd)
		"combiner": _fire_period = int(80.0 - 25.0 * fd)
		"turret": _fire_period = int(160.0 - 70.0 * fd)
		"tank": _fire_period = int(120.0 - 50.0 * fd)
		"splitter": _fire_period = int(135.0 - 40.0 * fd)
		"mirror": _fire_period = int(120.0 - 38.0 * fd)
		"ghost": _fire_period = int(105.0 - 32.0 * fd)
		"quad_ring": _fire_period = int(86.0 - 24.0 * fd)
		"gyro_drone": _fire_period = int(98.0 - 32.0 * fd)
		"pyramid": _fire_period = int(124.0 - 34.0 * fd)
	# Ground units get distinct silhouettes (flat guns, low tanks, tall masts,
	# fat warehouses) so they read instantly from above.
	match enemy_type:
		"turret":
			_mesh.scale = Vector3(1.4, 0.5, 1.4)
		"tank":
			_mesh.scale = Vector3(1.2, 0.75, 0.9)
		"radar":
			_mesh.scale = Vector3(0.7, 2.0, 0.7)
		"depot":
			_mesh.scale = Vector3(1.9, 1.0, 1.5)
		"midboss":
			_mesh.scale = Vector3(3.5, 2.2, 2.0)
		"boss":
			_mesh.scale = Vector3(6.0, 3.6, 3.0)
		"shooter":
			_mesh.scale = Vector3(1.2, 0.8, 1.0)
		"weaver":
			_mesh.scale = Vector3(0.9, 1.3, 0.9)
		"diver":
			_mesh.scale = Vector3(0.75, 1.55, 0.9)
		"climber":
			_mesh.scale = Vector3(0.85, 1.45, 0.85)
		"swooper":
			_mesh.scale = Vector3(1.25, 0.7, 0.9)
		"classic_invader", "crab":
			hit_radius = 0.10
		"fighter":
			hit_radius = 0.12
		"saucer", "manta", "toroid":
			hit_radius = 0.13
		"combiner":
			_mesh.scale = Vector3(1.25, 1.25, 1.0)
			hit_radius = 0.20
		"wisp", "shard":
			hit_radius = 0.075
		"orbiter":
			hit_radius = 0.085
		"lancer":
			_mesh.scale = Vector3(0.8, 1.35, 0.85)
			hit_radius = 0.09
		"corkscrew":
			hit_radius = 0.12
		"ghost":
			hit_radius = 0.12
		"quad_ring":
			hit_radius = 0.15
		"sam_missile":
			hit_radius = 0.085
			_mesh.scale = Vector3(1.35, 1.35, 1.15)
		"gyro_drone":
			hit_radius = 0.16
		"pyramid":
			hit_radius = 0.14
		"stoneface":
			hit_radius = 0.26
		"bacura":
			hit_radius = 0.20
		"splitcannon":
			hit_radius = 0.23
		"unit_guard_1", "unit_guard_2", "unit_guard_3", "unit_guard_4", "unit_guard_5":
			required_unit_id = int(enemy_type.substr(enemy_type.length() - 1, 1))

	# "Marked" indicator: thin glowing bar under the enemy while it is in the
	# player's attackable altitude band (homing bullets target these enemies).
	_marker = MeshInstance3D.new()
	var mbox := BoxMesh.new()
	mbox.size = Vector3(0.1, 0.012, 0.012)
	_marker.mesh = mbox
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.albedo_color = Color(1.0, 0.3, 0.2)
	_marker_mat.emission_enabled = true
	_marker_mat.emission = Color(1.0, 0.3, 0.2)
	_marker.material_override = _marker_mat
	_marker.position = Vector3(0, -0.06, 0)
	_marker.visible = false
	add_child(_marker)

	# Shrink the rabble (visual + collision together) so popcorn enemies read smaller.
	if not ZAKO_SCALE_EXCLUDE.has(enemy_type):
		scale = Vector3.ONE * ZAKO_SCALE
		hit_radius *= ZAKO_SCALE

func _build_voxel_model() -> void:
	_mesh.visible = false
	var unit_guard := enemy_type.begins_with("unit_guard_")
	if unit_guard and required_unit_id == 0:
		required_unit_id = int(enemy_type.substr(enemy_type.length() - 1, 1))
	match enemy_type:
		"classic_invader":
			_part(Vector3(0.0, 0.02, 0.0), Vector3(0.18, 0.10, 0.065))
			_part(Vector3(-0.13, 0.04, 0.0), Vector3(0.060, 0.085, 0.050), false, false, "accent")
			_part(Vector3(0.13, 0.04, 0.0), Vector3(0.060, 0.085, 0.050), false, false, "accent")
			_part(Vector3(-0.07, -0.075, 0.0), Vector3(0.050, 0.050, 0.045), false, true, "dark")
			_part(Vector3(0.07, -0.075, 0.0), Vector3(0.050, 0.050, 0.045), false, true, "dark")
			_part(Vector3(-0.045, 0.085, 0.026), Vector3(0.026, 0.026, 0.020), true)
			_part(Vector3(0.045, 0.085, 0.026), Vector3(0.026, 0.026, 0.020), true)
		"fighter":
			# Wide arcade fighter: blue slab body, dark wing tips, red glowing spine.
			_part(Vector3(0.0, 0.020, 0.0), Vector3(0.24, 0.150, 0.070))
			_part(Vector3(-0.205, 0.050, 0.0), Vector3(0.090, 0.090, 0.058), false, false, "accent")
			_part(Vector3(0.205, 0.050, 0.0), Vector3(0.090, 0.090, 0.058), false, false, "accent")
			_part(Vector3(0.0, 0.115, 0.036), Vector3(0.060, 0.115, 0.026), true)
			_part(Vector3(0.0, -0.115, 0.0), Vector3(0.080, 0.090, 0.058))
			_part(Vector3(-0.070, -0.195, 0.0), Vector3(0.055, 0.130, 0.050), false, false, "metal")
			_part(Vector3(0.070, -0.195, 0.0), Vector3(0.055, 0.130, 0.050), false, false, "metal")
			_part(Vector3(0.0, -0.235, 0.028), Vector3(0.055, 0.040, 0.022), true)
		"saucer":
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.24, 0.075, 0.060), false, false, "accent")
			_part(Vector3(0.0, 0.055, 0.0), Vector3(0.115, 0.075, 0.065))
			_part(Vector3(-0.15, -0.035, 0.0), Vector3(0.070, 0.040, 0.040), false, true, "dark")
			_part(Vector3(0.15, -0.035, 0.0), Vector3(0.070, 0.040, 0.040), false, true, "dark")
			_part(Vector3(0.0, 0.080, 0.032), Vector3(0.045, 0.030, 0.022), true)
		"toroid":
			# Xevious-like metallic ring, built from chunky voxel facets.
			_part(Vector3(-0.105, 0.135, 0.0), Vector3(0.145, 0.055, 0.060), false, true, "metal")
			_part(Vector3(0.105, 0.135, 0.0), Vector3(0.145, 0.055, 0.060), false, true, "metal")
			_part(Vector3(-0.175, 0.035, 0.0), Vector3(0.055, 0.150, 0.060), false, true, "metal")
			_part(Vector3(0.175, 0.035, 0.0), Vector3(0.055, 0.150, 0.060), false, true, "metal")
			_part(Vector3(-0.105, -0.105, 0.0), Vector3(0.145, 0.055, 0.060), false, true, "metal")
			_part(Vector3(0.105, -0.105, 0.0), Vector3(0.145, 0.055, 0.060), false, true, "metal")
			_part(Vector3(-0.205, -0.085, -0.012), Vector3(0.045, 0.045, 0.030), false, false, "dark")
			_part(Vector3(0.205, 0.110, -0.012), Vector3(0.045, 0.045, 0.030), false, false, "dark")
			_part(Vector3(0.0, 0.010, 0.034), Vector3(0.030, 0.030, 0.020), true)
		"crab":
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.15, 0.13, 0.070))
			_part(Vector3(-0.14, 0.04, 0.0), Vector3(0.070, 0.045, 0.045), false, true, "accent")
			_part(Vector3(0.14, 0.04, 0.0), Vector3(0.070, 0.045, 0.045), false, true, "accent")
			_part(Vector3(-0.12, -0.075, 0.0), Vector3(0.060, 0.045, 0.040), false, true, "dark")
			_part(Vector3(0.12, -0.075, 0.0), Vector3(0.060, 0.045, 0.040), false, true, "dark")
			_part(Vector3(0.0, 0.085, 0.030), Vector3(0.045, 0.030, 0.022), true)
		"manta":
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.13, 0.16, 0.065))
			_part(Vector3(-0.17, 0.025, 0.0), Vector3(0.16, 0.045, 0.040), false, true, "accent")
			_part(Vector3(0.17, 0.025, 0.0), Vector3(0.16, 0.045, 0.040), false, true, "accent")
			_part(Vector3(0.0, -0.12, 0.0), Vector3(0.060, 0.075, 0.045), false, false, "dark")
			_part(Vector3(0.0, 0.090, 0.030), Vector3(0.035, 0.035, 0.022), true)
		"invader":
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.16, 0.09, 0.07))
			_part(Vector3(-0.13, -0.02, 0.0), Vector3(0.10, 0.045, 0.05), false, false, "accent")
			_part(Vector3(0.13, -0.02, 0.0), Vector3(0.10, 0.045, 0.05), false, false, "accent")
			_part(Vector3(0.0, 0.055, 0.025), Vector3(0.040, 0.025, 0.020), true)
			_part(Vector3(0.0, -0.060, 0.045), Vector3(0.050, 0.040, 0.032), false, false, "dark")
		"drifter":
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.19, 0.060, 0.070))
			_part(Vector3(-0.09, 0.055, 0.0), Vector3(0.05, 0.10, 0.050), false, true, "accent")
			_part(Vector3(0.09, -0.055, 0.0), Vector3(0.05, 0.10, 0.050), false, true, "accent")
			_part(Vector3(0.0, -0.085, 0.052), Vector3(0.040, 0.045, 0.045), false, false, "metal")
			_part(Vector3(0.0, 0.035, 0.040), Vector3(0.040, 0.030, 0.022), true)
		"tracker":
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.110, 0.145, 0.080))
			_part(Vector3(0.0, 0.12, 0.0), Vector3(0.055, 0.08, 0.060), false, false, "accent")
			_part(Vector3(-0.095, -0.035, 0.0), Vector3(0.055, 0.055, 0.050), false, false, "dark")
			_part(Vector3(0.095, -0.035, 0.0), Vector3(0.055, 0.055, 0.050), false, false, "dark")
			_part(Vector3(0.0, -0.085, 0.050), Vector3(0.035, 0.045, 0.040), false, false, "metal")
			_part(Vector3(0.0, 0.045, 0.030), Vector3(0.035, 0.035, 0.022), true)
		"shooter":
			_part(Vector3(0.0, -0.015, 0.0), Vector3(0.18, 0.11, 0.085))
			_part(Vector3(0.0, 0.095, 0.0), Vector3(0.06, 0.11, 0.065), false, false, "accent")
			_part(Vector3(-0.13, 0.035, 0.0), Vector3(0.055, 0.10, 0.055), false, false, "dark")
			_part(Vector3(0.13, 0.035, 0.0), Vector3(0.055, 0.10, 0.055), false, false, "dark")
			_part(Vector3(0.0, -0.095, 0.055), Vector3(0.040, 0.060, 0.040), false, false, "metal")
			_part(Vector3(0.0, 0.165, 0.024), Vector3(0.032, 0.045, 0.022), true)
		"weaver":
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.11, 0.16, 0.075))
			_part(Vector3(-0.11, 0.04, 0.0), Vector3(0.075, 0.055, 0.050), false, false, "accent")
			_part(Vector3(0.11, -0.04, 0.0), Vector3(0.075, 0.055, 0.050), false, false, "accent")
			_part(Vector3(0.0, -0.12, 0.0), Vector3(0.05, 0.08, 0.050), false, false, "dark")
			_part(Vector3(0.0, 0.065, 0.045), Vector3(0.032, 0.040, 0.026), true)
		"diver":
			_part(Vector3(0.0, 0.02, 0.0), Vector3(0.10, 0.20, 0.090))
			_part(Vector3(-0.09, -0.04, 0.0), Vector3(0.06, 0.09, 0.055), false, false, "accent")
			_part(Vector3(0.09, -0.04, 0.0), Vector3(0.06, 0.09, 0.055), false, false, "accent")
			_part(Vector3(0.0, -0.115, 0.060), Vector3(0.038, 0.065, 0.045), false, false, "metal")
			_part(Vector3(0.0, 0.130, 0.035), Vector3(0.035, 0.050, 0.026), true)
		"climber":
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.10, 0.19, 0.080))
			_part(Vector3(-0.08, 0.075, 0.0), Vector3(0.055, 0.075, 0.050), false, false, "accent")
			_part(Vector3(0.08, 0.075, 0.0), Vector3(0.055, 0.075, 0.050), false, false, "accent")
			_part(Vector3(0.0, -0.13, 0.0), Vector3(0.14, 0.045, 0.050), false, false, "dark")
			_part(Vector3(0.0, 0.095, 0.052), Vector3(0.038, 0.050, 0.034), true)
		"swooper":
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.18, 0.075, 0.075))
			_part(Vector3(-0.16, 0.035, 0.0), Vector3(0.11, 0.045, 0.050), false, false, "accent")
			_part(Vector3(0.16, 0.035, 0.0), Vector3(0.11, 0.045, 0.050), false, false, "accent")
			_part(Vector3(0.0, -0.075, 0.0), Vector3(0.05, 0.08, 0.055), false, false, "dark")
			_part(Vector3(0.0, 0.035, 0.047), Vector3(0.045, 0.030, 0.026), true)
		"sniper":
			_part(Vector3(0.0, -0.02, 0.0), Vector3(0.13, 0.13, 0.080))
			_part(Vector3(0.0, 0.12, 0.0), Vector3(0.045, 0.16, 0.052), false, false, "metal")
			_part(Vector3(-0.10, -0.06, 0.0), Vector3(0.055, 0.055, 0.050), false, false, "accent")
			_part(Vector3(0.10, -0.06, 0.0), Vector3(0.055, 0.055, 0.050), false, false, "accent")
			_part(Vector3(0.0, 0.020, 0.050), Vector3(0.040, 0.034, 0.026), true)
		"hunter":
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.13, 0.13, 0.07))
			_part(Vector3(-0.11, 0.07, 0.0), Vector3(0.07, 0.08, 0.05))
			_part(Vector3(0.11, 0.07, 0.0), Vector3(0.07, 0.08, 0.05))
			_part(Vector3(0.0, -0.11, 0.0), Vector3(0.07, 0.09, 0.045))
		"zigzag", "spiraler":
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.12, 0.12, 0.06))
			_part(Vector3(-0.08, 0.08, 0.0), Vector3(0.075, 0.04, 0.04))
			_part(Vector3(0.08, -0.08, 0.0), Vector3(0.075, 0.04, 0.04))
		"blade":
			_part(Vector3(0.0, 0.03, 0.0), Vector3(0.08, 0.24, 0.065))
			_part(Vector3(-0.075, -0.035, 0.0), Vector3(0.055, 0.12, 0.045))
			_part(Vector3(0.075, -0.035, 0.0), Vector3(0.055, 0.12, 0.045))
			_part(Vector3(0.0, 0.18, 0.0), Vector3(0.045, 0.10, 0.04))
		"caster":
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.17, 0.17, 0.08))
			_part(Vector3(-0.13, 0.0, 0.0), Vector3(0.065, 0.10, 0.055), false, true)
			_part(Vector3(0.13, 0.0, 0.0), Vector3(0.065, 0.10, 0.055), false, true)
			_part(Vector3(0.0, 0.13, 0.0), Vector3(0.10, 0.06, 0.055), false, true)
			_part(Vector3(0.0, -0.13, 0.0), Vector3(0.10, 0.06, 0.055), false, true)
			_part(Vector3(0.0, 0.0, 0.036), Vector3(0.052, 0.052, 0.025), true)
		"pod":
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.105, 0.105, 0.065))
			_part(Vector3(-0.09, 0.0, 0.0), Vector3(0.055, 0.055, 0.045))
			_part(Vector3(0.09, 0.0, 0.0), Vector3(0.055, 0.055, 0.045))
			_part(Vector3(0.0, -0.09, 0.0), Vector3(0.050, 0.055, 0.04))
			_part(Vector3(0.0, 0.065, 0.026), Vector3(0.030, 0.030, 0.020), true)
		"combiner":
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.24, 0.18, 0.10))
			_part(Vector3(0.0, 0.18, 0.0), Vector3(0.12, 0.14, 0.085), false, true)
			_part(Vector3(0.0, -0.17, 0.0), Vector3(0.16, 0.075, 0.075), false, true)
			_part(Vector3(-0.22, 0.02, 0.0), Vector3(0.14, 0.11, 0.075), false, true)
			_part(Vector3(0.22, 0.02, 0.0), Vector3(0.14, 0.11, 0.075), false, true)
			_part(Vector3(-0.36, -0.05, 0.0), Vector3(0.11, 0.075, 0.065), false, true)
			_part(Vector3(0.36, -0.05, 0.0), Vector3(0.11, 0.075, 0.065), false, true)
			_part(Vector3(0.0, 0.035, 0.052), Vector3(0.090, 0.070, 0.030), true)
			_part(Vector3(-0.24, 0.11, 0.045), Vector3(0.045, 0.045, 0.026), true, true)
			_part(Vector3(0.24, 0.11, 0.045), Vector3(0.045, 0.045, 0.026), true, true)
		"turret":
			_part(Vector3(0.0, -0.02, 0.0), Vector3(0.18, 0.12, 0.06))
			_part(Vector3(0.0, 0.08, 0.0), Vector3(0.055, 0.16, 0.055))
		"tank":
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.21, 0.13, 0.07))
			_part(Vector3(-0.08, -0.08, 0.0), Vector3(0.07, 0.045, 0.045))
			_part(Vector3(0.08, -0.08, 0.0), Vector3(0.07, 0.045, 0.045))
			_part(Vector3(0.0, 0.10, 0.0), Vector3(0.045, 0.13, 0.045))
		"radar":
			_part(Vector3(0.0, -0.04, 0.0), Vector3(0.10, 0.14, 0.055))
			_part(Vector3(0.0, 0.10, 0.0), Vector3(0.18, 0.045, 0.045))
			_part(Vector3(-0.07, 0.15, 0.0), Vector3(0.045, 0.08, 0.04))
			_part(Vector3(0.07, 0.15, 0.0), Vector3(0.045, 0.08, 0.04))
		"depot":
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.28, 0.16, 0.08))
			_part(Vector3(-0.10, 0.12, 0.0), Vector3(0.08, 0.07, 0.06))
			_part(Vector3(0.10, 0.12, 0.0), Vector3(0.08, 0.07, 0.06))
		"midboss":
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.42, 0.25, 0.12))
			_part(Vector3(-0.30, 0.03, 0.0), Vector3(0.18, 0.12, 0.08))
			_part(Vector3(0.30, 0.03, 0.0), Vector3(0.18, 0.12, 0.08))
			_part(Vector3(0.0, 0.24, 0.0), Vector3(0.12, 0.18, 0.09))
			_part(Vector3(0.0, -0.20, 0.0), Vector3(0.26, 0.08, 0.08))
		"boss":
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.68, 0.34, 0.16))
			_part(Vector3(-0.48, 0.04, 0.0), Vector3(0.24, 0.16, 0.11))
			_part(Vector3(0.48, 0.04, 0.0), Vector3(0.24, 0.16, 0.11))
			_part(Vector3(0.0, 0.32, 0.0), Vector3(0.18, 0.22, 0.12))
			_part(Vector3(-0.22, -0.25, 0.0), Vector3(0.16, 0.10, 0.09))
			_part(Vector3(0.22, -0.25, 0.0), Vector3(0.16, 0.10, 0.09))
		"unit_guard_1", "unit_guard_2", "unit_guard_3", "unit_guard_4", "unit_guard_5":
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.21, 0.17, 0.095), false, false, "main")
			_part(Vector3(0.0, 0.0, 0.060), Vector3(0.16, 0.12, 0.026), true)
			_add_unit_label()
		"wisp":
			# Tiny popcorn mote: a glowing core with a short trailing fin. Comes
			# in dense sine-ribbon streams (see EnemySpawner wave 21).
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.060, 0.060, 0.050), true)
			_part(Vector3(0.0, -0.050, 0.0), Vector3(0.030, 0.045, 0.026), false, true, "accent")
		"orbiter":
			# Small ring drone that circles a drifting guide point (wave 22).
			_part(Vector3(-0.060, 0.045, 0.0), Vector3(0.075, 0.034, 0.040), false, true, "metal")
			_part(Vector3(0.060, 0.045, 0.0), Vector3(0.075, 0.034, 0.040), false, true, "metal")
			_part(Vector3(-0.075, -0.030, 0.0), Vector3(0.034, 0.075, 0.040), false, true, "metal")
			_part(Vector3(0.075, -0.030, 0.0), Vector3(0.034, 0.075, 0.040), false, true, "metal")
			_part(Vector3(0.0, 0.0, 0.026), Vector3(0.034, 0.034, 0.022), true)
		"splitter":
			# Cracked egg-block that bursts into shards on death (see take_hit).
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.155, 0.150, 0.090))
			_part(Vector3(-0.085, 0.0, 0.012), Vector3(0.022, 0.130, 0.075), false, false, "dark")
			_part(Vector3(0.0, 0.082, 0.012), Vector3(0.120, 0.022, 0.075), false, false, "dark")
			_part(Vector3(0.0, 0.0, 0.052), Vector3(0.050, 0.050, 0.028), true)
		"shard":
			# Sharp fragment thrown by a dying splitter.
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.055, 0.075, 0.045), false, false, "accent")
			_part(Vector3(0.0, 0.045, 0.0), Vector3(0.030, 0.040, 0.026), true)
		"lancer":
			# Thin spear ship: forms a line, then dashes in sequence (wave 24).
			_part(Vector3(0.0, 0.04, 0.0), Vector3(0.060, 0.220, 0.060))
			_part(Vector3(0.0, 0.175, 0.0), Vector3(0.030, 0.085, 0.034), true)
			_part(Vector3(-0.060, -0.050, 0.0), Vector3(0.045, 0.090, 0.040), false, false, "accent")
			_part(Vector3(0.060, -0.050, 0.0), Vector3(0.045, 0.090, 0.040), false, false, "accent")
		"mirror":
			# Symmetric twin ship for mirrored formations (wave 25).
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.080, 0.130, 0.075))
			_part(Vector3(-0.105, 0.020, 0.0), Vector3(0.095, 0.055, 0.050), false, false, "accent")
			_part(Vector3(0.105, 0.020, 0.0), Vector3(0.095, 0.055, 0.050), false, false, "accent")
			_part(Vector3(-0.105, -0.040, 0.026), Vector3(0.030, 0.030, 0.022), true)
			_part(Vector3(0.105, -0.040, 0.026), Vector3(0.030, 0.030, 0.022), true)
		"corkscrew":
			# 'a': a vicious orange drill-wasp. Glowing drill nose + segmented body + stepped
			# wings + twin engine glow. Corkscrew-rolls as it dives (see movement).
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.080, 0.260, 0.080))                       # spine
			_part(Vector3(0.0, 0.115, 0.0), Vector3(0.110, 0.045, 0.095))                     # collar
			_part(Vector3(0.0, 0.158, 0.0), Vector3(0.090, 0.075, 0.082), true)               # drill core (red)
			_part(Vector3(0.0, 0.212, 0.0), Vector3(0.050, 0.055, 0.050), false, false, "accent")  # pink drill tip
			_part(Vector3(0.0, -0.040, 0.040), Vector3(0.052, 0.190, 0.050), false, false, "metal")  # belly ridge
			_part(Vector3(0.0, 0.060, 0.058), Vector3(0.060, 0.024, 0.030), false, false, "dark")    # blue band
			_part(Vector3(0.0, 0.005, 0.058), Vector3(0.060, 0.024, 0.030), false, false, "dark")
			_part(Vector3(0.0, -0.050, 0.058), Vector3(0.060, 0.024, 0.030), false, false, "dark")
			_part(Vector3(-0.120, 0.040, 0.0), Vector3(0.150, 0.090, 0.050))                  # wing L inner
			_part(Vector3(0.120, 0.040, 0.0), Vector3(0.150, 0.090, 0.050))                   # wing R inner
			_part(Vector3(-0.220, 0.040, 0.0), Vector3(0.078, 0.058, 0.044))                  # wing L tip
			_part(Vector3(0.220, 0.040, 0.0), Vector3(0.078, 0.058, 0.044))                   # wing R tip
			_part(Vector3(-0.165, 0.092, 0.0), Vector3(0.070, 0.030, 0.040), false, false, "dark")  # wing edge
			_part(Vector3(0.165, 0.092, 0.0), Vector3(0.070, 0.030, 0.040), false, false, "dark")
			_part(Vector3(0.0, -0.160, 0.0), Vector3(0.060, 0.060, 0.058))                    # tail
			_part(Vector3(-0.034, -0.205, 0.0), Vector3(0.034, 0.040, 0.040), true)           # engine glow L
			_part(Vector3(0.034, -0.205, 0.0), Vector3(0.034, 0.040, 0.040), true)            # engine glow R
		"ghost":
			# a: cute electric blob. One coherent yellow body, pointy ears, rosy cheeks.
			_part(Vector3(0.0, 0.030, 0.0), Vector3(0.190, 0.170, 0.095))
			_part(Vector3(0.0, 0.120, 0.0), Vector3(0.145, 0.070, 0.090))
			_part(Vector3(-0.070, 0.175, 0.0), Vector3(0.050, 0.075, 0.065), false, true)
			_part(Vector3(0.070, 0.175, 0.0), Vector3(0.050, 0.075, 0.065), false, true)
			_part(Vector3(-0.070, 0.225, 0.0), Vector3(0.036, 0.042, 0.050), false, false, "dark")
			_part(Vector3(0.070, 0.225, 0.0), Vector3(0.036, 0.042, 0.050), false, false, "dark")
			_part(Vector3(-0.105, 0.010, 0.0), Vector3(0.050, 0.185, 0.080), false, true, "accent")
			_part(Vector3(0.105, 0.010, 0.0), Vector3(0.050, 0.185, 0.080), false, true, "accent")
			_part(Vector3(0.0, 0.040, 0.060), Vector3(0.125, 0.100, 0.024), false, true, "accent")
			_part(Vector3(-0.062, 0.066, 0.055), Vector3(0.038, 0.046, 0.026), false, false, "dark")
			_part(Vector3(0.062, 0.066, 0.055), Vector3(0.038, 0.046, 0.026), false, false, "dark")
			_part(Vector3(-0.045, 0.047, 0.075), Vector3(0.017, 0.017, 0.014), false, false, "metal")
			_part(Vector3(0.045, 0.047, 0.075), Vector3(0.017, 0.017, 0.014), false, false, "metal")
			_part(Vector3(-0.108, 0.005, 0.058), Vector3(0.030, 0.030, 0.018), true)
			_part(Vector3(0.108, 0.005, 0.058), Vector3(0.030, 0.030, 0.018), true)
			_part(Vector3(0.0, -0.030, 0.060), Vector3(0.052, 0.020, 0.016), false, false, "dark")
			_part(Vector3(-0.086, -0.094, 0.0), Vector3(0.040, 0.066, 0.070), false, true)
			_part(Vector3(-0.028, -0.110, 0.0), Vector3(0.045, 0.086, 0.072), false, true)
			_part(Vector3(0.028, -0.110, 0.0), Vector3(0.045, 0.086, 0.072), false, true)
			_part(Vector3(0.086, -0.094, 0.0), Vector3(0.040, 0.066, 0.070), false, true)
		"quad_ring":
			# b: four linked metal rings. Each ring is a small voxel toroid on its own host.
			_quad_rings.clear()
			for p in [Vector3(-0.105, 0.105, 0.0), Vector3(0.105, 0.105, 0.0),
					Vector3(-0.105, -0.105, 0.0), Vector3(0.105, -0.105, 0.0)]:
				var host := Node3D.new()
				host.position = p
				add_child(host)
				_quad_rings.append(host)
				_part(Vector3(0.0, 0.040, 0.0), Vector3(0.082, 0.030, 0.045), false, true, "metal", host)
				_part(Vector3(0.0, -0.040, 0.0), Vector3(0.082, 0.030, 0.045), false, true, "metal", host)
				_part(Vector3(-0.040, 0.0, 0.0), Vector3(0.030, 0.082, 0.045), false, true, "metal", host)
				_part(Vector3(0.040, 0.0, 0.0), Vector3(0.030, 0.082, 0.045), false, true, "metal", host)
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.055, 0.055, 0.055), true)
			_part(Vector3(0.0, 0.120, 0.018), Vector3(0.035, 0.090, 0.030), false, true, "metal")
			_part(Vector3(0.120, 0.0, 0.018), Vector3(0.090, 0.035, 0.030), false, true, "metal")
			_part(Vector3(0.0, -0.120, 0.018), Vector3(0.035, 0.090, 0.030), false, true, "metal")
			_part(Vector3(-0.120, 0.0, 0.018), Vector3(0.090, 0.035, 0.030), false, true, "metal")
			_part(Vector3(-0.050, 0.050, 0.0), Vector3(0.038, 0.038, 0.040), false, true, "dark")
			_part(Vector3(0.050, 0.050, 0.0), Vector3(0.038, 0.038, 0.040), false, true, "dark")
			_part(Vector3(-0.050, -0.050, 0.0), Vector3(0.038, 0.038, 0.040), false, true, "dark")
			_part(Vector3(0.050, -0.050, 0.0), Vector3(0.038, 0.038, 0.040), false, true, "dark")
		"sam_missile":
			# c: surface-to-air missile. Bigger, brighter, and much more readable.
			_part(Vector3(0.0, 0.040, 0.0), Vector3(0.135, 0.260, 0.120), false, false, "metal")
			_part(Vector3(0.0, 0.198, 0.0), Vector3(0.095, 0.090, 0.090))
			_part(Vector3(0.0, 0.270, 0.0), Vector3(0.055, 0.065, 0.058), true)
			_part(Vector3(-0.118, 0.020, 0.0), Vector3(0.090, 0.048, 0.055), true)
			_part(Vector3(0.118, 0.020, 0.0), Vector3(0.090, 0.048, 0.055), true)
			_part(Vector3(-0.085, -0.092, 0.0), Vector3(0.065, 0.090, 0.055), false, false, "dark")
			_part(Vector3(0.085, -0.092, 0.0), Vector3(0.065, 0.090, 0.055), false, false, "dark")
			_part(Vector3(-0.040, -0.166, 0.0), Vector3(0.055, 0.082, 0.052), true)
			_part(Vector3(0.040, -0.166, 0.0), Vector3(0.055, 0.082, 0.052), true)
			_part(Vector3(0.0, -0.240, 0.0), Vector3(0.130, 0.085, 0.130), true)
			_part(Vector3(0.0, -0.315, 0.0), Vector3(0.190, 0.065, 0.165), true)
			_part(Vector3(0.0, 0.050, 0.075), Vector3(0.044, 0.058, 0.028), false, false, "dark")
		"gyro_drone":
			# d: twin round gyro wings with a long central fuselage.
			_gyro_l = Node3D.new()
			_gyro_l.position = Vector3(-0.155, 0.0, 0.0)
			add_child(_gyro_l)
			_gyro_r = Node3D.new()
			_gyro_r.position = Vector3(0.155, 0.0, 0.0)
			add_child(_gyro_r)
			for host in [_gyro_l, _gyro_r]:
				_part(Vector3(0.0, 0.070, 0.0), Vector3(0.090, 0.030, 0.040), false, true, "metal", host)
				_part(Vector3(0.0, -0.070, 0.0), Vector3(0.090, 0.030, 0.040), false, true, "metal", host)
				_part(Vector3(-0.070, 0.0, 0.0), Vector3(0.030, 0.090, 0.040), false, true, "metal", host)
				_part(Vector3(0.070, 0.0, 0.0), Vector3(0.030, 0.090, 0.040), false, true, "metal", host)
				_part(Vector3(0.0, 0.0, 0.050), Vector3(0.120, 0.018, 0.018), false, true, "dark", host)
				_part(Vector3(0.0, 0.0, 0.050), Vector3(0.018, 0.120, 0.018), false, true, "dark", host)
				_part(Vector3(0.0, 0.0, 0.018), Vector3(0.040, 0.040, 0.026), false, false, "dark", host)
			_part(Vector3(0.0, 0.0, 0.0), Vector3(0.060, 0.290, 0.062), false, false, "metal")
			_part(Vector3(0.0, 0.160, 0.0), Vector3(0.050, 0.054, 0.055), true)
			_part(Vector3(0.0, -0.160, 0.0), Vector3(0.050, 0.054, 0.055), false, false, "accent")
			_part(Vector3(-0.075, 0.000, 0.0), Vector3(0.090, 0.042, 0.045), false, false, "metal")
			_part(Vector3(0.075, 0.000, 0.0), Vector3(0.090, 0.042, 0.045), false, false, "metal")
		"pyramid":
			# e: Xevious-Sionite inspired crystal: symmetric double square pyramid.
			_part(Vector3(0.0, 0.0, 0.000), Vector3(0.255, 0.255, 0.038), false, false, "metal")
			_part(Vector3(0.0, 0.0, 0.044), Vector3(0.200, 0.200, 0.052))
			_part(Vector3(0.0, 0.0, 0.090), Vector3(0.142, 0.142, 0.046), false, false, "accent")
			_part(Vector3(0.0, 0.0, 0.128), Vector3(0.075, 0.075, 0.040), false, false, "dark")
			_part(Vector3(0.0, 0.0, -0.044), Vector3(0.200, 0.200, 0.052))
			_part(Vector3(0.0, 0.0, -0.090), Vector3(0.142, 0.142, 0.046), false, false, "accent")
			_part(Vector3(0.0, 0.0, -0.128), Vector3(0.075, 0.075, 0.040), false, false, "dark")
			_part(Vector3(0.0, 0.0, 0.155), Vector3(0.035, 0.035, 0.026), true)
			_part(Vector3(0.0, 0.0, -0.155), Vector3(0.035, 0.035, 0.026), true)
			_part(Vector3(0.090, 0.0, 0.030), Vector3(0.045, 0.115, 0.022), false, false, "dark")
			_part(Vector3(-0.090, 0.0, -0.030), Vector3(0.045, 0.115, 0.022), false, false, "dark")
		"stoneface":
			_build_stoneface()
		"bacura":
			_build_bacura()
		"splitcannon":
			_build_splitcannon()
		_:
			_part(Vector3.ZERO, Vector3(0.12, 0.08, 0.055))

# 'b' stoneface: a rugged voxel ASTEROID (blocky sphere shell) bristling with jagged
# bumps, pocked with dark craters, laced with pulsing magma veins, and staring out of two
# deep-set red eyes. Tumbles slowly (movement). Very tough.
func _build_stoneface() -> void:
	# Rounded mass from a big core + 6 face caps + 4 edge chunks (11 parts instead of a
	# fine 3x3x3 voxel grid — same rugged read, far fewer draw calls). Bumps add ruggedness.
	_part(Vector3.ZERO, Vector3(0.300, 0.300, 0.280))                  # core mass
	var fstep := 0.135
	var faces := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0),
		Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	for i in faces.size():
		var d: Vector3 = faces[i]
		_part(d * fstep, Vector3(0.165, 0.165, 0.165), false, false,
			"metal" if (i % 2) == 0 else "main")                       # 6 face caps
	for e in [Vector3(1, 1, 0), Vector3(-1, 1, 0), Vector3(1, -1, 0), Vector3(-1, -1, 0)]:
		_part(e * fstep * 0.82, Vector3(0.120, 0.120, 0.120), false, false, "main")  # 4 edge chunks
	# Jagged surface bumps for that ゴツゴツ silhouette.
	for b in 5:
		var a := TAU * float(b) / 5.0
		var rr := 0.185 + 0.02 * sin(a * 3.0)
		_part(Vector3(cos(a) * rr, sin(a) * rr, 0.05 * sin(a * 2.0)),
			Vector3(0.078, 0.078, 0.078), false, false, "main")
	_part(Vector3(0.05, 0.14, 0.16), Vector3(0.06, 0.06, 0.06), false, false, "metal")  # top boulder
	_part(Vector3(-0.13, -0.08, 0.12), Vector3(0.07, 0.07, 0.07), false, false, "metal")
	# Dark craters (recessed shadow pits).
	_part(Vector3(-0.11, 0.07, 0.17), Vector3(0.06, 0.06, 0.03), false, false, "dark")
	_part(Vector3(0.13, -0.10, 0.15), Vector3(0.055, 0.055, 0.03), false, false, "dark")
	_part(Vector3(0.02, -0.17, 0.14), Vector3(0.05, 0.05, 0.03), false, false, "dark")
	# Brow shadow + deep-set red eyes (blink in visuals) + nose ridge.
	_part(Vector3(-0.075, 0.105, 0.175), Vector3(0.10, 0.030, 0.05), false, false, "dark")
	_part(Vector3(0.075, 0.105, 0.175), Vector3(0.10, 0.030, 0.05), false, false, "dark")
	_part(Vector3(-0.075, 0.050, 0.185), Vector3(0.052, 0.046, 0.040), true)
	_part(Vector3(0.075, 0.050, 0.185), Vector3(0.052, 0.046, 0.040), true)
	_part(Vector3(0.0, -0.02, 0.205), Vector3(0.04, 0.075, 0.035), false, false, "dark")

# 'c' bacura: the surface "pattern" is pure RELIEF — raised/recessed studs of the SAME
# material — so the single key light carves it into highlight/shadow (no colored cells).
# Metallic so the shading pops. Flips on X as it falls (movement); take_hit blocks shots.
func _build_bacura() -> void:
	_part(Vector3(0.0, 0.0, 0.0), Vector3(0.260, 0.360, 0.075))                  # base plate
	_part(Vector3(0.0, 0.0, -0.050), Vector3(0.240, 0.340, 0.040), false, false, "metal")  # back
	# Beveled armored rim (raised frame).
	_part(Vector3(0.0, 0.190, 0.0), Vector3(0.270, 0.040, 0.105), false, false, "metal")
	_part(Vector3(0.0, -0.190, 0.0), Vector3(0.270, 0.040, 0.105), false, false, "metal")
	_part(Vector3(-0.140, 0.0, 0.0), Vector3(0.040, 0.380, 0.105), false, false, "metal")
	_part(Vector3(0.140, 0.0, 0.0), Vector3(0.040, 0.380, 0.105), false, false, "metal")
	# Relief studs: a sparse grid at varying raise heights, ALL the same material (main).
	# Wider studs at 3x3 (was 3x4) — same relief read, fewer draw calls.
	for ix in 3:
		for iy in 3:
			var px := lerpf(-0.075, 0.075, float(ix) / 2.0)
			var py := lerpf(-0.125, 0.125, float(iy) / 2.0)
			var raise := 0.022 + 0.030 * float((ix * 2 + iy) % 3)
			_part(Vector3(px, py, 0.038 + raise * 0.5), Vector3(0.062, 0.062, raise))
	# Recessed grooves (read as shadow lines under the light).
	_part(Vector3(0.0, 0.065, 0.018), Vector3(0.150, 0.020, 0.020), false, false, "metal")
	_part(Vector3(0.0, -0.065, 0.018), Vector3(0.150, 0.020, 0.020), false, false, "metal")

# 'd' splitcannon: a HEAVY twin-cannon gunship with real presence. Two cannon pods (the
# halves) under a thick reactor-bar; charge-glow + recoil + muzzle flash gimmicks live in
# movement. Captures barrel/muzzle/core refs for those animations.
func _build_splitcannon() -> void:
	# Faithful to the sketch: a clean grey "H" — two upright bodies joined by a top bar,
	# a bright cyan band across each, and a lower prong/barrel. Splits at the bar, fires a
	# curtain, recloses and flees. NOT a winged ship (kept distinct from player Unit 3).
	_split_l = Node3D.new()
	add_child(_split_l)
	_split_r = Node3D.new()
	add_child(_split_r)
	# Top connecting bar + small core.
	_part(Vector3(0.0, 0.165, 0.0), Vector3(0.330, 0.060, 0.075), false, false, "metal")
	_part(Vector3(0.0, 0.165, 0.045), Vector3(0.110, 0.040, 0.035), false, false, "dark")
	_sc_core = _part(Vector3(0.0, 0.165, 0.065), Vector3(0.060, 0.060, 0.035), true)   # core spark
	_sc_barrels.clear()
	_sc_muzzles.clear()
	for s: float in [-1.0, 1.0]:
		var host: Node3D = _split_l if s < 0.0 else _split_r
		_part(Vector3(0.0, 0.050, 0.0), Vector3(0.105, 0.250, 0.105), false, false, "main", host)   # upright body
		_part(Vector3(0.0, 0.145, 0.0), Vector3(0.105, 0.055, 0.110), false, false, "metal", host)  # top shoulder
		# Cyan band across the middle (the sketch's blue strip).
		_part(Vector3(0.0, 0.025, 0.050), Vector3(0.120, 0.052, 0.055), false, false, "accent", host)
		_part(Vector3(0.0, 0.025, 0.080), Vector3(0.075, 0.034, 0.028), true, false, "glow", host)   # band light
		# Lower prong / barrel with a muzzle that flares when firing.
		var barrel: Node3D = _part(Vector3(0.0, -0.150, 0.0), Vector3(0.072, 0.170, 0.072), false, false, "metal", host)
		_part(Vector3(0.0, -0.130, 0.040), Vector3(0.026, 0.140, 0.026), false, false, "dark", host)  # barrel groove
		var muzzle: Node3D = _part(Vector3(0.0, -0.245, 0.0), Vector3(0.082, 0.050, 0.082), true, false, "glow", host)
		_sc_barrels.append(barrel)
		_sc_muzzles.append(muzzle)
	_split_l.position = Vector3(-0.085, 0.0, 0.0)
	_split_r.position = Vector3(0.085, 0.0, 0.0)

func _part(pos: Vector3, size: Vector3, glow: bool = false, anim: bool = false,
		mat_kind: String = "main", host: Node3D = null) -> MeshInstance3D:
	var p := MeshInstance3D.new()
	var key := "%d:%d:%d" % [int(size.x * 1000.0), int(size.y * 1000.0), int(size.z * 1000.0)]
	var box: BoxMesh = _box_cache.get(key)
	if box == null:
		box = BoxMesh.new()
		box.size = size
		_box_cache[key] = box
	p.mesh = box
	p.position = pos
	match mat_kind:
		"accent":
			p.material_override = _accent_mat
		"dark":
			p.material_override = _dark_mat
		"metal":
			p.material_override = _metal_mat
		_:
			p.material_override = _glow_mat if glow else _mat
	(host if host != null else self).add_child(p)
	if glow:
		_glow_parts.append(p)
	if anim:
		_anim_parts.append({"node": p, "base": pos, "phase": randf() * TAU})
	return p

func _add_unit_label() -> void:
	_label = Label3D.new()
	_label.text = str(required_unit_id)
	_label.font_size = 48
	_label.modulate = Color.WHITE
	_label.outline_size = 4
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	_label.position = Vector3(0.0, -0.012, 0.092)
	_label.scale = Vector3.ONE * 0.0065
	add_child(_label)

func _process(_delta: float) -> void:
	t += 1
	if _hit_flash > 0:
		_hit_flash -= 1
	if _shield_flash > 0:
		_shield_flash -= 1
	if _hit_flash > 0 or _shield_flash > 0 or (t & 3) == 0:
		_update_visuals()
	if dormant:
		# Fixed in world space, no AI/fire, never scroll-killed — a quiet landmark to find.
		_animate_parts()
		return
	_animate_parts()
	_update_movement()
	_check_bounds()

func _animate_parts() -> void:
	var split_t := 0.0
	if enemy_type == "combiner":
		split_t = smoothstep(0.22, 0.62, 0.5 + 0.5 * sin(float(t) * 0.032))
	for rec in _anim_parts:
		var node := rec.get("node") as MeshInstance3D
		if node == null or not is_instance_valid(node):
			continue
		var base: Vector3 = rec["base"]
		var phase: float = float(rec["phase"])
		var breathe := sin(float(t) * 0.10 + phase)
		var spread := Vector3(base.x, base.y, 0.0)
		if spread.length_squared() > 0.0001:
			spread = spread.normalized() * split_t * 0.18
		node.position = base + spread + Vector3(0.0, breathe * 0.010, 0.0)
		node.rotation_degrees.z = breathe * (10.0 if enemy_type == "combiner" else 4.0)
	for g in _glow_parts:
		if g != null and is_instance_valid(g):
			var pulse := 1.0 + 0.22 * sin(float(t) * 0.22)
			g.scale = Vector3.ONE * pulse

func _update_visuals() -> void:
	var alt_diff: float = absf(GameState.alt - alt * GameState.ALT_MAX)
	var base_alpha: float = 1.0 - clampf((alt_diff - 10.0) / 50.0, 0.0, 0.75)
	var flash_f := float(_hit_flash % 2) if _hit_flash > 0 else 0.0
	var h := hue / 360.0
	_mat.albedo_color = Color.from_hsv(h, 0.75, lerpf(0.55, 1.0, flash_f), base_alpha)
	_mat.emission = Color.from_hsv(h, 0.55, 0.3 + flash_f * 0.3)
	_mat.emission_energy_multiplier = lerpf(0.6, 4.0, flash_f)
	_accent_mat.albedo_color = Color.from_hsv(fposmod(h + 0.10, 1.0), 0.62, lerpf(0.68, 1.0, flash_f), base_alpha)
	_accent_mat.emission = Color.from_hsv(fposmod(h + 0.10, 1.0), 0.45, 0.45 + flash_f * 0.25)
	_accent_mat.emission_energy_multiplier = 0.8 + flash_f * 2.6
	_dark_mat.albedo_color = Color.from_hsv(fposmod(h - 0.08, 1.0), 0.60, lerpf(0.20, 0.55, flash_f), base_alpha)
	_dark_mat.emission = Color.from_hsv(fposmod(h - 0.08, 1.0), 0.45, 0.10 + flash_f * 0.20)
	_dark_mat.emission_energy_multiplier = 0.25 + flash_f * 1.8
	_metal_mat.albedo_color = Color(0.68 + flash_f * 0.22, 0.70 + flash_f * 0.20, 0.72 + flash_f * 0.18, base_alpha)
	_metal_mat.emission = Color.from_hsv(fposmod(h + 0.55, 1.0), 0.18, 0.20 + flash_f * 0.35)
	_metal_mat.emission_energy_multiplier = 0.45 + flash_f * 2.2
	_glow_mat.albedo_color = Color.from_hsv(h, 0.45, 1.0, base_alpha)
	_glow_mat.emission = Color.from_hsv(h, 0.35, 1.0)
	_glow_mat.emission_energy_multiplier = 2.0 + 1.1 * sin(float(t) * 0.18)
	if enemy_type == "fighter":
		_mat.albedo_color = Color(0.02, 0.62, 0.95, base_alpha)
		_mat.emission = Color(0.00, 0.22, 0.45)
		_accent_mat.albedo_color = Color(0.02, 0.20, 0.62, base_alpha)
		_accent_mat.emission = Color(0.00, 0.08, 0.32)
		_dark_mat.albedo_color = Color(0.52, 0.54, 0.54, base_alpha)
		_glow_mat.albedo_color = Color(1.0, 0.04, 0.02, base_alpha)
		_glow_mat.emission = Color(1.0, 0.02, 0.01)
		_glow_mat.emission_energy_multiplier = 2.5 + flash_f * 2.0 + sin(float(t) * 0.20) * 0.5
	elif enemy_type in ["shooter", "sniper", "diver"]:
		_mat.albedo_color = Color.from_hsv(0.01, 0.78, 0.88 + flash_f * 0.12, base_alpha)
		_accent_mat.albedo_color = Color.from_hsv(0.12, 0.75, 0.95, base_alpha)
		_dark_mat.albedo_color = Color(0.12, 0.12, 0.16, base_alpha)
		_glow_mat.albedo_color = Color(1.0, 0.78, 0.20, base_alpha)
		_glow_mat.emission = Color(1.0, 0.50, 0.08)
	elif enemy_type in ["weaver", "tracker", "climber"]:
		_mat.albedo_color = Color.from_hsv(0.47, 0.70, 0.78 + flash_f * 0.18, base_alpha)
		_accent_mat.albedo_color = Color.from_hsv(0.73, 0.55, 0.95, base_alpha)
		_dark_mat.albedo_color = Color.from_hsv(0.56, 0.65, 0.28 + flash_f * 0.20, base_alpha)
		_glow_mat.albedo_color = Color(0.40, 1.0, 0.72, base_alpha)
		_glow_mat.emission = Color(0.12, 0.90, 0.55)
	elif enemy_type in ["swooper", "manta", "drifter"]:
		_mat.albedo_color = Color.from_hsv(0.82, 0.68, 0.86 + flash_f * 0.14, base_alpha)
		_accent_mat.albedo_color = Color.from_hsv(0.58, 0.62, 0.92, base_alpha)
		_dark_mat.albedo_color = Color.from_hsv(0.75, 0.58, 0.30 + flash_f * 0.20, base_alpha)
		_glow_mat.albedo_color = Color(1.0, 0.52, 0.92, base_alpha)
		_glow_mat.emission = Color(0.85, 0.18, 0.72)
	elif enemy_type == "corkscrew":
		# Orange wasp: red head, pink tip, gray belly, blue tail band.
		_mat.albedo_color = Color(0.98, 0.60, 0.06, base_alpha)
		_mat.emission = Color(0.55, 0.28, 0.0)
		_accent_mat.albedo_color = Color(1.0, 0.58, 0.55, base_alpha)
		_metal_mat.albedo_color = Color(0.70, 0.72, 0.75, base_alpha)
		_dark_mat.albedo_color = Color(0.10, 0.55, 0.95, base_alpha)
		_glow_mat.albedo_color = Color(1.0, 0.14, 0.06, base_alpha)
		_glow_mat.emission = Color(1.0, 0.10, 0.03)
		_glow_mat.emission_energy_multiplier = 2.6 + flash_f * 2.0
	elif enemy_type == "ghost":
		_mat.albedo_color = Color(1.0, 0.88, 0.02, base_alpha)
		_mat.emission = Color(0.42, 0.30, 0.00)
		_mat.roughness = 0.08
		_mat.metallic = 0.0
		_accent_mat.albedo_color = Color(0.92, 0.74, 0.00, base_alpha)
		_accent_mat.roughness = 0.05
		_dark_mat.albedo_color = Color(0.20, 0.17, 0.02, base_alpha)
		_metal_mat.albedo_color = Color(1.0, 0.94, 0.18, base_alpha)
		_metal_mat.metallic = 0.0
		_metal_mat.roughness = 0.04
		_glow_mat.albedo_color = Color(1.0, 0.05, 0.02, base_alpha)
		_glow_mat.emission = Color(1.0, 0.02, 0.00)
		_glow_mat.emission_energy_multiplier = 1.8 + sin(float(t) * 0.22) * 0.8 + flash_f * 2.0
	elif enemy_type in ["quad_ring", "gyro_drone"]:
		_mat.albedo_color = Color(0.72, 0.74, 0.76, base_alpha)
		_metal_mat.albedo_color = Color(0.64 + flash_f * 0.22, 0.65 + flash_f * 0.22, 0.66 + flash_f * 0.22, base_alpha)
		_metal_mat.metallic = 0.88
		_metal_mat.roughness = 0.045 if enemy_type == "gyro_drone" else 0.10
		_dark_mat.albedo_color = Color(0.26, 0.26, 0.28, base_alpha)
		_accent_mat.albedo_color = Color(0.05, 0.70, 1.0, base_alpha)
		_glow_mat.albedo_color = Color(1.0, 0.06, 0.04, base_alpha)
		_glow_mat.emission = Color(1.0, 0.04, 0.02)
	elif enemy_type == "sam_missile":
		_mat.albedo_color = Color(0.88, 0.06, 0.04, base_alpha)
		_metal_mat.albedo_color = Color(0.70, 0.72, 0.72, base_alpha)
		_dark_mat.albedo_color = Color(0.12, 0.12, 0.12, base_alpha)
		_glow_mat.albedo_color = Color(1.0, 0.02, 0.01, base_alpha)
		_glow_mat.emission = Color(1.0, 0.02, 0.00)
		_glow_mat.emission_energy_multiplier = 2.4 + flash_f * 2.0
	elif enemy_type == "pyramid":
		_mat.albedo_color = Color(0.90, 0.94, 1.0, base_alpha)
		_mat.roughness = 0.08
		_mat.metallic = 0.22
		_accent_mat.albedo_color = Color(0.58, 0.72, 1.0, base_alpha)
		_dark_mat.albedo_color = Color(0.20, 0.24, 0.38, base_alpha)
		_metal_mat.albedo_color = Color(0.78, 0.82, 0.92, base_alpha)
		_metal_mat.metallic = 0.55
		_metal_mat.roughness = 0.06
		_glow_mat.albedo_color = Color(0.70, 0.90, 1.0, base_alpha)
		_glow_mat.emission = Color(0.32, 0.58, 1.0)
		_glow_mat.emission_energy_multiplier = 1.8 + flash_f * 2.4
	elif enemy_type == "stoneface":
		# Rough dead stone; glowing MAGMA veins (accent) pulse; red eyes (glow) BLINK.
		var stone := 0.46 + flash_f * 0.34
		_mat.albedo_color = Color(stone, stone * 0.99, stone * 1.03, base_alpha)
		_mat.metallic = 0.05
		_mat.roughness = 0.96
		_mat.emission = Color(0.05, 0.04, 0.05)
		_mat.emission_energy_multiplier = 0.2
		_metal_mat.albedo_color = Color(0.40, 0.40, 0.44, base_alpha)
		_metal_mat.metallic = 0.1
		_metal_mat.roughness = 0.9
		_dark_mat.albedo_color = Color(0.15, 0.14, 0.17, base_alpha)
		var blink := 1.0 if fmod(float(t) * 0.045, 1.0) < 0.55 else 0.12
		_glow_mat.albedo_color = Color(1.0, 0.07, 0.03, base_alpha)
		_glow_mat.emission = Color(1.0, 0.05, 0.02)
		_glow_mat.emission_energy_multiplier = 0.3 + blink * 5.2
	elif enemy_type == "bacura":
		# Indestructible slab: ONE uniform metallic purple. The "pattern" is relief — the
		# directional light carves the raised/recessed studs into highlight & shadow.
		_mat.albedo_color = Color(0.40, 0.06, 0.50, base_alpha)
		_mat.metallic = 0.55
		_mat.roughness = 0.32
		_mat.emission = Color(0.10, 0.0, 0.14)
		_mat.emission_energy_multiplier = 0.2
		_metal_mat.albedo_color = Color(0.30, 0.05, 0.40, base_alpha)
		_metal_mat.metallic = 0.6
		_metal_mat.roughness = 0.28
		_dark_mat.albedo_color = Color(0.12, 0.01, 0.18, base_alpha)
	elif enemy_type == "splitcannon":
		# Cold grey hull with hot blue gun bands.
		_mat.albedo_color = Color(0.72, 0.74, 0.78, base_alpha)
		_mat.emission = Color(0.05, 0.06, 0.08)
		_metal_mat.albedo_color = Color(0.54, 0.56, 0.60, base_alpha)
		_accent_mat.albedo_color = Color(0.10, 0.66, 1.0, base_alpha)
		_accent_mat.emission = Color(0.0, 0.34, 0.66)
		_accent_mat.emission_energy_multiplier = 1.6 + flash_f * 2.0
		_glow_mat.albedo_color = Color(0.25, 0.80, 1.0, base_alpha)
		_glow_mat.emission = Color(0.10, 0.52, 0.92)
	if _shield_flash > 0:
		var shield_pulse := 0.5 + 0.5 * sin(t * 0.8)
		_mat.albedo_color = _mat.albedo_color.lerp(Color(0.95, 0.95, 1.0, base_alpha), 0.65)
		_mat.emission = Color(0.75, 0.85, 1.0)
		_mat.emission_energy_multiplier = 4.0 + shield_pulse * 2.0
	if enemy_type == "sniper" and _charge_t > 0 and not _fired:
		var warn := clampf(_charge_t / 90.0, 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(t * 0.45)
		_mat.emission = _mat.emission.lerp(Color(1.0, 0.2, 0.05), warn * pulse)
		_mat.emission_energy_multiplier += warn * pulse * 3.0
	elif _fire_period > 0 and _charge_t >= _fire_period - 22:
		# Timed shooters flash orange in the ~22 frames before they fire, so the
		# shot is a readable threat instead of a surprise.
		var warn := clampf(float(_charge_t - (_fire_period - 22)) / 22.0, 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(t * 0.5)
		_mat.emission = _mat.emission.lerp(Color(1.0, 0.45, 0.1), warn * pulse)
		_mat.emission_energy_multiplier += warn * pulse * 2.6

	if enemy_type == "radar":
		# Sweeping signal pulse — the thing you want to silence first.
		_mat.emission_energy_multiplier += 1.5 + 1.5 * sin(t * 0.12)
	elif enemy_type == "caster":
		_mat.emission_energy_multiplier += 1.0 + 1.0 * sin(t * 0.20)
	elif required_unit_id > 0:
		var pulse := 0.5 + 0.5 * sin(t * 0.28)
		_mat.emission_energy_multiplier += 1.8 + pulse * 2.0
		_mat.albedo_color = Color.from_hsv(h, 0.78, 0.96, 0.72)
		_mat.roughness = 0.06
		if _label != null:
			_label.modulate = Color.WHITE.lerp(Color.from_hsv(h, 0.35, 1.0), pulse * 0.25)

	var marked := is_in_player_range()
	_marker.visible = marked
	if marked:
		_marker_mat.emission_energy_multiplier = 1.5 + sin(t * 0.3) * 0.8

func is_in_player_range() -> bool:
	return absf(GameState.alt - alt * GameState.ALT_MAX) < 12.0

func _player_in_ground_attack_band() -> bool:
	if GameState.stage != "planet":
		return false
	if GameState.underground:
		return GameState.alt < 85.0
	return absf(GameState.alt - GameState.GROUND_ALT) < 45.0

func _update_movement() -> void:
	if enemy_type.begins_with("unit_guard_"):
		_update_unit_guard()
		return
	match enemy_type:
		"combiner":
			_update_combiner()
		"invader":
			position.x += vx
			position.y += vy
		"drifter":
			position.x += vx
			position.y += vy
			alt = lerpf(alt, clampf(GameState.alt / GameState.ALT_MAX + sin(t * 0.050) * 0.045, 0.0, 1.0), 0.015)
			position.z = GameState.enemy_z(alt)
			rotation_degrees.y = sin(t * 0.060) * 18.0
		"tracker":
			vx = lerpf(vx, (GameState.px - position.x) * 0.015, 0.04)
			position.x += vx
			position.y += vy
			rotation_degrees.x = lerpf(rotation_degrees.x, -22.0 if vy < 0.0 else 24.0, 0.12)
			rotation_degrees.z = lerpf(rotation_degrees.z, clampf(-vx * 520.0, -22.0, 22.0), 0.12)
		"spiraler":
			_spiral_radius = minf(_spiral_radius + 0.002, 0.8)
			_spiral_angle += 0.09
			position.x = _spiral_cx + cos(_spiral_angle) * _spiral_radius
			position.y += vy
		"zigzag":
			_zag_t += 1
			if _zag_t >= _zag_period:
				_zag_t = 0
				_zag_dir = -_zag_dir
			position.x += _zag_dir * abs(vx)
			position.y += vy
		"shooter":
			if t < 36:
				# Form up: hold the spawn formation and drift down slowly together.
				# A squadron spawned on the same frame breaks into the charge in unison.
				position.x += vx
				position.y += vy
			else:
				# Charge: lock onto the player's lane and dive in fast, banking hard
				# and dropping into the player's altitude plane.
				vx = lerpf(vx, clampf(GameState.px - position.x, -1.6, 1.6) * 0.016, 0.05)
				vy = lerpf(vy, -(0.024 + 0.012 * GameState.difficulty()), 0.04)
				position.x += vx
				position.y += vy
				alt = lerpf(alt, GameState.alt / GameState.ALT_MAX, 0.03)
				position.z = GameState.enemy_z(alt)
				rotation_degrees.x = lerpf(rotation_degrees.x, -26.0, 0.14)
				rotation_degrees.z = lerpf(rotation_degrees.z, clampf(-vx * 700.0, -30.0, 30.0), 0.14)
			_charge_t += 1
			if _charge_t > _fire_period:
				_charge_t = 0
				if is_in_player_range():
					_fire_turret_shot()
		"weaver":
			position.x += vx + sin(t * 0.11) * 0.012
			position.y += vy
			_charge_t += 1
			if _charge_t > _fire_period:
				_charge_t = 0
				if is_in_player_range():
					_fire_turret_shot()
		"blade":
			if not _dive_armed and t > 34:
				_dive_armed = true
				vx = clampf(GameState.px - position.x, -1.4, 1.4) * 0.018
				vy = -0.030 * (1.0 + 0.45 * GameState.difficulty())
			position.x += vx
			position.y += vy
			if t > 88:
				vx = lerpf(vx, 0.0, 0.04)
				vy = lerpf(vy, -0.010, 0.03)
		"caster":
			position.x += vx + sin(t * 0.055) * 0.007
			position.y += vy
			if t > 40:
				vy = lerpf(vy, -0.002, 0.04)
			_charge_t += 1
			if _charge_t > _fire_period:
				_charge_t = 0
				if is_in_player_range():
					_fire_ring()
		"pod":
			position.x += vx + sin(t * 0.19) * 0.016
			position.y += vy
			_charge_t += 1
			if _charge_t > _fire_period:
				_charge_t = 0
				if is_in_player_range():
					_fire_twin_lanes()
		"classic_invader":
			position.x += vx + sin(t * 0.12) * 0.010
			position.y += vy
			_zag_t += 1
			if _zag_t >= 34:
				_zag_t = 0
				vx = -vx if absf(vx) > 0.001 else randf_range(-0.012, 0.012)
			_charge_t += 1
			if _charge_t > _fire_period:
				_charge_t = 0
				if is_in_player_range():
					_fire_turret_shot()
		"fighter":
			_update_fighter_attack()
		"saucer":
			position.x += vx + sin(t * 0.085) * 0.014
			position.y += vy * 0.75
			alt = lerpf(alt, clampf(GameState.alt / GameState.ALT_MAX + sin(t * 0.040) * 0.060, 0.0, 1.0), 0.022)
			position.z = GameState.enemy_z(alt)
			rotation_degrees.x = sin(t * 0.070) * 12.0
			rotation_degrees.z = sin(t * 0.075) * 7.0
			_charge_t += 1
			if _charge_t > _fire_period:
				_charge_t = 0
				if is_in_player_range():
					_fire_ring()
		"toroid":
			_update_toroid_descent()
		"crab":
			position.x += vx + sin(t * 0.23) * 0.012
			position.y += vy
			if t > 45:
				vx = lerpf(vx, clampf(GameState.px - position.x, -1.2, 1.2) * 0.007, 0.03)
				alt = lerpf(alt, clampf(GameState.alt / GameState.ALT_MAX - 0.035 + sin(t * 0.080) * 0.025, 0.0, 1.0), 0.022)
				position.z = GameState.enemy_z(alt)
				rotation_degrees.z = lerpf(rotation_degrees.z, clampf(-vx * 520.0, -18.0, 18.0), 0.12)
			_charge_t += 1
			if _charge_t > _fire_period:
				_charge_t = 0
				if is_in_player_range():
					_fire_twin_lanes()
		"manta":
			position.x += vx + sin(t * 0.06) * 0.020
			position.y += vy + sin(t * 0.11) * 0.005
			alt = lerpf(alt, clampf(GameState.alt / GameState.ALT_MAX + sin(t * 0.045) * 0.055, 0.0, 1.0), 0.020)
			position.z = GameState.enemy_z(alt)
			rotation_degrees.x = sin(t * 0.052) * 16.0
			rotation_degrees.z = sin(t * 0.09) * 12.0
			_charge_t += 1
			if _charge_t > _fire_period:
				_charge_t = 0
				if is_in_player_range():
					_fire_burst_line()
		"diver":
			vx = lerpf(vx, clampf(GameState.px - position.x, -1.0, 1.0) * 0.010, 0.035)
			vy = lerpf(vy, -0.018, 0.018)
			position.x += vx
			position.y += vy
			alt = lerpf(alt, clampf(GameState.alt / GameState.ALT_MAX - 0.050, 0.0, 1.0), 0.024)
			position.z = GameState.enemy_z(alt)
			rotation_degrees.x = lerpf(rotation_degrees.x, -32.0, 0.14)
			rotation_degrees.z = lerpf(rotation_degrees.z, clampf(-vx * 700.0, -28.0, 28.0), 0.14)
		"climber":
			vx = lerpf(vx, clampf(GameState.px - position.x, -1.3, 1.3) * 0.014, 0.05)
			vy = lerpf(vy, clampf(GameState.py - position.y, 0.2, 2.2) * 0.012, 0.035)
			alt = lerpf(alt, GameState.alt / GameState.ALT_MAX, 0.018)
			position.z = GameState.enemy_z(alt)
			position.x += vx
			position.y += vy
			rotation_degrees.x = lerpf(rotation_degrees.x, 32.0, 0.16)
			rotation_degrees.z = lerpf(rotation_degrees.z, clampf(-vx * 720.0, -30.0, 30.0), 0.14)
			if t > 85:
				vy = lerpf(vy, 0.018, 0.04)
		"swooper":
			position.x += vx + sin(t * 0.11) * 0.014
			position.y += vy + sin(t * 0.07) * 0.006
			if t > 32:
				vx = lerpf(vx, clampf(GameState.px - position.x, -1.5, 1.5) * 0.010, 0.026)
				alt = lerpf(alt, clampf(GameState.alt / GameState.ALT_MAX + sin(t * 0.060) * 0.035, 0.0, 1.0), 0.018)
				position.z = GameState.enemy_z(alt)
				rotation_degrees.z = lerpf(rotation_degrees.z, clampf(-vx * 720.0, -28.0, 28.0), 0.12)
			if t > 72:
				vy = lerpf(vy, -0.018, 0.035)
		"sniper":
			if t < 40:
				# Take aim in formation, drifting down slowly together.
				position.y += vy
			else:
				# Charge: dive onto the player's lane, banking into the player's plane.
				vx = lerpf(vx, clampf(GameState.px - position.x, -1.6, 1.6) * 0.015, 0.045)
				vy = lerpf(vy, -(0.022 + 0.012 * GameState.difficulty()), 0.04)
				position.x += vx
				position.y += vy
				alt = lerpf(alt, GameState.alt / GameState.ALT_MAX, 0.028)
				position.z = GameState.enemy_z(alt)
				rotation_degrees.x = lerpf(rotation_degrees.x, -24.0, 0.13)
				rotation_degrees.z = lerpf(rotation_degrees.z, clampf(-vx * 700.0, -28.0, 28.0), 0.13)
			if not _fired and is_in_player_range():
				_charge_t += 1
				# Charges faster as the player grows (90f → 50f).
				if _charge_t > int(90.0 - 40.0 * GameState.difficulty()):
					_fired = true
					_fire_aimed_fan()
		"turret":
			# Fixed on the ground: only scrolls past with the terrain, firing
			# slow aimed shots while the player flies low enough to threaten.
			position.y += vy
			_charge_t += 1
			if _charge_t > _fire_period:
				_charge_t = 0
				if _player_in_ground_attack_band() and absf(position.y - GameState.py) < 2.5:
					_fire_turret_shot()
		"tank":
			# Crawls with the ground while tracking the player's x lane,
			# firing faster than a turret.
			position.y += vy
			vx = lerpf(vx, clampf(GameState.px - position.x, -1.0, 1.0) * 0.004, 0.02)
			position.x += vx
			_charge_t += 1
			if _charge_t > _fire_period:
				_charge_t = 0
				if _player_in_ground_attack_band() and absf(position.y - GameState.py) < 2.5:
					_fire_turret_shot()
		"radar", "depot":
			# Passive installations: radar calls in extra raiders while alive
			# (see EnemySpawner); depots burst into salvage when destroyed.
			position.y += vy
		"midboss", "boss":
			# Boss: tracks the player's altitude band (always engageable),
			# slides in from the top, strafes, alternates aimed fans & rings.
			alt = lerpf(alt, GameState.alt / GameState.ALT_MAX, 0.015)
			position.z = GameState.enemy_z(alt)
			position.y = lerpf(position.y, 1.1, 0.012)
			var span := 1.3 if enemy_type == "midboss" else 1.8
			position.x = lerpf(position.x, sin(t * 0.013) * span, 0.02)
			_charge_t += 1
			var period := 70 if enemy_type == "midboss" else 45
			if _charge_t >= period:
				_charge_t = 0
				if (t / period) % 2 == 0:
					_fire_aimed_fan()
				else:
					_fire_ring()
		"wisp":
			# Dense sine ribbon: fast horizontal weave, steady descent. Popcorn.
			position.x += vx + sin(float(t) * 0.18 + _spiral_cx * 3.0) * 0.024
			position.y += vy
			rotation_degrees.z = sin(float(t) * 0.18) * 24.0
		"orbiter":
			# Circles a guide point that drifts down the screen at vy.
			if not _orbit_ready:
				_orbit_ready = true
				_orbit_cy = position.y
				_spiral_radius = 0.0
			_orbit_cy += vy
			_spiral_radius = minf(_spiral_radius + 0.004, 0.42)
			_spiral_angle += 0.12
			position.x = _spiral_cx + cos(_spiral_angle) * _spiral_radius
			position.y = _orbit_cy + sin(_spiral_angle) * _spiral_radius
			rotation_degrees.z += 6.0
		"splitter":
			position.x += vx + sin(float(t) * 0.04) * 0.006
			position.y += vy
			_charge_t += 1
			if _charge_t > _fire_period:
				_charge_t = 0
				if is_in_player_range():
					_fire_turret_shot()
		"shard":
			# Brief fast scatter from a dead splitter, settling into a fall.
			position.x += vx
			position.y += vy
			vx = lerpf(vx, 0.0, 0.03)
			vy = lerpf(vy, -0.013, 0.025)
			rotation_degrees.z += 9.0
		"lancer":
			if t < _dash_at:
				# Hold the line, drifting down slowly until this lancer's turn.
				position.x += vx
				position.y += vy
			else:
				if not _dive_armed:
					_dive_armed = true
					vx = clampf(GameState.px - position.x, -1.6, 1.6) * 0.020
					vy = -0.034 * (1.0 + 0.40 * GameState.difficulty())
				position.x += vx
				position.y += vy
				rotation_degrees.x = lerpf(rotation_degrees.x, -30.0, 0.16)
				rotation_degrees.z = lerpf(rotation_degrees.z, clampf(-vx * 700.0, -34.0, 34.0), 0.16)
		"mirror":
			# Twin formation: left/right breathe in unison (sign keyed off spawn x).
			position.x += vx + sin(float(t) * 0.09) * 0.012 * signf(_spiral_cx if absf(_spiral_cx) > 0.01 else 1.0)
			position.y += vy
			_charge_t += 1
			if _charge_t > _fire_period:
				_charge_t = 0
				if is_in_player_range():
					_fire_turret_shot()
		"corkscrew":
			# 'a': form up briefly, then corkscrew-roll and dive straight at the player.
			if t < 28:
				position.x += vx
				position.y += vy
			else:
				vx = lerpf(vx, clampf(GameState.px - position.x, -1.8, 1.8) * 0.020, 0.06)
				vy = lerpf(vy, -(0.030 + 0.014 * GameState.difficulty()), 0.05)
				position.x += vx
				position.y += vy
				alt = lerpf(alt, GameState.alt / GameState.ALT_MAX, 0.04)
				position.z = GameState.enemy_z(alt)
			rotation_degrees.y += 24.0                                  # the corkscrew roll
			rotation_degrees.x = lerpf(rotation_degrees.x, -26.0 if t >= 28 else 0.0, 0.12)
		"ghost":
			_update_ghost_blob()
		"quad_ring":
			_update_quad_ring()
		"sam_missile":
			_update_sam_missile()
		"gyro_drone":
			_update_gyro_drone()
		"pyramid":
			_update_pyramid_fall()
		"stoneface":
			# 'b': drifts straight down, slow and heavy. It ROCKS in a bounded sway (never a
			# full tumble) so the face keeps glaring at the player.
			position.y += vy
			position.x += sin(float(t) * 0.030) * 0.0035
			rotation_degrees.x = sin(float(t) * 0.018) * 11.0   # nod
			rotation_degrees.y = sin(float(t) * 0.023) * 15.0   # look side to side
			rotation_degrees.z = sin(float(t) * 0.015) * 7.0    # slight roll
			position.z = GameState.enemy_z(alt)
		"bacura":
			# 'c': flips on the X axis (Xevious bacura) as it falls straight down;
			# indestructible (take_hit blocks shots).
			position.y += vy
			rotation_degrees.x += 4.6
			position.z = GameState.enemy_z(alt)
		"splitcannon":
			# 'd': FAST dive to the player → SPLIT open → unleash a BULLET CURTAIN (repeated
			# wide fans from both cannons) → reclose, flip, flee fast. Gimmicks driven below.
			var open := 0.0
			var charge := 0.0
			var recoil := 0.0
			if t < 46:
				vx = lerpf(vx, clampf(GameState.px - position.x, -1.8, 1.8) * 0.030, 0.08)
				vy = lerpf(vy, -0.030, 0.07)
				position.x += vx
				position.y += vy
				alt = lerpf(alt, GameState.alt / GameState.ALT_MAX, 0.07)
			elif t < 108:
				vx = lerpf(vx, 0.0, 0.14)
				vy = lerpf(vy, 0.0, 0.14)
				position.x += vx
				position.y += vy
				open = smoothstep(46.0, 64.0, float(t))
				# Curtain window: a volley every 7 frames (~3 volleys), kicking barrels + flash.
				if t >= 70 and t <= 90:
					charge = 0.55 + 0.45 * sin(float(t) * 0.55)
					recoil = clampf(1.0 - float(t % 7) / 7.0, 0.0, 1.0)
					if (t % 7) == 0 and is_in_player_range():
						_fire_split_cannons()
				else:
					charge = clampf((float(t) - 48.0) / 22.0, 0.0, 1.0) if t < 70 else 0.0
			else:
				open = clampf(1.0 - (float(t) - 108.0) / 22.0, 0.0, 1.0)
				rotation_degrees.z += 12.0                            # flip away
				vy = lerpf(vy, 0.052, 0.09)                           # FAST escape upward
				position.x += vx * 0.5
				position.y += vy
			position.z = GameState.enemy_z(alt)
			var sep := 0.090 + open * 0.175
			if _split_l != null and is_instance_valid(_split_l):
				_split_l.position.x = -sep
			if _split_r != null and is_instance_valid(_split_r):
				_split_r.position.x = sep
			# Muzzle charge swell + fire flash; barrel recoil; core pulse.
			var flash := 1.0 + charge * 2.4
			for m: Node3D in _sc_muzzles:
				if m != null and is_instance_valid(m):
					m.scale = Vector3.ONE * flash
			for br: Node3D in _sc_barrels:
				if br != null and is_instance_valid(br):
					br.position.y = -0.150 + recoil * 0.065
			if _sc_core != null and is_instance_valid(_sc_core):
				_sc_core.scale = Vector3.ONE * (1.0 + open * 0.35 + charge * 0.6)
		"hunter":
			var dx := GameState.px - position.x
			var dy := GameState.py - position.y
			var dist := sqrt(dx * dx + dy * dy)
			if dist > 0.01:
				vx = lerpf(vx, dx / dist * 0.008, 0.025)
				vy = lerpf(vy, dy / dist * 0.008, 0.025)
			position.x += vx
			position.y += vy

func _update_fighter_attack() -> void:
	var player_alt_n := clampf(GameState.alt / GameState.ALT_MAX, 0.0, 1.0)
	if t < 52:
		# Fast dive deep toward the lower screen, banking toward the player's lane.
		var dive_t := float(t) / 52.0
		vx = lerpf(vx, clampf(GameState.px - position.x, -1.5, 1.5) * 0.012, 0.070)
		position.x += vx + sin(t * 0.13) * 0.010
		position.y += vy * lerpf(2.10, 1.22, dive_t)
		alt = lerpf(alt, clampf(player_alt_n + lerpf(0.20, 0.018, dive_t), 0.0, 1.0), 0.075)
		rotation_degrees.x = lerpf(rotation_degrees.x, -30.0, 0.20)
		rotation_degrees.z = lerpf(rotation_degrees.z, clampf(-vx * 1000.0, -38.0, 38.0), 0.24)
	elif t < 68:
		# Attack run near the lower half, snap level and launch missiles.
		vx = lerpf(vx, clampf(GameState.px - position.x, -1.2, 1.2) * 0.005, 0.035)
		position.x += vx
		position.y += vy * 0.16
		alt = lerpf(alt, clampf(player_alt_n + 0.006, 0.0, 1.0), 0.080)
		rotation_degrees.x = lerpf(rotation_degrees.x, 0.0, 0.24)
		rotation_degrees.z = lerpf(rotation_degrees.z, clampf(-vx * 720.0, -20.0, 20.0), 0.20)
		if not _fired and t > 56 and is_in_player_range():
			_fired = true
			_fire_burst_line()
	elif t < 102:
		# Flip hard and leave upward.
		var flip_t := smoothstep(0.0, 1.0, float(t - 68) / 34.0)
		position.x += vx * 0.75
		position.y += absf(vy) * lerpf(0.95, 2.05, flip_t)
		alt = lerpf(alt, clampf(player_alt_n + 0.16, 0.0, 1.0), 0.070)
		rotation_degrees.x = lerpf(0.0, 178.0, flip_t)
		rotation_degrees.z = lerpf(rotation_degrees.z, -clampf(vx * 620.0, -28.0, 28.0), 0.18)
	else:
		position.x += vx * 0.50
		position.y += absf(vy) * 2.20
		alt = lerpf(alt, clampf(player_alt_n + 0.25, 0.0, 1.0), 0.050)
		rotation_degrees.x = lerpf(rotation_degrees.x, 180.0, 0.24)
	position.z = GameState.enemy_z(alt)

func _update_toroid_descent() -> void:
	var player_alt_n := clampf(GameState.alt / GameState.ALT_MAX, 0.0, 1.0)
	var descend_t := clampf(float(t) / 86.0, 0.0, 1.0)
	position.x += vx + sin(t * 0.070) * 0.018
	position.y += vy * lerpf(1.10, 1.80, descend_t)
	var bob := sin(t * 0.075) * 0.040
	alt = lerpf(alt, clampf(player_alt_n + lerpf(0.22, -0.045, descend_t) + bob, 0.0, 1.0), 0.052)
	position.z = GameState.enemy_z(alt)
	rotation_degrees.x += 5.4
	rotation_degrees.y = sin(t * 0.072) * 52.0
	rotation_degrees.z += 4.2 + sin(t * 0.060) * 1.4
	_charge_t += 1
	if _charge_t > _fire_period:
		_charge_t = 0
		if is_in_player_range():
			_fire_ring()

func _update_ghost_blob() -> void:
	var pulse := sin(float(t) * 0.17)
	scale = Vector3(ZAKO_SCALE * (1.0 + pulse * 0.10), ZAKO_SCALE * (1.0 - pulse * 0.08),
		ZAKO_SCALE * (1.0 + absf(pulse) * 0.12))
	position.x += vx + sin(float(t) * 0.070) * 0.018
	position.y += vy + sin(float(t) * 0.110) * 0.006
	alt = lerpf(alt, clampf(GameState.alt / GameState.ALT_MAX + sin(float(t) * 0.040) * 0.040, 0.0, 1.0), 0.020)
	position.z = GameState.enemy_z(alt)
	rotation_degrees.x = sin(float(t) * 0.060) * 8.0
	rotation_degrees.z = sin(float(t) * 0.090) * 12.0
	_charge_t += 1
	if _charge_t > _fire_period:
		_charge_t = 0
		if is_in_player_range():
			_fire_twin_lanes()

func _update_quad_ring() -> void:
	if not _orbit_ready:
		_orbit_ready = true
		_spiral_angle = randf() * TAU
		_spiral_radius = randf_range(0.10, 0.26)
		_spiral_cx = signf(vx) if absf(vx) > 0.001 else (1.0 if position.x < GameState.px else -1.0)
		_orbit_cy = position.y - GameState.py
	_spiral_angle += 0.185
	var side_sway := sin(float(t) * 0.110 + _spiral_radius * 17.0) * 0.018
	var trail_sway := sin(float(t) * 0.072 + _orbit_cy * 4.0) * 0.012
	vx = lerpf(vx, _spiral_cx * (0.020 + GameState.difficulty() * 0.006), 0.028)
	position.x += vx + side_sway
	position.y += vy + trail_sway
	if t > 40:
		position.y = lerpf(position.y, GameState.py + sin(float(t) * 0.050 + _orbit_cy) * 0.42, 0.010)
	if t > 78:
		vx = lerpf(vx, clampf(GameState.px - position.x, -1.4, 1.4) * 0.010 + _spiral_cx * 0.012, 0.018)
	alt = lerpf(alt, clampf(GameState.alt / GameState.ALT_MAX + sin(float(t) * 0.060 + _orbit_cy) * 0.050, 0.0, 1.0), 0.026)
	position.z = GameState.enemy_z(alt)
	rotation_degrees.z += 14.0
	rotation_degrees.x = sin(float(t) * 0.080) * 32.0
	rotation_degrees.y = lerpf(rotation_degrees.y, clampf(-vx * 950.0, -34.0, 34.0), 0.16)
	for i in _quad_rings.size():
		var host := _quad_rings[i]
		if host != null and is_instance_valid(host):
			host.rotation_degrees.z += 14.0 * (-1.0 if (i & 1) == 0 else 1.0)
			host.position.z = sin(float(t) * 0.140 + float(i)) * 0.035
	_charge_t += 1
	if _charge_t > _fire_period:
		_charge_t = 0
		if is_in_player_range():
			_fire_ring()

func _update_sam_missile() -> void:
	if not _orbit_ready:
		_orbit_ready = true
		_spiral_radius = 1.0
	var target_alt := clampf(GameState.alt / GameState.ALT_MAX + 0.04, 0.0, 1.0)
	var exit_t := clampf((float(t) - 66.0) / 46.0, 0.0, 1.0)
	var home_gain := lerpf(0.034, 0.010, exit_t)
	vx = lerpf(vx, clampf(GameState.px - position.x, -1.4, 1.4) * home_gain, 0.090)
	vy = lerpf(vy, 0.056 + 0.018 * GameState.difficulty() + exit_t * 0.030, 0.105)
	position.x += vx
	position.y += vy
	alt = lerpf(alt, lerpf(target_alt, 1.0, exit_t), 0.070)
	position.z = GameState.enemy_z(alt)
	var out_scale := lerpf(1.0, 2.85, exit_t)
	scale = Vector3(out_scale, out_scale, out_scale)
	rotation_degrees.x = lerpf(rotation_degrees.x, 64.0 + exit_t * 18.0, 0.24)
	rotation_degrees.z = lerpf(rotation_degrees.z, clampf(-vx * 1100.0, -42.0, 42.0), 0.22)
	if exit_t >= 1.0 and alt > 0.97:
		queue_free()

func _update_gyro_drone() -> void:
	position.x += vx + sin(float(t) * 0.065) * 0.014
	position.y += vy + sin(float(t) * 0.100) * 0.004
	vx = lerpf(vx, clampf(GameState.px - position.x, -1.4, 1.4) * 0.004, 0.018)
	alt = lerpf(alt, clampf(GameState.alt / GameState.ALT_MAX + sin(float(t) * 0.050) * 0.050, 0.0, 1.0), 0.018)
	position.z = GameState.enemy_z(alt)
	rotation_degrees.z = sin(float(t) * 0.070) * 10.0
	if _gyro_l != null and is_instance_valid(_gyro_l):
		_gyro_l.rotation_degrees.z += 18.0
		_gyro_l.rotation_degrees.x = sin(float(t) * 0.090) * 22.0
	if _gyro_r != null and is_instance_valid(_gyro_r):
		_gyro_r.rotation_degrees.z -= 18.0
		_gyro_r.rotation_degrees.x = -sin(float(t) * 0.090) * 22.0
	_charge_t += 1
	if _charge_t > _fire_period:
		_charge_t = 0
		if is_in_player_range():
			_fire_twin_lanes()

func _update_pyramid_fall() -> void:
	position.x += vx + sin(float(t) * 0.055) * 0.010
	vy = lerpf(vy, minf(vy - 0.00030, -0.026), 0.014)
	position.y += vy * 1.25
	alt = lerpf(alt, clampf(GameState.alt / GameState.ALT_MAX + sin(float(t) * 0.040) * 0.075, 0.0, 1.0), 0.025)
	position.z = GameState.enemy_z(alt)
	rotation_degrees.x += 4.2
	rotation_degrees.y += 2.6
	rotation_degrees.z += 5.8
	_charge_t += 1
	if _charge_t > _fire_period:
		_charge_t = 0
		if is_in_player_range():
			_fire_burst_line()

func _update_combiner() -> void:
	alt = lerpf(alt, GameState.alt / GameState.ALT_MAX, 0.010)
	position.z = GameState.enemy_z(alt)
	position.y = lerpf(position.y, 1.25, 0.018)
	position.x = lerpf(position.x, sin(float(t) * 0.018) * 1.15, 0.026)
	_charge_t += 1
	if _charge_t >= _fire_period and is_in_player_range():
		_charge_t = 0
		var phase := int(t / maxi(_fire_period, 1))
		if (phase & 1) == 0:
			_fire_ring()
		else:
			_fire_burst_line()

# Sniper fan aimed at the player. Difficulty scales bullet speed and widens
# the fan from 3-way to 5-way past rank 0.6.
func _fire_aimed_fan() -> void:
	var d: float = GameState.difficulty()
	var spd := 0.045 * (1.0 + 0.45 * d)
	# Widen the fan with rank: 3-way normally, 5-way past 0.6 (was hardcoded 3-way
	# — the difficulty widening the comment promised never actually happened).
	var half: int = 2 if d > 0.6 else 1
	var base_ang := atan2(GameState.py - position.y, GameState.px - position.x)
	for i in range(-half, half + 1):
		var ang := base_ang + i * 0.14
		var b := EnemyBullet.new()
		b.bullet_type = "fan"
		b.velocity = Vector3(cos(ang), sin(ang), 0.0) * spd
		b.alt = alt
		b.position = position
		get_parent().add_child(b)

# Single slow aimed shot from a ground turret. The bullet keeps the turret's
# ground altitude, so it only threatens a player skimming low — flying at ALT0
# to attack the ground is what exposes you to ground fire.
func _fire_turret_shot() -> void:
	var spd := 0.022 * (1.0 + 0.4 * GameState.difficulty())
	var ang := atan2(GameState.py - position.y, GameState.px - position.x)
	var b := EnemyBullet.new()
	b.bullet_type = "shot"
	b.velocity = Vector3(cos(ang), sin(ang), 0.0) * spd
	b.alt = alt
	b.position = position
	get_parent().add_child(b)

# Full bullet ring (boss pattern).
func _fire_ring() -> void:
	var n := 8 if enemy_type == "midboss" else 10
	var spd := 0.03 * (1.0 + 0.4 * GameState.difficulty())
	var base := randf() * TAU
	for i in n:
		var ang := base + TAU * float(i) / float(n)
		var b := EnemyBullet.new()
		b.bullet_type = "ring"
		b.velocity = Vector3(cos(ang), sin(ang), 0.0) * spd
		b.alt = alt
		b.position = position
		get_parent().add_child(b)

func _update_unit_guard() -> void:
	position.x += vx + sin(t * (0.045 + float(required_unit_id) * 0.007)) * 0.010
	position.y += vy
	_charge_t += 1
	var period := 82 - required_unit_id * 5
	if _charge_t >= period and is_in_player_range():
		_charge_t = 0
		match required_unit_id:
			1:
				_fire_turret_shot()
			2:
				_fire_ring()
			3:
				_fire_aimed_fan()
			4:
				_fire_twin_lanes()
			5:
				_fire_burst_line()

func _fire_twin_lanes() -> void:
	var spd := 0.034 * (1.0 + 0.35 * GameState.difficulty())
	for sx: float in [-0.18, 0.18]:
		var b := EnemyBullet.new()
		b.bullet_type = "lane"
		b.velocity = Vector3(sx, -spd, 0.0)
		b.alt = alt
		b.position = position
		get_parent().add_child(b)

func _fire_split_cannons() -> void:
	# A wide curtain fan from BOTH cannons each volley — a real barrage to weave through.
	var d := GameState.difficulty()
	var spd := 0.030 * (1.0 + 0.5 * d)
	var n := 7                                   # bullets per cannon per volley
	var spread := 0.18
	var jitter := float(t) * 0.05                # rotate the fan a little each volley
	for half: Node3D in [_split_l, _split_r]:
		if half == null or not is_instance_valid(half):
			continue
		var muzzle := position + half.position * scale.x
		var base := atan2(GameState.py - muzzle.y, GameState.px - muzzle.x) + sin(jitter) * 0.10
		for k in n:
			var ang := base + (float(k) - float(n - 1) * 0.5) * spread
			var b := EnemyBullet.new()
			b.bullet_type = "fan"
			b.velocity = Vector3(cos(ang), sin(ang), 0.0) * spd
			b.alt = alt
			b.position = muzzle
			get_parent().add_child(b)

func _fire_burst_line() -> void:
	var spd := 0.040 * (1.0 + 0.35 * GameState.difficulty())
	for i in 3:
		var b := EnemyBullet.new()
		b.bullet_type = "burst"
		b.velocity = Vector3((float(i) - 1.0) * 0.020, -spd, 0.0)
		b.alt = alt
		b.position = position + Vector3((float(i) - 1.0) * 0.08, 0.0, 0.0)
		get_parent().add_child(b)

func _check_bounds() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var sp := camera.unproject_position(global_position)
	var sz := get_viewport().get_visible_rect().size
	if sp.y > sz.y + 120.0 or sp.y < -120.0 or sp.x < -120.0 or sp.x > sz.x + 120.0:
		queue_free()

func take_hit(attacker_unit_id: int = 0) -> bool:
	if enemy_type == "bacura":
		_shield_flash = 5      # indestructible Xevious-style slab: clang, block the shot, survive
		return false
	if required_unit_id > 0 and attacker_unit_id != required_unit_id:
		_shield_flash = 8
		return false
	hp -= 1
	_hit_flash = 10
	if hp <= 0:
		if enemy_type == "depot":
			_drop_depot_loot()
		elif enemy_type == "combiner":
			_drop_combiner_loot()
		elif enemy_type == "midboss":
			_on_guardian_down()
		elif enemy_type == "boss":
			_on_boss_down()
		# Occasionally drop a repair item (heals every owned unit equally).
		if randf() < 0.08:
			var item := RepairItem.new()
			get_parent().add_child(item)
			item.global_position = global_position
		queue_free()
		return true
	return false

# Abyss guardian defeated: count it, release the RELIC and a salvage burst.
func _on_guardian_down() -> void:
	GameState.mid_bosses += 1
	var relic := KeyItem.new()
	get_parent().add_child(relic)
	relic.global_position = global_position
	_drop_depot_loot()
	get_tree().call_group("star_hud", "show_message",
		Loc.pair("ガーディアン撃破  %d / %d", "GUARDIAN DOWN  %d / %d")
			% [GameState.mid_bosses, GameState.BOSS_REQ_BOSSES],
		"RELIC RELEASED - PICK IT UP")

# The OMEGA CORE falls: campaign complete.
func _on_boss_down() -> void:
	GameState.game_clear = true
	GameState.score += 50000
	get_tree().call_group("star_hud", "show_message",
		"OMEGA CORE DESTROYED", "MISSION COMPLETE! THE GALAXY IS YOURS TO ROAM")

# Warehouses burst into salvage: a few resource cubes, often a repair kit.
func _drop_depot_loot() -> void:
	var loot_ids: Array = [PlanetTerrain.CITY, PlanetTerrain.STONE,
		PlanetTerrain.NEON, PlanetTerrain.WOOD]
	for i in 2 + randi() % 2:
		var bd: Dictionary = PlanetTerrain.BLOCK_DEFS[loot_ids[randi() % loot_ids.size()]]
		ResourceItem.spawn(get_parent(), {"res": bd["res"], "color": bd["c"],
			"pos": global_position + Vector3((randf() - 0.5) * 0.3,
				(randf() - 0.5) * 0.3, 0.0), "rare": false})
	if randf() < 0.3:
		var kit := RepairItem.new()
		get_parent().add_child(kit)
		kit.global_position = global_position

func _drop_combiner_loot() -> void:
	var loot_ids: Array = [PlanetTerrain.NEON, PlanetTerrain.CITY,
		PlanetTerrain.STONE, PlanetTerrain.CRYSTAL]
	for i in 5:
		var bd: Dictionary = PlanetTerrain.BLOCK_DEFS[loot_ids[randi() % loot_ids.size()]]
		ResourceItem.spawn(get_parent(), {"res": bd["res"], "color": bd["c"],
			"pos": global_position + Vector3((randf() - 0.5) * 0.55,
				(randf() - 0.5) * 0.45, 0.0), "rare": i == 0})
	var kit := RepairItem.new()
	get_parent().add_child(kit)
	kit.global_position = global_position + Vector3(0.0, 0.12, 0.0)
