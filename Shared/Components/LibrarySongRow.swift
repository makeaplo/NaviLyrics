import SwiftUI

struct LibrarySongRow: View {
    let song: SubsonicSong
    let artworkURL: URL?
    let leadingLabel: String?
    let leadingSymbol: String?
    let metadata: String?
    let isFavorite: Bool
    let isFavoriteUpdating: Bool
    let onPlay: () -> Void
    let onToggleFavorite: () -> Void

    init(
        song: SubsonicSong,
        artworkURL: URL? = nil,
        leadingLabel: String? = nil,
        leadingSymbol: String? = nil,
        metadata: String? = nil,
        isFavorite: Bool,
        isFavoriteUpdating: Bool,
        onPlay: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void
    ) {
        self.song = song
        self.artworkURL = artworkURL
        self.leadingLabel = leadingLabel
        self.leadingSymbol = leadingSymbol
        self.metadata = metadata
        self.isFavorite = isFavorite
        self.isFavoriteUpdating = isFavoriteUpdating
        self.onPlay = onPlay
        self.onToggleFavorite = onToggleFavorite
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPlay) {
                HStack(spacing: 10) {
                    leadingContent
                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.title)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(resolvedMetadata)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(Self.timeString(song.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "(song.title)，(song.artist)，(Self.timeString(song.duration))"
            )
            .accessibilityHint("播放并从此处继续列表")

            FavoriteButton(
                isFavorite: isFavorite,
                isUpdating: isFavoriteUpdating,
                action: onToggleFavorite
            )
        }
    }

    @ViewBuilder
    private var leadingContent: some View {
        if let leadingSymbol {
            Image(systemName: leadingSymbol)
                .foregroundStyle(.tint)
                .font(.caption.weight(.semibold))
                .frame(width: 26)
        } else if let leadingLabel {
            Text(leadingLabel)
                .foregroundStyle(.secondary)
                .font(.caption.monospacedDigit())
                .frame(width: 26)
        } else {
            LibraryArtwork(url: artworkURL, size: 48)
        }
    }

    private var resolvedMetadata: String {
        if let metadata, !metadata.isEmpty {
            return metadata
        }
        return [song.artist, song.album]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private static func timeString(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "--:--" }
        return String(format: "%d:%02d", Int(time) / 60, Int(time) % 60)
    }
}
