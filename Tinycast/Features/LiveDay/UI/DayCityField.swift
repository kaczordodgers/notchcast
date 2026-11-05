import SwiftUI

struct DayCityField: View {
    private let noResults: LocalizedStringResource = "No Results"
    let store: DayWeatherStore
    @State private var query = ""
    @State private var submitted: String?
    @State private var request = UUID()
    @State private var results: [DayWeatherPlace] = []
    @State private var failed = false
    @State private var searching = false

    var body: some View {
        TextField(String(localized: "Search for a city", table: "Notchcast"), text: $query)
            .accessibilityLabel(Text("City", tableName: "Notchcast"))
            .onSubmit { submitted = query; request = UUID() }
            .onChange(of: query) { _, _ in
                submitted = nil
                request = UUID()
                results = []
                failed = false
                searching = false
            }
            .task(id: request) { await search() }
        if let place = store.place {
            LabeledContent {
                Text(place.name)
            } label: {
                SettingsRowTitle(.notchcastDay, LocalizedStringResource("City", table: "Notchcast"))
            }
        }
        if searching { ProgressView().accessibilityLabel(Text("Search for a city", tableName: "Notchcast")) }
        if failed {
            Text("Couldn’t search for cities.", tableName: "Notchcast").foregroundStyle(.secondary)
        } else if let submitted, !submitted.isEmpty, !searching, results.isEmpty {
            Text(noResults).foregroundStyle(.secondary)
        }
        ForEach(results.indices, id: \.self) { index in
            let place = results[index]
            Button { store.select(place) } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(place.name)
                    if let country = place.country { Text(country).foregroundStyle(.secondary) }
                    Spacer()
                    if store.place == place {
                        Image(systemName: "checkmark").accessibilityHidden(true)
                    }
                }
            }
            .accessibilityLabel(Text(place.name))
            .accessibilityAddTraits(store.place == place ? .isSelected : [])
        }
    }

    private func search() async {
        guard let submitted, !submitted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searching = false
            return
        }
        searching = true
        failed = false
        do {
            let places = try await DayWeatherStore.cities(matching: submitted)
            guard !Task.isCancelled, self.submitted == submitted else { return }
            results = places
        } catch {
            guard !Task.isCancelled, self.submitted == submitted else { return }
            failed = true
        }
        searching = false
    }
}
