# Data integrity

Load before computing any statistic on data you did not construct, and whenever a number is
surprising. Most surprising numbers in portfolio analysis are data defects, not discoveries.

The failures below are ordered by how often they silently change a headline result. Each has a
diagnostic that either confirms or eliminates it. Run the diagnostic; do not reason about
plausibility.

## Survivorship

The universe as it exists today is not the universe as it existed then. A backtest on current
index constituents, current holdings, or a current ETF's holdings measures the selection, not the
strategy.

- Reconstruct membership as of each date from a point-in-time constituent history. If you do not
  have one, say so and state that the result is biased upward by an unquantified amount.
- Include names that delisted, were acquired, or went to zero, with their terminal return.
  Dropping them is the bias. Standard delisting-return proxies where the actual return is
  unavailable: approximately -30% for NYSE and AMEX and -55% for NASDAQ performance-related
  delistings (Shumway 1997; Shumway and Warther 1999).
- Merger and acquisition terminations are not the same as failure delistings and should not take
  the same proxy.
- Diagnostic: count the securities in the universe at the start of the window and at the end. If
  the set is nested, the data is survivorship-filtered.

## Look-ahead in timestamps

Look-ahead almost never appears as an obvious future reference in code. It appears as a field
dated to when the fact became true rather than when it became knowable.

| Field | Dated to | Should be dated to | Typical lag |
|---|---|---|---|
| Fundamentals | Fiscal period end | Filing or first availability date | 30-90 days |
| Analyst estimates | Consensus as revised | As published on that date | Varies |
| Index membership | Effective date | Announcement, if traded on announcement | Days |
| Economic releases | Reference period | Release date, first print not revision | Weeks to months |
| Credit ratings | Effective | Announcement | Days |
| Split and dividend adjustment factors | Applied retroactively across the whole history | Applied as of each date | Structural |

The last row is the one most often missed. A vendor's adjusted-close series encodes today's
cumulative adjustment factors back through history. Ratios computed on it are consistent, but any
analysis that also uses a raw price, a share count, or a nominal threshold will be inconsistent.

- Diagnostic for fundamentals: pick a name with a known late filing and check whether the value is
  present in the series before the filing date.
- Diagnostic for the whole pipeline: shift every non-price input forward by one extra period. If
  the result barely changes, the lag structure is probably sound. If it collapses, the original
  was leaking.

## Restatement and vintage

Vendor histories are revised. The same query run six months apart returns different numbers for
the same historical date, without any code change.

- Record the snapshot date or vintage identifier with every stored result.
- Cache the raw pull to a file, hash it, and record the hash. Analysis reads the cache, never the
  live API. This is the only way a result is reproducible.
- A result that cannot name its data snapshot cannot be reproduced and should not be treated as
  durable.

## Corporate actions

- Total return and price return differ by the dividend stream. For broad developed equity indices
  this is roughly 150-250 basis points a year. Any alpha claim built on price returns against a
  total-return benchmark, or the reverse, is that size or larger in error.
- An unadjusted split appears as a single-day return near -50%, -66%, or +100%. It propagates into
  every downstream cumulative figure, every volatility estimate, and every correlation involving
  that name.
- Diagnostic: scan every series for single-day absolute returns above a threshold (50% is a common
  choice) and inspect each hit individually against the corporate-action record. Do not
  auto-correct. A genuine 50% move exists and deleting it is also a defect.
- Special dividends, spin-offs, rights issues, and share consolidations each break a naive price
  series differently. Check the action type before deciding the treatment.
- Diagnostic for consistency: for a name with a known split, confirm the share count and the price
  are adjusted on the same convention. A ratio computed from one adjusted and one unadjusted
  series is off by the split factor.

## Calendars, weekends, and non-trading days

- Vendor feeds return weekend rows for some venues. Left in, they add exactly-zero return
  observations, which deflate measured volatility and corrupt the square-root-of-time
  annualisation because the observation count no longer matches the assumed periods per year.
- Diagnostic: group observations by weekday and count. Any Saturday or Sunday rows in a series for
  a Monday-Friday venue are contamination.
