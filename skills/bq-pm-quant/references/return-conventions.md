# Return conventions

Load before computing any statistic on a return series, and whenever two analyses of the same
portfolio disagree by a small persistent amount. Most such disagreements are convention, not
error.

## Declare these before computing anything

Put them in one configuration object that every function reads. Nothing downstream may hardcode a
frequency, a rate, or a calendar.

| Field | Typical values | Consequence of getting it wrong |
|---|---|---|
| `return_type` | simple (arithmetic) or log | Log returns do not aggregate across assets; simple returns do not aggregate across time by summation |
| `total_or_price` | total return or price return | Dividends on a broad equity index are roughly 150-250bp a year; omitting them destroys any alpha claim |
| `periods_per_year` | 252, 12, 52, 4, 260, 365 | Scales every annualised figure; must match the series' actual sampling, not its nominal frequency |
| `risk_free` | instrument, tenor, day count | Sets the excess-return level for Sharpe and alpha |
| `base_currency` | portfolio's reporting currency | Determines whether FX moves are return or noise |
| `hedged` | unhedged, fully hedged, hedge ratio | Changes both level and volatility of a foreign-asset series |
| `calendar` | exchange calendar and holiday source | Determines n, and therefore every standard error |
| `gross_or_net` | of fees, of costs, of financing | The largest single source of backtest-to-live decay |
| `window` | inclusive start and end dates | Reproducibility |
| `vintage` | data snapshot date | Vendor histories restate |

## Simple versus log returns

- Simple return `r_t = P_t/P_{t-1} - 1`. Aggregates across assets: a portfolio's simple return is
  the weighted sum of constituent simple returns. Does not sum across time.
- Log return `l_t = ln(P_t/P_{t-1})`. Sums across time: cumulative log return is the sum. Does not
  aggregate across assets; the log return of a portfolio is not the weighted sum of log returns.
- Use simple returns for portfolio construction, attribution, and anything cross-sectional. Use
  log returns for time aggregation, volatility scaling, and distributional work.
- Never mix within one statistic. The difference is second order per period and first order over
  years: `l = ln(1+r) ≈ r - r²/2`.
- Sharpe on log returns is not Sharpe on simple returns. Declare which. Simple is the desk
  default.

## Arithmetic versus geometric mean

- Arithmetic mean answers "expected return next period". It is the numerator of the Sharpe ratio.
- Geometric mean (CAGR) answers "what the money actually did". `CAGR = (Π(1+r_t))^(k/T) - 1`.
- Relationship: `geometric ≈ arithmetic - σ²/2`. The gap is the volatility drag and grows with the
  square of volatility. At 30% annual volatility it is 4.5 percentage points a year.
- Report both. Using CAGR in a Sharpe numerator understates the ratio; using arithmetic mean as
  realised performance overstates the outcome.

## Annualisation

- Return: `(1 + r̄_period)^k - 1` for compounding, or `r̄_period × k` for the arithmetic
  convention. Declare which. The compounding form is standard for reported performance, the
  arithmetic form for Sharpe numerators where the denominator is also arithmetic.
- Volatility: `σ_period × sqrt(k)`. Valid only under serial independence. See [performance
  statistics](performance-statistics.md#autocorrelation-and-the-lo-adjustment) for the correction
  when it is not.
- Sharpe: `SR_period × sqrt(k)` under the same assumption.
- `k` must be the actual number of observations per year in the series, not the nominal frequency.
  A daily US equity series with an exchange calendar has about 252; one that forward-filled
  holidays to a 365-day grid has 365 observations of which many are structurally zero, which
  deflates measured volatility. Count the observations.
- A series with a gap must not be annualised as if continuous. Report the count.

## Risk-free and excess returns

- Subtract the risk-free rate **at the series' own frequency**, on the series' own dates.
- Convert an annualised quoted rate to a period rate consistently. For a rate `y` quoted act/360
  money-market simple, the period rate over `d` calendar days is `y × d/360`. For an annually
  compounded rate the period rate is `(1+y)^(1/k) - 1`. Choose one and record it; dividing an
  annual rate by 252 is an approximation that leaves a persistent small bias.
- Use the tenor that matches the rebalance horizon. Overnight rates (SOFR, ESTR, SONIA) for a
  daily series; 1M or 3M bills for monthly series if the mandate specifies.
- Excess return over a **benchmark** is a different quantity from excess return over the
  **risk-free**. Sharpe uses the latter. Information ratio uses the former. Never label both
  "excess".
- For a self-financing long-short book with no net capital deployed, the risk-free subtraction is
  ambiguous. Declare the capital base: if the reported return is already on posted margin or on a
  notional gross exposure, subtracting a full risk-free rate double-counts financing. State the
  choice.

## Currency

- Local return and base-currency return differ by the FX move and their interaction: `1 + r_base =
  (1 + r_local)(1 + r_fx)`. The cross term is not negligible over long horizons.
- Hedged returns are not local returns. A hedged position earns the local return plus the
  interest-rate differential embedded in the forward, minus hedge slippage from position drift.
- Fix the FX snapshot time to the equity close of the market in question, or to a single global
  snapshot applied consistently. A 4pm London rate against a US close introduces a spurious
  overnight component.
- Never average returns across currencies without conversion.

## Calendars and alignment

- Align on the union or the intersection of trading days, deliberately, and record which.
  Intersection loses observations and biases toward the least-traded asset. Union requires an
  explicit rule for the missing days.
- Forward-filling a price across a non-trading day creates a zero return that is not a real
  observation. It depresses estimated volatility and autocorrelation-distorts the series.
- Cross-market work with non-overlapping sessions (Asia against US) has a structural lag. Either
  align on a common timestamp using intraday data, or use weekly returns, or apply a lead-lag
  correction. Daily close-to-close across time zones understates true correlation.
- Half-days and early closes are full observations with compressed volatility. Leave them in and
  note them; removing them is a discretionary filter.
- Month-end and quarter-end have distinct return dynamics. Do not silently drop them when
  resampling.

## Resampling

- Resample by compounding within the period, never by averaging or by taking every k-th
  observation. Monthly return from daily is `Π(1+r_d) - 1` across the month.
- Resampling to lower frequency reduces the effect of microstructure noise and autocorrelation but
  cuts `n`, widening every standard error. State the trade being made.
- Resample the portfolio return, not the statistic. A monthly Sharpe computed from daily-Sharpe
  averages is meaningless.

## Weights and portfolio returns

- Portfolio simple return in a period is `Σ w_i,t-1 × r_i,t` where weights are those held at the
  start of the period, after the previous rebalance and before this period's drift.
- Weights drift within the period. Beginning-of-period weights with period returns is the standard
  approximation; it is exact only if you rebalance every period.
- Weights must sum to the declared gross or net exposure. Assert it. A long-short book has net
  weights summing to a target near zero and gross weights summing to the leverage.
- Cash is a position. If weights sum to less than one, the residual earns something; declare what.

## Common defects

- Annual risk-free divided by 252 rather than converted on the day count.
- Price return used where total return was intended, or an index level that is price return paired
  with constituent total returns.
- `numpy.std` default `ddof=0` used for a sample volatility. Use `ddof=1`.
- Percentage series and decimal series mixed, producing a factor-of-100 error that survives
  because ratios are scale-invariant while returns are not.
- `pct_change()` applied to an already-differenced series.
- Cumulative return computed as a sum of simple returns.
- Annualising a statistic computed on already-annualised inputs.
