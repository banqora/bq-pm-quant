# Performance statistics

Load when computing or reporting any ratio, drawdown, or summary statistic on a return series.
Conventions come from [return conventions](return-conventions.md); significance from
[inference](inference.md); search correction from [out of sample](out-of-sample.md).

## The rule that governs this file

Every ratio reported here is an estimate from a finite sample. Report it with `n` and a standard
error. A Sharpe ratio without a standard error is the most common presentation error in portfolio
analysis and it makes the number uninterpretable.

Order-of-magnitude anchor, iid case: `SE(SR_ann) ≈ sqrt(k/T) × sqrt(1 + SR_period²/2)`, which for
a modest Sharpe is close to `sqrt(k/T)`. Three years of daily data gives `SE ≈ sqrt(252/756) ≈
0.58`. Ten years of monthly gives `SE ≈ sqrt(12/120) ≈ 0.32`. A reported Sharpe of 1.0 on three
years of daily data is roughly `t = 1.7`. State this rather than presenting 1.0 as an established
fact.

## Sharpe ratio

`SR = mean(r - r_f) / sd(r - r_f)`, computed at the observation frequency with `ddof = 1`, then
annualised by `sqrt(k)`.

- Numerator is the **arithmetic** mean of excess returns, not the geometric mean.
- Denominator is the standard deviation of **excess** returns, not of raw returns. The difference
  is small for equities and material for rate-sensitive books.
- `k` is the actual observations per year in the series.
- The t-statistic `t = SR / SE(SR)` is invariant to annualisation. Report it; it is the quantity a
  reader should anchor on.

### Standard error under iid normality

`Var(SR) = (1 + SR²/2) / T`, with `SR` at the observation frequency and `T` the number of
observations (Lo, 2002). Annualise `SR` and `SE` by the same `sqrt(k)`.

### Standard error under non-normality

Returns are skewed and fat-tailed; the iid-normal SE is optimistic for negatively skewed,
leptokurtic series, which describes most carry, short-volatility, and credit strategies.

`Var(SR) = (1 - γ₃·SR + ((γ₄ - 3)/4)·SR²) / T + SR²/(2T)`

commonly written `Var(SR) = (1 + SR²/2 - γ₃·SR + ((γ₄-3)/4)·SR²) / T`, with `γ₃` the sample
skewness and `γ₄` the sample kurtosis (so `γ₄ - 3` is excess kurtosis). Mertens (2002), Opdyke
(2007).

Use this whenever excess kurtosis exceeds roughly 1 or absolute skewness exceeds roughly 0.5.
State which SE was used.

### Autocorrelation and the Lo adjustment

Square-root-of-time annualisation assumes serial independence. Positive autocorrelation, which
appears in illiquid holdings, appraisal-priced assets, smoothed monthly marks, and momentum books,
inflates the naive annualised Sharpe.

`SR_ann = SR_period × q / sqrt(q + 2·Σ_{j=1}^{q-1} (q - j)·ρ_j)`

with `q = k` and `ρ_j` the lag-`j` autocorrelation of the return series (Lo, 2002). Under
independence the denominator collapses to `sqrt(q)` and the expression reduces to the naive form.

Procedure: test the first several autocorrelations (Ljung-Box). If lag-1 autocorrelation exceeds
roughly 0.1 on a series of any length, report both the naive and the Lo-adjusted figure and say
which convention the headline number uses. For monthly private or credit marks the adjustment
frequently cuts the reported Sharpe by a third.

### Deflated Sharpe ratio

When a Sharpe is the survivor of a search, the maximum of `N` sampled ratios is upward biased even
if every underlying strategy has zero true edge. The Deflated Sharpe Ratio gives the probability
the true Sharpe exceeds zero, accounting for the search (Bailey and López de Prado, 2014).

Probabilistic Sharpe ratio against a benchmark `SR*`:

`PSR(SR*) = Φ[ (SR - SR*)·sqrt(T - 1) / sqrt(1 - γ₃·SR + ((γ₄ - 1)/4)·SR²) ]`

Deflated Sharpe uses `SR* = SR₀`, the expected maximum under the null across `N` trials:

`SR₀ = sqrt(Var(SR_n)) × [ (1 - γ)·Φ⁻¹(1 - 1/N) + γ·Φ⁻¹(1 - 1/(N·e)) ]`

with `γ ≈ 0.5772` (Euler-Mascheroni) and `Var(SR_n)` the variance of the Sharpe ratios across the
`N` trials. All Sharpes at the observation frequency, not annualised.

This requires an honest `N`. If the trial count is unknown, say so and do not report a p-value.

### Minimum track record length

The number of observations needed for a Sharpe of `SR` to be significantly above `SR*` at
confidence `p`:

`MinTRL = 1 + [1 - γ₃·SR + ((γ₄ - 1)/4)·SR²] × (Φ⁻¹(p) / (SR - SR*))²`

Useful for answering "how long before this track record means anything" without argument.

### Shrinking a Sharpe ratio

Two distinct problems, two distinct treatments. Do not confuse them.

- **Selection bias from search over specifications**: deflation, as above. The correction depends
  on the number of trials and the dispersion of their results.
