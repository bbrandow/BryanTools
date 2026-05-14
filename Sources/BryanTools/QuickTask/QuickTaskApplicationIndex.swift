import AppKit
import Foundation

struct QuickTaskApplication: Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL
    let bundleIdentifier: String?

    var icon: NSImage? {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}

enum QuickTaskApplicationIndex {
    static func loadApplications() -> [QuickTaskApplication] {
        var seenPaths = Set<String>()
        var apps: [QuickTaskApplication] = []
        for root in applicationRoots() {
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "app",
                      !seenPaths.contains(url.path) else {
                    continue
                }
                seenPaths.insert(url.path)
                let name = displayName(for: url)
                let bundleIdentifier = Bundle(url: url)?.bundleIdentifier
                apps.append(QuickTaskApplication(
                    id: url.path,
                    name: name,
                    url: url,
                    bundleIdentifier: bundleIdentifier
                ))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func matches(for query: String, applications: [QuickTaskApplication], limit: Int = 6) -> [QuickTaskApplication] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else {
            return []
        }

        return applications
            .compactMap { app -> (QuickTaskApplication, Int)? in
                let name = normalize(app.name)
                if name == normalizedQuery {
                    return (app, 0)
                }
                if name.hasPrefix(normalizedQuery) {
                    return (app, 1)
                }
                if name.contains(normalizedQuery) {
                    return (app, 2)
                }
                if acronym(app.name).hasPrefix(normalizedQuery) {
                    return (app, 3)
                }
                return nil
            }
            .sorted {
                if $0.1 != $1.1 {
                    return $0.1 < $1.1
                }
                return $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
            }
            .prefix(limit)
            .map(\.0)
    }

    private static func applicationRoots() -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true)
        ]
    }

    private static func displayName(for url: URL) -> String {
        let bundleName = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String
        return bundleName ?? url.deletingPathExtension().lastPathComponent
    }

    private static func normalize(_ string: String) -> String {
        string
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    private static func acronym(_ string: String) -> String {
        string
            .split { !$0.isLetter && !$0.isNumber }
            .compactMap(\.first)
            .map { String($0).lowercased() }
            .joined()
    }
}
