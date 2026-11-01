import SwiftUI
import Photos
import AVKit
import AVFoundation

struct PhotoBrowserView: View {
    @EnvironmentObject private var library: PhotoLibraryStore
    @Environment(\.dismiss) private var dismiss
    var title = "我的照片"
    var source: [LibraryPhoto]? = nil
    var allowsRestart = false
    @State private var filter: PhotoFilter
    @State private var selected: Set<String> = []
    @State private var selectionMode = false
    @State private var preview: LibraryPhoto?
    @State private var showAlbums = false
    @State private var showTrash = false
    @State private var showReview = false
    @State private var confirmRestart = false

    init(title: String = "我的照片", source: [LibraryPhoto]? = nil, initialFilter: PhotoFilter = .all, allowsRestart: Bool = false) {
        self.title = title
        self.source = source
        self.allowsRestart = allowsRestart
        _filter = State(initialValue: initialFilter)
    }

    private var items: [LibraryPhoto] {
        let ids = source.map { Set($0.map(\.id)) }
        return library.photos.filter { (ids == nil || ids!.contains($0.id)) && filter.includes($0) }
    }

    private var reviewTargets: [LibraryPhoto] {
        guard let source else { return items }
        let ids = Set(source.map(\.id))
        return library.photos.filter { ids.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 29, weight: .semibold, design: .serif))
                    Text(selectionMode ? "已选择 \(selected.count) 个项目" : "\(items.count) 个值得珍藏的瞬间")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                HStack(spacing: 14) {
                    if !selectionMode {
                        Button {
                            if allowsRestart { confirmRestart = true }
                            else { showReview = true }
                        } label: {
                            Text(allowsRestart ? "重新整理 \(reviewTargets.count)" : "整理")
                                .font(.system(size: 14, weight: .medium))
                        }.disabled(reviewTargets.isEmpty)
                    }
                    Button(selectionMode ? "完成" : "选择") {
                        selectionMode.toggle()
                        selected.removeAll()
                    }.font(.system(size: 14, weight: .medium))
                }
            }.padding(24)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PhotoFilter.allCases) { option in
                        Button { filter = option; selected.removeAll() } label: {
                            Text(option.rawValue).font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 20).padding(.vertical, 10)
                                .foregroundStyle(filter == option ? .white : Palette.muted)
                                .background(filter == option ? Palette.green : .white, in: Capsule())
                        }
                    }
                }.padding(.horizontal, 24)
            }.padding(.bottom, 18)
            if items.isEmpty {
                EmptyState(symbol: filter.symbol, title: "这里还是空的", subtitle: "换个分类看看，或在系统相册中添加照片。")
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                        ForEach(items) { photo in
                            Button {
                                if selectionMode {
                                    if !selected.insert(photo.id).inserted { selected.remove(photo.id) }
                                } else { preview = photo }
                            } label: {
                                PhotoThumbnail(photo: photo).aspectRatio(0.85, contentMode: .fit)
                                    .overlay(alignment: .topTrailing) {
                                        if selectionMode {
                                            Image(systemName: selected.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selected.contains(photo.id) ? Palette.lime : .white)
                                                .font(.system(size: 22)).shadow(radius: 3).padding(8)
                                        }
                                    }
                                    .overlay(alignment: .bottomLeading) {
                                        if photo.isFavorite {
                                            Image(systemName: "heart.fill").font(.system(size: 12)).foregroundStyle(.white).shadow(radius: 3).padding(8)
                                        }
                                    }
                                    .overlay(alignment: .bottomTrailing) {
                                        if photo.isVideo {
                                            Text(photo.duration ?? "0:12").font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(.white).shadow(radius: 3).padding(8)
                                        }
                                    }
                                    .overlay {
                                        if photo.isVideo {
                                            Image(systemName: "play.circle.fill").font(.system(size: 34))
                                                .foregroundStyle(.white.opacity(0.9)).shadow(radius: 5)
                                        }
                                    }
                                    .overlay { if selected.contains(photo.id) { Palette.green.opacity(0.15) } }
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 12).padding(.bottom, 16)
                }
            }
            if selectionMode {
                HStack(spacing: 20) {
                    Button(selected.count == items.count ? "取消全选" : "全选") {
                        selected = selected.count == items.count ? [] : Set(items.map(\.id))
                    }.padding(.horizontal, 6).frame(minHeight: 44)
                    Spacer()
                    Button { Task { await library.favorite(ids: selected) } } label: { Image(systemName: "heart").frame(width: 44, height: 44) }
                        .disabled(selected.isEmpty || library.isWorking).accessibilityLabel("收藏所选")
                    Button { showAlbums = true } label: { Image(systemName: "folder.badge.plus").frame(width: 44, height: 44) }
                        .disabled(selected.isEmpty).accessibilityLabel("加入相册")
                    Button {
                        library.markPending(ids: selected)
                        selected.removeAll()
                        showTrash = true
                    } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                        .disabled(selected.isEmpty).accessibilityLabel("加入待清理")
                }.font(.system(size: 18)).padding(.horizontal, 22).padding(.vertical, 14).background(.white)
            }
        }.foregroundStyle(Palette.green).background(Palette.background)
            .sheet(item: $preview) { PhotoDetailView(photo: $0) }
            .sheet(isPresented: $showAlbums) { AlbumPickerView(ids: selected) }
            .sheet(isPresented: $showTrash) { PendingDeletionView() }
            .fullScreenCover(isPresented: $showReview) { ReviewView(source: reviewTargets, includeAllInSource: allowsRestart) }
            .confirmationDialog("重新整理这 \(reviewTargets.count) 个项目？", isPresented: $confirmRestart, titleVisibility: .visible) {
                Button("重新整理", role: .destructive) {
                    library.restart(ids: Set(reviewTargets.map(\.id)))
                    dismiss()
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("这些项目的整理状态会被清除，将重新进入待整理列表，可再次逐张决定。不会修改或删除照片。")
            }
            .onChange(of: library.photos.map(\.id)) { _, ids in selected.formIntersection(Set(ids)) }
    }
}

