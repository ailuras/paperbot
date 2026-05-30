import SwiftUI
import AppKit
import Combine

/// Owns the menu bar status item.
///
/// We deliberately do NOT use SwiftUI's `MenuBarExtra` with a custom `Image`
/// label: that path repeatedly re-resolves the icon and pins a CPU core at
/// ~99% (observed and fixed the same way in the sibling FacetX app). Instead we
/// drive an AppKit `NSStatusItem` directly and pop the SwiftUI content in an
/// `NSPopover`, which is stable.
@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?

    private let store: PaperStore
    private let settings: AppSettings

    init(store: PaperStore, settings: AppSettings) {
        self.store = store
        self.settings = settings

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(closePopover: { [weak self] in self?.popover.performClose(nil) })
                .environmentObject(store)
                .environmentObject(settings)
        )

        // Show/hide the status item in step with the setting (default on).
        apply(enabled: settings.menuBarEnabled)
        cancellable = settings.$menuBarEnabled.sink { [weak self] enabled in
            self?.apply(enabled: enabled)
        }
    }

    private func apply(enabled: Bool) {
        if enabled {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                button.image = Self.icon
                button.image?.isTemplate = true   // adapts to light/dark menu bar
                button.action = #selector(togglePopover)
                button.target = self
            }
            statusItem = item
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
            }
            statusItem = nil
            popover.performClose(nil)
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Custom menu bar icon from the bundled template PNG, falling back to an
    /// SF Symbol if the resource is missing.
    static let icon: NSImage = {
        if let img = NSImage(named: "MenuBarIcon") {
            img.isTemplate = true
            img.size = NSSize(width: 18, height: 18)
            return img
        }
        let sym = NSImage(systemSymbolName: "books.vertical", accessibilityDescription: "VellumX")
        sym?.isTemplate = true
        return sym ?? NSImage()
    }()
}

/// The popover content: today's recommendations + quick actions. Plain SwiftUI,
/// hosted in an NSPopover (not MenuBarExtra).
struct MenuBarContentView: View {
    @EnvironmentObject private var store: PaperStore
    let closePopover: () -> Void

    private var recommendedPapers: [Paper] {
        store.papers.filter { $0.status == "recommended" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if recommendedPapers.isEmpty {
                Text(L10n.t(.noRecommendations))
                    .font(.caption)
                Button(L10n.t(.runRecommendEngine)) {
                    let engine = RecommendEngine(config: ConfigManager.shared.effectiveConfig)
                    _ = engine.recommend(papers: store.papers)
                }
            } else {
                Text(L10n.t(.todaysTopPicks))
                    .font(.headline)
                ForEach(recommendedPapers) { paper in
                    Menu(paper.title) {
                        Button(L10n.t(.openPDF)) { openPdf(for: paper) }
                        Button(L10n.t(.markRead)) { store.setPaperStatus(id: paper.id, status: "read") }
                        Button(L10n.t(.markStarred)) { store.setPaperStatus(id: paper.id, status: "starred") }
                    }
                }
            }
            Divider()
            HStack {
                Button {
                    openMainWindow()
                } label: {
                    HStack(spacing: 6) {
                        Image(nsImage: MenuBarController.icon)
                            .resizable()
                            .frame(width: 14, height: 14)
                            .opacity(0.62)
                        Text(L10n.t(.openVellumX))
                    }
                    .foregroundStyle(.primary.opacity(0.82))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label(L10n.t(.quit), systemImage: "power")
                        .foregroundStyle(.primary.opacity(0.68))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 320)
    }

    /// Bring the main window to the front (activating the app), then dismiss
    /// the popover. Uses SwiftUI's openWindow action (captured by the App) so a
    /// closed WindowGroup window is recreated rather than just re-fronted.
    private func openMainWindow() {
        closePopover()
        NSApp.activate(ignoringOtherApps: true)
        MainWindowOpener.shared.open()
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