- Half-days and early closes are real observations with compressed volatility. Keep them.
- Holidays differ by venue. A multi-market panel needs an explicit union or intersection rule; see
  [return conventions](return-conventions.md#calendars-and-alignment).

## Forward-filling and stale prices

Forward-filling a price across a gap creates a run of exactly-zero returns that are not
observations.

Consequences, all in the same direction: measured volatility falls, measured beta falls, measured
Sharpe rises, measured VaR narrows, and the series acquires positive autocorrelation. This is the
standard signature of an illiquid or thinly-traded holding and it makes a portfolio look better
than it is on every risk statistic simultaneously.

- Diagnostic: count exact zeros and count runs of identical consecutive prices, per security. A
  liquid large-cap has very few exact-zero daily returns; a run of five identical closes is a
  stale-price flag, not a quiet market.
- Do not silently forward-fill. Decide per security whether to fill, to drop, or to exclude the
  name, and record which and why.
- For beta on stale-priced assets, use the Dimson correction: sum the coefficients on
  contemporaneous and lagged market returns.
- Never synthesise price history for a security with insufficient data and then compute statistics
  on the combined series without marking which observations are synthetic. If a model-generated
  backfill is used, propagate a flag and exclude those observations from any reported statistic,
  or report the statistic twice.

## Missing data, zeros, and NaN

Four distinct facts that are routinely collapsed into one: not traded, no price reported, a
genuine zero return, and unknown.

- Zero is not missing. Missing is not zero. Filling NaN with zero converts an unknown into a
  strong claim of no movement and biases volatility down.
- NaN propagates silently through products and logarithms. A single NaN return entering a
  cumulative product makes the entire downstream path NaN; a cumulative return at or below -100%
  makes its logarithm undefined. Strip and count NaN before resampling or compounding, log the
  count, and fail if the count exceeds a declared threshold rather than proceeding on the
  remainder.
- Diagnostic: report null counts and the first and last valid date per security at every stage of
  the pipeline. The stage where the count changes is where the defect is.
- Dropping rows with any missing value across a wide panel silently reduces the sample to the
  intersection of all securities' histories, which is usually far shorter than intended and biased
  toward long-lived names.
- Pairwise-complete handling for a covariance matrix produces a matrix that need not be positive
  semi-definite. Check the eigenvalues and repair explicitly. See [risk
  models](risk-models.md#missing-data-in-a-covariance-matrix).

## Series alignment

Two return series of unequal length must be aligned on their dates, not on their positions.

- Aligning by position from the start pairs one series' 2019 observations against the other's 2022
  observations and produces a beta, correlation, or tracking error that is pure noise. It will not
  error and it will look plausible.
- Align on the date index. If truncating to a common length is unavoidable, truncate from the end
  so the most recent overlapping period is retained, and apply that convention everywhere. Mixing
  start-alignment in one statistic and end-alignment in another produces two internally consistent
  numbers that do not reconcile with each other.
- Diagnostic: assert that the two aligned series share an identical date index before computing
  anything on the pair. This single assertion prevents an entire class of failure.
- Confirm the benchmark is actually present in the aligned frame used for an ex-ante calculation.
  A benchmark column that silently became empty produces a tracking error against zero, which is
  just portfolio volatility wearing a different label.

## Currency and units

- Minor-unit quotations are a live trap. London-listed names quote in pence, not pounds; the same
  applies to South African cents, Israeli agorot, and several other venues. A missed conversion is
  a factor-of-100 error that survives every ratio and appears only in levels.
- FX series shorter than the price series must never be gap-filled with a rate of 1.0. Carry the
  last prior rate forward, then the earliest later rate, and fail if neither exists. A silent 1.0
  makes a foreign holding look like a domestic one.
- Apply FX at a snapshot time consistent with the equity close of the venue in question.
- Assert that percentage-valued and decimal-valued series are never mixed. Ratios are
  scale-invariant and will not reveal the error; levels will, much later.

## Fabricated and placeholder values

Placeholder implementations that return a plausible constant are the most dangerous defect in this
list, because the output looks like data.

Diagnostic, and it is fast: **look for suspicious uniformity.** Identical metrics across unrelated
securities, a value repeating to more precision than the input warrants, or a figure that is
always exactly at a floor or cap. Then reverse-engineer the number back to the constant that
produced it. If a portfolio shows every position with the same liquidation time, the same
price-to-earnings ratio within a sector, or a market cap repeating across names, the function is
returning a default.

Related patterns to grep for in any inherited analysis code: a hardcoded correlation, a volatility
derived as a fixed multiple of another volatility, an expected shortfall computed as a fixed
multiple of value-at-risk, and any comment containing "placeholder", "mock", "TODO", or
"approximate".

## Minimum observation gates

Every estimator has a sample size below which it should refuse rather than return.

Working defaults, to be stated and adjusted rather than assumed: volatility and beta at 20
observations, correlation at 30, historical value-at-risk at 50, a covariance matrix at 60 per
pair, and any annualised ratio at enough observations for its standard error to be reportable.

Below the gate, return a null and let the caller handle it. Never return zero: a beta of zero and
an unknown beta are different facts, and a zero will propagate into a portfolio aggregate as if it
were measured.

## The integrity pass

Run before any statistic, on every new dataset, and record the results next to the analysis.

```
per security:  n obs, first date, last date, n null, n exact-zero returns,
               longest identical-price run, max |1-day return|, currency, minor-unit flag
per panel:     date index is unique and monotonic, weekday distribution, venue calendar match,
               universe size at start vs end, names present at start but absent at end
per pair:      identical date index asserted before any covariance or beta
provenance:    source, snapshot date, file hash, adjustment convention, total vs price return
```
