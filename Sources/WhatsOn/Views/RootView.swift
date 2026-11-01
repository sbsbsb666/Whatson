import SwiftUI

enum Destination: String, CaseIterable, Identifiable {
    case today, exhibitions, gigs, cinema, substack, mixcloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .exhibitions: return "Exhibitions"
        case .gigs: return "Gigs"
        case .mixcloud: return "Mixcloud"
        case .cinema: return "Cinema"
        case .substack: return "Substack"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "sun.max"
        case .exhibitions: return "photo.artframe"
        case .gigs: return "music.mic"
        case .mixcloud: return "waveform"
        case .cinema: return "film"
        case .substack: return "text.book.closed"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updater: Updater
    @State private var selection: Destination? = .today

    private var destination: Destination { selection ?? .today }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label(Destination.today.title, systemImage: Destination.today.symbol)
                    .tag(Destination.today)
                Section("Going Out") {
                    ForEach([Destination.exhibitions, .gigs, .cinema]) { d in
                        Label(d.title, systemImage: d.symbol)
                            .badge(badgeCount(for: d))
                            .tag(d)
                    }
                }
                Section("Reading & Listening") {
                    ForEach([Destination.substack, .mixcloud]) { d in
                        Label(d.title, systemImage: d.symbol)
                            .badge(badgeCount(for: d))
                            .tag(d)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                UpdateBanner()
            }
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { RefreshButton() }
        }
        .environment(\.navigate) { selection = $0 }
        .sheet(isPresented: $updater.showSheet) {
            UpdateSheet().environmentObject(updater)
        }
    }

    @ViewBuilder private var detail: some View {
        switch destination {
        case .today: TodayView()
        case .exhibitions: ExhibitionsView()
        case .gigs: GigsView()
        case .mixcloud: MixcloudView()
        case .cinema: CinemaView()
        case .substack: SubstackView()
        }
    }

    /// Small counts in the sidebar: gigs this week, mixes from the last day.
    private func badgeCount(for d: Destination) -> Int {
        switch d {
        case .gigs:
            let cal = Calendar.london
            let weekEnd = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: model.now))!
            return model.gigs.items.filter { $0.date < weekEnd }.count
        case .mixcloud:
            return model.mixes.items.filter { model.now.timeIntervalSince($0.date) < 86_400 }.count
        case .substack:
            return model.substack.items.filter { model.now.timeIntervalSince($0.date) < 86_400 }.count
        default:
            return 0
        }
    }
}

struct RefreshButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button {
            model.refreshAll()
        } label: {
            if model.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .help("Refresh all sections (⌘R)")
        .disabled(model.isRefreshing)
    }
}
