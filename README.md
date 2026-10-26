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
| **Live** | What's happening now: the next scheduled meeting from the town calendar (or a plain "No Town Meeting scheduled. Annual Town Meeting is held each spring."), the latest meeting recordings from the Town TV YouTube channel (Select Board and other boards), and a compact **Last Town Meeting · <date>** card with its outcomes that links into Warrants |
| **Warrants** | The full library of warrant articles, grouped by Town Meeting. Each article shows one **In plain English** section, the **Official text** right below it, financial impact, the official outcome next to the reader's own **Where do you stand?** (Yay / Nay / Abstain, saved only on the phone), and "synced with history" links |
| **History** | Every past Town Meeting decision the town's results archive has in readable form (back to 2018 by default), merged with curated entries that explain why a decision still matters. Searchable, filterable by year |

Every screen scrolls vertically only: page content is pinned to the scroll view's width (`VerticalPage` in `Theme.swift`), so nothing can make a page pan sideways.

## Languages

English, Simplified Chinese, Spanish, Hindi and Arabic. **Settings → Language** switches the whole interface immediately, inside the app:

- The choice is stored in `UserDefaults` (`app.language`); on first launch the app picks the first supported language from the device's preferred languages.
- UI strings live in `TownHallLive/Localizable.xcstrings` (String Catalog, keys maintained by hand). Views look them up through `L("…")` (`Localization.swift`), which reads the chosen language's compiled table from the bundle, so changes apply on the next render.
- The root view sets `\.locale` (dates, relative times) and `\.layoutDirection` — Arabic renders right-to-left.
- Content: with an AI key set and a non-English language chosen, plain-English explanations are translated into that language through the configured endpoint and cached per language + text hash (`content_translations.json`). Without a key, content stays in English while the interface uses the chosen language.

To add a string: use `L("English text")` (or `L("Text with %@", value)`) and add the key with all five translations to `Localizable.xcstrings`.

## AI

- Runtime model calls use **any OpenAI-compatible endpoint** (OpenRouter-style shape).
  Defaults: Hack Club AI (`https://ai.hackclub.com/proxy/v1`, `openai/gpt-4o-mini`).
- Base URL + model live in `UserDefaults`; the API key is entered in **Settings** and stored only in the **Keychain** — never in code.
- **Plain English** on an article is one section: the curated summary bundled with the app when there is one, otherwise the cached AI version, otherwise one is written automatically when a key is set, otherwise the warrant booklet's own summary with a small note. A small **Regenerate with AI** button is available with a key.
- Without a key the app stays fully functional.
- AI disclosure for the CAC submission: AI generates runtime plain-English translations of public warrant text, and was used to prepare bundled example summaries. All official text remains attributed to public town documents.

## Live data

The app reads the town's own public sources **on the phone** — no backend:

| Source | What the app takes from it | Where it shows |
| --- | --- | --- |
| Town Meeting page on the town website (CivicPlus/CivicEngage) | One block per "<year> Annual/Special Town Meeting": links to the warrant booklet, the results summary, and the session videos | Live tab (last Town Meeting), Warrants tab headers, "Watch on Town TV" |
| Warrant booklet PDF (read with PDFKit) | Each `Article N:` — title, vote requirement, verbatim "To see if the Town…" text, dollar figures, the booklet's own summary and board recommendations | Warrants tab, article detail ("Original warrant text", financial impact) |
| Results summary PDF | Outcome per article (Approved / Not approved / No action / Postponed, plus a count when the sheet prints one) | Outcome chips and "Official outcome" |
| Town calendar RSS | Upcoming sessions whose title matches a filter (default "Town Meeting") | Live tab → Next meeting |
| Town TV YouTube channel feed | Recent videos whose title matches a filter (default "Meeting") | Live tab → Latest meeting recordings |
| Results archive (CivicPlus Archive Center, `Archive.aspx?AMID=…`) | Every past results abstract PDF since `historyFromYear`: per article title, outcome (passed / failed / no action / postponed) and the electronic-vote count when printed | History tab |
| Warrants archive | Past warrant PDFs, read only when a results abstract leaves article titles out | History tab (titles) |

