import Foundation

@Observable
final class MessagesViewModel {
    var messages: [DiscourseTopicList.Topic] = []
    var isLoading = false
    var errorMessage: String?
    var requiresLogin = false

    private let api: DiscourseAPI

    init(api: DiscourseAPI) {
        self.api = api
    }

    func loadMessages(username: String) async {
        isLoading = true
        errorMessage = nil
        requiresLogin = false
        do {
            let result = try await api.fetchPrivateMessages(username: username)
            messages = result.topicList.topics
        } catch {
            if let apiError = error as? DiscourseAPIError, apiError.isNotLoggedIn || apiError.isForbidden {
                requiresLogin = true
            }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
