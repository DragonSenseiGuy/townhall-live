import SwiftUI

// Endpoint, model, and key all live here — OpenAI-compatible (Hack Club AI by
// default, OpenRouter shape). The key is stored in the Keychain, never in code.
struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var draftURL: String = ""
    @State private var draftModel: String = ""
    @State private var draftKey: String = ""
    @State private var savedNotice = false
    @State private var draftWebsite: String = ""
    @State private var draftChannel: String = ""
    @State private var sourcesSaved = false

    var body: some View {
        Form {
            Section {
                Picker(L("Language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(verbatim: language.nativeName).tag(language)
                    }
                }
            } header: {
                Text(L("Language"))
            } footer: {
                Text(L("Changes the whole app right away, including meeting names, outcomes and dates. With an AI key, titles and plain-English explanations are translated too; official legal text stays in English."))
            }

            Section {
                TextField(L("Base URL"), text: $draftURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                TextField(L("Model"), text: $draftModel)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.footnote.monospaced())
            } header: {
                Text(L("AI endpoint"))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Uses any OpenAI-compatible chat-completions endpoint. Default is Hack Club AI — free API keys for students at ai.hackclub.com."))
                    Link(L("Get a Hack Club AI key"), destination: URL(string: "https://ai.hackclub.com")!)
                        .foregroundStyle(Theme.accent)
                }
            }

            Section {
                SecureField(L("API key"), text: $draftKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                    .onSubmit { saveKey() }
                HStack {
                    Button(L("Save key"), action: saveKey)
                        .disabled(draftKey.isEmpty)
                    Spacer()
                    if settings.hasAPIKey || !draftKey.isEmpty {
                        Button(L("Remove"), role: .destructive) {
                            draftKey = ""
                            settings.apiKey = ""
                        }
                    }
                }
                .buttonStyle(.borderless)

                if settings.hasAPIKey && draftKey.isEmpty {
                    Label(L("Key stored in the Keychain."), systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(Theme.green)
                }

                if savedNotice {
                    Label(L("Saved."), systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.green)
                }
            } footer: {
                Text(L("The key stays on this device and is never embedded in the app's code. Without a key, every screen still works; articles without a curated summary show the warrant booklet's own summary."))
            }

            Section {
                TextField(L("Town website (https://…)"), text: $draftWebsite)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                TextField(L("Town TV YouTube channel ID (UC…)"), text: $draftChannel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                HStack {
                    Button(L("Save sources"), action: saveSources)
                    Spacer()
                    if sourcesSaved {
                        Label(L("Saved."), systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(Theme.green)
                    }
                }
                .buttonStyle(.borderless)
            } header: {
                Text(L("Live town data"))
            } footer: {
                Text(L("Warrants, results, past decisions, meetings and Town TV recordings are read on this device from the town's public website and YouTube channel. Leave a field blank to use the app's TownSources.plist. Pull down on any tab to refresh; without a connection the app shows the last saved data."))
            }

            Section(L("About")) {
                LabeledContent(L("App"), value: "TownHall Live")
                LabeledContent(L("Pilot town"), value: "\(TownSources.current().townName ?? L("Town")), \(L(TownSources.current().state ?? "Massachusetts"))")
                LabeledContent(L("Made for"), value: "Congressional App Challenge 2026")
                Text(L("AI disclosure: AI is used to write plain-English summaries of public warrant articles and to translate them at runtime, and was used to prepare the bundled summaries. All legal text remains sourced from public town documents."))
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle(L("Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .sensoryFeedback(.success, trigger: savedNotice)
        .onAppear {
            draftURL = settings.baseURL
            draftModel = settings.model
            let current = TownSources.current()
            draftWebsite = settings.townWebsiteOverride.isEmpty
                ? (current.websiteBaseURL?.absoluteString ?? "") : settings.townWebsiteOverride
            draftChannel = settings.youtubeChannelOverride.isEmpty
                ? (current.youtubeChannelID ?? "") : settings.youtubeChannelOverride
        }
    }

    private func saveSources() {
        // Store an override only when it differs from the bundled config.
        settings.townWebsiteOverride = ""
        settings.youtubeChannelOverride = ""
        let bundled = TownSources.current()
        let website = draftWebsite.trimmingCharacters(in: .whitespacesAndNewlines)
        let channel = draftChannel.trimmingCharacters(in: .whitespacesAndNewlines)
        if website != (bundled.websiteBaseURL?.absoluteString ?? "") { settings.townWebsiteOverride = website }
        if channel != (bundled.youtubeChannelID ?? "") { settings.youtubeChannelOverride = channel }
        sourcesSaved = true
        withAnimation(.easeOut(duration: 0.4).delay(1.2)) { sourcesSaved = false }
    }

    private func saveKey() {
        guard !draftKey.isEmpty else { return }
        if draftURL.isEmpty { draftURL = settings.baseURL }
        if draftModel.isEmpty { draftModel = settings.model }
        settings.baseURL = draftURL
        settings.model = draftModel
        settings.apiKey = draftKey
        draftKey = ""
        savedNotice = true
        // Confirmation haptic fires with the green "Saved." label.
        withAnimation(.easeOut(duration: 0.4).delay(1.2)) { savedNotice = false }
    }
}

struct MeetingDetailView: View {
    let store: DataStore
    let meetingID: String

    private var meeting: Meeting? { store.meeting(id: meetingID) }

    private var articles: [WarrantArticle] {
        store.articles.filter { $0.meetingID == meetingID }.sorted { $0.number < $1.number }
    }

    var body: some View {
        VerticalPage {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(dateLineText(meeting?.date ?? ""))
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(meeting.map { meetingNameText($0.title) } ?? L("Meeting"))
                        .font(Theme.titleFont)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                if let url = meeting?.streamURL, let link = URL(string: url) {
                    Link(destination: link) {
                        Label(L("Watch the session on Town TV"), systemImage: "play.rectangle")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .card()
                    }
                    .pressable()
                }

                ForEach(articles) { article in
                    NavigationLink(value: article.id) {
                        HStack(alignment: .top, spacing: 12) {
                            Text(verbatim: "\(article.number)")
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.accent)
                                .frame(width: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LT(article.title))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.ink)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 6) {
                                    CategoryChip(text: article.category)
                                    if let outcome = article.officialOutcome {
                                        OutcomeChip(result: outcome.result)
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.inkSecondary.opacity(0.5))
                        }
                        .padding(12)
                        .card()
                    }
                    .pressable()
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle(L("Session"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
    }
}
