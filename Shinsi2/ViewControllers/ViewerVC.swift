import UIKit
import Hero
import SDWebImage
import Photos

class ViewerVC: UICollectionViewController {
    
    enum ViewerMode: Int {
        case horizontal = 0
        case vertical = 1
        case doublePage = 2
    }
    var selectedIndexPath: IndexPath? {
        set { _selectedIndexPath = newValue }
        get {
            if let i = _selectedIndexPath { return IndexPath(item: i.item + (Defaults.Gallery.isAppendBlankPage ? 1 : 0), section: i.section) }
            return _selectedIndexPath
        }
    }
    private var _selectedIndexPath: IndexPath?
    weak var doujinshi: Doujinshi!
    private lazy var browsingHistory: BrowsingHistory? = {
        return RealmManager.shared.browsingHistory(for: doujinshi)
    }()
    var pages: [Page] {
        var ps = Array(doujinshi.pages)
        if Defaults.Gallery.isAppendBlankPage { ps.insert(Page.blankPage(), at: 0) }
        if Defaults.Viewer.shouldUseDoubleSidedViewer && ps.count % 2 != 0 { ps.append(Page.blankPage()) } // Fix
        return ps
    }
    var mode: ViewerMode {
        if Defaults.Viewer.shouldUseDoubleSidedViewer && collectionView!.bounds.width > 1000 && collectionView!.bounds.width > collectionView!.bounds.height {
            return .doublePage
        } else {
            return Defaults.Viewer.mode
        }
    }
    private var exiting = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if !doujinshi.isDownloaded {
            pages.forEach{ $0.photo.checkCache() }
        }
        view.layoutIfNeeded()
        collectionView?.reloadData()
        
        if let selectedIndex = selectedIndexPath {
            DispatchQueue.main.async{ [self] in
                switch mode {
                case .horizontal:
                    collectionView!.scrollToItem(at: selectedIndex, at: .right, animated: false)
                case .vertical:
                    collectionView!.scrollToItem(at: selectedIndex, at: .top, animated: false)
                case .doublePage:
                    collectionView!.scrollToItem(at: selectedIndex.item % 2 != 0 ? selectedIndex : convertIndexPath(from: selectedIndex), at: .right, animated: false)
                }
            }
        }
        
