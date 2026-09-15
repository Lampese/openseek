# PTC capability and prompt evaluation

A focused, manual evaluation of tool orchestration guidance using the real
OpenSeek CLI and `deepseek-v4-flash`. It is not a general MoonBit coding
benchmark. The small Python standard-library runner stages byte-exact fixtures
and scores nested PTC metadata, which the general prompt-task harness does not
currently score. API credentials are inherited from `DEEPSEEK`, never copied
into commands or reports.

## Capability A/B (next release step)

Publish SDK 0.1.0 and pass the host's real-script tests first. Build a baseline
engine from the SDK-only PR (#1518, original host tools) and a candidate from
the host bridge (#1519). Then compare free tool choice with an identical prompt:

```sh
python3 eval/ptc_prompt/run.py \
  --baseline-engine /absolute/path/to/sdk-only-openseek \
  --engine /absolute/path/to/ptc-openseek \
  --out .moonagent/eval_runs/ptc_capability_ab --runs 5 --concurrency 3
```

The runner uses the current rendered prompt for **both** variants and records
both binary hashes and equal prompt hashes. Supplying `--require-ptc` is rejected
in capability mode because the baseline does not offer it. Package publication
and this capability comparison are still pending; the historical results below
must not be presented as results for this mode.

All trials share model, fixture bytes, step cap (24), and timeout (600s). Pair
launch order alternates across repetitions. Output directories must be new.

Cases:

- `single_edit`: direct-call control; exact bytes and protected file unchanged.
- `computed_edits`: calculate twelve replacements from CSV data, preserve input
  and all unrelated bytes, and report the count and sum.
- `search`: two documentation topics, JSON answer, official documentation hosts,
  distinct source URLs present in structured search results, at least two search
  calls. The strict host oracle accepts `docs.python.org` and
  `doc.rust-lang.org`; it can reject official repository documentation or a
  URL whose fragment the model changed. Review those failures manually.
  This checks format and provenance, **not** the semantic quality of the pages.
  Live search availability introduces noise; review the returned sources too.

## Historical prompt-only A/B

`baseline.md`, `candidate.md`, `candidate_expanded.md`, and the 2026-09-15 results
preserve the original injected-client experiment. Both variants had PTC. The
current SDK prompt is not the prompt tested in those artifacts.

To reproduce the original experiment, use an engine built from `c5c1210d2`
(original PR #1516) and explicitly select `--prompt-ab`:

```sh
python3 eval/ptc_prompt/run.py --prompt-ab \
  --engine /absolute/path/to/original-injected-client-openseek \
  --out .moonagent/eval_runs/historical_prompt_ab --runs 3 --concurrency 3
```

Historical mode splices the saved PTC sections into the rendered prompt and uses
one engine for both variants. `--require-ptc --cases computed_edits` reproduces
the separate execution cohort. Do not pool it with free-choice performance
results. Three repeats are exploratory, not a cross-model guarantee.

## Analyze without API calls

```sh
python3 eval/ptc_prompt/run.py --analyze-only \
  --out .moonagent/eval_runs/ptc_prompt_ab
python3 -m unittest discover -s eval/ptc_prompt -p 'test_*.py'
```

Each trial keeps its raw CLI log, durable session, workspace, and summary JSON.
`results.json` combines the summaries. Metrics distinguish outer calls, nested
calls, outer/nested errors, interrupted requests, model-visible tool output,
model steps, wall time, and provider token/cache usage. Missing usage is `null`.
An outer error can describe the same failure as a nested error; do not add those
counts as if they were independent failures. Token totals cover the agent's
reported usage; separate search-provider token costs are not included.

Review traces for unnecessary retries, unchecked results, detached work,
verification before finish, and unsupported final claims. A passing file oracle
alone does not prove that the agent followed the requested editing tool policy.
Do not promote a prompt merely because it increases PTC usage or wins one run.
