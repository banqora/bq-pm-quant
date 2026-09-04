# Out of sample

Load whenever a result is described as out-of-sample, validated, or robust, and whenever a
specification was chosen by looking at results. Correction machinery is in
[inference](inference.md#multiple-testing); Sharpe deflation in [performance
statistics](performance-statistics.md#deflated-sharpe-ratio).

## The problem, stated exactly

A backtest is not an experiment. It is a search over specifications applied to a single
realisation of history that the searcher has already seen. The reported statistic of the surviving
specification is the maximum of a set of noisy estimates and is upward biased even under a
complete null. The size of the bias depends on how wide the search was, and the search width is
usually unrecorded.

Everything in this file is machinery for either (a) restricting the search so the bias is bounded,
or (b) estimating and subtracting the bias.

## Levels of evidence

Rank any claim by which of these it actually meets. State the level explicitly.

| Level | What it means | What it supports |
|---|---|---|
| 0. In-sample fit | Parameters chosen on the same data the statistic is computed on | Nothing about future performance |
| 1. Simple holdout | Last fraction held back, but the whole file was visible during design | Weak. The holdout is contaminated by the designer's knowledge |
| 2. Cross-validated | Purged, embargoed k-fold or combinatorial CV with the search inside each fold | Estimates generalisation across the sample; still one history |
| 3. Walk-forward | Expanding or rolling window, decisions made only on prior data, no revisions | The strongest evidence obtainable from history |
| 4. Pre-registered holdout | Protocol and specification frozen in writing before the data was seen, one evaluation | Strong, but consumed after one look |
| 5. Live, out-of-sample track | Real money or a paper book run forward from a fixed date | The only genuinely out-of-sample evidence |

Most work described as out-of-sample is level 1. Say so.

## The holdout is a single-use resource

Once a holdout has been evaluated and the result influenced any subsequent decision, it is
in-sample for everything that follows. Looking at it, deciding the strategy needs a change, and
re-evaluating is not validation.

Practical protocol:

1. Write the specification, the estimand, the success criterion, and the cost assumptions down
   before the holdout is touched. Commit the file.
2. Do all development on the training portion only.
3. Evaluate once. Record the result whatever it is.
4. If the specification changes afterward for any reason, the holdout is spent. Either accept the
   contamination and label it, or reserve a further period.

For a manager, the operationally useful version: pick a date, refuse to look past it, and put the
date in writing.

## Walk-forward

Fit on data up to `t`, apply to `[t, t+h]`, roll forward, and concatenate the out-of-sample
segments. This is the closest historical analogue to running the strategy.

Requirements that are frequently violated:

- **Expanding or rolling, declared.** Rolling windows adapt to regime change and discard
  information; expanding windows accumulate. Both are defensible; mixing them is not.
- **Refit frequency must match what the desk would actually do.** Refitting daily in a backtest
  and monthly in production is not the same strategy.
- **No parameter may be chosen by looking at the concatenated out-of-sample result.** That is the
  most common form of leakage in walk-forward work, and it converts level 3 back to level 0.
- **Costs and capacity apply in each segment.** A walk-forward that ignores them is not more
  realistic than an in-sample test that ignores them.
- **The warm-up period is not out of sample.** Report the effective out-of-sample `n`, which is
  shorter than the file.

## Cross-validation on financial data

Standard k-fold cross-validation is invalid on time series with overlapping labels or serial
dependence. Two corrections, both from López de Prado (2018):

- **Purging.** Remove from the training set every observation whose label window overlaps the test
  set's label window. If the label is a 20-day forward return, purge 20 days on each side of the
  test fold.
- **Embargo.** Additionally drop a further gap after the test fold before resuming training data,
  to break residual serial correlation. An embargo of roughly 1% of the sample is a common
  starting point; justify the choice by the autocorrelation length actually present.

**Combinatorial purged cross-validation** generates many train/test path combinations rather than
one, producing a distribution of out-of-sample results instead of a point estimate. Use it when a
distribution of outcomes is more informative than a single backtest path, which is usually.

Do not shuffle time series data. Do not use `sklearn.model_selection.KFold` or `train_test_split`
with `shuffle=True` on a return series; both leak the future into training. Use `TimeSeriesSplit`
at minimum and add purge and embargo.

## Probability of backtest overfitting

**PBO via CSCV** (Bailey, Borwein, López de Prado and Zhu, 2017): split the sample into `S`
blocks, form all combinations of half as in-sample and half as out-of-sample, select the best
specification in-sample in each combination, and record its out-of-sample rank. PBO is the
fraction of combinations in which the in-sample-best specification underperforms the median
out-of-sample.

- PBO near 0.5 means selecting on in-sample performance is no better than choosing at random.
- Requires the full matrix of specification returns, not just the winner. Keep it.
- Reports a property of the **selection procedure**, not of the winning strategy. Both are worth
  knowing.

## Data-snooping tests

When many strategies are compared against a benchmark on the same data:

- **White's Reality Check (2000)**: bootstrap the maximum performance statistic across all
  candidates under the null that none beats the benchmark. Gives a p-value for the best performer
  that accounts for the whole search.
- **Hansen's SPA (2005)**: refines the Reality Check by removing poorly-performing candidates from
  the null distribution; more powerful and generally preferred.
- **Stepwise variants** (Romano and Wolf) identify which candidates beat the benchmark, not just
  whether the best does.

All require the return series of every candidate examined, including the discarded ones. This is
the practical reason to keep the trial log.

## The trial log

Maintain a machine-readable record of every specification evaluated. Without it, no correction in
this file can be computed and no p-value can be interpreted.

Minimum fields per trial: an id, a timestamp, the full parameter set, the universe and date range,
the resulting statistic, `n`, and a path to the stored return series. Include trials abandoned
after one look, trials that errored, and trials run before the current framing of the question.

```
trial_id  ts                   spec_hash  universe  window            sharpe   n     kept
0001      2025-03-04T09:14:22  a3f9...    R1000     2010-01..2019-12   0.41   2516   n
0002      2025-03-04T09:31:08  b71c...    R1000     2010-01..2019-12   0.63   2516   n
...
0041      2025-03-06T16:02:55  9de4...    R1000     2010-01..2019-12   1.12   2516   y
```

When the count is genuinely unknown — inherited work, exploratory sessions not logged — say so and
report the statistic without a p-value. An uncorrected p-value from an unmeasured search is worse
than no p-value, because it will be read as if it meant something.

## Leakage sources to check explicitly

Each of these has produced a spectacular and false backtest many times.

- Features computed on the full sample: a z-score, a rank, a PCA, a scaler, or a winsorisation
  fitted on all data then applied within folds. Fit inside the training window only.
- Target or label constructed with information overlapping the feature window.
- Universe or index membership as of today rather than as of each date.
- Fundamentals timestamped to fiscal period end rather than to filing or availability date.
- Restated financials, restated index levels, restated economic releases.
- Prices adjusted with split and dividend factors known only later. The adjustment itself is
  forward-looking unless applied as of each date.
- Delisted and acquired names dropped rather than carried with their terminal return.
- A rebalance executed at a price observed at or after the signal's own timestamp.
- Any `.shift(-1)`, any negative lag, any `.rolling(...).mean()` centred rather than trailing.
- A stop-loss or filter whose threshold was chosen after seeing which trades it would have
  avoided.

## What a backtest cannot establish

State these when the manager is deciding on the strength of a backtest.

- That the strategy will work. A backtest bounds a hypothesis; it does not confirm one.
- Capacity. Fill assumptions in a backtest are counterfactual, and the strategy's own trading
  would have moved the prices it traded against.
- Behaviour in a regime absent from the sample.
- The drawdown a manager would actually have tolerated. The backtest never redeemed.
- That the data used was available at the time in the form used.
