class_name GroundBomb
extends Node3D

# Unit1's automatic ground-strike bomb (planet stage only). Released over the
# target sight, it plunges from the ship's altitude toward the destructible
# deck — shrinking as it falls into the distance — then SKIMS forward over the
# surface until it actually reaches something to destroy, so it never fizzles
# over open water or a gap. On impact it craters the surface under it and bursts
# with a loud, legible blast: white core flash, cyan shards, flung terrain
# debris and an expanding shockwave ring.
#
# Deliberately distinct from Unit2's purple anti-air time bomb: a bright cyan
# teardrop that drives straight down (Unit1's colour) instead of a slow violet
# box that drifts forward. Unit1 arms the next drop only after this one has
# struck (active-bomb gating), so the cadence follows the ground impacts.

const SURFACE_Z  := -2.0    # PlanetTerrain.ALT0_Z: the destructible deck plane
const FALL       := 0.05    # z descent per frame toward the surface
const END_SCALE  := 0.4     # how small it reads once it reaches the surface
const SKIM_SPEED := 0.045   # forward (+Y) glide while hunting a target
const SKIM_MAX   := 200     # frames skimming before it just detonates anyway
const BLAST_FRAMES := 18    # shockwave-ring animation length

enum { DROP, SKIM, BLAST }

var radius: float = 0.4
var target: Vector2 = Vector2.ZERO   # world XY the sight marked at launch

var _state: int = DROP
var _start_z: float = 0.0
var _skim_t: int = 0
var _blast_t: int = 0
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D

func _ready() -> void:
	_start_z = global_position.z
	_mesh = MeshInstance3D.new()
	# Teardrop: a sphere stretched along its fall axis.
	var sph := SphereMesh.new()
	sph.radius = 0.05
	sph.height = 0.16
	_mesh.mesh = sph
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.5, 0.95, 1.0)
	_mat.emission_enabled = true
	_mat.emission = Color(0.3, 0.85, 1.0)
	_mat.emission_energy_multiplier = 2.2
	_mesh.material_override = _mat
	add_child(_mesh)

func _process(_delta: float) -> void:
	match _state:
		DROP:  _do_drop()
		SKIM:  _do_skim()
		BLAST: _do_blast()

# Fall to the deck over the sight, shrinking into the distance as it drops.
func _do_drop() -> void:
	global_position.x = lerpf(global_position.x, target.x, 0.12)
	global_position.y = lerpf(global_position.y, target.y, 0.12)
	global_position.z = move_toward(global_position.z, SURFACE_Z, FALL)
	# Shrink with depth: full size at release, END_SCALE at the surface — the
	# "下に向かって縮小していく" plunge that reads it as dropping away from camera.
	var k := 0.0
	if _start_z > SURFACE_Z:
		k = clampf(inverse_lerp(_start_z, SURFACE_Z, global_position.z), 0.0, 1.0)
	scale = Vector3.ONE * lerpf(1.0, END_SCALE, k)
	_spin()
	if global_position.z <= SURFACE_Z + 0.0001:
		_state = SKIM

# Glide forward just over the deck until a real block is within blast reach.
func _do_skim() -> void:
	global_position.y += SKIM_SPEED
	global_position.z = SURFACE_Z
	_spin()
	_skim_t += 1
	var terr := get_tree().get_first_node_in_group("planet_terrain")
	if terr == null:
		_begin_blast(false)
		return
	if terr.has_block(global_position.x, global_position.y, radius) or _skim_t >= SKIM_MAX:
		_begin_blast(true)

func _spin() -> void:
	_mesh.rotation_degrees += Vector3(7.0, 11.0, 5.0)
	_mat.emission_energy_multiplier = 2.0 + 0.8 * sin(float(Engine.get_frames_drawn()) * 0.4)

# Crater the surface and kick off the legible destruction burst.
func _begin_blast(hit: bool) -> void:
	_state = BLAST
	_mesh.visible = false
	var p := Vector3(global_position.x, global_position.y, SURFACE_Z)
	if hit:
		var terr := get_tree().get_first_node_in_group("planet_terrain")
		if terr != null:
			for drop: Dictionary in terr.blast(p, radius):
				ResourceItem.spawn(get_parent(), drop)

	# Three stacked bursts read as a real demolition: a white-hot core, cyan
	# energy shards, and brown terrain rubble flung out of the crater.
	_burst(p, Color(1.0, 1.0, 0.95), 24, 2.4)
	_burst(p, Color(0.45, 0.9, 1.0), 22, 1.7)
	_burst(p, Color(0.6, 0.45, 0.3), 18, 1.5)

	# Flat shockwave ring lying on the deck, expanding outward.
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.16
	torus.outer_radius = 0.22
	_ring.mesh = torus
	_ring.rotation_degrees.x = 90.0   # lie the ring flat in the XY plane (faces camera)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color(0.7, 0.95, 1.0)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color(0.5, 0.9, 1.0)
	_ring_mat.emission_energy_multiplier = 3.0
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring.material_override = _ring_mat
	add_child(_ring)
	_ring.global_position = p
	scale = Vector3.ONE

func _burst(p: Vector3, col: Color, count: int, strength: float) -> void:
	var ex := Explosion.new()
	ex.color = col
	ex.count = count
	ex.strength = strength
	get_parent().add_child(ex)
	ex.global_position = p

func _do_blast() -> void:
	_blast_t += 1
	var t := float(_blast_t) / float(BLAST_FRAMES)
	_ring.scale = Vector3.ONE * lerpf(1.0, radius * 9.0, t)
	_ring_mat.albedo_color.a = 1.0 - t
	_ring_mat.emission_energy_multiplier = 3.0 * (1.0 - t)
	if _blast_t >= BLAST_FRAMES:
		queue_free()
