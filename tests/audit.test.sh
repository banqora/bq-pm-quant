#!/usr/bin/env bash
# pm-audit rule precision and input handling, and pm-docs routing vocabulary.
# Every rule is asserted in both directions: the true positive still fires, the false positive
# no longer does. A lint that has gone quiet is worse than one that is noisy.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TEST_NAME="audit"
echo "$TEST_NAME"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp" || exit 1

cat > "$tmp/ids.py" <<'PY'
import json
import sys

data = json.load(sys.stdin)
for finding in data["findings"]:
    print(finding["severity"] + ":" + finding["id"])
PY

cat > "$tmp/counts.py" <<'PY'
import json
import sys

data = json.load(sys.stdin)
print(data["files_scanned"], len(data.get("skipped", [])))
PY

ids() {     "$BIN/pm-audit" --json "$@" 2>/dev/null | python3 "$tmp/ids.py"; }
counts() {  "$BIN/pm-audit" --json "$@" 2>/dev/null | python3 "$tmp/counts.py"; }
route() {   "$BIN/pm-docs" "$@" 2>/dev/null | head -1 | sed 's#.*/references/##'; }

# ------------------------------------------------- A1  extension-less Python is visible
mkdir -p pkg/bin
cat > pkg/bin/run-backtest <<'PY'
#!/usr/bin/env python3
import pandas as pd


def signal(prices: pd.Series) -> pd.Series:
    return prices.pct_change().shift(-1)
PY
chmod +x pkg/bin/run-backtest
printf '#!/bin/sh\necho deploying\n' > pkg/bin/deploy
chmod +x pkg/bin/deploy
printf 'VERSION = "1.0"\n' > pkg/version.py

shebang="$(ids pkg/bin/run-backtest)"
assert_contains "an extension-less python script is audited when passed explicitly" \
  "high:LOOKAHEAD-SHIFT-NEG" "$shebang"
assert_eq "and it counts as one scanned file" "1 0" "$(counts pkg/bin/run-backtest)"

dirscan="$(ids pkg)"
assert_contains "a directory scan finds the extension-less python script" \
  "high:LOOKAHEAD-SHIFT-NEG" "$dirscan"
assert_eq "the directory scan audits both python files and skips the shell script" \
  "2 0" "$(counts pkg)"

python3 - <<'NB'
import json
from pathlib import Path

nb = {"cells": [{"cell_type": "code", "source": ["x = df.shift(-1)\n"]}],
      "metadata": {}, "nbformat": 4, "nbformat_minor": 5}
Path("pkg/explore.ipynb").write_text(json.dumps(nb))
NB
assert_eq "a directory scan also picks up notebooks" "3 0" "$(counts pkg)"

# pm-audit can audit its own siblings, which it previously could not see at all.
self="$("$BIN/pm-audit" "$BIN/pm-stats" 2>&1)"
assert_contains "pm-audit can audit its own sibling scripts" "1 file(s) scanned" "$self"
assert_not_contains "and no longer claims there is nothing to audit" \
  "no Python or notebook files found" "$self"

# A genuinely non-Python file is skipped with a message, not silently.
notpy="$("$BIN/pm-audit" pkg/bin/deploy 2>&1)"
assert_contains "a non-python file is skipped with a reason" "no python shebang" "$notpy"
assert_fails "and pm-audit exits non-zero when nothing could be audited" \
  "$BIN/pm-audit" pkg/bin/deploy

# ------------------------------------------------- A2  strings and docstrings are not code
cat > strings.py <<'PY'
"""Usage line that mentions a convention.

  --periods-per-year K  default 252
"""
HELP = "divide the annual rate by / 12, and never call df.fillna(0)"
EXAMPLE = "return 0"


def load(name: str) -> object:
    return open("prices-252.csv").read()


def real(frame: object) -> object:
    return frame.load("cache.csv").shift(-1)
PY
str_out="$(ids strings.py)"
assert_not_contains "a docstring mentioning 252 is not a hardcoded convention" \
  "HARDCODE-PERIODS" "$str_out"
assert_not_contains "a string mentioning fillna(0) is not a silent zero" \
  "SILENT-ZERO" "$str_out"
assert_contains "code on the same line as a string is still audited" \
  "high:LOOKAHEAD-SHIFT-NEG" "$str_out"

