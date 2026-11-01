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
        .frame(width: 700, height: 580)
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
    enum Pane: String, CaseIterable { case westEnd = "West End Galleries", others = "Museums & Other Galleries" }
    @State private var pane: Pane = .westEnd

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Show", selection: $pane) {
                ForEach(Pane.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)

            switch pane {
            case .westEnd: WestEndSettings()
            case .others: OtherGallerySettings()
            }
        }
        .padding(20)
    }
}

/// Every private gallery on GalleriesNow's West End page, as a checklist grouped by area.
private struct WestEndSettings: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var search = ""

    private static let areaOrder = ["Mayfair", "St James’s", "Regent Street", "Soho", "Fitzrovia", "Marylebone"]

    private var groups: [(area: String, galleries: [WestEndGallery])] {
        let list = settings.westEndCatalogue.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        let grouped = Dictionary(grouping: list, by: \.area)
        return grouped.keys.sorted { a, b in
            let ia = Self.areaOrder.firstIndex(of: a) ?? 99, ib = Self.areaOrder.firstIndex(of: b) ?? 99
            return ia == ib ? a < b : ia < ib
        }.map { (area: $0, galleries: grouped[$0] ?? []) }
    }

    private func isOn(_ name: String) -> Binding<Bool> {
        Binding(
            get: { settings.westEndSelected.contains(name) },
            set: { on in
                if on {
                    if !settings.westEndSelected.contains(name) { settings.westEndSelected.append(name) }
                } else {
                    settings.westEndSelected.removeAll { $0 == name }
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Private galleries around Mayfair and St James’s. Shows come from one GalleriesNow page; new galleries appear here automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("Search galleries", text: $search)
                    .textFieldStyle(.roundedBorder)
                Menu("Select") {
                    Button("Around Grafton Street") { settings.westEndSelected = Defaults.westEndSelected }
                    Button("All of Mayfair & St James’s") {
                        settings.westEndSelected = settings.westEndCatalogue
                            .filter { ["Mayfair", "St James’s", "Regent Street"].contains($0.area) }.map(\.name)
                    }
                    Button("Everything in the West End") { settings.westEndSelected = settings.westEndCatalogue.map(\.name) }
                    Divider()
                    Button("None") { settings.westEndSelected = [] }
                }
                .fixedSize()
            }
            List {
                ForEach(groups, id: \.area) { group in
                    Section(group.area) {
                        ForEach(group.galleries) { gallery in
                            Toggle(isOn: isOn(gallery.name)) {
                                Text(gallery.name)
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            Text("\(settings.westEndSelected.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// ArtRabbit pages, museum sites and any other listing — add, edit and remove via a sheet.
private struct OtherGallerySettings: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var model: AppModel
    @State private var selection: GalleryConfig.ID?
    @State private var editing: GalleryConfig?
    @State private var isNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            List(selection: $selection) {
                ForEach($settings.galleries) { $gallery in
                    HStack(spacing: 10) {
                        Toggle("Show", isOn: $gallery.enabled)
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(gallery.name.isEmpty ? "Untitled" : gallery.name)
                            Text(subtitle(gallery))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .tag(gallery.id)
                }
                .onMove { settings.galleries.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            // Right-click for Edit/Remove; double-click a row to edit it.
            .contextMenu(forSelectionType: GalleryConfig.ID.self) { ids in
                if let id = ids.first, let g = settings.galleries.first(where: { $0.id == id }) {
                    Button("Edit…") { edit(g) }
                    Button("Remove", role: .destructive) { remove(id) }
                }
            } primaryAction: { ids in
                if let id = ids.first, let g = settings.galleries.first(where: { $0.id == id }) { edit(g) }
            }

            HStack(spacing: 4) {
                Button {
                    isNew = true
                    editing = GalleryConfig(name: "", url: "")
                } label: { Image(systemName: "plus").frame(width: 18, height: 16) }
                .help("Add a gallery")
                Button {
                    if let id = selection { remove(id) }
                } label: { Image(systemName: "minus").frame(width: 18, height: 16) }
                .disabled(selection == nil)
                .help("Remove the selected gallery")
                Button("Edit…") {
                    if let id = selection, let g = settings.galleries.first(where: { $0.id == id }) { edit(g) }
                }
                .disabled(selection == nil)
                Spacer()
                Button("Restore Defaults") { settings.galleries = Defaults.galleries }
            }
            .buttonStyle(.bordered)
        }
        .sheet(item: $editing) { draft in
            GalleryEditor(draft: draft, isNew: isNew) { saved in
                if let i = settings.galleries.firstIndex(where: { $0.id == saved.id }) {
                    settings.galleries[i] = saved
                } else {
                    settings.galleries.append(saved)
                }
                selection = saved.id
            }
        }
    }

    private func edit(_ g: GalleryConfig) {
        isNew = false
        editing = g
    }

    private func remove(_ id: GalleryConfig.ID) {
        settings.galleries.removeAll { $0.id == id }
        if selection == id { selection = nil }
    }

    private func subtitle(_ g: GalleryConfig) -> String {
        let host = URL(string: g.url)?.host?.replacingOccurrences(of: "www.", with: "") ?? g.url
        switch g.kind {
        case .artRabbit: return "ArtRabbit"
        case .galleriesNow: return g.filter.isEmpty ? "GalleriesNow" : "GalleriesNow · \(g.filter)"
        case .website: return host
        }
    }
}

private struct GalleryEditor: View {
    @State var draft: GalleryConfig
    let isNew: Bool
    let onSave: (GalleryConfig) -> Void
    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty &&
        URL(string: draft.url.trimmingCharacters(in: .whitespaces))?.scheme?.hasPrefix("http") == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Add Gallery" : "Edit Gallery").font(.headline)
            Form {
                TextField("Name", text: $draft.name, prompt: Text("e.g. Camden Art Centre"))
                TextField("Page address", text: $draft.url, prompt: Text("https://www.artrabbit.com/organisations/…"))
                switch draft.kind {
                case .artRabbit:
                    EmptyView()
                case .galleriesNow:
                    TextField("Filter", text: $draft.filter, prompt: Text("W1S, SW1Y or gallery names"))
                case .website:
                    TextField("Link prefix", text: $draft.linkPrefix, prompt: Text("/exhibitions/"))
                }
            }
            .formStyle(.columns)
            .textFieldStyle(.roundedBorder)

            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") {
                    draft.name = draft.name.trimmingCharacters(in: .whitespaces)
                    draft.url = draft.url.trimmingCharacters(in: .whitespaces)
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var hint: String {
        switch draft.kind {
        case .artRabbit:
            return "ArtRabbit page — most reliable. Find the gallery on artrabbit.com and paste its organisation page address."
        case .galleriesNow:
            return "GalleriesNow listing. The filter keeps shows from these postcode districts or galleries (comma-separated); leave it empty for everything."
        case .website:
            return "Tip: search artrabbit.com for the gallery first — its page is far more reliable. For a gallery's own site, paste its exhibitions page, and as link prefix the path every exhibition link starts with."
        }
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