        //Close gesture
        let panGR = UIPanGestureRecognizer()
        panGR.addTarget(self, action: #selector(pan(ges:)))
        panGR.delegate = self
        collectionView?.addGestureRecognizer(panGR)
        
        let tapToCloseGesture = UITapGestureRecognizer(target: self, action: #selector(tapToClose(ges:)))
        tapToCloseGesture.numberOfTapsRequired = 1
        collectionView?.addGestureRecognizer(tapToCloseGesture)
        
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(longPress(ges:)))
        longPressGesture.delaysTouchesBegan = true
        collectionView?.addGestureRecognizer(longPressGesture)
        
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        NotificationCenter.default.addObserver(self, selector: #selector(handleSKPhotoLoadingDidEndNotification(notification:)), name: .photoLoaded, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSKPhotoLoadingProgressNotification(notification:)), name: .photoProgress, object: nil)
        
        if #available(iOS 13.0, *) {
            NotificationCenter.default.addObserver(self, selector: #selector(willResignActive), name: UIScene.willDeactivateNotification, object: nil)
        } else {
            NotificationCenter.default.addObserver(self, selector: #selector(willResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        updateBrowsingHistory()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        guard UIApplication.shared.applicationState == .active else {return} 
        let indexPath = collectionView.indexPathsForVisibleItems.first
        super.viewWillTransition(to: size, with: coordinator)
        collectionView?.collectionViewLayout.invalidateLayout()
        coordinator.animate(alongsideTransition: { _ in
            if let indexPath = indexPath {
                self.collectionView.reloadData()
                let covertedIndexPath = self.mode == .doublePage ? self.convertIndexPath(from: indexPath) : indexPath
                let position: UICollectionView.ScrollPosition = self.mode == .vertical ? .top : (covertedIndexPath.item % 2 == 0 ? .left : .right)
                self.collectionView!.scrollToItem(at: covertedIndexPath, at: position, animated: false)
            }
        })
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView?.isPagingEnabled = mode != .vertical
        if let layout = collectionView?.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.scrollDirection = mode == .vertical ? .vertical : .horizontal
        }
    }
    
    override var prefersStatusBarHidden: Bool { return !exiting }
    
    override var prefersHomeIndicatorAutoHidden: Bool { return true }
    
    @objc func longPress(ges: UILongPressGestureRecognizer) {
        guard ges.state == .began else {return}
        let p = ges.location(in: collectionView)
        if let indexPath = collectionView!.indexPathForItem(at: p) {
            let item = getPage(for: indexPath)
            if !doujinshi.isDownloaded && item.photo.underlyingImage == nil {return}
            let image = doujinshi.isDownloaded ? item.localImage! : item.photo.underlyingImage!
            
            let alert = UIAlertController(title: "Save to camera roll", message: nil, preferredStyle: .alert)
            let ok = UIAlertAction(title: "OK", style: .default) { _ in
                PHPhotoLibrary.requestAuthorization({ s in
                    if s == .authorized {
                        PHPhotoLibrary.shared().performChanges({
                            PHAssetChangeRequest.creationRequestForAsset(from: image)
                        }, completionHandler: nil)
                    }
                })

            }
            let cancel = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
            alert.addAction(ok)
            alert.addAction(cancel)
            present(alert, animated: true, completion: nil)
        }
    }
    
    @objc func tapToClose(ges: UITapGestureRecognizer) {
        dismiss(animated: true, completion: nil)
        exiting = true
    }
    
    @objc func pan(ges: UIPanGestureRecognizer) {
        guard mode != .vertical else {return}
        let translation = ges.translation(in: nil)
        let progress = translation.y / collectionView!.bounds.height
        switch ges.state {
        case .began:
            hero.dismissViewController()
        case .changed:
            exiting = true
            setNeedsStatusBarAppearanceUpdate()
            Hero.shared.update(progress)
            for indexPath in collectionView!.indexPathsForVisibleItems {
                let cell = collectionView!.cellForItem(at: indexPath) as! ScrollingImageCell
                let currentPos = CGPoint(x: translation.x + view.center.x, y: translation.y + view.center.y)
                if mode == .doublePage {
                    let size = collectionView(collectionView!, layout: collectionView!.collectionViewLayout, sizeForItemAt: indexPath)
                    let pos = indexPath.item % 2 == 0 ?
                        CGPoint(x: currentPos.x - size.width/2, y: currentPos.y) :
                        CGPoint(x: currentPos.x + size.width/2, y: currentPos.y)
                    Hero.shared.apply(modifiers: [.position(pos)], to: cell.imageView)
                } else {
                    Hero.shared.apply(modifiers: [.position(currentPos)], to: cell.imageView)
                }
            }
        default:
            if progress + ges.velocity(in: nil).y / collectionView!.bounds.height > 0.3 {
                Hero.shared.finish()
            } else {
                Hero.shared.cancel()
                exiting = false
                setNeedsStatusBarAppearanceUpdate()
            }
        }
    }
    
    @objc func willResignActive(_ notification: Notification) {
        updateBrowsingHistory()
    }
    
    private func updateBrowsingHistory() {
        guard let browsingHistory = browsingHistory, let currentPage = selectedIndexPath?.item else { return }
        RealmManager.shared.updateBrowsingHistory(browsingHistory, currentPage: currentPage)
    }
}

extension ViewerVC: UICollectionViewDelegateFlowLayout {
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return pages.count
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = (collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as? ScrollingImageCell)!
        cell.imageView.hero.id = heroID(for: indexPath)
        cell.imageView.hero.modifiers = [.arc(intensity: 1), .forceNonFade]
        cell.imageView.isOpaque = true
        
        let page = getPage(for: indexPath)
        if doujinshi.isDownloaded {
            cell.image = page.localImage
        } else {
            let photo = page.photo!
            photo.pageIndex = indexPath
            if let image = photo.underlyingImage {
                cell.image = image
            } else {
                if let image = ImageManager.shared.getCache(forKey: page.thumbUrl) { 
                    cell.image = image
                    if page.cropRect != nil {
                        let rect = page.cropRect!
                        let src = image.cgImage!
                        if src.height != Int(rect.size.height) as Int || src.width != Int(rect.size.width) as Int {
                            let cropped = src.cropping(to: rect)!
                            let newImage = UIImage(cgImage: cropped)
                            cell.imageView.image = newImage
                        }
                    }
                } else {
                    cell.imageView.sd_setImage(with: URL(string: page.thumbUrl), placeholderImage: nil, options: [.handleCookies],
                                               completed: { (image: UIImage?, _: Error?, _: SDImageCacheType, _: URL?) in
                        if page.cropRect == nil || image == nil { return }
                        let rect = page.cropRect!
                        let src = image!.cgImage!
                        if src.height == Int(rect.size.height) as Int && src.width == Int(rect.size.width) as Int { return }
                        let cropped = src.cropping(to: rect)!
                        let newImage = UIImage(cgImage: cropped)
                        cell.imageView.image = newImage
                    })
                }
                photo.loadUnderlyingImageAndNotify()
            }
        }
        
        //prefetch
        let pageIndex = indexPath.item
        for i in -4...4 {
            if i + pageIndex > doujinshi.pages.count - 1 { break }
            if i + pageIndex < 0 || i == 0 { continue }
            if let nextPhoto = doujinshi.pages[i + pageIndex].photo, nextPhoto.underlyingImage == nil {
                nextPhoto.loadUnderlyingImageAndNotify()
                ImageManager.shared.prefetch(urls: [URL(string: doujinshi.pages[i + pageIndex].thumbUrl)!])
            }
        }
        
        return cell
    } 
    
    func convertIndexPath(from indexPath: IndexPath) -> IndexPath {
        var i = indexPath.item
        if mode == .doublePage {
            i = i % 2 == 0 ? i + 1 : i - 1
            i = min(i, pages.count - 1)
        }
        return IndexPath(item: i, section: indexPath.section)
    }

    func heroID(for indexPath: IndexPath) -> String {
        let index = convertIndexPath(from: indexPath).item - (Defaults.Gallery.isAppendBlankPage ? 1 : 0)
        return "image_\(doujinshi.id)_\(index)"
    }

    func getPage(for indexPath: IndexPath) -> Page {
        return pages[convertIndexPath(from: indexPath).item]
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if mode == .doublePage {
            return CGSize(width: collectionView.bounds.width/2, height: collectionView.bounds.height)
        } else if mode == .horizontal {
            return collectionView.bounds.size
        } else {
            return CGSize(width: collectionView.bounds.size.width, height: collectionView.bounds.size.width * paperRatio)
        }
    }
    
    @objc func handleSKPhotoLoadingDidEndNotification(notification: Notification) {
        guard let photo = notification.object as? SSPhoto else { return }
        if photo.underlyingImage != nil {
            if photo.pageIndex != nil {
                // crash on ios 26: invalid update
                //collectionView.reloadItems(at: [photo.pageIndex!])
                let page = getPage(for: photo.pageIndex!)
                let cell = collectionView.cellForItem(at: photo.pageIndex!) as? ScrollingImageCell
                let image = photo.underlyingImage
                cell?.image = image
            }
            //collectionView.reloadData()
        }
    }
    @objc func handleSKPhotoLoadingProgressNotification(notification: Notification) {
        guard let photo = notification.object as? SSPhoto else { return }
        guard let pageIndex = photo.pageIndex else { return }
        guard let cell = collectionView.cellForItem(at: pageIndex) as? ScrollingImageCell else { return }
        let info = notification.userInfo as! [String: Int]
        cell.progress = Float(info["recv"] ?? 0) / Float(info["total"] ?? 1)
    }
    
}

extension ViewerVC: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard mode != .vertical else {return false}
        guard let panGR = gestureRecognizer as? UIPanGestureRecognizer else {return false}
        guard let cell = collectionView?.visibleCells[0] as? ScrollingImageCell, cell.scrollView.zoomScale == 1 else {return false}
        let v = panGR.velocity(in: nil)
        return v.y > abs(v.x)
    } 
}
