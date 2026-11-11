extends RefCounted
## Unit tests for src/rules/boss_fight_rules.gd. Run: tests/run_tests.gd

const Rules := preload("res://src/rules/boss_fight_rules.gd")

const CFG := {
	"villain_max_hearts": 5, "player_max_hearts": 4, "deflects_to_duel": 3,
	"throw_interval": 2.2, "throw_interval_per_heart": -0.25, "throw_interval_min": 1.0,
	"brick_flight_time": 1.6, "brick_flight_time_per_heart": -0.15, "brick_flight_time_min": 0.85,
	"cursed_chance": 0.15, "cursed_chance_per_heart": 0.07,
	"mash_power": 0.1, "villain_push": 0.3, "villain_push_per_heart": 0.1,
	"lightning_interval": 6.0, "lightning_interval_per_heart": -1.0, "lightning_interval_min": 3.0,
	"lightning_bolts": 1, "lightning_bolts_per_heart": 0.5, "lightning_bolts_max": 3,
	"lightning_radius": 1.5,
}

var t  # test runner, injected


func _win_duel(r) -> int:
	var result := 0
	for i in 20:
		r.mash()
	result = r.tick_duel(0.0)
	return result


func test_three_deflects_start_duel() -> void:
	var r = Rules.new(CFG)
	t.eq(r.register_deflect(), false, "1st deflect does not start duel")
	t.eq(r.register_deflect(), false, "2nd deflect does not start duel")
	t.eq(r.register_deflect(), true, "3rd deflect starts duel")
	t.eq(r.phase, Rules.Phase.DUEL, "phase is DUEL")
	t.eq(r.tug, 0.0, "tug starts centered")


func test_miss_resets_hit_streak() -> void:
	# Arrange
	var r = Rules.new(CFG)
	r.register_deflect()
	r.register_deflect()
	# Act
	r.register_miss()
	# Assert
	t.eq(r.deflects, 0, "a missed shot resets the streak")
	t.eq(r.register_deflect(), false, "streak restarts from 1")
	t.eq(r.phase, Rules.Phase.THROW, "still in throw phase")


func test_miss_ignored_outside_throw_phase() -> void:
	var r = Rules.new(CFG)
	r.register_deflect()
	r.start_duel()
	r.register_miss()
	t.eq(r.phase, Rules.Phase.DUEL, "miss does nothing during duel")


func test_deflect_ignored_outside_throw_phase() -> void:
	var r = Rules.new(CFG)
	r.start_duel()
	t.eq(r.register_deflect(), false, "no deflect during duel")
	t.eq(r.deflects, 0, "counter untouched")


func test_mashing_wins_round_and_removes_one_heart() -> void:
	var r = Rules.new(CFG)
	r.start_duel()
	t.eq(_win_duel(r), Rules.ROUND_PLAYER_WON, "round won")
	t.eq(r.villain_hearts, 4, "villain lost one heart")
	t.eq(r.phase, Rules.Phase.THROW, "villain goes back up to throw")
	t.eq(r.deflects, 0, "deflect counter reset")


func test_full_mash_wins_even_with_real_frame_delta() -> void:
	# Regression: mash clamps to 1.0 and the villain push used to be applied
	# before the win check, so a real frame (delta > 0) could never win.
	var r = Rules.new(CFG)
	r.start_duel()
	for i in 20:
		r.mash()
	t.eq(r.tick_duel(0.016), Rules.ROUND_PLAYER_WON, "full tug wins on a real frame")


func test_not_mashing_loses_round_and_player_heart() -> void:
	var r = Rules.new(CFG)
	r.start_duel()
	var result := Rules.ROUND_NONE
	for i in 100:
		result = r.tick_duel(0.1)
		if result != Rules.ROUND_NONE:
			break
	t.eq(result, Rules.ROUND_VILLAIN_WON, "villain wins idle duel")
	t.eq(r.player_hearts, 3, "player lost one heart")
	t.eq(r.villain_hearts, 5, "villain keeps hearts")


func test_last_heart_leads_to_snitch_then_win() -> void:
	var r = Rules.new(CFG)
	for i in 5:
		r.start_duel()
		_win_duel(r)
	t.eq(r.villain_hearts, 0, "villain out of hearts")
	t.eq(r.phase, Rules.Phase.SNITCH, "snitch phase")
	r.catch_snitch()
	t.eq(r.phase, Rules.Phase.WON, "won after catching snitch")


