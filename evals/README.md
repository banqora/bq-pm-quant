# Evaluations

Two layers, both requiring live model calls, both run locally. GitHub Actions runs only the
deterministic tests in `tests/`; this repository stores no API keys or subscription tokens.

## Layers

**Conduct** is the one that matters. Each case in `conduct.json` is a prompt built to tempt one
specific failure, paired with regexes that must not appear in the response and regexes that must.
The failures probed are the ones this skill exists to prevent:

| Case | Tempts |
|---|---|
| `no-disclaimer` | Appending "past performance" or "not financial advice" to a computed number |
| `no-refusal` | Declining a position-sizing calculation because the output could inform a trade |
| `no-baseline-free-verdict` | Calling a return good or a turnover high with no comparator |
| `no-intuition-shrinkage` | Shrinking a Sharpe because the number looks too large |
| `no-world-claims` | Asserting what the industry does or what has been published |
| `reports-failure-explicitly` | Silently narrowing scope when data is missing |
| `no-exhaustion-claim` | Declaring the options exhausted after five attempts |
| `attaches-n-and-se` | Reporting a point estimate with no sample size and no standard error |

**Triggers** check that `prompts.json` activates the skill on portfolio work and leaves it alone
otherwise, including the near-misses: tax treatment, legal wording, and a discretionary buy
recommendation must not trigger it.

## Authenticate

```bash
claude auth login
evals/run-local --check-auth
```

Do not pass `--console` to `claude auth login`: that selects Console/API billing rather than the
subscription. The runner removes `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`,
`CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_BASE_URL`, and the hosted-provider selectors from the model
subprocess, so an inherited credential cannot silently replace subscription use.

## Run

```bash
evals/run-local --conduct-only                    # 8 calls, the fast signal
evals/run-local --conduct-only --case no-refusal  # 1 call, while iterating on one rule
evals/run-local --triggers-only --runs 1          # 30 calls
evals/run-local --out evals/results-local.json    # everything, 38 calls
```

Each call consumes the normal usage allowance of the local subscription. Raise `--runs` above 1 only
when promoting a baseline; trigger behaviour is stochastic and a single run is a noisy estimate of
the fire rate.

## Reading a failure

A conduct failure prints the exact substring that matched a forbidden pattern, or the required
pattern that was absent. Fix the skill text, not the regex, unless the regex is genuinely wrong:
loosening a probe to make it pass is the same defect as lowering a coverage gate.

A trigger failure on a `should_not_trigger` prompt is more serious than one on a `should_trigger`
prompt. A skill that fires on unrelated work spends context on every task in the session.

## Interpreting results honestly

These are small corpora, and a pass is weak evidence. Eight conduct cases at one run each is not a
measurement of conduct; it is a smoke test that catches regressions in the rules that have already
been written down. Treat a green run as "no known regression", not as "the skill behaves".
