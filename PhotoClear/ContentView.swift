import SwiftUI
import PhotosUI

struct ContentView: View {
    @EnvironmentObject private var library: PhotoLibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    @State private var navReset = 0
    @State private var showSettings = false

    var body: some View {
        Group {
            if library.hasAccess || library.isDemo {
                VStack(spacing: 0) {
                    HStack {
                        HStack(spacing: 8) {
                            Image("SquirrelLogo").resizable().interpolation(.none)
                                .frame(width: 32, height: 32)
                            Text("松鼠相册整理").font(.system(size: 21, weight: .semibold, design: .serif))
                        }
                        Spacer()
                        if library.isDemo {
                            Text("演示模式").font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Palette.lime.opacity(0.5), in: Capsule())
                        }
                        Button { showSettings = true } label: {
                            Image(systemName: "slider.horizontal.3").font(.system(size: 20))
                                .frame(width: 44, height: 44)
                        }.accessibilityLabel("设置")
                    }.padding(.horizontal, 24).padding(.top, 4).foregroundStyle(Palette.green)
                    NavigationStack {
                        Group {
                            switch tab {
                            case 1: ProfileView()
                            default: DashboardView()
                            }
                        }.toolbar(.hidden, for: .navigationBar)
                    }.id("\(tab)-\(navReset)").tint(Palette.green)
                    HStack(spacing: 0) {
                        tabItem("整理", symbol: "sparkles", index: 0)
                        tabItem("我的", symbol: "person.crop.circle", index: 1)
                    }.padding(.top, 12).padding(.bottom, 5)
                        .background(Palette.background.shadow(color: .black.opacity(0.04), radius: 10, y: -3))
                }
            } else {
                WelcomeView()
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .sheet(isPresented: $showSettings) { SettingsView() }
        .alert("操作未完成", isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })) {
            Button("好", role: .cancel) { library.errorMessage = nil }
        } message: { Text(library.errorMessage ?? "") }
        .overlay(alignment: .top) {
            if let notice = library.notice {
                Text(notice).font(.subheadline.weight(.medium)).padding(.horizontal, 20).padding(.vertical, 12)
                    .foregroundStyle(.white).background(Palette.green, in: Capsule()).padding(.top, 54)
                    .task(id: notice) {
                        try? await Task.sleep(for: .seconds(2))
                        if library.notice == notice { library.notice = nil }
                    }
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { library.refreshAuthorization() } }
    }

    private func tabItem(_ title: String, symbol: String, index: Int) -> some View {
        Button {
            if tab == index { navReset += 1 } else { tab = index }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 20, weight: tab == index ? .semibold : .regular))
                Text(title).font(.system(size: 11, weight: tab == index ? .semibold : .regular))
            }.foregroundStyle(tab == index ? Palette.green : Palette.muted)
                .frame(maxWidth: .infinity).frame(height: 45)
        }.accessibilityAddTraits(tab == index ? .isSelected : [])
    }
}

struct WelcomeView: View {
    @EnvironmentObject private var library: PhotoLibraryStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    Image("SquirrelLogo").resizable().interpolation(.none)
                        .frame(width: 30, height: 30)
                    Text("松鼠相册整理 SQUIRREL CLEAR")
                        .font(.system(size: 15, weight: .semibold)).tracking(2)
                }.padding(.top, 30)
                ZStack {
                    DemoLandscape(index: 0).frame(height: 290).clipShape(RoundedRectangle(cornerRadius: 28))
                        .rotationEffect(.degrees(-5)).padding(18)
                    VStack {
                        Spacer()
                        HStack {
                            Label("让美好，留下来", systemImage: "sparkles")
                                .font(.system(size: 14, weight: .medium)).padding(14)
                                .background(.regularMaterial, in: Capsule())
                            Spacer()
                        }.padding(28)
                    }
                }.frame(height: 330)
                Text("给相册一点留白。")
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                Text("整理随手拍，收藏心动瞬间。\n从一张照片开始，让回忆井井有条。")
                    .font(.system(size: 16)).foregroundStyle(Palette.muted).lineSpacing(7)
                Button { Task { await library.requestAccess() } } label: {
                    Label("开启我的相册", systemImage: "arrow.right")
                }.buttonStyle(PrimaryButtonStyle())
                if library.authorization == .denied || library.authorization == .restricted {
                    Button("前往设置，允许访问照片") { openAppSettings() }
                        .frame(maxWidth: .infinity).font(.subheadline)
                }
                Button("先体验一下") { library.startDemo() }
                    .frame(maxWidth: .infinity).font(.subheadline).foregroundStyle(Palette.muted)
                Label("照片仅在设备上处理，不上传云端", systemImage: "lock.shield")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
            }.padding(28)
        }.foregroundStyle(Palette.green)
    }
}

