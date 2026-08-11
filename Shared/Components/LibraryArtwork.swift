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
            if let image {
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
