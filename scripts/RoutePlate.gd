class_name RoutePlate
extends Node3D

# The golden MONOLITH route/boss plate. When a buried plate block is dug out (Planet.gd),
# this spawns AT that block, flies to screen-centre while tumbling, swells huge, holds for
# ~3 s facing the camera, then SPINS out and vanishes. The message is framed ON the slab.
#
# Built procedurally (block-polygon) as a RICH, glossy metal plaque: a layered chamfered
# bezel (several stepped frames), an inset panel, corner brackets, a riveted rim and a
# glowing inlay — with MSDF Label3D text (crisp at any scale, no jaggies) on the face.

const FLY := 0.85          # block → centre (tumble + swell)
const HOLD := 3.0          # held big & steady at centre (the 3-second read)
const EXIT := 0.8          # spin out + shrink + fade
const PLATE_DEPTH := 7.0   # distance in front of the camera it settles
const PLATE_SCALE := 2.0   # final size multiplier

# Wider plaque so the framed text sits comfortably inside the bezel.
const SLAB := Vector3(1.78, 1.74, 0.18)

var is_boss: bool = false
var route_num: int = 1

var _t: float = 0.0
var _from: Vector3 = Vector3.ZERO
var _mats: Array[StandardMaterial3D] = []
var _emis: Array[float] = []
var _labels: Array[Label3D] = []
var _font: Font = null

func setup(world_from: Vector3, boss: bool, num: int) -> void:
	_from = world_from
	is_boss = boss
	route_num = num

func _ready() -> void:
	add_to_group("route_plate")
	_font = _make_font()
	var accent := Color(1.0, 0.42, 0.30) if is_boss else Color(0.45, 1.0, 0.66)
	# --- Glossy metal materials (high metallic, low roughness → strong specular gloss). ---
	var dark   := _mat(Color(0.06, 0.05, 0.03), Color(0.10, 0.07, 0.02), 0.5, 0.9, 0.45)
	var gold   := _mat(Color(0.80, 0.58, 0.16), Color(0.85, 0.55, 0.10), 1.8, 0.95, 0.18)
	var gold_hi := _mat(Color(1.0, 0.84, 0.40), Color(1.0, 0.78, 0.22), 3.0, 1.0, 0.10)
	var panel  := _mat(Color(0.08, 0.07, 0.05), Color(0.16, 0.10, 0.03), 0.8, 0.6, 0.35)
	var glow   := _mat(accent, accent, 3.6, 0.2, 0.3)

	var fz := SLAB.z * 0.5
	# Dark outline plate behind → a crisp border shadow around the gold.
	_box(Vector3(0, 0, -0.03), Vector3(SLAB.x + 0.12, SLAB.y + 0.12, 0.12), dark)
	# Main slab body.
	_box(Vector3.ZERO, SLAB, gold)
	# Layered chamfered bezel: stepped frames rising toward the face for real depth.
	_frame(SLAB.x, SLAB.y, fz + 0.02, 0.12, gold_hi)
	_frame(SLAB.x * 0.90, SLAB.y * 0.90, fz + 0.05, 0.07, gold)
	_frame(SLAB.x * 0.80, SLAB.y * 0.80, fz + 0.075, 0.035, gold_hi)
	# Recessed inner panel the text sits on.
	var iw := SLAB.x * 0.72
	var ih := SLAB.y * 0.72
	_box(Vector3(0, 0, fz - 0.015), Vector3(iw, ih, 0.05), panel)
	# Glowing inlay line just inside the panel + an engraved header divider.
	_frame(iw * 0.99, ih * 0.99, fz + 0.04, 0.012, glow)
	_box(Vector3(0, ih * 0.20, fz + 0.05), Vector3(iw * 0.62, 0.018, 0.05), gold_hi)
	# Corner brackets (L-shaped ornaments) for that engineered, designed look.
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var cx := sx * iw * 0.5
			var cy := sy * ih * 0.5
			_box(Vector3(cx - sx * 0.10, cy, fz + 0.06), Vector3(0.22, 0.05, 0.05), gold_hi)
			_box(Vector3(cx, cy - sy * 0.10, fz + 0.06), Vector3(0.05, 0.22, 0.05), gold_hi)
			_box(Vector3(cx, cy, fz + 0.07), Vector3(0.07, 0.07, 0.05), glow)   # corner stud
	# Riveted rim: studs marching along the top & bottom bezel.
	var rivets := 9
	for i in rivets:
		var rx := lerpf(-SLAB.x * 0.42, SLAB.x * 0.42, float(i) / float(rivets - 1))
		_box(Vector3(rx, SLAB.y * 0.46, fz + 0.03), Vector3(0.045, 0.045, 0.05), gold_hi)
		_box(Vector3(rx, -SLAB.y * 0.46, fz + 0.03), Vector3(0.045, 0.045, 0.05), gold_hi)

	# --- Framed text on the panel (MSDF → crisp, no jaggies). ---
	var head := Loc.t("BOSS PLATE FOUND") if is_boss else Loc.t("ROUTE PLATE FOUND")
	_label(head, Vector3(0, ih * 0.30, fz + 0.07), 30, Color(1.0, 0.96, 0.86), accent)
	if is_boss:
		_label(Loc.t("BOSS"), Vector3(0, -ih * 0.08, fz + 0.07), 96, Color(1.0, 0.98, 0.92), accent)
	else:
		_label(Loc.t("ROUTE"), Vector3(0, ih * 0.02, fz + 0.07), 40, Color(1.0, 0.98, 0.92), accent)
		_label(str(route_num), Vector3(0, -ih * 0.26, fz + 0.07), 150,
			Color(0.82, 1.0, 0.90), accent)
	# Start tiny at the block.
	global_position = _from
	scale = Vector3.ONE * 0.18

