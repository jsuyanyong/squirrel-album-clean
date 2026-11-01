import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var library: PhotoLibraryStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                greeting
                freeCard
                stats
                VStack(spacing: 12) {
                    SectionHeading(title: "设置", caption: "照片仅在设备上处理")
                    row("照片权限", symbol: "lock.shield") { openAppSettings() }
                }
                Text("松鼠相册整理 · 版本 1.0.0")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity).padding(.top, 4)
            }.padding(.horizontal, 24).padding(.top, 15).padding(.bottom, 24)
        }
        .background(Palette.background)
        .foregroundStyle(Palette.green)
    }

    private var greeting: some View {
        HStack(spacing: 12) {
            Image("SquirrelLogo").resizable().interpolation(.none)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("我的").font(.system(size: 27, weight: .semibold, design: .serif))
                Text("免费整理你的相册，照片仅在设备上处理")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            Spacer()
        }.padding(.top, 8)
    }

    private var freeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("免费版", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.green)
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Palette.lime, in: Capsule())
                Spacer()
            }
            Text("全部功能已免费开放。")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text("新建相册、相册改名、边清理边归类和删除清理都可直接使用，全部免费开放。")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
                .lineLimit(3)
        }.padding(22)
            .foregroundStyle(.white)
            .background(Palette.green, in: RoundedRectangle(cornerRadius: 25))
    }

    private var stats: some View {
        HStack(spacing: 16) {
            Image(systemName: "internaldrive")
                .font(.system(size: 26, weight: .light)).foregroundStyle(Palette.green)
                .frame(width: 44, height: 44).background(Palette.lime.opacity(0.5), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("已为您节省 \(library.savedSpaceText) 空间")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.green)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(library.pendingDeletion.isEmpty
                     ? "整理出不需要的照片，腾出更多空间"
                     : "\(library.pendingDeletion.count) 个待清理项目，确认后即可释放")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }.padding(18)
            .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
    }

    private func row(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(Palette.green)
                    .frame(width: 22)
                Text(title).font(.system(size: 14))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Palette.muted)
            }.padding(15).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(Palette.green)
        }.buttonStyle(.plain)
    }
}
