extends RefCounted
## Pure rules of the boss fight: hearts, deflect counter, duel tug-of-war and
## difficulty scaling. No nodes, no timers: the scene drives it and reads it,
## so every rule here is unit-testable.

enum Phase { THROW, DUEL, SNITCH, WON, LOST }

## Duel round results returned by [method tick_duel].
const ROUND_NONE := 0
const ROUND_PLAYER_WON := 1
const ROUND_VILLAIN_WON := -1

var cfg: Dictionary
var phase: Phase = Phase.THROW
var villain_hearts: int
var player_hearts: int
var deflects: int = 0
## Tug position of the beam clash: -1 = at the player, +1 = at the villain.
var tug: float = 0.0


func _init(config: Dictionary) -> void:
	cfg = config
	villain_hearts = int(cfg.villain_max_hearts)
	player_hearts = int(cfg.player_max_hearts)


## Hearts the villain has already lost; drives all difficulty scaling.
func hearts_lost() -> int:
	return int(cfg.villain_max_hearts) - villain_hearts


## Counts a consecutive spell hit on the villain ([member deflects] is the
## streak). Returns true when he must come down for the Priori Incantatum duel.
func register_deflect() -> bool:
	if phase != Phase.THROW:
		return false
	deflects += 1
	if deflects >= int(cfg.deflects_to_duel):
		start_duel()
		return true
	return false


## A shot that missed the villain breaks the streak of consecutive hits.
func register_miss() -> void:
	if phase == Phase.THROW:
		deflects = 0


## The player was hit by a piece or lost a duel.
func register_player_hit() -> void:
	if phase == Phase.WON or phase == Phase.LOST:
		return
	player_hearts = max(player_hearts - 1, 0)
	if player_hearts == 0:
		phase = Phase.LOST


func start_duel() -> void:
	phase = Phase.DUEL
	tug = 0.0


## One key press during the duel pushes the clash toward the villain.
func mash() -> void:
	if phase == Phase.DUEL:
		tug = min(tug + float(cfg.mash_power), 1.0)


func villain_push_rate() -> float:
	return float(cfg.villain_push) + float(cfg.villain_push_per_heart) * hearts_lost()


## Advances the duel. [param surge] is extra instantaneous push (villain burst).
func tick_duel(delta: float, surge: float = 0.0) -> int:
	if phase != Phase.DUEL:
		return ROUND_NONE
	# Win is checked before the push: mash() clamps at 1.0, so pushing first
	# would make a full tug unreachable on any real frame.
	if tug < 1.0:
		tug = max(tug - villain_push_rate() * delta - surge, -1.0)
	if tug >= 1.0:
		villain_hearts -= 1
		deflects = 0
		phase = Phase.SNITCH if villain_hearts <= 0 else Phase.THROW
		return ROUND_PLAYER_WON
	if tug <= -1.0:
		deflects = 0
		phase = Phase.THROW
		register_player_hit()
		return ROUND_VILLAIN_WON
	return ROUND_NONE


func catch_snitch() -> void:
	if phase == Phase.SNITCH:
		phase = Phase.WON


func throw_interval() -> float:
	return max(float(cfg.throw_interval) + float(cfg.throw_interval_per_heart) * hearts_lost(),
		float(cfg.throw_interval_min))


func brick_flight_time() -> float:
	return max(float(cfg.brick_flight_time) + float(cfg.brick_flight_time_per_heart) * hearts_lost(),
		float(cfg.brick_flight_time_min))


func cursed_chance() -> float:
	return clamp(float(cfg.cursed_chance) + float(cfg.cursed_chance_per_heart) * hearts_lost(), 0.0, 0.6)


## Seconds between lightning volleys; shrinks as the villain loses hearts.
func lightning_interval() -> float:
	return max(float(cfg.lightning_interval) + float(cfg.lightning_interval_per_heart) * hearts_lost(),
		float(cfg.lightning_interval_min))


## How many bolts fall per volley; grows as the villain loses hearts.
func lightning_bolts() -> int:
	return mini(int(cfg.lightning_bolts) + int(float(cfg.lightning_bolts_per_heart) * hearts_lost()),
		int(cfg.lightning_bolts_max))


## True when a bolt landing [param distance] metres from the player hurts them.
func lightning_hits(distance: float) -> bool:
	return distance < float(cfg.lightning_radius)


## Number of levels in [param config] (at least one).
static func level_count(config: Dictionary) -> int:
	return maxi((config.get("levels", []) as Array).size(), 1)


## A copy of [param config] with the overrides of level [param level]
## (0-based, clamped) applied on top. The base is never modified.
static func config_for_level(config: Dictionary, level: int) -> Dictionary:
	var merged: Dictionary = config.duplicate(true)
	var levels: Array = config.get("levels", [])
	if levels.is_empty():
		return merged
	var overrides: Dictionary = levels[clampi(level, 0, levels.size() - 1)]
	for key in overrides:
		merged[key] = overrides[key]
	return merged
