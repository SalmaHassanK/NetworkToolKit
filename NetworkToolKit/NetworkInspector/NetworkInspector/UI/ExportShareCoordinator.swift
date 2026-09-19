//
//  ExportShareCoordinator.swift
//  MPesaNetworkService
//
//  Centralises the share flow used by the inspector's panel and detail
//  screens: when more than one ``ExportFormat`` is configured a picker is
//  presented first, otherwise the share dialog opens directly.
//
//  Both call sites (``APILogsPanelVC`` for all chains, ``ChainDetailVC`` for
//  a single chain) supply small closures that produce the file to share, so
//  the coordinator stays unaware of the chain model itself.
//

import UIKit

struct ExportShareCoordinator {

    let formats: [ExportFormat]
    let barButton: UIBarButtonItem?
    /// Returns the file name + content for the `.plainText` format.
    let plainText: () -> (name: String, content: String)
    /// Returns the file name + content for the `.markdown` format.
    let markdown: () -> (name: String, content: String)
    /// Returns the directory URL for the `.brunoCollection` format.
    /// The coordinator handles zipping and copying to a stable location.
    let bruno: () -> URL

    func present(from viewController: UIViewController) {
        guard !formats.isEmpty else { return }

        if formats.count == 1 {
            run(format: formats[0], from: viewController)
            return
        }

        let picker = UIAlertController(title: "Share as…", message: nil, preferredStyle: .actionSheet)
        for format in formats {
            picker.addAction(UIAlertAction(title: format.displayTitle, style: .default) { _ in
                self.run(format: format, from: viewController)
            })
        }
        picker.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        picker.popoverPresentationController?.barButtonItem = barButton
        viewController.present(picker, animated: true)
    }

    private func run(format: ExportFormat, from viewController: UIViewController) {
        // Export builders pretty-print every recorded body, so they run
        // off-main; the share sheet is presented once the file is ready.
        switch format {
        case .plainText:
            DispatchQueue.global(qos: .userInitiated).async {
                let (name, content) = plainText()
                let url = APILogExporter.writeTempFile(named: name, content: content)
                DispatchQueue.main.async {
                    presentActivity(items: [url], from: viewController)
                }
            }

        case .markdown:
            DispatchQueue.global(qos: .userInitiated).async {
                let (name, content) = markdown()
                let url = APILogExporter.writeTempFile(named: name, content: content)
                DispatchQueue.main.async {
                    presentActivity(items: [url], from: viewController)
                }
            }

        case .brunoCollection:
            DispatchQueue.global(qos: .userInitiated).async {
                let dirURL = bruno()
                let coordinator = NSFileCoordinator()
                var coordError: NSError?
                coordinator.coordinate(readingItemAt: dirURL, options: .forUploading, error: &coordError) { zipURL in
                    let stableZip = FileManager.default.temporaryDirectory
                        .appendingPathComponent(dirURL.lastPathComponent + ".zip")
                    try? FileManager.default.removeItem(at: stableZip)
                    try? FileManager.default.copyItem(at: zipURL, to: stableZip)

                    DispatchQueue.main.async {
                        self.presentActivity(items: [stableZip], from: viewController)
                    }
                }
            }
        }
    }

    private func presentActivity(items: [Any], from viewController: UIViewController) {
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activity.popoverPresentationController?.barButtonItem = barButton
        viewController.present(activity, animated: true)
    }
}
