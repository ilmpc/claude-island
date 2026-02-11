import Foundation

/// Provider-neutral hook event consumed by SessionStore
struct NormalizedHookEvent: Sendable {
    enum Provider: String, Sendable {
        case claude
        case openCode
    }

    let provider: Provider
    let sessionId: String
    let cwd: String
    /// Provider status or phase string (e.g. waiting_for_approval, processing, ended)
    let status: String
    let toolName: String?
    let toolInput: [String: AnyCodable]?
    let toolCallId: String?
    let message: String?
    let notificationType: String?
    /// Original provider event name (e.g. PreToolUse, Notification)
    let rawEventName: String
    let pid: Int?
    let tty: String?
}
