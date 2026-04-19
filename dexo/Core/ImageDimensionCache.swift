import Foundation
import UIKit

/// Disk-persisted cache of image pixel dimensions, keyed by URL.
///
/// Lets cells fix their image height before SDWebImage actually loads the image,
/// avoiding the layout jump that happens when an `<img>` without HTML
/// `width`/`height` finishes loading. First time we see a URL we still fall
/// back to a placeholder ratio; every subsequent render uses the recorded size.
///
/// Storage lives in the system Caches directory and is wiped by the existing
/// "Clear cache" sweep in `ImageCacheManager.clearAll`.
final class ImageDimensionCache {
    static let shared = ImageDimensionCache()

    private struct Stored: Codable {
        let w: Int
        let h: Int
    }

    private var storage: [String: Stored] = [:]
    private var pendingFlush = false
    private let ioQueue = DispatchQueue(label: "ImageDimensionCache.io", qos: .utility)

    private var fileURL: URL? {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return dir.appendingPathComponent("image-dimensions.json")
    }

    private init() {
        loadFromDisk()
    }

    /// Returns recorded pixel dimensions for `url`, or `nil` if unknown.
    func size(for url: URL) -> CGSize? {
        guard let s = storage[url.absoluteString] else { return nil }
        return CGSize(width: s.w, height: s.h)
    }

    /// Records dimensions and schedules a debounced background flush.
    func record(_ size: CGSize, for url: URL) {
        let w = Int(size.width.rounded())
        let h = Int(size.height.rounded())
        guard w > 0, h > 0 else { return }
        let key = url.absoluteString
        if let existing = storage[key], existing.w == w, existing.h == h { return }
        storage[key] = Stored(w: w, h: h)
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard !pendingFlush else { return }
        pendingFlush = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.pendingFlush = false
            self?.flushSnapshot()
        }
    }

    private func flushSnapshot() {
        guard let url = fileURL else { return }
        let snapshot = storage
        ioQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func loadFromDisk() {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode([String: Stored].self, from: data)
        else { return }
        storage = loaded
    }
}
