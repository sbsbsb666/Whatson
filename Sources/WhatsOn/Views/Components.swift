import SwiftUI
import AppKit

enum Layouts {
    static let cards = [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: 22, alignment: .top)]
    static let squares = [GridItem(.adaptive(minimum: 160, maximum: 230), spacing: 20, alignment: .top)]
    static let gigCards = [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 14, alignment: .top)]
    static let pagePadding: CGFloat = 28
}

// MARK: - Navigation between sections (used by "See All")

private struct NavigateKey: EnvironmentKey {
    static let defaultValue: (Destination) -> Void = { _ in }
}

extension EnvironmentValues {
    var navigate: (Destination) -> Void {
        get { self[NavigateKey.self] }
        set { self[NavigateKey.self] = newValue }
    }
}

// MARK: - Images

struct RemoteImage: View {
    let url: URL?
    var symbol = "photo"
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.primary.opacity(0.06))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            let loaded = await ImageLoader.shared.image(for: url)
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        }
    }
}

/// Fixed-aspect, rounded artwork tile.
struct Artwork: View {
    let url: URL?
    var aspect: CGFloat = 3 / 2
    var symbol = "photo"
    var cornerRadius: CGFloat = 10

    var body: some View {
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay { RemoteImage(url: url, symbol: symbol) }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 3)
    }
}

struct Badge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Buttons

/// Cards lift slightly on hover and settle on press.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { CardBody(configuration: configuration) }

    private struct CardBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.985 : (hovering ? 1.012 : 1))
                .animation(.spring(response: 0.28, dampingFraction: 0.86), value: hovering)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}

/// List rows get a soft highlight on hover instead of scaling.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { RowBody(configuration: configuration) }

    private struct RowBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .background(Color.primary.opacity(configuration.isPressed ? 0.09 : (hovering ? 0.045 : 0)))
                .animation(.easeOut(duration: 0.12), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

/// Anything clickable that opens a link in the default browser.
struct LinkButton<Label: View>: View {
    let url: URL?
    var row = false
    @ViewBuilder let label: () -> Label
    @Environment(\.openURL) private var openURL

    var body: some View {
        if row {
            button.buttonStyle(RowButtonStyle())
        } else {
            button.buttonStyle(CardButtonStyle())
        }
    }

    private var button: some View {
        Button {
            if let url { openURL(url) }
        } label: {
            label().contentShape(Rectangle())
        }
        .disabled(url == nil)
        .help(url?.host.map { "Open \($0.replacingOccurrences(of: "www.", with: ""))" } ?? "")
        .contextMenu {
            if let url {
                Button("Open in Browser") { openURL(url) }
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }
        }
    }
}

// MARK: - Headers & status

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.weight(.semibold))
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.link)
                    .font(.callout)
            }
        }
    }
}

/// Shown above content when a refresh failed but cached results are still on screen,
/// or when some sources within a section failed.
struct StatusBanner<T: Codable>: View {
    let state: SectionState<T>
    let retry: () -> Void
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let error = state.error {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Couldn't load").font(.callout.weight(.semibold))
                    Text("\(error) Showing results from \(model.relative(state.fetchedAt)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Retry", action: retry).controlSize(.small)
            }
            .padding(12)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
        if !state.warnings.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(state.warnings, id: \.self) { w in
                        Text(w).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            } label: {
                Label(state.warnings.count == 1 ? "1 note" : "\(state.warnings.count) notes", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Wraps a section: empty / loading / error / setup states, then a scrolling page.
struct SectionPage<T: Codable, Content: View>: View {
    let title: String
    let symbol: String
    let state: SectionState<T>
    let retry: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if state.items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        StatusBanner(state: state, retry: retry)
                        content()
                    }
                    .padding(Layouts.pagePadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.items.isEmpty)
    }

    @ViewBuilder private var emptyState: some View {
        if let setup = state.setupMessage {
            ContentUnavailableView {
                Label(title, systemImage: symbol)
            } description: {
                Text(setup)
            } actions: {
                SettingsLink { Text("Open Settings…") }
            }
        } else if state.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading \(title)…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = state.error {
            ContentUnavailableView {
                Label("Couldn't Load \(title)", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again", action: retry)
            }
        } else if state.fetchedAt != nil {
            ContentUnavailableView {
                Label("Nothing Listed", systemImage: symbol)
            } description: {
                Text(state.warnings.first ?? "There's nothing to show right now.")
            }
        } else {
            ContentUnavailableView {
                Label(title, systemImage: symbol)
            } description: {
                Text("Not loaded yet.")
            } actions: {
                Button("Load Now", action: retry)
            }
        }
    }
}

// MARK: - Calendar-style date block

struct DateBlock: View {
    let date: Date
    var highlighted = false

    var body: some View {
        VStack(spacing: 0) {
            Text(Fmt.weekdayShort.string(from: date).uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(highlighted ? Color.red : Color.secondary)
            Text(Fmt.dayNumber.string(from: date))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
        }
        .frame(width: 48, height: 50)
        .background(.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}

// MARK: - Wrapping layout for showtime pills

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        let width = (proposal.width.map { $0.isFinite ? $0 : widest }) ?? widest
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
