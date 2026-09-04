#!/usr/bin/env bash
# End-to-end behaviour of the four helper scripts.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/fixtures.sh"
TEST_NAME="scripts"
echo "$TEST_NAME"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

# ---------------------------------------------------------------- pm-stats
gen_returns "$tmp/good.csv" 2520 1.0 0.12 42
out="$("$BIN/pm-stats" good.csv 2>/dev/null)"
assert_contains "pm-stats reports n"                "n=2520"            "$out"
assert_contains "pm-stats reports the window"       "2015-01-01"        "$out"
assert_contains "pm-stats reports an iid SE"        "iid normal"        "$out"
assert_contains "pm-stats reports a Mertens SE"     "Mertens"           "$out"
assert_contains "pm-stats reports a Lo Sharpe"      "Sharpe (ann., Lo)" "$out"
assert_contains "pm-stats reports drawdown dates"   "peak 2"            "$out"
assert_contains "pm-stats reports VaR and ES"       "hist. VaR 95"      "$out"
assert_contains "pm-stats reports Ljung-Box"        "Ljung-Box"         "$out"
assert_contains "pm-stats flags a missing trial count" "no trial count supplied" "$out"

sharpe="$("$BIN/pm-stats" good.csv --json 2>/dev/null | python3 -c \
  'import json,sys; print(round(json.load(sys.stdin)["sharpe"]["sharpe_ann"], 2))')"
within="$(python3 -c "print('yes' if abs($sharpe - 1.0) < 0.25 else 'no ($sharpe)')")"
assert_eq "pm-stats recovers a simulated Sharpe of 1.0" "yes" "$within"

# prices
gen_prices "$tmp/px.csv" 800 7
assert_ok "pm-stats accepts a price series" "$BIN/pm-stats" px.csv --is-price

# risk-free lowers the Sharpe
s0="$("$BIN/pm-stats" good.csv --json 2>/dev/null | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["sharpe"]["sharpe_ann"])')"
s1="$("$BIN/pm-stats" good.csv --rf 0.05 --json 2>/dev/null | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["sharpe"]["sharpe_ann"])')"
lower="$(python3 -c "print('yes' if $s1 < $s0 else 'no')")"
assert_eq "a positive risk-free rate lowers the Sharpe" "yes" "$lower"

# refuses to silently drop unparsable rows
printf 'date,return\n2020-01-01,0.001\n2020-01-02,oops\n2020-01-03,0.002\n' > bad.csv
assert_fails "pm-stats refuses unparsable rows" "$BIN/pm-stats" bad.csv
err="$("$BIN/pm-stats" bad.csv 2>&1 || true)"
assert_contains "pm-stats explains why it refused" "cannot be parsed" "$err"

# too few observations
printf 'date,return\n2020-01-01,0.001\n' > tiny.csv
assert_fails "pm-stats refuses a single observation" "$BIN/pm-stats" tiny.csv

# integrity flags
python3 - <<'PY'
import csv, datetime
d, rows = datetime.date(2021, 1, 1), []
for i in range(600):
    r = 0.0 if i % 3 == 0 else 0.001
    if i == 300:
        r = -0.55
    rows.append((d.isoformat(), r))          # weekends included deliberately
    d += datetime.timedelta(days=1)
with open("dirty.csv", "w", newline="") as fh:
    w = csv.writer(fh); w.writerow(["date", "return"]); w.writerows(rows)
PY
dirty="$("$BIN/pm-stats" dirty.csv 2>/dev/null)"
assert_contains "flags stale or forward-filled prices" "forward-filled or stale" "$dirty"
assert_contains "flags unadjusted corporate actions"   "unadjusted corporate actions" "$dirty"
assert_contains "flags weekend rows"                   "exchange calendar" "$dirty"

# a look-ahead-grade Sharpe is flagged as a lag defect
gen_returns "$tmp/toogood.csv" 1500 6.0 0.10 3
tg="$("$BIN/pm-stats" toogood.csv 2>/dev/null)"
assert_contains "flags an implausibly high Sharpe as a lag defect" "lag defect" "$tg"

