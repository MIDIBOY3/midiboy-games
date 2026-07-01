extends Control

const TRACK_X:   float = 28.0
const TOP_Y:     float = 100.0
const BOTTOM_Y:  float = 980.0
const TRACK_W:   float = 6.0
const MARKER_W:  float = 22.0
const MARKER_H:  float = 6.0

# Motion-debug: rolling min/max of Unit5's transform to expose any oscillation.
var _u5_rotx_min := 0.0
var _u5_rotx_max := 0.0
var _u5_posy_min := 0.0
var _u5_posy_max := 0.0
var _u5_posz_min := 0.0
var _u5_posz_max := 0.0
var _u5_visible := true
var _u5_samples := 0

# Additive (glowing) overlay for the altitude actor markers — drawn on its own Node2D so only the
# markers use the ADD blend (a neon glow over the ships), not the whole HUD.
var _mk_layer: Node2D

func _ready() -> void:
	_mk_layer = Node2D.new()
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_mk_layer.material = m
	add_child(_mk_layer)
	_mk_layer.draw.connect(_draw_actor_alt_markers)

func _process(_delta: float) -> void:
	if _mk_layer != null:
		_mk_layer.queue_redraw()
	if GameState.motion_debug:
		var u5 := get_node_or_null("/root/Main/Unit5") as Node3D
		if u5 != null:
			var rx := u5.rotation_degrees.x
			var py := u5.global_position.y
			var pz := u5.global_position.z
			if _u5_samples == 0 or GameState.frame % 90 == 0:
				_u5_rotx_min = rx; _u5_rotx_max = rx
				_u5_posy_min = py; _u5_posy_max = py
				_u5_posz_min = pz; _u5_posz_max = pz
			_u5_rotx_min = minf(_u5_rotx_min, rx); _u5_rotx_max = maxf(_u5_rotx_max, rx)
			_u5_posy_min = minf(_u5_posy_min, py); _u5_posy_max = maxf(_u5_posy_max, py)
			_u5_posz_min = minf(_u5_posz_min, pz); _u5_posz_max = maxf(_u5_posz_max, pz)
			_u5_visible = u5.visible
			_u5_samples += 1
	queue_redraw()

func _draw() -> void:
	if GameState.ending_active:
		return   # ending crawl owns the screen
	var font: Font   = ThemeDB.fallback_font
	var sz:   Vector2 = get_viewport().get_visible_rect().size

	_draw_alt_gauge(font)
	# (actor altitude markers are drawn on the additive _mk_layer, see _ready)
	_draw_boost_lanes(font)
	_draw_life_bars(font, sz)
	_draw_score(font, sz)
	_draw_exp_and_levels(font, sz)
	_draw_resource_panel(font, sz)
	# GENESIS enemy/lock HUD (up-down arrows, Unit3 missile-lock ring/diamonds) — replaced by the
	# clean SF altitude brackets in the ZAKO prototype, so skip them there.
	if not GameState.is_zako_prototype_mode():
		_draw_enemy_markers()
		_draw_lock_ring()
		_draw_lock_markers()
	if GameState.is_zako_mode():
		_draw_build_hud(font, sz)
	_draw_golden_gauge(font, sz)
	_draw_hubris_gauge(font, sz)
	_draw_nav_gauge(font, sz)
	_draw_motion_debug(font, sz)

# Zako terrain-paint HUD: a build GAUGE bar, the build LAYER (from the ZAKO's altitude), a paint
# state readout, and whether the current spot is paintable (green) or why not (red).
func _draw_build_hud(font: Font, sz: Vector2) -> void:
	var mgr := get_tree().get_first_node_in_group("enemy_front_mgr")
	if mgr == null:
		return
	var gmax: float = maxf(1.0, float(mgr.call("gauge_max")))
	var gval: float = clampf(GameState.build_credits, 0.0, gmax)
	var layer_name: String = ["LOW", "MID", "HIGH"][clampi(GameState.build_layer, 0, 2)]
	var ok := GameState.build_reason == ""
	var px := 24.0
	var py := sz.y * 0.44
	var w := 200.0
	draw_rect(Rect2(px - 8.0, py - 22.0, w, 96.0), Color(0.02, 0.04, 0.07, 0.72))
	var hint := "PAINT (R3)  △ erase"
	draw_string(font, Vector2(px, py - 7.0), "ZAKO TERRAIN", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.85, 1.0))
	draw_string(font, Vector2(px, py + 12.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.62, 0.7))
	# Gauge bar.
	var bw := w - 24.0
	var by := py + 26.0
	draw_rect(Rect2(px, by, bw, 12.0), Color(0.12, 0.14, 0.18, 0.9))
	var frac := gval / gmax
	var bar_col := Color(0.25, 0.9, 1.0) if GameState.build_painting else Color(0.3, 0.7, 0.95)
	if frac < 0.2:
		bar_col = Color(1.0, 0.4, 0.3)
	draw_rect(Rect2(px, by, bw * frac, 12.0), bar_col)
	draw_string(font, Vector2(px, by + 34.0), "LAYER %s" % layer_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(0.72, 0.82, 0.92))
	var status := "READY" if ok else _build_reason_text(GameState.build_reason)
	draw_string(font, Vector2(px + 92.0, by + 34.0), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(0.3, 1.0, 0.45) if ok else Color(1.0, 0.42, 0.36))

