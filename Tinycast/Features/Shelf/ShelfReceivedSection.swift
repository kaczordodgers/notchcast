import AppKit
import SwiftUI

struct ShelfReceivedSection: View {
    @Environment(AppCore.self) private var core
    @State private var entries: [ShelfReceivedEntry] = []
    @State private var busy = false
    var samples: [ShelfReceivedEntry]?
    private var store: ShelfReceivedStore { NotchcastCore.shelf.store }

    var body: some View {
        Group {
            if let status = NotchcastCore.shelf.linkStatus {
                LabeledContent("Status", value: status.shelfPeerAvailable
                    ? String(localized: "Paired") : String(localized: "Not connected"))
            }
            ShelfReceivedRows(entries: samples ?? entries, action: perform)
            if !(samples ?? entries).isEmpty {
                Button("Clear all", role: .destructive) {
                    Task {
                        guard await core.confirm(title: String(localized: "Clear All Received Items?"),
                            message: nil, symbol: "tray", confirmTitle: String(localized: "Clear All")) else { return }
                        await update { try await store.clear() }
                    }
                }
            }
        }
        .disabled(busy)
        .task {
            guard samples == nil else { return }
            while !Task.isCancelled {
                do {
                    let loaded = try await store.entries()
                    try Task.checkCancellation()
                    if !busy { entries = loaded }
                    try await Task.sleep(for: .seconds(2))
                } catch is CancellationError { return } catch {
                    core.showMessage(String(localized: "Could Not Load Shelf"), tone: .danger)
                    return
                }
            }
        }
    }

    private func perform(_ entry: ShelfReceivedEntry, _ action: ShelfReceivedAction) {
        switch action {
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(String(data: entry.item.data, encoding: .utf8) ?? "", forType: .string)
        case .open:
            Task { await update {
                try await QuicklinkLauncher.open(String(data: entry.item.data, encoding: .utf8) ?? "",
                                                 openWithBundleID: nil, inNewWindow: false)
            } }
        case .save:
            Task { await update { _ = try await store.save(entry, to: .downloadsDirectory) } }
        case .remove:
            Task { await update { try await store.remove(entry) } }
        }
    }

    private func update(_ operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await operation()
            let loaded = try await store.entries()
            try Task.checkCancellation()
            entries = loaded
        } catch is CancellationError {} catch {
            core.showMessage(String(localized: "Could Not Update Shelf"), tone: .danger)
        }
    }
}

enum ShelfReceivedAction { case copy, open, save, remove }

struct ShelfReceivedRows: View {
    let entries: [ShelfReceivedEntry]
    let action: (ShelfReceivedEntry, ShelfReceivedAction) -> Void

    var body: some View {
        if entries.isEmpty {
            Text("Items sent from the other Mac appear here.").foregroundStyle(.secondary)
        }
        ForEach(entries) { entry in
            HStack(spacing: Theme.Spacing.lg) {
                SymbolImage(name: symbol(entry.item.kind), size: Theme.Size.settingsRowIcon)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(entry.item.kind == .text
                        ? String(data: entry.item.data, encoding: .utf8) ?? "" : entry.item.name).lineLimit(2)
                    Text(entry.receivedAt, format: .dateTime.month().day().hour().minute())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if entry.item.kind != .file { Button("Copy") { action(entry, .copy) } }
                if entry.item.kind == .link { Button("Open") { action(entry, .open) } }
                if entry.item.kind == .file { Button("Save to downloads") { action(entry, .save) } }
                Button("Remove", role: .destructive) { action(entry, .remove) }
            }
        }
    }

    private func symbol(_ kind: ShelfItem.Kind) -> String {
        switch kind {
        case .text: "text.alignleft"
        case .link: "link"
        case .file: "doc"
        }
    }
}