struct DashboardView: View {
    @EnvironmentObject private var library: PhotoLibraryStore
    @State private var showReview = false
    @State private var randomReview: RandomReview?
    @State private var showTrash = false
    @State private var monthReview: MonthReview?
    @State private var showAllMonths = false
    @State private var confirmAlbum: LibraryAlbum?
    @State private var renamingAlbum: LibraryAlbum?
    @State private var showCreateAlbum = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 27) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Date().formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier: "zh_CN"))))
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
                    Text("少一点杂乱，\n多一点美好。")
                        .font(.system(size: 33, weight: .semibold, design: .serif)).lineSpacing(4)
                }.padding(.top, 15)
                hero
                VStack(spacing: 10) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        NavigationLink {
                            PhotoBrowserView(title: "待整理", source: library.unreviewed)
                                .toolbar(.visible, for: .navigationBar)
                        } label: {
                            metric(value: library.unreviewed.count, title: "待整理", symbol: "sparkles")
                        }.buttonStyle(.plain)
                        NavigationLink {
                            PhotoBrowserView(title: "已保留", source: library.reviewedPhotos, allowsRestart: true)
                                .toolbar(.visible, for: .navigationBar)
                        } label: {
                            metric(value: library.reviewed.count, title: "已保留", symbol: "checkmark.seal")
                        }.buttonStyle(.plain)
                        Button { showTrash = true } label: {
                            metric(value: library.pendingDeletion.count, title: "待清理", symbol: "trash")
                        }.buttonStyle(.plain)
                    }
                    Text("共 \(library.photos.count) 个项目")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                VStack(spacing: 15) {
                    SectionHeading(title: "从这里开始", caption: "小整理 · 大轻松")
                    HStack(spacing: 12) {
                        category(.screenshots, description: "告别临时备忘", color: Color(red: 0.92, green: 0.89, blue: 0.80))
                        category(.videos, description: "重温动态回忆", color: Color(red: 0.85, green: 0.89, blue: 0.84))
                    }
                }
                VStack(spacing: 14) {
                    SectionHeading(title: "我的相册", caption: library.albums.isEmpty ? "先创建一本空相册" : "\(library.albums.count) 本回忆")
                    Button { showCreateAlbum = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 20, weight: .medium))
                                .frame(width: 42, height: 42)
                                .background(Palette.lime, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text("新建相册").font(.system(size: 15, weight: .semibold))
                                Text("不必先选择照片，也可以创建空相册。")
                                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Palette.muted)
                        }.padding(15).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)
                    if !library.albums.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                            ForEach(library.albums) { album in
                                NavigationLink {
                                    PhotoBrowserView(title: album.title, source: library.photos(in: album))
                                        .toolbar(.visible, for: .navigationBar)
                                } label: {
                                    albumCard(album)
                                }
                                .buttonStyle(.plain)
                                .contextMenu { albumActions(album) }
                            }
                        }
                    }
                }
                monthsSection
                Text("每一张留下的照片，都值得被记住。")
                    .font(.system(size: 12, design: .serif)).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }.padding(.horizontal, 24).padding(.bottom, 24)
        }.background(Palette.background).foregroundStyle(Palette.green)
            .fullScreenCover(isPresented: $showReview) { ReviewView() }
            .fullScreenCover(item: $randomReview) { ReviewView(source: $0.photos) }
            .fullScreenCover(item: $monthReview) { ReviewView(source: $0.month.photos) }
            .sheet(isPresented: $showTrash) { PendingDeletionView() }
            .sheet(isPresented: $showCreateAlbum) { CreateAlbumView() }
            .sheet(item: $renamingAlbum) { RenameAlbumView(album: $0) }
            .confirmationDialog("删除空相册「\(confirmAlbum?.title ?? "")」？", isPresented: Binding(get: { confirmAlbum != nil }, set: { if !$0 { confirmAlbum = nil } }), titleVisibility: .visible) {
                Button("删除相册", role: .destructive) {
                    if let album = confirmAlbum { Task { await library.deleteAlbum(album) } }
                    confirmAlbum = nil
                }
                Button("取消", role: .cancel) { confirmAlbum = nil }
            } message: {
                Text("该相册没有任何照片，删除不会影响你的照片。")
            }
    }

    private func isAlbumEmpty(_ album: LibraryAlbum) -> Bool {
        album.count == 0 || library.photos(in: album).isEmpty
    }

    @ViewBuilder private func albumCard(_ album: LibraryAlbum) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let cover = album.cover { PhotoThumbnail(photo: cover) }
                else { Palette.line.overlay { Image(systemName: "photo").foregroundStyle(Palette.muted) } }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .topTrailing) {
                if library.canRenameAlbum(album) || isAlbumEmpty(album) {
                    Menu { albumActions(album) } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Palette.green.opacity(0.85), in: Circle())
                            .shadow(radius: 3)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("相册更多操作")
                }
            }
            Text(album.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
            Text(isAlbumEmpty(album) ? "空相册" : "\(album.count) 个项目")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
    }

    @ViewBuilder private func albumActions(_ album: LibraryAlbum) -> some View {
        if library.canRenameAlbum(album) {
            Button {
                renamingAlbum = album
            } label: {
                Label("重命名", systemImage: "pencil")
            }
        }
        if isAlbumEmpty(album) {
            Button(role: .destructive) {
                confirmAlbum = album
            } label: {
                Label("删除空相册", systemImage: "trash")
            }
        }
    }

    private var monthsSection: some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("按月慢慢整理").font(.system(size: 21, weight: .semibold))
                Spacer()
                if library.months.count > 6 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { showAllMonths.toggle() }
                    } label: {
                        Text(showAllMonths ? "收起" : "显示全部 \(library.months.count)")
                            .font(.system(size: 12, weight: .medium))
                    }.buttonStyle(.plain)
                } else {
                    Text("\(library.months.count) 个月的回忆").font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
            }
            ForEach(showAllMonths ? library.months : Array(library.months.prefix(6))) { month in
                HStack(spacing: 10) {
                    NavigationLink {
                        PhotoBrowserView(title: month.title, source: month.photos)
                            .toolbar(.visible, for: .navigationBar)
                    } label: {
                        HStack(spacing: 15) {
                            if let cover = month.photos.first {
                                PhotoThumbnail(photo: cover).frame(width: 62, height: 66)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(month.title).font(.system(size: 16, weight: .medium))
                                Text("\(month.photos.count) 个项目").font(.system(size: 12)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Palette.muted)
                        }
                    }.buttonStyle(.plain)
                    Button { monthReview = MonthReview(month: month) } label: {
                        Text("整理").font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .background(Palette.lime, in: Capsule())
                    }.buttonStyle(.plain)
                }.padding(12).background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("今日的整理时刻").font(.system(size: 12)).foregroundStyle(Palette.lime)
                    Text("给回忆做个减法").font(.system(size: 23, weight: .semibold))
                    Text("还有 \(library.unreviewed.count) 个项目等待整理")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Image(systemName: "leaf").font(.system(size: 41, weight: .ultraLight)).foregroundStyle(Palette.lime)
                    .rotationEffect(.degrees(-20))
            }
            HStack(spacing: 10) {
                Button { showReview = true } label: {
                    Label("从最新开始", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    randomReview = RandomReview(photos: library.unreviewed.shuffled())
                } label: {
                    Label("随机整理", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(15)
            .foregroundStyle(Palette.green)
            .background(Palette.lime, in: RoundedRectangle(cornerRadius: 12))
            .disabled(library.unreviewed.isEmpty)
        }.padding(23).foregroundStyle(.white).background(Palette.green, in: RoundedRectangle(cornerRadius: 25))
    }

    private func metric(value: Int, title: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(Palette.muted)
            Text(value.formatted()).font(.system(size: 25, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.system(size: 11)).foregroundStyle(Palette.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(15)
            .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 17))
    }

    private func category(_ filter: PhotoFilter, description: String, color: Color) -> some View {
        NavigationLink {
            PhotoBrowserView(initialFilter: filter).toolbar(.visible, for: .navigationBar)
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: filter.symbol).font(.system(size: 24, weight: .light))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 12))
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(filter.rawValue) · \(library.photos.filter(filter.includes).count)").font(.system(size: 16, weight: .semibold))
                    Text(description).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(color, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain)
    }
}

