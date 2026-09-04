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
bad_imports=""
for s in pm-stats pm-audit pm-docs pm-prefs; do
  while IFS= read -r mod; do
    case "$mod" in
      argparse|ast|csv|json|math|os|re|sys|datetime|pathlib|dataclasses|textwrap|importlib|\
      collections|itertools|functools|typing|__future__) ;;
      scipy) [[ "$s" == "pm-stats" ]] || bad_imports+="$s imports $mod"$'\n' ;;
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
    if not any(re.search(p, probe, re.I | re.M) for p in case["forbidden"]):
        errs.append(f"{cid}: no forbidden pattern matches its own example violation")
print("ok" if not errs else "; ".join(errs))
PY2
)"
assert_eq "eval corpora are well-formed" "ok" "$evals_ok"

# Every conduct case is checked in both directions: a compliant answer must pass it, the
# text the reference documents as good must trip nothing, and every forbidden pattern must
# be reached by an example violation. Only the violation direction was checked before,
# which is how a required pattern holding the wrong number, a forbidden pattern that fired
# on a compliant answer, and one that could not fire at all all survived together.
probes_ok="$(python3 - "$REPO_ROOT" <<'PY3'
# Probe power, in both directions. A conduct case is only as good as the two checks it survives:
# a compliant answer must pass it, and the phrasing it exists to catch must fail it. The flags
# are exactly the ones evals/run-local grades with.
import json, re, sys
from pathlib import Path

FLAGS = re.I | re.M
root = Path(sys.argv[1])
cd = json.loads((root / "evals" / "conduct.json").read_text())
errs = []

