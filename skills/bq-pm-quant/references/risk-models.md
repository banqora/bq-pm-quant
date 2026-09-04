# Risk models

Load when estimating covariance, beta, tracking error, or tail risk, and before any optimiser
runs.

## Covariance: the estimation problem

With `N` securities and `T` observations, the sample covariance matrix has `N(N+1)/2` parameters
estimated from `NT` numbers. It is singular when `N > T` and badly conditioned well before that.
Inverting it, which every mean-variance optimiser does, amplifies the estimation error in the
smallest eigenvalues, which are precisely the least reliably estimated directions.

The consequence has a name: **error maximisation** (Michaud, 1989). An unconstrained optimiser
loads on the eigenvector with the smallest estimated variance, which is usually an artefact.

Check before inverting, and report the numbers:

- `N` and `T`, and the ratio `N/T`. Above roughly 0.1 the sample matrix needs treatment; above 1
  it is singular.
- Condition number, the ratio of largest to smallest eigenvalue. Report it before and after any
  treatment.
- Smallest eigenvalue. If negative, the matrix is not positive semi-definite and something
  upstream is wrong.

Do not decide a matrix "looks unstable". Compute the condition number and act on it.

## Shrinkage

- **Ledoit-Wolf linear shrinkage**: convex combination of the sample covariance and a structured
  target, with an analytically optimal intensity. Targets in common use: the identity scaled by
  average variance (Ledoit and Wolf, 2004), and the constant-correlation matrix (Ledoit and Wolf,
  2003). The constant-correlation target is usually better for equities because it preserves the
  variance estimates and shrinks only the correlation structure.
- **Oracle Approximating Shrinkage** is a related estimator with a different intensity rule, often
  slightly better under normality.
- **Nonlinear shrinkage** (Ledoit and Wolf, 2017 onward) shrinks each eigenvalue individually
  rather than applying one intensity. Better when `N/T` is large. Heavier to compute.
- **Random matrix theory denoising**: replace eigenvalues that fall inside the Marchenko-Pastur
  bulk, which are indistinguishable from noise, with their average, keeping the significant ones.
  Then project to the nearest positive semi-definite matrix.
- **Factor-model covariance**: `Σ = B Ω Bᵀ + D` with `B` the exposures, `Ω` the factor covariance,
  and `D` diagonal specific variance. Reduces the parameter count from `N²/2` to `NK + K²/2 + N`.
  The standard institutional approach and the right default when `N` is in the hundreds.
- **Constraints as implicit shrinkage** (Jagannathan and Ma, 2003): a no-short constraint on a
  minimum-variance problem is mathematically equivalent to shrinking the covariance matrix. A
  constrained optimiser on a sample matrix is therefore not as naive as it looks, but the implied
  shrinkage is uncontrolled.

Always report the shrinkage intensity selected and the condition number before and after. An
intensity near 1 means the sample matrix contributed almost nothing, which is information about
the sample, not a failure.

## Missing data in a covariance matrix

Two approaches, with different failure modes.

- **Complete-case**: drop every date on which any security is missing. Produces a valid positive
  semi-definite matrix on a sample that is the intersection of all histories, which is typically
  far shorter than intended and biased toward long-lived names.
- **Pairwise-complete**: estimate each entry on the dates where that pair is jointly available.
  Uses more data but the result **need not be positive semi-definite**, and it will not warn you.

If using pairwise-complete: check the eigenvalues, floor the negative ones at a small positive
value, and reconstruct, or project to the nearest positive semi-definite matrix. Report that the
repair was applied.

Use the same degrees-of-freedom convention on the diagonal and off-diagonal. A matrix whose
diagonal uses `ddof=0` while its off-diagonals use `ddof=1` is internally inconsistent and the
inconsistency grows as the sample shortens.

## Time variation

- **EWMA**: weight recent observations more heavily with decay `λ`, equivalently a half-life. The
  RiskMetrics convention is `λ = 0.94` daily, but the choice should follow the horizon of the
  decision, not convention. Report the half-life in days, which is more interpretable than `λ`.
- **GARCH**: models volatility clustering explicitly. Use a Student-t innovation for equity
  returns; the normal specification understates tails. Report the estimated degrees of freedom
  rather than hardcoding it, and check convergence.
- **DCC** for time-varying correlation. Heavy to estimate for large `N` and usually blended with a
  static shrunk estimate.
- A shorter estimation window is more responsive and noisier. There is no universally correct
  length; state the window, and show the statistic's sensitivity to it rather than defending one
  choice.

## Beta

`β = Cov(r_p, r_b) / Var(r_b)`, with the **same degrees-of-freedom convention in numerator and
denominator**. This is a common and silent error.

- Align the two series on their dates. Drop pairs where either is missing, before computing the
  covariance, not after.
- Set a minimum observation count and return null below it. A beta of zero and an unknown beta are
  different facts, and zero will propagate into a portfolio aggregate as if measured.
