# PTC prompt A/B

A focused, manual evaluation of tool orchestration guidance using the real
OpenSeek CLI and `deepseek-v4-flash`. It is not a general MoonBit coding
benchmark. The small Python standard-library runner stages byte-exact fixtures
and scores nested PTC metadata, which the general prompt-task harness does not
currently score. API credentials are inherited from `DEEPSEEK`, never copied
into commands or reports.

## Run

Build the engine first, then run three repetitions per variant:

```sh
moon build --target native cmd/openseek
python3 eval/ptc_prompt/run.py \
  --engine _build/native/debug/build/bobzhang/openseek/cmd/openseek/openseek.exe \
  --out .moonagent/eval_runs/ptc_prompt_ab --runs 3 --concurrency 3
```

`baseline.md` and `candidate.md` replace only the PTC section of the same
**rendered** generated prompt, including its expanded references tree. All
trials use the same binary, model, fixtures, step cap (24), and timeout (600s).
The manifest records the commit, binary hash, and complete prompt hashes. Each
pair alternates launch order across repetitions. Output directories must be new;
trials are never silently overwritten.

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

`candidate_expanded.md` preserves the first, rejected wording for audit;
`candidate.md` is the compact revision. The saved full prompts in each run
directory are authoritative for that run.

Neither variant is forced to use PTC by default. To measure the callable API
separately from the model's choice of tools, run a separate cohort:

```sh
python3 eval/ptc_prompt/run.py \
  --engine _build/native/debug/build/bobzhang/openseek/cmd/openseek/openseek.exe \
  --out .moonagent/eval_runs/ptc_prompt_required_ab \
  --cases computed_edits --require-ptc --runs 3 --concurrency 2
```

Do not pool these two cohorts: they answer different questions. Three repeats
are exploratory evidence, not statistical proof or a cross-model guarantee.

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
