import Foundation
import Photos

struct LibraryPhoto: Identifiable {
    let id: String
    let asset: PHAsset?
    let date: Date
    let isScreenshot: Bool
    let isVideo: Bool
    var isFavorite: Bool
    let demoIndex: Int?

    var pixelSize: CGSize {
        guard let asset else { return CGSize(width: 4, height: 3) }
        return CGSize(width: max(asset.pixelWidth, 1), height: max(asset.pixelHeight, 1))
    }

    var duration: String? {
        guard let asset, isVideo else { return nil }
        let seconds = Int(asset.duration)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var estimatedBytes: Int64 {
        if let asset {
            let resources = PHAssetResource.assetResources(for: asset)
            let total = resources.reduce(Int64(0)) { partial, resource in
                let size = (resource.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
                return partial + size
            }
            if total > 0 { return total }
        }
        return isVideo ? 8_000_000 : 2_500_000
    }
}

enum PhotoFilter: String, CaseIterable, Identifiable {
    case all = "全部", screenshots = "截图", videos = "视频", favorites = "收藏"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .screenshots: return "viewfinder"
        case .videos: return "play.rectangle"
        case .favorites: return "heart"
        }
    }
    func includes(_ photo: LibraryPhoto) -> Bool {
        switch self {
        case .all: return true
        case .screenshots: return photo.isScreenshot
        case .videos: return photo.isVideo
        case .favorites: return photo.isFavorite
        }
    }
}

struct PhotoMonth: Identifiable {
    let date: Date
    let photos: [LibraryPhoto]
    var id: Date { date }
    var title: String { date.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN"))) }
}

struct LibraryAlbum: Identifiable {
    let id: String
    let title: String
    let count: Int
    let collection: PHAssetCollection?
    let cover: LibraryPhoto?
}
