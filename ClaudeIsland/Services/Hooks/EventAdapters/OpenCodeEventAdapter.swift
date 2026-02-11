import Foundation

/// Generic OpenCode plugin event payload mapped into NormalizedHookEvent
struct OpenCodePluginEvent: Codable, Sendable {
    let sessionId: String
    let cwd: String
    let eventName: String
    let status: String
    let toolName: String?
    let toolInput: [String: AnyCodable]?
    let toolCallId: String?
    let message: String?
    let notificationType: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case eventName = "event"
        case status
        case toolName = "tool"
        case toolInput = "tool_input"
        case toolCallId = "tool_call_id"
        case message
        case notificationType = "notification_type"
    }
}

enum OpenCodeEventAdapter {
    static func normalize(_ event: OpenCodePluginEvent) -> NormalizedHookEvent {
        NormalizedHookEvent(
            provider: .openCode,
            sessionId: event.sessionId,
            cwd: event.cwd,
            status: event.status,
            toolName: event.toolName,
            toolInput: event.toolInput,
            toolCallId: event.toolCallId,
            message: event.message,
            notificationType: event.notificationType,
            rawEventName: event.eventName,
            pid: nil,
            tty: nil
        )
    }
}
