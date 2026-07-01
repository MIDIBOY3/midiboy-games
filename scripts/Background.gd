extends Node3D

@export var scroll_speed: float = 0.001
@export var parallax_strength: float = 0.01
@export var bg_scroll_factor: float = 0.06   # starfield scroll per world-Y (parallax; tune live)

@onready var _mesh: MeshInstance3D = $MeshInstance3D

var _scroll_y: float = 0.0
var _bg_last_cam_y: float = 0.0     # forward-progress baseline (per-mode scroll sign)
var _bg_last_zako: bool = false
var _ground_mix: float = 0.0
var _neb_strength: float = 0.0
var _dark_mix: float = 0.0          # eases toward 1 during the black-hole mid-boss
var _mat: ShaderMaterial
var _light: DirectionalLight3D
# backdrop kind → shader strength uniform; smoothed values live in _bg_s.
const BG_KINDS := {
	"sun": "sun_strength", "galaxy": "galaxy_strength", "blackhole": "blackhole_strength",
	"lunar": "lunar_strength", "twin_suns": "twin_strength", "supernova": "supernova_strength",
	"aurora": "aurora_strength", "cluster": "cluster_strength",
}
var _bg_s: Dictionary = {}

func _ready() -> void:
	add_to_group("space_background")  # DeckWalkMode keeps this drifting while the tree is paused
	_mat = _mesh.material_override as ShaderMaterial
	_mat.set_shader_parameter("space_brightness", 0.8)  # 宇宙背景全体の光量（1.0=従来 → 0.8で少し抑える）

