import UIKit

/// Small image cache: memory (NSCache) + disk (URLCache), with downscaling so
/// older devices don't run out of memory on big posters.
final class ImageLoader {
    static let shared = ImageLoader()

    private let memory = NSCache<NSString, UIImage>()
    private let session: URLSession
    private var waiting: [String: [(UIImage?) -> Void]] = [:] // main-thread only

    private init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024, diskPath: "lumen-images")
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
        memory.countLimit = 250
    }

    func load(_ urlString: String?, maxPixel: CGFloat = 720, completion: @escaping (UIImage?) -> Void) {
        guard let s = urlString, let url = StreamItem.makeURL(s) else { completion(nil); return }
        let key = "\(s)#\(Int(maxPixel))"
        if let cached = memory.object(forKey: key as NSString) { completion(cached); return }
        if waiting[key] != nil { waiting[key]?.append(completion); return }
        waiting[key] = [completion]

        session.dataTask(with: url) { data, _, _ in
            var image: UIImage?
            if let data = data, let raw = UIImage(data: data) {
                image = ImageLoader.downscale(raw, maxPixel: maxPixel)
            }
            DispatchQueue.main.async {
                if let image = image { self.memory.setObject(image, forKey: key as NSString) }
                let callbacks = self.waiting.removeValue(forKey: key) ?? []
                callbacks.forEach { $0(image) }
            }
        }.resume()
    }

    private static func downscale(_ image: UIImage, maxPixel: CGFloat) -> UIImage {
        let pixelW = image.size.width * image.scale
        let pixelH = image.size.height * image.scale
        let longest = max(pixelW, pixelH)
        let ratio = longest > maxPixel ? maxPixel / longest : 1
        let size = CGSize(width: floor(pixelW * ratio), height: floor(pixelH * ratio))
        guard size.width > 0, size.height > 0 else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // Drawing also forces decoding off the main thread.
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private var imageTokenKey: UInt8 = 0

extension UIImageView {
    func loadImage(_ urlString: String?, maxPixel: CGFloat = 720) {
        let token = UUID().uuidString
        objc_setAssociatedObject(self, &imageTokenKey, token, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        image = nil
        ImageLoader.shared.load(urlString, maxPixel: maxPixel) { [weak self] img in
            guard let self = self,
                  (objc_getAssociatedObject(self, &imageTokenKey) as? String) == token,
                  let img = img else { return }
            self.alpha = 0
            self.image = img
            UIView.animate(withDuration: 0.2) { self.alpha = 1 }
        }
    }
}
