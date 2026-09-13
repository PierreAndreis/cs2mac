#!/bin/bash
# Repeatable CS2 benchmark: loads the "CS2 FPS BENCHMARK DUST2" workshop addon (de_dust2 + bots),
# stands still at spawn and samples the cl_showfps overlay via OCR every 5 s.
# Usage: bench.sh <backend> [seconds] [WxH] [cs2 args...]   -> build/bench/<backend>-<WxH>-<ts>.{csv,txt}
set -u
backend="${1:?backend}"; dur="${2:-120}"; res="${3:-1280x720}"; shift $(( $# > 3 ? 3 : $# ))
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CS2MAC_DIRECT=1 CS2MAC_BACKEND="$backend" CS2MAC_WIDTH="${res%x*}" CS2MAC_HEIGHT="${res#*x}"
source "$ROOT/scripts/env.sh"
ts=$(date +%Y%m%d-%H%M%S); out="$ROOT/build/bench/$backend-$res-$ts"; mkdir -p "$ROOT/build/bench"
pkill -f "^cs2.exe" 2>/dev/null; sleep 3
: > "$CS2_DIR/game/csgo/console.log"
"$ROOT/scripts/run-cs2.sh" +cl_showfps 2 +fps_max 0 +map_workshop 3240880604 de_dust2 "$@" > "$out.log" 2>&1 &
launcher=$!
echo "[bench] backend=$backend res=$res waiting for map load"
for i in $(seq 1 240); do
  grep -q "Sending full update to client" "$CS2_DIR/game/csgo/console.log" 2>/dev/null && break
  kill -0 $launcher 2>/dev/null || { echo "[bench] cs2 exited before map load (see $out.log)"; exit 1; }
  sleep 1
done
grep -q "Sending full update to client" "$CS2_DIR/game/csgo/console.log" || { echo "[bench] map load timeout"; pkill -f "^cs2.exe"; exit 1; }
load_s=$i; echo "[bench] map loaded after ${load_s}s, warming up 20s"; sleep 20
echo "t,now,f60,f240,f1000,min_ms,max_ms" > "$out.csv"
end=$((SECONDS + dur)); n=0
while [ $SECONDS -lt $end ]; do
  shot="$ROOT/build/bench/frame.png"
  WINSHOT_NAME="Counter" "$ROOT/scripts/winshot" "$shot" > /dev/null 2>&1 || break
  r=$("$ROOT/scripts/fpsread" "$shot" 2>/dev/null)
  g() { echo "$r" | tr ' ' '\n' | grep "^$1=" | cut -d= -f2; }
  echo "$SECONDS,$(g now),$(g f60),$(g f240),$(g f1000),$(g min),$(g max)" >> "$out.csv"
  n=$((n + 1)); [ $((n % 4)) = 0 ] && cp "$shot" "$out-$SECONDS.png"
  sleep 5
done
pkill -f "^cs2.exe" 2>/dev/null
python3 - "$out.csv" "$backend" "$res" "$load_s" <<'PY' | tee "$out.txt"
import csv, statistics, sys
rows = list(csv.DictReader(open(sys.argv[1])))
def col(k): return [float(r[k]) for r in rows if r[k]]
f60, f1000, mx = col("f60"), col("f1000"), col("max_ms")
print(f"backend={sys.argv[2]} res={sys.argv[3]} samples={len(rows)} map_load_s={sys.argv[4]}")
if f60:
    s = sorted(f60)
    print(f"fps(60-frame window): median={statistics.median(s):.1f} mean={statistics.fmean(s):.1f} p5={s[max(0,int(len(s)*0.05)-1)]:.1f} min={s[0]:.1f} max={s[-1]:.1f}")
if f1000: print(f"fps(1000-frame window): last={f1000[-1]:.1f} median={statistics.median(f1000):.1f}")
if mx: print(f"worst frame (ms) over run: {max(mx):.1f}")
PY