struct PhotoDetailView: View {
    @EnvironmentObject private var library: PhotoLibraryStore
    @Environment(\.dismiss) private var dismiss
    let photo: LibraryPhoto
    @State private var showAlbums = false
    private var current: LibraryPhoto { library.photos.first { $0.id == photo.id } ?? photo }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                media.clipShape(RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 16)
                HStack(alignment: .top, spacing: 8) {
                    detailAction(current.isFavorite ? "已收藏" : "收藏",
                                 symbol: current.isFavorite ? "heart.fill" : "heart") {
                        Task { await library.favorite(ids: [current.id], value: !current.isFavorite) }
                    }
                    detailAction("加入相册", symbol: "folder.badge.plus") { showAlbums = true }
                    if library.reviewed.contains(current.id) {
                        detailAction("重新整理", symbol: "arrow.counterclockwise") {
                            library.unreview(current)
                            library.notice = "已放回待整理"
                            dismiss()
                        }
                    }
                    detailAction("待清理", symbol: "trash",
                                 tint: Color(red: 0.70, green: 0.39, blue: 0.30)) {
                        library.markPending(current)
                        library.notice = "已加入待清理"
                        dismiss()
                    }
                }.padding(.bottom, 24).disabled(library.isWorking)
            }.background(Palette.background).navigationTitle(photo.date.formatted(date: .abbreviated, time: .omitted))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
                .sheet(isPresented: $showAlbums) { AlbumPickerView(ids: [photo.id]) }
        }.tint(Palette.green)
    }

    @ViewBuilder private var media: some View {
        if current.isVideo, let asset = current.asset {
            LibraryVideoPlayer(asset: asset)
        } else if current.isVideo {
            PhotoThumbnail(photo: current, large: true)
                .aspectRatio(current.pixelSize, contentMode: .fit)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash").font(.system(size: 30, weight: .light))
                        Text("演示模式不包含视频播放").font(.system(size: 12, weight: .medium))
                    }.padding(18).foregroundStyle(.white)
                        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
                }
        } else {
            PhotoThumbnail(photo: current, large: true, showsFullImage: true)
                .aspectRatio(current.pixelSize, contentMode: .fit)
        }
    }

    private func detailAction(_ title: String, symbol: String, tint: Color = Palette.green, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 19, weight: .medium))
                Text(title).font(.system(size: 11, weight: .medium))
            }.frame(maxWidth: .infinity)
        }.foregroundStyle(tint)
    }
}

struct LibraryVideoPlayer: View {
    let asset: PHAsset
    var isPlaying: Bool
    var showsPlaybackControls: Bool
    @State private var player: AVPlayer?
    @State private var requestID: PHImageRequestID?
    @State private var failed = false
    @State private var ratio: CGFloat
    @State private var loadToken = UUID()

