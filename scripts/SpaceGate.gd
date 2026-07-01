class_name SpaceGate
extends Node3D

# The BOUNDARY between two star systems: a giant RING gate — a circle of 3D blocks
# standing in space, facing the ship — that crosses space once a navigation leg
# fills (GameState.nav_distance). It scrolls down toward the ship; fly through the
# hoop (like a hula hoop) and the cosmos transitions NATURALLY into the next system.
#
# TWO MODES:
#  - Normal nav gate (default): one full-screen hoop; crossing it is a blind/explore jump.
#  - CHOICE gate (setup_choice): a smaller hoop parked in a horizontal LANE. A found
#    route/boss plate spawns a SET of these side by side (see Main._spawn_route_choice) so
#    the player STEERS through one to choose — 正規ルート(route) / ボス(boss) / 探索(explore).
#    Crossing one resolves its kind and dismisses the unchosen siblings. Extensible to 3+.

const SPAWN_Y := 4.5          # above the visible top so the whole ring enters from the top
const DESPAWN_Y := -4.5       # fully off the bottom → loop back to SPAWN_Y
const SCROLL := 0.012         # descend speed (≈6s to cross)
const RING_R := 2.5         # HUGE hoop — the top looms large into the screen
const RING_SEGMENTS := 20     # 3D blocks around the single ring
const TUBE := 0.5            # block size of each ring segment (chunky)
const TILT_DEG := 90.0         # nearly vertical — it towers facing the ship, no lean
const SPIN_SPEED := 0.5       # slow stargate spin (rad/s)
# "Inside the ring" radius for the pass check — bigger than the visible ring AND the full
# play width (ARENA_HALF_W) so the ship counts as inside the hoop ANYWHERE on screen.
const HOLE_R := 3.4
# Vertical tolerance for the sweep: cross while the ring's plane is within this of the ship,
# checked EVERY frame — so a moving ship can't slip through a single-frame window.
const CROSS_BAND := 0.7

var _crossed := false        # passed through → keep scrolling out, don't pop instantly
var _route := false          # true gate (正規ゲート): armed by a found route panel
var _glow_t := 0.0
# True-gate accent (gold-green) overrides the next-system palette while armed.
const ROUTE_GLOW := Color(0.4, 1.0, 0.5)
var _spin: Node3D            # spins the ring around its facing axis
var _mat_frame: StandardMaterial3D
var _mat_glow: StandardMaterial3D

# --- Choice-gate config (default = normal full-screen nav gate) ---
var _is_choice := false
var _kind := ""              # "route" | "boss" | "explore"
var _slot_x := 0.0           # horizontal lane centre
var _ring_r := RING_R
var _hole_r := HOLE_R

# Configure this gate as one lane of a side-by-side CHOICE set.
func setup_choice(kind: String, slot_x: float, hole_r: float) -> void:
	_is_choice = true
	_kind = kind
	_slot_x = slot_x
	_hole_r = hole_r
	_ring_r = hole_r * 0.82

func _ready() -> void:
	add_to_group("boundary_gate")
	position = Vector3(_slot_x, SPAWN_Y, GameState.alt_to_z(GameState.alt))
	if _is_choice:
		var col := _kind_color()
		_mat_frame = StandardMaterial3D.new()
		_mat_frame.albedo_color = col.darkened(0.72)
		_mat_frame.roughness = 0.6
		_mat_frame.emission_enabled = true
		_mat_frame.emission = col.darkened(0.45)
		_mat_frame.emission_energy_multiplier = 0.8
		_mat_glow = StandardMaterial3D.new()
		_mat_glow.albedo_color = col
		_mat_glow.emission_enabled = true
		_mat_glow.emission = col
		_mat_glow.emission_energy_multiplier = 3.0
	else:
		# The gate wears the NEXT system's palette — a glimpse of what lies beyond it.
		var th: Dictionary = GameState.next_sector_theme()
		_mat_frame = StandardMaterial3D.new()
		_mat_frame.albedo_color = th["base"]
		_mat_frame.roughness = 0.7
		_mat_frame.emission_enabled = true
		_mat_frame.emission = th["struct"]
		_mat_frame.emission_energy_multiplier = 0.7
		_mat_glow = StandardMaterial3D.new()
		_mat_glow.albedo_color = th["accent"]
		_mat_glow.emission_enabled = true
		_mat_glow.emission = th["accent"]
		_mat_glow.emission_energy_multiplier = 3.0
	_build()
	if _is_choice:
		_add_choice_label()

# --- Accessors so Main can tell a plain nav gate from a resolved choice set ---
func is_choice_gate() -> bool:
	return _is_choice

func was_crossed() -> bool:
	return _crossed