func _build_reason_text(r: String) -> String:
	match r:
		"occupied": return "OCCUPIED"
		"full": return "BAND FULL"
		"locked": return "LOCKED (near HERO)"
		"too_close": return "TOO CLOSE"
		"too_far": return "TOO FAR"
		"no_credits": return "NO CREDITS"
		"no_gauge": return "GAUGE EMPTY"
		"turret_dense": return "TURRET DENSITY"
		"socket": return "SOCKET MISMATCH"
		"blocked_route": return "WOULD BLOCK ROUTE"
		_: return r.to_upper()

func _draw_alt_gauge(font: Font) -> void:
	if GameState.is_zako_prototype_mode():
		_draw_proto_gauge(font)
		return
	var in_space := GameState.stage == "space"
	var amin: float = GameState.ARENA_FLOOR_ALT if GameState.arena_active else GameState.GROUND_ALT
	var amax: float = GameState.ARENA_CEIL_ALT if GameState.arena_active else GameState.ALT_MAX
	var span: float = amax - amin

	var marker_y: float = lerp(BOTTOM_Y, TOP_Y, clampf((GameState.alt - amin) / span, 0.0, 1.0))
	var marker_col := Color(0.5, 1.0, 0.88, 0.95)
	var fill_color := Color(0.25, 0.65, 1.0, 0.32)
	var label_col  := Color(0.55, 0.8, 1.0, 0.55)

	draw_rect(Rect2(TRACK_X - TRACK_W * 0.5, TOP_Y, TRACK_W, BOTTOM_Y - TOP_Y), Color(0.1, 0.22, 0.34, 0.42))

	draw_rect(Rect2(TRACK_X - TRACK_W * 0.5, marker_y, TRACK_W, BOTTOM_Y - marker_y), fill_color)

	var tick_col := Color(0.4, 0.65, 0.9, 0.4)
	for i in range(int(amin), int(amax) + 1, 20):
		var ty: float = lerp(BOTTOM_Y, TOP_Y, (float(i) - amin) / span)
		var hw: float = 5.0 if i % 40 == 0 else 3.0
		draw_rect(Rect2(TRACK_X - hw - TRACK_W * 0.5, ty - 1.0, hw * 2.0 + TRACK_W, 2.0), tick_col)

	draw_rect(
		Rect2(TRACK_X - MARKER_W * 0.5, marker_y - MARKER_H * 0.5, MARKER_W, MARKER_H),
		marker_col
	)

	draw_string(font, Vector2(TRACK_X - 12.0, TOP_Y - 8.0), "%d" % int(amax), HORIZONTAL_ALIGNMENT_CENTER, -1, 13, label_col)
	draw_string(font, Vector2(TRACK_X - 12.0, BOTTOM_Y + 18.0), "%d" % int(amin), HORIZONTAL_ALIGNMENT_CENTER, -1, 13, label_col)
	draw_string(font, Vector2(TRACK_X + 12.0, TOP_Y + 4.0), Loc.t("ALT"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 1.0, 0.9, 0.7))
	if GameState.stage == "planet":
		var type_col := Color(1.0, 0.35, 0.28, 0.86)
		if GameState.planet_type == "mine":
			type_col = Color(1.0, 0.78, 0.18, 0.9)
		elif GameState.planet_type == "rescue":
			type_col = Color(0.35, 1.0, 0.92, 0.9)
		draw_string(font, Vector2(TRACK_X + 12.0, TOP_Y + 22.0),
			GameState.planet_type.to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, type_col)

	# Mothership landing band on the alt track: the runway line is the FLOOR
	# and the boardable zone extends a good margin above it (the carrier sits
	# beneath the player when altitudes "match").
	for node in get_tree().get_nodes_in_group("mothership"):
		if not in_space:
			continue
		var ship := node as Node3D
		if ship == null or not is_instance_valid(ship):
			continue
		var sa: Variant = ship.get("ship_alt")
		if sa == null:
			continue
		var deck_a: float = float(sa)
		var floor_y: float = lerp(BOTTOM_Y, TOP_Y, clampf((deck_a - amin) / span, 0.0, 1.0))
		var low_band: float = lerp(BOTTOM_Y, TOP_Y, clampf((deck_a - 15.0 - amin) / span, 0.0, 1.0))
		var ma := 0.18 + 0.08 * sin(GameState.frame * 0.15)
		draw_rect(Rect2(TRACK_X - 12.0, floor_y, 24.0, low_band - floor_y),
			Color(0.3, 1.0, 0.5, ma))
		# Solid runway line at the bottom of the band.
		draw_rect(Rect2(TRACK_X - 14.0, floor_y - 2.0, 28.0, 4.0), Color(0.35, 1.0, 0.55, 0.9))
		draw_string(font, Vector2(TRACK_X + 18.0, floor_y + 5.0), "M",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.35, 1.0, 0.55, 0.9))

