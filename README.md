# TownHall Live

Preserving Civic History & Demystifying Local Democracy for Massachusetts Towns.
**Congressional App Challenge 2026 entry.** Native SwiftUI iOS app; pilot town: Town, MA.

## Run it

```sh
xcodegen          # generates TownHallLive.xcodeproj from project.yml
open TownHallLive.xcodeproj
```

Pick the `TownHallLive` scheme, choose the iPhone simulator (or your device),
Cmd+R. Everything works offline — no backend, no key.

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

## Data — READ BEFORE RECORDING YOUR VIDEO

`TownHallLive/Resources/townhall_data.json` currently contains **placeholder seed data written in the style of real Town warrant articles**. Before submission you should replace it with real scraped content, since CAC judges may request the app and source and verify claims:

- Real warrant text: the Town warrant PDF(s) from the town's website (town-ma.gov)
- Real outcomes/tallies: Town Meeting minutes
- Real history: past meeting minutes/records (Town Exchange, townexchange.org, is a good secondary source)
- Confirm the Town TV YouTube channel URL is correct

Each record's `officialOutcome.sourceNote` marks where the town-clerk figure should go.

## CAC submission checklist

- [ ] Registration done (personal email, home + school addresses, district) — **deadline Mon Oct 26, 12:00 pm EDT**
- [ ] Replace seed data with real Town content
- [ ] Record video on iPhone: 1–3 min — participant name, app name, purpose, target audience, tools/languages (Swift, SwiftUI, OpenAI-compatible runtime AI), showcase all three pillars
- [ ] Disclose AI usage in submission materials
- [ ] One entry per person — submitting solo
