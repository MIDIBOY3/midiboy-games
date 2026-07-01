class_name HomePlanet
extends Node3D

# The homeworld for the ending — a luminous blue marble meant to read as the grand,
# beautiful counterpoint to the crawl's sorrow. Still lightweight (one shaded sphere +
# two additive atmosphere halos — NO building/structure nodes, so no frame drops).
# The living surface uses the planet_backdrop shader with the homeworld extras turned on:
# a sun-glint sparkle skating over the seas and golden city lights twinkling on the night
# side. set_grow(0..1) swells it; stop_spin() halts the surface rotation near GAME OVER.

const RADIUS := 5.0
# Direction TOWARD the sun (matches Main.tscn's DirectionalLight3D) so the city lights
# glow on the side turned away from it.
const SUN_DIR := Vector3(0.5, 0.707, 0.5)

var _t: float = 0.0
var _spin := true
var _rot_speed := 0.05
var _surf_mat: ShaderMaterial
var decayed := false   # TRUE END: a withered, colour-drained homeworld (set before add_child)

func _ready() -> void:
	add_to_group("home_planet")
	# Living surface (shader-driven land/ocean/cloud, slow self-rotation).
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = RADIUS
	sm.height = RADIUS * 2.0
	sm.radial_segments = 64
	sm.rings = 32
	body.mesh = sm
	_surf_mat = ShaderMaterial.new()
	_surf_mat.shader = preload("res://shaders/planet_backdrop.gdshader")
	# Rich blue-marble palette: deep vivid oceans, lush land, bright caps + clouds.
	_surf_mat.set_shader_parameter("land_color", Color(0.24, 0.52, 0.28))
	_surf_mat.set_shader_parameter("ocean_color", Color(0.05, 0.26, 0.60))
	_surf_mat.set_shader_parameter("pole_color", Color(0.95, 0.98, 1.0))
	_surf_mat.set_shader_parameter("cloud_color", Color(1.0, 1.0, 1.0))
	_surf_mat.set_shader_parameter("pole_amount", 0.38)
	_surf_mat.set_shader_parameter("cloud_amount", 0.50)
	_surf_mat.set_shader_parameter("sea_level", 0.52)
	_surf_mat.set_shader_parameter("rotate_speed", _rot_speed)
	_surf_mat.set_shader_parameter("seed", 1234.0)
	_surf_mat.set_shader_parameter("emission_energy", 0.30)
	# Homeworld extras: sparkling seas + twinkling night-side cities.
	_surf_mat.set_shader_parameter("ocean_glint", 1.6)
	_surf_mat.set_shader_parameter("night_lights", 1.0)
	_surf_mat.set_shader_parameter("sun_dir", SUN_DIR)
	if decayed:
		# Colour-drained, dying world: dead tan land, a faded grey sea, ashen caps/clouds, no
		# sparkle, only a few flickering lights. (The poem's "色褪せた海"・"空に残った灰".)
		_surf_mat.set_shader_parameter("land_color", Color(0.33, 0.29, 0.21))
		_surf_mat.set_shader_parameter("ocean_color", Color(0.17, 0.21, 0.23))
		_surf_mat.set_shader_parameter("pole_color", Color(0.72, 0.70, 0.66))
		_surf_mat.set_shader_parameter("cloud_color", Color(0.66, 0.62, 0.56))
		_surf_mat.set_shader_parameter("cloud_amount", 0.62)
		_surf_mat.set_shader_parameter("ocean_glint", 0.15)
		_surf_mat.set_shader_parameter("night_lights", 0.18)
		_surf_mat.set_shader_parameter("emission_energy", 0.16)
	body.material_override = _surf_mat
	add_child(body)
	# Two stacked atmosphere halos for a deep, glowing limb: a tight bright cyan rim and
	# a wide soft blue glow that the WorldEnvironment bloom spreads into a majestic haze.
	if decayed:
		_add_halo(RADIUS * 1.05, Color(0.62, 0.58, 0.50), 3.0, 0.9, 0.04)   # sickly ashen limb
		_add_halo(RADIUS * 1.22, Color(0.40, 0.36, 0.30), 1.7, 0.5, 0.10)
	else:
		_add_halo(RADIUS * 1.05, Color(0.55, 0.80, 1.0), 3.0, 1.8, 0.06)
		_add_halo(RADIUS * 1.22, Color(0.25, 0.52, 1.0), 1.7, 0.95, 0.14)
	scale = Vector3.ONE * 0.2

func _add_halo(r: float, col: Color, rim_power: float, intensity: float, twinkle: float) -> void:
	var halo := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = r
	hm.height = r * 2.0
	hm.radial_segments = 48
	hm.rings = 24
	halo.mesh = hm
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/home_atmo.gdshader")
	mat.set_shader_parameter("glow_color", col)
	mat.set_shader_parameter("rim_power", rim_power)
	mat.set_shader_parameter("intensity", intensity)
	mat.set_shader_parameter("twinkle", twinkle)
	halo.material_override = mat
	add_child(halo)

func set_grow(t: float) -> void:
	scale = Vector3.ONE * lerpf(0.2, 1.0, clampf(t, 0.0, 1.0))

func stop_spin() -> void:
	_spin = false

func _process(delta: float) -> void:
	_t += delta
	# Surface rotation eases to a halt near GAME OVER (stop_spin).
	_rot_speed = 0.05 if _spin else lerpf(_rot_speed, 0.0, 0.04)
	if _surf_mat != null:
		_surf_mat.set_shader_parameter("rotate_speed", _rot_speed)
