# SodaPulse (汽水脉冲)

一款专为 ColorOS 17 打造的音乐播放器，支持流体云（Fluid Cloud）胶囊联动与逐字卡拉OK（Karaoke）歌词动效。

## 项目结构

```text
.
├── .github/workflows/
│   └── build_apk.yml       # GitHub Actions 云端自动构建 APK 工作流
├── android/                # Android 原生宿主工程（MediaSession / 通知 / 流体云适配）
├── lib/                    # Flutter 应用源码（UI、播放器核心、逐字歌词引擎）
├── test/                   # 单元测试与 Widget 测试
├── analysis_options.yaml   # Dart 静态代码检查配置
└── pubspec.yaml            # Flutter 项目依赖与元数据配置
```

## ColorOS 17 Root / LSPosed 适配模式说明

1. **标准模式（无 Root）**：
   - 通过标准 Android `MediaStyle` 通知与 `MediaSession` 向系统推送播放状态与歌词元数据。
   - 若系统本身允许非白名单应用触发基础媒体胶囊，可直接使用基础媒体控制功能。
2. **Root / LSPosed 增强模式**：
   - ColorOS 流体云（Fluid Cloud）与状态栏歌词对第三方应用存在白名单及系统签名校验限制。
   - 在已获取 Root 权限并安装 **LSPosed** 框架的设备上，可配合对应的系统增强模块（Hook 系统界面/流体云服务白名单校验与状态栏歌词接口），将 SodaPulse 伪装或注入为受信任的媒体服务源，实现完整的流体云胶囊展开动效与系统级实时卡拉OK歌词显示。
   - 请在应用内设置中开启「ColorOS 17 增强适配」开关，并在 LSPosed 管理器中勾选作用域（如系统界面 `com.android.systemui` 及相关系统框架进程）后重启系统界面生效。

## GitHub Actions 云编 APK 指南

本项目已配置 `.github/workflows/build_apk.yml`，无需本地配置完整 Android SDK 即可在云端自动编译 Release APK：

1. 将代码推送至 GitHub 仓库的 `main` 或 `master` 分支，系统将自动触发构建；也可在 GitHub 仓库页面进入 **Actions -> Build Android APK -> Run workflow** 手动触发。
2. 工作流将依次执行：配置 Java 17、Flutter Stable、Gradle 8.10.2、生成 Gradle Wrapper、`flutter pub get`、`flutter analyze`、`flutter test` 与 `flutter build apk --release --target-platform android-arm64`。
3. 构建完成后，在对应 Action 运行详情页底部的 **Artifacts** 区域下载 `soda_pulse-arm64-release-apk`，解压即可获取 `app-arm64-v8a-release.apk` 安装包。

---
