import CryptoKit
import Foundation

enum EmojiStore {
    private static let cacheDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("EmojiCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func load(for baseURL: String) -> [String: String]? {
        let file = cacheFile(for: baseURL)
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    static func save(_ map: [String: String], for baseURL: String) {
        let file = cacheFile(for: baseURL)
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: file, options: .atomic)
    }

    private static func cacheFile(for baseURL: String) -> URL {
        let hash = SHA256.hash(data: Data(baseURL.utf8))
        let prefix = hash.prefix(8).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent("\(prefix).json")
    }
}
