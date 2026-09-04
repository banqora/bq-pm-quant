# Deterministic fixture generators. No third-party dependencies, no network.
gen_returns() {  # gen_returns <out.csv> <n> <ann_sharpe> <ann_vol> <seed>
  python3 - "$@" <<'PY'
import csv, datetime, math, random, sys
out, n, sr, vol, seed = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), \
    float(sys.argv[4]), int(sys.argv[5])
rng = random.Random(seed)
sd = vol / math.sqrt(252)
mu = sr * vol / 252
d = datetime.date(2015, 1, 1)
rows = []
while len(rows) < n:
    if d.weekday() < 5:
        rows.append((d.isoformat(), f"{rng.gauss(mu, sd):.10f}"))
    d += datetime.timedelta(days=1)
with open(out, "w", newline="") as fh:
    w = csv.writer(fh); w.writerow(["date", "return"]); w.writerows(rows)
PY
}

gen_prices() {  # gen_prices <out.csv> <n> <seed>
  python3 - "$@" <<'PY'
import csv, datetime, math, random, sys
out, n, seed = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
rng = random.Random(seed)
d, p, rows = datetime.date(2020, 1, 1), 100.0, []
while len(rows) < n:
    if d.weekday() < 5:
        p *= (1 + rng.gauss(0.0003, 0.011))
        rows.append((d.isoformat(), f"{p:.6f}"))
    d += datetime.timedelta(days=1)
with open(out, "w", newline="") as fh:
    w = csv.writer(fh); w.writerow(["date", "close"]); w.writerows(rows)
PY
}
