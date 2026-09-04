# Equity desk

Load for equity-specific mechanics that change a result and are not covered by general return or
risk conventions.

## Universe construction

The universe is a modelling choice with a larger effect on results than most estimator choices.
Declare it as explicitly as any parameter.

- **Membership as of each date**, not as of today. See [data
  integrity](data-integrity.md#survivorship).
- **Index membership versus a screen.** An index has an announcement date, an effective date, and
  a rebalancing schedule; trading on the announcement and trading on the effective date are
  different strategies. A screen has no announcement and its own look-ahead risk in the screening
  fields.
- **Liquidity and price filters.** A minimum price filter, typically excluding sub-dollar or
  sub-five-dollar shares, and a minimum average daily volume filter. Both are defensible and both
  are choices that materially change a cross-sectional result. State them.
- **Share class handling.** Multiple listed classes of one issuer are one economic exposure.
  Decide whether to keep the most liquid class, aggregate them, or keep both, and state which.
- **Cross-listings, depositary receipts, and dual-listed structures** create the same exposure at
  two venues in two currencies. Deduplicate on the issuer, not on the ticker.
- **Free float versus shares outstanding.** Market-capitalisation weights are conventionally on
  free float. A strategy using total shares outstanding overweights closely-held names.
- **Investment trusts, closed-end funds, ETFs, SPACs, and REITs** behave differently from
  operating companies in almost every cross-sectional signal. Include or exclude deliberately.

## Classification

- GICS, ICB, and vendor-specific schemes disagree on individual names, especially at the
  sub-industry level and especially for conglomerates and technology-adjacent retailers.
- Classifications change over time and vendors apply changes retroactively to their history. A
  sector attribution run today on a period five years ago may not match the one run then.
- Record the scheme, the level (sector, industry group, industry, sub-industry), and the vintage.
- A "sector-neutral" strategy is neutral only to the scheme used to neutralise it.

## Corporate actions

Covered generally in [data integrity](data-integrity.md#corporate-actions). Equity-specific
points:

- **Spin-offs** create a new security whose initial history does not exist. The parent's return on
  the ex-date includes the value of the distributed entity; a price series that does not account
  for it shows a large false loss.
- **Rights issues** dilute and are handled by an adjustment factor, like a split.
- **Special dividends** are frequently missed by the ordinary dividend adjustment.
- **Mergers**: the acquired name's terminal return is the deal consideration, not a delisting to
  zero. Treating an acquisition as a failure delisting is a large and systematic error, because
  acquisitions are positive events concentrated in specific parts of the cross-section.
- **Ticker reuse.** Exchanges reissue tickers. Key on a persistent identifier such as an ISIN or a
  vendor permanent identifier, never on a ticker.

## Short borrow

Materially changes any long-short result and is frequently ignored entirely.

- Borrow must be locatable, is charged as a fee, and can be recalled, forcing a buy-in at the
  worst time.
- The fee is not uniform. General collateral names cost a few basis points a year; hard-to-borrow
  names cost hundreds or thousands of basis points, and they are concentrated in exactly the
  small, expensive, heavily-shorted part of the cross-section that value, quality, and
  short-interest signals want to short.
- A dollar-neutral backtest with no borrow cost systematically overstates the short leg. Report
  the long and short legs separately so the manager can see where the return comes from.
- Short-sale restrictions and bans appear in stress periods, exactly when a short leg is working.
- Report the fraction of the short book in hard-to-borrow names, or state that borrow data was
  unavailable and that the short leg's return is therefore an upper bound.

## Liquidity and capacity

- **Average daily volume**, typically a 20 or 60 day median rather than a mean, because the mean
  is dominated by event days.
- **Participation rate**: the fraction of ADV the strategy would trade. Beyond roughly 10-20% the
  impact model's assumptions break down and the cost is better described as unavailable.
- **Days to liquidate** at a stated participation rate, per position and for the book. Report the
  distribution, not the average; the tail is the risk.
- Liquidity is not stable. ADV falls sharply in stress, exactly when liquidation is needed.
- Free float, not market capitalisation, bounds what can be traded.

## Beta and factor exposure

See [risk models](risk-models.md#beta) for estimation. Equity-specific:

- Equity betas mean-revert toward one, which is what the Blume and Vasicek adjustments encode. Use
  an adjusted beta for forward-looking hedging and a raw beta for describing what happened.
- Small caps and recent listings have unstable betas and short histories. A sector median beta is
  a defensible fallback for a name below the minimum observation gate; a beta of zero is not.
- Sector betas are not stable across regimes. A sector's defensive reputation is not a substitute
  for its measured behaviour in the specific stress period being modelled. Where a historical
  analogue exists, measure the sector's actual behaviour in it and use that rather than a prior.

## Cross-sectional signal work

- **Neutralise deliberately.** A raw signal usually carries a size, sector, and beta tilt. Report
  the signal's return before and after neutralisation; the difference is the part of the return
  that was a factor bet.
- **Rank or z-score within the cross-section on each date**, fitting nothing across dates. Fitting
  a scaler on the full panel leaks the future into every date. See [out of
  sample](out-of-sample.md#leakage-sources-to-check-explicitly).
- **Winsorise or clip explicitly and state the threshold.** Cross-sectional signals have long
  tails and a single extreme value can dominate a value-weighted quintile spread.
- **Quintile or decile spreads** are the standard presentation. Report the monotonicity across
  buckets, not just the top-minus-bottom spread. A non-monotonic signal with a large spread is
  usually a tail artefact.
- **Information coefficient**: the cross-sectional rank correlation between the signal and the
  forward return, computed per date, then averaged with a Newey-West standard error on the time
  series of coefficients. Do not pool across dates.
- **Signal decay**: report the information coefficient at several forward horizons. A signal that
  decays within a day has a cost problem regardless of its strength.
- **Turnover of the signal itself**, separately from the portfolio's turnover.

## Timing and market microstructure

- The close is an auction with different dynamics from continuous trading. A backtest executing at
  the close is assuming auction participation.
- Opening prices are noisier and gap from the prior close. A signal using the previous close and
  executing at the next open captures the overnight move, which is a different and often larger
  effect than the intraday one.
- Earnings announcements, index rebalance dates, quarterly expiries, and month ends have distinct
  and well-documented return dynamics. A strategy whose return concentrates on those dates is
  trading that effect, not the stated signal. Report the return decomposition by event day.
- Non-overlapping trading sessions across regions understate measured correlation on daily
  close-to-close data. Use weekly returns or a lead-lag correction for cross-region work.