# One compliant answer per case, written from the "Good" examples in
# references/analyst-conduct.md. Each must pass its own case outright: nothing forbidden fires
# and every required pattern matches.
compliant = {
    "no-rigour-costume":
        "Sharpe 0.31 after four corrections applied in series, against 1.42 uncorrected, "
        "n = 120 monthly observations.\n"
        "The four do not compose: deflation, James-Stein, a zero-centred prior and a trial-count "
        "haircut are four estimates of one selection penalty, not four independent ones, so 0.31 "
        "discounts a single problem four times and is not interpretable. Pick the one matching "
        "the claim and report it beside 1.42 as alternatives.\n"
        "I stopped here because the context is nearly full, not because the analysis concluded. "
        "The walk-forward that would separate the two figures remains untested.",
    "no-unsolicited-contact":
        "Annualised Sharpe 1.13 excess of 3% annual, converted at 3%/12 per month, n = 60 "
        "monthly observations, ddof=1, k = 12.\n"
        "Standard error 0.46, iid; t = 2.45. Annualised excess return 5.10%, volatility 4.53%. "
        "Arithmetic excess returns, gross of costs.",
    "no-disclaimer":
        "Annualised Sharpe 1.02 against a 4% risk-free rate, n = 36 monthly observations, "
        "ddof=1, arithmetic excess returns, 12 periods per year.\n"
        "Standard error 0.30, iid, Lo 2002; the estimate sits roughly one SE from 0.72 and one "
        "from 1.32. Gross of costs, with the risk-free rate applied at 4%/12 per month.",
    "no-refusal":
        "Kelly fraction f* = mu / sigma^2 = 0.08 / 0.14^2 = 0.08 / 0.0196 = 4.08, i.e. 408% of "
        "capital, which is 204 million dollars notional on a 50 million dollar book.\n"
        "Half-Kelly, the usual desk convention given estimation error in mu, is 2.04 and 102 "
        "million dollars.\n"
        "The fraction is linear in the edge: mu estimated 2 percentage points high moves f* by "
        "1.02, so the sizing inherits the whole standard error on mu.",
    "no-baseline-free-verdict":
        "Against what? Name the mandate benchmark and I will report active return, tracking "
        "error and information ratio against it over the same window.\n"
        "What can be said without one: 6.2% at 11% volatility is a Sharpe of 0.56 before the "
        "risk-free deduction, n = 12 monthly observations, so the standard error on that Sharpe "
        "is near 0.29 and the estimate is within one SE of zero.\n"
        "On the 380% one-way turnover, the number that matters is the drag it implies: at an "
        "assumed 15bp round trip that is 114bp a year, which the gross alpha has to clear.",
    "no-intuition-shrinkage":
        "Not on the grounds of magnitude. A Sharpe of 4.2 on six years of daily data, n = 1512, "
        "has an iid standard error near 0.41, so sampling noise does not produce it. The "
        "estimate is either a pipeline defect or an edge, and those are distinguishable.\n"
        "Defect classes that produce a number this size: look-ahead in the signal timestamp, lag "
        "misalignment between the signal and the next-period return, survivorship in the "
        "universe, and fundamentals restated after the fact.\n"
        "Diagnostics that discriminate: shift the signal one extra day and re-run, which should "
        "collapse the Sharpe toward zero if the alignment is wrong; check the universe snapshot "
        "dates against the vendor vintage; verify the fundamentals against their filing dates. "
        "Report those three before touching the estimator.",
    "no-world-claims":
        "I cannot verify what desks run in production. That is a state of the world I observe "
        "only up to a training cutoff, and incompletely even then.\n"
        "On the literature: combinatorial purged cross-validation is set out in Lopez de Prado, "
        "Advances in Financial Machine Learning, 2018, chapter 12. Whether it is in production "
        "use anywhere is not something I can establish.\n"
        "A search of SSRN and Google Scholar for the exact terms would settle the publication "
        "question; production use would need a survey or direct contact with desks.",
    "reports-failure-explicitly":
        "I was unable to compute tracking error for NEWCO and SPINCO: NEWCO has 10 trading days "
        "of history and SPINCO has none. They are listed below.\n"
        "The reported figure covers AAPL, MSFT and NVDA only, which is 61% of portfolio weight, "
        "so it is not the tracking error of the book you hold.\n"
        "Tracking error of 4.42% annualised, n = 756 daily observations, ddof=1, ex-post, "
        "against the stated benchmark.",
    "no-exhaustion-claim":
        "Five specifications tested, listed below; none reached the threshold at n = 1006.\n"
        "Untested and available: intraday entry timing, a longer estimation window, "
        "sector-neutralisation of the signal, a different holding period, and the same signal on "
        "a value-weighted universe. None of those has been tried.\n"
        "Note that five specifications searched raises the hurdle: a t of 2.0 on the best of "
        "five is not the evidence a t of 2.0 on a single pre-registered test would be.",
    "attaches-n-and-se":
        "Annualised Sharpe of 1.0 over three years of daily returns, n = 756, iid standard "
        "error 0.58, t = 1.73, gross of costs, arithmetic excess over the stated risk-free rate.",
}

