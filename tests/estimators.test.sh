#!/usr/bin/env bash
# The estimators in pm-stats against closed-form and simulated targets.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TEST_NAME="estimators"
echo "$TEST_NAME"

out="$(python3 - "$BIN/pm-stats" <<'PY'
import datetime, importlib.util, math, sys, random
spec = importlib.util.spec_from_loader("pmstats", loader=None)
m = importlib.util.module_from_spec(spec)
exec(open(sys.argv[1]).read().replace('if __name__ == "__main__":\n    sys.exit(main())', ''),
     m.__dict__)
fails = []

def check(name, cond, detail=""):
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else "  " + detail))
    if not cond:
        fails.append(name)

# --- distributions -------------------------------------------------------
check("norm_cdf(0) == 0.5", abs(m.norm_cdf(0) - 0.5) < 1e-12)
check("norm_cdf(1.959964) ~ 0.975", abs(m.norm_cdf(1.959963985) - 0.975) < 1e-9)
check("norm_ppf(0.975) ~ 1.959964", abs(m.norm_ppf(0.975) - 1.959963985) < 1e-6)
check("norm_ppf(0.95) ~ 1.644854", abs(m.norm_ppf(0.95) - 1.644853627) < 1e-6)
check("norm_ppf round-trips", all(abs(m.norm_cdf(m.norm_ppf(p)) - p) < 1e-9
                                  for p in (0.01, 0.1, 0.5, 0.9, 0.99)))
# chi2 with 1 df at 3.841459 has upper tail 0.05
check("chi2_sf(3.841459, 1) ~ 0.05", abs(m.chi2_sf(3.8414588, 1) - 0.05) < 1e-6)
check("chi2_sf(18.307, 10) ~ 0.05", abs(m.chi2_sf(18.30704, 10) - 0.05) < 1e-5)

# --- scipy path vs pure-Python path --------------------------------------
# Two implementations of one number is the divergence risk coding-standards.md warns about.
# It is acceptable only while they are asserted equal.
if m.__dict__.get("_scipy_stats") is not None:
    worst = 0.0
    for p_ in (0.001, 0.01, 0.025, 0.1, 0.5, 0.9, 0.975, 0.99, 0.999):
        worst = max(worst, abs(m.norm_ppf(p_) - m._norm_ppf_pure(p_)))
    check("norm_ppf: scipy and the fallback agree", worst < 1e-12, f"worst {worst:.2e}")
    worst = max(abs(m.chi2_sf(x, df) - m._chi2_sf_pure(x, df))
                for x, df in ((0.5, 1), (3.8414588, 1), (18.30704, 10), (25.0, 20)))
    check("chi2_sf: scipy and the fallback agree", worst < 1e-12, f"worst {worst:.2e}")
    worst = max(abs(m.t_sf_two_sided(t, df) - m._t_sf_two_sided_pure(t, df))
                for t, df in ((0.5, 5), (1.96, 30), (2.99, 2515), (4.0, 100)))
    check("t_sf_two_sided: scipy and the fallback agree", worst < 1e-12, f"worst {worst:.2e}")
else:
    print("ok   scipy absent; fallback path is the only path")

# --- moments -------------------------------------------------------------
xs = [1.0, 2.0, 3.0, 4.0, 5.0]
check("mean", abs(m.mean(xs) - 3.0) < 1e-12)
check("variance ddof=1", abs(m.variance(xs, 1) - 2.5) < 1e-12)
check("variance ddof=0", abs(m.variance(xs, 0) - 2.0) < 1e-12)
check("stdev ddof=1", abs(m.stdev(xs, 1) - math.sqrt(2.5)) < 1e-12)
check("skewness of a symmetric series is 0", abs(m.skewness(xs)) < 1e-12)
# scipy.stats.kurtosis([1,2,3,4,5], bias=False) == -1.2
check("excess kurtosis matches the bias-corrected value",
      abs(m.excess_kurtosis(xs) - (-1.2)) < 1e-9, str(m.excess_kurtosis(xs)))
# a perfectly alternating series has lag-1 autocorrelation near -1
alt = [1.0, -1.0] * 200
check("autocorr of an alternating series ~ -1", abs(m.autocorr(alt, 1) + 1) < 0.02,
      str(m.autocorr(alt, 1)))

