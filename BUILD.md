# PiliPlus-A 多平台构建与发布指南

本项目为 **PiliPlus-A**（哔哩哔哩第三方 Flutter 客户端），包名与应用标识已全面独立，支持与原版 PiliPlus 以及官方哔哩哔哩客户端在同一设备上**完全共存安装**。

---

## 目录

- [一、环境准备](#一环境准备)
- [二、克隆与初始化](#二克隆与初始化)
- [三、本地多平台编译指南](#三本地多平台编译指南)
  - [1. Android 版本编译](#1-android-版本编译)
  - [2. Windows 桌面版编译](#2-windows-桌面版编译)
  - [3. Linux 桌面版编译](#3-linux-桌面版编译)
  - [4. macOS 桌面版编译](#4-macos-桌面版编译)
  - [5. iOS 移动端编译](#5-ios-移动端编译)
- [四、GitHub Actions 自动化编译与发布 Releases](#四github-actions-自动化编译与发布-releases)
  - [1. 自动打标签发布](#1-自动打标签发布)
  - [2. 手动在 GitHub 触发构建](#2-手动在-github-触发构建)
- [五、共存特性与标识说明](#五共存特性与标识说明)
- [六、常见问题与注意事项](#六常见问题与注意事项)

---

## 一、环境准备

构建各平台前请确保安装好以下基础依赖：

| 工具 / SDK | 建议版本 | 适用平台 |
| :--- | :--- | :--- |
| **Flutter SDK** | **3.47.5 (Stable)** | 全平台通用 |
| **Dart SDK** | 3.12.0+ (内置于 Flutter) | 全平台通用 |
| **PowerShell** | 7.0+ (pwsh) 或 Windows PowerShell 5.1 | 执行 build.ps1 / patch.ps1 脚本 |
| **JDK (Java)** | 17 (推荐 Zulu JDK 或 Temurin) | Android |
| **Android SDK / NDK** | compileSdk 37, NDK 26+ | Android |
| **Visual Studio** | 2022 (勾选「使用 C++ 的桌面开发」) | Windows |
| **Inno Setup** | 6.x (安装并在 Languages 放入中文文件) | Windows 安装包打包 |
| **fastforge** | 最新版 (`dart pub global activate fastforge`) | Windows 打包向导 |
| **Xcode** | 15.0+ | macOS / iOS |
| **GTK / CMake / Ninja** | `libgtk-3-dev`, `libmpv-dev`, `webkit2gtk-4.1` | Linux |

---

## 二、克隆与初始化

1. **克隆源码仓库**：
   ```bash
   git clone https://github.com/xin-build/PiliPlus-A.git
   cd PiliPlus-A
   ```

2. **拉取依赖包**：
   ```bash
   flutter pub get
   ```

3. **生成版本元数据**：
   项目内置了自动化版本解析脚本，编译前需执行一次生成 `pili_release.json`：
   ```powershell
   # Windows PowerShell 或 Linux/macOS pwsh
   pwsh lib/scripts/build.ps1
   # 若为 Android 则指定平台参数：
   pwsh lib/scripts/build.ps1 android
   ```

---

## 三、本地多平台编译指南

### 1. Android 版本编译

支持生成主流 64 位、32 位及 x86 平板模拟器专用的独立 APK：

```bash
# 1. 执行补丁脚本（可选）：
pwsh lib/scripts/patch.ps1 android

# 2. 分架构编译 Release APK
flutter build apk --release --split-per-abi --dart-define-from-file=pili_release.json --no-pub
```
构建产物路径：`build/app/outputs/flutter-apk/app-*-release.apk`

---

### 2. Windows 桌面版编译

#### 方式 A：生成安装包 (.exe) 与便携包 (.zip)
```powershell
# 1. 全局激活 fastforge
dart pub global activate fastforge

# 2. 应用 Windows 补丁
pwsh lib/scripts/patch.ps1 windows

# 3. 使用 fastforge 编译打包
fastforge package --platform windows --targets exe --flutter-build-args="dart-define-from-file=pili_release.json,no-pub" --skip-clean
```
构建完成后：
- 安装包位于：`dist/` 目录下
- 二进制绿色目录位于：`build/windows/x64/runner/Release/`

#### 方式 B：仅生成独立可执行程序
```bash
flutter build windows --release --dart-define-from-file=pili_release.json --no-pub
```

---

### 3. Linux 桌面版编译

支持在 Ubuntu / Debian / Fedora 等环境下编译：

1. **安装底层依赖（Ubuntu / Debian 为例）**：
   ```bash
   sudo apt-get update
   sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev \
       libayatana-appindicator3-dev webkit2gtk-4.1 libasound2-dev libmpv-dev rpm
   ```

2. **编译与打包**：
   ```bash
   # 应用 Linux 优化补丁
   pwsh lib/scripts/patch.ps1 Linux

   # 编译二进制
   flutter build linux --release --dart-define-from-file=pili_release.json --no-pub

   # 制作 tar.gz 归档包
   tar -zcvf PiliPlus-A_linux_amd64.tar.gz -C build/linux/x64/release/bundle .
   ```

---

### 4. macOS 桌面版编译

须在 Apple macOS 设备或 macOS 虚拟机/CI 环境下运行：

```bash
# 1. 编译 Mac 原生应用
flutter build macos --release --dart-define-from-file=pili_release.json --no-pub

# 2. 使用 create-dmg 或 hdiutil 生成 DMG 磁盘镜像
hdiutil create -volname "PiliPlus-A" -srcfolder "build/macos/Build/Products/Release/PiliPlus-A.app" -ov -format UDZO "PiliPlus-A_macos.dmg"

# 3. 生成 ZIP 压缩包
ditto -c -k --sequesterRsrc --keepParent "build/macos/Build/Products/Release/PiliPlus-A.app" "PiliPlus-A_macos.zip"
```

---

### 5. iOS 移动端编译

无需开发者付费证书即可生成支持 TrollStore、AltStore、Sideloadly 侧载的 `.ipa`：

```bash
# 1. 编译无证书 iOS 项目
flutter build ios --release --no-codesign --dart-define-from-file=pili_release.json --no-pub

# 2. 组装标准 Payload 目录并压缩成 IPA
rm -rf Payload && mkdir -p Payload
cp -r build/ios/iphoneos/Runner.app Payload/
find Payload/Runner.app/Frameworks -type d -name "*.framework" -exec codesign --force --sign - --preserve-metadata=identifier,entitlements {} \; || true
zip -r9 PiliPlus-A_ios.ipa Payload
```

---

## 四、GitHub Actions 自动化编译与发布 Releases

本仓库配置了全自动化的持续集成与持续发布（CI/CD）工作流，支持一键将全平台产物打包并发布至 GitHub Releases。

### 1. 自动打标签发布

只需推送符合规范的版本标签（如 `v2.1.4.1`、`release-2.1.4.1`），CI 会自动触发并在编译成功后把全平台 11 个安装包一并关联至该 Release：

```bash
# 创建版本标签
git tag v2.1.4.1

# 推送标签至 GitHub 仓库
git push origin v2.1.4.1
```

GitHub Actions 将自动执行：
- 编译 Android (arm64-v8a / armeabi-v7a / x86_64)
- 编译 Windows (Setup.exe / Portable.zip)
- 编译 macOS (DMG / ZIP)
- 编译 iOS (IPA)
- 编译 Linux (Deb / Rpm / AppImage / Tar.gz)
- 将所有二进制文件自动发布到 Release 页面，无需任何人工搬运！

### 2. 手动在 GitHub 触发构建

1. 进入仓库页面：**Actions** -> **Build**
2. 点击 **Run workflow**
3. 选择分支（`main` 或 `master`）
4. （可选）在 `tag` 栏填入发布标签名，勾选需要构建的目标平台，点击绿色按钮开始。

---

## 五、共存特性与标识说明

为了避免与原版 PiliPlus 发生覆盖或冲突，本项目各平台已完成下列隔离：

| 平台 | 属性 | 原版 PiliPlus | **本项目 PiliPlus-A** |
| :--- | :--- | :--- | :--- |
| **Android** | ApplicationId | `com.example.piliplus` | **`com.example.piliplus.a`** |
| **Android** | App Name | `PiliPlus` | **`PiliPlus-A`** |
| **Android** | Documents Provider | `.MTDataFilesProvider` | **`${applicationId}.MTDataFilesProvider`** |
| **Windows** | Inno Setup AppId | `5ef970f9-...-b226` | **`c7a42e18-...-d8a1`** |
| **Windows** | 默认安装路径 | `Program Files\PiliPlus` | **`Program Files\PiliPlus-A`** |
| **Windows** | 窗口互斥标识 | `piliplus` | **`PiliPlus-A`** (可双开运行) |
| **macOS** | Bundle Identifier | `com.example.piliplus` | **`com.example.piliplus.a`** |
| **macOS** | App Bundle Name | `PiliPlus.app` | **`PiliPlus-A.app`** |
| **iOS** | Bundle Identifier | `com.example.piliplus` | **`com.example.piliplus.a`** |
| **iOS** | Display Name | `PiliPlus` | **`PiliPlus-A`** |
| **Linux** | Application ID | `com.example.piliplus` | **`com.example.piliplus.a`** |
| **Linux** | Desktop 文件 | `PiliPlus` | **`PiliPlus-A`** |

---

## 六、常见问题与注意事项

1. **`flutter-action` 版本下载报错**：
   - 请保持 `pubspec.yaml` 中 `environment.flutter: 3.47.5` 精确版本号写法，勿加 `>=` 或 `^` 符号。
2. **`pubspec.yaml` 版本规范与发布标签**：
   - `pubspec.yaml` 中的 `version:` 字段受 Dart 包管理器严格约束，必须保持标准三段式 SemVer 格式（例如 `2.1.5+1`），切勿使用非标准四段式（如 `2.1.5.1+1`）。
   - CI 构建脚本 `build.ps1` 会自动从 Git 标签（例如 `v2.1.5`）提取发布版本号，并在各平台安装包与内置关于信息中正确注入版本标识。
3. **`patch.ps1` 提示找不到 cupertino_ui**：
   - 执行 patch 之前必须先执行 `flutter pub get`，确保缓存中有相关组件包。
4. **Android 签名配置**：
   - 默认使用 debug 签名或由 CI 环境变量中配置的 KeyStore 签名。
   - 若需使用自己的签名文件，在 `android/key.properties` 中填入路径与密钥即可。
