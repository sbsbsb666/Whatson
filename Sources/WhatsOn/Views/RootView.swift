import SwiftUI

enum Destination: String, CaseIterable, Identifiable {
    case today, exhibitions, gigs, mixcloud, cinema

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .exhibitions: return "Exhibitions"
        case .gigs: return "Gigs"
        case .mixcloud: return "Mixcloud"
        case .cinema: return "Cinema"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "sun.max"
        case .exhibitions: return "photo.artframe"
        case .gigs: return "music.mic"
        case .mixcloud: return "waveform"
        case .cinema: return "film"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updater: Updater
    @SceneStorage("destination") private var destinationRaw = Destination.today.rawValue

    private var destination: Destination { Destination(rawValue: destinationRaw) ?? .today }

    private var selection: Binding<Destination?> {
        Binding(get: { destination },
                set: { if let d = $0 { destinationRaw = d.rawValue } })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                NavigationLink(value: Destination.today) {
                    Label(Destination.today.title, systemImage: Destination.today.symbol)
                }
                Section("London") {
                    ForEach([Destination.exhibitions, .gigs, .mixcloud, .cinema]) { d in
                        NavigationLink(value: d) {
                            Label(d.title, systemImage: d.symbol)
                        }
                        .badge(badgeCount(for: d))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                UpdateBanner()
                    .animation(.spring(response: 0.35, dampingFraction: 0.9), value: updater.phase)
            }
        } detail: {
            detail
                .id(destination)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.18), value: destination)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { RefreshButton() }
        }
        .environment(\.navigate) { destinationRaw = $0.rawValue }
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
