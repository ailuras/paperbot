import SwiftUI

@main
struct PaperBotApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 600, minHeight: 400)
        }

        MenuBarExtra("PaperBot", systemImage: "books.vertical") {
            Button("Hello PaperBot") {
                print("Menu item clicked")
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
