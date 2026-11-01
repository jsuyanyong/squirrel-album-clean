import SwiftUI
import Photos

@MainActor
final class PhotoLibraryStore: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private(set) var photos: [LibraryPhoto] = []
    @Published private(set) var albums: [LibraryAlbum] = []
    @Published private(set) var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var isDemo = false
    @Published private(set) var isLoading = false
    @Published private(set) var isWorking = false
    @Published private(set) var reviewed: Set<String> = []
    @Published private(set) var unsure: Set<String> = []
    @Published var pendingDeletion: Set<String> = [] {
        didSet {
            if !isDemo { UserDefaults.standard.set(Array(pendingDeletion), forKey: "photoclear.pending") }
        }
    }
    @Published private(set) var totalSavedBytes: Int64 = 0
    @Published var errorMessage: String?
    @Published var notice: String?

    private let reviewedKey = "photoclear.reviewed"
    private let unsureKey = "photoclear.unsure"
    private let savedBytesKey = "photoclear.savedBytes"

    override init() {
        super.init()
        reviewed = Set(UserDefaults.standard.stringArray(forKey: reviewedKey) ?? [])
        unsure = Set(UserDefaults.standard.stringArray(forKey: unsureKey) ?? [])
        pendingDeletion = Set(UserDefaults.standard.stringArray(forKey: "photoclear.pending") ?? [])
        totalSavedBytes = Int64(UserDefaults.standard.integer(forKey: savedBytesKey))
        PHPhotoLibrary.shared().register(self)
        if hasAccess { reload() }
    }

    deinit { PHPhotoLibrary.shared().unregisterChangeObserver(self) }

    var hasAccess: Bool { authorization == .authorized || authorization == .limited }
    var unreviewed: [LibraryPhoto] {
        photos.filter { !reviewed.contains($0.id) && !pendingDeletion.contains($0.id) }
    }
    var reviewedPhotos: [LibraryPhoto] { photos.filter { reviewed.contains($0.id) } }
    var unsurePhotos: [LibraryPhoto] { photos.filter { unsure.contains($0.id) } }
    var pendingPhotos: [LibraryPhoto] { photos.filter { pendingDeletion.contains($0.id) } }
    var savedBytes: Int64 { totalSavedBytes }
    var savedSpaceText: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: max(savedBytes, 0))
    }
    var months: [PhotoMonth] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: photos) {
            calendar.dateInterval(of: .month, for: $0.date)?.start ?? $0.date
        }
        return grouped.map { PhotoMonth(date: $0.key, photos: $0.value) }.sorted { $0.date > $1.date }
    }

    func requestAccess() async {
        authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        if hasAccess {
            isDemo = false
            reviewed = Set(UserDefaults.standard.stringArray(forKey: reviewedKey) ?? [])
            unsure = Set(UserDefaults.standard.stringArray(forKey: unsureKey) ?? [])
            reload()
        }
    }

    func refreshAuthorization() {
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if hasAccess && !isDemo { reload() }
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            guard let self, !self.isDemo else { return }
            self.refreshAuthorization()
        }
    }

    private func photo(from asset: PHAsset) -> LibraryPhoto {
        LibraryPhoto(id: asset.localIdentifier, asset: asset, date: asset.creationDate ?? .distantPast,
                     isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                     isVideo: asset.mediaType == .video, isFavorite: asset.isFavorite, demoIndex: nil)
    }

    func reload() {
        guard hasAccess, !isDemo else { return }
        isLoading = true
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        var loaded: [LibraryPhoto] = []
        result.enumerateObjects { asset, _, _ in loaded.append(self.photo(from: asset)) }
        photos = loaded
        let loadedIDs = Set(loaded.map(\.id))
        reviewed.formIntersection(loadedIDs)
        unsure.formIntersection(loadedIDs)
        pendingDeletion.formIntersection(loadedIDs)
        reviewed.subtract(pendingDeletion)
        unsure.subtract(reviewed)
        unsure.subtract(pendingDeletion)
        persistReviewed()
        persistUnsure()
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        var loadedAlbums: [LibraryAlbum] = []
        collections.enumerateObjects { collection, _, _ in
            let assets = PHAsset.fetchAssets(in: collection, options: options)
            loadedAlbums.append(LibraryAlbum(id: collection.localIdentifier,
                                            title: collection.localizedTitle ?? "未命名相册", count: assets.count,
                                            collection: collection, cover: assets.firstObject.map(self.photo)))
        }
        albums = loadedAlbums
        isLoading = false
    }

    func startDemo() {
        isDemo = true
        reviewed.removeAll()
        unsure.removeAll()
        pendingDeletion.removeAll()
        photos = (0..<48).map { index in
            LibraryPhoto(id: "demo-\(index)", asset: nil,
                         date: Calendar.current.date(byAdding: .day, value: -index * 3, to: Date())!,
                         isScreenshot: index % 7 == 0, isVideo: index % 9 == 0,
                         isFavorite: index % 5 == 0, demoIndex: index)
        }
        albums = ["山野之间", "日常碎片", "去看海"].enumerated().map { index, name in
            LibraryAlbum(id: "album-\(index)", title: name, count: 8 + index * 4, collection: nil, cover: photos[index * 3])
        }
    }

    func exitDemo() {
        let savedPending = Set(UserDefaults.standard.stringArray(forKey: "photoclear.pending") ?? [])
        isDemo = false
        photos = []
        albums = []
        pendingDeletion = savedPending
        reviewed = Set(UserDefaults.standard.stringArray(forKey: reviewedKey) ?? [])
        unsure = Set(UserDefaults.standard.stringArray(forKey: unsureKey) ?? [])
        refreshAuthorization()
    }

    func review(_ photo: LibraryPhoto, keep: Bool) {
        unsure.remove(photo.id)
        if keep {
            pendingDeletion.remove(photo.id)
            reviewed.insert(photo.id)
        } else {
            reviewed.remove(photo.id)
            pendingDeletion.insert(photo.id)
        }
        persistReviewed()
        persistUnsure()
    }

    func markUnsure(_ photo: LibraryPhoto) {
        reviewed.remove(photo.id)
        pendingDeletion.remove(photo.id)
        unsure.insert(photo.id)
        persistReviewed()
        persistUnsure()
    }

    func markPending(_ photo: LibraryPhoto) { markPending(ids: [photo.id]) }

    func markPending(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        reviewed.subtract(ids)
        unsure.subtract(ids)
        pendingDeletion.formUnion(ids)
        persistReviewed()
        persistUnsure()
    }

    func undoReview(_ photo: LibraryPhoto) {
        reviewed.remove(photo.id)
        unsure.remove(photo.id)
        pendingDeletion.remove(photo.id)
        persistReviewed()
        persistUnsure()
    }

    func resetReview() {
        reviewed.removeAll()
        unsure.removeAll()
        persistReviewed()
        persistUnsure()
    }

    func migrateUnsureToUnreviewed() {
        guard !unsure.isEmpty else { return }
        unsure.removeAll()
        persistUnsure()
    }

    func unreview(_ photo: LibraryPhoto) {
        reviewed.remove(photo.id)
        unsure.remove(photo.id)
        pendingDeletion.remove(photo.id)
        persistReviewed()
        persistUnsure()
    }

    func restart(ids: Set<String>) {
        reviewed.subtract(ids)
        unsure.subtract(ids)
        pendingDeletion.subtract(ids)
        persistReviewed()
        persistUnsure()
    }

    func canRenameAlbum(_ album: LibraryAlbum) -> Bool {
        if isDemo { return true }
        guard let collection = album.collection else { return false }
        return collection.assetCollectionType == .album
            && collection.assetCollectionSubtype == .albumRegular
            && collection.canPerform(.delete)
    }

    /// Only albums that accept new photos can be used as classification tags.
    func canAddContent(to album: LibraryAlbum) -> Bool {
        if isDemo { return true }
        guard let collection = album.collection else { return false }
        return collection.canPerform(.addContent)
    }

    /// Regular user albums whose membership can be adjusted by the classification tags.
    func canRemoveContent(from album: LibraryAlbum) -> Bool {
        if isDemo { return true }
        guard let collection = album.collection else { return false }
        return collection.assetCollectionType == .album
            && collection.assetCollectionSubtype == .albumRegular
            && collection.canPerform(.removeContent)
    }

    /// Albums that can be tagged during a review, i.e. writable and removable regular user albums.
    var writableAlbums: [LibraryAlbum] {
        albums.filter { canAddContent(to: $0) && canRemoveContent(from: $0) }
    }

    func classifiedAlbumIDs(for photo: LibraryPhoto) -> Set<String> {
        if isDemo { return [] }
        guard let asset = photo.asset else { return [] }
        var ids: Set<String> = []
        for album in writableAlbums {
            guard let collection = album.collection else { continue }
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            var containsAsset = false
            assets.enumerateObjects { existingAsset, _, stop in
                if existingAsset.localIdentifier == asset.localIdentifier {
                    containsAsset = true
                    stop.pointee = true
                }
            }
            if containsAsset { ids.insert(album.id) }
        }
        return ids
    }

    static func sanitizedAlbumTitle(_ rawTitle: String) -> String {
        let scalars = rawTitle.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0)
        }
        return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func albumTitleWithoutControlCharacters(_ rawTitle: String) -> String {
        let scalars = rawTitle.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    func hasAlbum(named rawTitle: String, excluding excludedID: String? = nil) -> Bool {
        let title = Self.sanitizedAlbumTitle(rawTitle)
        guard !title.isEmpty else { return false }
        return albums.contains { album in
            album.id != excludedID && album.title.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    func deleteAlbum(_ album: LibraryAlbum) async {
        guard !isWorking else { return }
        if isDemo {
            albums.removeAll { $0.id == album.id }
            notice = "已删除相册「\(album.title)」"
            return
        }
        guard let collection = album.collection else { return }
        let success = await change { PHAssetCollectionChangeRequest.deleteAssetCollections([collection] as NSArray) }
        if success { notice = "已删除相册「\(album.title)」" }
    }

    func renameAlbum(_ album: LibraryAlbum, to rawTitle: String) async -> Bool {
        guard !isWorking else { return false }
        let title = Self.sanitizedAlbumTitle(rawTitle)
        guard !title.isEmpty else {
            errorMessage = "请输入相册名称"
            return false
        }
        guard !hasAlbum(named: title, excluding: album.id) else {
            errorMessage = "已存在同名相册，请换一个名称"
            return false
        }
        guard hasAccess || isDemo else {
            errorMessage = "请先允许照片访问权限后再重命名相册"
            return false
        }
        guard canRenameAlbum(album) else {
            errorMessage = "该相册不支持重命名"
            return false
        }
        if isDemo {
            guard let index = albums.firstIndex(where: { $0.id == album.id }) else { return false }
            let existing = albums[index]
            albums[index] = LibraryAlbum(id: existing.id, title: title, count: existing.count,
                                         collection: existing.collection, cover: existing.cover)
            notice = "已重命名为「\(title)」"
            return true
        }
        guard let collection = album.collection else {
            errorMessage = "该相册不支持重命名"
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCollectionChangeRequest(for: collection)?.title = title
            }
            reload()
            notice = "已重命名为「\(title)」"
            return true
        } catch {
            errorMessage = "相册重命名失败：\(error.localizedDescription)"
            return false
        }
    }

    private func persistReviewed() {
        if !isDemo { UserDefaults.standard.set(Array(reviewed), forKey: reviewedKey) }
    }

    private func persistUnsure() {
        if !isDemo { UserDefaults.standard.set(Array(unsure), forKey: unsureKey) }
    }

    private func addSavedBytes(_ bytes: Int64) {
        guard bytes > 0 else { return }
        totalSavedBytes += bytes
        if !isDemo { UserDefaults.standard.set(totalSavedBytes, forKey: savedBytesKey) }
    }

    private func change(_ block: @escaping () -> Void) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await PHPhotoLibrary.shared().performChanges(block)
            reload()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deletePending() async {
        let targets = pendingPhotos
        guard !targets.isEmpty, !isWorking else { return }
        let bytesToSave = targets.reduce(Int64(0)) { $0 + $1.estimatedBytes }
        if isDemo {
            photos.removeAll { pendingDeletion.contains($0.id) }
            pendingDeletion.removeAll()
            addSavedBytes(bytesToSave)
            notice = "已移除 \(targets.count) 个演示项目"
            return
        }
        let assets = targets.compactMap(\.asset)
        if await change({ PHAssetChangeRequest.deleteAssets(assets as NSArray) }) {
            pendingDeletion.subtract(targets.map(\.id))
            addSavedBytes(bytesToSave)
            notice = "已删除 \(targets.count) 个项目"
        }
    }

    func favorite(ids: Set<String>, value: Bool = true) async {
        guard !ids.isEmpty else { return }
        if isDemo {
            for index in photos.indices where ids.contains(photos[index].id) { photos[index].isFavorite = value }
            notice = value ? "已加入收藏" : "已取消收藏"
            return
        }
        let assets = photos.filter { ids.contains($0.id) }.compactMap(\.asset)
        if await change({ for asset in assets { PHAssetChangeRequest(for: asset).isFavorite = value } }) {
            notice = value ? "已加入收藏" : "已取消收藏"
        }
    }

    func createAlbum(title rawTitle: String) async -> Bool {
        let title = Self.sanitizedAlbumTitle(rawTitle)
        guard !title.isEmpty else {
            errorMessage = "请输入相册名称"
            return false
        }
        guard hasAccess || isDemo else {
            errorMessage = "请先允许照片访问权限后再创建相册"
            return false
        }
        if isDemo {
            albums.append(LibraryAlbum(id: UUID().uuidString, title: title, count: 0,
                                       collection: nil, cover: nil))
            notice = "已创建相册「\(title)」"
            return true
        }
        let success = await change {
            PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
        }
        if success { notice = "已创建相册「\(title)」" }
        return success
    }

    func add(ids: Set<String>, to album: LibraryAlbum? = nil, newTitle: String? = nil) async -> Bool {
        let title = newTitle.map(Self.sanitizedAlbumTitle)
        guard !ids.isEmpty, album != nil || !(title ?? "").isEmpty else {
            errorMessage = (title ?? "").isEmpty ? "请输入相册名称" : nil
            return false
        }
        guard hasAccess || isDemo else {
            errorMessage = "请先允许照片访问权限后再加入相册"
            return false
        }
        if isDemo {
            if let album, let index = albums.firstIndex(where: { $0.id == album.id }) {
                let existing = albums[index]
                albums[index] = LibraryAlbum(id: existing.id, title: existing.title, count: existing.count + ids.count,
                                            collection: nil, cover: existing.cover)
            } else if let title {
                albums.append(LibraryAlbum(id: UUID().uuidString, title: title, count: ids.count,
                                           collection: nil, cover: photos.first { ids.contains($0.id) }))
            }
            notice = "已加入相册"
            return true
        }
        let assets = photos.filter { ids.contains($0.id) }.compactMap(\.asset)
        let collection = album?.collection
        let success = await change {
            let request: PHAssetCollectionChangeRequest?
            if let collection { request = PHAssetCollectionChangeRequest(for: collection) }
            else { request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title ?? "新相册") }
            request?.addAssets(assets as NSArray)
        }
        if success { notice = "已加入相册" }
        return success
    }

    func photos(in album: LibraryAlbum) -> [LibraryPhoto] {
        guard let collection = album.collection else { return Array(photos.prefix(album.count)) }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(in: collection, options: options)
        var items: [LibraryPhoto] = []
        result.enumerateObjects { asset, _, _ in items.append(self.photo(from: asset)) }
        return items
    }

    /// Classify a single photo into exactly one writable user album. Used by the review screen's album tags.
    /// Returns a failure message instead of touching `errorMessage`, so callers can show
    /// inline feedback while the review screen covers the global alert.
    func classify(_ photo: LibraryPhoto, into album: LibraryAlbum) async -> Result<Void, AlbumWriteError> {
        guard !isWorking else { return .failure(.busy) }
        guard hasAccess || isDemo else { return .failure(.noAccess) }
        guard canAddContent(to: album), canRemoveContent(from: album) else { return .failure(.notWritable) }
        if isDemo {
            for index in albums.indices where albums[index].id != album.id && canRemoveContent(from: albums[index]) {
                let existing = albums[index]
                albums[index] = LibraryAlbum(id: existing.id, title: existing.title, count: max(existing.count - 1, 0),
                                            collection: existing.collection, cover: existing.cover)
            }
            if let index = albums.firstIndex(where: { $0.id == album.id }) {
                let existing = albums[index]
                albums[index] = LibraryAlbum(id: existing.id, title: existing.title, count: existing.count + 1,
                                            collection: existing.collection, cover: existing.cover ?? photo)
            }
            return .success(())
        }
        guard let asset = photo.asset else { return .failure(.assetUnavailable) }
        guard let targetCollection = album.collection else { return .failure(.notWritable) }
        let collectionsToRemoveFrom = albums.compactMap { candidate -> PHAssetCollection? in
            guard candidate.id != album.id, canRemoveContent(from: candidate), let collection = candidate.collection else { return nil }
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            var containsAsset = false
            assets.enumerateObjects { existingAsset, _, stop in
                if existingAsset.localIdentifier == asset.localIdentifier {
                    containsAsset = true
                    stop.pointee = true
                }
            }
            return containsAsset ? collection : nil
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCollectionChangeRequest(for: targetCollection)?.addAssets([asset] as NSArray)
                for collection in collectionsToRemoveFrom {
                    PHAssetCollectionChangeRequest(for: collection)?.removeAssets([asset] as NSArray)
                }
            }
            reload()
            return .success(())
        } catch {
            return .failure(.writeFailed(error.localizedDescription))
        }
    }

    /// Remove a review classification from one writable regular user album. Used when
    /// tapping the selected classification tag again to return the photo to an unfiled state.
    func removeClassification(_ photo: LibraryPhoto, from album: LibraryAlbum) async -> Result<Void, AlbumWriteError> {
        guard !isWorking else { return .failure(.busy) }
        guard hasAccess || isDemo else { return .failure(.noAccess) }
        guard canRemoveContent(from: album) else { return .failure(.notRemovable) }
        if isDemo {
            if let index = albums.firstIndex(where: { $0.id == album.id }) {
                let existing = albums[index]
                albums[index] = LibraryAlbum(id: existing.id, title: existing.title, count: max(existing.count - 1, 0),
                                            collection: existing.collection, cover: existing.cover)
            }
            return .success(())
        }
        guard let asset = photo.asset else { return .failure(.assetUnavailable) }
        guard let collection = album.collection else { return .failure(.notRemovable) }
        isWorking = true
        defer { isWorking = false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCollectionChangeRequest(for: collection)?.removeAssets([asset] as NSArray)
            }
            reload()
            return .success(())
        } catch {
            return .failure(.writeFailed(error.localizedDescription))
        }
    }
}

/// Failure reasons for album writes surfaced to the user as explicit messages.
enum AlbumWriteError: Error {
    case busy
    case noAccess
    case notWritable
    case notRemovable
    case assetUnavailable
    case writeFailed(String)

    var message: String {
        switch self {
        case .busy: return "正在处理上一个操作，请稍候"
        case .noAccess: return "请先允许照片访问权限后再加入相册"
        case .notWritable: return "该相册不支持加入照片"
        case .notRemovable: return "该相册不支持移出照片"
        case .assetUnavailable: return "找不到这张照片，无法加入相册"
        case .writeFailed(let detail): return "相册更新失败：\(detail)"
        }
    }
}
