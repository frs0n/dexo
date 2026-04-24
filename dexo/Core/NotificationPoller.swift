import UIKit

/// Polls for unread notification / PM status via MessageBus long-polling.
///
/// Strategy:
/// - First poll: `/session/current.json` for initial state + user ID,
///   plus a MessageBus poll with -1 to seed channel positions.
/// - Subsequent polls: continuous long-poll loop (request immediately after response).
/// - 3 s delay before first poll on start / foreground resume.
import Perception

@Perceptible
final class NotificationPoller {
    var hasUnreadNotifications = false
    var hasUnreadMessages = false

    var hasAnyUnread: Bool { hasUnreadNotifications || hasUnreadMessages }

    private let api: DiscourseAPI
    private let usernameProvider: () -> String?
    private var isActive = false
    private var pollTask: Task<Void, Never>?

    // MessageBus state
    private let clientId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    private var userId: Int?
    private var lastMessageIds: [String: Int] = [:]
    private var sharedSessionKey: String?
    private var seeded = false

    private static let initialDelay: TimeInterval = 3
    private static let pollInterval: TimeInterval = 60

    init(api: DiscourseAPI, usernameProvider: @escaping () -> String?) {
        self.api = api
        self.usernameProvider = usernameProvider
    }

    func start() {
        guard !isActive else { return }
        isActive = true

        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIScene.didActivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIScene.didEnterBackgroundNotification, object: nil)

        startPolling(delay: Self.initialDelay)
    }

    func stop() {
        isActive = false
        pollTask?.cancel()
        pollTask = nil
        NotificationCenter.default.removeObserver(self)
    }

    func clearNotifications() {
        hasUnreadNotifications = false
    }

    func clearMessages() {
        hasUnreadMessages = false
    }

    // MARK: - Foreground / Background

    @objc private func appDidBecomeActive() {
        startPolling(delay: Self.initialDelay)
    }

    @objc private func appDidEnterBackground() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Long-poll loop

    private func startPolling(delay: TimeInterval) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard let self, !Task.isCancelled else { return }

            if !seeded {
                await seedInitialState()
            }

            guard self.userId != nil else { return }

            while !Task.isCancelled, self.isActive {
                await self.pollMessageBus()
                try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
            }
        }
    }

    /// First poll: fetch current user for initial unread state + user ID,
    /// then seed MessageBus channel positions with -1.
    private func seedInitialState() async {
        // linux.do's /session/current.json returns empty, so skip it entirely there.
        if !api.isLinuxDo, let user = try? await api.fetchCurrentUser() {
            userId = user.id
            // Apply initial unread state from session
            let total = (user.unreadNotifications ?? 0) + (user.unreadHighPriorityNotifications ?? 0)
            hasUnreadNotifications = total > 0
            hasUnreadMessages = (user.unreadPrivateMessages ?? 0) > 0
        } else if let username = usernameProvider(), !username.isEmpty,
                  let profile = try? await api.fetchUserProfile(username: username)
        {
            userId = profile.id
            // currentUser returned empty — seed unread state from notifications list
            if let list = try? await api.fetchNotifications() {
                hasUnreadNotifications = list.notifications.contains { !$0.read }
                hasUnreadMessages = list.notifications.contains { !$0.read && $0.notificationType == 6 }
            }
        }
        guard userId != nil else {
            seeded = true
            return
        }

        // linux.do uses a separate MessageBus domain (ping.linux.do) that requires a shared session key.
        // Only needed for web-based login (cookie auth), not User API Key auth.
        if api.baseURL.contains("linux.do"),
           KeychainHelper.getUserApiKey(for: api.baseURL) == AuthManager.webAuthSentinel
        {
            sharedSessionKey = await api.fetchSharedSessionKey()
        }

        // Seed MessageBus channel positions from /__status response
        let channels: [String: Int] = ["/notification/\(userId!)": -1]
        if let msgs = try? await api.pollMessageBus(clientId: clientId, channels: channels, sharedSessionKey: sharedSessionKey) {
            for msg in msgs {
                if let positions = msg.statusChannelPositions {
                    for (ch, pos) in positions {
                        lastMessageIds[ch] = pos
                    }
                } else {
                    lastMessageIds[msg.channel] = msg.messageId
                }
            }
        }

        // Default to 0 for channels not included in __status so we don't keep sending -1
        for ch in channels.keys where lastMessageIds[ch] == nil {
            lastMessageIds[ch] = 0
        }

        seeded = true
    }

    /// Long-poll: send request, server holds until new data or timeout, then return immediately for next round.
    @discardableResult
    private func pollMessageBus() async -> Bool {
        guard let userId else { return false }

        let channel = "/notification/\(userId)"
        let pollChannels = [channel: lastMessageIds[channel] ?? -1]

        guard let messages = try? await api.pollMessageBus(clientId: clientId, channels: pollChannels, sharedSessionKey: sharedSessionKey) else {
            return false
        }

        for msg in messages {
            if let positions = msg.statusChannelPositions {
                for (ch, pos) in positions {
                    lastMessageIds[ch] = pos
                }
            } else {
                if msg.messageId > (lastMessageIds[msg.channel] ?? -1) {
                    lastMessageIds[msg.channel] = msg.messageId
                }
                if msg.channel == channel, let data = msg.data {
                    let total = data.allUnreadNotificationsCount
                        ?? ((data.unreadNotifications ?? 0) + (data.unreadHighPriorityNotifications ?? 0))
                    let pm = data.groupedUnreadNotifications?["6"] ?? data.newPersonalMessagesNotificationsCount ?? 0
                    hasUnreadNotifications = total > 0
                    hasUnreadMessages = pm > 0
                }
            }
        }

        return true
    }

    deinit {
        stop()
    }
}