# csv output carries the conventions
"$BIN/pm-stats" good.csv --rf 0.03 --trials 9 --csv metrics.csv >/dev/null 2>&1
csvout="$(cat metrics.csv)"
assert_contains "csv carries the window"        "# window"            "$csvout"
assert_contains "csv carries n"                 "# n,2520"            "$csvout"
assert_contains "csv carries the risk-free"     "# risk_free"         "$csvout"
assert_contains "csv carries the trial count"   "# trials_searched,9" "$csvout"
assert_contains "csv carries standard errors"   "se,t,method"         "$csvout"

# benchmark alignment
gen_returns "$tmp/bench.csv" 2520 0.4 0.16 99
act="$("$BIN/pm-stats" good.csv --benchmark bench.csv 2>/dev/null)"
assert_contains "reports tracking error"    "tracking error" "$act"
assert_contains "reports information ratio" "information ratio" "$act"
assert_contains "reports beta"              "beta vs benchmark" "$act"

# ---------------------------------------------------------------- pm-audit
cat > leaky.py <<'PY'
import numpy as np
from sklearn.model_selection import train_test_split
RISK_FREE = 0.02
def signal(prices):
    return prices.pct_change().shift(-1)
def sharpe(r):
    try:
        return r.mean() / np.std(r) * np.sqrt(252)
    except Exception:
        return 0.0
def te(p, b):
    return np.std(p.iloc[:min_len].values - b.iloc[:min_len].values)
PY
audit="$("$BIN/pm-audit" leaky.py 2>&1 || true)"
for rule in LOOKAHEAD-SHIFT-NEG LEAK-KFOLD DDOF-DEFAULT SILENT-FALLBACK EXCEPT-DEFAULT \
            SILENT-ZERO ALIGN-POSITIONAL HARDCODE-RF; do
  assert_contains "pm-audit flags $rule" "$rule" "$audit"
done
assert_fails "pm-audit exits non-zero on a high-severity finding" "$BIN/pm-audit" leaky.py
assert_contains "pm-audit states it is a lint, not a proof" "not a confirmed defect" "$audit"

cat > clean.py <<'PY'
"""A module with no flagged patterns."""
from dataclasses import dataclass


@dataclass(frozen=True)
class Config:
    periods_per_year: int
    ddof: int = 1


def annualise(mean_period, cfg):
    assert cfg.periods_per_year > 0
    return mean_period * cfg.periods_per_year
PY
assert_ok "pm-audit exits zero on clean code" "$BIN/pm-audit" clean.py
clean_out="$("$BIN/pm-audit" clean.py --severity high 2>&1)"
assert_contains "pm-audit reports no high findings on clean code" "high 0" "$clean_out"

# notebooks
python3 - <<'PY'
import json
nb = {"cells": [{"cell_type": "code", "source": ["import numpy as np\n",
                                                 "x = df.shift(-1)\n"]}],
      "metadata": {}, "nbformat": 4, "nbformat_minor": 5}
open("nb.ipynb", "w").write(json.dumps(nb))
PY
nbout="$("$BIN/pm-audit" nb.ipynb 2>&1 || true)"
assert_contains "pm-audit reads notebooks"          "LOOKAHEAD-SHIFT-NEG" "$nbout"
assert_contains "pm-audit warns about notebook state" "restart and run top to bottom" "$nbout"

# typing rules
cat > typed.py <<'PY2'
from typing import Any
import pandas as pd


def untyped(a, b):
    return a + b


def typed_ok(returns: pd.Series, k: int) -> float:
    return float(returns.std(ddof=1) * k ** 0.5)


def anyish(source: Any) -> pd.DataFrame:
    return pd.DataFrame(source)


def _private(x):
    return x