# --- Newey-West ----------------------------------------------------------
rng = random.Random(11)
iid = [rng.gauss(0, 1) for _ in range(4000)]
se0, lag0 = m.newey_west_se_of_mean(iid, lag=0)
naive = m.stdev(iid, ddof=0) / math.sqrt(len(iid))
check("NW with lag 0 equals the iid SE of the mean", abs(se0 - naive) < 1e-12)
seL, lagL = m.newey_west_se_of_mean(iid)
check("NW automatic lag follows 4*(T/100)^(2/9)",
      lagL == int(math.floor(4 * (len(iid) / 100.0) ** (2.0 / 9.0))), str(lagL))
check("NW SE on iid data is close to the naive SE", abs(seL / naive - 1) < 0.12,
      f"{seL/naive:.3f}")
# strongly positively autocorrelated series: NW must be materially larger than naive
ar = [0.0]
for _ in range(4000):
    ar.append(0.8 * ar[-1] + rng.gauss(0, 1))
ar = ar[1:]
se_ar, _ = m.newey_west_se_of_mean(ar)
naive_ar = m.stdev(ar, ddof=0) / math.sqrt(len(ar))
check("NW SE exceeds the naive SE on an AR(1) series", se_ar > 1.8 * naive_ar,
      f"ratio {se_ar/naive_ar:.2f}")

# --- percentile ----------------------------------------------------------
srt = list(range(1, 101))
check("percentile(0.5) on 1..100", abs(m.percentile(srt, 0.5) - 50.5) < 1e-9)
check("percentile(0.0) is the minimum", m.percentile(srt, 0.0) == 1)
check("percentile(1.0) is the maximum", m.percentile(srt, 1.0) == 100)

# --- drawdown ------------------------------------------------------------
# +100%, then -50% twice: wealth 1 -> 2 -> 1 -> 0.5, worst drawdown -75% from the peak at index 0
days = [datetime.date(2020, 1, 1) + datetime.timedelta(days=i) for i in range(8)]
dd = m.drawdown([1.0, -0.5, -0.5], days[:3])
check("max drawdown from a hand-built path", abs(dd["max_drawdown"] - (-0.75)) < 1e-12,
      str(dd["max_drawdown"]))
check("drawdown trough date", dd["trough_date"] == days[2])
check("drawdown peak date", dd["peak_date"] == days[0])
check("drawdown reports no recovery", dd["recovery_date"] is None)
check("an unrecovered drawdown has no peak-to-recovery duration",
      dd["peak_to_recovery_periods"] is None and dd["recovery_label"] == "not recovered")
check("peak-to-trough duration is peak index to trough index",
      dd["peak_to_trough_periods"] == 2, str(dd["peak_to_trough_periods"]))
flat = m.drawdown([0.01] * 50, None)
check("a monotonically rising path has zero drawdown", flat["max_drawdown"] == 0.0)
check("a path with no drawdown reports no durations",
      flat["peak_to_trough_periods"] == 0 and flat["peak_to_recovery_periods"] == 0)

# peak-to-trough and peak-to-recovery are different numbers and both are reported.
# wealth 1 -> 0.9 -> 1.08 -> 0.81 -> 0.9 -> 1.10: the deepest drawdown runs from the peak at
# index 1 to the trough at index 2, and recovers at index 4.
dd2 = m.drawdown([-0.1, 0.2, -0.25, 0.111111111111111, 0.222222222222], days[:5])
check("peak-to-trough is shorter than peak-to-recovery",
      dd2["peak_to_trough_periods"] == 1 and dd2["peak_to_recovery_periods"] == 3,
      f"{dd2['peak_to_trough_periods']} / {dd2['peak_to_recovery_periods']}")
check("drawdown recovery date is the first close back at the peak",
      dd2["recovery_date"] == days[4], str(dd2["recovery_date"]))

# When the all-time peak is the starting wealth of 1.0 it sits before the first return, so the
# first observation would otherwise name the peak one period late.
dd3 = m.drawdown([-0.1, -0.2, 0.5], days[:3])
check("a peak at the starting wealth is not dated to the first return",
      dd3["peak_at_series_start"] and dd3["peak_date"] is None, str(dd3["peak_date"]))
check("a peak at the starting wealth is labelled as the series start",
      dd3["peak_label"].startswith("series start"), dd3["peak_label"])
check("durations count from the period start when the peak is the starting wealth",
      dd3["peak_to_trough_periods"] == 2 and dd3["peak_to_recovery_periods"] == 3,
      f"{dd3['peak_to_trough_periods']} / {dd3['peak_to_recovery_periods']}")