struct CreateAlbumView: View {
    @EnvironmentObject private var library: PhotoLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasDuplicateName: Bool {
        library.albums.contains { $0.title.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("相册名称") {
                    TextField("例如：旅行灵感", text: $name)
                        .submitLabel(.done)
                        .onSubmit { createIfPossible() }
                    if trimmedName.isEmpty && !name.isEmpty {
                        Label("相册名称不能只包含空格", systemImage: "exclamationmark.circle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    if !trimmedName.isEmpty && hasDuplicateName {
                        Label("已存在同名相册，将创建一本新的同名空相册。", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(Palette.muted)
                    }
                }
                Section {
                    Button(hasDuplicateName ? "仍然创建同名相册" : "创建空相册") { createIfPossible() }
                        .disabled(trimmedName.isEmpty || library.isWorking)
                } footer: {
                    Text("创建成功后会写入系统相册，并刷新显示在 App 的相册列表中。")
                }
            }
            .navigationTitle("新建相册")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { dismiss() } } }
        }.tint(Palette.green)
    }

    private func createIfPossible() {
        guard !trimmedName.isEmpty, !library.isWorking else { return }
        Task { if await library.createAlbum(title: name) { dismiss() } }
    }
}

struct RenameAlbumView: View {
    @EnvironmentObject private var library: PhotoLibraryStore
    @Environment(\.dismiss) private var dismiss
    let album: LibraryAlbum
    @State private var name: String

