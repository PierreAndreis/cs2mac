#!/bin/bash
# Frame-time test while shooting: Aim Botz map, idle phase, then bursts of AK-47 fire
# (o = join CT + god + bot_stop, p = give weapon_ak47; keycodes 31 and 35). Map: Aim Botz (workshop
# 3070244462, install it with scripts/workshop.sh 3070244462 first) unless SHOOT_MAP is set, e.g.
# SHOOT_MAP="+map de_dust2". Tag a run with SHOOT_TAG.
# Usage: shoot-test.sh <backend> [WxH] [extra cs2 args]  -> build/bench/shoot-<backend>-<ts>.{csv,txt}
set -u
backend="${1:?backend}"; res="${2:-1280x720}"; shift 2 2>/dev/null
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CS2MAC_BACKEND="$backend" CS2MAC_WIDTH="${res%x*}" CS2MAC_HEIGHT="${res#*x}"
source "$ROOT/scripts/env.sh"
ts=$(date +%Y%m%d-%H%M%S); out="$ROOT/build/bench/shoot-$backend${SHOOT_TAG:+-$SHOOT_TAG}-$ts"; mkdir -p "$ROOT/build/bench"
pkill -9 -f "^cs2.exe" 2>/dev/null; sleep 3
: > "$CS2_DIR/game/csgo/console.log"
"$ROOT/scripts/run-cs2.sh" +cl_showfps 2 +fps_max 0 +sv_cheats 1 +sv_infinite_ammo 1 \
    +bind o "jointeam 3; mp_warmup_end; mp_freezetime 0; mp_roundtime 60; bot_stop 1; god" \
    +bind p "give weapon_ak47" ${SHOOT_MAP:-+map_workshop 3070244462 aim_botz} "$@" > "$out.log" 2>&1 &
# The main menu runs its own local server, so "Sending full update" alone is not proof the map
# loaded: also require the addon to be mounted, and bail out on a failed map command.
L="$CS2_DIR/game/csgo/console.log"
for i in $(seq 1 240); do
  LC_ALL=C grep -a -q "invalid map name\|CLIENT_NO_MAP\|Failed to mount" "$L" 2>/dev/null && { echo "[shoot] map failed to load, see $L"; pkill -9 -f "^cs2.exe"; exit 1; }
  LC_ALL=C grep -a -q "Spawn Server: " "$L" 2>/dev/null && LC_ALL=C grep -a -q "Sending full update to client" "$L" && break
  sleep 1
done
[ $i -lt 240 ] || { echo "[shoot] map load timeout"; pkill -9 -f "^cs2.exe"; exit 1; }
echo "[shoot] $backend map loaded after ${i}s, warm-up 20s"; sleep 20
echo "t,phase,now,f60,f240,f1000,min_ms,max_ms" > "$out.csv"
sample() { # phase
  shot="$ROOT/build/bench/shoot-frame.png"
  WINSHOT_NAME="Counter" "$ROOT/scripts/winshot" "$shot" > /dev/null 2>&1 || return
  r=$("$ROOT/scripts/fpsread" "$shot" 2>/dev/null)
  g() { echo "$r" | tr ' ' '\n' | grep "^$1=" | cut -d= -f2; }
  echo "$SECONDS,$1,$(g now),$(g f60),$(g f240),$(g f1000),$(g min),$(g max)" >> "$out.csv"
}
"$ROOT/scripts/wininput" focus >/dev/null
"$ROOT/scripts/wininput" key 31; sleep 6; "$ROOT/scripts/wininput" key 31; sleep 4
end=$((SECONDS + 20)); while [ $SECONDS -lt $end ]; do sample idle; sleep 0.6; done
"$ROOT/scripts/wininput" key 35; sleep 1; "$ROOT/scripts/wininput" key 35; sleep 1
cp "$ROOT/build/bench/shoot-frame.png" "$out-armed.png"
for burst in 1 2 3 4 5 6 7 8; do
  "$ROOT/scripts/wininput" click 1200 & clickpid=$!
  end=$((SECONDS + 4)); while [ $SECONDS -lt $end ]; do sample "shoot$burst"; sleep 0.3; done
  wait $clickpid
  cp "$ROOT/build/bench/shoot-frame.png" "$out-burst$burst.png"
  [ "${SHOOT_TURN:-0}" != 0 ] && "$ROOT/scripts/wininput" move "$SHOOT_TURN" 0 >/dev/null
done
end=$((SECONDS + 15)); while [ $SECONDS -lt $end ]; do sample after; sleep 0.6; done
pkill -9 -f "^cs2.exe" 2>/dev/null
cp "$CS2_DIR/game/csgo/console.log" "$out-console.log"
adapter=$(LC_ALL=C grep -a -o "Creating device for graphics adapter 0 '[^']*'" "$out-console.log" | head -1 | cut -d"'" -f2)
python3 - "$out.csv" "$backend${SHOOT_TAG:+-$SHOOT_TAG}" "$adapter" <<'PY' | tee "$out.txt"
import csv, statistics, sys
rows = list(csv.DictReader(open(sys.argv[1])))
def stats(name, sel):
    # the OCR misses lines on bright backgrounds, so report the 60- and 240-frame windows separately
    f = sorted(float(r["f60"]) for r in sel if r["f60"])
    f2 = sorted(float(r["f240"]) for r in sel if r["f240"])
    mx = [float(r["max_ms"]) for r in sel if r["max_ms"]]
    if not f and not f2: print(f"{name}: no samples"); return
    def w(v): return f"median={statistics.median(v):6.1f} min={v[0]:6.1f}" if v else "median=   n/a min=   n/a"
    print(f"{name:8s} f60[n={len(f):2d}] {w(f)} | f240[n={len(f2):2d}] {w(f2)} | worst max_ms={max(mx) if mx else 0:7.1f}")
print(f"backend={sys.argv[2]} adapter={sys.argv[3]}")
stats("idle", [r for r in rows if r["phase"]=="idle"])
stats("shooting", [r for r in rows if r["phase"].startswith("shoot")])
for b in range(1,9): stats(f" burst{b}", [r for r in rows if r["phase"]==f"shoot{b}"])
stats("after", [r for r in rows if r["phase"]=="after"])
PY
