import SwiftUI

struct ExhibitionCard: View {
    let item: Exhibition

    var body: some View {
        LinkButton(url: item.url) {
            VStack(alignment: .leading, spacing: 10) {
                Artwork(url: item.imageURL, aspect: 3 / 2, symbol: "photo.artframe")
                    .overlay(alignment: .topLeading) {
                        if let badge = item.badge { Badge(text: badge).padding(8) }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(item.venue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !item.dateLabel.isEmpty {
                        Text(item.dateLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MixCard: View {
    let mix: Mix
    var now: Date = Date()

    private var caption: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = Locale(identifier: "en_GB")
        let when = f.localizedString(for: mix.date, relativeTo: now)
        return [when, Fmt.duration(mix.durationSeconds)].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        LinkButton(url: mix.url) {
            VStack(alignment: .leading, spacing: 10) {
                Artwork(url: mix.artworkURL, aspect: 1, symbol: "waveform", cornerRadius: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(mix.title)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(mix.uploader)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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

/// Larger gig tile used for "This week".
struct GigFeatureCard: View {
    let gig: Gig

    var body: some View {
        LinkButton(url: gig.url) {
            HStack(spacing: 14) {
                DateBlock(date: gig.date, highlighted: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(gig.artist)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(gig.venue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(gig.timeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        }
    }
}

/// Compact row for gigs further out.
struct GigRow: View {
    let gig: Gig

    var body: some View {
        LinkButton(url: gig.url, row: true) {
            HStack(spacing: 14) {
                DateBlock(date: gig.date)
                VStack(alignment: .leading, spacing: 2) {
                    Text(gig.artist).font(.body.weight(.medium)).lineLimit(1)
                    Text(gig.venue).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if !gig.allDay {
                    Text(Fmt.time.string(from: gig.date))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }
}

/// Grouped-list container, like Settings / Music.
struct GroupedBox<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0, content: content)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct TimePill: View {
    let showtime: Showtime
    var now: Date = Date()
    @Environment(\.openURL) private var openURL
    @State private var hovering = false

    private var isPast: Bool { showtime.time < now }
    private var disabled: Bool { showtime.soldOut || isPast || showtime.bookingURL == nil }

    private var help: String {
        if showtime.soldOut { return "Sold out" }
        if isPast { return "Already started" }
        return ["Book", showtime.screen].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        Button {
            if let url = showtime.bookingURL { openURL(url) }
        } label: {
            Text(Fmt.time.string(from: showtime.time))
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .strikethrough(showtime.soldOut)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(hovering && !disabled ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
                )
                .foregroundStyle(disabled ? Color.secondary : (hovering ? Color.accentColor : Color.primary))
                .opacity(isPast ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .help(help)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct FilmRow: View {
    let film: Film
    let times: [Showtime]
    var now: Date = Date()
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Artwork(url: film.posterURL, aspect: 2 / 3, symbol: "film", cornerRadius: 6)
                .frame(width: 58)
            VStack(alignment: .leading, spacing: 9) {
                VStack(alignment: .leading, spacing: 2) {
                    Button {
                        if let url = film.url { openURL(url) }
                    } label: {
                        Text(film.title)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    .help("Open film page")
                    if let meta = film.meta {
                        Text(meta).font(.caption).foregroundStyle(.secondary)
                    }
                }
                FlowLayout(spacing: 6) {
                    ForEach(times) { TimePill(showtime: $0, now: now) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }
}
