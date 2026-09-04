# Review checklist

Load before a number is used for a decision, and when a manager asks whether a result can be
trusted. Written so that each item can be demanded and verified without reading code.

## The seven questions

Ask these of any result. Each has a checkable answer. A result that cannot answer all seven is
provisional.

1. **What is `n`, and what is the standard error?** No sample size, no result. See [performance
   statistics](performance-statistics.md).
2. **How many specifications were tried before this one?** If the answer is unknown, the p-value
   is uninterpretable and should not appear. See [out of sample](out-of-sample.md#the-trial-log).
3. **Is it in-sample, cross-validated, or out-of-sample, and under what protocol?** Name the level
   from the evidence table, not the word "out-of-sample".
4. **Is it gross or net, and what is the break-even cost?** See
   [backtesting](backtesting.md#transaction-costs).
5. **What was the universe, and how was membership determined as of each date?** See [data
   integrity](data-integrity.md#survivorship).
6. **What is the data snapshot, and does the pipeline reproduce from a cached file?**
7. **Did the pipeline pass the noise test?** Signal replaced with random noise, edge disappears.
   See [coding standards](coding-standards.md#the-golden-test).

## Diagnose a surprising number

A number that surprises you is a hypothesis about a defect, not a discovery and not a reason to
adjust the number. Identify the defect class the magnitude implies, run the test that
discriminates, and report what was ruled out. Never shrink, winsorise, or cap a value because of
its size.

| Symptom | Most likely causes, in order | Discriminating test |
|---|---|---|
| Daily gross Sharpe above 3 | Lag error; look-ahead in a non-price field; survivorship | Shift the signal one extra period; if the edge vanishes it was the lag. Then the noise test |
| Volatility lower than expected | Forward-filled prices; weekend or holiday rows; stale marks | Count exact-zero returns and identical-price runs per security |
| Beta near zero on a real holding | Stale prices; start-aligned series; too few observations | Assert identical date indices; recompute with a Dimson correction |
| Beta or correlation implausible | Positional rather than date alignment | Print the first and last date of each aligned series |
| A single-day return near ±50% | Unadjusted split or a spin-off | Check the corporate-action record for that name and date |
| Cumulative return does not match the periodic returns | Arithmetic summation instead of compounding | Recompute as a product; compare |
| Two tracking errors differ by a large factor | Rebalancing assumption, not the estimator | Hold everything fixed and switch only the drift treatment |
| Metrics suspiciously uniform across securities | Placeholder function returning a constant | Reverse-engineer the value back to the constant that produces it |
| Portfolio return does not match the sum of contributions | Weight convention; missing cash; a dropped position | Reconcile weights, confirm they sum to the declared exposure |
| Optimiser weights extreme or unstable | Unshrunk covariance; error maximisation | Report the condition number; re-run with shrinkage and compare |
| Result changed with no code change | Vendor restatement | Compare against the cached snapshot and its hash |
| VaR breached far more often than expected | Normal assumption on fat tails; horizon scaling | Kupiec coverage test; refit with a Student-t |
| A result that only appears in one sub-period | Regime dependence or a data defect confined to that period | Run the integrity pass on that sub-period alone |

## Before reporting

- [ ] Sample size and window on every estimate
- [ ] Standard error with the estimator named: iid, Lo, Mertens, Newey-West with lag, or bootstrap
      with block length and replications
- [ ] Conventions declared once: return type, periods per year, risk-free instrument and day
  count,
      base currency, total or price return
- [ ] Gross and net both shown, cost model stated, break-even cost reported
- [ ] Trial count stated, and the multiplicity correction applied
- [ ] Evidence level stated from the out-of-sample table
- [ ] Data vintage and file hash recorded
- [ ] Every exclusion visible in the output, with its count and its portfolio weight
- [ ] Golden test and noise test run, and reported as run
- [ ] No merit adjective, no disclaimer, no baseline-free judgement anywhere in the text
- [ ] Any failure stated as "I was unable to X because Y", with what the result no longer covers

## The engineering gate

Applies to any code that produced a number, including code an assistant wrote and code inherited
from someone else. There is no exploratory tier: the numbers go into a decision either way. See
[coding standards](coding-standards.md#treat-every-line-as-production).

- [ ] `ruff check` and `ruff format --check` clean
- [ ] `mypy --strict` clean on the analysis package, with quantities that must not be interchanged
      given distinct types or unit-bearing names
- [ ] `pytest` passing, with known-answer, property, boundary, and regression tests present
- [ ] Coverage at or above 80% overall and 95% on any module producing a reported statistic
- [ ] Golden test and noise test named explicitly and run
- [ ] Two runs of the same commit on the same data hash produce identical output
- [ ] No gate lowered, and every exemption scoped, dated, and stated in the config
- [ ] In an existing codebase: every line written or touched meets the standard in full, untouched
      code left alone, and the report says which modules are exempt and why

`scripts/pm-audit` covers a subset of this statically. It does not run the type checker, the
linter, or the tests, and a clean audit is not a substitute for any of them.

## Escalate before proceeding

Stop and report rather than working around, in each of these cases. Each is a decision the manager
must make, not a problem to route past.

- The trial count is unavailable for an inherited backtest.
- Point-in-time universe membership is unavailable and the result depends on the cross-section.
- A material fraction of the portfolio has insufficient history for the statistic requested.
- Two implementations of the same statistic disagree and the cause is not yet identified.
- The optimiser did not converge, or its solution violates a stated constraint.
- Borrow data is unavailable for a strategy with a material short leg.
- The data cannot be reproduced from a cached snapshot.

In each case the report is the deliverable: what was attempted, what blocked it, what the number
would cover if the block were removed, and what would remove it.
