class_name Explosion
extends Node3D

var color: Color = Color(1.0, 0.6, 0.2)
var count: int = 10
var strength: float = 1.0   # scales particle speed/size (player death uses > 1)

const LIFETIME := 34

var _parts: Array[Dictionary] = []
var _flash: MeshInstance3D
var _flash_mat: ShaderMaterial
var _debris_mat: StandardMaterial3D
var _life: int = 0

func _ready() -> void:
	count = mini(count, 54)
	# White-hot core flash: an edgeless billboard glow (radial falloff, additive) that
	# expands fast and fades in ~12 frames — reads as a burst of light, not a box.
	_flash = MeshInstance3D.new()
	var flash_quad := QuadMesh.new()
	flash_quad.size = Vector2(0.26, 0.26) * strength
	_flash.mesh = flash_quad
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = preload("res://shaders/glow.gdshader")
	_flash_mat.set_shader_parameter("glow_color", Color(1.0, 0.92, 0.72))
	_flash_mat.set_shader_parameter("intensity", 9.0)
	_flash_mat.set_shader_parameter("softness", 2.0)
	_flash.material_override = _flash_mat
	add_child(_flash)

	# All debris share one mesh and one material (they fade in sync);
	# per-particle size variation comes from the node scale.
	var debris_box := BoxMesh.new()
	debris_box.size = Vector3(0.045, 0.026, 0.032) * strength
	_debris_mat = StandardMaterial3D.new()
	_debris_mat.albedo_color = color
	_debris_mat.emission_enabled = true
	_debris_mat.emission = color
	_debris_mat.emission_energy_multiplier = 2.5
	_debris_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	for i in count:
		var m := MeshInstance3D.new()
		m.mesh = debris_box
		m.material_override = _debris_mat
		add_child(m)
		var ang := randf() * TAU
		var spd := (0.036 + randf() * 0.092) * strength
		_parts.append({
			"node": m,
			"base": 0.85 + randf() * 1.6,
			"vel": Vector3(cos(ang) * spd, sin(ang) * spd, (randf() - 0.5) * 0.070 * strength),
			"spin": Vector3(randf() * 34.0 - 17.0, randf() * 34.0 - 17.0, randf() * 34.0 - 17.0),
		})

func _process(_delta: float) -> void:
	_life += 1
	if _life >= LIFETIME:
		queue_free()
		return
	var t := float(_life) / float(LIFETIME)

	var flash_t := clampf(_life / 12.0, 0.0, 1.0)
	_flash.scale = Vector3.ONE * (1.0 + flash_t * 2.6)
	_flash_mat.set_shader_parameter("intensity", 9.0 * (1.0 - flash_t))
	_flash.visible = flash_t < 1.0

	_debris_mat.albedo_color.a = 1.0 - t
	_debris_mat.emission_energy_multiplier = 2.8 * (1.0 - t)
	var shrink := 1.0 - t * 0.6
	for p in _parts:
		var m: MeshInstance3D = p["node"]
		m.position += p["vel"]
		p["vel"] = Vector3(p["vel"].x * 0.94, p["vel"].y * 0.94 - 0.0012 * strength, p["vel"].z * 0.91)
		m.rotation_degrees += p["spin"]
		m.scale = Vector3.ONE * (p["base"] * shrink)
