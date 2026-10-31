import UIKit

enum Theme {
    static let background = UIColor(red: 0.055, green: 0.059, blue: 0.075, alpha: 1)
    static let surface = UIColor(red: 0.105, green: 0.112, blue: 0.137, alpha: 1)
    static let surfaceHigh = UIColor(red: 0.16, green: 0.17, blue: 0.205, alpha: 1)
    static let accent = UIColor(red: 0.49, green: 0.40, blue: 1.0, alpha: 1)
    static let text = UIColor.white
    static let secondaryText = UIColor(white: 0.62, alpha: 1)

    static func applyAppearance() {
        let nav = UINavigationBar.appearance()
        nav.barStyle = .black
        nav.barTintColor = background
        nav.isTranslucent = false
        nav.tintColor = accent
        nav.shadowImage = UIImage()
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]

        let tab = UITabBar.appearance()
        tab.barStyle = .black
        tab.barTintColor = background
        tab.isTranslucent = false
        tab.tintColor = accent

        if #available(iOS 13.0, *) {
            let navAppearance = UINavigationBarAppearance()
            navAppearance.configureWithOpaqueBackground()
            navAppearance.backgroundColor = background
            navAppearance.shadowColor = .clear
            navAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
            navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
            nav.standardAppearance = navAppearance
            nav.scrollEdgeAppearance = navAppearance
            nav.compactAppearance = navAppearance

            let tabAppearance = UITabBarAppearance()
            tabAppearance.configureWithOpaqueBackground()
            tabAppearance.backgroundColor = background
            tab.standardAppearance = tabAppearance
            if #available(iOS 15.0, *) { tab.scrollEdgeAppearance = tabAppearance }
        }

        UISegmentedControl.appearance().tintColor = accent
    }
}

