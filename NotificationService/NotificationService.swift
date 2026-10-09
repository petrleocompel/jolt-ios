import UserNotifications

/// Replaces the generic text of a relayed alert ("You've been poked") with
/// the real one before iOS shows it. The relay can't write that text itself:
/// it never sees what is in the poke.
///
/// Runs only for alerts with `mutable-content`, which every relayed one has.
/// Anything that fails to open — no key for the server, a bad envelope, a
/// payload that doesn't match its wrapper — leaves the alert as it arrived,
/// so the recipient still learns that something came in.
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var original: UNNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        original = request.content

        let keys = PayloadKeyStore()
        guard let relayed = RelayedNotificationContent(
            userInfo: request.content.userInfo,
            key: { keys.key(for: $0) }
        ), let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        content.title = relayed.title
        content.body = relayed.body
        content.userInfo = relayed.userInfo
        contentHandler(content)
    }

    /// Opening a push takes milliseconds, so this should never run; if iOS
    /// cuts the extension short anyway, the fallback text is still shown.
    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let original {
            contentHandler(original)
        }
    }
}
