import SwiftUI

/// The standard macOS Settings window (⌘,), organized into tabs:
/// General (storage, menu bar, language), API (DeepSeek), Papers
/// (recommendation + OpenAlex + tracks + venue ratings), and Config File.
struct SettingsRootView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label(L10n.t(.general), systemImage: "gearshape") }
            APISettingsTab()
                .tabItem { Label(L10n.t(.api), systemImage: "key") }
            PapersSettingsTab()
                .tabItem { Label(L10n.t(.papers), systemImage: "doc.text.magnifyingglass") }
            ConfigFileTab()
                .tabItem { Label(L10n.t(.configFile), systemImage: "doc.badge.gearshape") }
        }
        .frame(width: 580, height: 520)
    }
}
