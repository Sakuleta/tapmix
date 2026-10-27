import AppKit
import Foundation
import TapmixCore

@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    private var running = false

    func check() {
        guard !running else { return }
        running = true

        guard let url = URL(string: "https://api.github.com/repos/Sakuleta/tapmix/releases/latest")
        else {
            running = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            Task { @MainActor in
                self?.running = false
                self?.handle(data: data, error: error)
            }
        }.resume()
    }

    private func handle(data: Data?, error: Error?) {
        guard error == nil,
              let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let urlString = json["html_url"] as? String,
              let releaseURL = URL(string: urlString)
        else {
            present(
                title: "Update check failed",
                message: "GitHub could not be reached. Try again later.",
                open: nil
            )
            return
        }

        let current = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0"

        if AppUpdate.isNewer(tag, than: current) {
            present(
                title: "Tapmix \(tag) is available",
                message: "You are running \(current). Download the latest notarized build from GitHub.",
                open: releaseURL
            )
        } else {
            present(
                title: "Tapmix is up to date",
                message: "You are running \(current).",
                open: nil
            )
        }
    }

    private func present(title: String, message: String, open url: URL?) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: url == nil ? "OK" : "Open Release")
        if url != nil {
            alert.addButton(withTitle: "Later")
        }

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if let url, response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(url)
        }
    }
}
