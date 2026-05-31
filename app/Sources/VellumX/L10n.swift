import Foundation

/// Lightweight in-app localization. Strings are authored as (English, 中文)
/// pairs and selected by `AppSettings.language` (default English). This keeps
/// the UI consistent instead of mixing languages, while letting the user switch.
enum L10n {
    enum Key {
        // Tabs
        case general, api, papers, configFile
        // General
        case storageLocation, currentLocation, change, restoreDefault, storageHint
        case interface, showInMenuBar, language, menuBarHint
        case changeStorageTitle, migrateDB, switchOnly, cancel, migratePrompt
        case choose, storageUpdated
        // API
        case deepseekSection, enableTranslation, apiKeyHint, model, targetLanguage
        case testConnection, testingConnection, connectionOK, connectionFailed
        case refreshModels, loadingModels, modelsLoaded, modelsUnavailable
        case apiConnection, modelSelection, apiKey, baseURL
        // Papers
        case dailyRecommendations, dailyCount, qualitySlots, highScoreThreshold, recentWindow
        case openAlexFetch, contactEmail, perPage, fetchDays, maxResults, topicFilter
        case interestsTracks, venueRatings
        case noTracks, name, searchQuery, keywordsCSV, newTrack, addTrack
        case noVenues, abbr, matchPhrase, tier, addVenue, field
        case applyVenueChanges, venueChangesApplied, venueChangesHint
        // Config file
        case notSet, advancedConfigFile, path, open, revealInFinder, clear, advancedConfigHint
        // Menu bar
        case noRecommendations, runRecommendEngine, todaysTopPicks
        case openPDF, markRead, markStarred, openVellumX, quit
    }

    @MainActor
    static func t(_ key: Key) -> String {
        AppSettings.shared.language == "zh" ? pair(key).1 : pair(key).0
    }