func _make_font() -> Font:
	# MSDF system font → resolution-independent, smooth edges at the plate's large scale.
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Helvetica Neue", "Arial", "sans-serif"])
	f.font_weight = 700
	f.multichannel_signed_distance_field = true
	f.msdf_pixel_range = 12
	f.msdf_size = 64
	return f

func _mat(albedo: Color, emis: Color, energy: float, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metal
	m.metallic_specular = 0.9
	m.roughness = rough
	m.emission_enabled = true
	m.emission = emis
	m.emission_energy_multiplier = energy
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats.append(m)
	_emis.append(energy)
	return m

func _box(pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)

# Four bars forming a rectangular ring (a raised bezel step).
func _frame(w: float, h: float, z: float, bar: float, mat: StandardMaterial3D) -> void:
	_box(Vector3(0, h * 0.5, z), Vector3(w + bar, bar, 0.06), mat)    # top
	_box(Vector3(0, -h * 0.5, z), Vector3(w + bar, bar, 0.06), mat)   # bottom
	_box(Vector3(-w * 0.5, 0, z), Vector3(bar, h, 0.06), mat)         # left
	_box(Vector3(w * 0.5, 0, z), Vector3(bar, h, 0.06), mat)          # right

func _label(text: String, pos: Vector3, font_size: int, col: Color, outline: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = _font
	l.font_size = font_size
	l.position = pos
	l.modulate = col
	l.outline_size = maxi(6, font_size / 8)
	l.outline_modulate = Color(outline.r * 0.35, outline.g * 0.35, outline.b * 0.35, 1.0)
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.double_sided = true
	l.no_depth_test = true
	l.render_priority = 4
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	l.pixel_size = 0.0034
	add_child(l)
	_labels.append(l)

func _process(delta: float) -> void:
	_t += delta
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cbasis := cam.global_transform.basis
	var target := cam.global_position + cbasis * Vector3(0.0, 0.0, -PLATE_DEPTH)
	var a := 1.0
	var pos: Vector3
	var sc: float
	var spin := 0.0
	if _t < FLY:
		var k := _ease_out(clampf(_t / FLY, 0.0, 1.0))
		pos = _from.lerp(target, k)
		sc = lerpf(0.18, 1.0, k)
		spin = (1.0 - k) * TAU * 2.0           # tumble in, decelerating to face the camera
	elif _t < FLY + HOLD:
		pos = target
		sc = 1.0
		spin = sin((_t - FLY) * 0.7) * 0.04    # barely-there idle gloss sway
	else:
		var f := clampf((_t - FLY - HOLD) / EXIT, 0.0, 1.0)
		pos = target
		sc = lerpf(1.0, 0.05, _ease_in(f))     # shrink away
		spin = f * f * TAU * 3.0               # accelerating spin-out
		a = 1.0 - f
		if f >= 1.0:
			queue_free()
			return
	# Face the camera (plate +Z toward the viewer), uniform scale, with the spin applied.
	global_transform = Transform3D(cbasis.scaled(Vector3.ONE * sc * PLATE_SCALE), pos)
	rotate_object_local(Vector3.UP, spin)
	_set_alpha(a)

func _set_alpha(a: float) -> void:
	for i in _mats.size():
		var m := _mats[i]
		var c := m.albedo_color
		c.a = a
		m.albedo_color = c
		m.emission_energy_multiplier = _emis[i] * a
	for l in _labels:
		var lc := l.modulate
		lc.a = a
		l.modulate = lc
		var oc := l.outline_modulate
		oc.a = a
		l.outline_modulate = oc

func _ease_out(k: float) -> float:
	return 1.0 - pow(1.0 - k, 3.0)

func _ease_in(k: float) -> float:
	return k * k