# Boost lanes navigate via the alt track: a steady cyan chevron marks each live
# lane's altitude, and an amber blinking chevron previews the next incoming lane —
# climb/dive to that altitude, then steer onto the glowing strip on screen.
func _draw_boost_lanes(font: Font) -> void:
	if GameState.stage != "space":
		return
	var amin: float = GameState.GROUND_ALT
	var span: float = GameState.ALT_MAX - amin
	for la_v in GameState.boost_lane_alts:
		var y: float = lerp(BOTTOM_Y, TOP_Y, clampf((float(la_v) - amin) / span, 0.0, 1.0))
		_draw_lane_chevron(y, Color(0.3, 0.95, 1.0, 0.95))
	if GameState.boost_lane_warn_alt >= 0.0:
		var wy: float = lerp(BOTTOM_Y, TOP_Y,
			clampf((GameState.boost_lane_warn_alt - amin) / span, 0.0, 1.0))
		var blink: float = 0.35 + 0.55 * absf(sin(GameState.frame * 0.18))
		var wc := Color(1.0, 0.85, 0.2, blink)
		_draw_lane_chevron(wy, wc)
		draw_string(font, Vector2(TRACK_X + 34.0, wy + 4.0), Loc.t("BOOST"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, wc)

func _draw_lane_chevron(y: float, col: Color) -> void:
	draw_rect(Rect2(TRACK_X - 9.0, y - 1.5, 18.0, 3.0), col)
	for k in 2:
		var ox: float = TRACK_X + 14.0 + float(k) * 7.0
		draw_line(Vector2(ox, y - 7.0), Vector2(ox + 7.0, y), col, 2.0)
		draw_line(Vector2(ox + 7.0, y), Vector2(ox, y + 7.0), col, 2.0)

# Right side: one vertical life bar per owned unit (Unit1 is widest, rightmost).
# A unit's bar blinks when its life is low.
func _draw_life_bars(font: Font, sz: Vector2) -> void:
	# Robot form runs off one shared pool → the per-unit bars give way to the
	# Golden gauge (drawn separately).
	if GameState.golden_active:
		return
	var height: float = BOTTOM_Y - TOP_Y
	var drawn := 0
	for i in 5:
		var uid := i + 1
		if uid != 1 and uid not in GameState.collected_units:
			continue
		var bw: float = 10.0 if uid == 1 else 6.0
		var tx: float = sz.x - TRACK_X - float(drawn) * 16.0
		var col: Color = UNIT_HUD_COLORS[i]
		draw_rect(Rect2(tx - bw * 0.5, TOP_Y, bw, height), Color(col.r, col.g, col.b, 0.18))
		var life_t := clampf(GameState.unit_life[i] / GameState.life_cap(), 0.0, 1.0)
		var fh: float = height * life_t
		var a := 0.85
		if life_t <= 0.3 and (GameState.frame % 30) >= 20:
			a = 0.3
		draw_rect(Rect2(tx - bw * 0.5, BOTTOM_Y - fh, bw, fh), Color(col.r, col.g, col.b, a))
		drawn += 1
	draw_string(font, Vector2(sz.x - TRACK_X - 30.0, TOP_Y - 8.0), Loc.t("LIFE"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 1.0, 0.7, 0.6))

func _draw_score(font: Font, sz: Vector2) -> void:
	var label := "%s  %08d" % [Loc.t("SCORE"), GameState.score]
	var col   := Color(1.0, 0.95, 0.4, 0.92)
	draw_string(font, Vector2(sz.x * 0.5 - 84.0, 36.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)

# Lock-on circle around the player (Unit3 owned, formation mode):
# enemies the player sweeps it over get locked.
func _draw_lock_ring() -> void:
	if GameState.lock_ring_radius <= 0.0:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var p := Vector3(GameState.px, GameState.py, GameState.alt_to_z(GameState.alt))
	var c := camera.unproject_position(p)
	var edge := camera.unproject_position(p + Vector3(GameState.lock_ring_radius, 0.0, 0.0))
	var r := c.distance_to(edge)
	var col := Color(1.0, 0.8, 0.15, 0.6)
	# Rotating dashed circle.
	var segs := 8
	var base := GameState.frame * 0.02
	for i in segs:
		var a0: float = base + TAU * float(i) / float(segs)
		draw_arc(c, r, a0, a0 + TAU / float(segs) * 0.6, 8, col, 2.0)

# Gold pulsing diamonds on enemies locked by Unit3's missile system.
func _draw_lock_markers() -> void:
	if GameState.lock_targets.is_empty():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var col := Color(1.0, 0.8, 0.15, 0.95)
	var idx := 0
	for e in GameState.lock_targets:
		# Validate BEFORE casting: `as Node3D` on an already-freed locked enemy throws
		# "Trying to cast a freed object", so the is_instance_valid check must come first.
		if not is_instance_valid(e):
			continue
		var en := e as Node3D
		if en == null:
			continue
		var sp := camera.unproject_position(en.global_position)
		var rr: float = 26.0 * (1.0 + 0.12 * sin(GameState.frame * 0.35 + idx))
		var pts := PackedVector2Array([
			sp + Vector2(0, -rr), sp + Vector2(rr, 0),
			sp + Vector2(0, rr), sp + Vector2(-rr, 0),
		])
		for i in 4:
			draw_line(pts[i], pts[(i + 1) % 4], col, 2.0)
		idx += 1

const UNIT_HUD_COLORS := [
	Color(0.85, 0.95, 1.0),
	Color(0.7, 0.35, 0.95),
	Color(0.95, 0.75, 0.1),
	Color(0.35, 0.85, 0.35),
	Color(1.0, 0.5, 0.1),
]

func _draw_exp_and_levels(font: Font, sz: Vector2) -> void:
	# EXP bar under the score (fills toward the next orb spawn).
	var t := clampf(float(GameState.exp_points) / float(GameState.exp_next), 0.0, 1.0)
	var bx := sz.x * 0.5 - 110.0
	draw_rect(Rect2(bx, 46.0, 220.0, 6.0), Color(0.2, 0.3, 0.45, 0.5))
	draw_rect(Rect2(bx, 46.0, 220.0 * t, 6.0), Color(0.4, 1.0, 0.7, 0.8))
	draw_string(font, Vector2(bx + 226.0, 53.0), Loc.t("EXP"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 1.0, 0.8, 0.6))

	# Per-unit levels along the bottom edge.
	for i in 5:
		var x := 70.0 + i * 86.0
		var owned: bool = (i + 1) in GameState.collected_units
		var col: Color = UNIT_HUD_COLORS[i] if owned else Color(0.4, 0.45, 0.5, 0.5)
		var label := ("U%d Lv%d" % [i + 1, GameState.unit_levels[i]]) if owned else ("U%d ---" % (i + 1))
		if owned and GameState.unit_levels[i] >= 5:
			label = "U%d MAX" % (i + 1)
		draw_string(font, Vector2(x, sz.y - 24.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)

	# Difficulty rank (bottom-right) and the debug-spawn indicator.
	draw_string(font, Vector2(sz.x - 150.0, sz.y - 24.0),
		"%s %3d%%" % [Loc.t("RANK"), int(GameState.difficulty() * 100.0)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.7, 0.3, 0.8))

	# (Old GUARDIANS/RELICS campaign readout removed — route system replaces it.)
	if GameState.debug_endless_spawn:
		draw_string(font, Vector2(sz.x - 180.0, 60.0), "%s [E]" % Loc.t("DEBUG SPAWN"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.3, 0.3, 0.9))

func _draw_resource_panel(font: Font, sz: Vector2) -> void:
	# Durability upgrade readout, top-right, clear ABOVE the LIFE bars (TOP_Y). Three tidy
	# rows: title + current Lv (header), a clean progress bar, then a meaning line — so no
	# number sits ON the bar.
	var x := sz.x - 245.0
	var w := 190.0
	var y := 38.0
	var lvl := GameState.dura_level
	var maxed: bool = lvl >= GameState.DURA_MAX
	# res_pool keeps accruing while mining and is only spent when docked, so it can already
	# cover several FUTURE levels. Simulate the buy chain to find how many whole levels it
	# can afford right now (`buyable`), the highest reachable level (`reach`), and the
	# leftover that has carried into the in-progress level (`pool` / `part_need`).
	var pool := GameState.res_pool
	var sim_lvl := lvl
	var buyable := 0
	while sim_lvl < GameState.DURA_MAX and pool >= GameState.dura_cost_at(sim_lvl):
		pool -= GameState.dura_cost_at(sim_lvl)
		sim_lvl += 1
		buyable += 1
	var reach := sim_lvl
	var part_maxed: bool = sim_lvl >= GameState.DURA_MAX
	var part_need := 1 if part_maxed else GameState.dura_cost_at(sim_lvl)
	var part_t := 1.0 if part_maxed else clampf(float(pool) / float(maxi(part_need, 1)), 0.0, 1.0)
	# Header: title (left) + current → reachable level (right). The "→N" makes it plain
	# in text how many levels the banked resources can still buy.
	draw_string(font, Vector2(x, y + 10.0), Loc.t("DURABILITY"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.95, 1.0, 0.92))
	var lvtxt: String
	if maxed:
		lvtxt = "Lv MAX"
	elif buyable > 0:
		lvtxt = "Lv %d→%d" % [lvl, reach]
	else:
		lvtxt = "Lv %d" % lvl
	var lvw := font.get_string_size(lvtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, Vector2(x + w - lvw, y + 10.0), lvtxt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(1.0, 0.92, 0.55, 0.95) if maxed else Color(0.85, 1.0, 0.8, 0.95))
	# Progress bar. Each whole level already banked is a full-width band in its own color,
	# drawn oldest-outermost so newer ones nest inside as visible frames — the carry-over
	# stacks up left-to-right and the colors change so you can read how much has rolled over.
	var by := y + 16.0
	var bh := 11.0
	draw_rect(Rect2(x, by, w, bh), Color(0.06, 0.10, 0.14, 0.85))
	if maxed:
		draw_rect(Rect2(x, by, w, bh), Color(0.95, 0.82, 0.30, 0.9))
	else:
		var shown := mini(buyable, 6)
		for i in shown:
			var inset := float(i) * 2.0
			draw_rect(Rect2(x, by + inset, w, bh - inset * 2.0), _dura_layer_col(i))
		# In-progress level on top (a new color, growing from the left).
		if not part_maxed:
			var inset2 := float(shown) * 2.0
			draw_rect(Rect2(x, by + inset2, w * part_t, bh - inset2 * 2.0), _dura_layer_col(shown))
	draw_rect(Rect2(x, by, w, bh), Color(0.4, 0.7, 0.9, 0.5), false, 1.0)
	# Meaning line BELOW the bar: life cap + carry-over state.
	var sub: String
	if maxed:
		sub = "%s %d - %s" % [Loc.t("LIFE CAP"), int(GameState.life_cap()), Loc.t("MAXED")]
	elif buyable > 0:
		var tail := "MAX" if part_maxed else ("%d/%d" % [pool, part_need])
		sub = "%s %d - %s%dLv - %s" % [
			Loc.t("LIFE CAP"), int(GameState.life_cap()), Loc.t("CARRY"), buyable, tail]
	else:
		sub = "%s %d - %s %d/%d" % [
			Loc.t("LIFE CAP"), int(GameState.life_cap()), Loc.t("NEXT LV"),
			GameState.res_pool, part_need]
	draw_string(font, Vector2(x, by + bh + 11.0), sub,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.88, 0.95, 0.72))

# Distinct color per stacked durability carry-over layer, cycling so each rolled-over
# level reads as a different band.
func _dura_layer_col(i: int) -> Color:
	const COLS := [
		Color(0.25, 0.95, 0.65, 0.9),  # green  – base level
		Color(0.35, 0.75, 1.00, 0.9),  # blue
		Color(0.95, 0.55, 0.85, 0.9),  # magenta
		Color(1.00, 0.78, 0.35, 0.9),  # amber
		Color(0.70, 0.95, 0.40, 0.9),  # lime
	]
	return COLS[i % COLS.size()]

# While the Golden robot is active (the 10 s G-icon power) the per-unit life bars
# give way to ONE bold gauge counting the time left — gold, pulsing, turning hot as
# it runs low — with a big "GOLDEN" / seconds-remaining readout.
func _draw_golden_gauge(font: Font, sz: Vector2) -> void:
	if not GameState.golden_active:
		return
	var t := clampf(float(GameState.golden_timer) / float(GameState.GOLDEN_DURATION), 0.0, 1.0)
	var w := 440.0
	var h := 20.0
	var bx := sz.x * 0.5 - w * 0.5
	var by := 64.0
	var pulse := 0.6 + 0.4 * sin(GameState.frame * 0.12)
	draw_rect(Rect2(bx - 3.0, by - 3.0, w + 6.0, h + 6.0), Color(0.3, 0.2, 0.0, 0.7))
	draw_rect(Rect2(bx, by, w, h), Color(0.18, 0.13, 0.02, 0.75))
	var fc := Color(1.0, 0.82, 0.2) if t > 0.25 else Color(1.0, 0.45, 0.12)
	draw_rect(Rect2(bx, by, w * t, h), Color(fc.r, fc.g, fc.b, 0.55 + 0.4 * pulse))
	draw_string(font, Vector2(bx - 86.0, by + 15.0), Loc.t("GOLDEN"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.85, 0.3, 0.95))
	draw_string(font, Vector2(bx + w * 0.5 - 18.0, by + 15.0),
		"%.1f" % (float(GameState.golden_timer) / 60.0),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.12, 0.09, 0.0, 0.95))

# 慢心 (Hubris) gauge — shown only once the full 5-unit formation hits durability Lv15+.
# It creeps up per kill; at MAX the ship stops firing (soak in the 温泉 to reset). Frozen
# (and harmless) during boss / mid-boss fights, which the gauge calls out.
func _draw_hubris_gauge(font: Font, sz: Vector2) -> void:
	if not GameState.hubris_unlocked():
		return
	var x := sz.x - 245.0
	var w := 190.0
	var y := 86.0   # tucked just under the durability panel (top-right)
	var t := clampf(GameState.hubris / GameState.HUBRIS_MAX, 0.0, 1.0)
	var suspended := GameState.hubris_suspended()
	var blocking := GameState.hubris_blocking_fire()
	var pulse := 0.5 + 0.5 * sin(GameState.frame * 0.18)
	# Header: title (left) + state (right).
	draw_string(font, Vector2(x, y + 10.0), Loc.t("HUBRIS"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.7, 0.55, 0.92))
	var state := ""
	var scol := Color(0.85, 0.8, 0.75, 0.9)
	if suspended:
		state = Loc.t("UNLOCKING")
		scol = Color(0.6, 0.95, 1.0, 0.92)
	elif blocking:
		state = Loc.t("MAX NO FIRE")
		scol = Color(1.0, 0.35, 0.3, 0.6 + 0.4 * pulse)
	var sw := font.get_string_size(state, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, Vector2(x + w - sw, y + 10.0), state,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, scol)
	# Bar.
	var by := y + 16.0
	var bh := 11.0
	draw_rect(Rect2(x, by, w, bh), Color(0.12, 0.06, 0.05, 0.85))
	var fcol := Color(0.5, 0.7, 0.8, 0.5) if suspended \
		else (Color(1.0, 0.3, 0.25, 0.55 + 0.4 * pulse) if blocking \
		else Color(0.95, 0.55, 0.3).lerp(Color(1.0, 0.3, 0.2), t))
	if not suspended and not blocking:
		fcol.a = 0.9
	draw_rect(Rect2(x, by, w * t, bh), fcol)
	draw_rect(Rect2(x, by, w, bh), Color(0.9, 0.5, 0.4, 0.5), false, 1.0)
	# Meaning line below the bar.
	var sub: String
	if suspended:
		sub = Loc.t("MID-BOSS: HUBRIS SUSPENDED")
	elif blocking:
		sub = Loc.t("SOAK IN THE CARRIER ONSEN")
	else:
		sub = "%s %d/%d" % [Loc.t("KILLS BUILD HUBRIS"),
			int(GameState.hubris), int(GameState.HUBRIS_MAX)]
	draw_string(font, Vector2(x, by + bh + 11.0), sub,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.92, 0.8, 0.74, 0.72))

