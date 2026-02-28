import Foundation
import UIKit

enum AssetImageLoader {
    private static let cacheLock = NSLock()
    private static var fileIndexByBundleURL: [URL: [String: URL]] = [:]
    private static var fileIndexByRootURL: [URL: [String: URL]] = [:]

    static func image(named name: String) -> UIImage? {
        for bundle in resourceBundles {
            if let image = UIImage(named: name, in: bundle, compatibleWith: nil) {
                return image
            }
        }

        if let url = resourceURL(named: name, extensions: ["png", "jpg", "jpeg", "webp"]),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            return image
        }

        return nil
    }

    static func resourceURL(named name: String, extensions: [String]) -> URL? {
        resourceURLs(named: name, extensions: extensions).first
    }

    static func resourceURLs(named name: String, extensions: [String]) -> [URL] {
        let nameNSString = name as NSString
        let explicitExt = nameNSString.pathExtension.lowercased()
        let baseName = explicitExt.isEmpty ? name : nameNSString.deletingPathExtension
        let exts = explicitExt.isEmpty ? extensions.map { $0.lowercased() } : [explicitExt]
        let fileNames = Set(exts.map { "\(baseName).\($0)".lowercased() })
        var orderedURLs: [URL] = []
        var seen = Set<URL>()

        func append(_ url: URL) {
            if !seen.contains(url) {
                seen.insert(url)
                orderedURLs.append(url)
            }
        }

        for bundle in resourceBundles {
            for ext in exts {
                if let url = bundle.url(forResource: baseName, withExtension: ext) {
                    append(url)
                }
            }

            let index = indexedFiles(for: bundle)
            for fileName in fileNames {
                if let url = index[fileName] {
                    append(url)
                }
            }
        }

        // Playgrounds fallback: read directly from the project Resources folder on disk.
        for root in resourceRootDirectories {
            let index = indexedFiles(forRoot: root)
            for fileName in fileNames {
                if let url = index[fileName] {
                    append(url)
                }
            }
        }

        return orderedURLs
    }

    static var resourceBundles: [Bundle] {
        var seen = Set<URL>()
        var bundles: [Bundle] = []

        func append(_ bundle: Bundle) {
            let key = bundle.bundleURL
            if !seen.contains(key) {
                seen.insert(key)
                bundles.append(bundle)
            }
        }

        #if SWIFT_PACKAGE
        append(.module)
        #endif
        append(.main)
        Bundle.allBundles.forEach(append)
        Bundle.allFrameworks.forEach(append)

        return bundles
    }

    private static var resourceRootDirectories: [URL] {
        var roots: [URL] = []
        var seen = Set<URL>()

        func append(_ url: URL) {
            if !seen.contains(url) {
                seen.insert(url)
                roots.append(url)
            }
        }

        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let designDir = sourceFileURL.deletingLastPathComponent()
        let sourcesDir = designDir.deletingLastPathComponent()
        let packageRoot = sourcesDir.deletingLastPathComponent()
        append(packageRoot.appendingPathComponent("Resources", isDirectory: true))

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        append(cwd.appendingPathComponent("Resources", isDirectory: true))
        append(cwd.appendingPathComponent("FirstSign.swiftpm/Resources", isDirectory: true))

        return roots.filter { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    private static func indexedFiles(for bundle: Bundle) -> [String: URL] {
        let bundleURL = bundle.bundleURL

        cacheLock.lock()
        if let cached = fileIndexByBundleURL[bundleURL] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        var index: [String: URL] = [:]
        if let resourceURL = bundle.resourceURL,
           let enumerator = FileManager.default.enumerator(
               at: resourceURL,
               includingPropertiesForKeys: [.isRegularFileKey],
               options: [.skipsHiddenFiles]
           ) {
            for case let fileURL as URL in enumerator {
                let key = fileURL.lastPathComponent.lowercased()
                if index[key] == nil {
                    index[key] = fileURL
                }
            }
        }

        cacheLock.lock()
        fileIndexByBundleURL[bundleURL] = index
        cacheLock.unlock()

        return index
    }

    private static func indexedFiles(forRoot rootURL: URL) -> [String: URL] {
        cacheLock.lock()
        if let cached = fileIndexByRootURL[rootURL] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        var index: [String: URL] = [:]
        if let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                let key = fileURL.lastPathComponent.lowercased()
                if index[key] == nil {
                    index[key] = fileURL
                }
            }
        }

        cacheLock.lock()
        fileIndexByRootURL[rootURL] = index
        cacheLock.unlock()

        return index
    }
}
