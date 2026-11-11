import Foundation
import Observation

@MainActor
@Observable
final class DayWeatherStore {
    private struct Cache: Codable, Sendable {
        let place: DayWeatherPlace
        let forecast: DayForecast
        let fetchedAt: Date
    }

    private(set) var place: DayWeatherPlace?
    private(set) var forecast: DayForecast?
    private(set) var fetchedAt: Date?
    private(set) var lastError: String?
    private let defaults: UserDefaults
    private let cacheURL: URL
    nonisolated static let placeKey = "notchcast.day.weatherPlace"
    @ObservationIgnored private var task: Task<Void, Never>?
    private var generation = UUID()
    private var fetchingGeneration: UUID?
    private(set) var isRunning = false

    convenience init() {
        self.init(defaults: DayStorage.defaults, cacheURL: DayStorage.weatherCacheURL)
    }

    init(defaults: UserDefaults, cacheURL: URL) {
        self.defaults = defaults
        self.cacheURL = cacheURL
        place = defaults.data(forKey: Self.placeKey).flatMap { try? JSONDecoder().decode(DayWeatherPlace.self, from: $0) }
    }

    func isStale(now: Date) -> Bool {
        fetchedAt.map { now.timeIntervalSince($0) >= 1800 || now < $0 } ?? true
    }

    func select(_ place: DayWeatherPlace?) {
        let restart = isRunning
        stop()
        self.place = place
        forecast = nil
        fetchedAt = nil
        defaults.set(place.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.placeKey)
        if restart { start() }
    }

    func start() {
        stop()
        isRunning = true
        guard let place else { return }
        let operation = generation
        task = Task { [weak self, cacheURL] in
            let cached = await Self.readCache(cacheURL)
            guard !Task.isCancelled, self?.place == place, operation == self?.generation else { return }
            if let cached, cached.place == place {
                self?.forecast = cached.forecast
                self?.fetchedAt = cached.fetchedAt
            }
            while !Task.isCancelled, self != nil {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(1800))
            }
        }
    }

    func stop() {
        isRunning = false
        generation = UUID()
        task?.cancel()
        task = nil
    }

    func refresh() async {
        guard let place, fetchingGeneration != generation else { return }
        let operation = generation
        fetchingGeneration = operation
        defer { if fetchingGeneration == operation { fetchingGeneration = nil } }
        do {
            var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            url.queryItems = [
                .init(name: "latitude", value: String(place.latitude)),
                .init(name: "longitude", value: String(place.longitude)),
                .init(name: "hourly", value: "temperature_2m,weather_code"),
                .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,weather_code"),
                .init(name: "timezone", value: "auto"), .init(name: "timeformat", value: "unixtime")
            ]
            let forecast = try DayForecast.decode(await DayHTTPService.data(url.url!))
            guard !Task.isCancelled, self.place == place, operation == generation else { return }
            let now = Date()
            self.forecast = forecast
            fetchedAt = now
            lastError = nil
            await Self.writeCache(Cache(place: place, forecast: forecast, fetchedAt: now), to: cacheURL)
        } catch {
            guard !Task.isCancelled, self.place == place, operation == generation else { return }
            lastError = error.localizedDescription
        }
    }

    static func cities(matching query: String) async throws -> [DayWeatherPlace] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var url = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        url.queryItems = [.init(name: "name", value: query), .init(name: "count", value: "8")]
        return try DayWeatherPlace.decodeCities(await DayHTTPService.data(url.url!))
    }

    @concurrent private static func readCache(_ url: URL) async -> Cache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Cache.self, from: data)
    }

    @concurrent private static func writeCache(_ cache: Cache, to url: URL) async {
        guard !Task.isCancelled, let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
