class_name TitleScreen
extends Node3D

# The "GENESIS" title logo, built from BLOCKS and tilted in 3D (Metroid-logo style) over
# the starfield. Each letter is a 3x5 block bitmap. Sits in front of the game camera; it
# is removed when the player starts (Main._start_game), leaving just the space behind.

const CELL := 0.18          # grid pitch between block centers
const BOX := 0.155          # block size (slightly under the pitch → seams read)
const LETTER_GAP := 0.14    # extra space between letters

# 3x5 block font (top row first). N is just its two verticals — its diagonal is drawn
# as a running LIGHT LINE instead of blocks (see _build_n_diagonal).
const FONT := {
	"G": ["111", "100", "101", "101", "111"],
	"E": ["111", "100", "110", "100", "111"],
	"N": ["101", "101", "101", "101", "101"],
	"S": ["111", "100", "111", "001", "111"],
	"I": ["111", "010", "010", "010", "111"],
}

# N diagonal style: "saturn" = a spinning ringed planet whose tilted ring is the stroke;
# "light" = a glowing line with a running spark. Flip to compare.
const N_STYLE := "saturn"
# Keep the ring nearly EDGE-ON (thin ellipse) so it reads as a stroke — NOT face-on (a
# circle). The diagonal lean is done by rotating the whole thing about Z (see _build_n_saturn).
const RING_OPEN := 0.32          # small tip toward camera (0 = pure edge-on line, PI/2 = face-on circle)

var _sparks: Array = []          # {node, a, b, phase} running lights along N diagonals
var _line_mats: Array = []       # the diagonal glow-line materials (pulse in _process)
var _planets: Array = []         # spinning planet bodies (Saturn-N) to rotate in _process
var _ring_lights: Array = []     # {node, mat, r, phase} lights orbiting the Saturn ring

var _t: float = 0.0

func _ready() -> void:
	add_to_group("title_screen")
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.74, 0.92)
	mat.metallic = 0.6
	mat.roughness = 0.32
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.6, 1.0)
	mat.emission_energy_multiplier = 0.8
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.95, 0.97, 1.0)
	accent.metallic = 0.5
	accent.roughness = 0.25
	accent.emission_enabled = true
	accent.emission = Color(0.7, 0.85, 1.0)
	accent.emission_energy_multiplier = 1.4
	# One deep HULL block per cell + a slightly smaller bright FRONT plate. (Previously
	# three boxes overlapped at the same x,y → coplanar side faces = Z-fighting flicker.)
	var hull_box := BoxMesh.new()
	hull_box.size = Vector3(BOX, BOX, 0.18)
	var plate := BoxMesh.new()
	plate.size = Vector3(BOX * 0.92, BOX * 0.92, 0.02)
	var word := "GENESIS"
	# Uniform 5-wide letters laid left to right.
	var total := 0.0
	for li in word.length():
		var rws: Array = FONT.get(word[li], [])
		var cols: int = 0 if rws.is_empty() else (rws[0] as String).length()
		total += float(cols) * CELL
		if li < word.length() - 1:
			total += LETTER_GAP
	var lx := -total * 0.5
	for li in word.length():
		var ch := word[li]
		var rows: Array = FONT.get(ch, [])
		var lcols: int = 0 if rows.is_empty() else (rows[0] as String).length()
		for row in rows.size():
			var bits: String = rows[row]
			for col in bits.length():
				if bits[col] != "1":
					continue
				var cx := lx + float(col) * CELL
				var cy := float(2 - row) * CELL          # row 0 = top
				# Front face uses the bright accent material; depth blocks use the hull.
				# Hull body (centred) + inset bright plate just off its front face.
				_block(Vector3(cx, cy, 0.0), mat, hull_box)
				_block(Vector3(cx, cy, 0.10), accent, plate)
		if ch == "N":
			if N_STYLE == "saturn":
				_build_n_saturn(lx)
			else:
				_build_n_light(lx)
		lx += float(lcols) * CELL + LETTER_GAP   # advance to the next letter
	# Metroid-logo tilt: top recedes, a slight turn for a 3D presence.
	rotation = Vector3(-0.42, 0.26, 0.05)

