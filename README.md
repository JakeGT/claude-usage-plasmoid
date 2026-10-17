# Claude Code Usage — KDE Plasma widget

A Plasma 6 applet showing how close you are to your plan's rate limits, and
what your Claude Code usage would cost at API list prices.

<img src="docs/widget.png" alt="The widget, showing demo data" width="460">

*Screenshot uses the collector's `--demo` data.*

## What it shows

From top to bottom:

- **Session limit** — the rolling 5-hour window as a large percentage and a
  meter, with the time until it resets. The same figures as Claude Code's
  own `/usage`.
- **Weekly limits** — the weekly cap, plus any model-scoped weekly caps once
  they carry a number.
- **Pace markers** — each limit meter has a small tick showing how far
  through its window you are. If the fill is past the tick, you are using the
  limit faster than an even pace would. Hover a meter for the numbers.
- **Current 5h block** — spend, burn rate and projected close-out for the
  active window, as three tiles.
- **Period totals** — today, last 7 days, last 30 days and all time,
  optionally measured against budgets you set.
- **Daily spend** — the last 14 days as stacked columns, one colour per
  model family (Opus, Sonnet, Haiku, Fable). Only the biggest day and today
  are labelled; hover any column for its breakdown.
- **By model** — all-time spend per model.
- **Recent sessions** — Claude Code's own title for each session, the
  folder it ran in, the model, how long ago, and its cost. A green dot means
  the session has activity in the current block.

Status colours are kept for state: amber means a limit is near (80%), red
means it is reached (95%). Both also show an icon or the words "near limit"
or "at limit", so the colour is never the only signal. The model-family
colours were checked for colour-blind separation and contrast on Breeze
Dark.

In the panel the widget shows the block cost and the session-limit percent,
with a coloured dot only when the limit is near.

## How it gets the numbers

Two local sources plus one network call:

| | source |
|---|---|
| Anything time-sliced (block, today, 7/30 days, daily chart) | `message.usage` on assistant turns in `~/.claude/projects/**/*.jsonl`, priced locally |
| All-time totals and the model breakdown | `cost-state` records, which include background Haiku calls that never reach a transcript |
| Session titles and folders | `ai-title` records and the `cwd` on each turn, in the same transcripts |
| Plan rate limits | `GET https://api.anthropic.com/api/oauth/usage`, the endpoint Claude Code's own `/usage` reads |

Local pricing is reconciled against Claude Code's own recorded `costUSD`
figures: run `claude-usage --verify` to check every entry. Claude Code's
records do not say whether a cache write used the 5-minute or 1-hour TTL, so
a session that used both is reported as `mix` when its recorded cost falls
between the two prices.

Prices come from
[platform.claude.com/docs/en/about-claude/pricing](https://platform.claude.com/docs/en/about-claude/pricing),
including the 5.5 generation (Opus 5.5, Sonnet 5.5 and Haiku 5.5, with
Haiku 5.5's higher rate for prompts over 100K tokens). On a subscription
these are what the same usage would cost through the API, not what you are
billed.

### About the token

The limits call authenticates with the OAuth access token that Claude Code
already stores in `~/.claude/.credentials.json`. It is only ever sent back to
the host that issued it. The collector never refreshes the token: on a 401 it
serves its cached figures and waits for Claude Code to refresh, because
rotating the refresh token here would log you out.

Responses are cached in `~/.cache/claude-usage/limits.json` for 120s
(`CLAUDE_USAGE_LIMITS_TTL`), so a 60s widget poll only hits the network every
other tick. If you would rather the widget never touched the network, set the
collector command to `claude-usage --no-limits` and it will run entirely from
local transcripts.

## Install

```sh
git clone https://github.com/JakeGT/claude-usage-plasmoid.git
cd claude-usage-plasmoid

install -Dm755 bin/claude-usage ~/.local/bin/claude-usage
kpackagetool6 --type Plasma/Applet --install .
```

Then right-click the desktop → *Add Widgets* → *Claude Code Usage*.

To upgrade an installed copy:

```sh
git pull
install -Dm755 bin/claude-usage ~/.local/bin/claude-usage
kpackagetool6 --type Plasma/Applet --upgrade .
systemctl --user restart plasma-plasmashell
```

The widget is designed for a desktop slot of roughly 23 × 40 grid units
(about 420 × 750 px at 1× scale). In a smaller slot the recent-sessions list
scrolls; the sections above it can be switched off in the settings.

## The collector on its own

`claude-usage` is a standalone script; the widget just reads its JSON. The
format is documented in [docs/collector-json.md](docs/collector-json.md).

```
claude-usage             JSON for the widget (default)
claude-usage --text      pretty terminal report
claude-usage --daily 14  per-day table
claude-usage --limits    plan limits only  (--json for raw)
claude-usage --no-limits skip the network call, cached limits only
claude-usage --verify    reconcile computed cost against Claude Code's own
claude-usage --demo      synthetic data, for screenshots and testing
```

`CLAUDE_USAGE_DEMO=1` makes the default command print demo data too, which
is how the screenshot above was taken:

```sh
CLAUDE_USAGE_DEMO=1 plasmawindowed org.kde.claudeusage
```

## Configuration

Right-click the widget → *Configure*:

- **Collector command** — defaults to `claude-usage`, found on `PATH` with
  `~/.local/bin` added.
- **Refresh interval** — default 60s.
- **Block / daily / weekly budgets** — optional cost ceilings. The block
  budget adds a meter under the block tiles; the daily and weekly budgets
  add a percentage under Today and 7 days. Leave at zero to ignore.
- **Show** — plan limits, session-limit percent in the panel, daily spend
  chart, per-model breakdown, recent sessions.

## Requirements

Plasma 6, Python 3.9+, and a Claude Code install signed in to claude.ai.
Plan limits need a subscription; on API-key, Bedrock or Vertex auth the
endpoint returns nothing and that section is replaced by a one-line note.

## Licence

MIT
