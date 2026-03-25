import Foundation

struct DiscourseCustomEmoji: Decodable {
    let name: String
    let url: String
}

struct DiscourseEmojiEntry: Decodable {
    let name: String
    let url: String
}

struct DiscourseCreatePostResponse: Decodable {
    let id: Int
    let postNumber: Int

    enum CodingKeys: String, CodingKey {
        case id
        case postNumber = "post_number"
    }
}