    init(asset: PHAsset, isPlaying: Bool = true, showsPlaybackControls: Bool = true) {
        self.asset = asset
        self.isPlaying = isPlaying
        self.showsPlaybackControls = showsPlaybackControls
        _ratio = State(initialValue: CGFloat(max(asset.pixelWidth, 1)) / CGFloat(max(asset.pixelHeight, 1)))
    }

    var body: some View {
        ZStack {
            Color.black
            if let player {
                if showsPlaybackControls {
                    VideoPlayer(player: player)
                } else {
                    ReviewVideoSurface(player: player)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            } else if failed {
                VStack(spacing: 10) {
                    Image(systemName: "video.slash").font(.system(size: 30, weight: .light))
                    Text("视频暂时无法播放").font(.system(size: 13))
                }.foregroundStyle(.white.opacity(0.75))
            } else {
                ProgressView().tint(.white)
            }
        }
        .aspectRatio(ratio, contentMode: .fit)
        .task(id: asset.localIdentifier) { load() }
        .onChange(of: isPlaying) { _, playing in
            if playing { player?.play() } else { player?.pause() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard !showsPlaybackControls, let item = notification.object as? AVPlayerItem,
                  item === player?.currentItem else { return }
            player?.seek(to: .zero)
            if isPlaying { player?.play() }
        }
        .onDisappear { stop() }
    }

    private func load() {
        stop()
        failed = false
        let target = asset.localIdentifier
        let token = loadToken
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        requestID = PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, info in
            Task { @MainActor in
                guard self.asset.localIdentifier == target, loadToken == token else { return }
                requestID = nil
                guard let item else {
                    if (info?[PHImageCancelledKey] as? Bool) != true { failed = true }
                    return
                }
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try? AVAudioSession.sharedInstance().setActive(true)
                let player = AVPlayer(playerItem: item)
                self.player = player
                if isPlaying { player.play() }
                updateRatio(for: item)
            }
        }
    }

    private func updateRatio(for item: AVPlayerItem) {
        Task {
            guard let tracks = try? await item.asset.loadTracks(withMediaType: .video),
                  let track = tracks.first else { return }
            guard let size = try? await track.load(.naturalSize),
                  let transform = try? await track.load(.preferredTransform) else { return }
            let applied = size.applying(transform)
            let width = abs(applied.width), height = abs(applied.height)
            guard width > 0, height > 0 else { return }
            await MainActor.run {
                guard player?.currentItem === item else { return }
                ratio = width / height
            }
        }
    }

    private func stop() {
        loadToken = UUID()
        player?.pause()
        player = nil
        if let requestID {
            PHImageManager.default().cancelImageRequest(requestID)
            self.requestID = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private struct ReviewVideoSurface: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        controller.player = player
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player = nil
    }
}

struct AlbumPickerView: View {
    @EnvironmentObject private var library: PhotoLibraryStore
    @Environment(\.dismiss) private var dismiss
    let ids: Set<String>
    @State private var name = ""
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasDuplicateName: Bool {
        library.albums.contains { $0.title.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }
    var body: some View {
        NavigationStack {
            List {
                Section("新建相册") {
                    TextField("相册名称", text: $name)
                    if trimmedName.isEmpty && !name.isEmpty {
                        Label("相册名称不能只包含空格", systemImage: "exclamationmark.circle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    if !trimmedName.isEmpty && hasDuplicateName {
                        Label("已存在同名相册，将创建一本新的同名相册并加入所选项目。", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(Palette.muted)
                    }
                    Button(hasDuplicateName ? "新建同名并加入 \(ids.count) 个项目" : "新建并加入 \(ids.count) 个项目") {
                        Task { if await library.add(ids: ids, newTitle: name) { dismiss() } }
                    }.disabled(trimmedName.isEmpty || library.isWorking)
                }
                Section("加入已有相册") {
                    ForEach(library.albums) { album in
                        Button {
                            Task { if await library.add(ids: ids, to: album) { dismiss() } }
                        } label: {
                            HStack { Text(album.title); Spacer(); Text("\(album.count)").foregroundStyle(Palette.muted) }
                        }.disabled(library.isWorking || (!library.isDemo && album.collection?.canPerform(.addContent) != true))
                    }
                }
            }.navigationTitle("加入相册").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { dismiss() } } }
                .scrollContentBackground(.hidden).background(Palette.background)
        }.tint(Palette.green)
    }
}
