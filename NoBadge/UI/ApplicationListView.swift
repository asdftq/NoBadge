import AppKit
import SwiftUI

/// Reuses native rows so scrolling does not rebuild an observed SwiftUI tree per app.
struct ApplicationListView: NSViewRepresentable {
  let apps: [AppEntry]
  let keptIDs: Set<String>
  let changed: (String, Bool) -> Void
  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeNSView(context: Context) -> NSScrollView {
    let table = ApplicationTableView()
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
    column.resizingMask = .autoresizingMask
    table.addTableColumn(column)
    table.headerView = nil
    table.rowHeight = 38
    table.intercellSpacing = NSSize(width: 0, height: 0)
    table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    table.selectionHighlightStyle = .regular
    table.allowsMultipleSelection = false
    table.backgroundColor = .clear
    table.delegate = context.coordinator
    table.dataSource = context.coordinator
    table.toggleSelection = { [weak coordinator = context.coordinator] row in
      coordinator?.toggle(row: row)
    }
    table.setAccessibilityLabel(L("Apps"))
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.drawsBackground = false
    scroll.documentView = table
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let table = scroll.documentView as? NSTableView else { return }
    let coordinator = context.coordinator
    coordinator.changed = changed
    guard coordinator.apps != apps || coordinator.keptIDs != keptIDs else { return }
    if coordinator.apps == apps {
      coordinator.keptIDs = keptIDs
      // Do not destroy a focused checkbox after Space or a VoiceOver press.
      table.enumerateAvailableRowViews { rowView, row in
        guard apps.indices.contains(row), let cell = rowView.view(atColumn: 0) as? AppCell else {
          return
        }
        cell.checkbox.state = keptIDs.contains(apps[row].id) ? .on : .off
      }
      return
    }
    let selectedID = coordinator.apps.indices.contains(table.selectedRow)
      ? coordinator.apps[table.selectedRow].id : nil
    coordinator.apps = apps
    coordinator.keptIDs = keptIDs
    table.reloadData()
    if let selectedID, let row = apps.firstIndex(where: { $0.id == selectedID }) {
      table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }
  }
  @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var apps: [AppEntry] = []
    var keptIDs: Set<String> = []
    var changed: ((String, Bool) -> Void)?
    func numberOfRows(in tableView: NSTableView) -> Int { apps.count }
    func toggle(row: Int) {
      guard apps.indices.contains(row) else { return }
      let app = apps[row]
      changed?(app.id, !keptIDs.contains(app.id))
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
      -> NSView?
    {
      let identifier = NSUserInterfaceItemIdentifier("app-row")
      let cell =
        tableView.makeView(withIdentifier: identifier, owner: self) as? AppCell ?? AppCell()
      cell.identifier = identifier
      let app = apps[row]
      cell.name.stringValue = app.name
      cell.checkbox.state = keptIDs.contains(app.id) ? .on : .off
      cell.checkbox.setAccessibilityLabel(app.name)
      cell.checkbox.tag = row
      cell.checkbox.target = self
      cell.checkbox.action = #selector(toggle(_:))
      cell.loadIcon(app.url)
      return cell
    }
    @objc private func toggle(_ sender: NSButton) {
      guard apps.indices.contains(sender.tag) else { return }
      changed?(apps[sender.tag].id, sender.state == .on)
    }
  }
}

/// Retain AppKit's arrow-key navigation and expose the selected checkbox to Space/Return.
@MainActor private final class ApplicationTableView: NSTableView {
  var toggleSelection: ((Int) -> Void)?
  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    if accepted, selectedRow < 0, numberOfRows > 0 {
      selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
      scrollRowToVisible(0)
    }
    return accepted
  }
  override func keyDown(with event: NSEvent) {
    if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
      event.charactersIgnoringModifiers == " " || event.charactersIgnoringModifiers == "\r",
      selectedRow >= 0
    {
      toggleSelection?(selectedRow)
      return
    }
    super.keyDown(with: event)
  }
}

@MainActor private final class AppCell: NSTableCellView {
  let name = NSTextField(labelWithString: "")
  let icon = NSImageView()
  let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
  private var iconURL: URL?
  private var iconTask: Task<Void, Never>?
  init() {
    super.init(frame: .zero)
    name.lineBreakMode = .byTruncatingTail
    name.font = .systemFont(ofSize: NSFont.systemFontSize)
    name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    icon.imageScaling = .scaleProportionallyUpOrDown
    icon.setAccessibilityElement(false)
    for view in [icon, name, checkbox] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
      view.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
    }
    NSLayoutConstraint.activate([
      icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      icon.widthAnchor.constraint(equalToConstant: 24),
      icon.heightAnchor.constraint(equalToConstant: 24),
      name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
      name.trailingAnchor.constraint(lessThanOrEqualTo: checkbox.leadingAnchor, constant: -10),
      checkbox.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
    ])
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func loadIcon(_ url: URL) {
    guard iconURL != url else { return }
    iconTask?.cancel()
    iconURL = url
    icon.image = NSImage(systemSymbolName: "app", accessibilityDescription: nil)
    iconTask = Task { [weak self] in
      let data = await ApplicationIcons.shared.data(for: url)
      guard !Task.isCancelled, let self, self.iconURL == url else { return }
      self.icon.image = data.flatMap(NSImage.init(data:))
    }
  }
}
