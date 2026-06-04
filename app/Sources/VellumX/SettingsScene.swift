import SwiftUI
import Observation

/// The Settings tabs, used both as the `TabView` selection and as the target
/// other parts of the UI can deep-link to (e.g. the sidebar's "edit tracks"
/// button jumps to `.rules`).
enum SettingsTab: Hashable {
    case general, api, papers, rules, configFile
}

/// Lets non-Settings views request a specific Settings tab before opening the
/// window. Set `selectedTab`, then trigger `@Environment(\.openSettings)`.
@MainActor
@Observable
final class SettingsRouter {
    static let shared = SettingsRouter()
    var selectedTab: SettingsTab = .general
}

/// The standard macOS Settings window (⌘,), organized into tabs:
/// General (storage, menu bar, language), API (translation), Papers
/// (recommendation + OpenAlex params), Rules (tracks, venues, tiers,
/// citation scoring – all DB-persisted), and Config File.
struct SettingsRootView: View {
    @State private var router = SettingsRouter.shared

    var body: some View {
        TabView(selection: $router.selectedTab) {
            GeneralSettingsTab()
                .tabItem { Label(L10n.t(.general), systemImage: "gearshape") }
                .tag(SettingsTab.general)
            APISettingsTab()
                .tabItem { Label(L10n.t(.api), systemImage: "key") }
                .tag(SettingsTab.api)
            PapersSettingsTab()
                .tabItem { Label(L10n.t(.papers), systemImage: "doc.text.magnifyingglass") }
                .tag(SettingsTab.papers)
            RulesSettingsTab()
                .tabItem { Label(L10n.t(.rules), systemImage: "list.bullet.rectangle") }
                .tag(SettingsTab.rules)
            ConfigFileTab()
                .tabItem { Label(L10n.t(.configFile), systemImage: "doc.badge.gearshape") }
                .tag(SettingsTab.configFile)
        }
        .frame(width: 620, height: 560)
    }
}

