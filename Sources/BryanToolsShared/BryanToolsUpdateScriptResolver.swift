import Foundation

public struct BryanToolsUpdateScriptResolution: Equatable {
    public let sourceRoot: URL
    public let scriptURL: URL
}

public enum BryanToolsUpdateScriptResolver {
    public static let sourceRootDefaultsKey = "bryanTools.updater.sourceRoot"

    public static func resolve(
        configuredSourceRoot: URL? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundleURL: URL? = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) -> BryanToolsUpdateScriptResolution? {
        candidateSourceRoots(
            configuredSourceRoot: configuredSourceRoot,
            homeDirectory: homeDirectory,
            bundleURL: bundleURL
        )
        .lazy
        .compactMap { sourceRoot in
            guard validateSourceRoot(sourceRoot, fileManager: fileManager) == nil else {
                return nil
            }
            let scriptURL = sourceRoot.appendingPathComponent("Scripts/update.sh")
            return BryanToolsUpdateScriptResolution(sourceRoot: sourceRoot, scriptURL: scriptURL)
        }
        .first
    }

    public static func validateSourceRoot(_ sourceRoot: URL, fileManager: FileManager = .default) -> String? {
        let scriptURL = sourceRoot.appendingPathComponent("Scripts/update.sh")
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: scriptURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return "Selected folder does not contain Scripts/update.sh."
        }

        let packageURL = sourceRoot.appendingPathComponent("Package.swift")
        guard fileManager.fileExists(atPath: packageURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return "Selected folder does not contain Package.swift."
        }

        guard let packageText = try? String(contentsOf: packageURL, encoding: .utf8),
              packageText.contains("name: \"BryanTools\""),
              packageText.contains("executable(name: \"BryanTools\"") else {
            return "Selected Package.swift is not the BryanTools package."
        }

        let appEntryURL = sourceRoot.appendingPathComponent("Sources/BryanTools/App/BryanToolsApp.swift")
        guard fileManager.fileExists(atPath: appEntryURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return "Selected folder does not contain the BryanTools app source."
        }

        return nil
    }

    public static func candidateSourceRoots(
        configuredSourceRoot: URL? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundleURL: URL? = Bundle.main.bundleURL
    ) -> [URL] {
        var candidates: [URL] = []

        if let configuredSourceRoot {
            candidates.append(configuredSourceRoot)
        }

        candidates.append(homeDirectory.appendingPathComponent("code/BryanTools", isDirectory: true))
        candidates.append(homeDirectory.appendingPathComponent("BryanTools", isDirectory: true))
        candidates.append(homeDirectory.appendingPathComponent("Documents/BryanTools", isDirectory: true))

        if let sourceRoot = sourceRootContainingBuildBundle(bundleURL) {
            candidates.append(sourceRoot)
        }

        return uniqueStandardized(candidates)
    }

    public static func sourceRootContainingBuildBundle(_ bundleURL: URL?) -> URL? {
        guard let bundleURL else {
            return nil
        }

        let buildDirectory = bundleURL.deletingLastPathComponent()
        guard buildDirectory.lastPathComponent == ".build" else {
            return nil
        }
        return buildDirectory.deletingLastPathComponent()
    }

    private static func uniqueStandardized(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.compactMap { url in
            let standardizedURL = url.standardizedFileURL
            guard seen.insert(standardizedURL.path).inserted else {
                return nil
            }
            return standardizedURL
        }
    }
}
