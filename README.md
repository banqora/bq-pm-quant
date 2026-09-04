# bq-pm-quant

An agent skill for portfolio-manager quantitative analysis.

It addresses a specific pairing of gaps. Portfolio managers increasingly write analysis code through
an AI assistant without being able to audit what it produces. The assistant, in turn, is fluent in
Python and unreliable on the statistical conventions the work depends on: it will annualise a Sharpe
ratio without checking for autocorrelation, report a t-statistic from the two hundredth signal
tried, invert a singular covariance matrix, and then wrap the answer in disclaimers the manager
did not ask for.

This skill supplies three things.

**Methodology.** What test to run and what its standard error is. Sharpe ratios with iid,
non-normal, and autocorrelation-adjusted standard errors. Newey-West and the stationary bootstrap.
Multiple-testing correction and the deflated Sharpe ratio. Purged and embargoed cross-validation,
walk-forward protocol, and the probability of backtest overfitting. Covariance shrinkage and when
the sample matrix is unusable. Brinson attribution and multi-period linking.

**Engineering.** How to structure analysis code so that a manager who cannot read it can still
establish that it is correct: one canonical implementation per number, conventions in one config
object, invariants asserted rather than eyeballed, failures that raise rather than fall back, and a
golden test that recovers a known answer from simulated data before the pipeline touches real data.
There is no exploratory tier. The numbers go into a decision either way, so the standard is strict
typing, lint, unit tests, and an 80% coverage floor rising to 95% on any module that produces a
reported statistic. Inside an existing codebase the standard applies as a ratchet: every line
written or touched meets it in full, untouched code is left alone, and no gate is lowered to make a
build pass.

**Conduct.** An output contract. Report the estimate, the sample, the uncertainty, and the
convention. No disclaimers, no merit adjectives, no baseline-free verdicts, no methodology chosen
from intuition, no unverifiable claims about the state of the industry, and no failure delivered as
a quieter result.

## Install

```bash
claude plugin marketplace add banqora/bq-pm-quant
claude plugin install bq-pm-quant@bq-pm-quant
```

Or point Claude Code at a local checkout:

```bash
claude plugin marketplace add /path/to/bq-pm-quant
```

## Contents

```
skills/bq-pm-quant/
  SKILL.md              the always-loaded surface: conduct, authority table, analysis path
  references/           twelve topic references, loaded only when the task needs them
  scripts/              four executable helpers, offline, standard library only
```

### References

| File | Scope |
|---|---|
| `analyst-conduct.md` | Output contract: disclaimers, refusals, tone, failure reporting, delivery format |
| `return-conventions.md` | Return construction, compounding, annualisation, risk-free, currency, calendars |
| `performance-statistics.md` | Sharpe, information ratio, Sortino, drawdown, standard errors, deflation, shrinkage |
| `inference.md` | t-tests, HAC standard errors, bootstrap, multiple testing, power, strategy comparison |
| `out-of-sample.md` | Holdout protocol, walk-forward, purged CV, PBO, reality-check tests, the trial log |
| `backtesting.md` | Timing contract, rebalancing, transaction costs, capacity, what a backtest cannot prove |
| `risk-models.md` | Covariance and shrinkage, factor models, beta, tracking error, VaR and expected shortfall |
| `attribution.md` | Brinson variants, factor attribution, multi-period linking, reconciliation |
| `equity-desk.md` | Universe, classification, corporate actions, borrow, liquidity, cross-sectional signals |
| `data-integrity.md` | Survivorship, look-ahead, vintage, stale prices, alignment, fabricated values |
| `coding-standards.md` | Project layout, config, assertions, golden test, determinism, code review |
| `review-checklist.md` | What to demand before a number is used, and how to diagnose a surprising one |

### Scripts

All four are Python 3 with no dependencies beyond the standard library.

**`pm-stats`** produces a complete statistics block from a return or price series.

```bash
pm-stats returns.csv --rf 0.0525 --trials 12 --benchmark spx.csv --csv report.csv
```