func _physics_process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		global_position = camera.global_position + Vector3(0.0, 0.0, -110.0)
		# The background is PART of the 180°-rotated ZAKO world (inherit the camera roll), so the
		# whole world — stars included — scrolls top-to-bottom as the ZAKO advances forward.
		global_rotation = camera.global_rotation
	# Prototype uses the FULL altitude range (LOW/MID/HI = 0..ALT_MAX) so LOW/MID differ; GENESIS
	# keeps its 760-floored sky_t. (sky_t floored everything below 760 to 0, so LOW==MID.)
	var proto := GameState.is_zako_prototype_mode()
	var alt_t: float = clampf(GameState.alt / GameState.ALT_MAX, 0.0, 1.0) if proto else GameState.sky_t()
	var target_planet := get_tree().get_first_node_in_group("target_planet") as TargetPlanet
	var approach := target_planet.approach if target_planet != null else 0.0
	var pass_t := smoothstep(0.18, 0.86, approach)
	# uv_zoom: SMALLER = zoomed in (near), LARGER = zoomed out (far). LOW zooms in more (0.7),
	# HI stays subtle (~1.05). GENESIS keeps the near-flat range.
	var uv_zoom: float     = (lerp(0.7, 1.05, alt_t) if proto else lerp(0.94, 1.06, alt_t))
	uv_zoom = lerpf(uv_zoom, 0.34, pass_t)
	var scroll_mult: float = lerp(2.0, 0.5, alt_t)  # alt0→速い、alt99→遅い
	scroll_mult *= lerpf(1.0, 5.8, pass_t)
	if GameState.in_transition():
		scroll_mult *= 3.0  # 大気圏突入/離脱の加速感
	scroll_mult *= 1.0 + GameState.nav_boost * 2.5  # boost-lane "vroom" rush
	# Background scrolls with the camera's world-Y (moves WITH travel; never drifts when idle).
	# The ZAKO quad is rolled 180°, which FLIPS the shader UV — so with a plain cam_y scroll the
	# STARS ran opposite the (correct, rolled) world objects. Negate the ZAKO contribution so the
	# stars flow top-to-bottom too. Delta-accumulated with a baseline reset on the F9 snap so the
	# starfield never jumps.
	if not GameState.scroll_frozen:                 # ending: the cosmos stops dead
		var zako := GameState.is_zako_mode()
		if zako != _bg_last_zako:
			_bg_last_cam_y = GameState.cam_y
			_bg_last_zako = zako
		var dcam := GameState.cam_y - _bg_last_cam_y
		_bg_last_cam_y = GameState.cam_y
		# ÷ cam_z: HIGH altitude = camera farther = stars crawl; LOW = stars rush by. Pure
		# rendering (the world travel rate itself is constant). Normalised so LOW keeps the tuned
		# rate. This is the altitude→speed feel, camera-only (no shared-world change).
		var alt_speed: float = GameState.CAM_REF_DIST / maxf(GameState.cam_z, 0.01)
		_scroll_y += (-dcam if zako else dcam) * bg_scroll_factor * alt_speed
	# Keep space visible during approach. The planet atmosphere should haze the
	# background, not replace it with a flat biome color.
	var target_mix := 0.0
	if target_planet != null:
		target_mix = smoothstep(0.35, 1.0, approach) * 0.10
	_ground_mix = move_toward(_ground_mix, target_mix, 0.018)
	var sky := Color(0.3, 0.5, 0.7)
	if PlanetTerrain.BIOMES.has(GameState.planet_biome):
		sky = PlanetTerrain.BIOMES[GameState.planet_biome]["sky"]
	_mat.set_shader_parameter("scroll_y", _scroll_y)
	_mat.set_shader_parameter("scroll_x", GameState.px * parallax_strength * lerpf(1.0, 2.6, pass_t))
	_mat.set_shader_parameter("time_val", Time.get_ticks_msec() / 1000.0)
	_mat.set_shader_parameter("zoom", uv_zoom)
	_mat.set_shader_parameter("ground_mix", _ground_mix)
	_mat.set_shader_parameter("sky_color", Vector3(sky.r, sky.g, sky.b))
	# Per-region nebula: fades in over open space, out as a planet's atmosphere
	# takes over. Colors crossfade CONTINUOUSLY between regions (sector_blend) so
	# the sky just keeps drifting into a new nebula as you travel — no warp snap.
	# Black-hole mid-boss: drown the whole sky in an eerie dark void. Eases in/out so the
	# normal starfield + sector backdrop dissolve into a near-black field with a hole.
	var dark_target: float = 1.0 if (GameState.blackhole_active and GameState.stage == "space") else 0.0
	_dark_mix = move_toward(_dark_mix, dark_target, 0.02)
	_mat.set_shader_parameter("dark_mix", _dark_mix)

	var neb_a: Color = GameState.sector_color("neb")
	var neb_b: Color = GameState.sector_color("neb2")
	var neb_target: float = 0.0
	if GameState.stage == "space":
		# Per-system nebula intensity, crossfaded between systems.
		var ns: float = lerpf(
			float(GameState.sector_at(GameState.sector).get("neb_str", 0.6)),
			float(GameState.sector_at(GameState.sector + 1).get("neb_str", 0.6)),
			GameState.sector_blend)
		neb_target = (1.0 - _ground_mix) * ns
	neb_target *= (1.0 - _dark_mix)
	_neb_strength = move_toward(_neb_strength, neb_target, 0.012)
	_mat.set_shader_parameter("nebula_strength", _neb_strength)
	_mat.set_shader_parameter("nebula_a", Vector3(neb_a.r, neb_a.g, neb_a.b))
	_mat.set_shader_parameter("nebula_b", Vector3(neb_b.r, neb_b.g, neb_b.b))

	# Backdrop feature + main light. Each system rolls a kind; across a region crossing
	# the two fade past each other (sector_blend) and the feature position/color, the
	# light energy/colour/angle all lerp, so the change is seamless.
	var blend: float = GameState.sector_blend
	var cur: Dictionary = GameState.sector_at(GameState.sector)
	var nxt: Dictionary = GameState.sector_at(GameState.sector + 1)
	var space_t: float = (1.0 - _ground_mix) if GameState.stage == "space" else 0.0
	for kind in BG_KINDS:
		var tgt: float = lerpf(_backdrop_amt(cur, kind), _backdrop_amt(nxt, kind), blend) * space_t
		# In the void, force OUT every backdrop feature (suns, galaxies, star spheres, even
		# the discrete black-hole ball+ring) — the dark field itself carries the mood.
		tgt *= (1.0 - _dark_mix)
		var cv: float = move_toward(float(_bg_s.get(kind, 0.0)), tgt, 0.02)
		_bg_s[kind] = cv
		_mat.set_shader_parameter(BG_KINDS[kind], cv)
	# Drag the feature to screen-centre and tint it to a hot accretion ring as the void deepens.
	var fx: float = lerpf(lerpf(float(cur.get("feat_x", 0.5)), float(nxt.get("feat_x", 0.5)), blend), 0.5, _dark_mix)
	var fy: float = lerpf(lerpf(float(cur.get("feat_y", 0.5)), float(nxt.get("feat_y", 0.5)), blend), 0.5, _dark_mix)
	_mat.set_shader_parameter("feature_pos", Vector2(fx, fy))
	_mat.set_shader_parameter("feature_seed", float(cur.get("feat_seed", 0.0)))
	var fc: Color = GameState.sector_color("feat").lerp(Color(1.0, 0.52, 0.22), _dark_mix)
	_mat.set_shader_parameter("feature_color", Vector3(fc.r, fc.g, fc.b))
	# Drive the main light in space; the surface stage owns the light via Planet.gd.
	if GameState.stage == "space":
		if _light == null or not is_instance_valid(_light):
			_light = get_tree().current_scene.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
		if _light != null:
			var le: float = lerpf(float(cur.get("light_energy", 1.0)),
				float(nxt.get("light_energy", 1.0)), blend)
			var lc: Color = GameState.sector_color("light_col")
			var lp: float = lerpf(float(cur.get("light_pitch", -45.0)),
				float(nxt.get("light_pitch", -45.0)), blend)
			var ly: float = lerpf(float(cur.get("light_yaw", 45.0)),
				float(nxt.get("light_yaw", 45.0)), blend)
			# The void field (shader, unshaded) stays the darkest in the game. The lone
			# directional light only touches the BOSS — keep it modest + cold-white so the
			# boss reads as a clean HALF-SHADOW (lit side vs shadow side), not blown-out white.
			# (Ambient is already disabled, so a single key light gives the terminator.)
			le *= lerpf(1.0, 1.15, _dark_mix)
			lc = lc.lerp(Color(0.82, 0.88, 1.0), _dark_mix)
			_light.light_energy = lerpf(_light.light_energy, le * 1.0, 0.04)  # 宇宙の全光源を一律0.8倍
			_light.light_color = _light.light_color.lerp(lc, 0.04)
			_light.rotation_degrees = _light.rotation_degrees.lerp(Vector3(lp, ly, 0.0), 0.04)

func _backdrop_amt(d: Dictionary, kind: String) -> float:
	return 1.0 if String(d.get("backdrop", "nebula")) == kind else 0.0
