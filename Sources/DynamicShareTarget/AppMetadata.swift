import Foundation

enum AppMetadata {
    static let productName = "Vitrina"
    static let creatorName = "Mariano Miguel"
    static let website = "https://github.com/MarianoMiguel/vitrina"
    static let bundleIdentifier = "com.marianomiguel.vitrina"
    static let repositoryURL = URL(string: "https://github.com/MarianoMiguel/vitrina")!
    static let updateFeedURL = URL(string: "https://github.com/MarianoMiguel/vitrina/releases/latest/download/appcast.json")!

    static var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    static var buildString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

}
