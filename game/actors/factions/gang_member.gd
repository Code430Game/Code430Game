class_name GangMember
extends Node3D
## One member of a faction's crew (add-hostile-gang): a rigged body with a weapon in hand, a
## hittable capsule and the threat state the FactionManager steps. Built like an officer so
## one combat path serves both; the manager owns every decision.

enum State { PATROL, ALERT, ATTACK, FLEE, REGROUP, DOWN, TAGGED, RETURNING }

var faction_id: String = ""
var faction_index: int = 0
var turf_index: int = 0
var leader: bool = false
var role_ranged: bool = false  # carries the faction's ranged weapon
var state: int = State.PATROL
var hp: float = 100.0
var toughness: float = 100.0
var last_hit: float = -INF
var cooldown: float = 0.0
var stagger_t: float = 0.0
var state_t: float = 0.0  # seconds in the current state
var goal: Vector3 = Vector3.INF  # where the member is walking to
var pause_t: float = 0.0  # patrol: standing at a waypoint
var seed: int = 0  # the look's random seed (replicated so a guest builds the same body)
var in_car: bool = false  # riding the faction car: hidden until it arrives
var weapon: Dictionary = {}  # the weapon in hand, resolved for the tone ({}: fists)
var rig: CharacterRig
var held: HeldWeapon
var body: FactionBody
var ragdoll: CharacterRagdoll


## True while the member is still in the fight (not down, tagged out or walking back).
func in_fight() -> bool:
	return state <= State.REGROUP


func state_name() -> String:
	return State.keys()[state].to_lower()


## The member's feet position.
func position_xz() -> Vector2:
	return Vector2(global_position.x, global_position.z)
