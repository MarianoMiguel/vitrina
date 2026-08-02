import Foundation

enum AppMetadata {
    static let productName = "Vitrina"
    static let companyName = "Interstellar Computer"
    static let legalEntity = "Mariano Miguel, LLC"
    static let website = "https://interstellar.computer"
    static let bundleIdentifier = "computer.interstellar.vitrina"
    static let repositoryURL = URL(string: "https://github.com/MarianoMiguel/vitrina")!
    static let updateFeedURL = URL(string: "https://github.com/MarianoMiguel/vitrina/releases/latest/download/appcast.json")!

    static var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    static var buildString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var producerLine: String {
        "\(companyName), a DBA of \(legalEntity)"
    }
}
