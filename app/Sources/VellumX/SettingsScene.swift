import SwiftUI

/// The standard macOS Settings window (⌘,), organized into tabs:
/// General (storage, menu bar, language), API (translation), Papers
/// (recommendation + OpenAlex params), Rules (tracks, venues, tiers,
/// citation scoring – all DB-persisted), and Config File.
struct SettingsRootView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label(L10n.t(.general), systemImage: "gearshape") }
            APISettingsTab()
                .tabItem { Label(L10n.t(.api), systemImage: "key") }
            PapersSettingsTab()
                .tabItem { Label(L10n.t(.papers), systemImage: "doc.text.magnifyingglass") }
            RulesSettingsTab()
                .tabItem { Label(L10n.t(.rules), systemImage: "list.bullet.rectangle") }
            ConfigFileTab()
                .tabItem { Label(L10n.t(.configFile), systemImage: "doc.badge.gearshape") }
        }
        .frame(width: 620, height: 560)
    }
}

