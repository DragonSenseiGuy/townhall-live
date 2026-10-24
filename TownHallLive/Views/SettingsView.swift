import SwiftUI

// Endpoint, model, and key all live here — OpenAI-compatible (Hack Club AI by
// default, OpenRouter shape). The key is stored in the Keychain, never in code.
struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var draftURL: String = ""
    @State private var draftModel: String = ""
    @State private var draftKey: String = ""
    @State private var savedNotice = false

    var body: some View {
        Form {
            Section {
                TextField("Base URL", text: $draftURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                TextField("Model", text: $draftModel)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.footnote.monospaced())
            } header: {
                Text("AI endpoint")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Uses any OpenAI-compatible chat-completions endpoint. Default is Hack Club AI — free API keys for students at ai.hackclub.com.")
                    Link("Get a Hack Club AI key", destination: URL(string: "https://ai.hackclub.com")!)
                        .foregroundStyle(Theme.gold)
                }
            }

            Section {
                SecureField("API key", text: $draftKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                    .onSubmit { saveKey() }
                HStack {
                    Button("Save key", action: saveKey)
                        .disabled(draftKey.isEmpty)
                    Spacer()
                    if settings.hasAPIKey || !draftKey.isEmpty {
                        Button("Remove", role: .destructive) {
                            draftKey = ""
                            settings.apiKey = ""
                        }
                    }
                }
                .buttonStyle(.borderless)

                if settings.hasAPIKey && draftKey.isEmpty {
                    Label("Key stored in the Keychain.", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(Theme.green)
                }

                if savedNotice {
                    Label("Saved.", systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.green)
                }
            } footer: {
                Text("The key stays on this device and is never embedded in the app's code. Without a key, every screen still works with bundled plain-English summaries.")
            }

            Section("About") {
                LabeledContent("App", value: "TownHall Live")
                LabeledContent("Pilot town", value: "Town, Massachusetts")
                LabeledContent("Made for", value: "Congressional App Challenge 2026")
                Text("AI disclosure: AI is used to generate plain-English summaries of public warrant articles at runtime, and was used to prepare the bundled example summaries. All legal text remains sourced from public town documents.")
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.parchment.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.parchment, for: .navigationBar)
        .onAppear {
            draftURL = settings.baseURL
            draftModel = settings.model
        }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        if meeting?.status == "live" { LiveBadge() }
                        Spacer()
                        Text(meeting?.date ?? "")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Text(meeting?.title ?? "Meeting")
                        .font(Theme.titleFont)
                        .foregroundStyle(Theme.navy)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                if let url = meeting?.streamURL, let link = URL(string: url) {
                    Link(destination: link) {
                        Label("Watch the session on Town TV", systemImage: "play.rectangle")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.navy)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .card()
                    }
                }

                ForEach(articles) { article in
                    NavigationLink(value: article.id) {
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(article.number)")
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.gold)
                                .frame(width: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(article.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.navy)
                                    .multilineTextAlignment(.leading)
                                HStack(spacing: 6) {
                                    CategoryChip(text: article.category)
                                    if let outcome = article.officialOutcome {
                                        OutcomeChip(result: outcome.result)
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.divider)
                        }
                        .padding(12)
                        .card()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Theme.parchment.ignoresSafeArea())
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
    }
}
