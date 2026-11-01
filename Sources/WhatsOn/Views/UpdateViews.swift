import SwiftUI
import AppKit

/// Sheet shown for "Check for Updates…" and when installing.
struct UpdateSheet: View {
    @EnvironmentObject private var updater: Updater
    @Environment(\.dismiss) private var dismiss
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline).font(.headline)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            switch updater.phase {
            case .available:
                if !updater.changes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What’s new").font(.subheadline.weight(.semibold))
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(updater.changes, id: \.self) { change in
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text("•").foregroundStyle(.secondary)
                                        Text(change)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                        }
                        .frame(maxHeight: 140)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            case .installing:
                ProgressView().progressViewStyle(.linear)
                DisclosureGroup("Details", isExpanded: $showLog) {
                    ScrollView {
                        Text(updater.log)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 140)
                    .defaultScrollAnchor(.bottom)
                }
            case .failed:
                if !updater.log.isEmpty {
                    DisclosureGroup("Details", isExpanded: $showLog) {
                        ScrollView {
                            Text(updater.log).font(.caption.monospaced()).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 140)
                        .defaultScrollAnchor(.bottom)
                    }
                }
            default:
                EmptyView()
            }

            HStack {
                if needsSetup {
                    SettingsLink { Text("Open Settings…") }
                }
                Spacer()
                switch updater.phase {
                case .available:
                    Button("Later") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Install and Relaunch") { Task { await updater.install() } }
                        .keyboardShortcut(.defaultAction)
                case .installing:
                    Button("Hide") { dismiss() }
                case .checking:
                    ProgressView().controlSize(.small)
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                default:
                    Button("OK") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 440)
        .animation(.easeInOut(duration: 0.2), value: updater.phase)
    }

    private var needsSetup: Bool {
        if case .failed = updater.phase { return !updater.isConfigured }
        return false
    }

    private var headline: String {
        switch updater.phase {
        case .idle, .checking: return "Checking for updates…"
        case .upToDate: return "What’s On is up to date"
        case .available: return "A new version of What’s On is available"
        case .installing: return "Updating What’s On…"
        case .failed: return "Couldn’t update"
        }
    }

    private var detail: String {
        switch updater.phase {
        case .idle, .checking: return updater.versionLabel
        case .upToDate: return "You’re running the latest version. \(updater.versionLabel)."
        case .available: return "It will be built on this Mac and the app will reopen when it’s ready."
        case .installing: return "Building the new version. The app will quit and reopen by itself."
        case .failed(let message): return message
        }
    }
}

/// Quiet card at the bottom of the sidebar when an update is waiting.
struct UpdateBanner: View {
    @EnvironmentObject private var updater: Updater

    var body: some View {
        if updater.updateAvailable || updater.phase == .installing {
            Button {
                updater.showSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: updater.phase == .installing ? "arrow.triangle.2.circlepath" : "arrow.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.pulse, isActive: updater.phase == .installing)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(updater.phase == .installing ? "Updating…" : "Update available")
                            .font(.callout.weight(.semibold))
                        Text(updater.phase == .installing ? "The app will reopen" : "Click to install")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
