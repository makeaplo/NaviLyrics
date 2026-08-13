import SwiftUI
import UIKit

struct LibraryArtwork: View {
    let url: URL?
    let size: CGFloat

    @State private var image: Image? = nil
    @State private var isLoading = false

    private static let imageCache = NSCache<NSURL, UIImage>()

    var body: some View {
        Group {
            if url?.scheme == "navi-demo" {
                DemoArtworkView(identifier: url?.lastPathComponent ?? "")
            } else if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
                    .overlay {
                        if isLoading {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.13))
        .task(id: url) { await loadImage() }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: size * 0.13)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
    }

    private func loadImage() async {
        image = nil
        guard let url else {
            isLoading = false
            return
        }
        guard url.scheme != "navi-demo" else {
            isLoading = false
            return
        }
        if let cachedImage = Self.imageCache.object(forKey: url as NSURL) {
            image = Image(uiImage: cachedImage)
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let (data, response) = try await URLSession.shared.data(
                from: url
            )
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode,
                  let loadedImage = UIImage(data: data) else {
                return
            }
            try Task.checkCancellation()
            Self.imageCache.setObject(loadedImage, forKey: url as NSURL)
            image = Image(uiImage: loadedImage)
        } catch is CancellationError {
            return
        } catch {
            return
        }
    }
}

struct DemoArtworkView: View {
    let identifier: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: palette,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.white.opacity(0.2))
                .frame(width: 180, height: 180)
                .blur(radius: 8)
                .offset(x: 52, y: -58)

            Circle()
                .stroke(.white.opacity(0.46), lineWidth: 2)
                .frame(width: 92, height: 92)
                .scaleEffect(1.6)
                .opacity(0.7)

            Image(systemName: symbolName)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
        }
        .compositingGroup()
    }

    private var palette: [Color] {
        if identifier.contains("afterglow") {
            return [.indigo, .purple, .pink.opacity(0.8)]
        }
        return [.teal, .blue, .black.opacity(0.86)]
    }

    private var symbolName: String {
        identifier.contains("afterglow") ? "moon.stars.fill" : "waveform"
    }
}