- **Estimation noise across a cross-section of managers, funds, or strategies**: empirical-Bayes
  or James-Stein shrinkage toward the cross-sectional mean. For unit `i` with observed `SR_i` and
  estimation variance `s_i²`, and cross-sectional dispersion `τ²` of true Sharpes: `SR_i^shrunk =
  SR̄ + (τ² / (τ² + s_i²)) × (SR_i - SR̄)`. The shrinkage weight is the reliability of unit `i`'s
  estimate. Short track records shrink almost entirely to the mean; that is the correct answer,
  not a failure of the method. Estimate `τ²` as the cross-sectional variance of observed Sharpes
  minus the mean estimation variance, floored at zero.
- Ranking a set of funds or signals on raw Sharpe is ranking largely on `1/sqrt(T_i)` and luck.
  Shrink before ranking. Report both raw and shrunk.

For a **single** strategy with no cross-section and a known trial count, deflation is the
appropriate correction and shrinkage toward a peer mean is not available.

## Information ratio

`IR = mean(r_p - r_b) / sd(r_p - r_b)`, on active returns against the mandated benchmark.

- The denominator is tracking error. Annualise both by `sqrt(k)`.
- Same standard-error machinery as Sharpe: `SE(IR) ≈ sqrt((1 + IR²/2)/T)`, non-normal and
  autocorrelation corrections apply identically.
- Distinguish the ex-post realised IR from an ex-ante forecast IR from a risk model. They are
  different objects and routinely conflated.
- Fundamental law of active management, `IR ≈ IC × sqrt(breadth) × TC`, is a design heuristic. Do
  not use it to validate a realised result; the breadth term is almost never the naive position
  count once positions are correlated.
- Active return must be against the benchmark actually held to, on the same currency and calendar,
  and net of the same cost treatment.

## Sortino, Calmar, Omega

- **Sortino** replaces the denominator with downside deviation below a threshold `τ`: `sqrt(
  (1/T)·Σ min(r_t - τ, 0)² )`. Declare `τ` (zero and the risk-free are both used and give
  different answers) and declare whether the sum divides by `T` or by the count of downside
  observations. The former is standard; the latter is not comparable across series.
- **Calmar** is annualised return over maximum drawdown, conventionally on 36 months. Maximum
  drawdown is an extreme-order statistic with enormous sampling variance and grows mechanically
  with sample length. Calmar is not comparable across track records of different length.
- **Omega**, gain-loss ratios, and similar are functions of the full distribution and are highly
  sensitive to the threshold. Report the threshold.
- None of these have well-behaved standard errors in small samples. If reported at all, report
  alongside Sharpe, never instead of it.

## Drawdown

- Maximum drawdown `MDD = max_t (1 - W_t / max_{s≤t} W_s)` on the cumulative wealth series.
- Report with: date of peak, date of trough, date of recovery or "not recovered", and duration.
  The depth alone is not informative.
- Expected maximum drawdown grows with the square root of horizon and inversely with Sharpe. A
  longer backtest will show a larger MDD with no change in the underlying process. Comparing MDD
  across differently-sized samples is invalid without adjustment.
- Drawdown on a monthly series understates drawdown on the daily series of the same portfolio.
  Declare the frequency.
- Time-under-water and the drawdown duration distribution are usually more decision-relevant to a
  manager than the single deepest point.

## Hit rate, capture, and other cross-checks

- **Hit rate** is the fraction of periods with positive return. Uninformative alone: a strategy
  can win 70% of days and lose money. Pair with the win/loss magnitude ratio, and note that hit
  rate, magnitude ratio, and mean return are algebraically linked.
- Binomial SE on a hit rate is `sqrt(p(1-p)/T)`, but returns are not independent Bernoulli draws;
  treat it as indicative.
- **Up/down capture** against a benchmark is conditional on benchmark sign and is mechanically
  driven by beta. Report beta first; capture ratios add little once beta and alpha are known.
- **Skewness and kurtosis** on returns: report them, because they drive the correct standard
  errors above and because they describe the shape of the tail the manager is carrying.
- **Autocorrelation at lags 1 to 5**: report them. High positive lag-1 autocorrelation on a fund
  return series is a mark-smoothing signature and a Sharpe overstatement.

## Turnover and cost-adjusted statistics

- Turnover per period `= 0.5 × Σ_i |w_i,t - w_i,t⁻|` where `w_i,t⁻` is the drifted weight before
  rebalancing. The 0.5 makes it one-way; declare one-way or two-way.
- Always report gross and net side by side, with the cost assumption in basis points and its basis
  (per side, round trip, on notional traded).
- The break-even cost — the cost level at which the strategy's mean return reaches zero — is a
  more useful summary than a net figure at one assumed cost. Report it.

## Reporting block

Produce this shape. Conventions once, estimates with uncertainty, method named.

```
window 2015-01-02..2024-12-31 | n=2516 daily | simple total returns, USD
excess of SOFR (act/360) | ddof=1 | k=252 | gross of costs | vintage 2025-01-15

metric                    value     se      t       method
ann. arithmetic excess    9.14%    2.41%   3.79    iid
ann. geometric (CAGR)     8.32%       -       -    compounded
ann. volatility          12.09%    0.17%      -    ddof=1
Sharpe (ann.)             0.756    0.204   3.71    Mertens (skew -0.61, exkurt 4.2)
Sharpe (ann., Lo)         0.712    0.199   3.58    rho1=0.07, q=252
max drawdown            -18.4%        -       -    2020-02-19 to 2020-03-23, rec 2020-08-11
turnover (one-way, ann.)   412%        -       -
break-even cost           22bp        -       -    round trip on notional traded
trials searched              6                     deflated Sharpe 0.61
```