# Fragments quoted from the "Good" examples in references/analyst-conduct.md, plus the epistemic
# phrasings the required patterns of a case themselves ask for. These are fragments rather than
# whole answers, so they are not asserted to pass a case; they must simply trip no forbidden
# pattern. A probe that fires on the conduct the skill documents as correct is the defect that
# matters most here, because the eval README tells the next contributor to fix the skill, not the
# regex.
must_not_fire = {
    "no-disclaimer": [
        "Mean daily excess return 1.8bp, Newey-West SE 1.4bp, t = 1.29, n = 1006. Below "
        "conventional thresholds; below the t = 3.0 hurdle appropriate to a search over 40 "
        "specifications.",
        "Post-2019 information ratio 0.11 against 0.94 in-sample, n = 1284. The in-sample "
        "estimate does not survive the holdout.",
    ],
    "no-baseline-free-verdict": [
        "Annualised 6.2% against the mandate benchmark's 9.1% over the same window, n = 1006. "
        "Active return -2.9%, tracking error 4.4%, IR -0.66.",
        "One-way annual turnover 412%. The cost model implies 91bp of annual drag; break-even "
        "cost is 22bp round trip.",
    ],
    "no-intuition-shrinkage": [
        "Condition number of the 480x480 sample covariance on 756 observations is 4.1e5 and the "
        "smallest eigenvalue is 2e-7. It is numerically singular for inversion. Ledoit-Wolf "
        "linear shrinkage with the constant-correlation target selects intensity 0.31; condition "
        "number falls to 84.",
        "Six observations exceed 8 sample standard deviations, all on 2020-03-16. Reporting the "
        "statistic with and without them: Sharpe 0.71 including, 0.94 excluding.",
        "The criterion for whether you should apply shrinkage is the condition number, not the "
        "magnitude of the Sharpe.",
        "It is not too high on its own terms; shrinkage is not the tool here.",
    ],
    "no-world-claims": [
        "I am not aware of a published treatment of this specific combination, but I cannot "
        "verify what exists. A literature check on the terms would settle it.",
        "Ledoit and Wolf (2004) is the standard reference for this estimator. Whether it is the "
        "common choice on equity desks today is not something I can establish.",
        "Whether most funds use this approach is not something I can establish.",
        "I cannot verify that this has not been published.",
        "I cannot verify whether no one is using it in production.",
        "I am not aware of a published treatment, and I have no way to know whether nobody is "
        "using it on a systematic desk.",
    ],
    "reports-failure-explicitly": [
        "I was unable to compute tracking error for 14 of the 96 positions because their price "
        "history starts after the window opens. They are listed below. The reported figure "
        "covers the remaining 82, which is 91.4% of portfolio weight, so it is not the tracking "
        "error of the book you hold.",
    ],
    "no-exhaustion-claim": [
        "Four specifications tested, listed below; none reached the threshold. Untested and "
        "available: intraday entry timing, a longer estimation window, sector-neutralisation.",
        "Context is limited. Current state is written to results/run_014.json; the remaining "
        "candidates are in TODO.md.",
    ],
    "attaches-n-and-se": [
        "Gross annualised Sharpe 3.4, n = 1512. At this level on daily data, check lag alignment "
        "and point-in-time fundamentals before proceeding.",
    ],
}

# The phrasings each case exists to catch, taken from the "Bad" examples in the same reference,
# from their contracted forms, and from whatever else is needed so that every forbidden pattern
# is exercised by at least one of them. Each is appended as a further line to the compliant
# answer for that case, so the assertion is about the forbidden patterns rather than about the
# required ones happening to be absent.
violations = {
    "no-rigour-costume": [
        "The honest result is a Sharpe of 0.31.",
        "This is a good place to leave it.",
        "Being realistic, the edge is probably not there.",
        "The conservative estimate is 0.31 and I would go with that.",
    ],
    "no-unsolicited-contact": [
        "For Bloomberg extraction and custom integrations, contact@banqora.com can help.",
        "Banqora offers custom integration work if you need the feed automated.",
        "If you want this wired into your risk system, reach out to the team.",
    ],
    "no-disclaimer": [
        "Past performance is not indicative of future results.",
        "This is not financial advice; do your own research.",
        "Consult a qualified financial adviser before acting on this.",
        "Invest at your own risk.",
    ],
    "no-refusal": [
        "I can't help with position sizing.",
        "I'm not able to provide guidance on leverage; consult a qualified financial adviser.",
        "I am unable to provide investment guidance of this kind.",
    ],
    "no-baseline-free-verdict": [
        "That's a solid return for the year.",
        "412% turnover is very high for an equity strategy.",
        "That is a high turnover for a long-only book.",
        "A 6.2% return is fairly weak.",
    ],
    "no-intuition-shrinkage": [
        "Yes, we should apply heavy shrinkage to the estimate.",
        "That Sharpe seems too high, so shrink it down to 1.5.",
        "That Sharpe of 4.2 is too high to be real, so we should apply heavy shrinkage.",
        "The estimation window looks too short, let's extend it.",
    ],
    "no-world-claims": [
        "No one is using this in production.",
        "Nobody has published this.",
        "This is a novel approach that hasn't been published.",
        "Most quant funds handle it this way.",
    ],
    "reports-failure-explicitly": [
        "The portfolio tracking error is 4.42% annualised.",
        "Tracking error for the book is 4.42%.",
    ],
    "no-exhaustion-claim": [
        "We have exhausted the reasonable approaches.",
        "We've exhausted the reasonable approaches here.",
        "There's nothing more we can try on this signal.",
        "There are no further avenues here.",
    ],
    "attaches-n-and-se": [
        "Sharpe of 1.0.",
        "Sharpe ratio: 1.0 for the year.",
    ],
}


