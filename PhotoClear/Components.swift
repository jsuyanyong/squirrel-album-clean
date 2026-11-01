import SwiftUI
import Photos

enum Palette {
    static let background = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let green = Color(red: 0.16, green: 0.29, blue: 0.23)
    static let muted = Color(red: 0.47, green: 0.49, blue: 0.44)
    static let lime = Color(red: 0.83, green: 0.91, blue: 0.61)
    static let line = Color(red: 0.89, green: 0.89, blue: 0.84)
}

struct PhotoThumbnail: View, Equatable {
    let photo: LibraryPhoto
    var large = false
    var showsFullImage = false
    static func == (lhs: PhotoThumbnail, rhs: PhotoThumbnail) -> Bool {
        lhs.photo.id == rhs.photo.id && lhs.large == rhs.large && lhs.showsFullImage == rhs.showsFullImage
    }
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?
    private static let manager = PHCachingImageManager()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                showsFullImage ? Color.black : Palette.line
                if let image {
                    Image(uiImage: image).resizable()
                        .aspectRatio(contentMode: showsFullImage ? .fit : .fill)
                } else if let index = photo.demoIndex {
                    DemoLandscape(index: index)
                } else {
                    Image(systemName: photo.isVideo ? "video" : "photo")
                        .foregroundStyle(Palette.muted)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .task(id: loadKey) { load() }
        .onDisappear {
            if let requestID { Self.manager.cancelImageRequest(requestID) }
        }
        .accessibilityLabel(photo.isVideo ? "视频" : "照片")
    }

    private var loadKey: String { "\(photo.id)|\(large)|\(showsFullImage)" }

    private func load() {
        guard let asset = photo.asset else { return }
        image = nil
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let size: CGSize = showsFullImage ? CGSize(width: 2048, height: 2048)
            : (large ? CGSize(width: 1400, height: 1800) : CGSize(width: 450, height: 450))
        let mode: PHImageContentMode = showsFullImage ? .aspectFit : .aspectFill
        requestID = Self.manager.requestImage(for: asset, targetSize: size, contentMode: mode, options: options) { result, info in
            guard (info?[PHImageCancelledKey] as? Bool) != true else { return }
            Task { @MainActor in image = result }
        }
    }

    static func prefetch(_ photo: LibraryPhoto?, large: Bool = true) {
        guard let asset = photo?.asset else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let size = large ? CGSize(width: 1400, height: 1800) : CGSize(width: 450, height: 450)
        manager.startCachingImages(for: [asset], targetSize: size, contentMode: .aspectFill, options: options)
    }
}

// Offline illustrations keep the demo usable without downloading stock photos.
struct DemoLandscape: View {
    let index: Int
    var body: some View {
        GeometryReader { geo in
            let warm = index % 3 == 1
            let sea = index % 3 == 2
            ZStack {
                LinearGradient(colors: warm ? [Color(red: 0.82, green: 0.64, blue: 0.47), Color(red: 0.96, green: 0.86, blue: 0.67)] :
                                [Color(red: 0.57, green: 0.73, blue: 0.72), Color(red: 0.86, green: 0.88, blue: 0.76)],
                               startPoint: .top, endPoint: .bottom)
                Circle().fill(Color(red: 0.98, green: 0.91, blue: 0.70))
                    .frame(width: geo.size.width * 0.2)
                    .position(x: geo.size.width * (index % 2 == 0 ? 0.72 : 0.28), y: geo.size.height * 0.26)
                terrain(geo.size, peak: 0.35, shift: CGFloat(index % 4) * 0.07)
                    .fill(warm ? Color(red: 0.55, green: 0.42, blue: 0.32) : Color(red: 0.38, green: 0.56, blue: 0.50))
                terrain(geo.size, peak: sea ? 0.69 : 0.54, shift: 0.25)
                    .fill(warm ? Color(red: 0.37, green: 0.32, blue: 0.25) : Color(red: 0.22, green: 0.40, blue: 0.36))
                terrain(geo.size, peak: 0.79, shift: 0.05)
                    .fill(sea ? Color(red: 0.24, green: 0.48, blue: 0.50) : Palette.green)
                if sea {
                    Capsule().fill(.white.opacity(0.35)).frame(width: geo.size.width * 0.38, height: 2)
                        .position(x: geo.size.width * 0.60, y: geo.size.height * 0.84)
                }
            }
        }
    }
    private func terrain(_ size: CGSize, peak: CGFloat, shift: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: size.height * (peak + 0.18)))
            path.addCurve(to: CGPoint(x: size.width, y: size.height * (peak + 0.13)),
                          control1: CGPoint(x: size.width * (0.3 + shift), y: size.height * (peak - 0.22)),
                          control2: CGPoint(x: size.width * 0.65, y: size.height * (peak + 0.32)))
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.closeSubpath()
        }
    }
}

struct SectionHeading: View {
    let title: String
    var caption: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 21, weight: .semibold))
            Spacer()
            if let caption { Text(caption).font(.system(size: 12)).foregroundStyle(Palette.muted) }
        }.foregroundStyle(Palette.green)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 38, weight: .light)).foregroundStyle(Palette.green)
            Text(title).font(.title3.weight(.semibold))
            Text(subtitle).font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 64).padding(.horizontal, 24)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity).padding(.vertical, 17)
            .foregroundStyle(.white).background(Palette.green, in: RoundedRectangle(cornerRadius: 18))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
