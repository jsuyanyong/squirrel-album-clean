拾光 · PhotoClear
原生 iOS 相册整理 App，SwiftUI + PhotoKit，最低支持 iOS 17。

运行
1. 使用 Xcode 15 或更新版本打开 PhotoClear.xcodeproj。
2. 选择 PhotoClear scheme 和 iPhone 模拟器，点击 Run。
3. 启动页点击“先体验一下”，即可浏览 48 个离线插画演示项目。
4. 真机运行：在 Signing & Capabilities 选择你的 Development Team，
   将 Bundle Identifier 改为自己的唯一标识，连接 iPhone 后运行。
5. 点击“开启我的相册”，允许完整或部分照片访问。

功能
- 整理首页：项目统计、截图与视频入口、按月浏览与按月整理。
- 滑动整理：左滑加入待清理，右滑保留，可撤销上一次操作；可按月份或当前筛选范围整理。
- 待清理列表：点按移出、全部保留、确认批量删除。
- 照片：全部/截图/视频/收藏筛选，多选、全选、批量收藏。
- 相册：创建相册、加入已有相册、查看相册内容。
- 照片详情：查看大图或播放视频、切换收藏状态、加入相册。
- 设置：权限管理、部分访问补选、重置整理进度。
- 整理进度和待清理队列保存在本机，重启后可继续。
- 离线演示模式，不读取或修改真实图库。

说明
“保留”只记录整理进度；“收藏”会修改系统照片收藏状态。
删除前会显示 App 确认框，PhotoKit 还会由系统请求确认。
真实删除会影响系统图库及相关相册；通常可在“最近删除”中恢复。
iCloud 照片通过系统 PhotoKit 下载预览；App 不向自建服务上传照片。
视频在详情页可直接播放（支持 iCloud 下载与系统播放控件），演示模式仍以插画封面展示。
演示中的相册内容是示例；连接真实图库后使用系统相册数据。

项目结构
PhotoClear/PhotoClearApp.swift       App 入口
PhotoClear/Models.swift              照片、筛选、月份、相册模型
PhotoClear/PhotoLibraryStore.swift   PhotoKit 授权与读写、本地状态
PhotoClear/Components.swift          配色、缩略图、离线插画、通用组件
PhotoClear/ContentView.swift         启动页、导航、整理首页
PhotoClear/PhotoBrowserView.swift    网格、详情、相册与相册选择器
PhotoClear/ReviewView.swift          滑动整理、待清理、设置

构建检查（安装完整 Xcode 后）
xcodebuild -project PhotoClear.xcodeproj -scheme PhotoClear \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

当前环境验证
已通过 Swift frontend 语法解析、Info.plist / project.pbxproj 格式校验、scheme XML 校验。
当前机器仅安装 Command Line Tools，无法进行 iOS SDK 类型检查、模拟器构建与真机测试。

真机验收建议
1. 分别测试拒绝权限、部分授权、完整授权，检查设置入口与补选。
2. 收藏照片并创建相册，确认系统照片 App 中同步显示。
3. 左右滑动后撤销，退出重进，检查进度与待清理队列。
4. 使用可丢弃的测试照片验证删除取消、删除确认与“最近删除”恢复。
5. 在系统相册新增/删除照片或修改权限后返回，检查数据刷新。
