//
//  OpenCodePluginInstaller.swift
//  ClaudeIsland
//
//  Installs and manages Claude Island OpenCode plugin artifacts
//

import Foundation

struct OpenCodePluginInstaller: ProviderIntegrationInstaller {
    var provider: ProviderIntegration { .openCodePlugin }

    enum Scope {
        case project
        case global
    }

    enum PluginMode {
        case file
        case npmPackage

        init(environment: [String: String] = ProcessInfo.processInfo.environment) {
            if environment["CLAUDE_ISLAND_OPENCODE_PLUGIN_MODE"]?.lowercased() == "npm" {
                self = .npmPackage
            } else {
                self = .file
            }
        }
    }

    private let fileManager: FileManager
    private let mode: PluginMode

    init(fileManager: FileManager = .default, mode: PluginMode = PluginMode()) {
        self.fileManager = fileManager
        self.mode = mode
    }

    func installIfNeeded() {
        let scope = resolveScope()
        let pluginDirectory = pluginDirectory(for: scope)
        let pluginURL = pluginDirectory.appendingPathComponent(Self.pluginFilename)

        try? fileManager.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        try? Self.pluginSource.data(using: .utf8)?.write(to: pluginURL)

        if mode == .npmPackage {
            let configURL = opencodeConfigURL(for: scope)
            updateOpenCodeConfig(at: configURL)
        }
    }

    func isInstalled() -> Bool {
        status() == .installed
    }

    func status() -> ProviderInstallStatus {
        let scope = resolveScope()
        let pluginURL = pluginDirectory(for: scope).appendingPathComponent(Self.pluginFilename)
        let configURL = opencodeConfigURL(for: scope)

        let pluginExists = fileManager.fileExists(atPath: pluginURL.path)
        let configExists = fileManager.fileExists(atPath: configURL.path)

        var hasManagedPlugin = false
        var hasConflictingPlugin = false

        if pluginExists {
            guard let source = try? String(contentsOf: pluginURL) else {
                return .error
            }

            if source.contains(Self.managedFingerprint) {
                hasManagedPlugin = true
            } else {
                hasConflictingPlugin = true
            }
        }

        if mode == .npmPackage {
            var hasManagedPackage = false
            if configExists {
                guard let data = try? Data(contentsOf: configURL),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let plugins = json["plugins"] as? [Any] else {
                    return .error
                }

                hasManagedPackage = plugins.contains { ($0 as? String) == Self.npmPackageName }
            }

            if hasManagedPlugin && hasManagedPackage {
                return .installed
            }

            if !hasManagedPlugin && !hasManagedPackage && !hasConflictingPlugin {
                return .missing
            }

            return .conflict
        }

        if hasManagedPlugin {
            return .installed
        }

        if !pluginExists {
            return .missing
        }

        return .conflict
    }

    func uninstall() {
        for scope in [Scope.project, Scope.global] {
            let pluginURL = pluginDirectory(for: scope).appendingPathComponent(Self.pluginFilename)
            try? fileManager.removeItem(at: pluginURL)
            removeManagedPackageFromConfig(at: opencodeConfigURL(for: scope))
        }
    }

    private func resolveScope() -> Scope {
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let projectOpenCodeDirectory = currentDirectory.appendingPathComponent(".opencode")
        if fileManager.fileExists(atPath: projectOpenCodeDirectory.path) {
            return .project
        }
        return .global
    }

    private func pluginDirectory(for scope: Scope) -> URL {
        switch scope {
        case .project:
            return URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent(".opencode")
                .appendingPathComponent("plugins")
        case .global:
            return fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".config")
                .appendingPathComponent("opencode")
                .appendingPathComponent("plugins")
        }
    }

    private func opencodeConfigURL(for scope: Scope) -> URL {
        switch scope {
        case .project:
            return URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("opencode.json")
        case .global:
            return fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".config")
                .appendingPathComponent("opencode")
                .appendingPathComponent("opencode.json")
        }
    }

    private func updateOpenCodeConfig(at configURL: URL) {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: configURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        var plugins = json["plugins"] as? [Any] ?? []
        let hasManagedPackage = plugins.contains {
            ($0 as? String) == Self.npmPackageName
        }

        if !hasManagedPackage {
            plugins.append(Self.npmPackageName)
            json["plugins"] = plugins
            if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
                try? fileManager.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: configURL)
            }
        }
    }

    private func removeManagedPackageFromConfig(at configURL: URL) {
        guard let data = try? Data(contentsOf: configURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var plugins = json["plugins"] as? [Any] else {
            return
        }

        plugins.removeAll { ($0 as? String) == Self.npmPackageName }

        if plugins.isEmpty {
            json.removeValue(forKey: "plugins")
        } else {
            json["plugins"] = plugins
        }

        if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? updatedData.write(to: configURL)
        }
    }

    private static let pluginFilename = "claude-island-opencode-plugin.ts"
    private static let managedFingerprint = "claude-island-opencode-plugin@v1"
    private static let npmPackageName = "@claude-island/opencode-plugin"

    private static let pluginSource = """
    // Managed by Claude Island.
    // fingerprint: \(managedFingerprint)

    export default {
      name: "claude-island",
      onEvent(event: unknown) {
        return event;
      },
    };
    """
}