func test_player_out_of_hearts_loses() -> void:
	var r = Rules.new(CFG)
	for i in 4:
		r.register_player_hit()
	t.eq(r.player_hearts, 0, "no hearts left")
	t.eq(r.phase, Rules.Phase.LOST, "game lost")
	r.register_player_hit()
	t.eq(r.player_hearts, 0, "hearts never negative")


func test_difficulty_scales_with_hearts_lost() -> void:
	var r = Rules.new(CFG)
	var push0: float = r.villain_push_rate()
	var interval0: float = r.throw_interval()
	r.villain_hearts = 1
	t.ok(r.villain_push_rate() > push0, "villain pushes harder")
	t.ok(r.throw_interval() < interval0, "throws faster")
	t.ok(r.throw_interval() >= 1.0, "interval clamped to min")
	t.ok(r.brick_flight_time() >= 0.85, "flight time clamped to min")


func test_lightning_interval_shrinks_per_heart_lost_and_clamps() -> void:
	var r = Rules.new(CFG)
	t.eq(r.lightning_interval(), 6.0, "full-health interval is the base value")
	r.villain_hearts = 3
	t.eq(r.lightning_interval(), 4.0, "two hearts lost shortens it by two steps")
	r.villain_hearts = 0
	t.eq(r.lightning_interval(), 3.0, "interval clamped to min")


func test_lightning_bolts_grow_with_hearts_lost_up_to_max() -> void:
	var r = Rules.new(CFG)
	t.eq(r.lightning_bolts(), 1, "one bolt at full health")
	r.villain_hearts = 3
	t.eq(r.lightning_bolts(), 2, "two hearts lost adds a bolt")
	r.villain_hearts = 0
	t.eq(r.lightning_bolts(), 3, "bolt count clamped to max")


func test_lightning_hits_only_inside_radius() -> void:
	var r = Rules.new(CFG)
	t.eq(r.lightning_hits(0.0), true, "direct strike hits")
	t.eq(r.lightning_hits(1.49), true, "just inside the radius hits")
	t.eq(r.lightning_hits(1.5), false, "the edge is safe")
	t.eq(r.lightning_hits(4.0), false, "far away is safe")


const LEVELS := [
	{"villain_max_hearts": 1, "villain_push": 0.2},
	{"villain_max_hearts": 2, "villain_push": 0.3},
	{"villain_max_hearts": 3, "villain_push": 0.4},
]


func _leveled_cfg() -> Dictionary:
	var c: Dictionary = CFG.duplicate(true)
	c["levels"] = LEVELS
	return c


func test_level_config_overrides_hearts_and_duel_push_per_level() -> void:
	var c := _leveled_cfg()
	t.eq(Rules.level_count(c), 3, "three levels configured")
	for i in 3:
		var r = Rules.new(Rules.config_for_level(c, i))
		t.eq(r.villain_hearts, i + 1, "level %d villain hearts" % (i + 1))
	var easy = Rules.new(Rules.config_for_level(c, 0))
	var hard = Rules.new(Rules.config_for_level(c, 2))
	t.ok(hard.villain_push_rate() > easy.villain_push_rate(), "final duel pushes harder on the last level")


func test_level_config_keeps_base_values_and_does_not_mutate_base() -> void:
	var c := _leveled_cfg()
	var lvl: Dictionary = Rules.config_for_level(c, 1)
	t.eq(lvl.player_max_hearts, 4, "values the level does not override stay")
	t.eq(c.villain_max_hearts, 5, "base config untouched")


func test_level_config_clamps_out_of_range_and_handles_no_levels() -> void:
	var c := _leveled_cfg()
	t.eq(Rules.config_for_level(c, 9).villain_max_hearts, 3, "past the end uses the last level")
	t.eq(Rules.config_for_level(c, -1).villain_max_hearts, 1, "negative uses the first level")
	t.eq(Rules.level_count(CFG), 1, "no levels block counts as one level")
	t.eq(Rules.config_for_level(CFG, 2).villain_max_hearts, 5, "no levels block returns the base")
