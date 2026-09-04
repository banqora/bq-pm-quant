# Backtesting

Load when constructing, reviewing, or interpreting a simulated track record. Protocol and search
correction are in [out of sample](out-of-sample.md); data defects in [data
integrity](data-integrity.md).

## The timing contract

Write it down before writing code, in one place, and make every function conform.

```
t      information set closes. Signal computed from data timestamped strictly at or before t.
t+1    trade executes at a price observed at or after the decision. Name the price: open,
       VWAP over a stated window, close, or arrival plus impact.
t+1..  position is held and earns return.
```

The single most common backtest defect is a one-period slip in this chain, and it is not visible
in the output except as an implausibly good result. Enforce it structurally rather than by care:

- One function produces the signal and it may not receive any argument containing data after `t`.
- One function converts signal to target weights and it sees no returns.
- One function applies weights to forward returns and it sees no signal.
- Assert in the third function that the weight index is strictly earlier than the return index.

Any centred rolling window, any negative shift, and any `resample` that labels a bar by its start
while aggregating forward breaks the contract. Trailing windows only.

**A daily-frequency gross Sharpe above roughly 3 is a lag defect until proven otherwise.** Do not
report it as a result. Run the diagnostics in [review
checklist](review-checklist.md#diagnose-a-surprising-number) first, and report what you ruled out.

## Rebalancing

The rebalancing assumption is frequently a larger source of error than the estimator. Two
components computing "the same" tracking error on the same portfolio can differ by a factor of
three or more purely because one renormalises weights when a security's data is missing and the
other holds them fixed.

Declare, as an explicit named choice rather than an emergent behaviour of the code:

- **Frequency**: daily, weekly, monthly, at signal change, or at a band breach.
- **Drift treatment between rebalances**: weights drift with returns (buy and hold), or are held
  constant (implicit costless daily rebalancing). The second is a strong and usually unintended
  assumption that inflates both volatility and turnover.
- **Missing-data treatment**: what happens to a weight when a security has no price that day.
  Renormalising the remaining weights is an implicit trade that costs nothing in the simulation
  and something in reality.
- **Band or no-trade region**: rebalance only when a weight deviates by more than a threshold.
  Materially reduces turnover and changes the return path.
- **Cash**: where the residual goes and what it earns.

If two implementations disagree, compare them by holding everything else fixed and switching only
the rebalancing method. Report both numbers and the gap.

## Transaction costs

A gross backtest is an upper bound on a strategy that does not exist. Report gross and net side by
side, always, with the cost model stated.

Components, in the order they matter for a typical equity book:

1. **Spread**: half the quoted bid-ask on each side, or an effective spread estimate for larger
   orders. Widens sharply in small caps and in stress.
2. **Market impact**: the strategy's own trading moves the price. A square-root model is the
   standard working form: `impact ≈ Y × σ_daily × sqrt(Q / ADV)` with `Y` on the order of 0.5 to
   1. Linear models understate impact for large participation and overstate it for small.
3. **Commission and fees**: exchange, clearing, regulatory. Small and predictable.
4. **Borrow cost** on short positions. Not small, not constant, and concentrated exactly in the
   names a cross-sectional signal wants to short. See [equity desk](equity-desk.md#short-borrow).
5. **Financing** on leverage, at the actual rate the book pays.

Report the **break-even cost**: the round-trip cost at which the strategy's mean return reaches
zero. It is a single number, does not require committing to a cost assumption, and directly
answers whether the result survives realistic execution. A strategy with a break-even cost below
the typical spread of its own universe does not need a further cost debate.

A flat basis-point assumption is acceptable as a first pass if it is stated as such. It is wrong
in a specific direction: it understates cost for the small, illiquid, high-turnover corner of the
universe where cross-sectional signals concentrate.

## Capacity

Backtest fills are counterfactual. The strategy did not trade, so the prices it trades against are
prices that would have moved.

- Constrain the position size to a fraction of average daily volume, typically 5-20%
  participation, and report how much of the signal's return is lost when the constraint binds.
- Report the assets under management at which the strategy's impact cost consumes its alpha. This
  is more useful to a manager than a Sharpe ratio.
- A signal whose returns concentrate in the smallest quintile by market capitalisation has a
  capacity problem regardless of its statistics. Report the return decomposition by size and
  liquidity bucket.

## Shorting and leverage

- Shorting requires locatable borrow, at a cost, with recall risk. A dollar-neutral backtest that
  assumes free unlimited shorting is measuring something that cannot be traded.
- Report the long and short legs separately. If the return comes entirely from the short leg in
  hard-to-borrow names, the strategy is a borrow-cost trade.
- Leverage has a financing cost and a margin constraint that binds exactly when the strategy is
  losing. A backtest with constant leverage through a drawdown assumes a margin call that never
  came.

## What to report from a backtest

```
window, n, universe definition and how membership was determined as of each date
rebalance frequency, drift treatment, execution price convention, lag from signal to fill
cost model and parameters, borrow assumption, financing rate
gross and net: annualised return, volatility, Sharpe with SE, max drawdown with dates
break-even round-trip cost
one-way annual turnover
capacity: participation constraint applied, AUM at which net alpha reaches zero
return decomposition: long leg vs short leg, by size quintile, by sector
factor exposures: the backtest's realised beta and factor loadings
number of specifications searched, and the protocol level from out-of-sample.md
```

The factor exposure line matters more than it looks. A long-short equity backtest with a realised
market beta of 0.3 and a value loading of 0.8 has produced a leveraged, tilted portfolio, and its
return should be judged against that combination rather than against zero.

## What a backtest cannot establish

State these plainly when a manager is weighing a backtested result.

- That the strategy works. A backtest fails to reject a hypothesis; it cannot confirm one.
- Its capacity, because the fills are counterfactual.
- Its behaviour in a regime the sample does not contain.
- The drawdown that would actually have been tolerated. The simulation never faced redemptions, a
  risk committee, or a career.
- That the data used was available at the time, in the form used, to a person who did not know the
  answer. That has to be established separately.

## Reviewing a backtest you did not write

In order, because each step can end the review:

1. Find the line where signal meets return and check the lag by hand on three dated observations.
2. Check the universe construction for survivorship and for membership as of date.
3. Check whether any transformation, scaler, ranking, or threshold was fitted on the full sample.
4. Check the cost model exists and find its parameters.
5. Check what happens to a security with missing data on a rebalance date.
6. Ask how many specifications were tried. If the answer is unavailable, the p-value is not
   interpretable and should not be reported.
7. Run the golden test: feed the pipeline simulated data with a known Sharpe and confirm recovery.
   See [coding standards](coding-standards.md#the-golden-test).
