import UIKit

/// Polls for unread notification / PM status via MessageBus long-polling.
///
/// Strategy:
/// - First poll: `/session/current.json` for initial state + user ID,
///   plus a MessageBus poll with -1 to seed channel positions.
/// - Subsequent polls: continuous long-poll loop (request immediately after response).
/// - 3 s delay before first poll on start / foreground resume.
@Observable
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
    private var seeded = false

    private static let initialDelay: TimeInterval = 3
    private static let pollInterval: TimeInterval = 60
    private static let retryDelay: TimeInterval = 10

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

    /// Trigger an immediate poll, resetting the interval timer.
    func pollNow() {
        guard isActive else { return }
        startPolling(delay: 0)
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
                try? await Task.sleep(for: .seconds(delay))
            }
            guard let self, !Task.isCancelled else { return }

            if !seeded {
                await seedInitialState()
            }

            while !Task.isCancelled, self.isActive {
                let success = await self.pollMessageBus()
                let delay = success ? Self.pollInterval : Self.retryDelay
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    /// First poll: fetch current user for initial unread state + user ID,
    /// then seed MessageBus channel positions with -1.
    private func seedInitialState() async {
        guard let user = try? await api.fetchCurrentUser() else { return }
        userId = user.id

        // Seed MessageBus channel positions from /__status response
        let channel = "/notification/\(user.id)"
        if let msgs = try? await api.pollMessageBus(clientId: clientId, channels: [channel: -1]) {
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

        seeded = true
    }

    /// Long-poll: send request, server holds until new data or timeout, then return immediately for next round.
    @discardableResult
    private func pollMessageBus() async -> Bool {
        guard let userId else { return false }

        let channel = "/notification/\(userId)"
        let lastId = lastMessageIds[channel] ?? -1

        guard let messages = try? await api.pollMessageBus(clientId: clientId, channels: [channel: lastId]) else {
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
            }

            if msg.channel == channel, let data = msg.data {
                let total = data.allUnreadNotificationsCount
                    ?? ((data.unreadNotifications ?? 0) + (data.unreadHighPriorityNotifications ?? 0))
                let pm = data.newPersonalMessagesNotificationsCount ?? 0
                hasUnreadNotifications = total > 0
                hasUnreadMessages = pm > 0
            }
        }

        return true
    }

    deinit {
        stop()
    }
}
