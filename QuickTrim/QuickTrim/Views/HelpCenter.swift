//
//  HelpCenter.swift
//  QuickTrim
//
//  QuickTrim's help: a window of topics, and the Help menu's search field.
//
//  Built into the app rather than as an Apple help book, because recent
//  macOS versions show help books in the Tips app instead of a native help
//  window. The pages are plain HTML in the app's Help folder, light and dark.
//  (Same design as Neil's Outline app.)
//

import AppKit
import WebKit

@MainActor
enum HelpCenter {

    struct Topic: Hashable, Sendable {
        let file: String
        let title: String
        let symbol: String
    }

    /// In the order the sidebar lists them.
    nonisolated static let topics: [Topic] = [
        Topic(file: "index", title: "Welcome", symbol: "house"),
        Topic(file: "getting-started", title: "Getting Started", symbol: "play.circle"),
        Topic(file: "trimming", title: "Trimming with Regions", symbol: "scissors"),
        Topic(file: "markers", title: "Moving and Removing Markers", symbol: "arrow.left.and.right"),
        Topic(file: "timeline", title: "Using the Timeline", symbol: "waveform"),
        Topic(file: "crop", title: "Cropping Video", symbol: "crop"),
        Topic(file: "export", title: "Exporting", symbol: "square.and.arrow.up"),
        Topic(file: "shortcuts", title: "Keyboard Shortcuts", symbol: "keyboard"),
        Topic(file: "troubleshooting", title: "Troubleshooting", symbol: "wrench.and.screwdriver"),
    ]

    nonisolated static var directory: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Help"),
              FileManager.default.fileExists(atPath: url.appendingPathComponent("index.html").path)
        else { return nil }
        return url
    }

    nonisolated static func url(for topic: Topic) -> URL? {
        directory?.appendingPathComponent(topic.file + ".html")
    }

    /// Each topic's words, for searching, read once.
    nonisolated static let searchText: [Topic: String] = {
        var result: [Topic: String] = [:]
        for topic in topics {
            guard let url = url(for: topic),
                  let html = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
            result[topic] = topic.title + " " + text
        }
        return result
    }()

    /// Reduces a word to a rough stem so "move" finds "moving", "markers"
    /// finds "marker" and "trimming" finds "trim".
    nonisolated static func stem(_ word: String) -> String {
        var w = word
        if w.count > 5, w.hasSuffix("ing") {
            w.removeLast(3)
            if w.count > 2, let last = w.last, w.dropLast().last == last { w.removeLast() }  // trimm → trim
        } else if w.count > 4, w.hasSuffix("ed") {
            w.removeLast(2)
        } else if w.count > 3, w.hasSuffix("s") {
            w.removeLast()
        }
        if w.count > 3, w.hasSuffix("e") { w.removeLast() }  // move → mov, so it matches "moving"
        return w
    }

    /// Topics containing every word of `query` (by stem), best matches first:
    /// title matches, then how often the words appear. The Welcome page
    /// mentions every topic, so it ranks below the specific ones.
    nonisolated static func search(_ query: String) -> [Topic] {
        let words = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { stem(String($0)) }
        guard !words.isEmpty else { return topics }

        func score(_ topic: Topic) -> Int? {
            let text = (searchText[topic] ?? topic.title).lowercased()
            guard words.allSatisfy({ text.contains($0) }) else { return nil }
            let title = topic.title.lowercased()
            let titleHits = words.filter { title.contains($0) }.count
            let occurrences = words.reduce(0) { $0 + text.components(separatedBy: $1).count - 1 }
            var total = titleHits * 100 + min(occurrences, 50)
            if titleHits == words.count { total += 1000 }
            if topic.file == "index" { total -= 500 }
            return total
        }

        return topics
            .compactMap { topic in score(topic).map { (topic, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    // MARK: Showing

    private static var controller: HelpWindowController?

    static func show(_ file: String = "index") {
        if controller == nil { controller = HelpWindowController() }
        controller?.showWindow(nil)
        controller?.window?.makeKeyAndOrderFront(nil)
        controller?.open(topics.first { $0.file == file } ?? topics[0])
        NSApp.activate()
    }

    static func showSearch(_ query: String) {
        controller?.showResults(for: query)
    }
}

/// The Help window: topics on the left, the page on the right, search in the toolbar.
@MainActor
final class HelpWindowController: NSWindowController, NSToolbarDelegate, NSSearchFieldDelegate {

    private let split = NSSplitViewController()
    private let sidebar = HelpSidebar()
    private let page = HelpPage()
    private static let searchItem = NSToolbarItem.Identifier("HelpSearch")

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "QuickTrim Help"
        window.minSize = NSSize(width: 640, height: 420)
        window.toolbarStyle = .unified
        window.setFrameAutosaveName("QuickTrimHelp")
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 210
        sidebarItem.maximumThickness = 300
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(NSSplitViewItem(viewController: page))
        window.contentViewController = split
        if window.frame.width < 700 {
            window.setContentSize(NSSize(width: 900, height: 660))
            window.center()
        }

        let toolbar = NSToolbar(identifier: "QuickTrimHelpToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        sidebar.onSelect = { [weak self] topic in self?.page.load(topic) }
        page.onNavigate = { [weak self] file in self?.sidebar.highlight(file) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func open(_ topic: HelpCenter.Topic) {
        sidebar.highlight(topic.file)
        page.load(topic)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, Self.searchItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard identifier == Self.searchItem else { return nil }
        let item = NSSearchToolbarItem(itemIdentifier: identifier)
        item.searchField.placeholderString = "Search Help"
        item.searchField.delegate = self
        item.searchField.sendsSearchStringImmediately = true
        item.searchField.target = self
        item.searchField.action = #selector(search(_:))
        return item
    }

    @objc private func search(_ sender: NSSearchField) {
        let results = HelpCenter.search(sender.stringValue)
        sidebar.show(results)
        if let first = results.first, !sender.stringValue.isEmpty {
            page.load(first, highlighting: sender.stringValue)
        }
    }

    /// Show the help with these topics listed, as the Help menu's "Show All Help Topics" asks.
    func showResults(for query: String) {
        let item = window?.toolbar?.items.first { $0.itemIdentifier == Self.searchItem }
        if let field = (item as? NSSearchToolbarItem)?.searchField {
            field.stringValue = query
            search(field)
        }
    }
}

@MainActor
private final class HelpSidebar: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private var shown = HelpCenter.topics
    var onSelect: ((HelpCenter.Topic) -> Void)?
    private var isHighlighting = false

    override func loadView() {
        table.addTableColumn(NSTableColumn(identifier: .init("topic")))
        table.headerView = nil
        table.style = .sourceList
        table.rowHeight = 28
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        view = scroll
    }

    func show(_ topics: [HelpCenter.Topic]) {
        shown = topics
        table.reloadData()
    }

    func highlight(_ file: String) {
        if !shown.contains(where: { $0.file == file }) { show(HelpCenter.topics) }
        guard let row = shown.firstIndex(where: { $0.file == file }) else { return }
        isHighlighting = true
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
        isHighlighting = false
    }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let topic = shown[row]
        let cell = NSTableCellView()
        let image = NSImageView(image: NSImage(systemSymbolName: topic.symbol, accessibilityDescription: nil) ?? NSImage())
        let label = NSTextField(labelWithString: topic.title)
        label.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [image, label])
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 18),
        ])
        cell.textField = label
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isHighlighting, table.selectedRow >= 0 else { return }
        onSelect?(shown[table.selectedRow])
    }
}

