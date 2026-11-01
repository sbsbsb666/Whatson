import SwiftUI

/// One post: cover image, publication line, title, subtitle.
struct SubstackCard: View {
    let post: SubstackPost
    var now: Date = Date()
    var showSubtitle = true

    private var caption: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = Locale(identifier: "en_GB")
        var parts = [f.localizedString(for: post.date, relativeTo: now)]
        if let author = post.author, !post.publication.localizedCaseInsensitiveContains(author) { parts.insert(author, at: 0) }
        if post.isPaid { parts.append("Paid") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        LinkButton(url: post.url) {
            VStack(alignment: .leading, spacing: 10) {
                Artwork(url: post.imageURL, aspect: 16 / 9, symbol: "text.book.closed")
                    .overlay(alignment: .topLeading) {
                        if let symbol = post.kindSymbol {
                            Image(systemName: symbol)
                                .font(.caption.weight(.semibold))
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                                .padding(8)
                        }
                    }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if let logo = post.logoURL {
                            Color.clear
                                .frame(width: 16, height: 16)
                                .overlay { RemoteImage(url: logo, symbol: "text.book.closed") }
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                        Text(post.publication)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(post.title)
                        .font(.headline)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    if showSubtitle, let subtitle = post.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SubstackView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    @State private var publication = "All"

    private var publications: [String] {
        ["All"] + Set(model.substack.items.map(\.publication)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var filtered: [SubstackPost] {
        model.substack.items.filter { post in
            (publication == "All" || post.publication == publication) &&
            (search.isEmpty
             || post.title.localizedCaseInsensitiveContains(search)
             || post.publication.localizedCaseInsensitiveContains(search)
             || (post.subtitle ?? "").localizedCaseInsensitiveContains(search))
        }
    }

    private static let columns = [GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 24, alignment: .top)]

    var body: some View {
        SectionPage(title: "Substack", symbol: Destination.substack.symbol, state: model.substack,
                    retry: { Task { await model.refreshSubstack() } }) {
            let items = filtered
            let cal = Calendar.london
            let today = items.filter { cal.isDate($0.date, inSameDayAs: model.now) }
            let week = items.filter { !cal.isDate($0.date, inSameDayAs: model.now) && model.now.timeIntervalSince($0.date) < 7 * 86_400 }
            let earlier = items.filter { model.now.timeIntervalSince($0.date) >= 7 * 86_400 }

            if items.isEmpty {
                ContentUnavailableView.search(text: search)
            }
            if !today.isEmpty { grid("Today", today) }
            if !week.isEmpty { grid("This week", week) }
            if !earlier.isEmpty { grid("Earlier", earlier) }
        }
        .navigationTitle("Substack")
        .navigationSubtitle(model.updatedLabel(model.substack))
        .searchable(text: $search, placement: .toolbar, prompt: "Search posts")
        .toolbar {
            ToolbarItem {
                Picker("Publication", selection: $publication) {
                    ForEach(publications, id: \.self) { Text($0 == "All" ? "All Publications" : $0).tag($0) }
                }
                .pickerStyle(.menu)
                .help("Filter by publication")
            }
        }
    }

    private func grid(_ title: String, _ posts: [SubstackPost]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: title, subtitle: "\(posts.count) post\(posts.count == 1 ? "" : "s")")
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 32) {
                ForEach(posts) { SubstackCard(post: $0, now: model.now) }
            }
        }
    }
}
