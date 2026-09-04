# Contributing

## Ground rules for content

The references are dense on purpose. They are loaded into a model's context, so every line competes
for attention with the task.

- **State the rule, then the reason, then the diagnostic.** A guideline with no test attached is not
  actionable.
- **Prefer a number to an adjective.** "A Sharpe of 1.0 on three years of daily data is roughly
  t = 1.7" beats "short samples are unreliable".
- **Cite the source for a named method** with author and year. Do not cite what you have not read.
- **Do not assert what cannot be checked from the text.** Claims about industry practice, vendor
  coverage, or what is common on desks do not belong here unless sourced.
- **No hedging and no editorialising**, in the references themselves as much as in the output they
  govern.
- Keep lines under 100 characters.

## Ground rules for scripts

- Python 3.9+, standard library only. These run on a manager's machine, offline, with no install
  step.
- Fail loudly. No broad exception handlers, no constant fallbacks, no silent row drops.
- Every statistic ships with the convention it assumes, in the output.
- `--help` must be sufficient to use the tool.

## Before opening a pull request

```bash
tests/run
scripts/check-skill --static
```

Run `scripts/pm-audit` over any Python you add. If a rule fires and the code is correct anyway, say
so in the pull request rather than suppressing the rule.

## Adding a reference

New references need an entry in `SKILL.md` under "Load only what the task needs", a row in the
`README.md` table, and a keyword set in `scripts/pm-docs`. `tests/run` checks all three.