/// Tab and button icons drawn in code (SF Symbols need iOS 13).
enum Icons {
    private static func make(_ size: CGFloat = 25, _ draw: () -> Void) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { _ in
            UIColor.black.setStroke()
            UIColor.black.setFill()
            draw()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    static let home: UIImage = make {
        let p = UIBezierPath()
        p.lineWidth = 2
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        p.move(to: CGPoint(x: 3, y: 12))
        p.addLine(to: CGPoint(x: 12.5, y: 3.5))
        p.addLine(to: CGPoint(x: 22, y: 12))
        p.move(to: CGPoint(x: 6, y: 9.5))
        p.addLine(to: CGPoint(x: 6, y: 21.5))
        p.addLine(to: CGPoint(x: 19, y: 21.5))
        p.addLine(to: CGPoint(x: 19, y: 9.5))
        p.stroke()
    }

    static let search: UIImage = make {
        let c = UIBezierPath(ovalIn: CGRect(x: 3.5, y: 3.5, width: 13, height: 13))
        c.lineWidth = 2
        c.stroke()
        let l = UIBezierPath()
        l.lineWidth = 2.2
        l.lineCapStyle = .round
        l.move(to: CGPoint(x: 15, y: 15))
        l.addLine(to: CGPoint(x: 21.5, y: 21.5))
        l.stroke()
    }

    static let library: UIImage = make {
        let p = UIBezierPath()
        p.lineWidth = 2
        p.lineJoinStyle = .round
        p.move(to: CGPoint(x: 6, y: 3.5))
        p.addLine(to: CGPoint(x: 19, y: 3.5))
        p.addLine(to: CGPoint(x: 19, y: 21.5))
        p.addLine(to: CGPoint(x: 12.5, y: 16.5))
        p.addLine(to: CGPoint(x: 6, y: 21.5))
        p.close()
        p.stroke()
    }

    static let addons: UIImage = make {
        let origins: [CGPoint] = [CGPoint(x: 3.5, y: 3.5), CGPoint(x: 13.5, y: 3.5),
                                  CGPoint(x: 3.5, y: 13.5), CGPoint(x: 13.5, y: 13.5)]
        for o in origins {
            let r = UIBezierPath(roundedRect: CGRect(origin: o, size: CGSize(width: 8, height: 8)), cornerRadius: 2)
            r.lineWidth = 2
            r.stroke()
        }
    }

    static let bigPlay: UIImage = make(44) {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: 11, y: 5))
        p.addLine(to: CGPoint(x: 39, y: 22))
        p.addLine(to: CGPoint(x: 11, y: 39))
        p.close()
        p.fill()
    }

    static let bigPause: UIImage = make(44) {
        UIBezierPath(roundedRect: CGRect(x: 9, y: 6, width: 9, height: 32), cornerRadius: 2).fill()
        UIBezierPath(roundedRect: CGRect(x: 26, y: 6, width: 9, height: 32), cornerRadius: 2).fill()
    }

    static let close: UIImage = make(22) {
        let p = UIBezierPath()
        p.lineWidth = 2.4
        p.lineCapStyle = .round
        p.move(to: CGPoint(x: 4, y: 4))
        p.addLine(to: CGPoint(x: 18, y: 18))
        p.move(to: CGPoint(x: 18, y: 4))
        p.addLine(to: CGPoint(x: 4, y: 18))
        p.stroke()
    }

    static let compass: UIImage = make {
        let c = UIBezierPath(ovalIn: CGRect(x: 3, y: 3, width: 19, height: 19))
        c.lineWidth = 2
        c.stroke()
        let p = UIBezierPath()
        p.move(to: CGPoint(x: 16.5, y: 8.5))
        p.addLine(to: CGPoint(x: 14, y: 14))
        p.addLine(to: CGPoint(x: 8.5, y: 16.5))
        p.addLine(to: CGPoint(x: 11, y: 11))
        p.close()
        p.fill()
    }

    static let gear: UIImage = make {
        let c = UIBezierPath(ovalIn: CGRect(x: 8.5, y: 8.5, width: 8, height: 8))
        c.lineWidth = 2
        c.stroke()
        let p = UIBezierPath()
        p.lineWidth = 2.6
        p.lineCapStyle = .round
        for i in 0..<8 {
            let a = CGFloat(i) * .pi / 4
            p.move(to: CGPoint(x: 12.5 + cos(a) * 6.5, y: 12.5 + sin(a) * 6.5))
            p.addLine(to: CGPoint(x: 12.5 + cos(a) * 9.5, y: 12.5 + sin(a) * 9.5))
        }
        p.stroke()
        let ring = UIBezierPath(ovalIn: CGRect(x: 6, y: 6, width: 13, height: 13))
        ring.lineWidth = 2
        ring.stroke()
    }

    static let pip: UIImage = make(22) {
        let outer = UIBezierPath(roundedRect: CGRect(x: 1.5, y: 3.5, width: 19, height: 15), cornerRadius: 2)
        outer.lineWidth = 1.8
        outer.stroke()
        UIBezierPath(roundedRect: CGRect(x: 10.5, y: 10.5, width: 8, height: 6), cornerRadius: 1).fill()
    }

    static let play: UIImage = make(16) {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: 3, y: 1.5))
        p.addLine(to: CGPoint(x: 14.5, y: 8))
        p.addLine(to: CGPoint(x: 3, y: 14.5))
        p.close()
        p.fill()
    }
}

final class GradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    var colors: [UIColor] = [] {
        didSet { (layer as? CAGradientLayer)?.colors = colors.map { $0.cgColor } }
    }
}

final class ProgressBar: UIView {
    private let fill = UIView()
    var progress: Double = 0 { didSet { setNeedsLayout() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 1, alpha: 0.25)
        layer.cornerRadius = 1.5
        clipsToBounds = true
        fill.backgroundColor = Theme.accent
        addSubview(fill)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let p = CGFloat(min(max(progress, 0), 1))
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * p, height: bounds.height)
    }
}

extension UIViewController {
    /// The view controller currently on top of this one's presentation stack.
    var topPresenter: UIViewController {
        var vc: UIViewController = self
        while let p = vc.presentedViewController, !p.isBeingDismissed { vc = p }
        return vc
    }

    func showAlert(_ title: String, _ message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        topPresenter.present(alert, animated: true)
    }

    /// Presents an action sheet safely on both iPhone and iPad.
    func presentSheet(_ sheet: UIAlertController, from source: UIView?) {
        if let pop = sheet.popoverPresentationController {
            if let s = source {
                pop.sourceView = s
                pop.sourceRect = s.bounds
            } else {
                pop.sourceView = view
                pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
                pop.permittedArrowDirections = []
            }
        }
        topPresenter.present(sheet, animated: true)
    }
}
