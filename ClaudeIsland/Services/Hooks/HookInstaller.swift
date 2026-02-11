//
//  HookInstaller.swift
//  ClaudeIsland
//
//  Auto-installs Claude Code hooks on app launch
//

import Foundation

enum ProviderIntegration: String, CaseIterable, Hashable {
    case claudeCodeHooks
    case openCodePlugin

    var title: String {
        switch self {
        case .claudeCodeHooks:
            return "Claude Code Hooks"
        case .openCodePlugin:
            return "OpenCode Plugin"
        }
    }
}

enum ProviderInstallStatus {
    case installed
    case missing
    case conflict
    case error

    var label: String {
        switch self {
        case .installed:
            return "Installed"
        case .missing:
            return "Missing"
        case .conflict:
            return "Conflict"
        case .error:
            return "Error"
        }
    }
}

protocol ProviderIntegrationInstaller {
    var provider: ProviderIntegration { get }
    func installIfNeeded()
    func isInstalled() -> Bool
    func status() -> ProviderInstallStatus
    func uninstall()
}

struct HookInstaller {

    private static let providerInstallers: [ProviderIntegration: any ProviderIntegrationInstaller] = {
        let installers: [any ProviderIntegrationInstaller] = [
            HookInstaller(),
            OpenCodePluginInstaller()
        ]
        return Dictionary(uniqueKeysWithValues: installers.map { ($0.provider, $0) })
    }()

    static func installIfNeeded(for enabledProviders: Set<ProviderIntegration>) {
        enabledProviders.forEach { provider in
            providerInstallers[provider]?.installIfNeeded()
        }
    }

    static func isInstalled(for provider: ProviderIntegration) -> Bool {
        providerInstallers[provider]?.isInstalled() ?? false
    }

    static func status(for provider: ProviderIntegration) -> ProviderInstallStatus {
        providerInstallers[provider]?.status() ?? .error
    }

    static func uninstall(provider: ProviderIntegration) {
        providerInstallers[provider]?.uninstall()
    }
}

extension HookInstaller: ProviderIntegrationInstaller {
    var provider: ProviderIntegration { .claudeCodeHooks }

    func installIfNeeded() {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let hooksDir = claudeDir.appendingPathComponent("hooks")
        let pythonScript = hooksDir.appendingPathComponent("claude-island-state.py")
        let settings = claudeDir.appendingPathComponent("settings.json")

        try? FileManager.default.createDirectory(
            at: hooksDir,
            withIntermediateDirectories: true
        )

        if let bundled = Bundle.main.url(forResource: "claude-island-state", withExtension: "py") {
            try? FileManager.default.removeItem(at: pythonScript)
            try? FileManager.default.copyItem(at: bundled, to: pythonScript)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: pythonScript.path
            )
        }

        Self.updateSettings(at: settings)
    }

    private static func updateSettings(at settingsURL: URL) {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        let python = detectPython()
        let command = "\(python) ~/.claude/hooks/claude-island-state.py"
        let hookEntry: [[String: Any]] = [["type": "command", "command": command]]
        let hookEntryWithTimeout: [[String: Any]] = [["type": "command", "command": command, "timeout": 86400]]
        let withMatcher: [[String: Any]] = [["matcher": "*", "hooks": hookEntry]]
        let withMatcherAndTimeout: [[String: Any]] = [["matcher": "*", "hooks": hookEntryWithTimeout]]
        let withoutMatcher: [[String: Any]] = [["hooks": hookEntry]]
        let preCompactConfig: [[String: Any]] = [
            ["matcher": "auto", "hooks": hookEntry],
            ["matcher": "manual", "hooks": hookEntry]
        ]

        var hooks = json["hooks"] as? [String: Any] ?? [:]

        let hookEvents: [(String, [[String: Any]])] = [
            ("UserPromptSubmit", withoutMatcher),
            ("PreToolUse", withMatcher),
            ("PostToolUse", withMatcher),
            ("PermissionRequest", withMatcherAndTimeout),
            ("Notification", withMatcher),
            ("Stop", withoutMatcher),
            ("SubagentStop", withoutMatcher),
            ("SessionStart", withoutMatcher),
            ("SessionEnd", withoutMatcher),
            ("PreCompact", preCompactConfig),
        ]

        for (event, config) in hookEvents {
            if var existingEvent = hooks[event] as? [[String: Any]] {
                let hasOurHook = existingEvent.contains { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { h in
                            let cmd = h["command"] as? String ?? ""
                            return cmd.contains("claude-island-state.py")
                        }
                    }
                    return false
                }
                if !hasOurHook {
                    existingEvent.append(contentsOf: config)
                    hooks[event] = existingEvent
                }
            } else {
                hooks[event] = config
            }
        }

        json["hooks"] = hooks

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: settingsURL)
        }
    }

    func isInstalled() -> Bool {
        status() == .installed
    }

    func status() -> ProviderInstallStatus {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let scriptURL = claudeDir
            .appendingPathComponent("hooks")
            .appendingPathComponent("claude-island-state.py")
        let settingsURL = claudeDir.appendingPathComponent("settings.json")

        let scriptExists = FileManager.default.fileExists(atPath: scriptURL.path)

        var hookReferenceExists = false
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            guard let data = try? Data(contentsOf: settingsURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hooks = json["hooks"] as? [String: Any] else {
                return .error
            }

            hookReferenceExists = Self.settingsContainClaudeIslandHook(hooks)
        }

        if scriptExists && hookReferenceExists {
            return .installed
        }

        if !scriptExists && !hookReferenceExists {
            return .missing
        }

        return .conflict
    }

    func uninstall() {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let hooksDir = claudeDir.appendingPathComponent("hooks")
        let pythonScript = hooksDir.appendingPathComponent("claude-island-state.py")
        let settings = claudeDir.appendingPathComponent("settings.json")

        try? FileManager.default.removeItem(at: pythonScript)

        guard let data = try? Data(contentsOf: settings),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else {
            return
        }

        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries.removeAll { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { hook in
                            let cmd = hook["command"] as? String ?? ""
                            return cmd.contains("claude-island-state.py")
                        }
                    }
                    return false
                }

                if entries.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = entries
                }
            }
        }

        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: settings)
        }
    }

    private static func detectPython() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return "python3"
            }
        } catch {}

        return "python"
    }

    private static func settingsContainClaudeIslandHook(_ hooks: [String: Any]) -> Bool {
        for (_, value) in hooks {
            if let entries = value as? [[String: Any]] {
                for entry in entries {
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        for hook in entryHooks {
                            if let cmd = hook["command"] as? String,
                               cmd.contains("claude-island-state.py") {
                                return true
                            }
                        }
                    }
                }
            }
        }

        return false
    }
}
