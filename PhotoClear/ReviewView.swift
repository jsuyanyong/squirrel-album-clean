import SwiftUI
import UIKit
import Photos
import PhotosUI

struct ReviewView: View {
    @EnvironmentObject private var library: PhotoLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var offset = CGSize.zero
    @State private var history: [LibraryPhoto] = []
    @State private var showTrash = false
    @State private var isAnimatingOut = false
    @State private var currentIndex = 0
    @State private var reviewFeedback: String?
    @State private var playingVideoID: String?
    @State private var videoPaused = false
    @State private var classifiedAlbums: Set<String> = []
    @State private var tagFeedback: String?
    @State private var tagFeedbackIsError = false
    @State private var isClassifying = false
    @State private var showCreateAlbum = false
    var source: [LibraryPhoto]? = nil
    var includeAllInSource = false
    private var baseQueue: [LibraryPhoto] {
        let pool = source ?? library.photos
        if includeAllInSource { return pool }
        return pool.filter { !library.reviewed.contains($0.id) && !library.pendingDeletion.contains($0.id) }
    }
    private var queue: [LibraryPhoto] { baseQueue }
    private var current: LibraryPhoto? {
        guard queue.indices.contains(currentIndex) else { return queue.first }
        return queue[currentIndex]
    }
    private var nextPhoto: LibraryPhoto? {
        let nextIndex = min(currentIndex + 1, queue.count - 1)
        guard queue.indices.contains(nextIndex), nextIndex != currentIndex else { return nil }
        return queue[nextIndex]
    }
    private var topCardScale: CGFloat {
        guard !isAnimatingOut else { return 1 }
        return max(0.9, 1 - abs(offset.width) / 2600 - max(0, -offset.height) / 2600)
    }
    private var nextScale: CGFloat {
        guard !isAnimatingOut else { return 1 }
        let progress = min(1, (abs(offset.width) + max(0, -offset.height) * 0.6) / 140)
        return 0.94 + 0.06 * progress
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                Spacer()
                Text("一张一张，慢慢来").font(.system(size: 16, weight: .medium, design: .serif))
                Spacer()
                Button { showTrash = true } label: {
                    Image(systemName: "tray").overlay(alignment: .topTrailing) {
                        if !library.pendingDeletion.isEmpty {
                            Text("\(library.pendingDeletion.count)").font(.system(size: 9, weight: .bold))
                                .padding(4).foregroundStyle(.white).background(Palette.green, in: Circle()).offset(x: 10, y: -10)
                        }
                    }.frame(width: 44, height: 44)
                }.accessibilityLabel("待清理列表")
            }
            if let photo = current {
                VStack(spacing: 8) {
                    Text(photo.date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN"))))
                        .font(.system(size: 20, weight: .semibold))
                    Text("剩余 \(queue.count) 个项目")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                GeometryReader { geo in
                    ZStack {
                        if let next = nextPhoto {
                            PhotoThumbnail(photo: next, large: true, showsFullImage: true).equatable()
                                .clipShape(RoundedRectangle(cornerRadius: 26))
                                .padding(.horizontal, 12).padding(.top, 12)
                                .scaleEffect(nextScale)
                                .animation(.easeOut(duration: 0.18), value: nextScale)
                        } else {
                            RoundedRectangle(cornerRadius: 26).fill(Palette.line)
                                .padding(.horizontal, 12).padding(.top, 12)
                                .scaleEffect(nextScale)
                                .animation(.easeOut(duration: 0.18), value: nextScale)
                        }
                        card(photo)
                            .offset(offset).rotationEffect(.degrees(Double(offset.width / 24)))
                            .gesture(drag(on: photo))
                    }.frame(width: geo.size.width, height: geo.size.height)
                }.padding(.horizontal, 24)
                Text("左右浏览 · 上滑待清理 · 下滑保留")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                if let reviewFeedback {
                    Text(reviewFeedback).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.green)
                        .transition(.opacity)
                }
                albumTagBar(for: photo)
                HStack(alignment: .top, spacing: 16) {
                    actionButton("待清理", symbol: "trash", color: Color(red: 0.70, green: 0.39, blue: 0.30)) { markPending(photo, verticalDirection: -1) }
                    Button {
                        if let previous = history.popLast() {
                            library.undoReview(previous)
                            reviewFeedback = "已撤销上一次操作"
                            if let restoredIndex = queue.firstIndex(where: { $0.id == previous.id }) { currentIndex = restoredIndex }
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.uturn.backward").font(.system(size: 20))
                                .frame(width: 70, height: 70).background(.white, in: Circle())
                            Text("撤销").font(.system(size: 12, weight: .medium))
                        }.foregroundStyle(Palette.muted)
                    }.disabled(history.isEmpty).accessibilityLabel("撤销上一次整理")
                    actionButton("保留", symbol: "heart", color: Palette.green) { decide(photo, keep: true) }
                }.padding(.bottom, 18)
            } else {
                Spacer()
                EmptyState(symbol: "checkmark.seal", title: "整理完成，轻装前行", subtitle: "你为回忆留出了更多空间。\n待清理的项目可在确认后删除。")
                Button("查看待清理 · \(library.pendingDeletion.count)") { showTrash = true }
                    .buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 28)
                Button("完成") { dismiss() }.padding(16)
                Spacer()
            }
        }.padding(.horizontal, 12).foregroundStyle(Palette.green).background(Palette.background)
            .sheet(isPresented: $showTrash) { PendingDeletionView() }
            .sheet(isPresented: $showCreateAlbum) { CreateAlbumView() }
            .onAppear {
                library.migrateUnsureToUnreviewed()
                clampCurrentIndex()
                refreshClassificationState(for: current)
                prefetchUpcoming()
            }
            .onChange(of: current?.id) { _, _ in
                playingVideoID = nil
                videoPaused = false
                reviewFeedback = nil
                clampCurrentIndex()
                refreshClassificationState(for: current)
                tagFeedback = nil
                prefetchUpcoming()
            }
            .onChange(of: showTrash) { _, visible in
                if visible { videoPaused = true }
            }
    }

    private func card(_ photo: LibraryPhoto) -> some View {
        ZStack {
            if playingVideoID == photo.id, let asset = photo.asset {
                Color.black
                LibraryVideoPlayer(asset: asset, isPlaying: !videoPaused, showsPlaybackControls: false)
                    .id(photo.id)
            } else {
                PhotoThumbnail(photo: photo, large: true, showsFullImage: true).equatable()
            }
        }
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(alignment: playingVideoID == photo.id ? .bottomTrailing : .center) {
                if photo.isVideo, photo.asset != nil {
                    Button {
                        if playingVideoID == photo.id { videoPaused.toggle() }
                        else {
                            videoPaused = false
                            playingVideoID = photo.id
                        }
                    } label: {
                        Label(playingVideoID == photo.id && !videoPaused ? "暂停视频" : "播放视频",
                              systemImage: playingVideoID == photo.id && !videoPaused ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .padding(16).foregroundStyle(.white)
                            .background(.black.opacity(0.6), in: Capsule())
                    }.buttonStyle(.plain).padding(16).disabled(isAnimatingOut)
                } else if photo.isVideo {
                    Text("演示模式不包含视频播放")
                        .font(.system(size: 12)).padding(12).foregroundStyle(.white)
                        .background(.black.opacity(0.6), in: Capsule())
                }
            }
            .overlay(alignment: .top) {
                if offset.height < -55 && abs(offset.width) < 110 {
                    Label("加入待清理", systemImage: "trash")
                        .font(.system(size: 21, weight: .bold)).padding(16)
                        .foregroundStyle(.red)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)).padding(.top, 24)
                } else if offset.height > 55 && abs(offset.width) < 110 {
                    Label("保留", systemImage: "heart.fill")
                        .font(.system(size: 21, weight: .bold)).padding(16)
                        .foregroundStyle(Palette.green)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)).padding(.top, 24)
                } else if abs(offset.width) > 35 {
                    Label(offset.width > 0 ? "上一张" : "下一张", systemImage: offset.width > 0 ? "chevron.left" : "chevron.right")
                        .font(.system(size: 21, weight: .bold)).padding(16)
                        .foregroundStyle(Palette.green)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)).padding(.top, 24)
                }
            }
    }

    private func drag(on photo: LibraryPhoto) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard !isAnimatingOut else { return }
                offset = value.translation
            }
            .onEnded { value in
                guard !isAnimatingOut else { return }
                let projected = value.translation.width + value.predictedEndTranslation.width * 0.25
                let vertical = value.translation.height + value.predictedEndTranslation.height * 0.25
                if abs(vertical) > 130 && abs(value.translation.width) < 110 {
                    if vertical < 0 { markPending(photo, verticalDirection: -1) }
                    else { keepByVerticalSwipe(photo) }
                } else if abs(projected) > 130 && abs(value.translation.height) < 120 {
                    browse(direction: projected < 0 ? 1 : -1)
                } else { withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { offset = .zero } }
            }
    }

    private func decide(_ photo: LibraryPhoto, keep: Bool) {
        fly(photo, direction: keep ? 1 : -1, keep: keep)
    }

    private func browse(direction: Int) {
        let targetIndex = currentIndex + direction
        guard queue.indices.contains(targetIndex) else {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            reviewFeedback = direction > 0 ? "已经是最后一张" : "已经是第一张"
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { offset = .zero }
            return
        }
        isAnimatingOut = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeOut(duration: 0.18)) {
            offset = CGSize(width: direction > 0 ? -640 : 640, height: offset.height * 0.2)
        } completion: {
            currentIndex = targetIndex
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { offset = .zero }
            isAnimatingOut = false
        }
    }

    private func fly(_ photo: LibraryPhoto, direction: CGFloat, keep: Bool) {
        guard !isAnimatingOut else { return }
        isAnimatingOut = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeOut(duration: 0.22)) {
            offset = CGSize(width: direction * 640, height: offset.height + 60)
        } completion: {
            history.append(photo)
            library.review(photo, keep: keep)
            reviewFeedback = keep ? "已保留，可点撤销恢复" : "已加入待清理，可点撤销恢复"
            clampCurrentIndex()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { offset = .zero }
            isAnimatingOut = false
        }
    }

    private func markPending(_ photo: LibraryPhoto, verticalDirection: CGFloat) {
        guard !isAnimatingOut else { return }
        isAnimatingOut = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeOut(duration: 0.22)) {
            offset = CGSize(width: offset.width * 0.2, height: verticalDirection * 640)
        } completion: {
            history.append(photo)
            library.review(photo, keep: false)
            reviewFeedback = "已加入待清理，可点撤销恢复"
            clampCurrentIndex()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { offset = .zero }
            isAnimatingOut = false
        }
    }

    private func keepByVerticalSwipe(_ photo: LibraryPhoto) {
        guard !isAnimatingOut else { return }
        isAnimatingOut = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeOut(duration: 0.22)) {
            offset = CGSize(width: offset.width * 0.2, height: 640)
        } completion: {
            history.append(photo)
            library.review(photo, keep: true)
            reviewFeedback = "已保留，可点撤销恢复"
            clampCurrentIndex()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { offset = .zero }
            isAnimatingOut = false
        }
    }

    private func clampCurrentIndex() {
        if queue.isEmpty { currentIndex = 0 }
        else if currentIndex >= queue.count { currentIndex = max(queue.count - 1, 0) }
        else if currentIndex < 0 { currentIndex = 0 }
    }

    private func prefetchUpcoming() {
        let upcoming = queue
        guard let current, let index = upcoming.firstIndex(where: { $0.id == current.id }) else { return }
        let end = min(index + 3, upcoming.count - 1)
        guard end > index else { return }
        for i in (index + 1)...end { PhotoThumbnail.prefetch(upcoming[i], large: true) }
    }

    private func actionButton(_ title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 25)).frame(width: 70, height: 70)
                    .background(color.opacity(0.1), in: Circle())
                Text(title).font(.system(size: 12, weight: .medium))
            }.foregroundStyle(color)
        }
    }

    // MARK: - Album classification tags

    /// Horizontal row of album names above the action buttons. Tapping a tag files the
    /// current photo into that album; the row scrolls sideways when there are many albums.
    @ViewBuilder
    private func albumTagBar(for photo: LibraryPhoto) -> some View {
        let albums = library.writableAlbums
        VStack(spacing: 6) {
            if albums.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.plus").font(.system(size: 11))
                    Text("暂无相册，先新建相册")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Button("新建相册") { showCreateAlbum = true }
                        .font(.system(size: 12, weight: .medium))
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(albums) { album in
                            let isDone = classifiedAlbums.contains(album.id)
                            Button {
                                toggleClassification(photo, album: album, isSelected: isDone)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: isDone ? "checkmark.circle.fill" : "folder")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(album.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .foregroundStyle(isDone ? Palette.green : Palette.muted)
                                .background(isDone ? Palette.lime.opacity(0.55) : .white.opacity(0.85), in: Capsule())
                                .overlay(Capsule().stroke(isDone ? Palette.green.opacity(0.35) : Palette.line, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .disabled(isClassifying)
                            .accessibilityLabel(isDone ? "从相册 \(album.title) 移除" : "加入相册 \(album.title)")
                            .accessibilityAddTraits(isDone ? [.isSelected] : [])
                        }
                        Button { showCreateAlbum = true } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                                Text("新建相册").font(.system(size: 12, weight: .medium)).lineLimit(1)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .foregroundStyle(Palette.muted)
                            .background(.white.opacity(0.85), in: Capsule())
                            .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("新建相册")
                    }.padding(.horizontal, 14)
                }
            }
            if let tagFeedback {
                Text(tagFeedback)
                    .font(.system(size: 11))
                    .foregroundStyle(tagFeedbackIsError ? Color(red: 0.70, green: 0.39, blue: 0.30) : Palette.green)
                    .transition(.opacity)
            }
        }
    }

    private func refreshClassificationState(for photo: LibraryPhoto?) {
        guard let photo else {
            classifiedAlbums.removeAll()
            return
        }
        classifiedAlbums = library.classifiedAlbumIDs(for: photo)
    }

    private func toggleClassification(_ photo: LibraryPhoto, album: LibraryAlbum, isSelected: Bool) {
        guard !isClassifying else { return }
        isClassifying = true
        Task {
            let result = isSelected
                ? await library.removeClassification(photo, from: album)
                : await library.classify(photo, into: album)
            isClassifying = false
            switch result {
            case .success:
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isSelected {
                        classifiedAlbums.remove(album.id)
                        tagFeedback = "已从「\(album.title)」移除"
                    } else {
                        classifiedAlbums = [album.id]
                        tagFeedback = "已分类到「\(album.title)」"
                    }
                    tagFeedbackIsError = false
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .failure(let error):
                withAnimation(.easeInOut(duration: 0.2)) {
                    refreshClassificationState(for: photo)
                    tagFeedback = error.message
                    tagFeedbackIsError = true
                }
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

struct PendingDeletionView: View {
    @EnvironmentObject private var library: PhotoLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if library.pendingPhotos.isEmpty {
                    EmptyState(symbol: "leaf", title: "干干净净，刚刚好", subtitle: "滑动整理或选择照片，将不需要的项目加入这里。")
                    Spacer()
                } else {
                    Text("点按照片可移出待清理列表").font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.top, 16)
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                            ForEach(library.pendingPhotos) { photo in
                                Button { library.pendingDeletion.remove(photo.id) } label: {
                                    PhotoThumbnail(photo: photo).aspectRatio(1, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(alignment: .topTrailing) {
                                            Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(.white)
                                                .shadow(radius: 3).padding(6)
                                        }
                                }.accessibilityLabel("保留这张照片")
                            }
                        }.padding(.horizontal, 16)
                    }
                    VStack(spacing: 12) {
                        Button { confirm = true } label: {
                            Text(library.isWorking ? "正在删除…" : "删除 \(library.pendingPhotos.count) 个项目")
                        }.buttonStyle(PrimaryButtonStyle()).disabled(library.isWorking)
                        Text(library.isDemo ? "演示模式仅移除示例，不影响系统相册。" : "删除后可在系统相册「最近删除」中恢复，通常保留 30 天。")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                    }.padding(20)
                }
            }.background(Palette.background).navigationTitle("待清理")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("全部保留") { library.pendingDeletion.removeAll() }.disabled(library.isWorking)
                    }
                    ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
                }
                .confirmationDialog("删除这 \(library.pendingPhotos.count) 个项目？", isPresented: $confirm, titleVisibility: .visible) {
                    Button("确认删除", role: .destructive) { Task { await library.deletePending() } }
                    Button("取消", role: .cancel) { }
                } message: { Text(library.isDemo ? "只会移除演示项目，不影响你的照片。" : "这些项目将从系统照片图库及相关相册中删除。") }
        }.tint(Palette.green)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var library: PhotoLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    var body: some View {
        NavigationStack {
            List {
                Section("照片访问") {
                    LabeledContent("当前模式", value: library.isDemo ? "演示模式" : library.authorization == .limited ? "部分照片" : "完整图库")
                    if library.isDemo {
                        Button("连接我的相册") { library.exitDemo(); dismiss(); Task { await library.requestAccess() } }
                    } else {
                        if library.authorization == .limited {
                            Button("选择更多可访问照片") { presentLimitedPicker() }
                        }
                        Button("管理系统照片权限") { openAppSettings() }
                    }
                }
                Section {
                    LabeledContent("已保留", value: "\(library.reviewed.count) 个项目")
                    Button("重置整理进度") { confirmReset = true }
                } header: {
                    Text("整理记录")
                } footer: { Text("重置后可重新整理全部照片，不会修改或删除照片。") }
                Section("关于松鼠相册整理") {
                    LabeledContent("版本", value: "1.0.0")
                    Text("照片只在本机读取和整理。收藏与相册会同步到系统照片 App。")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    Text("视频可在整理卡片和详情页播放，也可参与收藏、相册归类与清理。")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                }
            }.scrollContentBackground(.hidden).background(Palette.background)
                .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
                .confirmationDialog("重新开始整理？", isPresented: $confirmReset, titleVisibility: .visible) {
                    Button("重置进度") { library.resetReview() }
                }
        }.tint(Palette.green)
    }

    private func presentLimitedPicker() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              var controller = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        while let presented = controller.presentedViewController { controller = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
    }
}