cat > prose.py <<'PY'
# TODO: replace this with the real estimator
NOTE = "placeholder value until the vendor feed lands"
PY
prose_out="$(ids prose.py)"
assert_contains "PLACEHOLDER still fires inside a comment" "high:PLACEHOLDER" "$prose_out"

cat > broken.py <<'PY'
def beta(p, b)
    return p.shift(-1)
PY
broken_out="$(ids broken.py)"
assert_contains "a file that does not parse reports PARSE-ERROR" "low:PARSE-ERROR" "$broken_out"
assert_contains "and the line rules still run on it" \
  "high:LOOKAHEAD-SHIFT-NEG" "$broken_out"

# ------------------------------------------------- A3  SILENT-ZERO targets fabricated estimates
cat > zero_bad.py <<'PY'
def beta(p, b):
    if len(p) < 20:
        return 0.0
    return 1.0
PY
assert_contains "an unknown beta reported as zero is high severity" \
  "high:SILENT-ZERO" "$(ids zero_bad.py)"

cat > zero_fill.py <<'PY'
def clean(frame: object) -> object:
    return frame.fillna(0)
PY
assert_contains "fillna(0) is still a high-severity silent zero" \
  "high:SILENT-ZERO" "$(ids zero_fill.py)"

cat > zero_exit.py <<'PY'
import sys


def main(argv: list[str]) -> int:
    if not argv:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
PY
assert_not_contains "a process exit code of zero is not a silent zero" \
  "SILENT-ZERO" "$(ids zero_exit.py)"

cat > zero_domain.py <<'PY'
def regularized(x: float) -> float:
    if x <= 0:
        return 0.0
    if x >= 1:
        return 1.0
    return x
PY
domain_out="$(ids zero_domain.py)"
assert_not_contains "a mathematically correct zero branch is not high severity" \
  "high:SILENT-ZERO" "$domain_out"
assert_contains "but it is still reported at low severity for inspection" \
  "low:SILENT-ZERO" "$domain_out"

# ------------------------------------------------- A4  EXCEPT-PASS and the format probe
cat > probe_ok.py <<'PY'
from datetime import datetime


def parse_date(s: str) -> object:
    for fmt in ("%Y-%m-%d", "%d/%m/%Y"):
        try:
            return datetime.strptime(s, fmt).date()
        except ValueError:
            continue
    return None
PY
probe_out="$(ids probe_ok.py)"
assert_not_contains "the format-probe idiom is no longer a high-severity finding" \
  "high:EXCEPT-PASS" "$probe_out"
assert_contains "it is reported at low severity instead of being deleted" \
  "low:EXCEPT-PASS" "$probe_out"

cat > probe_bad.py <<'PY'
def a() -> None:
    try:
        compute()
    except ValueError:
        pass


def b() -> None:
    try:
        compute()
    except Exception:
        pass


def c() -> None:
    for _ in range(3):
        try:
            compute()
        except Exception:
            continue
PY
bad_out="$(ids probe_bad.py)"
assert_contains "except: pass is still high severity" "high:EXCEPT-PASS" "$bad_out"
assert_not_contains "and a broad catch is never downgraded to the probe idiom" \
  "low:EXCEPT-PASS" "$bad_out"

# ------------------------------------------------- A5  asymmetric regexes
cat > periods.py <<'PY'
def a(x: float) -> float:
    return x / 12


def b(x: float) -> float:
    return x/12
PY
periods_out="$("$BIN/pm-audit" periods.py --severity medium 2>&1)"
assert_contains "a spaced monthly divisor is flagged"        "> return x / 12" "$periods_out"
assert_contains "an unspaced monthly divisor is flagged too" "> return x/12"   "$periods_out"

cat > summing_bad.py <<'PY'
def a(portfolio_returns) -> float:
    return portfolio_returns.sum()


def b(returns) -> float:
    return returns.sum()


def c(active_returns) -> float:
    return active_returns.sum()


def d(daily_pnl) -> float:
    return daily_pnl.sum()
PY
bad_sum="$(ids summing_bad.py | grep -c 'SUM-RETURNS')"
assert_eq "an identifier ending in a return word is flagged, not only the bare word" \
  "4" "$bad_sum"

cat > summing_ok.py <<'PY'
def a(log_returns, cumulative_log_returns) -> float:
    return log_returns.sum() + cumulative_log_returns.sum()


def b(bar, counter, factor) -> float:
    return bar.sum() + counter.sum() + factor.sum()
PY
assert_not_contains "summing log returns is correct and is not flagged" \
  "SUM-RETURNS" "$(ids summing_ok.py)"