PY2
tout="$("$BIN/pm-audit" typed.py 2>&1 || true)"
assert_contains "pm-audit flags an untyped public function" "TYPE-MISSING" "$tout"
assert_contains "pm-audit names the untyped arguments"      "untyped: a, b" "$tout"
assert_contains "pm-audit flags an explicit Any"            "TYPE-ANY"     "$tout"
assert_not_contains "pm-audit does not flag a typed function" "typed_ok:"  "$tout"
assert_not_contains "pm-audit does not flag a private helper" "_private"   "$tout"
assert_contains "pm-audit points at the type checker and coverage" "cov-fail-under=80" "$tout"

# json output is machine-readable and carries severities
jout="$("$BIN/pm-audit" leaky.py --json 2>/dev/null || true)"
parsed="$(printf '%s' "$jout" | python3 -c \
  'import json,sys; d=json.load(sys.stdin); print(d["files_scanned"], len(d["findings"])>5, all(f["severity"] in ("high","medium","low") for f in d["findings"]))')"
assert_eq "pm-audit --json emits valid structured output" "1 True True" "$parsed"

# severity filter
hi="$("$BIN/pm-audit" leaky.py --severity high 2>&1 || true)"
assert_not_contains "--severity high suppresses medium findings" "  medium " "$hi"

# ---------------------------------------------------------------- pm-docs
d1="$("$BIN/pm-docs" "is my sharpe statistically significant" 2>&1)"
assert_contains "pm-docs routes a Sharpe question" "performance-statistics.md" "$d1"
d2="$("$BIN/pm-docs" "how do i run out of sample validation" 2>&1)"
assert_contains "pm-docs routes an OOS question" "out-of-sample.md" "$d2"
d3="$("$BIN/pm-docs" "ledoit wolf covariance shrinkage" 2>&1)"
assert_contains "pm-docs routes a covariance question" "risk-models.md" "$d3"
d4="$("$BIN/pm-docs" "should i add a disclaimer to this" 2>&1)"
assert_contains "pm-docs routes a conduct question" "analyst-conduct.md" "$d4"
d5="$("$BIN/pm-docs" "survivorship bias in my universe" 2>&1)"
assert_contains "pm-docs routes a data question" "data-integrity.md" "$d5"
d6="$("$BIN/pm-docs" "brinson allocation and selection effects" 2>&1)"
assert_contains "pm-docs routes an attribution question" "attribution.md" "$d6"
assert_ok "pm-docs --list works" "$BIN/pm-docs" --list
assert_fails "pm-docs exits non-zero on no match" "$BIN/pm-docs" "zzzz qqqq"

# ---------------------------------------------------------------- pm-prefs
export XDG_CONFIG_HOME="$tmp/config"
assert_fails "pm-prefs exits non-zero when nothing is set" "$BIN/pm-prefs"
assert_ok "pm-prefs set writes a value" "$BIN/pm-prefs" set output_format xlsx
assert_eq "pm-prefs get reads it back" "xlsx" "$("$BIN/pm-prefs" get output_format)"
assert_ok "pm-prefs init --project writes a project file" "$BIN/pm-prefs" init --project
assert_ok "pm-prefs set --project writes to the project file" \
  "$BIN/pm-prefs" set output_format html --project
assert_eq "the project file overrides the user file" "html" "$("$BIN/pm-prefs" get output_format)"
assert_ok "pm-prefs unset --project removes it" "$BIN/pm-prefs" unset output_format --project
assert_eq "the user value is restored" "xlsx" "$("$BIN/pm-prefs" get output_format)"
assert_fails "pm-prefs get exits non-zero for an unset key" "$BIN/pm-prefs" get benchmark
assert_ok "pm-prefs keys lists the documented keys" "$BIN/pm-prefs" keys
listing="$("$BIN/pm-prefs" 2>&1)"
assert_contains "pm-prefs shows where each value came from" "project (" "$listing"

