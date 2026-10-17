# Collector JSON

`claude-usage` (no flags) prints one JSON object on a single line. The widget
reads nothing else, so any program that prints this shape can stand in for
the collector: set it as the *Collector command* in the widget settings.

If the collector fails it prints `{"error": "..."}` instead, and the widget
shows the message while keeping the last good render on screen.

All costs are USD at API list prices. All times are ISO 8601 in local time
unless noted.

## Top level

| field | type | meaning |
|---|---|---|
| `generated` | string | when this output was produced |
| `block_hours` | number | length of a usage block, currently 5 |
| `limits` | object | plan limits; see [limits](#limits) |
| `block` | object | the current rolling block; see [block](#block) |
| `today`, `week`, `month`, `total` | [usage](#usage) | today since midnight, the last 7 days, the last 30 days, all time |
| `models` | map of model id → [usage](#usage) | all-time usage per model, most expensive first |
| `sessions` | array | the most recent sessions (up to 8); see [sessions](#sessions) |
| `daily` | array | the last 14 days, oldest first; see [daily](#daily) |
| `families` | array of strings | the fixed family order used by `daily`: `opus`, `sonnet`, `haiku`, `fable`, `other` |
| `by_day` | map of `YYYY-MM-DD` → [usage](#usage) | every day with activity, newest first |
| `session_count` | number | sessions seen in transcripts or cost records |
| `first_seen` | string or null | timestamp of the oldest priced turn |
| `unpriced_models` | array of strings | models counted but missing from the price table |

## usage

The same shape is used for periods, models and days.

| field | meaning |
|---|---|
| `input`, `output` | uncached input and output tokens |
| `cache_write`, `cache_read` | cache creation and cache hit tokens |
| `thinking` | thinking tokens (already included in `output`) |
| `tokens` | `input + output + cache_write + cache_read` |
| `cost` | USD |
| `messages` | assistant turns |
| `web_searches` | server-side web searches |

## block

Everything in [usage](#usage), plus:

| field | meaning |
|---|---|
| `active` | whether a block is open right now |
| `start`, `end` | block bounds; `null` when idle |
| `remaining_min` | minutes until the block closes |
| `time_pct` | how far through the block we are, 0–100 |
| `burn_cost_per_hour`, `burn_tokens_per_min` | average rate since the block opened |
| `projected_cost` | `cost` plus the burn rate carried to the end of the block |

## limits

| field | meaning |
|---|---|
| `ok` | `false` when no figures are available; `reason` says why |
| `fresh`, `stale` | whether the figures came from the network on this run or the disk cache |
| `fetched`, `age_sec` | when the cached response was fetched |
| `plan` | e.g. `"Max · Max 5x"` |
| `credits` | usage credits when enabled: `currency`, `used`, `limit`, `pct` |
| `entries` | one object per limit, session first, then weekly |

Each entry:

| field | meaning |
|---|---|
| `kind` | `session`, `weekly_all`, `weekly_scoped`, or another kind the endpoint reports |
| `label` | display name, e.g. `Week (Sonnet)` |
| `pct` | percent used |
| `resets_at`, `resets_at_local`, `resets_day`, `resets_in_min` | when the window resets |
| `window_min` | window length in minutes (300 for session, 10080 for weekly); the widget uses it with `resets_in_min` to place the pace marker |
| `severity` | `normal`, `warning` (≥ 80%) or `critical` (≥ 95%), unless the endpoint supplies its own |
| `active` | whether this is the limit currently binding, when the endpoint says |

## sessions

| field | meaning |
|---|---|
| `id` | session id |
| `title` | Claude Code's latest `ai-title` for the session, or `null` |
| `cwd`, `dir` | working directory and its last path component, or `null` |
| `project` | the transcript folder name (dash-encoded path), kept for older consumers |
| `model` | the model of the most recent turn |
| `cost`, `tokens` | session totals; cost prefers Claude Code's own `totalCostUSD` |
| `last`, `ago_min` | time of the most recent turn, and minutes since |
| `active` | whether the session has turns inside the current block |

## daily

| field | meaning |
|---|---|
| `date` | `YYYY-MM-DD` |
| `label`, `weekday` | short display forms, e.g. `17 Oct`, `Sat` |
| `cost` | total for the day |
| `families` | cost per family, keyed by every name in `families` (zeros included) |

Daily figures, like `today`, `week` and `month`, come from transcripts, so
they exclude background calls that only appear in cost records. `total` uses
the cost records when they add up to more, which is why it can be slightly
higher than the sum of the days.