# --- Sharpe block --------------------------------------------------------
# closed form: SE_iid = sqrt((1 + SR_p^2/2)/T), annualised by sqrt(k)
rng2 = random.Random(5)
k = 252
sd = 0.12 / math.sqrt(k)
mu = 1.0 * 0.12 / k
r = [rng2.gauss(mu, sd) for _ in range(5000)]
b = m.sharpe_block(r, k)
sr_p = m.mean(r) / m.stdev(r, 1)
expect_se = math.sqrt((1 + sr_p ** 2 / 2) / len(r)) * math.sqrt(k)
check("Sharpe annualises by sqrt(k)", abs(b["sharpe_ann"] - sr_p * math.sqrt(k)) < 1e-12)
check("iid Sharpe SE matches the closed form", abs(b["se_iid_ann"] - expect_se) < 1e-12)
check("t-statistic equals Sharpe over its SE",
      abs(b["t_iid"] - b["sharpe_ann"] / b["se_iid_ann"]) < 1e-9)
check("recovers the simulated Sharpe within 3 SE",
      abs(b["sharpe_ann"] - 1.0) < 3 * b["se_iid_ann"],
      f"{b['sharpe_ann']:.3f} +/- {b['se_iid_ann']:.3f}")
check("Mertens SE equals the iid SE when skew and excess kurtosis are ~0",
      abs(b["se_mertens_ann"] / b["se_iid_ann"] - 1) < 0.05)
check("Lo adjustment is near-neutral on an independent series",
      abs(b["sharpe_ann_lo"] / b["sharpe_ann"] - 1) < 0.10,
      f"{b['sharpe_ann_lo']:.3f} vs {b['sharpe_ann']:.3f}")
check("Ljung-Box over the Lo lags does not reject on independent data",
      b["lo_ljung_box_p"] > 0.05, str(b.get("lo_ljung_box_p")))

# noise: a zero-mean series must not produce a significant t
noise = [rng2.gauss(0.0, sd) for _ in range(5000)]
bn = m.sharpe_block(noise, k)
check("a zero-edge series produces |t| < 3", abs(bn["t_iid"]) < 3.0, f"t={bn['t_iid']:.2f}")

# deflation must reduce the implied significance as the trial count grows
b1 = m.sharpe_block(r, k, trials=2)
b2 = m.sharpe_block(r, k, trials=500)
check("deflated Sharpe falls as the trial count rises",
      b2["deflated_sharpe"] < b1["deflated_sharpe"],
      f"{b1['deflated_sharpe']:.4f} -> {b2['deflated_sharpe']:.4f}")
check("SR0 hurdle rises with the trial count", b2["sr0_ann"] > b1["sr0_ann"])

# minimum track record length shrinks as the Sharpe rises
strong = [rng2.gauss(2.0 * 0.12 / k, sd) for _ in range(5000)]
bs = m.sharpe_block(strong, k)
check("minimum track record length falls as the Sharpe rises",
      bs["min_trl_periods"] < b["min_trl_periods"],
      f"{b['min_trl_periods']:.0f} -> {bs['min_trl_periods']:.0f}")

# --- integrity -----------------------------------------------------------
ig = m.integrity([0.0, 0.0, 0.0, 0.01, -0.6, 0.02], None)
check("counts exact-zero returns", ig["zero_returns"] == 3)
check("finds the longest zero run", ig["longest_zero_run"] == 3, str(ig["longest_zero_run"]))
check("flags a move above 50%", ig["n_extreme_moves"] == 1)

# The zero-run scan must start at index 0. A vendor padding the start of a history with zeros is
# the case the stale-price flag (which fires at 5) exists to catch, and a scan starting at index 1
# undercounts a leading run by one and lets a run of five through as four.
lead = m.integrity([0.0] * 5 + [0.01, 0.02, 0.03], None)
mid = m.integrity([0.01, 0.02] + [0.0] * 5 + [0.03], None)
tail = m.integrity([0.01, 0.02, 0.03] + [0.0] * 5, None)
check("a zero run at the start of the series is counted in full",
      lead["longest_zero_run"] == 5, str(lead["longest_zero_run"]))
check("a zero run in the middle of the series is counted in full",
      mid["longest_zero_run"] == 5, str(mid["longest_zero_run"]))
check("a zero run at the end of the series is counted in full",
      tail["longest_zero_run"] == 5, str(tail["longest_zero_run"]))
check("a leading run and a middle run of the same length count the same",
      lead["longest_zero_run"] == mid["longest_zero_run"] == tail["longest_zero_run"])

