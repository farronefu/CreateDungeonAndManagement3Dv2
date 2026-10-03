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

# audio event routing and authored pitch
"$GODOT" --headless -- --autostart --seed=3 --audiotest > "$OUT/audio.txt" 2>&1
check "audiotest" "$OUT/audio.txt" "AUDIOTEST PASS"

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

# the hero ignores tunnels dug after it came in, and looks around once per one-block-wide fork
"$GODOT" --resolution 1280x720 -- --autostart --seed=3 --herotest > "$OUT/herotest.txt" 2>&1
check "herotest (starter map)" "$OUT/herotest.txt" "HEROTEST PASS"
"$GODOT" --resolution 1280x720 -- --autostart --seed=3 --digs=45 --simulate=40 --herotest > "$OUT/herotest2.txt" 2>&1
check "herotest (dug map)" "$OUT/herotest2.txt" "HEROTEST PASS"

# breaker pokes kill monsters in 3 hits (nutrient conserved); one-block stubs are not forks
"$GODOT" --resolution 1280x720 -- --autostart --seed=3 --digs=45 --simulate=40 --poketest > "$OUT/poketest.txt" 2>&1
check "poketest" "$OUT/poketest.txt" "POKETEST PASS"

# death clips play to the end after a monster dies
"$GODOT" --resolution 1280x720 -- --autostart --seed=3 --dietest > "$OUT/dietest.txt" 2>&1
check "dietest" "$OUT/dietest.txt" "DIETEST PASS"

# the hero grabs the 魔王 from the next cell and drags him one cell behind, out of the dungeon
"$GODOT" --resolution 1280x720 -- --autostart --seed=3 --capturetest > "$OUT/capturetest.txt" 2>&1
check "capturetest" "$OUT/capturetest.txt" "CAPTURETEST PASS"

# the 魔王 starts near the entrance; cowers while the hero is close, stands again once it has gone
"$GODOT" --resolution 1280x720 --fixed-fps 30 -- --autostart --cowertest > "$OUT/cowertest.txt" 2>&1
check "cowertest" "$OUT/cowertest.txt" "COWERTEST PASS"

# a freshly emerged scythe bug lays two larvae at once (nutrient conserved)
"$GODOT" --resolution 1280x720 -- --autostart --seed=3 --birthtest > "$OUT/birthtest.txt" 2>&1
check "birthtest" "$OUT/birthtest.txt" "BIRTHTEST PASS"

# monster popups show what the next evolution needs; the BGM files are the ones playing
"$GODOT" --resolution 1280x720 -- --autostart --seed=3 --digs=45 --simulate=80 --tiptest > "$OUT/tiptest.txt" 2>&1
check "tiptest" "$OUT/tiptest.txt" "TIPTEST PASS"

# pause menu "retry" restarts the stage at the arrival cut-in
"$GODOT" --resolution 1280x720 -- --retrytest > "$OUT/retrytest.txt" 2>&1
check "retrytest" "$OUT/retrytest.txt" "RETRYTEST PASS"

# title / pause menu driven by the pad
"$GODOT" --resolution 1280x720 -- --menutest > "$OUT/menutest.txt" 2>&1
check "menutest" "$OUT/menutest.txt" "MENUTEST PASS"

# approved runtime models: scales, clips, palette materials, evolutions and breaker stroke
"$GODOT" --headless -s res://scripts/debug/final_runtime_test.gd > "$OUT/final_runtime.txt" 2>&1
check "final_runtime" "$OUT/final_runtime.txt" "FINAL RUNTIME PASS checks=[0-9]+ failures=0"

echo "----"
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILED"; fi
exit "$fails"
