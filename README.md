# TownHall Live

Making Local Democracy and legislation accessible to the common people through education and increased participation for Massachusetts Towns.
**Congressional App Challenge 2026 entry.** Native SwiftUI iOS app; pilot town: Town, MA.

## Setup and run

### Requirements

- A Mac with **Xcode 26** or newer (Swift 6.2+ is needed for default MainActor isolation).
- [Homebrew](https://brew.sh) and **XcodeGen**: `brew install xcodegen`
- For a real iPhone: iOS 18 or newer, a USB cable, and an Apple ID (a free account works).

### 1. Get the code

```sh
git clone https://github.com/DragonSenseiGuy/townhall-live.git
cd townhall-live
```

### 2. Point it at a town (optional)

Without this step the app runs on its bundled data. To read live data from a town's website:

```sh
cp TownHallLive/Resources/TownSources.example.plist TownHallLive/Resources/TownSources.plist
```

Fill in the keys described in [Setting up `TownSources.plist`](#setting-up-townsourcesplist). This file is gitignored: never commit it.

### 3. Generate the Xcode project

```sh
xcodegen
open TownHallLive.xcodeproj
```

The `.xcodeproj` is generated from `project.yml` and isn't checked in. Re-run `xcodegen` after every pull, and after adding or removing files or the plist.

### 4a. Run in the Simulator

Pick the `TownHallLive` scheme, choose an iPhone simulator, press **Cmd+R**.

### 4b. Run on your iPhone

1. Connect the iPhone and unlock it; tap **Trust** if asked.
2. In Xcode select the **TownHallLive** target → **Signing & Capabilities** → check **Automatically manage signing** and pick your **Team** (add your Apple ID under Xcode → Settings → Accounts if none appears).
3. If signing complains the bundle ID is taken, change **Bundle Identifier** to something unique, e.g. `com.yourname.townhalllive`.
4. Choose your iPhone as the run destination and press **Cmd+R**.
5. First time only: on the phone, turn on **Settings → Privacy & Security → Developer Mode** (restarts the phone), then trust the developer profile under **Settings → General → VPN & Device Management**.

With a free Apple ID the install expires after 7 days; just run it again from Xcode.

### 5. Add an AI key (optional)

Plain-English explanations and translations of live content need an AI key. Without one the app still works: articles show the official text with a note to add a key.

1. Get a free student key at [ai.hackclub.com](https://ai.hackclub.com) (or use any OpenAI-compatible provider).
2. In the app open **Settings** (the ☰ button on the Live tab) → **AI endpoint**, paste the key into **API key**, tap **Save key**, and adjust the base URL and model if you're not using the defaults (`https://ai.hackclub.com/proxy/v1`, `openai/gpt-4o-mini`).
3. Open **Warrants**: explanations are written in the background, one article at a time, and cached.

The key is saved in the iOS **Keychain**, never in code or files.

### Updating to the latest version

```sh
git fetch origin
git checkout main
git pull
xcodegen
```

Then in Xcode: **Product → Clean Build Folder** (Shift+Cmd+K), delete the app from the phone or simulator, and run again. Deleting the app clears its caches and settings, but **not** the AI key in the Keychain; remove it in Settings first if you want a true fresh start.

### Troubleshooting

| Problem | Fix |
| --- | --- |
| Old screens or text after pulling | Re-run `xcodegen`, Clean Build Folder, delete the app, run again |
| Build errors about MainActor or concurrency | Use Xcode 26 or newer |
| "No account for team" / signing errors | Pick your Team under Signing & Capabilities; change the bundle ID if it's taken |
| "Untrusted Developer" on the phone | Settings → General → VPN & Device Management → trust your profile |
| App shows only bundled data | Check `TownSources.plist` exists with real values, then re-run `xcodegen` |
| No plain-English text | Add an AI key in Settings → AI endpoint; check your network |
| Explanations or translations stuck | Pull down to refresh, or relaunch the app; failed AI requests retry on relaunch |
| Wrong language | Settings → Language |

### CI

`.github/workflows/build.yml` runs on every push and pull request: it copies the example plist, runs `xcodegen`, builds for the iOS Simulator without signing, and checks that all five languages are compiled.

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
- Live content without AI: recurring shapes in scraped text are localized from the String Catalog by `ContentPatterns` (`LiveData/ContentPatterns.swift`): meeting names composed from parts ("Special Town Meeting - November 25, 2024", board meetings, elections, "Day 2"), outcome labels and tallies, categories, the app's own generated notes, and every parseable date and time (formatted with the chosen locale).
- Live content with AI: with an AI key set and a non-English language chosen, free-form scraped text (recording titles, article titles, curated history notes) is batch-translated in the background through the configured endpoint (one request per ~30 short strings, JSON array in/out) and cached per language + text hash (`text_translations.json`); English shows until a translation arrives. Plain-English explanations are translated the same way (`content_translations.json`). Without a key, free-form content stays in English.
- Official legal text (warrant wording, results excerpts) is never translated: it stays in the original English and is labeled as the official record in the chosen language.

To add a string: use `L("English text")` (or `L("Text with %@", value)`) and add the key with all five translations to `Localizable.xcstrings`.

## AI

- Runtime model calls use **any OpenAI-compatible endpoint** (OpenRouter-style shape).
  Defaults: Hack Club AI (`https://ai.hackclub.com/proxy/v1`, `openai/gpt-4o-mini`).
- Base URL + model live in `UserDefaults`; the API key is entered in **Settings** and stored only in the **Keychain** — never in code.
- **Plain English** on an article is one section, and it is always written by the AI: nothing is prewritten or bundled. The cached AI version is shown when there is one; with a key set, one is written automatically for every article (live and bundled) from its official text; without a key, the section shows only a short note to add one (no summary, takeaways or yes/no text); the official text stays below. A small **Regenerate with AI** button is available with a key.
- Without a key the app stays fully functional.
- AI disclosure for the CAC submission: AI writes every plain-English explanation at runtime from the public warrant text; the app ships no prewritten explanations. All official text remains attributed to public town documents.

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
- Live data overrides bundled data article by article. Bundled vote counts (only when they agree with the live result) and the curated History entries stay bundled; plain English never comes from the bundle.
- **History** loads lazily when the tab opens: the archive listing is re-read at most daily, each abstract PDF is downloaded and parsed once (newest first, published as it goes) and cached in `history_archive_v2.json`. PDFs without extractable text are skipped and retried weekly. Pull down on History to re-read the archive.
- **Plain English:** with an AI key set, every article shown (live warrant articles and bundled ones) is written up in the background from its official text through the configured OpenAI-compatible endpoint, one article per request, and cached on disk by a hash of that text. A reply that can't be read is retried (up to 3 tries per article), network failures back off and retry, and each article appears as soon as its version arrives. Without a key, no plain-English version is shown at all, just a note to add a key in Settings; the dollar figure and vote requirement still appear in their own places.
- **Offline / failures:** every source is fetched and parsed independently. A network error, a moved page or an unreadable PDF is logged (`com.townhalllive` / `live` in Console) and the previous data stays on screen; nothing blanks or crashes. The warrant PDF is only re-downloaded when its link changes.
- Caches live in the app's Caches directory (`TownHallLive/live_snapshot_v2.json`, `plain_english_cache.json`, `content_translations.json`, `text_translations.json`, `history_archive_v2.json`), so iOS may purge them; the app then falls back to bundled data until the next refresh. Unknown keys in older caches or bundles are ignored when decoding.

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

## Data

`TownHallLive/Resources/townhall_data.json` is the offline fallback under live data. It holds facts only (official text, outcomes, meetings, history), never plain-English explanations. It contains **real Town data** as of Oct 24, 2026:

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