# Boundary readout (space only): a bottom-center bar. While cruising it fills with
# the leg's progress to the next boundary gate; when the gate is up it blinks a
# "fly through" cue; during the crossing it shows the fade into the new system.
# The current system's name reads beneath it.
func _draw_nav_gauge(font: Font, sz: Vector2) -> void:
	if GameState.stage != "space" or GameState.in_transition():
		return
	var th := GameState.sector_theme()
	var nx := GameState.next_sector_theme()
	var w := 320.0
	var bx := sz.x * 0.5 - w * 0.5
	var by := sz.y - 58.0
	var col: Color = GameState.sector_color("struct")
	var t: float = GameState.sector_blend if GameState.transitioning else GameState.nav_t()
	draw_rect(Rect2(bx, by, w, 9.0), Color(0.06, 0.09, 0.13, 0.7))
	draw_rect(Rect2(bx, by, w * t, 9.0), Color(col.r, col.g, col.b, 0.85))
	draw_rect(Rect2(bx, by, w, 9.0), Color(col.r, col.g, col.b, 0.3), false, 1.0)
	if GameState.transitioning:
		draw_string(font, Vector2(bx, by - 6.0), "▸ %s %s" % [Loc.t("CROSSING INTO"), str(nx["name"])],
			HORIZONTAL_ALIGNMENT_CENTER, w, 14, Color(1.0, 0.92, 0.45, 0.9))
	elif GameState.gate_active:
		var blink := 0.5 + 0.5 * sin(GameState.frame * 0.22)
		draw_string(font, Vector2(bx, by - 6.0), "◯ %s ◯" % Loc.t("STAR GATE - FLY THROUGH"),
			HORIZONTAL_ALIGNMENT_CENTER, w, 14, Color(1.0, 0.9, 0.35, 0.5 + 0.45 * blink))
	else:
		draw_string(font, Vector2(bx, by - 6.0), "%s - %s %d" % [
			Loc.t("DEEP SPACE"), Loc.t("SECTOR"), GameState.sector + 1],
			HORIZONTAL_ALIGNMENT_CENTER, w, 13, Color(0.7, 0.9, 1.0, 0.8))
	draw_string(font, Vector2(bx, by + 24.0),
		str(nx["name"]) if GameState.transitioning else str(th["name"]),
		HORIZONTAL_ALIGNMENT_CENTER, w, 14, Color(col.r, col.g, col.b, 0.9))

