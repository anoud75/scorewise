import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct ScoreWiseApp: App {
    @StateObject private var viewModel = AppViewModel()
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(ScoreWiseAppDelegate.self) private var appDelegate
    #endif

    var sharedModelContainer: ModelContainer = AppModelContainer.makeShared()

    init() {
        FirebaseBootstrap.configureIfPossible()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(viewModel)
        }
        .modelContainer(sharedModelContainer)
    }
}

#if canImport(UIKit)
final class ScoreWiseAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        #if canImport(GoogleSignIn)
        let googleSchemes = (Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])?
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] } ?? []

        guard let scheme = url.scheme, googleSchemes.contains(where: { $0.caseInsensitiveCompare(scheme) == .orderedSame }) else {
            return false
        }
        return GIDSignIn.sharedInstance.handle(url)
        #else
        return false
        #endif
    }
}
#endif

private enum AppModelContainer {
    static func makeShared() -> ModelContainer {
        do {
            return try makePersistentContainer()
        } catch {
            print("ScoreWise: persistent SwiftData store failed to load: \(error)")
            deleteExistingStoreArtifacts()
            do {
                return try makePersistentContainer()
            } catch {
                print("ScoreWise: rebuilt SwiftData store still failed. Falling back to in-memory container: \(error)")
                do {
                    return try makeInMemoryContainer()
                } catch {
                    fatalError("Failed to create fallback ModelContainer: \(error)")
                }
            }
        }
    }

    private static func makePersistentContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration("ScoreWise")
        return try ModelContainer(
            for: UserProfileEntity.self,
            RankingProjectEntity.self,
            VendorEntity.self,
            CriterionEntity.self,
            ScoreEntryEntity.self,
            InsightReportEntity.self,
            ChatThreadEntity.self,
            ChatMessageEntity.self,
            ProjectVersionEntity.self,
            configurations: configuration
        )
    }

    private static func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: UserProfileEntity.self,
            RankingProjectEntity.self,
            VendorEntity.self,
            CriterionEntity.self,
            ScoreEntryEntity.self,
            InsightReportEntity.self,
            ChatThreadEntity.self,
            ChatMessageEntity.self,
            ProjectVersionEntity.self,
            configurations: configuration
        )
    }

    private static func deleteExistingStoreArtifacts() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let storeBase = appSupport?.appendingPathComponent("default.store")
        let candidates = [
            storeBase,
            storeBase?.appendingPathExtension("sqlite"),
            storeBase?.appendingPathExtension("sqlite-wal"),
            storeBase?.appendingPathExtension("sqlite-shm"),
            appSupport?.appendingPathComponent("ScoreWise.store"),
            appSupport?.appendingPathComponent("ScoreWise.store-wal"),
            appSupport?.appendingPathComponent("ScoreWise.store-shm")
        ].compactMap { $0 }

        for url in candidates where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }
}
