import Foundation

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var displayName: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? .simplifiedChinese : .english
    }
}

final class LanguageSettings: @unchecked Sendable {
    static let didChangeNotification = Notification.Name("MacVideoPlayer.languageDidChange")
    static let shared = LanguageSettings()

    private enum Key {
        static let language = "appLanguage"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var language: AppLanguage {
        guard let rawValue = defaults.string(forKey: Key.language), let language = AppLanguage(rawValue: rawValue) else {
            return .systemDefault
        }
        return language
    }

    func select(_ language: AppLanguage) {
        guard self.language != language else { return }
        defaults.set(language.rawValue, forKey: Key.language)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}

enum AppStrings {
    private static var isChinese: Bool { LanguageSettings.shared.language == .simplifiedChinese }
    static var usesSimplifiedChinese: Bool { isChinese }
    private static func value(_ english: String, _ chinese: String) -> String { isChinese ? chinese : english }

    static var appName: String { "Mac Video Player" }
    static var settings: String { value("Settings", "设置") }
    static var general: String { value("General", "通用") }
    static var language: String { value("Language", "语言") }
    static var languageDescription: String { value("Choose the language used throughout the player.", "选择播放器显示语言。") }
    static var languageChangesImmediately: String { value("Changes apply immediately.", "切换后立即生效。") }
    static var done: String { value("Done", "完成") }
    static var ok: String { value("OK", "好") }
    static var cancel: String { value("Cancel", "取消") }
    static var save: String { value("Save", "保存") }
    static var restoreDefault: String { value("Restore Default", "恢复默认") }

    static var localLibrary: String { value("Your local video library", "你的本地视频库") }
    static var open: String { value("Open", "打开") }
    static var folder: String { value("Folder", "文件夹") }
    static var playlist: String { value("Playlist", "播放列表") }
    static var tags: String { value("Tags", "标签") }
    static var add: String { value("Add", "添加") }
    static var addTag: String { value("Add tag", "添加标签") }
    static var newTag: String { value("New tag", "新标签") }
    static var filterAll: String { value("Filter: All", "筛选：全部") }
    static var noTags: String { value("No tags", "暂无标签") }
    static var name: String { value("Name", "名称") }
    static var size: String { value("Size", "大小") }
    static var sort: String { value("Sort", "排序") }
    static var currentVideo: String { value("Current video", "正在播放") }

    static var openVideo: String { value("Open Video...", "打开视频…") }
    static var openFolder: String { value("Open Folder...", "打开文件夹…") }
    static var openVideoHeading: String { value("Open a video", "打开一个视频") }
    static var loadingLibrary: String { value("Loading your library", "正在载入视频库") }
    static var readyWhenYouAre: String { value("Ready when you are", "随时可以开始") }
    static var openFirstMessage: String { value("Drop a video here, or open a file or folder to get started.", "将视频拖到这里，或打开文件、文件夹开始播放。") }
    static var playlistEmptyMessage: String { value("Choose a video from your playlist, or open another file.", "从播放列表选择视频，或打开其他文件。") }
    static var localFilesHint: String { value("MP4, MOV, M4V & MKV  ·  Files stay on your Mac", "支持 MP4、MOV、M4V 和 MKV · 文件始终保留在本机") }
    static var tagInputHint: String { value("Type a new tag or choose an existing tag, then press Return", "输入新标签或选择已有标签，然后按 Return") }
    static var addTagTooltip: String { value("Add the tag", "添加标签") }
    static var filterTagsTooltip: String { value("Filter videos by tag", "按标签筛选视频") }
    static var previousVideo: String { value("Previous Video", "上一个视频") }
    static var nextVideo: String { value("Next Video", "下一个视频") }
    static var play: String { value("Play", "播放") }
    static var pause: String { value("Pause", "暂停") }
    static var playOrPause: String { value("Play or Pause", "播放或暂停") }
    static var mute: String { value("Mute", "静音") }
    static var volume: String { value("Volume", "音量") }
    static var adjustVolume: String { value("Scroll to adjust volume", "滚动以调整音量") }
    static var playbackPosition: String { value("Playback position", "播放进度") }
    static var sequentialPlayback: String { value("Sequential Playback", "顺序播放") }
    static var shufflePlayback: String { value("Shuffle Playback", "随机播放") }
    static var playbackOrder: String { value("Playback order", "播放顺序") }
    static var sortByName: String { value("Sort by filename", "按文件名排序") }
    static var sortBySize: String { value("Sort by file size, largest first", "按文件大小排序（从大到小）") }
    static var showPlaylist: String { value("Show playlist", "显示播放列表") }
    static var hidePlaylist: String { value("Hide playlist", "隐藏播放列表") }
    static var screenshotSaved: String { value("Screenshot saved to Pictures", "截图已保存到“图片”") }
    static var removeTag: String { value("Remove tag", "移除标签") }

    static func playlistCount(_ count: Int) -> String {
        isChinese ? "\(count) 个视频" : count == 1 ? "1 video" : "\(count) videos"
    }

    static func playlistDetail(index: Int, fileExtension: String, isCurrent: Bool) -> String {
        let prefix = String(format: "%02d  ·  %@", index + 1, fileExtension)
        return isCurrent ? prefix + (isChinese ? "  ·  正在播放" : "  ·  Current video") : prefix
    }

    static func playlistAccessibilityName(_ filename: String, isCurrent: Bool) -> String {
        isCurrent ? "\(filename), \(currentVideo)" : filename
    }

    static func loadingVideos(from name: String) -> String {
        value("Loading videos from \(name)...", "正在从 \(name) 载入视频…")
    }