    private static func pair(_ key: Key) -> (String, String) {
        switch key {
        case .general:            return ("General", "通用")
        case .api:                return ("API", "API")
        case .papers:             return ("Papers", "论文")
        case .configFile:         return ("Config File", "配置文件")

        case .storageLocation:    return ("Storage Location", "存储位置")
        case .currentLocation:    return ("Current location", "当前位置")
        case .change:             return ("Change…", "更改…")
        case .restoreDefault:     return ("Restore Default", "恢复默认")
        case .storageHint:        return ("Folder holding vellumx.db. Put it in iCloud Drive to sync.",
                                          "数据库 vellumx.db 所在的文件夹。可放到 iCloud Drive 内以便同步。")
        case .interface:          return ("Interface", "界面")
        case .showInMenuBar:      return ("Show in Menu Bar", "在菜单栏显示")
        case .language:           return ("Language", "语言")
        case .menuBarHint:        return ("Hiding it only removes the status-bar icon; the main window is unaffected.",
                                          "关闭后仅隐藏右上角状态栏图标，主窗口不受影响。")
        case .changeStorageTitle: return ("Change Storage Location", "更改存储位置")
        case .migrateDB:          return ("Migrate existing database", "迁移现有数据库")
        case .switchOnly:         return ("Switch only, don't migrate", "仅切换，不迁移")
        case .cancel:             return ("Cancel", "取消")
        case .migratePrompt:      return ("Move the current database to the new location? If a vellumx.db already exists there, it will be replaced.",
                                          "是否把当前数据库迁移到新位置？\n如目标位置已存在 vellumx.db，迁移会直接替换它。")
        case .choose:             return ("Choose", "选择")
        case .storageUpdated:     return ("Storage location updated:", "已更新存储位置：")

        case .deepseekSection:    return ("DeepSeek Translation", "DeepSeek 翻译")
        case .enableTranslation:  return ("Enable abstract translation", "启用摘要翻译")
        case .apiKeyHint:         return ("The API key is stored securely in the system Keychain, not in any config file.",
                                          "API Key 安全存储在系统钥匙串中，不写入配置文件。")
        case .model:              return ("Model", "模型")
        case .targetLanguage:     return ("Target language", "目标语言")
        case .testConnection:     return ("Test Connection", "测试连接")
        case .testingConnection:  return ("Testing connection…", "正在测试连接…")
        case .connectionOK:       return ("Connection OK", "连接正常")
        case .connectionFailed:   return ("Connection failed", "连接失败")
        case .refreshModels:      return ("Refresh Models", "刷新模型")
        case .loadingModels:      return ("Loading models…", "正在加载模型…")
        case .modelsLoaded:       return ("Models loaded", "模型已加载")
        case .modelsUnavailable:  return ("Configure API key, then refresh models.", "配置 API Key 后刷新模型。")
        case .apiConnection:      return ("Connection", "连接")
        case .modelSelection:     return ("Model Selection", "模型选择")
        case .apiKey:             return ("API Key", "API Key")
        case .baseURL:            return ("Base URL", "Base URL")

        case .dailyRecommendations: return ("Daily Recommendations", "每日推荐")
        case .dailyCount:         return ("Daily count", "每日推荐数")
        case .qualitySlots:       return ("Quality-priority slots", "质量优先槽位")
        case .highScoreThreshold: return ("High-score threshold", "高分阈值")
        case .recentWindow:       return ("Recent window (days)", "新近窗口（天）")
        case .openAlexFetch:      return ("OpenAlex Fetch", "OpenAlex 抓取")
        case .contactEmail:       return ("Contact email", "联系邮箱")
        case .perPage:            return ("Per page", "每页条数")
        case .fetchDays:          return ("Fetch days", "抓取天数")
        case .maxResults:         return ("Max results", "最大结果数")
        case .topicFilter:        return ("Topic filter", "主题过滤")
        case .interestsTracks:    return ("Interests (Tracks)", "研究方向 (Tracks)")
        case .venueRatings:       return ("Venue Ratings", "会议评级")
        case .noTracks:           return ("No tracks yet. Add one below.", "暂无方向。点击下方按钮添加。")
        case .name:               return ("Name", "名称")
        case .searchQuery:        return ("Search query", "搜索词 (query)")
        case .keywordsCSV:        return ("Keywords (comma-separated)", "关键词（逗号分隔）")
        case .newTrack:           return ("New Track", "新方向")
        case .addTrack:           return ("Add Track", "添加方向")
        case .noVenues:           return ("No venues yet. Add one below.", "暂无会议。点击下方按钮添加。")
        case .abbr:               return ("Abbr.", "缩写")
        case .matchPhrase:        return ("Match phrase", "匹配词")
        case .tier:               return ("Tier", "评级")
        case .addVenue:           return ("Add Venue", "添加会议")
        case .field:              return ("Field", "领域")
        case .applyVenueChanges:  return ("Apply Venue Changes", "应用会议变更")
        case .venueChangesApplied:return ("Updated paper metadata:", "已更新论文元数据：")
        case .venueChangesHint:   return ("Recomputes cached venue abbreviation, tier, and score for the current library.",
                                          "重新计算当前论文库缓存的会议缩写、评级和分数。")

        case .notSet:             return ("(not set)", "（未设置）")
        case .advancedConfigFile: return ("Advanced Config File", "高级配置文件")
        case .path:               return ("Path", "路径")
        case .open:               return ("Open", "打开")
        case .revealInFinder:     return ("Reveal in Finder", "在访达中显示")
        case .clear:              return ("Clear", "清除")
        case .advancedConfigHint: return ("Optional. A JSON file overriding the built-in scoring/filters (e.g. a full venue tier table). Configure day-to-day settings in the other tabs — visual settings take precedence.",
                                          "可选。一个 JSON 文件，用于覆盖内置的评分规则与过滤器。日常设置请在其他标签页中配置——可视化设置优先级更高。")

        case .noRecommendations:  return ("No recommendations for today.", "今天还没有推荐。")
        case .runRecommendEngine: return ("Run Recommend Engine", "运行推荐引擎")
        case .todaysTopPicks:     return ("Today's Top Picks:", "今日精选：")
        case .openPDF:            return ("Open PDF", "打开 PDF")
        case .markRead:           return ("Mark Read", "标记已读")
        case .markStarred:        return ("Mark Starred", "标记收藏")
        case .openVellumX:        return ("Open VellumX", "打开 VellumX")
        case .quit:               return ("Quit", "退出")
        }
    }
}
