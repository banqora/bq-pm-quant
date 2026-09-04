#!/usr/bin/env bash
# The estimators in pm-stats against closed-form and simulated targets.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TEST_NAME="estimators"
echo "$TEST_NAME"

out="$(python3 - "$BIN/pm-stats" <<'PY'
import importlib.util, math, sys, random
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
dd = m.drawdown([1.0, -0.5, -0.5], ["d0", "d1", "d2"])
check("max drawdown from a hand-built path", abs(dd["max_drawdown"] - (-0.75)) < 1e-12,
      str(dd["max_drawdown"]))
check("drawdown trough date", dd["trough_date"] == "d2")
check("drawdown reports no recovery", dd["recovery_date"] is None)
flat = m.drawdown([0.01] * 50, None)
check("a monotonically rising path has zero drawdown", flat["max_drawdown"] == 0.0)

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
check("finds the longest zero run", ig["longest_zero_run"] == 2, str(ig["longest_zero_run"]))
check("flags a move above 50%", ig["n_extreme_moves"] == 1)

print("FAILCOUNT " + str(len(fails)))
PY
)"
echo "$out" | sed 's/^/  /'
n_fail="$(echo "$out" | sed -n 's/^FAILCOUNT //p')"
TESTS_RUN=$(echo "$out" | grep -cE '^(ok|FAIL) ')
TESTS_FAILED="${n_fail:-1}"
finish