- Estimate by covariance ratio and by regression and confirm they agree to numerical tolerance.
  They are algebraically identical, so a disagreement means an alignment or degrees-of-freedom
  defect. The regression form also gives you the residual standard error and the alpha estimate;
  do not discard them.
- **Window and frequency are conventions, not truths.** Five years of daily, two years of weekly,
  and sixty months of monthly give different answers for the same security. State which. A common
  vendor convention is 104 weeks of Wednesday-to-Wednesday returns.
- **Blume adjustment**: `β_adj = (2/3)·β + (1/3)·1.0`, a mean-reversion correction toward one.
  **Vasicek adjustment**: shrink toward the cross-sectional mean weighted by the precision of each
  estimate, which is the better-founded version. Both are appropriate for forward-looking use;
  neither for measuring what happened.
- **Dimson correction** for stale prices: regress on contemporaneous and lagged market returns and
  sum the coefficients. Necessary for illiquid names, where the naive beta is biased toward zero.
- If your beta disagrees with a client's or a vendor's, the causes in order of likelihood are:
  different benchmark, different adjustment convention on the underlying prices, different window,
  different frequency, and only then a defect. Eliminate them in that order and report which one
  accounted for the gap.

## Tracking error

- **Ex-post**: the annualised standard deviation of realised active returns, `sd(r_p - r_b) ×
  sqrt(k)` with `ddof=1`. It measures what happened.
- **Ex-ante**: `sqrt( (w - w_b)ᵀ Σ (w - w_b) × k )` from a risk model. It forecasts.
- These are different quantities and routinely conflated. Label every tracking error as one or the
  other. A large gap between them is informative: it means the risk model's covariance does not
  describe the realised period, which is a finding about the model.
- The benchmark must be present in the covariance estimation as an explicit column or as a weight
  vector over the same securities. A benchmark that silently became an empty column produces a
  "tracking error" that is just portfolio volatility.
- Have exactly one implementation. Multiple tracking-error functions in one codebase reliably
  diverge, and the divergence is usually a rebalancing or alignment assumption rather than an
  estimator difference. See [backtesting](backtesting.md#rebalancing).

## Value at risk and expected shortfall

- **Historical simulation**: the empirical quantile of the portfolio's return distribution. No
  distributional assumption, limited by the tail observations available. At 99% on 250
  observations the estimate rests on two or three points.
- **Parametric**: closed form from mean and volatility. Understates the tail for equity returns
  under a normal assumption. A Student-t with estimated degrees of freedom is better; estimate the
  degrees of freedom, do not fix them.
- **Monte Carlo**: flexible, and only as good as the simulated process.
- **Expected shortfall** (conditional VaR) is the mean loss beyond the VaR threshold. It is
  coherent, it uses tail shape rather than one quantile, and it is the better default. Never
  approximate it as a fixed multiple of VaR; the multiple depends on the tail and that dependence
  is the reason to use expected shortfall in the first place.
- **State the horizon and the scaling.** Scaling a one-day figure by `sqrt(h)` assumes
  independence and normality, and neither holds in the tail. Scaling by trading days and by
  calendar days gives different answers; declare which and be consistent. Report the one-day
  figure alongside any scaled one.
- **State the confidence level** on every figure. A system carrying 90%, 95%, and 96.5%
  conventions in different components will produce numbers that cannot be compared.
- Backtest the VaR: count exceedances against the expected count and test with Kupiec's
  unconditional coverage test and Christoffersen's independence test. An unbacktested VaR is an
  assertion.

## Drawdown-based risk

- Maximum drawdown's sampling behaviour, and why it is not comparable across track records of
  different length, is in [performance
  statistics](performance-statistics.md#drawdown). Everything below is what a risk model adds.
- **Rolling or economic drawdown**, measured against a rolling peak over a fixed lookback rather
  than the all-time peak, is more stable and more decision-relevant for a live book. State the
  lookback.
- Forward drawdown forecasts should come from a block bootstrap or a simulated path distribution
  and be reported as a quantile with the quantile stated, never as a point estimate.

## Optimiser sensitivity

Whatever the optimiser, report these or the weights are not interpretable.

- The condition number of the covariance used, and the shrinkage applied.
- Sensitivity of the weights to the expected-return input. Mean-variance weights are far more
  sensitive to means than to covariances; a small change in a return forecast moves weights a lot.
- Which constraints are binding at the solution. A solution sitting on its constraints is
  reporting the constraints, not the optimisation.
- Whether the solver converged. An optimiser that returns a solution after failing to satisfy its
  constraints is more dangerous than one that raises. Validate every constraint on the returned
  weights before reporting them, and if any is violated, report the failure rather than the
  weights.
- Effective number of positions `1 / Σ w²` alongside the nominal count.
- Turnover from the current portfolio, since that is what the trade costs.
