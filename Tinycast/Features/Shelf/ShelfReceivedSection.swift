import AppKit
import SwiftUI

struct ShelfReceivedSection: View {
    @Environment(AppCore.self) private var core
    @State private var entries: [ShelfReceivedEntry] = []
    @State private var busy = false
    private var store: ShelfReceivedStore { ShelfModule.shared.store }

    var body: some View {
        Group {
            if let status = ShelfModule.shared.linkStatus {
                LabeledContent("Status", value: status.shelfPeerAvailable
                    ? String(localized: "Connected", table: "Notchcast") : String(localized: "Not connected", table: "Notchcast"))
            }
            ShelfReceivedRows(entries: entries, action: perform)
            Group {
                Button(String(localized: "Clear All", table: "Notchcast"), role: .destructive) {
                    Task {
                        guard await core.confirm(title: String(localized: "Clear all received items?", table: "Notchcast"),
                            message: String(localized: "This can't be undone."), symbol: "tray",
                            confirmTitle: String(localized: "Clear All", table: "Notchcast")) else { return }
                        await update { try await store.clear() }
                    }
                }
            }
        }
        .disabled(busy)
        .task {
            var lastDate: Date?
            var loadedOnce = false
            var reportedError = false
            while !Task.isCancelled {
                do {
                    let date = try await store.modificationDate()
                    if !busy && (!loadedOnce || date != lastDate) {
                        let loaded = try await store.entries()
                        try Task.checkCancellation()
                        if !busy {
                            entries = loaded
                            lastDate = date
                            loadedOnce = true
                        }
                    }
                    reportedError = false
                } catch is CancellationError { return } catch {
                    if !reportedError {
                        core.showMessage(String(localized: "Could Not Load Shelf", table: "Notchcast"), tone: .danger)
                        reportedError = true
                    }
                }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
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
            Task { await update {
                _ = try await store.save(entry, to: .downloadsDirectory)
                core.showMessage(String(localized: "Saved to Downloads", table: "Notchcast"))
            } }
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
            core.showMessage(String(localized: "Could Not Update Shelf", table: "Notchcast"), tone: .danger)
        }
    }
}

enum ShelfReceivedAction { case copy, open, save, remove }

struct ShelfReceivedRows: View {
    let entries: [ShelfReceivedEntry]
    let action: (ShelfReceivedEntry, ShelfReceivedAction) -> Void

    var body: some View {
        if entries.isEmpty {
            Text("Items sent from the other Mac appear here.", tableName: "Notchcast").foregroundStyle(.secondary)
        }
        ForEach(entries) { entry in
            HStack(spacing: Theme.Spacing.lg) {
                SymbolImage(name: symbol(entry.item.kind), size: Theme.Size.settingsRowIcon)
                    .foregroundStyle(.secondary)
                    .frame(width: Theme.Size.settingsRowIcon)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(entry.item.kind == .text
                        ? String(data: entry.item.data, encoding: .utf8) ?? "" : entry.item.name).lineLimit(2)
                    Text(entry.receivedAt, format: .dateTime.month().day().hour().minute())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if entry.item.kind != .file { Button("Copy") { action(entry, .copy) } }
                if entry.item.kind == .link { Button("Open") { action(entry, .open) } }
                if entry.item.kind == .file { Button(String(localized: "Save to Downloads", table: "Notchcast")) { action(entry, .save) } }
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
