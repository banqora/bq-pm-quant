# Inference

Load when a result is about to be called significant, when a p-value or t-statistic is produced,
or when comparing two strategies, two managers, or two periods.

## What test for what question

| Question | Default | Why not the obvious alternative |
|---|---|---|
| Is mean return different from zero? | t-test with Newey-West HAC standard errors | Plain OLS/iid SE assumes no serial correlation and no heteroskedasticity; both fail on returns |
| Is alpha different from zero? | Time-series regression on factor returns with HAC SEs | Residuals are autocorrelated and heteroskedastic; naive SEs overstate `t` |
| Is Sharpe A different from Sharpe B, same period? | Ledoit-Wolf (2008) test for correlated, non-iid Sharpe difference | An independent two-sample test ignores the correlation between the two series and is badly sized |
| Is this the best of N strategies genuinely good? | Deflated Sharpe, or White Reality Check / Hansen SPA | Any single-hypothesis test applied to a maximum is invalid |
| Does the distribution differ from normal? | Jarque-Bera or Anderson-Darling, plus a QQ plot | A single moment test misses the tail behaviour that matters |
| Is there serial dependence? | Ljung-Box on returns and on squared returns | Returns can be uncorrelated while volatility is strongly dependent |
| Is a cross-sectional coefficient significant? | Fama-MacBeth with Newey-West on the coefficient series | Pooled OLS ignores cross-sectional correlation and produces vastly overstated `t` |
| Small sample, unknown distribution, path-dependent statistic? | Stationary bootstrap | Analytic SEs do not exist for drawdown, Calmar, or a full backtest path |

## The t-test on returns, done properly

The null is `E[r] = 0` on excess returns. The complications, in order of practical importance:

1. **Serial correlation.** Use Newey-West HAC standard errors. Automatic lag selection `L =
   floor(4·(T/100)^(2/9))`; Andrews (1991) data-dependent selection is defensible. Report the lag
   used. On daily equity strategy returns the correction is often small; on monthly fund returns,
   carry, and anything with smoothed marks it is large.
2. **Heteroskedasticity.** Volatility clustering is universal. HAC handles it jointly with the
   autocorrelation.
3. **Fat tails.** The t-distribution reference is asymptotically fine, but in samples under
   roughly 100 observations with excess kurtosis above 3, the bootstrap is better calibrated.
4. **One-sided versus two-sided.** A one-sided test at the same nominal level is more powerful and
   is defensible for "does this make money", but only if declared before seeing the sign.
   Declaring it after is a doubling of the effective significance level. Default to two-sided
   unless the direction was pre-registered.

Relationship to Sharpe: under iid, `t ≈ SR_period × sqrt(T)`, so a t-statistic and a Sharpe carry
the same information at a fixed sample size. This is why the t-statistic is the better headline —
it is annualisation-invariant and directly comparable across frequencies.

## Power

Underpowered tests are the norm in this field and are rarely acknowledged.

- To detect a true annualised Sharpe of 0.5 at 5% two-sided with 80% power requires roughly
  `years ≈ (1.96 + 0.84)² / SR_ann² = (2.80/0.5)² ≈ 31` years of data, which is `31 × k`
  observations at the series' own frequency. State this when a manager asks whether a two-year
  track record proves anything.
- Rule of thumb: years needed `≈ 7.8 / SR_ann²` for 80% power at 5% two-sided.
- A non-significant result on a short sample is not evidence of no edge. Report the effect size,
  the interval, and the smallest effect the sample could have detected.
- Report the minimum detectable effect alongside a null result. Inverting the same rule, on `T`
  observations at `k` per year the minimum detectable annualised Sharpe is `sqrt(7.84 × k / T)`.
  It converts an uninformative "not significant" into a bound.

## Bootstrap

For path-dependent statistics, small samples, non-normal returns, and any statistic without a
closed form standard error.

- **Stationary bootstrap** (Politis and Romano, 1994) is the default for return series. It
  resamples blocks of geometrically distributed random length, preserving serial dependence while
  keeping the resampled series stationary. Choose the expected block length by the Politis and
  White (2004) automatic rule; do not pick it by eye.
