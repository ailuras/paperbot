import SwiftUI

@main
struct VellumXApp: App {
    @StateObject private var store = PaperStore.shared
    
    var recommendedPapers: [Paper] {
        store.papers.filter { $0.status == "recommended" }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 550)
        }

        MenuBarExtra("VellumX", systemImage: "books.vertical") {
            if recommendedPapers.isEmpty {
                Text("No recommendations for today.")
                    .font(.caption)
                Button("Run Recommend Engine") {
                    if let config = ConfigManager.shared.config {
                        let engine = RecommendEngine(config: config)
                        _ = engine.recommend(papers: store.papers)
                    }
                }
            } else {
                Text("Today's Top Picks:")
                    .font(.headline)
                
                ForEach(recommendedPapers) { paper in
                    Menu(paper.title) {
                        Button("Open PDF") {
                            openPdf(for: paper)
                        }
                        Button("Mark Read") {
                            store.setPaperStatus(id: paper.id, status: "read")
                        }
                        Button("Mark Starred") {
                            store.setPaperStatus(id: paper.id, status: "starred")
                        }
                    }
                }
            }
            Divider()
            Button("Quit VellumX") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    private func openPdf(for paper: Paper) {
        if let pdfUrl = paper.pdfUrl, !pdfUrl.isEmpty, let url = URL(string: pdfUrl) {
            NSWorkspace.shared.open(url)
            return
        }
        
        Task {
            let resolver = PdfResolver()
            if let resolvedUrl = await resolver.resolve(paper: paper), let url = URL(string: resolvedUrl) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
