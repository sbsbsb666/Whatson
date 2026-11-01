import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            AccountsSettings()
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
            GallerySettings()
                .tabItem { Label("Galleries", systemImage: "photo.artframe") }
            CinemaSettings()
                .tabItem { Label("Cinemas", systemImage: "film") }
            DataSettings()
                .tabItem { Label("Data", systemImage: "externaldrive") }
            UpdateSettings()
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
        }
        .frame(width: 680, height: 500)
    }
}

private struct AccountsSettings: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                TextField("Username", text: $settings.songkickUsername, prompt: Text("your Songkick username"))
                TextField("Calendar link", text: $settings.songkickICalURL, prompt: Text("Optional — webcal://… or https://….ics"))
                Toggle("Only show London gigs", isOn: $settings.londonOnly)
            } header: {
                Text("Songkick")
            } footer: {
                Text("If gigs don't load from your username alone, copy your calendar subscription link from Songkick and paste it above. Any other gig calendar (.ics) link works too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                TextField("Username", text: $settings.mixcloudUsername, prompt: Text("your Mixcloud username"))
            } header: {
                Text("Mixcloud")
            } footer: {
                Text("The part after mixcloud.com/ in your profile address.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .textFieldStyle(.roundedBorder)
    }
}

private struct GallerySettings: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var model: AppModel
    @State private var selection = Set<GalleryConfig.ID>()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ArtRabbit organisation pages and GalleriesNow listings are the most reliable. For a GalleriesNow listing, the last column filters by postcode or name (e.g. W1S, SW1Y or Zwirner). For a gallery's own site, it's the path its exhibition links start with.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(selection: $selection) {
                ForEach($settings.galleries) { $gallery in
                    HStack(spacing: 8) {
                        Toggle("Show", isOn: $gallery.enabled)
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                        TextField("Name", text: $gallery.name)
                            .frame(width: 150)
                        TextField("Page address", text: $gallery.url)
                        Group {
                            switch gallery.kind {
                            case .artRabbit:
                                TextField("Not needed", text: .constant(""), prompt: Text("—"))
                                    .disabled(true)
                            case .galleriesNow:
                                TextField("Filter", text: $gallery.filter, prompt: Text("W1S, SW1Y…"))
                                    .help("Postcode districts or names, comma-separated. Empty shows everything.")
                            case .website:
                                TextField("Link prefix", text: $gallery.linkPrefix, prompt: Text("/exhibitions/"))
                                    .help("The path each exhibition link starts with, e.g. /whats-on/tate-modern/")
                            }
                        }
                        .frame(width: 140)
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding(.vertical, 2)
                }
                .onMove { settings.galleries.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))

            HStack(spacing: 8) {
                ControlGroup {
                    Button {
                        let new = GalleryConfig(name: "New Gallery", url: "https://www.artrabbit.com/organisations/")
                        settings.galleries.append(new)
                        selection = [new.id]
                    } label: { Image(systemName: "plus") }
                    .help("Add a gallery")
                    Button {
                        settings.galleries.removeAll { selection.contains($0.id) }
                        selection.removeAll()
                    } label: { Image(systemName: "minus") }
                    .disabled(selection.isEmpty)
                    .help("Remove selected")
                }
                .frame(width: 64)
                Spacer()
                Button("Restore Defaults") { settings.galleries = Defaults.galleries }
                Button("Refresh Exhibitions") { Task { await model.refreshExhibitions() } }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}

private struct CinemaSettings: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var search = ""

    private var venues: [CinemaVenueRef] {
        let all = settings.knownCinemaVenues
        let selected = settings.cinemaVenueIDs.compactMap { id -> CinemaVenueRef? in
            all.first(where: { $0.id == id }) ?? Defaults.cinemas.first(where: { $0.id == id })
        }
        let rest = all.filter { !settings.cinemaVenueIDs.contains($0.id) }
        let list = selected + rest
        guard !search.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private func isOn(_ id: String) -> Binding<Bool> {
        Binding(
            get: { settings.cinemaVenueIDs.contains(id) },
            set: { on in
                if on {
                    if !settings.cinemaVenueIDs.contains(id) { settings.cinemaVenueIDs.append(id) }
                } else {
                    settings.cinemaVenueIDs.removeAll { $0 == id }
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Showtimes come from Clusterflick, which covers \(max(settings.knownCinemaVenues.count, 3)) London venues. Ticked cinemas appear in the order you ticked them.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("Search cinemas", text: $search)
                .textFieldStyle(.roundedBorder)
            List {
                ForEach(venues) { venue in
                    Toggle(venue.name, isOn: isOn(venue.id))
                        .toggleStyle(.checkbox)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
        }
        .padding(20)
    }
}

private struct UpdateSettings: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var updater: Updater

    var body: some View {
        Form {
            Section {
                LabeledContent("Installed", value: updater.versionLabel)
                Toggle("Check for updates automatically", isOn: $settings.autoCheckUpdates)
                LabeledContent("Last checked") {
                    Text(updater.lastChecked.map { Fmt.time.string(from: $0) + ", " + Fmt.relativeDay($0) } ?? "Not yet")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Check Now") { Task { await updater.check(userInitiated: true) } }
                        .disabled(!updater.isConfigured)
                }
            }
            Section {
                TextField("Git address", text: $settings.updateRepo, prompt: Text("https://github.com/you/whats-on.git"))
                TextField("Branch", text: $settings.updateBranch, prompt: Text("main"))
            } header: {
                Text("Source")
            } footer: {
                Text("Filled in automatically when the app is built from a git checkout. Updates are rebuilt on this Mac, so they need Apple's command line tools (already installed if you built the app).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .textFieldStyle(.roundedBorder)
    }
}

private struct DataSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Sources") {
                source("Cinema", "Clusterflick open data (updated several times a day)", "Reliable")
                source("Mixcloud", "Official public API", "Reliable")
                source("Gigs", "Songkick calendar export (iCal)", "Fairly reliable")
                source("Exhibitions", "ArtRabbit pages", "May break if ArtRabbit redesigns")
                source("Exhibitions", "Tate and other gallery websites", "Most fragile")
            }
            Section("Cache") {
                LabeledContent("Saved results") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Cache.directory]) }
                }
                LabeledContent("Clear saved results and images") {
                    Button("Clear Cache", role: .destructive) {
                        Cache.clearAll()
                        model.refreshAll()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func source(_ section: String, _ detail: String, _ reliability: String) -> some View {
        LabeledContent {
            Text(reliability).foregroundStyle(.secondary)
        } label: {
            Text(section)
            Text(detail)
        }
    }
}