**How it behaves**

- Launch shows the last saved live data (or the bundled JSON) instantly, then refreshes in the background. Pull down on any tab to refresh; the app also refreshes when it comes back to the foreground after 30 minutes. A small "Updated X ago" line shows freshness.
- Live data overrides bundled data article by article. Curated plain-English summaries, curated vote counts (only when they agree with the live result) and the curated History entries stay bundled.
- **History** loads lazily when the tab opens: the archive listing is re-read at most daily, each abstract PDF is downloaded and parsed once (newest first, published as it goes) and cached in `history_archive_v1.json`. PDFs without extractable text are skipped and retried weekly. Pull down on History to re-read the archive.
- **Plain English:** with an AI key set, scraped articles that have no curated summary are translated in the background through the configured OpenAI-compatible endpoint and cached on disk by a hash of the article text. Without a key, the app shows the booklet's own summary (first sentences), the dollar figure and vote requirement, clearly marked *not translated yet*.
- **Offline / failures:** every source is fetched and parsed independently. A network error, a moved page or an unreadable PDF is logged (`com.townhalllive` / `live` in Console) and the previous data stays on screen; nothing blanks or crashes. The warrant PDF is only re-downloaded when its link changes.
- Caches live in the app's Caches directory (`TownHallLive/live_snapshot.json`, `plain_english_cache.json`, `content_translations.json`, `history_archive_v1.json`), so iOS may purge them; the app then falls back to bundled data until the next refresh. Unknown keys in older caches or bundles are ignored when decoding.

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
| `resultsArchivePath` | Archive Center listing of past results abstracts, e.g. `/Archive.aspx?AMID=<id>` |
| `warrantsArchivePath` | Archive Center listing of past warrants (titles fallback) |
| `historyFromYear` | Oldest year the History tab reads (default 2018) |

`TownSources.plist` is gitignored. If it's missing, or still has the placeholder values, the app runs entirely on bundled data. The website base URL and YouTube channel ID can also be changed in **Settings → Live town data** (stored in `UserDefaults`, overriding the plist). Re-run `xcodegen` after adding the plist so it's included in the bundle.

CI (`.github/workflows/build.yml`) copies the example plist, runs `xcodegen` and builds for the iOS Simulator without signing.

## Data

`TownHallLive/Resources/townhall_data.json` is the offline fallback and the curated layer on top of live data. It contains **real Town data** as of Oct 24, 2026:

- **9 warrant articles** from the official 2026 ATM warrant (town website) — verbatim "To see if the Town…" text, real dollar amounts
- **Official outcomes with real electronic-vote tallies** from the town results sheet (town website) — e.g. Article 8 school assessment approved 364–41; Article 20 logged as "No action taken" (220–48 on the motion)
- **7 curated historical decisions** (2024 $6.6M override, MBTA Communities overlay, Wetherbee Woods purchase, 2025 ADU reform, Gates/ABRHS debt exclusions, water-district PFAS) with sources in CONTEXT.md
- **Real meeting logistics** (May 4–5, 2026, ABRHS Auditorium) and **real Town TV recording URLs** (Town TV Day 1: youtu.be/8mYIVisTVoo)

`officialOutcome.sourceNote` on each record names where the figure comes from; if you refresh the data for next year, replace those per the town clerk's records.

## CAC submission checklist

- [ ] Registration done (personal email, home + school addresses, district) — **deadline Mon Oct 26, 12:00 pm EDT**
- [x] Replace seed data with real Town content — done (official warrant + results, see Data section)
- [ ] Record video on iPhone: 1–3 min — participant name, app name, purpose, target audience, tools/languages (Swift, SwiftUI, OpenAI-compatible runtime AI), showcase all three tabs and the language switch
- [ ] Disclose AI usage in submission materials
- [ ] One entry per person — submitting solo
