import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WeatherCitySettingRow: View {
    let store: DayWeatherStore

    var body: some View {
        DayCityField(store: store)
        .settingsEnabled(NotchcastPreferences.shared.isOn(.island))
    }
}

struct MarketSymbolsSettingRow: View {
    let markets: DayMarketsStore
    @State private var symbols = ""

    var body: some View {
        TextField(text: $symbols) {
            SettingsRowTitle(.notchcastDay, "Symbols")
            Text("Yahoo Finance symbols, separated by commas.", tableName: "Notchcast")
        }
        .textFieldStyle(.roundedBorder)
        .onAppear { symbols = markets.symbols.joined(separator: ", ") }
        .onSubmit(saveSymbols)
        .onDisappear(perform: saveSymbols)
        .settingsEnabled(NotchcastPreferences.shared.isOn(.island))
    }
    private func saveSymbols() {
        let updated = symbols.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        if updated != markets.symbols { markets.setSymbols(updated) }
    }
}

struct TimerSoundSettingRow: View {
    @Bindable var store: LiveTimerStore

    var body: some View {
        Toggle(isOn: $store.playSoundWhenTimeIsUp) {
            SettingsRowTitle(.notchcastTimers, LocalizedStringResource("Play sound when time is up", table: "Notchcast"))
        }
        .settingsEnabled(NotchcastPreferences.shared.isOn(.island))
    }
}

struct TimerDefaultDurationSettingRow: View {
    @Bindable var store: LiveTimerStore

    var body: some View {
        Picker(selection: $store.defaultDuration) {
            ForEach(LiveTimerStore.defaultDurations, id: \.self) { duration in
                Text(Duration.seconds(duration).formatted(.units(allowed: [.minutes], width: .wide)))
                    .tag(duration)
            }
        } label: {
            SettingsRowTitle(.notchcastTimers, LocalizedStringResource("Default timer", table: "Notchcast"))
        }
        .settingsEnabled(NotchcastPreferences.shared.isOn(.island))
    }
}

struct TaskCountSettingRow: View {

    var body: some View {
        if let module = NotchcastCore.services?.tasks, let store = module.store {
            Text("Tasks: \(store.state.tasks.count)", tableName: "Notchcast").foregroundStyle(.secondary)
        }
    }
}

struct TodoistImportSettingRow: View {
    @State private var selectedFile: URL?
    @State private var result: String?
    var body: some View {
        Group {
            if let module = NotchcastCore.services?.tasks {
                Button(String(localized: "Import Todoist JSON export…", table: "Notchcast"), action: selectFile)
                    .help(String(localized: "Accepts a JSON object with Todoist tasks, projects, sections and labels arrays.", table: "Notchcast"))
                    .disabled(module.store == nil || selectedFile != nil)
                    .settingsAnchor(.notchcastTasks)
                if let result { Text(result).foregroundStyle(.secondary) }
            }
        }
        .task(id: selectedFile) {
            guard let url = selectedFile, let module = NotchcastCore.services?.tasks,
                  let store = module.store else { return }
            defer { selectedFile = nil }
            do {
                let data = try await TodoistImportClient.export(from: FixtureExportSource(url: url))
                try Task.checkCancellation()
                guard module.store === store else { return }
                let count = try TodoSettingsImport.apply(data, to: store, now: Date(),
                    calendar: .current, timeZone: .current)
                result = String(localized: "Imported tasks: \(count)", table: "Notchcast")
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, module.store === store else { return }
                result = String(localized: "The file is not a Todoist JSON export.", table: "Notchcast")
            }
        }
    }

    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            result = nil
            selectedFile = url
        }
    }
}