- **Circular block bootstrap** is an acceptable alternative. Plain iid bootstrap destroys the
  serial dependence and gives intervals that are too narrow; use it only on series shown to be
  independent.
- **B = 1000** replications for a confidence interval, **B ≥ 10000** for a tail p-value. Record
  the seed.
- For cross-sectional data, resample entities, not observations, when observations within an
  entity are correlated.
- Bootstrap the whole pipeline, not the final statistic, when the pipeline includes estimation. A
  bootstrap of Sharpe that reuses fixed estimated weights understates uncertainty.
- Report the interval, not just the p-value: BCa or percentile, stated.

## Multiple testing

The central problem in quantitative portfolio research. Twenty independent signals tested at 5%
will produce one significant result under a complete null.

- **Record the trial count.** Every specification examined counts: parameter values, universes,
  date ranges, weighting schemes, and the ones abandoned after one look. This is the single most
  important input and the one most often unavailable. See [out of
  sample](out-of-sample.md#the-trial-log).
- **Family-wise error rate**, when a single false discovery is costly:
  - Bonferroni: reject if `p < α/N`. Correct but very conservative under dependence.
  - Holm-Bonferroni: uniformly more powerful than Bonferroni, same guarantee. Prefer it.
- **False discovery rate**, when a controlled proportion of false positives is acceptable, which
  is the usual case in signal research:
  - Benjamini-Hochberg at `q = 0.1` or `0.05`. The sensible default for screening many signals.
  - Benjamini-Yekutieli under arbitrary dependence: more conservative, use when signals are
    strongly
    and unknown-sign correlated.
- **Harvey, Liu and Zhu (2016)** on the factor literature: accounting for the breadth of the
  search, a newly proposed factor needs a t-statistic near **3.0**, not 2.0, to be credible. Use
  3.0 as the working hurdle for any newly discovered effect, and higher for a wide automated
  search.
- **Correlated tests reduce the effective number of independent trials.** `N` distinct parameter
  settings of one idea is not `N` independent tests. Estimate the effective count from the
  correlation of the strategies' return series rather than counting configurations.
- Applying a correction after the fact to a search whose size you are guessing is better than no
  correction, but say that the count is an estimate.

## Comparing two strategies

- Do not compare two Sharpe ratios by checking whether each is individually significant. Test the
  **difference**, using an estimator that accounts for the correlation between the two return
  series (Ledoit and Wolf, 2008, with a studentised bootstrap).
- Two highly correlated strategies can have very different point Sharpes with an insignificant
  difference. This is the usual outcome when a manager asks which of two variants is better.
- For nested specifications, the added variant must beat the base by more than the noise
  introduced by having selected it.
- For comparing many strategies to a benchmark, use the Model Confidence Set (Hansen, Lunde and
  Nason) rather than pairwise tests.

## Regression practice

- **Alpha and beta**: regress excess portfolio return on excess factor returns. Report HAC SEs.
  Report `R²`, the residual volatility, and `n`.
- **Fama-MacBeth**: run the cross-sectional regression each period, then test the time series of
  coefficients with Newey-West SEs. Do not pool.
- **Errors-in-variables**: betas estimated in a first stage and used as regressors in a second
  stage bias the second-stage coefficient toward zero. Use portfolios rather than individual
  securities, or a Shanken correction.
- **Overlapping observations** (e.g. 12-month forward returns sampled monthly) induce strong
  autocorrelation by construction. Newey-West with lag at least the overlap length, or use
  non-overlapping observations and accept the smaller `n`. Naive SEs here overstate `t` by roughly
  the square root of the overlap.
- **Look at the residuals.** Autocorrelated or trending residuals mean the specification is wrong,
  not that the SEs need patching.

## Reporting a test

State, in order: the null, the estimator, the standard-error method and its parameters, the
sample, the statistic, the p-value or interval, and the multiplicity correction applied with the
trial count.

```
H0: mean daily excess return = 0
estimate 3.62bp | Newey-West SE 1.21bp (L=6) | t = 2.99 | n = 2516 | two-sided p = 0.0028
trials in family: 18 | Benjamini-Hochberg q=0.10 threshold p = 0.0056 | survives
minimum detectable ann. Sharpe at 80% power on this sample: 0.89
```