# ------------------------------------------------- A6  failures are explicit
missing="$("$BIN/pm-audit" no-such-file.py 2>&1)"
assert_contains "a missing path is reported, not a traceback" "no such file" "$missing"
assert_not_contains "and there is no traceback" "Traceback" "$missing"
assert_fails "a missing path exits non-zero" "$BIN/pm-audit" no-such-file.py

printf 'not json at all' > bad.ipynb
badnb="$("$BIN/pm-audit" bad.ipynb 2>&1)"
assert_contains "an unreadable notebook is named in the output" "could not read" "$badnb"
assert_contains "and is not counted as scanned" "0 file(s) scanned" "$badnb"
assert_fails "an unreadable file exits non-zero" "$BIN/pm-audit" bad.ipynb

: > empty.py
assert_eq "a genuinely empty file is scanned rather than silently dropped" \
  "1 0" "$(counts empty.py)"
assert_ok "and an empty file has no findings" "$BIN/pm-audit" empty.py

# ------------------------------------------------- A7  the tools meet their own typing rule
own="$("$BIN/pm-audit" "$BIN/pm-audit" "$BIN/pm-docs" 2>&1)"
assert_not_contains "pm-audit and pm-docs are fully annotated" "TYPE-MISSING" "$own"
assert_not_contains "and declare no Any on a public signature" "TYPE-ANY" "$own"

# ------------------------------------------------- B1  core vocabulary routes somewhere
assert_eq "a benchmark question routes to the conventions"  "return-conventions.md" \
  "$(route "what benchmark should i use")"
assert_eq "an alpha question routes to inference"           "inference.md" \
  "$(route "is my alpha real")"
assert_eq "a volatility question routes to the conventions" "return-conventions.md" \
  "$(route "how do i annualise volatility")"
assert_eq "a tracking-error question routes to risk models" "risk-models.md" \
  "$(route "what is my tracking error")"
assert_eq "a delivery-format question routes to conduct"    "analyst-conduct.md" \
  "$(route "give me the output as a spreadsheet")"
assert_eq "a Kelly question routes to conduct"              "analyst-conduct.md" \
  "$(route "what is the kelly fraction")"
assert_eq "a position-sizing question routes to conduct"    "analyst-conduct.md" \
  "$(route "how do i size this position")"
assert_eq "an expected-return question routes to conventions" "return-conventions.md" \
  "$(route "my expected return calculation")"
assert_eq "a monotonicity question routes to the equity desk" "equity-desk.md" \
  "$(route "is the signal monotonic across quintiles")"
assert_eq "a trial-log question routes to out of sample"    "out-of-sample.md" \
  "$(route "where is the trial log")"
assert_eq "a sample-size question routes to inference"      "inference.md" \
  "$(route "what sample size do i need")"
assert_eq "a survivorship question routes to data integrity" "data-integrity.md" \
  "$(route "survivorship bias in my universe")"
assert_ok "pm-docs exits zero for a benchmark question" "$BIN/pm-docs" "what benchmark should i use"

# ------------------------------------------------- B2  diagnostic vocabulary
assert_eq "a suspicious number routes to the review checklist" "review-checklist.md" \
  "$(route "this number looks suspicious")"
assert_eq "a surprising backtest Sharpe routes to the review checklist" "review-checklist.md" \
  "$(route "my backtest sharpe is 5, what now")"
assert_eq "'what should i check' routes to the review checklist" "review-checklist.md" \
  "$(route "what should i check before using this number")"
assert_eq "'seems wrong' routes to the review checklist" "review-checklist.md" \
  "$(route "seems wrong that the return is so high")"

# The routing that already worked must not have moved.
assert_eq "a Sharpe question still routes to performance statistics" \
  "performance-statistics.md" "$(route "is my sharpe statistically significant")"
assert_eq "an OOS question still routes to out of sample" \
  "out-of-sample.md" "$(route "how do i run out of sample validation")"
assert_eq "a shrinkage question still routes to risk models" \
  "risk-models.md" "$(route "ledoit wolf covariance shrinkage")"
assert_eq "a disclaimer question still routes to conduct" \
  "analyst-conduct.md" "$(route "should i add a disclaimer to this")"
assert_eq "an attribution question still routes to attribution" \
  "attribution.md" "$(route "brinson allocation and selection effects")"

cd "$REPO_ROOT" || exit 1
finish
