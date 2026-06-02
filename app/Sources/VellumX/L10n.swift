import Foundation

/// Lightweight in-app localization. Strings are authored as (English, 中文)
/// pairs and selected by `AppSettings.language` (default English). This keeps
/// the UI consistent instead of mixing languages, while letting the user switch.
enum L10n {
    enum Key {
        // Tabs
        case general, api, papers, rules, configFile
        // General
        case storageLocation, currentLocation, change, restoreDefault, storageHint
        case interface, showInMenuBar, language, menuBarHint
        case changeStorageTitle, migrateDB, switchOnly, cancel, migratePrompt
        case choose, storageUpdated
        // API
        case translationSection, enableTranslation, apiKeyHint, model, targetLanguage, provider
        case testConnection, testingConnection, connectionOK, connectionFailed, connectionUntested
        case refreshModels, loadingModels, modelsLoaded, modelsUnavailable
        case apiConnection, modelSelection, apiKey, baseURL
        // Papers
        case dailyRecommendations, dailyCount, qualitySlots, highScoreThreshold, recentWindow
        case openAlexFetch, contactEmail, perPage, fetchDays, maxResults, topicFilter
        // Rules
        case interestsTracks, venueRatings
        case noTracks, name, searchQuery, keywordsCSV, newTrack, addTrack
        case noVenues, abbr, matchPhrase, tier, addVenue, field, newField
        case applyVenueChanges, venueChangesApplied, venueChangesHint
        case tierSettings, tierRank, tierPointsValue, addTier
        case citationScoring, citationScoringHint
        case breakpointUpTo, pointsPerCitation, maxCitationPointsLabel
        case addBreakpoint, noBreakpoints, noCap
        case importRules, exportRules, usePreset
        case usePresetTitle, usePresetMessage, confirm
        case importSuccess, importFailed
        // Settings file
        case path, open, revealInFinder, settingsFile, settingsFileHint
        // Menu bar
        case noRecommendations, runRecommendEngine, todaysTopPicks
        case openPDF, markRead, markStarred, markSkip, cancelRecommendation, openInVellumX, openVellumX, quit
        // Citation export
        case cite, copyBibtex, copyRIS, saveBib, copiedBibtex, copiedRIS, savedBib
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
        case .rules:              return ("Rules", "学术规则")
        case .configFile:         return ("Settings File", "设置文件")

        case .storageLocation:    return ("Storage Location", "存储位置")
        case .currentLocation:    return ("Current location", "当前位置")
        case .change:             return ("Change…", "更改…")
        case .restoreDefault:     return ("Restore Default", "恢复默认")
        case .storageHint:        return ("Folder holding vellumx.db. Defaults to Application Support; pick another folder to relocate it.",
                                          "数据库 vellumx.db 所在的文件夹。默认位于 Application Support，可另选文件夹迁移。")
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

        case .translationSection: return ("Translation", "翻译")
        case .enableTranslation:  return ("Enable abstract translation", "启用摘要翻译")
        case .apiKeyHint:         return ("The API key is saved in settings.json (~/Library/Application Support/VellumX/).",
                                          "API Key 保存在 settings.json（~/Library/Application Support/VellumX/）中。")
        case .model:              return ("Model", "模型")
        case .targetLanguage:     return ("Target language", "目标语言")
        case .provider:           return ("Provider", "提供商")
        case .testConnection:     return ("Test Connection", "测试连接")
        case .testingConnection:  return ("Testing connection…", "正在测试连接…")
        case .connectionOK:       return ("Connection OK", "连接正常")
        case .connectionFailed:   return ("Connection failed", "连接失败")
        case .connectionUntested: return ("Untested", "未测试")
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
        case .newField:           return ("New Field…", "新建领域…")
        case .applyVenueChanges:  return ("Apply Venue Changes", "应用会议变更")
        case .venueChangesApplied:return ("Updated paper metadata:", "已更新论文元数据：")
        case .venueChangesHint:   return ("Recomputes cached venue abbreviation, tier, and score for the current library.",
                                          "重新计算当前论文库缓存的会议缩写、评级和分数。")