# Candidate 2 — N's diagonal as a SATURN: a spinning planet in the centre of the letter
# wearing a REAL 3D ring. The ring is built as an ordinary HORIZONTAL Saturn ring (a flat
# banded disc tipped toward the camera = a wide ellipse), then the whole planet+ring is
# simply rotated 45° clockwise vs the logo so the ring lies along the N's diagonal. It may
# extend past the two vertical bars — that's fine.
func _build_n_saturn(lx: float) -> void:
	var c := Vector3(lx + 1.0 * CELL, 0.0, 0.05)               # centre of the letter
	# The N's true diagonal: top of the left bar → bottom of the right bar (3 wide, 5 tall).
	var ang := atan2(-4.0 * CELL, 2.0 * CELL)
	var holder := Node3D.new()
	holder.position = c
	holder.rotation.z = ang                                   # ring's long axis = the N diagonal
	add_child(holder)
	# Faithful Saturn banding: thin concentric discs with gaps (Cassini-like), all parallel
	# (a normal horizontal ring), tipped toward the camera by RING_OPEN.
	# A single tilted ring PLANE holds all the bands (and the orbiting light), so they
	# share the same disc orientation. Tip it toward the camera (thin ellipse).
	var ring_plane := Node3D.new()
	ring_plane.rotation.x = RING_OPEN
	holder.add_child(ring_plane)
	# Thinner ring: narrow bands with clearer gaps; outer ~0.60 spans the diagonal.
	var bands := [
		[0.46, 0.485, Color(0.78, 0.80, 0.88, 0.55)],
		[0.50, 0.55, Color(0.92, 0.93, 1.0, 0.9)],
		[0.565, 0.60, Color(0.72, 0.78, 0.92, 0.5)],
	]
	for band in bands:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = float(band[0])
		torus.outer_radius = float(band[1])
		torus.rings = 24          # tube cross-section = a CIRCLE (was 3 = a triangle!)
		torus.ring_segments = 72  # smooth loop around
		ring.mesh = torus
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = band[2]
		rmat.emission_enabled = true
		rmat.emission = Color(0.7, 0.85, 1.0)
		rmat.emission_energy_multiplier = 1.6
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		ring.material_override = rmat
		ring_plane.add_child(ring)
	# A pure, edgeless LIGHT that orbits the ring forever — a camera-facing billboard glow
	# (radial alpha falloff, additive), so it reads as light, not an object.
	var lite := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.55, 0.55)
	lite.mesh = q
	var lmat := ShaderMaterial.new()
	lmat.shader = preload("res://shaders/glow.gdshader")
	lmat.set_shader_parameter("glow_color", Color(0.85, 0.95, 1.0))
	lmat.set_shader_parameter("intensity", 4.0)
	lmat.set_shader_parameter("softness", 2.6)
	lite.material_override = lmat
	ring_plane.add_child(lite)
	_ring_lights.append({"node": lite, "mat": lmat, "r": 0.525, "phase": randf() * TAU})
	# The planet body, spinning in the centre.
	var planet := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.135
	sm.height = 0.27
	sm.radial_segments = 24
	sm.rings = 12
	planet.mesh = sm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.95, 0.78, 0.45)               # warm gas-giant
	pmat.metallic = 0.2
	pmat.roughness = 0.6
	pmat.emission_enabled = true
	pmat.emission = Color(0.6, 0.4, 0.2)
	pmat.emission_energy_multiplier = 0.5
	planet.material_override = pmat
	planet.position = c
	add_child(planet)
	_planets.append(planet)

# Candidate 1 — N's diagonal as a glowing light line from the top-left block to the
# bottom-right block, plus a bright spark that runs along it.
func _build_n_light(lx: float) -> void:
	var a := Vector3(lx + 0.0 * CELL, 2.0 * CELL, 0.085)        # top-left
	var b := Vector3(lx + 2.0 * CELL, -2.0 * CELL, 0.085)       # bottom-right
	var dir := b - a
	var length := dir.length()
	var ang := atan2(dir.y, dir.x) - PI * 0.5                   # box long axis is +Y
	# The glowing line itself.
	var line := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.05, length, 0.05)
	line.mesh = lb
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.7, 0.95, 1.0)
	lmat.emission_enabled = true
	lmat.emission = Color(0.6, 0.92, 1.0)
	lmat.emission_energy_multiplier = 3.0
	line.material_override = lmat
	line.position = (a + b) * 0.5
	line.rotation.z = ang
	add_child(line)
	_line_mats.append(lmat)
	# The running spark.
	var spark := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.11, 0.11, 0.11)
	spark.mesh = sb
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(1.0, 1.0, 1.0)
	smat.emission_enabled = true
	smat.emission = Color(0.85, 0.97, 1.0)
	smat.emission_energy_multiplier = 6.0
	spark.material_override = smat
	add_child(spark)
	_sparks.append({"node": spark, "a": a, "b": b, "phase": randf()})

func _block(pos: Vector3, mat: Material, mesh: Mesh) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)

func _process(delta: float) -> void:
	# Gentle idle sway so the logo feels alive.
	_t += delta
	rotation.y = 0.26 + 0.05 * sin(_t * 0.6)
	rotation.x = -0.42 + 0.03 * sin(_t * 0.43)
	# Saturn-N: spin each ringed planet in the centre of the letter.
	for pl in _planets:
		(pl as Node3D).rotation.y += delta * 0.9
	# A light orbits each ring forever (brighter as it swings toward the camera).
	for rl in _ring_lights:
		var th: float = float(rl["phase"]) + _t * 1.6
		var r: float = float(rl["r"])
		var n := rl["node"] as Node3D
		n.position = Vector3(cos(th) * r, 0.0, sin(th) * r)   # in the ring's plane
		var front: float = 0.5 + 0.5 * sin(th)               # 1 toward camera, 0 behind
		(rl["mat"] as ShaderMaterial).set_shader_parameter("intensity", 2.5 + 6.0 * front)
	# Light-N: pulse the glow line and run the spark along it (light streaking through).
	for lm in _line_mats:
		(lm as StandardMaterial3D).emission_energy_multiplier = 2.4 + 1.2 * sin(_t * 3.0)
	for s in _sparks:
		var ph: float = fmod(s["phase"] + _t * 0.55, 1.0)
		var n := s["node"] as MeshInstance3D
		n.position = (s["a"] as Vector3).lerp(s["b"] as Vector3, ph)
		# Brightest mid-run, fading at the ends so it reads as a streak that repeats.
		var glow: float = sin(ph * PI)
		(n.material_override as StandardMaterial3D).emission_energy_multiplier = 2.0 + 7.0 * glow
		n.scale = Vector3.ONE * (0.6 + 0.7 * glow)