# Motion-check sandbox overlay: live pose values + the manual trigger keys, so
# the humanoid motions can be inspected and any idle flicker isolated.
func _draw_motion_debug(font: Font, sz: Vector2) -> void:
	# The arena drives motion_debug internally (to stand the Golden) — it's not the pose sandbox
	# there, so suppress the overlay in the arena (normal play shows no debug text; the "[G to
	# exit]" hint is misleading there anyway). Only the real F5/G sandbox (motion_debug without the
	# arena) shows it.
	if not GameState.motion_debug or GameState.arena_active:
		return
	var x := 60.0
	var y := 150.0
	draw_string(font, Vector2(x, y), "%s [G %s]" % [Loc.t("MOTION DEBUG"), Loc.t("TO EXIT")],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.5, 0.9, 0.95))
	var lines := [
		"robot_t %.3f   golden %ds   active %s" % [
			GameState.robot_t, GameState.golden_timer, str(GameState.golden_active)],
		"Z punch %.2f (side %d)" % [GameState.robot_punch, GameState.robot_punch_side],
		"X kick  %.2f (side %d)" % [GameState.robot_kick, GameState.robot_kick_side],
		"V laser %.2f    B rocket %.2f" % [GameState.robot_laser_pose, GameState.robot_rocket_pose],
		"R drop robot   (enemies frozen)",
	]
	# Live Unit5 transform RANGE over the last ~90 frames — if a row shows a wide
	# min..max while the robot stands still, that value is the oscillator.
	if _u5_samples > 0:
		lines.append("U5 rotX  %.1f .. %.1f" % [_u5_rotx_min, _u5_rotx_max])
		lines.append("U5 posY  %.3f .. %.3f" % [_u5_posy_min, _u5_posy_max])
		lines.append("U5 posZ  %.3f .. %.3f" % [_u5_posz_min, _u5_posz_max])
		lines.append("U5 visible %s" % str(_u5_visible))
	var ly := y + 26.0
	for line: String in lines:
		draw_string(font, Vector2(x, ly), line,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.8, 0.95, 0.85))
		ly += 22.0