    init(album: LibraryAlbum) {
        self.album = album
        _name = State(initialValue: album.title)
    }

    private var cleanedName: String { PhotoLibraryStore.sanitizedAlbumTitle(name) }
    private var hasDuplicateName: Bool { library.hasAlbum(named: name, excluding: album.id) }
    private var isUnchanged: Bool { cleanedName == PhotoLibraryStore.sanitizedAlbumTitle(album.title) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("相册名称", text: $name)
                        .submitLabel(.done)
                        .onSubmit { renameIfPossible() }
                        .onChange(of: name) { _, value in
                            let filtered = PhotoLibraryStore.albumTitleWithoutControlCharacters(value)
                            if filtered != value { name = filtered }
                        }
                    if cleanedName.isEmpty && !name.isEmpty {
                        Label("相册名称不能只包含空格", systemImage: "exclamationmark.circle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    if hasDuplicateName {
                        Label("已存在同名相册，请换一个名称。", systemImage: "exclamationmark.circle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                } header: {
                    Text("新名称")
                } footer: {
                    Text("支持特殊字符和 Emoji；粘贴内容中的换行和控制字符会自动移除。")
                }
                Section {
                    Button("保存名称") { renameIfPossible() }
                        .disabled(cleanedName.isEmpty || hasDuplicateName || isUnchanged || library.isWorking)
                }
            }
            .navigationTitle("重命名相册")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { dismiss() } } }
        }.tint(Palette.green)
    }

    private func renameIfPossible() {
        guard !cleanedName.isEmpty, !hasDuplicateName, !isUnchanged, !library.isWorking else { return }
        Task { if await library.renameAlbum(album, to: name) { dismiss() } }
    }
}

private struct RandomReview: Identifiable {
    let id = UUID()
    let photos: [LibraryPhoto]
}

private struct MonthReview: Identifiable {
    let month: PhotoMonth
    var id: Date { month.date }
}

func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
}
