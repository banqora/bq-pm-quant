#!/usr/bin/env bash
# Skill structure, manifests, links, and the conduct rules that must be in the always-loaded surface.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TEST_NAME="structure"
echo "$TEST_NAME"

assert_ok "check-skill --static passes" "$REPO_ROOT/scripts/check-skill" --static

skill="$(cat "$SKILL_ROOT/SKILL.md")"

# The conduct rules must live in SKILL.md, which is always loaded, not only in the reference.
assert_contains "SKILL.md forbids disclaimers"        "Never append investment disclaimers" "$skill"
assert_contains "SKILL.md forbids refusing to compute" "Never refuse a computation"          "$skill"
assert_contains "SKILL.md forbids merit adjectives"   "Never editorialise on merit"          "$skill"
assert_contains "SKILL.md forbids baseline-free verdicts" "No baseline-free verdicts"        "$skill"
assert_contains "SKILL.md forbids intuition-driven method" "No methodology from intuition"   "$skill"
assert_contains "SKILL.md forbids world claims"       "No claims about the state of the world" "$skill"
assert_contains "SKILL.md forbids silent failure"     "No silent failure"                    "$skill"
assert_contains "SKILL.md forbids tone"               "No tone in either direction"          "$skill"
assert_contains "SKILL.md forbids exhaustion claims"  "No declarations of exhaustion"        "$skill"
assert_contains "SKILL.md requires n and a standard error" "point estimate without n"        "$skill"
assert_contains "SKILL.md names the preferences store" "pm-prefs"                            "$skill"
assert_contains "SKILL.md names the stats helper"     "pm-stats"                             "$skill"
assert_contains "SKILL.md names the audit helper"     "pm-audit"                             "$skill"
assert_contains "SKILL.md names the docs router"      "pm-docs"                              "$skill"

# The description drives triggering; it must name the work and the exclusions.
desc="$(sed -n '3p' "$SKILL_ROOT/SKILL.md")"
for term in Sharpe attribution backtest out-of-sample equity risk; do
  assert_contains "the description mentions $term" "$term" "$desc"
done
assert_contains "the description states an exclusion" "Exclude" "$desc"

# References must not contain the phrasing they forbid. SKILL.md and analyst-conduct.md are the
# two places that quote the banned phrases in order to prohibit them.
banned_out=""
while IFS= read -r hit; do banned_out+="$hit"$'\n'; done < <(
  grep -rniE "past performance is not|not financial advice|consult a (qualified|financial) (adviser|advisor|professional)" \
    "$SKILL_ROOT" --include='*.md' | grep -vE "analyst-conduct\.md|SKILL\.md" || true)
if [[ -z "$banned_out" ]]; then
  pass "only the conduct surfaces quote a disclaimer phrase"
else
  fail "only the conduct surfaces quote a disclaimer phrase" "$banned_out"
fi

# Every reference opens with a load condition so the model knows when to read it.
for f in "$SKILL_ROOT"/references/*.md; do
  name="$(basename "$f")"
  head5="$(sed -n '1,6p' "$f")"
  if [[ "$head5" == *"Load "* ]]; then
    pass "$name states when to load it"
  else
    fail "$name states when to load it" "no 'Load ...' line in the first six lines"
  fi
done

# Scripts must be dependency-free: standard library imports only.
while IFS= read -r line; do
  :
done < /dev/null
bad_imports=""
for s in pm-stats pm-audit pm-docs pm-prefs; do
  while IFS= read -r mod; do
    case "$mod" in
      argparse|ast|csv|json|math|os|re|sys|datetime|pathlib|dataclasses|textwrap|importlib|\
      collections|itertools|functools|typing|__future__) ;;
      *) bad_imports+="$s imports $mod"$'\n' ;;
    esac
  done < <(grep -hoE '^(import|from) [a-z_]+' "$BIN/$s" | awk '{print $2}' | sort -u)
done
if [[ -z "$bad_imports" ]]; then
  pass "scripts import only the standard library"
else
  fail "scripts import only the standard library" "$bad_imports"
fi

# The plugin and marketplace manifests must agree.
agree="$(python3 - "$REPO_ROOT" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
mk = json.loads((root / ".claude-plugin" / "marketplace.json").read_text())
pl = json.loads((root / "skills" / "bq-pm-quant" / ".claude-plugin" / "plugin.json").read_text())
entry = mk["plugins"][0]
diffs = [k for k in ("name", "description", "homepage", "repository", "license")
         if entry.get(k) != pl.get(k)]
print("agree" if not diffs else "differ: " + ",".join(diffs))
PY
)"
assert_eq "the manifests agree on the shared fields" "agree" "$agree"

# Eval corpora must be well-formed and their regexes must compile.
evals_ok="$(python3 - "$REPO_ROOT" <<'PY2'
import json, re, sys
from pathlib import Path
root = Path(sys.argv[1])
errs = []
tr = json.loads((root / "evals" / "prompts.json").read_text())
if tr.get("skill") != "bq-pm-quant":
    errs.append("prompts.json names the wrong skill")
if len(tr["should_trigger"]) < 15:
    errs.append("should_trigger corpus is too small to be informative")
if len(tr["should_not_trigger"]) < 8:
    errs.append("should_not_trigger corpus is too small")
overlap = set(tr["should_trigger"]) & set(tr["should_not_trigger"])
if overlap:
    errs.append(f"a prompt appears in both corpora: {overlap}")

cd = json.loads((root / "evals" / "conduct.json").read_text())
ids = [c["id"] for c in cd["cases"]]
if len(ids) != len(set(ids)):
    errs.append("duplicate conduct case ids")
for case in cd["cases"]:
    for key in ("id", "tempts", "prompt"):
        if not case.get(key):
            errs.append(f"conduct case missing {key}")
    if not case.get("forbidden") and not case.get("required"):
        errs.append(f"conduct case {case.get('id')} asserts nothing")
    for pat in case.get("forbidden", []) + case.get("required", []):
        try:
            re.compile(pat)
        except re.error as exc:
            errs.append(f"{case['id']}: bad regex {pat!r}: {exc}")
# every forbidden pattern must actually match the phrasing it claims to forbid
probes = {
    "no-disclaimer": "Past performance is not indicative of future results.",
    "no-refusal": "I can't help with position sizing.",
    "no-exhaustion-claim": "We have exhausted the reasonable approaches.",
}
for cid, probe in probes.items():
    case = next(c for c in cd["cases"] if c["id"] == cid)
    if not any(re.search(p, probe, re.I) for p in case["forbidden"]):
        errs.append(f"{cid}: no forbidden pattern matches its own example violation")
print("ok" if not errs else "; ".join(errs))
PY2
)"
assert_eq "eval corpora are well-formed" "ok" "$evals_ok"
assert_ok "evals/run-local is executable" test -x "$REPO_ROOT/evals/run-local"
assert_ok "evals/run-local parses" python3 -c \
  "import ast,sys; ast.parse(open('$REPO_ROOT/evals/run-local').read())"

# Licence present at both levels.
assert_ok "repository LICENSE exists" test -f "$REPO_ROOT/LICENSE"
assert_ok "skill LICENSE exists"      test -f "$SKILL_ROOT/LICENSE"

finish
