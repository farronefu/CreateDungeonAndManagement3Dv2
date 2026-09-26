#!/usr/bin/env bash
# Runs every automated check and prints PASS / FAIL for each. Exit code 0 only if all pass.
#   GODOT=/path/to/godot tools/run_tests.sh
# (run before every push)
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT=debug_shots/tests
mkdir -p "$OUT"
fails=0

check() {   # name, log, pass-condition (grep -E pattern that must appear)
	local name="$1" log="$2" pattern="$3"
	if grep -qiE "SCRIPT ERROR" "$log"; then
		echo "FAIL  $name (script error, see $log)"; fails=$((fails + 1))
	elif grep -qE "$pattern" "$log"; then
		echo "PASS  $name"
	else
		echo "FAIL  $name (see $log)"; fails=$((fails + 1))
	fi
}

# ecosystem: nutrient conservation over a long headless simulation
"$GODOT" --headless -s res://scripts/debug/sim_test.gd -- 450 90 > "$OUT/sim.txt" 2>&1
if grep -qE "(!= [0-9]+)" "$OUT/sim.txt"; then
	echo "FAIL  sim_test: nutrient not conserved (see $OUT/sim.txt)"; fails=$((fails + 1))
else
	check "sim_test" "$OUT/sim.txt" "births"
fi

# a whole stage played by the autoplayer must end in victory
"$GODOT" --resolution 1280x720 -- --autoplay --seed=4 > "$OUT/autoplay.txt" 2>&1
check "autoplay" "$OUT/autoplay.txt" "AUTOPLAY RESULT victory"

# scripted controller session (pan, orbit, RB, A-hold dig, Y, placement, pause)
"$GODOT" --resolution 1280x720 -- --autostart --padtest > "$OUT/padtest.txt" 2>&1
check "padtest" "$OUT/padtest.txt" "PADTEST PASS"

# mouse drag digs every cell passed over, in order
"$GODOT" --resolution 1280x720 -- --autostart --dragtest > "$OUT/dragtest.txt" 2>&1
check "dragtest" "$OUT/dragtest.txt" "DRAGTEST PASS"

# title / pause menu driven by the pad
"$GODOT" --resolution 1280x720 -- --menutest > "$OUT/menutest.txt" 2>&1
check "menutest" "$OUT/menutest.txt" "MENUTEST PASS"

echo "----"
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILED"; fi
exit "$fails"
