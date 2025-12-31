import Foundation
import SDWebImage

public extension Notification.Name {
    static let photoLoaded = Notification.Name("SSPHOTO_LOADING_DID_END_NOTIFICATION")
    static let photoProgress = Notification.Name("SSPHOTO_LOADING_PROGRESS_NOTIFICATION")
}

class SSPhoto: NSObject {
    
    var underlyingImage: UIImage?
    var urlString: String
    var isLoading = false
    let imageCache = SDWebImageManager.shared.imageCache as! SDImageCache
    var pageIndex: IndexPath?
    static var altLoader = SDWebImageDownloader()
    
    init(URL url: String) {
        urlString = url
        super.init()
    }

    func loadUnderlyingImageAndNotify() {
        guard isLoading == false, underlyingImage == nil else { return } 
        isLoading = true
        
        RequestManager.shared.getPageImageUrl(url: urlString) { [weak self] url in
            guard let self = self else { return }
            guard let url = url else {
                self.imageLoadComplete()
                return
            }
            SSPhoto.altLoader.downloadImage( with: URL(string: url)!, options: [.highPriority, .handleCookies, .useNSURLCache], progress: { [weak self] recv, total, url in
                var dict: Dictionary = [String: Int]()
                dict["recv"] = recv
                dict["total"] = total
                DispatchQueue.main.async {
                    NotificationCenter.default.post( name: .photoProgress, object: self, userInfo: dict )
                }
            }, completed: { [weak self] image, _, _, _ in
                guard let self = self else { return }
                self.imageCache.store(image, forKey: self.urlString)
                self.underlyingImage = image
                DispatchQueue.main.async {
                    self.imageLoadComplete()
                }
            })
        }
    }

    func checkCache() {
        if let memoryCache = imageCache.imageFromMemoryCache(forKey: urlString) {
            underlyingImage = memoryCache
            imageLoadComplete()
            return
        }
        
        imageCache.queryCacheOperation(forKey: urlString) { [weak self] image, _, _ in
            if let diskCache = image, let self = self {
                self.underlyingImage = diskCache
                self.imageLoadComplete()
            }
        }
    }

    func imageLoadComplete() {
        isLoading = false
        NotificationCenter.default.post(name: .photoLoaded, object: self)
    }
}
