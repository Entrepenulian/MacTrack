# Changelog

Notable changes to MacTrack. Dates are in the developer's local time.

## Unreleased

### Added
- **Projects** — tag what you're working on (right-click any app or site →
  **Project**), optionally remember "always this project" so switching apps switches
  the active project, and see per-project totals for today / this week / this month
  on a new projects page (the tag button in the header). Time is credited at sampling
  time, so changing a project never relabels a past day.
- **Best-days leaderboard** — a trophy button ranks your completed days by the least
  time spent on unproductive apps/sites (today, still in progress, is never crowned).
- **Month view** in a row's detail, alongside Day and Week, with a per-day bar chart
  and a "% of month" readout.
- **Per-app/site detail** with an hourly/weekly/monthly bar chart drawn in the app or
  site's own brand color (pulled from its icon or favicon), plus its share of the
  day / week / month.
- **Per-X-account tracking** — reads the active account from the page and tracks each
  handle on its own row, with an account switcher and combined "All" total.
- **Per-X-account blocking** — block one account and MacTrack auto-switches you to
  your allowed account when you land on the blocked one (bounces only as a fallback).
- **Block a website from Settings** — a picker of your recently-used sites and a
  search box to block any site you've visited, or a brand-new domain you type.
- **Reset time** — right-click an item in the productivity breakdown to zero an
  accidental visit for the day (it re-accumulates if you go back).
- **Pause + sleep** — the Pause button also sleeps the display; a mouse move wakes it
  and auto-resumes tracking.

### Changed
- The chart now spans your **real active window** (first activity → last) instead of
  a fixed schedule, and the overview headlines your **total active time on the Mac**.
- Browsers are judged only by the **sites** you visit — empty/new tabs and
  search-results pages stay out of the Productive/Unproductive/Other split while still
  counting toward your total time.
- Settings reorganized into a category home so no page runs off the bottom.
