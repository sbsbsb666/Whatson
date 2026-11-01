import Foundation
import AppKit
import Combine

/// Self-updater.
///
/// The app keeps a private git checkout of its own source (in Application Support), checks it for
/// new commits, and when you choose Install it rebuilds locally with build.sh, swaps the new .app
/// into place and relaunches. Building locally means macOS treats it as your own app — no
/// Developer ID, notarisation or Gatekeeper prompts. Needs Apple's command line tools (already
/// installed for the first build) and a git repository to pull from.
@MainActor
final class Updater: ObservableObject {
    enum Phase: Equatable {
        case idle, checking, upToDate, available, installing, failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var changes: [String] = []
    @Published private(set) var log = ""
    @Published private(set) var lastChecked: Date?
    @Published var showSheet = false

    let settings: SettingsStore
    private var timer: AnyCancellable?
    private var remoteCommit = ""

    static let sourceDirectory = Cache.directory.appendingPathComponent("Source", isDirectory: true)

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// Commit the running app was built from (written into Info.plist by build.sh).
    var currentCommit: String {
        (Bundle.main.object(forInfoDictionaryKey: "WOCommit") as? String ?? "").trimmingCharacters(in: .whitespaces)
    }

    var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return currentCommit.isEmpty ? "Version \(version)" : "Version \(version) (\(currentCommit.prefix(7)))"
    }

    var isConfigured: Bool { !repo.isEmpty }
    private var repo: String { settings.updateRepo.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var branch: String {
        let b = settings.updateBranch.trimmingCharacters(in: .whitespaces)
        return b.isEmpty ? "main" : b
    }

    var updateAvailable: Bool { phase == .available }

    // MARK: - Checking

    func startAutomaticChecks() {
        guard timer == nil else { return }
        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            await checkAutomatically()
        }
        timer = Timer.publish(every: 6 * 3600, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in Task { await self?.checkAutomatically() } }
    }

    private func checkAutomatically() async {
        guard settings.autoCheckUpdates, isConfigured, phase != .installing else { return }
        await check(userInitiated: false)
    }

    func check(userInitiated: Bool) async {
        if userInitiated { showSheet = true }
        guard isConfigured else {
            if userInitiated { phase = .failed("Add the project's git address in Settings → Updates first.") }
            return
        }
        guard phase != .checking, phase != .installing else { return }
        phase = .checking
        do {
            try await prepareSource()
            let remote = try await git(["rev-parse", "origin/\(branch)"]).trimmingCharacters(in: .whitespacesAndNewlines)
            remoteCommit = remote
            lastChecked = Date()
            if !currentCommit.isEmpty, remote.hasPrefix(currentCommit) || currentCommit.hasPrefix(remote) {
                changes = []
                phase = .upToDate
            } else {
                changes = await changeList(to: remote)
                phase = .available
            }
        } catch {
            // Automatic checks fail quietly (e.g. offline); manual checks explain.
            phase = userInitiated ? .failed(Self.describe(error)) : .idle
        }
    }

    private func changeList(to remote: String) async -> [String] {
        var args = ["log", "--format=%s", "--no-merges"]
        if currentCommit.isEmpty {
            args += ["-8", remote]
        } else {
            args += ["\(currentCommit)..\(remote)"]
        }
        let out = (try? await git(args)) ?? ""
        let lines = out.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return lines.isEmpty ? ["Latest version"] : lines
    }

    private func prepareSource() async throws {
        let fm = FileManager.default
        let gitDir = Self.sourceDirectory.appendingPathComponent(".git").path
        if fm.fileExists(atPath: gitDir) {
            try await git(["remote", "set-url", "origin", repo])
            try await git(["fetch", "--prune", "origin", "+refs/heads/\(branch):refs/remotes/origin/\(branch)"])
        } else {
            try? fm.removeItem(at: Self.sourceDirectory)
            try fm.createDirectory(at: Self.sourceDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await Shell.run("/usr/bin/git", ["clone", "--branch", branch, repo, Self.sourceDirectory.path])
        }
    }

    @discardableResult
    private func git(_ args: [String]) async throws -> String {
        try await Shell.run("/usr/bin/git", ["-C", Self.sourceDirectory.path] + args)
    }

    // MARK: - Installing

    func install() async {
        guard isConfigured, phase != .installing, phase != .checking else { return }
        phase = .installing
        log = ""
        do {
            if remoteCommit.isEmpty { try await prepareSource() }
            appendLog("Getting the latest code…\n")
            try await git(["reset", "--hard", "origin/\(branch)"])
            try await git(["clean", "-fd"])   // keeps ignored .build cache for faster rebuilds

            appendLog("Building — this takes a minute or two…\n")
            try await Shell.run("/bin/bash", ["build.sh", "--no-dmg"], in: Self.sourceDirectory) { [weak self] chunk in
                Task { @MainActor in self?.appendLog(chunk) }
            }

            let built = Self.sourceDirectory.appendingPathComponent("build").appendingPathComponent("What’s On.app")
            guard FileManager.default.fileExists(atPath: built.path) else {
                throw Shell.Failure(command: "build.sh", output: "The build finished but no app was produced.")
            }
            appendLog("\nInstalling and relaunching…\n")
            try relaunch(replacingWith: built)
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    private func appendLog(_ text: String) {
        log += text
        if log.count > 60_000 { log = String(log.suffix(40_000)) }
    }

    /// Hands off to a tiny script that waits for this app to quit, swaps the bundle and reopens it.
    private func relaunch(replacingWith newApp: URL) throws {
        let target = Bundle.main.bundleURL.path
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("whatson-update-\(UUID().uuidString).sh")
        let body = """
        #!/bin/bash
        while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done
        TARGET=\(quote(target))
        /bin/rm -rf "$TARGET.updating"
        if /usr/bin/ditto \(quote(newApp.path)) "$TARGET.updating"; then
            /bin/rm -rf "$TARGET" && /bin/mv "$TARGET.updating" "$TARGET"
        fi
        /usr/bin/open "$TARGET"
        /bin/rm -f "$0"
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/bash")
        helper.arguments = [script.path]
        try helper.run()
        NSApp.terminate(nil)
    }

    private func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func describe(_ error: Error) -> String {
        if let failure = error as? Shell.Failure {
            let out = failure.output.lowercased()
            if out.contains("could not read username") || out.contains("authentication failed") || out.contains("repository not found") {
                return "Couldn't access the repository. If it's private, sign in to GitHub on this Mac first (or make the repo public)."
            }
            if out.contains("could not resolve host") || out.contains("unable to access") {
                return "Couldn't reach the repository — are you online?"
            }
            if out.contains("xcode-select") || out.contains("no developer tools") {
                return "Apple's command line tools are missing. Run xcode-select --install in Terminal, then try again."
            }
            return failure.localizedDescription
        }
        return error.localizedDescription
    }
}
