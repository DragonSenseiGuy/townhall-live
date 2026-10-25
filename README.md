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

## Data

`TownHallLive/Resources/townhall_data.json` contains **real Town data** as of Oct 24, 2026:

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
