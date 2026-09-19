import UIKit
import NetworkToolKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Enable NetworkInspector
        NetworkInspector.shared.enable(
            uiConfiguration: .init(
                environment: "Demo",
                exportFormats: [.plainText, .markdown]
            ),
            configuration: .init(
                maxChains: 200,
                maxPendingChains: 500,
                pendingChainTTL: 15 * 60
            )
        )
        
        // Setup window and root view controller
        window = UIWindow(frame: UIScreen.main.bounds)
        let mainViewController = MainViewController()
        let navigationController = UINavigationController(rootViewController: mainViewController)
        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()
        
        return true
    }
}
