# TownHall Live

Preserving Civic History & Demystifying Local Democracy for Massachusetts Towns.
**Congressional App Challenge 2026 entry.** Native SwiftUI iOS app; pilot town: Town, MA.

## Run it

```sh
xcodegen          # generates TownHallLive.xcodeproj from project.yml
open TownHallLive.xcodeproj
```

Pick the `TownHallLive` scheme, choose the iPhone simulator (or your device),
Cmd+R. Everything works offline — no backend, no key. With a `TownSources.plist` (see Live data) it pulls current warrants, results and recordings from the town's website.

## App map

| Tab | Purpose |
| --- | --- |
| **Live** | Agenda of the (simulated) current session, "Demo live session" auto-advancing playback, Town TV stream link, and a clearly-labeled **mock poll** (Yay/Nay/Abstain with a simulated community tally) |
| **Warrants** | Warrant articles grouped by meeting; each article shows a plain-English translation, financial impact, official outcome, "synced with history" links, and the original legal text |
| **History** | Searchable timeline of past Town Meeting decisions, linked both ways to the warrants they echo |

## AI

- Runtime model calls use **any OpenAI-compatible endpoint** (OpenRouter-style shape).
  Defaults: Hack Club AI (`https://ai.hackclub.com/proxy/v1`, `openai/gpt-4o-mini`).
- Base URL + model live in `UserDefaults`; the API key is entered in **Settings** and stored only in the **Keychain** — never in code.
- Without a key the app is fully functional from bundled plain-English summaries.
- AI disclosure for the CAC submission: AI generates runtime plain-English translations of public warrant text, and was used to prepare bundled example summaries. All official text remains attributed to public town documents.

## Live data

The app reads the town's own public sources **on the phone** — no backend:

| Source | What the app takes from it | Where it shows |
| --- | --- | --- |
| Town Meeting page on the town website (CivicPlus/CivicEngage) | One block per "<year> Annual/Special Town Meeting": links to the warrant booklet, the results summary, and the session videos | Live hero, Recent sessions, Warrants tab headers, "Watch on Town TV" |
| Warrant booklet PDF (read with PDFKit) | Each `Article N:` — title, vote requirement, verbatim "To see if the Town…" text, dollar figures, the booklet's own summary and board recommendations | Warrants tab, article detail ("Original warrant text", financial impact) |
| Results summary PDF | Outcome per article (Approved / Not approved / No action / Postponed, plus a count when the sheet prints one) | Outcome chips and "Official outcome" |
| Town calendar RSS | Upcoming sessions whose title matches a filter (default "Town Meeting") | Recent sessions (as upcoming) |
| Town TV YouTube channel feed | Recent videos whose title matches a filter (default "Meeting") | Recent sessions (opens the recording) |

**How it behaves**

- Launch shows the last saved live data (or the bundled JSON) instantly, then refreshes in the background. Pull down on any tab to refresh; the app also refreshes when it comes back to the foreground after 30 minutes. A small "Updated X ago" line shows freshness.
- Live data overrides bundled data article by article. Curated plain-English summaries, curated vote counts (only when they agree with the live result), the **History** timeline and the **simulated** demo session stay bundled.
- **Plain English:** with an AI key set, scraped articles that have no curated summary are translated in the background through the configured OpenAI-compatible endpoint and cached on disk by a hash of the article text. Without a key, the app shows the booklet's own summary (first sentences), the dollar figure and vote requirement, clearly marked *not translated yet*.
- **Offline / failures:** every source is fetched and parsed independently. A network error, a moved page or an unreadable PDF is logged (`com.townhalllive` / `live` in Console) and the previous data stays on screen; nothing blanks or crashes. The warrant PDF is only re-downloaded when its link changes.
- Caches live in the app's Caches directory (`TownHallLive/live_snapshot.json`, `plain_english_cache.json`), so iOS may purge them; the app then falls back to bundled data until the next refresh.

### Setting up `TownSources.plist`

Real source URLs are kept out of git. To point the app at a town:

```sh
cp TownHallLive/Resources/TownSources.example.plist TownHallLive/Resources/TownSources.plist
# edit TownSources.plist, then
xcodegen
```

| Key | Meaning |
| --- | --- |
| `townName`, `state` | Shown in the Live tab header and Settings |
| `websiteBaseURL` | The town website, e.g. `https://www.example-town.gov` |
| `townMeetingPath` | Path of the page that lists each Town Meeting's warrant, results and videos |
| `calendarRSSPath` | Calendar RSS path (CivicPlus: `/RSSFeed.aspx?ModID=58&CID=<category>`) |
| `calendarTitleFilter` | Regex an event title must match to be listed as upcoming |
| `youtubeChannelID` | Town TV channel ID (`UC…`), read via `https://www.youtube.com/feeds/videos.xml?channel_id=…` |
| `recordingTitleFilter` | Regex a video title must match to count as a meeting recording |

`TownSources.plist` is gitignored. If it's missing, or still has the placeholder values, the app runs entirely on bundled data. The website base URL and YouTube channel ID can also be changed in **Settings → Live town data** (stored in `UserDefaults`, overriding the plist). Re-run `xcodegen` after adding the plist so it's included in the bundle.

CI (`.github/workflows/build.yml`) copies the example plist, runs `xcodegen` and builds for the iOS Simulator without signing.

## Data

`TownHallLive/Resources/townhall_data.json` is the offline fallback and the curated layer on top of live data. It contains **real Town data** as of Oct 24, 2026:

- **9 warrant articles** from the official 2026 ATM warrant (town website) — verbatim "To see if the Town…" text, real dollar amounts
- **Official outcomes with real electronic-vote tallies** from the town results sheet (town website) — e.g. Article 8 school assessment approved 364–41; Article 20 logged as "No action taken" (220–48 on the motion)
- **7 documented historical decisions** (2024 $6.6M override, MBTA Communities overlay, Wetherbee Woods purchase, 2025 ADU reform, Gates/ABRHS debt exclusions, water-district PFAS) with sources in CONTEXT.md
- **Real meeting logistics** (May 4–5, 2026, ABRHS Auditorium) and **real Town TV recording URLs** (Town TV Day 1: youtu.be/8mYIVisTVoo)

The demo session replays the actual 2026 meeting in outline, clearly labeled *simulated*.
`officialOutcome.sourceNote` on each record names where the figure comes from; if you refresh the data for next year, replace those per the town clerk's records.

## CAC submission checklist

- [ ] Registration done (personal email, home + school addresses, district) — **deadline Mon Oct 26, 12:00 pm EDT**
- [x] Replace seed data with real Town content — done (official warrant + results, see Data section)
- [ ] Record video on iPhone: 1–3 min — participant name, app name, purpose, target audience, tools/languages (Swift, SwiftUI, OpenAI-compatible runtime AI), showcase all three pillars
- [ ] Disclose AI usage in submission materials
- [ ] One entry per person — submitting solo