        case .tierSettings:       return ("Tier Settings", "等级设置")
        case .tierRank:           return ("Rank", "等级")
        case .tierPointsValue:    return ("Points", "积分")
        case .addTier:            return ("Add Tier", "添加等级")
        case .citationScoring:    return ("Citation Scoring", "引用评分")
        case .citationScoringHint:return ("Configure how citations contribute to paper scores. Leave empty to disable citation scoring.",
                                          "配置引用数如何影响论文分数。留空则不启用引用评分。")
        case .breakpointUpTo:     return ("Up to", "上限")
        case .pointsPerCitation:  return ("Pts/cite", "分/引用")
        case .maxCitationPointsLabel: return ("Max citation points", "引用得分上限")
        case .addBreakpoint:      return ("Add Segment", "添加区间")
        case .noBreakpoints:      return ("Citation scoring disabled. Add a segment to enable.", "引用评分未启用。添加区间以启用。")
        case .noCap:              return ("No cap", "不封顶")
        case .importRules:        return ("Import…", "导入…")
        case .exportRules:        return ("Export…", "导出…")
        case .usePreset:          return ("Use Preset", "使用预设")
        case .usePresetTitle:     return ("Reset to Preset?", "恢复预设配置？")
        case .usePresetMessage:   return ("This will replace all current rules (tracks, venues, tiers, scoring) with the built-in defaults. This cannot be undone.",
                                          "此操作将用内置默认值替换当前的所有规则（研究方向、会议评级、等级、评分）。此操作不可撤销。")
        case .confirm:            return ("Confirm", "确认")
        case .importSuccess:      return ("Rules imported successfully.", "规则导入成功。")
        case .importFailed:       return ("Import failed:", "导入失败：")

        case .path:               return ("Path", "路径")
        case .open:               return ("Open", "打开")
        case .revealInFinder:     return ("Reveal in Finder", "在访达中显示")
        case .settingsFile:       return ("Settings File", "设置文件")
        case .settingsFileHint:   return ("All preferences are stored in this JSON file. It is generated on first launch and can be edited by hand; relaunch VellumX to apply changes.",
                                          "所有偏好设置都存储在这个 JSON 文件里。它在首次启动时生成，可手动编辑；改完后重启 VellumX 生效。")

        case .noRecommendations:  return ("No recommendations for today.", "今天还没有推荐。")
        case .runRecommendEngine: return ("Run Recommend Engine", "运行推荐引擎")
        case .todaysTopPicks:     return ("Today's Top Picks:", "今日精选：")
        case .openPDF:            return ("Open PDF", "打开 PDF")
        case .markRead:           return ("Mark Read", "标记已读")
        case .markStarred:        return ("Mark Starred", "标记收藏")
        case .markSkip:           return ("Skip", "跳过")
        case .cancelRecommendation:return ("Cancel Recommendation", "取消推荐")
        case .openInVellumX:      return ("Open in VellumX", "在 VellumX 中打开")
        case .openVellumX:        return ("Open VellumX", "打开 VellumX")
        case .quit:               return ("Quit", "退出")

        case .cite:               return ("Cite", "引用")
        case .copyBibtex:         return ("Copy BibTeX", "复制 BibTeX")
        case .copyRIS:            return ("Copy RIS", "复制 RIS")
        case .saveBib:            return ("Save .bib…", "保存 .bib…")
        case .copiedBibtex:       return ("BibTeX copied to clipboard", "BibTeX 已复制到剪贴板")
        case .copiedRIS:          return ("RIS copied to clipboard", "RIS 已复制到剪贴板")
        case .savedBib:           return ("Saved BibTeX file", "已保存 BibTeX 文件")
        }
    }
}
