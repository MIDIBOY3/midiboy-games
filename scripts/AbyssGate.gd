class_name AbyssGate
extends Node3D

# An INVISIBLE descent marker. The visible hole is the irregular gap carved out
# of the surface terrain (PlanetTerrain._queue_carve); this node just rides the
# same terrain chunk and marks "the ship may sink below alt0 here". Without it,
# the only openings would be every natural surface gap, letting the ship drop
# through anywhere — descent must be a RARE, deliberate hole instead.

const KIND_COLORS := {
	"CAVE":     Color(0.90, 0.60, 0.25),
	"BASE":     Color(0.15, 0.85, 1.00),
	"TEMPLE":   Color(1.00, 0.85, 0.30),
	"LAVACAVE": Color(1.00, 0.40, 0.10),
}
const ENTER_RADIUS := 0.45

var kind: String = "CAVE"
var _entered: bool = false

func _ready() -> void:
	add_to_group("abyss_gates")

# Scrolled off the bottom → tell the terrain it may re-open a hole further on.
func _exit_tree() -> void:
	if _entered or GameState.stage != "planet":
		return
	var terr := get_tree().get_first_node_in_group("planet_terrain")
	if terr != null and is_instance_valid(terr) and not terr.is_queued_for_deletion():
		terr.call("notify_gate_lost")