Reports annualised arithmetic and geometric return, volatility, Sharpe with iid, Mertens
non-normal, and Lo autocorrelation-adjusted standard errors, a Newey-West t-statistic on the mean,
maximum drawdown with peak, trough and recovery dates, historical VaR and expected shortfall,
skewness and kurtosis, autocorrelation with its null standard error, Ljung-Box, probabilistic and
deflated Sharpe, minimum track record length, and active statistics against a benchmark.

It also runs an integrity pass and flags what it finds: exact-zero return runs indicating stale or
forward-filled prices, single-period moves above 50% indicating unadjusted corporate actions,
weekend rows, duplicate or non-monotonic dates, a Sharpe high enough to indicate a lag defect, an
autocorrelation adjustment that is really estimation noise, and a missing trial count that makes the
p-values uninterpretable.

It refuses rather than guesses. Unparsable rows are an error, not a silent drop, because dropping
rows changes `n` and therefore every annualisation. A series whose largest absolute value exceeds
150% is an error naming both possible causes, rather than a quiet rescale by one hundred.

**`pm-audit`** statically flags the defect classes that produce plausible wrong numbers.

```bash
pm-audit src/ --severity high
```

Look-ahead through negative shifts, centred windows and backward fill. Leakage through shuffled
splits, plain k-fold and full-panel scalers. Degrees-of-freedom defaults. Broad exception handlers
and constant fallbacks. Positional rather than date alignment. Hardcoded conventions. Missing type
annotations and explicit `Any` on public signatures. Non-determinism through the legacy global seed
and salted string hashes. Summed simple returns. It reads notebooks as well as scripts.

It is a lint, not a proof, and it deliberately does not replace the type checker, the linter, or the
test suite. It prints the commands for those at the end of every run.

**`pm-prefs`** stores the desk's conventions and reporting format so they are asked once.

```bash
pm-prefs init --project
pm-prefs set output_format xlsx
pm-prefs get output_format
```

Resolution order is project file, then environment override, then user config.

**`pm-docs`** routes plain words to the single most relevant reference.

```bash
pm-docs "is my sharpe significant"
pm-docs "how do i do out of sample properly"
```

## Tests

```bash
tests/run
```

Three deterministic suites. Offline, no model calls, no third-party dependencies.

| Suite | Covers |
|---|---|
| `estimators` | The statistics in `pm-stats` against closed-form and simulated targets: normal and chi-squared tails, bias-corrected moments, Newey-West against the naive standard error on iid and AR(1) series, drawdown on a hand-built path, the Sharpe standard error against its closed form, recovery of a simulated Sharpe within three standard errors, a zero-edge series producing an insignificant t, and deflation falling as the trial count rises |
| `scripts` | End-to-end behaviour of all four helpers, including every audit rule, the refusal paths, preference resolution and override order, and determinism |
| `structure` | Frontmatter, manifest agreement, reference and anchor link integrity, dependency-free imports, and the presence of each conduct rule in the always-loaded surface |

## Evaluations

The tests above prove the scripts work. They cannot prove the skill changes how a model behaves.
That is what `evals/` is for, and it needs live model calls, so it runs locally against a
signed-in Claude Code subscription rather than in CI.

```bash
evals/run-local --check-auth
evals/run-local --conduct-only
```

`evals/conduct.json` holds eight probes, each a prompt built to tempt one specific failure, paired
with patterns that must not appear in the response and patterns that must. They cover appending an
investment disclaimer to a computed number, refusing a position-sizing calculation, calling a return
good with no comparator, shrinking a Sharpe because it looks too large, asserting what the industry
does, silently narrowing scope when data is missing, declaring the options exhausted, and reporting
a point estimate with no sample size.

`evals/prompts.json` checks the skill fires on portfolio work and stays out of the way otherwise,
including the near-misses: tax treatment, legal wording, and a discretionary buy recommendation
must not trigger it.

Eight cases at one run each is a smoke test, not a measurement. A green run means no known
regression. See [evals/README.md](evals/README.md).

## License

Apache-2.0. See [LICENSE](LICENSE).

This is independent tooling. It is not affiliated with, endorsed by, or derived from any index
provider, data vendor, or standards body. Nothing in it is investment, tax, or legal advice.
