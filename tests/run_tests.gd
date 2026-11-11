extends SceneTree
## Minimal headless test runner.
## godot --headless --path . -s res://tests/run_tests.gd

const SUITES := [
	"res://tests/unit/boss_fight/boss_fight_rules_test.gd",
]

var failures := 0
var checks := 0


func eq(actual, expected, msg: String) -> void:
	checks += 1
	if actual != expected:
		failures += 1
		printerr("  FAIL: %s (expected %s, got %s)" % [msg, str(expected), str(actual)])


func ok(cond: bool, msg: String) -> void:
	eq(cond, true, msg)


func _init() -> void:
	for path in SUITES:
		var suite = load(path).new()
		suite.t = self
		for m in suite.get_method_list():
			var name: String = m.name
			if name.begins_with("test_"):
				var before := failures
				var checks_before := checks
				suite.call(name)
				# A script error aborts the test silently; a test that ran no
				# checks is therefore counted as a failure.
				if checks == checks_before:
					failures += 1
					printerr("  FAIL: %s ran no checks (script error?)" % name)
				print(("PASS " if failures == before else "FAIL ") + name)
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