    static var loadingVideos: String { value("Loading videos...", "正在载入视频…") }
    static var loadingWindowTitle: String { value("Loading Videos - \(appName)", "正在载入视频 - \(appName)") }
    static func playerWindowTitle(index: Int, count: Int, filename: String) -> String {
        "\(index + 1)/\(count) \(filename) - \(appName)"
    }

    static var editTags: String { value("Edit Tags", "编辑标签") }
    static var editTagsSubtitle: String { value("Keep this video easy to find later.", "为视频添加标签，方便日后查找。") }
    static var localTagsNotice: String { value("Tags are saved locally. The video file is not changed.", "标签仅保存在本地，不会修改视频文件。") }
    static var addTags: String { value("Add tags", "添加标签") }
    static var tagEntryPlaceholder: String { value("Type a tag, or separate several with commas", "输入标签，多个标签请用英文逗号分隔") }
    static var currentTags: String { value("Current tags", "当前标签") }
    static var noTagsYet: String { value("No tags yet. Add one above to organize this video.", "还没有标签。请在上方添加标签来整理视频。") }
    static var suggestions: String { value("Suggestions", "推荐标签") }
    static var saveChanges: String { value("Save changes", "保存更改") }
    static func tagCount(_ count: Int) -> String { isChinese ? "\(count) 个标签" : count == 1 ? "1 tag" : "\(count) tags" }

    static var openVideoPanelTitle: String { value("Open Video", "打开视频") }
    static var openVideoPanelMessage: String { value("Choose an MP4, MOV, M4V, or MKV file.", "选择 MP4、MOV、M4V 或 MKV 视频文件。") }
    static var openFolderPanelTitle: String { value("Open Folder", "打开文件夹") }
    static var openFolderPanelMessage: String { value("Choose a folder containing MP4, MOV, M4V, or MKV files.", "选择包含 MP4、MOV、M4V 或 MKV 视频文件的文件夹。") }
    static var screenshotShortcut: String { value("Screenshot Shortcut", "截图快捷键") }
    static var shortcutHelp: String { value("Click the shortcut, then press a key with at least one modifier.", "点击快捷键区域，然后按下至少带有一个修饰键的组合键。") }
    static var shortcutDescription: String { value("The shortcut works while Mac Video Player is active.", "快捷键仅在 Mac Video Player 激活时有效。") }
    static var pressShortcut: String { value("Press shortcut…", "按下快捷键…") }
    static var shortcutRecorderTooltip: String { value("Click, then press a shortcut with Command, Option, Control, or Shift.", "点击后按下带有 Command、Option、Control 或 Shift 的快捷键。") }
    static var about: String { value("About Mac Video Player", "关于 Mac Video Player") }
    static func buildInfo(version: String, buildNumber: String, created: String) -> String {
        isChinese ? "版本 \(version) (\(buildNumber))\n创建于 \(created)" : "Version \(version) (\(buildNumber))\nCreated \(created)"
    }
    static var deleteVideoTitle: String { value("Delete Video?", "删除视频？") }
    static func deleteVideoMessage(_ filename: String) -> String {
        isChinese ? "将 \(filename) 移到废纸篓？\n\n它将从当前播放列表中移除。" : "Move \(filename) to the Trash?\n\nThis will remove it from the current playlist."
    }
    static var moveToTrash: String { value("Move to Trash", "移到废纸篓") }
    static var cannotOpenVideo: String { value("Cannot Open Video", "无法打开视频") }
    static func cannotOpenVideoMessage(_ filename: String, error: String) -> String {
        isChinese ? "无法打开 \(filename)。\n\n支持的格式：\(SupportedVideoFormat.displayName)。\n\n\(error)" : "\(filename) could not be opened.\n\nSupported formats are \(SupportedVideoFormat.displayName).\n\n\(error)"
    }
    static var cannotAccessTags: String { value("Cannot Access Tags", "无法访问标签") }
    static var cannotCaptureScreenshot: String { value("Cannot Capture Screenshot", "无法截取画面") }
    static var cannotUpdateTags: String { value("Cannot Update Tags", "无法更新标签") }
    static var noActiveVideoForScreenshot: String { value("Open a video before capturing a screenshot.", "请先打开视频，再截取画面。") }
    static func tagStoreReadFailure(path: String, reason: String) -> String {
        isChinese
            ? "无法读取 \(path) 中的标签。原文件已保留，请在编辑标签前修复文件并重新打开应用。\(reason)"
            : "Tags could not be read from \(path). The original file has been preserved. Restore or repair it and reopen the app before editing tags. \(reason)"
    }

    static var menuFile: String { value("File", "文件") }
    static var menuOpen: String { value("Open...", "打开…") }
    static var menuOpenFolder: String { value("Open Folder...", "打开文件夹…") }
    static var menuCloseWindow: String { value("Close Window", "关闭窗口") }
    static var menuPrevious: String { value("Previous Video", "上一个视频") }
    static var menuNext: String { value("Next Video", "下一个视频") }
    static var menuPlayPause: String { value("Play/Pause", "播放/暂停") }
    static var menuCaptureScreenshot: String { value("Capture Screenshot", "截取画面") }
    static var menuToggleShuffle: String { value("Toggle Shuffle", "切换随机播放") }
    static var menuToggleSizeSort: String { value("Toggle Size Sort", "切换大小排序") }
    static var menuEditTags: String { value("Edit Tags...", "编辑标签…") }
    static var menuRevealInFinder: String { value("Reveal in Finder", "在 Finder 中显示") }
    static var menuDeleteCurrent: String { value("Delete Current Video", "删除当前视频") }
    static var screenshotShortcutTooltip: String { value("Capture the current video frame", "截取当前视频画面") }
    static var quit: String { value("Quit Mac Video Player", "退出 Mac Video Player") }
}
