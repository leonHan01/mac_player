# Mac Video Player

> 一款轻量级 macOS 本地视频播放器，支持文件夹播放列表、标签管理、随机播放，以及基于 IINA/libmpv 的硬件解码和 GPU 渲染。

[English](README.md) · [简体中文](README.zh-CN.md)

Mac Video Player 是一款原生 macOS 本地视频播放器，专注于简单的本地播放流程。打开视频或文件夹后，应用会自动生成附近视频文件的播放列表，并使用本地标签进行分类，不会修改原始媒体文件。

## 功能

- 支持打开本地 MP4、MOV、M4V 和 MKV 文件。
- 打开文件夹并自动生成播放列表。
- 按文件名或文件大小排序。
- 支持顺序播放和随机播放；随机模式下保留播放历史，方便返回上一个视频。
- 提供播放/暂停、上一集、下一集、快进、进度条和音量控制。
- 支持将视频文件拖入窗口播放。
- 支持添加、删除和筛选本地标签。标签保存在 JSON 文件中，不会写入视频文件。
- 支持使用可配置的快捷键截取当前视频画面。
- 确认后可将当前视频移动到 macOS 废纸篓。
- 可在 Finder 中定位当前视频文件。
- 使用 IINA/libmpv 提供格式支持、硬件解码和 GPU 渲染。
- 使用 Swift Package Manager 构建，不需要 Xcode 工程文件。

## 环境要求

- macOS 13.0 或更高版本。
- Swift 6 工具链和 macOS Command Line Tools。
- `Vendor/IINAFrameworks` 中存在 IINA/libmpv 运行库。

如果仓库中没有运行库，请先安装官方 IINA，然后导入它的 Frameworks 目录：

```sh
./scripts/fetch-iina-runtime.sh
```

如果 IINA 安装在 `/Applications/IINA.app` 以外的位置，可以设置 `IINA_APP`：

```sh
IINA_APP="/path/to/IINA.app" ./scripts/fetch-iina-runtime.sh
```

## 构建

构建 macOS 应用：

```sh
./scripts/build-app.sh
```

构建结果位于：

```text
build/MacVideoPlayer.app
```

创建 DMG 安装镜像：

```sh
./scripts/build-dmg.sh
```

也可以直接运行 Swift 可执行文件：

```sh
swift run MacVideoPlayer
```

直接运行的调试可执行文件不包含 IINA/libmpv 运行库。要播放视频，请使用 `scripts/build-app.sh` 构建出的应用包。

## 测试

运行测试：

```sh
swift test
```

## 播放和快捷操作

- `文件 > 打开...`：打开视频，并扫描所在文件夹中的支持格式视频。
- `文件 > 打开文件夹...`：直接扫描指定文件夹。
- `文件 > 上一个视频` 和 `文件 > 下一个视频`：切换播放列表项目。
- `文件 > 切换大小排序`：在文件名排序和文件大小排序之间切换。
- `文件 > 编辑标签...`：编辑当前视频的全部标签。
- `文件 > 在 Finder 中显示`：在 Finder 中打开当前视频所在位置。
- `文件 > 删除当前视频`：确认后将当前视频移动到废纸篓。
- `空格键`：播放/暂停。
- `上方向键` 和 `下方向键`：切换上一个或下一个视频。
- `左方向键` 和 `右方向键`：向前或向后跳转 5 秒。
- 在视频区域滚动：切换上一个或下一个视频；播放列表区域保持正常滚动。
- 在音量滑块上滚动：调节音量。

标签保存在：

```text
~/Library/Application Support/MacVideoPlayer/tags.json
```

## 运行库和许可证

应用会捆绑 IINA/libmpv 运行库及相关媒体依赖。运行库使用 FFmpeg，并会在系统支持时使用硬件解码。播放器直接解码原始文件，不进行封装转换或转码。

由于发布的应用包含 IINA/libmpv 运行库，本项目使用 GNU GPLv3 许可证发布。重新分发应用构建版本时，应同时向接收者提供完整的对应源代码和第三方声明。

相关文件：

- [LICENSE](LICENSE)
- [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
- `ThirdParty/IINA` 中记录的上游 IINA 源码版本，提交号为 `db549a6`

## 项目状态

这是一个面向本地播放和实验用途的 macOS 小型项目。本项目与 IINA、FFmpeg、VLC、Sparkle 或 Apple 没有隶属、赞助或官方背书关系。