# pm-stats picks up the stored periods_per_year
"$BIN/pm-prefs" set periods_per_year 12 --project >/dev/null
monthly="$("$BIN/pm-stats" good.csv 2>/dev/null)"
assert_contains "pm-stats honours the stored periods_per_year" "k=12" "$monthly"
explicit="$("$BIN/pm-stats" good.csv --periods-per-year 252 2>/dev/null)"
assert_contains "an explicit flag overrides the stored preference" "k=252" "$explicit"

# a corrupt preferences file must not be silently ignored into wrong defaults
echo 'not json' > .bq-pm-quant.json
warn="$("$BIN/pm-stats" good.csv 2>&1 >/dev/null)"
assert_contains "pm-stats warns about unreadable preferences" "unreadable preferences" "$warn"

# ---------------------------------------------------------------- misc pm-stats
rm -f .bq-pm-quant.json
a="$("$BIN/pm-stats" good.csv --trials 5 2>/dev/null)"
b="$("$BIN/pm-stats" good.csv --trials 5 2>/dev/null)"
assert_eq "pm-stats is deterministic" "$a" "$b"

"$BIN/pm-stats" good.csv --out report.txt >/dev/null 2>&1
assert_ok "pm-stats --out creates the file" test -s report.txt
assert_contains "the written report matches stdout" "$(head -1 report.txt)" "$a"

python3 - <<'PY3'
import csv, datetime, random
rng = random.Random(4)
d, rows = datetime.date(2019, 1, 1), []
while len(rows) < 800:
    if d.weekday() < 5:
        rows.append((d.isoformat(), f"{rng.gauss(0.0004, 0.009):.10f}"))
    d += datetime.timedelta(days=1)
with open("logret.csv", "w", newline="") as fh:
    w = csv.writer(fh); w.writerow(["date", "return"]); w.writerows(rows)
PY3
simple="$("$BIN/pm-stats" logret.csv --json 2>/dev/null | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["cagr"])')"
logged="$("$BIN/pm-stats" logret.csv --log-returns --json 2>/dev/null | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["cagr"])')"
differs="$(python3 -c "print('yes' if abs($simple - $logged) > 1e-9 else 'no')")"
assert_eq "--log-returns changes the result" "yes" "$differs"

python3 - <<'PY3'
import csv, datetime, random
rng = random.Random(8)
d, rows = datetime.date(2019, 1, 1), []
while len(rows) < 500:
    if d.weekday() < 5:
        rows.append((d.isoformat(), f"{rng.gauss(0.0005, 0.01):.10f}", "0.00012"))
    d += datetime.timedelta(days=1)
with open("withrf.csv", "w", newline="") as fh:
    w = csv.writer(fh); w.writerow(["date", "return", "rf"]); w.writerows(rows)
PY3
rfout="$("$BIN/pm-stats" withrf.csv --rf-col rf 2>/dev/null)"
assert_contains "pm-stats accepts a risk-free column" "column rf (periodic)" "$rfout"

printf 'date,return\nweek1,0.01\nweek2,-0.02\nweek3,0.03\nweek4,0.01\n' > nodate.csv
nd="$("$BIN/pm-stats" nodate.csv 2>&1 >/dev/null || true)"
assert_contains "pm-stats says which checks it disabled" "DISABLED" "$nd"

printf 'date,return\n2020-01-01,1.5\n2020-01-02,-2.0\n2020-01-03,0.8\n2020-01-06,1.1\n' > pct.csv
assert_fails "pm-stats refuses ambiguous percent-scaled input" "$BIN/pm-stats" pct.csv
pc="$("$BIN/pm-stats" pct.csv 2>&1 || true)"
assert_contains "pm-stats explains the two possible causes" "unadjusted corporate action" "$pc"
assert_contains "pm-stats refuses to guess"                  "will not guess" "$pc"
assert_ok "an explicit override accepts the series" \
  "$BIN/pm-stats" pct.csv --allow-extreme-returns

# ---------------------------------------------------------------- help
for s in pm-stats pm-audit pm-docs pm-prefs; do
  assert_ok "$s --help exits zero" "$BIN/$s" --help
done

cd "$REPO_ROOT"
finish
