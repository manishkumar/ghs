import AppKit
import SwiftUI

/// Tiny in-memory avatar cache. Avatars are 64px and repeat heavily across a
/// queue (the same few authors), so a dictionary outperforms hitting the URL
/// loading system on every popover open.
@MainActor
final class AvatarLoader: ObservableObject {
    static let shared = AvatarLoader()

    @Published private var images: [URL: NSImage] = [:]
    private var inFlight: Set<URL> = []

    func image(for url: URL?) -> NSImage? {
        guard let url else { return nil }
        if let cached = images[url] { return cached }
        load(url)
        return nil
    }

    private func load(_ url: URL) {
        guard !inFlight.contains(url) else { return }
        inFlight.insert(url)
        Task {
            defer { inFlight.remove(url) }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data)
            else { return }
            images[url] = image
        }
    }
}

struct Avatar: View {
    let url: URL?
    let login: String
    var size: CGFloat = 22

    @ObservedObject private var loader = AvatarLoader.shared

    var body: some View {
        Group {
            if let image = loader.image(for: url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                // Initial on a tinted disc, so the row never reflows when the
                // real avatar arrives.
                Text(login.prefix(1).uppercased())
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.08))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
}