func _draw_enemy_markers() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var sz     := get_viewport().get_visible_rect().size
	var col_lock := Color(1.0, 0.9, 0.2, 0.85)
	var r  := 18.0
	var br := r * 0.55

	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Node3D
		if e == null or not is_instance_valid(e):
			continue

		var sp := camera.unproject_position(e.global_position)
		if sp.x < -400 or sp.x > sz.x + 400 or sp.y < -400 or sp.y > sz.y + 400:
			continue

		if e.has_method("is_in_player_range") and e.call("is_in_player_range"):
			# 高度一致: マーカー（円弧 + 隅ブラケット）
			draw_arc(sp, r, 0.0, TAU, 24, col_lock, 2.0)
			for dx: float in [-1.0, 1.0]:
				for dy: float in [-1.0, 1.0]:
					var cx := sp.x + dx * r * 0.7
					var cy := sp.y + dy * r * 0.7
					draw_line(Vector2(cx, cy), Vector2(cx + dx * br, cy), col_lock, 1.5)
					draw_line(Vector2(cx, cy), Vector2(cx, cy + dy * br), col_lock, 1.5)
		else:
			# 高度ずれ: 上下矢印
			var e_alt: Variant = e.get("alt")
			if e_alt == null:
				continue
			var alt_diff: float = float(e_alt) * GameState.ALT_MAX - GameState.alt
			var abs_diff := absf(alt_diff)
			if abs_diff > 55.0:
				continue
			var alpha := lerpf(0.75, 0.2, abs_diff / 55.0)
			var col_arr := Color(0.45, 0.85, 1.0, alpha)
			var hw := 8.0
			var ah := 13.0
			if alt_diff > 0.0:
				# 敵が高い → ▲ (画面上向き)
				draw_colored_polygon(PackedVector2Array([
					Vector2(sp.x,       sp.y - ah),
					Vector2(sp.x - hw,  sp.y + 1.0),
					Vector2(sp.x + hw,  sp.y + 1.0),
				]), col_arr)
			else:
				# 敵が低い → ▽ (画面下向き)
				draw_colored_polygon(PackedVector2Array([
					Vector2(sp.x,       sp.y + ah),
					Vector2(sp.x - hw,  sp.y - 1.0),
					Vector2(sp.x + hw,  sp.y - 1.0),
				]), col_arr)

