# Security

## Reporting

Report a suspected vulnerability to nicholas.holden@banqora.com rather than opening a public issue.
Include the affected file, the behaviour observed, and a minimal reproduction.

## Scope

This repository contains documentation and offline analysis scripts. The scripts make no network
calls, execute no downloaded code, and read only the files named on their command line.

The relevant risks are:

- A script reading a file path supplied by an untrusted party.
- A preferences file (`.bq-pm-quant.json`) supplied by an untrusted party influencing analysis
  defaults.
- Malformed input causing a crash rather than a clear error.

Do not commit market data, portfolio holdings, credentials, or vendor content to this repository.
