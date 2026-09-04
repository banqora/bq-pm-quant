# Attribution

Load when decomposing return or risk against a benchmark, and whenever two attributions of the
same portfolio disagree. They usually both reconcile internally and answer different questions.

## Decide what the attribution is for

Three distinct questions, three different models. Choosing the wrong one produces a correct
decomposition of something the manager did not ask about.

| Question | Model |
|---|---|
| Did the manager add value through sector or country bets, or through stock picking within them? | Brinson-type sector attribution |
| What systematic exposures drove the return, and how much was idiosyncratic? | Factor-based attribution |
| Which individual holdings contributed the return? | Contribution analysis, no benchmark decomposition |

Brinson answers a question about the investment process. Factor attribution answers a question
about exposures. A portfolio can show positive Brinson selection and negative factor alpha
simultaneously with no contradiction: the stock picks worked and they worked because of a factor
tilt.

## Brinson

For each segment `i` with portfolio weight `w_p,i`, benchmark weight `w_b,i`, portfolio segment
return `r_p,i`, benchmark segment return `r_b,i`, and total benchmark return `r_b`:

**Brinson-Hood-Beebower (1986)**, three-way:

```
allocation_i  = (w_p,i - w_b,i) × r_b,i
selection_i   =  w_b,i × (r_p,i - r_b,i)
interaction_i = (w_p,i - w_b,i) × (r_p,i - r_b,i)
```

**Brinson-Fachler (1985)** changes the allocation term to measure the bet against the total
benchmark rather than against zero:

```
allocation_i  = (w_p,i - w_b,i) × (r_b,i - r_b)
```

Brinson-Fachler is the better default. Under BHB, overweighting any segment with a positive return
scores positive allocation even if that segment underperformed the benchmark overall, which is not
what an allocation decision means. Under BF, overweighting a segment scores positive only if the
segment beat the total benchmark.

The interaction term is real but hard to attribute to a decision-maker. Two-way presentations fold
it into selection. Declare which convention is used; a two-way and a three-way attribution of the
same portfolio will show different selection numbers.

The three effects sum to the active return **in a single period only**.

## Multi-period linking

Arithmetic attribution effects do not sum across periods, because returns compound. Summing daily
effects over a year gives a total that does not equal the compounded active return. The gap is
sometimes called the residual or the smoothing term, and it can be large.

Three standard treatments:

- **Carino (1999)**: scale each period's effects by a logarithmic linking coefficient so the
  scaled effects sum exactly to the geometric active return. The most widely used.
- **Menchero (2000)**: an optimised linking coefficient that distributes the residual more evenly
  across periods.
- **GRAP**: recursive linking through the compounded portfolio and benchmark returns.
- **Geometric attribution**: define the effects multiplicatively from the outset, so linking is
  simply compounding. Cleaner arithmetic, less intuitive individual numbers, standard in some
  European practice.

Never present a multi-period attribution as a plain sum of single-period effects and never present
one whose components do not reconcile to the actual active return. State the linking method used
and show the reconciliation: components, sum, actual active return, residual.

A related and separate error is computing the active return itself as an arithmetic sum of
periodic active returns. Active return over a window is the difference of two compounded returns,
not the sum of the differences.

## Factor attribution

Decompose the return into factor contributions and a residual:

```
r_p,t = Σ_k β_p,k,t × f_k,t + ε_t
```

- Exposures `β` must be the exposures **held at the start of the period**, from a risk model or
  from a regression on a prior window. Exposures estimated on the same period being attributed are
  in-sample and will absorb the return by construction, leaving a spuriously small residual.
- Report the factor set explicitly, including whether it contains a market factor, whether it is
  cash-neutral, and whether the factors are returns to long-short portfolios or to
  characteristics.
- The residual is the alpha claim. Report its annualised size, its volatility, and its t-statistic
  with HAC standard errors. See [inference](inference.md#regression-practice).
- Two different factor models will give two different alphas for the same portfolio, and neither
  is wrong. The alpha is defined relative to the model. State the model whenever you state an
  alpha.
- Currency and country factors interact strongly for international portfolios; a model without
  them will push their effect into the residual and inflate the apparent alpha.

## Risk attribution

Distinct from return attribution and often more useful for a live book.

- **Marginal contribution to risk** for position `i`: `(Σw)_i / sqrt(wᵀΣw)`. The change in
  portfolio volatility per unit change in weight.
- **Contribution to risk**: `w_i × (Σw)_i / sqrt(wᵀΣw)`. These sum exactly to portfolio
  volatility, which makes them a genuine decomposition.
- Do this by factor as well as by position. A portfolio can look diversified by name and be a
  single factor bet.
- Report the effective number of positions `1 / Σ w²` alongside the nominal count, and the
  contribution concentration: what fraction of risk the top five contributors account for.

## Currency attribution

For an international portfolio, split the return into local return, currency return, and their
interaction, and separate the currency effect into the passive exposure implied by the holdings
and the active effect of any hedging decision. A portfolio with an unhedged foreign allocation has
a currency bet whether or not anyone made one; attributing it to the stock selection decision is
wrong.

## Reconciliation, and why two attributions disagree

Before concluding either is wrong, check these in order. The cause is almost always one of them.

1. **Different weights.** Beginning-of-period, end-of-period, average, or drifted.
   Beginning-of-period is the standard.
2. **Different segment definitions.** Sector classification schemes differ, and classification as
   of today versus as of the date differs again.
3. **Different linking method**, or one implementation summing and the other compounding.
4. **Different treatment of cash, futures, and unclassified holdings.** Residual buckets absorb
   the discrepancy silently.
5. **Different benchmark**, including different vintages of the same benchmark, or price return
   against total return.
6. **Different treatment of intraperiod trades.** A daily attribution on a portfolio that traded
   intraday will not match a transaction-based attribution.
7. **Different frequency.** A monthly attribution and a daily attribution linked to the same
   period give different selection and allocation splits.

Report the reconciliation explicitly: the two totals, the gap, and which of the above accounts for
it. Do not adjudicate without doing this.

## Reporting

```
window, frequency, linking method, weight convention, classification scheme and vintage

segment        w_p     w_b    r_p      r_b     allocation  selection  interaction  total
Technology    24.1%  18.3%   14.2%    11.8%       +0.31%     +0.44%       +0.14%   +0.89%
...
total        100.0% 100.0%    9.41%    7.02%      +0.88%     +1.36%       +0.15%   +2.39%

reconciliation: sum of effects +2.39% | compounded active return +2.39% | residual 0.00%
```

The reconciliation line is not optional. An attribution that does not reconcile to the active
return is not an attribution.