# --- ZAKO prototype altitude gauge (continuous 0..100, 8 notches, aim band, enemy red marks) ---
func _alt_y(a: float) -> float:
	return lerp(BOTTOM_Y, TOP_Y, clampf(a / GameState.ALT_MAX, 0.0, 1.0))

func _draw_proto_gauge(font: Font) -> void:
	var self_alt: float = GameState.alt
	draw_rect(Rect2(TRACK_X - TRACK_W * 0.5, TOP_Y, TRACK_W, BOTTOM_Y - TOP_Y), Color(0.1, 0.22, 0.34, 0.5))
	# Aim band: within ±1 notch of the SELF you're "aligned" (can hit / ◯). Highlight it.
	var band: float = GameState.ALT_ALIGN_BAND
	var by1: float = _alt_y(self_alt + band)
	var by0: float = _alt_y(self_alt - band)
	draw_rect(Rect2(TRACK_X - TRACK_W * 0.5 - 3.0, by1, TRACK_W + 6.0, by0 - by1), Color(0.4, 1.0, 0.6, 0.16))
	# Fill from the marker down.
	var my: float = _alt_y(self_alt)
	draw_rect(Rect2(TRACK_X - TRACK_W * 0.5, my, TRACK_W, BOTTOM_Y - my), Color(0.25, 0.65, 1.0, 0.30))
	# 8 notches.
	for i in range(GameState.ALT_GAUGE_DIV + 1):
		var ty: float = lerp(BOTTOM_Y, TOP_Y, float(i) / float(GameState.ALT_GAUGE_DIV))
		var hw: float = 6.0 if (i == 0 or i == GameState.ALT_GAUGE_DIV) else 4.0
		draw_rect(Rect2(TRACK_X - hw - TRACK_W * 0.5, ty - 1.0, hw * 2.0 + TRACK_W, 2.0), Color(0.5, 0.72, 0.95, 0.5))
	# Current marker + numeric 0..100 (to the right of the track).
	draw_rect(Rect2(TRACK_X - MARKER_W * 0.5, my - MARKER_H * 0.5, MARKER_W, MARKER_H), Color(0.5, 1.0, 0.88, 0.98))
	draw_string(font, Vector2(TRACK_X + 14.0, my + 5.0), "%d" % GameState.alt_display(self_alt),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 1.0, 0.9, 1.0))
	# Enemy altitudes in RED — drawn ON TOP (after the self marker) so they stay visible even
	# next to it. A bold red bar + a small pointer arrow on the right.
	for ea in _enemy_alts():
		var ey: float = _alt_y(ea)
		draw_rect(Rect2(TRACK_X - 11.0 - TRACK_W * 0.5, ey - 2.5, 22.0 + TRACK_W, 5.0), Color(1.0, 0.20, 0.16, 0.98))
		draw_colored_polygon(PackedVector2Array([
			Vector2(TRACK_X + 15.0 + TRACK_W * 0.5, ey - 6.0),
			Vector2(TRACK_X + 15.0 + TRACK_W * 0.5, ey + 6.0),
			Vector2(TRACK_X + 5.0 + TRACK_W * 0.5, ey)]), Color(1.0, 0.20, 0.16, 0.95))
	draw_string(font, Vector2(TRACK_X + 12.0, TOP_Y - 6.0), "100", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.9, 1.0, 0.6))
	draw_string(font, Vector2(TRACK_X + 12.0, BOTTOM_Y + 14.0), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.9, 1.0, 0.6))

