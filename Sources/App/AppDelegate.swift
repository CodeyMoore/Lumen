import UIKit
import AVFoundation

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Theme.applyAppearance()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.backgroundColor = Theme.background
        window.tintColor = Theme.accent
        window.rootViewController = MainTabBarController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    /// Handles stremio://…/manifest.json links (the "Install" buttons on addon pages).
    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard let tabs = window?.rootViewController as? MainTabBarController else { return false }
        tabs.installAddon(from: url.absoluteString)
        return true
    }
}

final class MainTabBarController: UITabBarController {
    private let addonsController = AddonsViewController()

    override func viewDidLoad() {
        super.viewDidLoad()
        viewControllers = [
            wrap(HomeViewController(), title: "Home", icon: Icons.home),
            wrap(SearchViewController(), title: "Search", icon: Icons.search),
            wrap(LibraryViewController(), title: "Library", icon: Icons.library),
            wrap(addonsController, title: "Addons", icon: Icons.addons),
        ]
    }

    private func wrap(_ vc: UIViewController, title: String, icon: UIImage) -> UINavigationController {
        let nav = UINavigationController(rootViewController: vc)
        nav.tabBarItem = UITabBarItem(title: title, image: icon, selectedImage: nil)
        nav.navigationBar.prefersLargeTitles = true
        return nav
    }

    func installAddon(from urlString: String) {
        let show = { [weak self] in
            guard let self = self else { return }
            self.selectedIndex = 3
            (self.viewControllers?[3] as? UINavigationController)?.popToRootViewController(animated: false)
            self.addonsController.promptInstall(prefill: urlString)
        }
        if presentedViewController != nil {
            dismiss(animated: true, completion: show)
        } else {
            show()
        }
    }
}
