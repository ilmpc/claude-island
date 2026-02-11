import Foundation

enum ClaudeEventAdapter {
    static func normalize(_ event: HookEvent) -> NormalizedHookEvent {
        NormalizedHookEvent(
            provider: .claude,
            sessionId: event.sessionId,
            cwd: event.cwd,
            status: event.status,
            toolName: event.tool,
            toolInput: event.toolInput,
            toolCallId: event.toolUseId,
            message: event.message,
            notificationType: event.notificationType,
            rawEventName: event.event,
            pid: event.pid,
            tty: event.tty
        )
    }
}