# Enemy altitudes (0..ALT_MAX) to red-mark on the gauge.
func _enemy_alts() -> Array:
	var out: Array = []
	# The opposing faction's actor is ALWAYS marked (ZAKO sees the HERO's altitude; HERO sees the
	# ZAKO's) so you can always read the altitude gap.
	out.append(GameState.hero_alt if GameState.is_zako_mode() else GameState.zako_alt)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e) or e.has_meta("local_zako_unit"):
			continue
		var a: Variant = e.get("alt")
		out.append((clampf(float(a), 0.0, 1.0) * GameState.ALT_MAX) if a != null else 0.0)
	if not get_tree().get_nodes_in_group("enemy_front").is_empty():
		out.append(0.0)                                      # the front sits at ground
	return out

# --- △ (above) / ◯ (aligned) / ▽ (below) marker over each enemy/opponent vs the SELF's altitude ---
func _draw_actor_alt_markers() -> void:
	if not GameState.is_zako_prototype_mode():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var self_alt: float = GameState.alt
	var items: Array = []
	if GameState.is_zako_mode():
		items.append([Vector3(GameState.hero_pos.x, GameState.hero_pos.y, GameState.alt_z(GameState.hero_alt)), GameState.hero_alt])
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e) or e.has_meta("local_zako_unit"):
			continue
		var a: Variant = e.get("alt")
		items.append([(e as Node3D).global_position, (float(a) * GameState.ALT_MAX) if a != null else 0.0])
	for t in get_tree().get_nodes_in_group("enemy_front"):
		if t != null and is_instance_valid(t):
			items.append([(t as Node3D).global_position, 0.0])
	var sz := get_viewport().get_visible_rect().size
	for it in items:
		var wp: Vector3 = it[0]
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		if sp.x < -20.0 or sp.x > sz.x + 20.0 or sp.y < -20.0 or sp.y > sz.y + 20.0:
			continue
		_draw_rel_marker(_mk_layer, sp, GameState.alt_rel(self_alt, float(it[1])))

# Large △ / ◯ / ▽ overlaid ON the actor, drawn on the ADDITIVE layer `ci` so it GLOWS (neon)
# over the ship instead of using an ugly outline. Layered (soft fill → mid → bright core) so the
# additive blend builds a bloom. YELLOW △ = above · RED ◯ = aligned (aim band) · BLUE ▽ = below.
func _draw_rel_marker(ci: CanvasItem, sp: Vector2, rel: int) -> void:
	var col: Color
	if rel > 0:
		col = Color(1.0, 0.85, 0.12, 1.0)      # above → yellow
	elif rel < 0:
		col = Color(0.22, 0.6, 1.0, 1.0)       # below → blue
	else:
		col = Color(1.0, 0.22, 0.16, 1.0)      # aligned → red
	var r := 26.0
	var mid := Color(col.r, col.g, col.b, 0.35)    # faint soft halo (thin)
	if rel == 0:                               # ◯
		ci.draw_arc(sp, r, 0.0, TAU, 48, mid, 2.0)
		ci.draw_arc(sp, r, 0.0, TAU, 48, col, 1.0)
		return
	var pts: PackedVector2Array
	if rel > 0:                                # △
		pts = PackedVector2Array([Vector2(sp.x - r, sp.y + r * 0.72), Vector2(sp.x, sp.y - r), Vector2(sp.x + r, sp.y + r * 0.72)])
	else:                                      # ▽
		pts = PackedVector2Array([Vector2(sp.x - r, sp.y - r * 0.72), Vector2(sp.x, sp.y + r), Vector2(sp.x + r, sp.y - r * 0.72)])
	var line := PackedVector2Array(pts)
	line.append(pts[0])
	ci.draw_polyline(line, mid, 2.0)
	ci.draw_polyline(line, col, 1.0)
