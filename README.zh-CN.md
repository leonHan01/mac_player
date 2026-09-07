# Mac Video Player

> 一款简洁的原生 macOS 本地视频播放器，支持标签、播放列表和熟悉的键盘操作。

[English](README.md) · [简体中文](README.zh-CN.md)

<p align="center">
  <img src="./docs/images/welcome-zh-CN.jpeg" alt="Mac Video Player 中文界面" width="100%">
</p>

Mac Video Player 专注于简单的本地播放流程：打开视频或文件夹，浏览自动生成的播放列表，使用标签整理内容，全程不修改原始媒体文件。

## 功能亮点

- **简洁浅色界面**：采用接近 macOS 原生的视觉风格，提供宽大的视频画面和圆形播放/暂停按钮。
- **本地视频库**：支持打开 MP4、MOV、M4V 和 MKV 文件，也可扫描文件夹并自动生成播放列表。
- **可折叠播放列表**：通过侧边栏按钮收起播放列表，为视频腾出更多空间；重新展开后仍会保留当前选择。
- **本地标签**：可在播放器或标签编辑页添加、删除和筛选标签。标签单独保存为 JSON，不会写入或修改视频文件。
- **中英文界面**：在 **Mac Video Player > 设置…** 中选择 **English** 或 **简体中文**；切换立即生效并会被记住。
- **播放控制**：支持顺序播放、随机播放、进度跳转、音量、上一个/下一个、拖入视频、在 Finder 中显示和截取画面。
- **方向键长按加速**：左右方向键每次跳转 5 秒；持续按住超过 5 秒后，每次重复跳转增加 150%，即每次跳转 12.5 秒。

## 语言设置

<p align="center">
  <img src="./docs/images/settings-zh-CN.jpeg" alt="Mac Video Player 中文设置界面" width="440">
</p>

打开 **Mac Video Player > 设置…**，选择 **English** 或 **简体中文**，点击 **完成** 即可。菜单、播放器控件、播放列表、标签控件和提示会立即更新。

## 快捷操作

| 操作 | 功能 |
| --- | --- |
| `空格` | 播放或暂停 |
| `上方向键` / `下方向键` | 上一个或下一个视频 |
| `左方向键` / `右方向键` | 向后或向前跳转 5 秒 |
| 持续按住 `左方向键` / `右方向键` 超过 5 秒 | 每次重复按键跳转 12.5 秒 |
| 在视频区域滚动 | 切换上一个或下一个视频 |
| 在音量滑块上滚动 | 调节音量 |

播放列表区域保持正常滚动。点击播放器右上角的侧边栏按钮即可收起或重新打开播放列表。

## 标签

在 **添加标签** 输入框中键入标签后按 Return，或点击 **添加**。即使播放状态更新、正在使用输入法组合文字，输入框仍可持续编辑。选择播放列表筛选器中的标签，即可只显示匹配的视频。

标签保存在：

```text
~/Library/Application Support/MacVideoPlayer/tags.json
```

## 构建

### 环境要求

- macOS 13.0 或更高版本
- Swift 6 和 macOS Command Line Tools
- `Vendor/IINAFrameworks` 中的 IINA/libmpv 运行库

如果仓库中没有运行库，请先安装 IINA，再导入其 Frameworks 目录：

```sh
./scripts/fetch-iina-runtime.sh
```

如果 IINA 安装在 `/Applications/IINA.app` 以外的位置，可以设置 `IINA_APP`：

```sh
IINA_APP="/path/to/IINA.app" ./scripts/fetch-iina-runtime.sh
```

构建应用包：

```sh
./scripts/build-app.sh
```

构建结果位于 `build/MacVideoPlayer.app`。创建 DMG 安装镜像：

```sh
./scripts/build-dmg.sh
```

## 验证

如环境提供 XCTest，可运行：

```sh
swift test
```

仅安装 Command Line Tools 时，可运行核心回归检查：

```sh
python3 scripts/test-regressions.py
```

检查覆盖语言保存、标签输入和输入法行为、播放列表筛选和排序、方向键长按加速、播放事件、命令串行化、截图路径和干净的 DMG 暂存流程，不会打开播放器窗口或解码媒体。

性能回归还覆盖后台标签写入、并发编辑和失败恢复、跳过未变化的保存、排序缓存、扫描取消、扫描期间删除文件以及暂停时的进度更新。若环境无法提供 OpenGL 像素格式，脚本会明确跳过隐藏窗口的输入检查，其余核心检查继续执行。

## 运行库与许可证

应用包包含 IINA/libmpv 和相关媒体依赖。它直接解码原始文件，在系统支持时使用硬件解码，不会对媒体重新封装或转码。

由于发布版本包含 IINA/libmpv 运行库，本项目采用 GNU GPLv3 许可证。重新分发时，请同时提供对应源代码和第三方声明。

- [LICENSE](LICENSE)
- [第三方声明](THIRD_PARTY_NOTICES.md)
- 上游 IINA 源码参考：`ThirdParty/IINA`，提交号 `db549a6`

Mac Video Player 与 IINA、FFmpeg、VLC、Sparkle 和 Apple 没有隶属、赞助或官方背书关系。