func _kind_color() -> Color:
	match _kind:
		"route": return Color(0.4, 1.0, 0.5)
		"boss": return Color(1.0, 0.42, 0.32)
		_: return Color(0.45, 0.8, 1.0)   # explore

func _kind_label() -> String:
	match _kind:
		"route": return Loc.t("ROUTE")
		"boss": return Loc.t("BOSS")
		_: return Loc.t("EXPLORE")

# A camera-facing sign above the hoop so the player can read which lane is which.
func _add_choice_label() -> void:
	var l := Label3D.new()
	l.text = _kind_label()
	l.font_size = 120
	l.pixel_size = 0.004
	l.modulate = _kind_color().lerp(Color.WHITE, 0.35)
	l.outline_size = 14
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 6
	# BELOW the ring (ship-side / leading edge): the gate scrolls DOWN, so its bottom enters
	# the screen FIRST — the label here frames in ahead of the hoop so you read the choice
	# early, before committing.
	l.position = Vector3(0.0, -(_ring_r + 0.7), 0.0)
	add_child(l)

func _block(parent: Node3D, pos: Vector3, size: Vector3, spin_z: float, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	m.mesh = bm
	m.position = pos
	m.scale = size
	m.rotation.z = spin_z
	m.material_override = mat
	parent.add_child(m)

func _build() -> void:
	# A small (near-zero) tilt keeps it nearly vertical; a child node spins it.
	var tilt := Node3D.new()
	tilt.rotation_degrees.x = TILT_DEG
	add_child(tilt)
	_spin = Node3D.new()
	tilt.add_child(_spin)
	# ONE ring of chunky 3D blocks, tangent-aligned (block size scaled to the ring). Every
	# third block glows as an accent so the portal reads — a single ring, not a double one.
	var tube := TUBE * (_ring_r / RING_R)
	for i in RING_SEGMENTS:
		var a := TAU * float(i) / float(RING_SEGMENTS)
		var p := Vector3(cos(a) * _ring_r, sin(a) * _ring_r, 0.0)
		var lit := (i % 3) == 0
		_block(_spin, p, Vector3(tube * 1.7, tube, tube * 1.5), a + PI * 0.5,
			_mat_glow if lit else _mat_frame)

func _process(delta: float) -> void:
	# Park (invisible) when not cruising open space. A gate we've ALREADY crossed
	# keeps scrolling even though GameState.transitioning is now true (it caused that
	# transition) — so it frames out the bottom instead of popping the instant we pass.
	if GameState.stage != "space" or GameState.in_transition() or GameState.arena_active \
			or GameState.final_phase != GameState.FINAL_NONE \
			or (GameState.transitioning and not _crossed):
		visible = false
		return
	visible = true
	# Stay co-planar with the ship so the hole lines up on screen (x stays in its lane).
	position.z = GameState.alt_to_z(GameState.alt)
	position.y -= SCROLL
	# Slow stargate spin + pulsing portal glow.
	_glow_t += delta
	if _spin != null:
		_spin.rotation.z += SPIN_SPEED * delta
	if _is_choice:
		_mat_glow.emission_energy_multiplier = 2.6 + 1.6 * sin(_glow_t * 6.0)
	else:
		# A found route panel arms a NORMAL gate as the true gate (legacy path): recolor its
		# accent blocks gold-green. (Plates now usually spawn a choice set instead.)
		if GameState.route_armed != _route:
			_route = GameState.route_armed
			_mat_glow.albedo_color = ROUTE_GLOW if _route else GameState.next_sector_theme()["accent"]
			_mat_glow.emission = ROUTE_GLOW if _route else GameState.next_sector_theme()["accent"]
		_mat_glow.emission_energy_multiplier = (3.2 if _route else 2.4) + 1.6 * sin(_glow_t * 6.0)
	# The ring sweeps down over the ship. Crossing counts the moment the ring's plane is
	# within CROSS_BAND of the ship — checked EVERY frame (no single-frame window), with the
	# ship inside this gate's own hole (_hole_r, centred on its lane).
	if not _crossed and absf(position.y - GameState.py) <= CROSS_BAND and _any_unit_in_ring():
		_cross()
	if position.y < DESPAWN_Y:
		if _crossed:
			queue_free()           # fully framed out the bottom → now retire it
		else:
			position.y = SPAWN_Y   # swept past without crossing → loop back (choose again)

# True if the ship is within THIS gate's hoop as its plane passes.
func _any_unit_in_ring() -> bool:
	var c := Vector2(position.x, position.y)
	if Vector2(GameState.px, GameState.py).distance_to(c) <= _hole_r:
		return true
	# CHOICE gates are lane-picked by the LEAD only — orbiting formation units can drift
	# into an adjacent lane's hole, which would cross the wrong (or both) gate(s).
	if _is_choice:
		return false
	var main := get_parent()
	if main == null:
		return false
	for uid in GameState.collected_units:
		if int(uid) == 1:
			continue
		var u := main.get_node_or_null("Unit%d" % int(uid)) as Node3D
		if u != null and u.visible \
				and Vector2(u.global_position.x, u.global_position.y).distance_to(c) <= _hole_r:
			return true
	return false

# Crossed the boundary. The gate is NOT freed here — it keeps scrolling and frames out the
# bottom. For a choice gate, resolve by kind and dismiss the unchosen siblings.
func _cross() -> void:
	_crossed = true
	if _is_choice:
		_cross_choice()
		_dismiss_siblings()
		return
	# --- Normal nav gate (blind/explore unless legacy-armed) ---
	var route_gate := GameState.route_armed
	GameState.begin_region_transition()
	get_tree().call_group("star_hud", "reset_for_new_system")
	var th: Dictionary = GameState.next_sector_theme()
	if route_gate:
		GameState.blind_gate_count = 0
		GameState.advance_route()
		if GameState.route_complete():
			get_tree().call_group("star_hud", "show_message",
				Loc.pair("ルート %d - ボス星", "ROUTE %d - THE BOSS STAR") % GameState.route_number(),
				"MINE THIS STAR TO FIND THE BOSS PANEL")
		else:
			get_tree().call_group("star_hud", "show_message",
				Loc.pair("ルート %d 到達", "ROUTE %d REACHED") % GameState.route_number(),
				"FIND THE NEXT ROUTE PANEL")
	else:
		GameState.blind_gate_count += 1
		if GameState.blind_gate_count >= GameState.BLIND_GATE_LIMIT and not GameState.blackhole_active:
			GameState.enter_blackhole()
			get_tree().call_group("star_hud", "show_message",
				"NO ROUTE - THE GATE LEADS NOWHERE", "A BLACK HOLE SWALLOWS THE SHIP")
		else:
			get_tree().call_group("star_hud", "show_message",
				Loc.pair("ゲート通過 - %s", "THROUGH THE GATE - %s") % str(th["name"]),
				"A NEW STAR SYSTEM UNFOLDS")

# Resolve a chosen lane.
func _cross_choice() -> void:
	match _kind:
		"route":
			# 正規ルート: advance the true route by one step (+ the usual system crossfade).
			GameState.begin_region_transition()
			get_tree().call_group("star_hud", "reset_for_new_system")
			GameState.blind_gate_count = 0
			GameState.advance_route()
			if GameState.route_complete():
				get_tree().call_group("star_hud", "show_message",
					Loc.pair("ルート %d - ボス星", "ROUTE %d - THE BOSS STAR") % GameState.route_number(),
					"MINE THIS STAR TO FIND THE BOSS PANEL")
			else:
				get_tree().call_group("star_hud", "show_message",
					Loc.pair("ルート %d 到達", "ROUTE %d REACHED") % GameState.route_number(),
					"FIND THE NEXT ROUTE PANEL")
		"boss":
			# Commit to the final boss: arm it (it spawns once cruising space). No system jump.
			GameState.arm_boss_panel()
			GameState.route_armed = false   # the choice is consumed
			GameState.gate_active = false
			get_tree().call_group("star_hud", "show_message",
				"FINAL BATTLE", "THE BOSS AWAITS - CLIMB AND FIGHT")
		_:
			# 探索: a blind jump into the next system (+ the black-hole streak as before).
			GameState.begin_region_transition()
			get_tree().call_group("star_hud", "reset_for_new_system")
			var th: Dictionary = GameState.next_sector_theme()
			GameState.blind_gate_count += 1
			if GameState.blind_gate_count >= GameState.BLIND_GATE_LIMIT and not GameState.blackhole_active:
				GameState.enter_blackhole()
				get_tree().call_group("star_hud", "show_message",
					"OFF-ROUTE - THE GATE LEADS NOWHERE", "A BLACK HOLE SWALLOWS THE SHIP")
			else:
				get_tree().call_group("star_hud", "show_message",
					Loc.pair("探索 - %s", "EXPLORING - %s") % str(th["name"]),
					"A NEW STAR SYSTEM UNFOLDS")

# Free the unchosen choice gates once a lane is picked.
func _dismiss_siblings() -> void:
	for g in get_tree().get_nodes_in_group("boundary_gate"):
		if g != self and g.has_method("dismiss_choice"):
			g.dismiss_choice()

func dismiss_choice() -> void:
	if _is_choice and not _crossed:
		queue_free()
