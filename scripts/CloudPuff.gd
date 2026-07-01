class_name CloudPuff
extends Sprite3D

# A single soft billboard cloud blob. The carrier spawns a sea of these during
# an atmosphere-entry dive (Mothership._run_boost "enter"); they drift down and
# slightly toward the camera so the diving carrier slips THROUGH them — some
# puffs pass in front, some behind (real depth), instead of a flat overlay.

static var _tex: Texture2D

var vel: Vector3 = Vector3(0.0, -0.045, 0.02)
var grow: float = 1.006
var tint: Color = Color(1, 1, 1)
var _t: int = 0
var _life: int = 95

static func _puff_texture() -> Texture2D:
	if _tex != null:
		return _tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.95))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.55, Color(1, 1, 1, 0.45))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	_tex = t
	return _tex

func _ready() -> void:
	add_to_group("cloud_puff")
	texture = _puff_texture()
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	shaded = false
	modulate = Color(tint.r, tint.g, tint.b, 0.0)

func _process(_delta: float) -> void:
	_t += 1
	position += vel
	scale *= grow
	var fade_in := clampf(float(_t) / 12.0, 0.0, 1.0)
	var fade_out := clampf(float(_life - _t) / 22.0, 0.0, 1.0)
	modulate.a = minf(fade_in, fade_out) * 0.8
	if _t >= _life or global_position.z > 4.3:
		queue_free()
