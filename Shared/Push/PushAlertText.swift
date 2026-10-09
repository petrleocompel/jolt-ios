import Foundation

/// The title and body a poke or test alert shows. A port of `alertTextFor`
/// and `testAlertTextFor` in jolt-server's `src/push/types.ts`: a direct
/// push arrives with the server's rendering of this text, a relayed one only
/// with the generic fallback, so the extension renders it here instead.
///
/// One difference on purpose: the time is the phone's local time, from the
/// raw `sentAt`. The server prints its own zone's time and names the zone
/// because that is the only way to make it unambiguous; here neither is
/// needed.
struct PushAlertText: Equatable {
    var title: String
    var body: String

    /// "Alice" / "zapped you — 30% x2 at 14:32", with " (automation)" for a
    /// poke a friend's script sent.
    static func poke(_ payload: PokePushPayload, timeZone: TimeZone = .current, locale: Locale = .current) -> Self {
        let time = sendTime(payload.sentAt, timeZone: timeZone, locale: locale).map { " at \($0)" } ?? ""
        let automation = payload.viaApiToken == true ? " (automation)" : ""
        return PushAlertText(
            title: payload.senderDisplayName.isEmpty ? "@\(payload.senderHandle)" : payload.senderDisplayName,
            body: "\(payload.stimulus.kind.pastTenseVerb) you — \(strength(payload.stimulus))\(time)\(automation)"
        )
    }

    /// Says which half of the test it is: notification only, or firing too.
    static func test(_ payload: TestPushPayload, timeZone: TimeZone = .current, locale: Locale = .current) -> Self {
        let sent = sendTime(payload.sentAt, timeZone: timeZone, locale: locale).map { ", sent \($0)" } ?? ""
        guard let stimulus = payload.stimulus else {
            return PushAlertText(title: "Jolt", body: "Test notification — push delivery works\(sent).")
        }
        return PushAlertText(
            title: "Jolt test",
            body: "Delivery works — firing \(stimulus.kind.rawValue) \(strength(stimulus))\(sent)."
        )
    }

    /// "30% x2", or just "30%".
    static func strength(_ stimulus: StimulusConfig) -> String {
        stimulus.repetitions > 1 ? "\(stimulus.intensity)% x\(stimulus.repetitions)" : "\(stimulus.intensity)%"
    }

    /// Hours and minutes in the phone's own clock style. Nil for a missing or
    /// unparseable timestamp, so a bad clock costs the time, not the alert.
    static func sendTime(_ sentAt: String?, timeZone: TimeZone, locale: Locale) -> String? {
        guard let sentAt, let date = parseTimestamp(sentAt) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter.string(from: date)
    }

    private static func parseTimestamp(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return withFraction.date(from: text) ?? plain.date(from: text)
    }
}
