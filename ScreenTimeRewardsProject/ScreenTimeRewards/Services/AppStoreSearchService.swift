import Foundation
import Combine

/// Information about an app from the iTunes Search API
struct AppStoreAppInfo: Codable, Identifiable, Hashable {
    let trackId: Int
    let trackName: String
    let bundleId: String
    let artworkUrl60: String
    let artworkUrl100: String
    let artworkUrl512: String

    var id: Int { trackId }

    /// Get the appropriate icon URL for the given size
    func iconURL(size: IconSize) -> URL? {
        let urlString: String
        switch size {
        case .small:
            urlString = artworkUrl60
        case .medium:
            urlString = artworkUrl100
        case .large:
            urlString = artworkUrl512
        }
        return URL(string: urlString)
    }

    enum IconSize {
        case small   // 60px
        case medium  // 100px
        case large   // 512px
    }
}

/// Response structure from iTunes Search API
private struct iTunesSearchResponse: Codable {
    let resultCount: Int
    let results: [iTunesAppResult]
}

/// Individual app result from iTunes API
private struct iTunesAppResult: Codable {
    let trackId: Int?
    let trackName: String?
    let bundleId: String?
    let artworkUrl60: String?
    let artworkUrl100: String?
    let artworkUrl512: String?

    func toAppInfo() -> AppStoreAppInfo? {
        guard let trackId = trackId,
              let trackName = trackName,
              let bundleId = bundleId,
              let artworkUrl60 = artworkUrl60,
              let artworkUrl100 = artworkUrl100,
              let artworkUrl512 = artworkUrl512 else {
            return nil
        }

        return AppStoreAppInfo(
            trackId: trackId,
            trackName: trackName,
            bundleId: bundleId,
            artworkUrl60: artworkUrl60,
            artworkUrl100: artworkUrl100,
            artworkUrl512: artworkUrl512
        )
    }
}

/// Service for searching the App Store via iTunes Search API
class AppStoreSearchService: ObservableObject {
    @MainActor static let shared = AppStoreSearchService()

    @Published var searchResults: [AppStoreAppInfo] = []
    @Published var isSearching = false
    @Published var searchError: String?

    private var searchTask: Task<Void, Never>?
    private var cache: [String: CachedResult] = [:]
    private let cacheTimeout: TimeInterval = 300 // 5 minutes
    private let debounceInterval: TimeInterval = 0.3 // 300ms

    private struct CachedResult {
        let results: [AppStoreAppInfo]
        let timestamp: Date

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > 300
        }
    }

    @MainActor
    private init() {}

    // MARK: - Public Methods

    /// Search for apps by name with debouncing
    /// - Parameter query: The search term
    @MainActor
    func search(query: String) {
        // Cancel any pending search
        searchTask?.cancel()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Clear results if query is too short
        guard trimmedQuery.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }

        // Check cache first
        if let cached = cache[trimmedQuery.lowercased()], !cached.isExpired {
            searchResults = cached.results
            isSearching = false
            #if DEBUG
            print("[AppStoreSearchService] Cache hit for '\(trimmedQuery)': \(cached.results.count) results")
            #endif
            return
        }

        isSearching = true
        #if DEBUG
        print("[AppStoreSearchService] Starting search for '\(trimmedQuery)'...")
        #endif

        // Debounce the search
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))

            guard !Task.isCancelled else { return }

            do {
                let results = try await performSearch(query: trimmedQuery)

                guard !Task.isCancelled else { return }

                // Cache the results
                cache[trimmedQuery.lowercased()] = CachedResult(results: results, timestamp: Date())

                searchResults = results
                searchError = nil

                #if DEBUG
                print("[AppStoreSearchService] Search complete for '\(trimmedQuery)': \(results.count) results")
                for app in results.prefix(3) {
                    print("  - \(app.trackName)")
                }
                #endif
            } catch {
                guard !Task.isCancelled else { return }

                if !(error is CancellationError) {
                    searchError = error.localizedDescription
                    #if DEBUG
                    print("[AppStoreSearchService] Search error: \(error)")
                    #endif
                }
            }

            isSearching = false
        }
    }

    /// Search for apps synchronously (async/await version)
    /// - Parameter query: The search term
    /// - Returns: Array of matching apps
    func searchApps(query: String) async throws -> [AppStoreAppInfo] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedQuery.count >= 2 else {
            return []
        }

        // Check cache first
        if let cached = cache[trimmedQuery.lowercased()], !cached.isExpired {
            return cached.results
        }

        let results = try await performSearch(query: trimmedQuery)

        // Cache the results
        cache[trimmedQuery.lowercased()] = CachedResult(results: results, timestamp: Date())

        return results
    }

    /// Clear the search results
    @MainActor
    func clearSearch() {
        searchTask?.cancel()
        searchResults = []
        isSearching = false
        searchError = nil
    }

    /// Clear the cache
    @MainActor
    func clearCache() {
        cache.removeAll()
    }

    // MARK: - Private Methods

    private func performSearch(query: String) async throws -> [AppStoreAppInfo] {
        // Build the iTunes Search API URL
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encodedQuery)&entity=software&country=us&limit=10") else {
            throw AppStoreSearchError.invalidQuery
        }

        #if DEBUG
        print("[AppStoreSearchService] Searching: \(url.absoluteString)")
        #endif

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppStoreSearchError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw AppStoreSearchError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let searchResponse = try decoder.decode(iTunesSearchResponse.self, from: data)

        let apps = searchResponse.results.compactMap { $0.toAppInfo() }

        #if DEBUG
        print("[AppStoreSearchService] Found \(apps.count) apps for '\(query)'")
        #endif

        return apps
    }
}

// MARK: - Errors

enum AppStoreSearchError: LocalizedError {
    case invalidQuery
    case invalidResponse
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "Invalid search query"
        case .invalidResponse:
            return "Invalid response from App Store"
        case .httpError(let statusCode):
            return "App Store returned error: \(statusCode)"
        }
    }
}