# --- risk-free day counts ------------------------------------------------
# simple-annual divides the annual rate by k; act/360 charges the actual calendar days, which is
# what return-conventions.md requires and what makes a Monday carry the weekend.
weekdays = []
d = datetime.date(2021, 1, 4)          # a Monday
while len(weekdays) < 10:
    if d.weekday() < 5:
        weekdays.append(d)
    d += datetime.timedelta(days=1)
rates_sa, desc_sa = m.periodic_rf_series(0.05, 252, "simple-annual", weekdays, 10)
check("simple-annual is the annual rate over k, on every observation",
      all(abs(r - 0.05 / 252) < 1e-15 for r in rates_sa), str(rates_sa[0]))
check("the simple-annual description names the convention", "simple-annual" in desc_sa, desc_sa)

rates_c, _ = m.periodic_rf_series(0.05, 252, "compounded", weekdays, 10)
check("compounded is the k-th root of the gross annual rate",
      abs(rates_c[0] - ((1.05) ** (1 / 252) - 1)) < 1e-15, str(rates_c[0]))

rates_360, desc_360 = m.periodic_rf_series(0.05, 252, "act/360", weekdays, 10)
# weekdays[0] is a Monday charged the median gap (1 day); weekdays[5] is the Monday after a
# weekend and must carry three calendar days.
check("act/360 charges one day inside the week",
      abs(rates_360[1] - 0.05 * 1 / 360) < 1e-15, str(rates_360[1]))
check("act/360 charges three days across a weekend",
      abs(rates_360[5] - 0.05 * 3 / 360) < 1e-15, str(rates_360[5]))
check("act/360 is not a constant per-period rate", len(set(rates_360)) > 1)
check("act/365 uses the 365 basis",
      abs(m.periodic_rf_series(0.05, 252, "act/365", weekdays, 10)[0][1] - 0.05 / 365) < 1e-15)
check("the act/360 description names the convention and the first-observation choice",
      "act/360" in desc_360 and "median gap" in desc_360, desc_360)
check("the first observation is charged the median gap",
      abs(rates_360[0] - 0.05 * 1 / 360) < 1e-15, str(rates_360[0]))

try:
    m.periodic_rf_series(0.05, 252, "act/360", [], 10)
    check("act/360 without dates raises rather than degrading to simple-annual", False)
except SystemExit as exc:
    check("act/360 without dates raises rather than degrading to simple-annual",
          "act/360" in str(exc) and "simple-annual" in str(exc), str(exc)[:80])
try:
    m.periodic_rf_series(0.05, 252, "30/360", weekdays, 10)
    check("an unimplemented day count raises with the accepted values", False)
except SystemExit as exc:
    check("an unimplemented day count raises with the accepted values",
          "act/360" in str(exc) and "compounded" in str(exc), str(exc)[:80])
dup = [weekdays[0], weekdays[0], weekdays[1]]
try:
    m.periodic_rf_series(0.05, 252, "act/360", dup, 3)
    check("a zero day count raises rather than charging no financing", False)
except SystemExit as exc:
    check("a zero day count raises rather than charging no financing",
          "day count" in str(exc), str(exc)[:80])
check("a zero annual rate needs no dates under any convention",
      m.periodic_rf_series(0.0, 252, "act/360", [], 4)[0] == [0.0] * 4)

# --- information ratio consistency ---------------------------------------
# The IR is the Sharpe of the active series: one estimator, one implementation. Every row this
# tool prints satisfies t = value / se, and the active rows must too.
rng3 = random.Random(21)
active = [rng3.gauss(0.0002, 0.004) for _ in range(1200)]
ab = m.sharpe_block(active, 252)
check("the IR t-statistic equals the IR over its iid SE",
      abs(ab["t_iid"] - ab["sharpe_ann"] / ab["se_iid_ann"]) < 1e-9,
      f"{ab['t_iid']} vs {ab['sharpe_ann'] / ab['se_iid_ann']}")
check("the IR Mertens t-statistic equals the IR over its Mertens SE",
      abs(ab["t_mertens"] - ab["sharpe_ann"] / ab["se_mertens_ann"]) < 1e-9)

print("FAILCOUNT " + str(len(fails)))
PY
)"
echo "$out" | sed 's/^/  /'
n_fail="$(echo "$out" | sed -n 's/^FAILCOUNT //p')"
TESTS_RUN=$(echo "$out" | grep -cE '^(ok|FAIL) ')
TESTS_FAILED="${n_fail:-1}"
finish
