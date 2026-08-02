import Foundation

struct UpdateCheckResult {
    let title: String
    let detail: String
}

enum UpdateCheckController {
    static func checkForUpdates(completion: @escaping (UpdateCheckResult) -> Void) {
        let request = URLRequest(
            url: AppMetadata.updateFeedURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 8
        )

        URLSession.shared.dataTask(with: request) { data, response, error in
            let result: UpdateCheckResult

            if let error {
                result = UpdateCheckResult(
                    title: "Update feed unavailable",
                    detail: error.localizedDescription
                )
            } else if let httpResponse = response as? HTTPURLResponse,
                      !(200...299).contains(httpResponse.statusCode) {
                result = UpdateCheckResult(
                    title: "Update feed unavailable",
                    detail: "Server returned HTTP \(httpResponse.statusCode)."
                )
            } else if let data,
                      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let latestVersion = payload["latestVersion"] as? String {
                let downloadURL = payload["downloadURL"] as? String ?? AppMetadata.website
                result = updateResult(latestVersion: latestVersion, downloadURL: downloadURL)
            } else {
                result = UpdateCheckResult(
                    title: "Update feed unavailable",
                    detail: "The update feed is not published yet."
                )
            }

            DispatchQueue.main.async {
                completion(result)
            }
        }.resume()
    }

    private static func updateResult(latestVersion: String, downloadURL: String) -> UpdateCheckResult {
        let currentVersion = AppMetadata.versionString

        if latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
            return UpdateCheckResult(
                title: "Update available: \(latestVersion)",
                detail: downloadURL
            )
        }

        return UpdateCheckResult(
            title: "Vitrina is up to date",
            detail: "Current version: \(currentVersion)"
        )
    }
}
