# Coding standards

Load when writing, structuring, or reviewing analysis code for a portfolio manager. The reader of
this code cannot audit it line by line. The code must therefore be structured so that its
correctness can be checked from outside.

## The governing constraint

A portfolio manager will act on a number without reading the function that produced it. Every
practice below exists to make that safe. The three that matter most, in order:

1. **Assert invariants in the code** so a defect stops the run rather than producing a plausible
   number.
2. **Validate the whole pipeline against a known answer** so the manager has one check they can
   demand and understand.
3. **Fail loudly** so a failure is never delivered as a quieter result.

These sit on top of ordinary production engineering, which is not optional here either: typed,
linted, unit-tested to a coverage floor, and deterministic. See [Treat every line as
production](#treat-every-line-as-production).

## Treat every line as production

There is no exploratory tier. A number produced by a throwaway script is used in exactly the same
way as a number produced by a reviewed pipeline: it goes into a decision. The script written to
answer one question in an afternoon is the script that will be re-run next quarter, copied into
another project, and cited in a meeting long after anyone remembers its assumptions.

The standards below therefore apply to sample code, notebooks promoted to scripts, one-off
analyses, and anything an assistant generates. They are not aspirational and they are not deferred
until the analysis is "real".

| Requirement | Gate | Why it applies here specifically |
|---|---|---|
| Type annotations on every public function | `mypy --strict` or Pyright strict, zero errors | A series of prices and a series of returns have the same type to the interpreter and different meanings to the analysis. Types are where that distinction gets written down |
| Lint and format | `ruff check` and `ruff format --check`, zero findings | Removes the diff noise that hides a one-character lag change in review |
| Unit tests | `pytest`, all passing | The only mechanism by which a manager who cannot read the code can be shown that it works |
| Coverage | 80% of lines overall; 95% on any module that produces a reported number | An untested branch in a statistics module is an unreported number waiting to be wrong |
| Known-answer tests | Golden test and noise test present and passing | Catches the defect classes that unit tests structurally cannot |
| Determinism | Two runs of the same commit on the same data hash produce identical output | A result that cannot be reproduced cannot be defended |

Coverage is a floor, not a target. Eighty per cent of lines executed with no assertion on the
values is worth nothing. The number that matters is whether every reported statistic has a test
that would fail if its formula changed.

### Working into an existing codebase

Most of this work happens inside a repository that predates the standard. Do not open by demanding
a rewrite, and do not use the existing state as licence to match it.

Apply the ratchet. Every line you write or touch meets the standard in full; everything else stays
as it is until someone has a reason to change it.

- **New modules**: fully typed, fully linted, tested to the coverage floor. No exceptions.
- **Edited functions**: bring the whole function up to standard, not just the changed line. Add
  its test in the same commit.
- **Untouched code**: leave it. A large mechanical reformat destroys the git blame that is often
  the only surviving record of why a convention was chosen.
- **Configure the tools to ratchet with you.** Scope the strict settings to the new package, or
  baseline the existing findings so the count can only fall:

```toml
[[tool.mypy.overrides]]
module = ["legacy.*"]
ignore_errors = true          # legacy is exempt; everything else is --strict
```

```bash
ruff check --statistics .              # record the current count as the ceiling
pytest --cov=src/newmodule --cov-fail-under=80   # coverage gate on the new package only
```

- **Never lower a gate to make a build pass.** If the standard blocks a merge, either the code
  changes or the exemption is explicit, scoped, and dated in the config.
- **When an existing function produces a reported number**, it is in scope regardless of who wrote
  it. Add the known-answer test before changing anything, so that a behaviour change is visible.

Say what you did. "New module fully typed and tested to 94%; the three legacy modules it calls are
untyped and exempted in `pyproject.toml` with a note" is a complete report. Quietly matching the
surrounding style is not.

### A working configuration

```toml
# pyproject.toml
[project]
name = "book-analysis"
requires-python = ">=3.11"

[tool.ruff]
line-length = 100
target-version = "py311"

[tool.ruff.lint]
# PD and NPY catch pandas and numpy misuse directly, including chained assignment and the
# ddof and inplace defaults that silently change a statistic.
select = ["E", "F", "W", "I", "N", "UP", "B", "A", "C4", "SIM", "ARG", "PD", "NPY", "RUF"]

[tool.mypy]
python_version = "3.11"
strict = true
warn_unreachable = true

[tool.pytest.ini_options]
addopts = "--strict-markers --strict-config -q"
testpaths = ["tests"]

[tool.coverage.report]
fail_under = 80
show_missing = true
exclude_lines = ["if TYPE_CHECKING:", "raise NotImplementedError"]
```

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.6.9
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format
  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.11.2
    hooks:
      - id: mypy
        args: [--strict]
        additional_dependencies: [pandas-stubs]
```

Pin the versions. An estimator default that changes between library releases changes your results
with no commit of your own.

### Typing that carries meaning

Annotating everything as a dataframe or series satisfies the type checker and prevents nothing.
Distinguish the quantities that must not be interchanged.

```python
from typing import NewType
import pandas as pd

Prices = NewType("Prices", pd.Series)           # adjusted levels, indexed by date
SimpleReturns = NewType("SimpleReturns", pd.Series)
ExcessReturns = NewType("ExcessReturns", pd.Series)
Weights = NewType("Weights", pd.Series)         # by security, sums to the gross target


def to_simple_returns(prices: Prices) -> SimpleReturns: ...


def sharpe(excess: ExcessReturns, periods_per_year: int) -> float:
    # Annualised Sharpe on arithmetic excess returns, ddof=1.
    # Requires excess returns: passing raw returns overstates the ratio by the risk-free
    # rate divided by the volatility.
    ...
```

The type checker now rejects a call passing raw returns where excess returns are required. That is
a real defect class caught at edit time rather than in a report.

Where a distinct type is too heavy, put the unit in the name: `ann_vol_pct`, `daily_excess_ret`,
`cost_bps_round_trip`, `mv_usd`. A variable called `ret` is an unanswered question.

### What the tests must cover

A statistics module needs four kinds of test, and the first is the one most often skipped.

1. **Known-answer tests.** Hand-computed values for small inputs, and closed-form values where one
   exists. The Sharpe standard error under iid normality is the square root of `(1 + SR²/2)/T`;
   assert against the formula, not against whatever the code currently returns.
2. **Property tests.** Invariants that hold for any input. Sharpe is invariant to leverage scaling
   of excess returns. Portfolio return equals the weighted sum of constituent returns. Attribution
   effects sum to the active return. Cumulative return is a product, never a sum. A library such
   as `hypothesis` generates the inputs; you supply the invariant.
3. **Boundary and failure tests.** Zero variance, a single observation, all missing, a series
   shorter than the minimum observation gate, a weight vector that does not sum to its target.
   Each must raise or return null, and the test must assert which. A suite that only covers the
   happy path leaves the failure behaviour undefined, and undefined failure behaviour is where
   fabricated numbers come from.
4. **Regression tests on a fixed fixture.** A small committed dataset with its expected output
   committed alongside. Any change to a reported number then appears as a test diff and has to be
   explained in the pull request rather than discovered in a meeting.

Never write a test by running the code and pasting its output into the assertion. That records the
current behaviour, defects included, and makes them permanent.

### The pull-request gate

Nothing merges without all of these green, and a reviewer should decline to read the diff until
they are.

```
ruff check . && ruff format --check .
mypy --strict src/
pytest --cov=src --cov-report=term-missing --cov-fail-under=80
pytest tests/test_golden.py -v        # known-answer and noise tests, named explicitly
```

If a reported number changed, the pull request states which, by how much, and why. A silent change
to a headline statistic is the failure this entire gate exists to prevent.

## Project layout

```
project/
  config.py           one object holding every convention and parameter. Nothing else defines one.
  data/
    raw/              immutable pulls, never edited, named with source and snapshot date
    cache/            derived parquet, each with a manifest recording inputs and a hash
  src/
    load.py           data acquisition and caching only. No statistics.
    clean.py          hygiene and validation. Returns clean data or raises.
    signal.py         signal construction. Receives no forward returns.
    portfolio.py      weights from signal. Receives no returns.
    performance.py    statistics from weights and returns. Receives no signal.
    stats.py          estimators. Pure functions, no I/O, no data loading.
  tests/
    test_golden.py    known-answer tests on simulated data
    test_invariants.py
  results/            outputs, named by run, never edited by hand
  run.py              one entry point that executes the pipeline end to end
  TRIALS.md           the trial log
```

The separation between `signal.py`, `portfolio.py`, and `performance.py` is not aesthetic. It
makes look-ahead structurally difficult: the signal module cannot see forward returns because they
are not passed to it. Enforce this with function signatures, not with discipline.

## Configuration

Every convention lives in one object, and every function receives it or reads from it. No function
defines a periods-per-year, a risk-free rate, a cost assumption, a lookback, or a threshold
locally.

```python
@dataclass(frozen=True)
class Config:
    start: date
    end: date
    periods_per_year: int = 252
    return_type: str = "simple"        # simple | log
    total_return: bool = True
    risk_free: str = "SOFR"
    risk_free_daycount: str = "act/360"
    base_currency: str = "USD"
    rebalance: str = "monthly"
    drift_weights: bool = True          # buy-and-hold between rebalances
    cost_bps_round_trip: float = 15.0
    min_obs_vol: int = 20
    min_obs_corr: int = 30
    seed: int = 20250904
    data_vintage: str = "2025-09-04"
```

Frozen, so nothing mutates it mid-run. Written to the results directory with every run. Two runs
with the same config and the same data hash must produce identical output.

Duplicate constants are a reliable source of divergence: one module defaulting to 10 basis points
and another to 5 will produce two irreconcilable net returns. Grep for numeric literals in the
analysis modules; each one is a config field that has not been created yet.

## One canonical implementation per number

Every reported statistic has exactly one function that computes it, and every caller uses that
function. Duplicate implementations diverge; the divergence is usually an alignment or rebalancing
assumption rather than a formula difference, and it surfaces as two teams reporting different
tracking errors for the same portfolio.

- Mark the canonical function in its docstring and state the conventions it assumes.
- When replacing an implementation, make the old one raise rather than deleting it silently. A
  deprecated function that returns a plausible wrong number is worse than one that fails.
- Where two defensible conventions exist, expose the choice as an explicit enumerated parameter
  with a documented default, and provide a function that computes both and reports the gap. That
  gap is information, and hiding it behind a default is how two components come to disagree by a
  factor of three without anyone noticing.

## Fail loudly, never fall back silently

The most damaging pattern in analysis code is a broad exception handler that substitutes a
default.

- Do not wrap computations in `try/except` as a matter of course. If a computation cannot be
  performed correctly, raise.
- Never fall back to a hardcoded constant, a sector average, a prior value, or zero. A fabricated
  number is indistinguishable from a measured one once it reaches a report.
- Never return zero for a failed estimate. Return `None` and force the caller to handle it. Zero
  propagates into portfolio aggregates as if it were measured; `None` does not.
- Exclusions must be visible in the output, not only in a log line. If fourteen positions were
  dropped for insufficient history, the result carries that count and their weight.
- A solver or optimiser that fails must raise, not return its last iterate. Validate every
  constraint on a returned solution before reporting it.

This is the code form of the reporting rule in [analyst
conduct](analyst-conduct.md#report-failure-explicitly-in-the-first-person-with-the-cause).

## Assertions on invariants

Assert what must be true, at the point it must be true. These catch the majority of silent defects
and cost nothing.

```python
assert idx.is_monotonic_increasing and idx.is_unique
assert returns.index.equals(benchmark.index)          # before any pair statistic
assert weights.index.equals(prior_returns.index)      # alignment, not position
assert abs(weights.sum() - config.gross_target) < 1e-8
assert not returns.isna().any().any(), returns.isna().sum()[lambda s: s > 0]
assert signal.index.max() < forward_returns.index.min()   # the lag contract
assert returns.abs().max() < 1.0, "check for unadjusted corporate action"
assert np.linalg.eigvalsh(cov).min() > 0, "covariance is not positive definite"
```

The alignment assertion and the lag assertion together prevent two of the three most common
catastrophic defects in this domain.

## The golden test

Simulate data with a known answer, run it through the entire pipeline, and confirm recovery inside
the simulation's own error bars.

```python
def test_recovers_known_sharpe():
    rng = np.random.default_rng(0)
    target_sr = 1.0
    daily_mu = target_sr / np.sqrt(252) * 0.01
    r = pd.Series(rng.normal(daily_mu, 0.01, 10_000), index=trading_days(10_000))
    est = pipeline.performance(r, config_zero_rf)
    se = np.sqrt(252 / 10_000)          # ~0.16
    assert abs(est.sharpe - target_sr) < 3 * se
```

Extend it to the parts that matter for the specific analysis:

- A signal with a **known** relationship to forward returns. The pipeline must recover its
  information coefficient.
- A signal with **no** relationship. The pipeline must return a Sharpe indistinguishable from
  zero. A pipeline that produces a positive Sharpe on pure noise has look-ahead, and this test
  finds it immediately.
- A portfolio with known weights and known constituent returns. The portfolio return must match
  the hand-computed value exactly.
- A series with an injected split, an injected gap, and an injected outlier. The cleaning must
  catch each and say so.

The noise test is the single highest-value test in this domain. Run it before running the real
data, and report that it was run.

## Determinism and reproducibility

- One seed in the config, passed explicitly to a `numpy.random.Generator`. Do not use the legacy
  global `numpy.random.seed`; it makes the state dependent on execution order.
- Where a per-entity seed is needed so that two scenarios differ by construction rather than by
  Monte Carlo noise, derive it deterministically from the entity identifier and the base seed. Do
  not use Python's built-in `hash` on a string for this: it is salted per process and the result
  is not reproducible across runs.
- Cache the raw data pull to a file, hash it, record the hash in the results. Analysis reads the
  cache. A run that hits a live API is not reproducible.
- Record the package versions. Estimator defaults change between library releases.
- Two runs of the same commit against the same data hash must produce byte-identical output. Test
  it.

## Notebooks

Notebooks are acceptable for exploration and unacceptable as the source of a reported number.

- Notebook state does not correspond to notebook text. Cells run out of order, variables survive
  edits, and a result can depend on a cell that has since been deleted.
- If a notebook produced the number, restart the kernel and run it top to bottom before the number
  is used. If it does not reproduce, the number does not exist.
- Move anything reported into a script with a single entry point. The notebook may call the
  script.

## Reviewing code you did not write

For an analysis someone else, or a model, produced. In order, because each step can end the
review.

1. **Find the lag.** Locate where the signal meets the forward return and verify by hand on three
   dated observations that no future information enters the signal.
2. **Find the conventions.** Periods per year, return type, risk-free, cost model. If they are
   scattered as literals rather than centralised, expect divergence between components.
3. **Find the exception handlers.** Every broad `except` is a place where a failure may have
   become a number. Every default value is a candidate fabrication.
4. **Look for uniformity in the output.** Identical values across unrelated securities, values
   pinned at a floor or cap, and precision beyond what the inputs support all indicate placeholder
   implementations. Reverse-engineer a suspicious value back to the constant that produced it.
5. **Check the alignment.** Any statistic on two series must align on dates, not positions.
6. **Run the noise test.** Replace the signal with random noise and confirm the reported edge
   disappears.
7. **Check `ddof`.** `numpy.std` defaults to `ddof=0`. A covariance matrix must use the same
   convention on its diagonal and off-diagonals.
8. **Grep for `shift(-`, `KFold`, `train_test_split`, `shuffle=True`, `center=True`, `.fillna(0)`,
   `.dropna()` after a merge, and `bfill`.** Each has a legitimate use and each is a common defect
   site.

## What to hand back with a result

- The script, the config used, and the data hash.
- The test output, including the golden test and the noise test.
- The result files, unedited.
- The trial log.
- A one-page summary in the reporting format from [performance
  statistics](performance-statistics.md#reporting-block).

A number handed over without the config and the data hash cannot be reproduced and should be
treated as provisional.