@MainActor
private final class HelpPage: NSViewController, WKNavigationDelegate {
    private let web = WKWebView()
    var onNavigate: ((String) -> Void)?
    private var pendingHighlight: String?

    override func loadView() {
        web.navigationDelegate = self
        view = web
    }

    func load(_ topic: HelpCenter.Topic, highlighting query: String? = nil) {
        guard let url = HelpCenter.url(for: topic), let directory = HelpCenter.directory else { return }
        pendingHighlight = query
        web.loadFileURL(url, allowingReadAccessTo: directory)
    }

    // Links between topics stay here; anything else opens in its own app.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
        if url.isFileURL { return decisionHandler(.allow) }
        NSWorkspace.shared.open(url)
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let file = webView.url?.deletingPathExtension().lastPathComponent { onNavigate?(file) }
        if let query = pendingHighlight, !query.isEmpty {
            pendingHighlight = nil
            let configuration = WKFindConfiguration()
            configuration.caseSensitive = false
            webView.find(query, configuration: configuration) { _ in }
        }
    }
}

/// Lets the Help menu's search field find QuickTrim's help topics, listed
/// beneath the menu commands macOS finds itself, as in every Mac app.
///
/// AppKit may ask from a background thread, so searching touches nothing but
/// the topics' text (read once); only showing a topic goes to the main thread.
final class HelpMenuSearch: NSObject, NSUserInterfaceItemSearching, @unchecked Sendable {
    static let shared = HelpMenuSearch()

    func searchForItems(withSearch searchString: String, resultLimit: Int,
                        matchedItemHandler handleMatchedItems: @escaping ([Any]) -> Void) {
        handleMatchedItems(Array(HelpCenter.search(searchString).prefix(resultLimit)).map(\.file))
    }

    func localizedTitles(forItem item: Any) -> [String] {
        guard let file = item as? String,
              let topic = HelpCenter.topics.first(where: { $0.file == file }) else { return [] }
        return [topic.title]
    }

    func performAction(forItem item: Any) {
        guard let file = item as? String else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { HelpCenter.show(file) } }
    }

    func showAllHelpTopics(forSearch searchString: String) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                HelpCenter.show()
                // A moment for the window's toolbar to exist.
                DispatchQueue.main.async { MainActor.assumeIsolated { HelpCenter.showSearch(searchString) } }
            }
        }
    }
}