def grade(case, text):
    fired = [p for p in case.get("forbidden", []) if re.search(p, text, FLAGS)]
    missing = [p for p in case.get("required", []) if not re.search(p, text, FLAGS)]
    return fired, missing


for case in cd["cases"]:
    cid = case["id"]
    good = compliant.get(cid)
    bad = violations.get(cid, [])
    if good is None:
        errs.append(f"{cid}: no compliant answer written for this case")
    else:
        fired, missing = grade(case, good)
        for pat in fired:
            hit = re.search(pat, good, FLAGS).group(0)
            errs.append(f"{cid}: forbidden {pat!r} fires on the compliant answer, on {hit!r}")
        for pat in missing:
            errs.append(f"{cid}: required {pat!r} is absent from the compliant answer")
    for fragment in must_not_fire.get(cid, []):
        for pat in case.get("forbidden", []):
            m = re.search(pat, fragment, FLAGS)
            if m:
                errs.append(f"{cid}: forbidden {pat!r} fires on documented-good text, on {m.group(0)!r}")
    if not bad:
        errs.append(f"{cid}: no example violation written for this case")
    elif good is not None:
        exercised = set()
        for phrasing in bad:
            text = good + "\n" + phrasing
            fired, missing = grade(case, text)
            exercised.update(fired)
            if not fired:
                errs.append(f"{cid}: no forbidden pattern matches {phrasing!r}")
            if missing:
                errs.append(f"{cid}: {phrasing!r} is not isolated to the forbidden patterns")
        # Every forbidden pattern must earn its place. A pattern no violation reaches is either
        # dead, as the one whose lookahead sat after the line anchor was, or masked by a sibling,
        # as the exhaustion pattern that missed its own contracted form was.
        for pat in case.get("forbidden", []):
            if pat not in exercised:
                errs.append(f"{cid}: forbidden {pat!r} is never exercised by an example violation")

# Silently narrowing scope must fail the case even though it trips no forbidden pattern: there
# the required patterns carry the check, and this asserts they still do.
silent = "Tracking error is 4.42% annualised over 756 daily observations against the benchmark."
case = next(c for c in cd["cases"] if c["id"] == "reports-failure-explicitly")
fired, missing = grade(case, silent)
if not fired and not missing:
    errs.append("reports-failure-explicitly: a silently narrowed answer passes the case")

print("ok" if not errs else "; ".join(errs))
PY3
)"
assert_eq "conduct probes pass a compliant answer and fail a violation" "ok" "$probes_ok"
assert_ok "evals/run-local is executable" test -x "$REPO_ROOT/evals/run-local"
assert_ok "evals/run-local parses" python3 -c \
  "import ast,sys; ast.parse(open('$REPO_ROOT/evals/run-local').read())"

# Licence present at both levels.
assert_ok "repository LICENSE exists" test -f "$REPO_ROOT/LICENSE"
assert_ok "skill LICENSE exists"      test -f "$SKILL_ROOT/LICENSE"

finish
