import Foundation
import SwiftUI

/// Service for caching app icons locally
@MainActor
class AppIconCacheService {
    static let shared = AppIconCacheService()

    private let fileManager = FileManager.default
    private let cacheDirectoryName = "AppIcons"
    private var memoryCache: [String: UIImage] = [:]
    private let maxMemoryCacheSize = 50

    private init() {
        createCacheDirectoryIfNeeded()
    }

    // MARK: - Public Methods

    /// Get a cached icon for the given identifier
    /// - Parameter identifier: The app's logicalID or bundleId
    /// - Returns: The cached UIImage, or nil if not cached
    func getCachedIcon(for identifier: String) -> UIImage? {
        let safeIdentifier = sanitizeIdentifier(identifier)

        // Check memory cache first
        if let cached = memoryCache[safeIdentifier] {
            return cached
        }

        // Check disk cache
        guard let filePath = iconFilePath(for: safeIdentifier) else {
            return nil
        }
        if fileManager.fileExists(atPath: filePath.path) {
            if let image = UIImage(contentsOfFile: filePath.path) {
                // Add to memory cache
                addToMemoryCache(image, for: safeIdentifier)
                return image
            }
        }

        return nil
    }

    /// Download and cache an icon from a URL
    /// - Parameters:
    ///   - url: The URL to download from
    ///   - identifier: The app's logicalID or bundleId for caching
    /// - Returns: The downloaded UIImage
    @discardableResult
    func downloadAndCache(from url: URL, for identifier: String) async throws -> UIImage {
        let safeIdentifier = sanitizeIdentifier(identifier)

        // Check if already cached
        if let cached = getCachedIcon(for: safeIdentifier) {
            return cached
        }

        #if DEBUG
        print("[AppIconCacheService] Downloading icon for \(identifier) from \(url)")
        #endif

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw IconCacheError.downloadFailed
        }

        guard let image = UIImage(data: data) else {
            throw IconCacheError.invalidImageData
        }

        // Save to disk
        try saveIconToDisk(data: data, identifier: safeIdentifier)

        // Add to memory cache
        addToMemoryCache(image, for: safeIdentifier)

        #if DEBUG
        print("[AppIconCacheService] Cached icon for \(identifier)")
        #endif

        return image
    }

    /// Download and cache an icon from a URL string
    /// - Parameters:
    ///   - urlString: The URL string to download from
    ///   - identifier: The app's logicalID or bundleId for caching
    /// - Returns: The downloaded UIImage
    @discardableResult
    func downloadAndCache(from urlString: String, for identifier: String) async throws -> UIImage {
        guard let url = URL(string: urlString) else {
            throw IconCacheError.invalidURL
        }
        return try await downloadAndCache(from: url, for: identifier)
    }

    /// Check if an icon is cached for the given identifier
    /// - Parameter identifier: The app's logicalID or bundleId
    /// - Returns: True if the icon is cached
    func isIconCached(for identifier: String) -> Bool {
        let safeIdentifier = sanitizeIdentifier(identifier)

        if memoryCache[safeIdentifier] != nil {
            return true
        }

        guard let filePath = iconFilePath(for: safeIdentifier) else {
            return false
        }
        return fileManager.fileExists(atPath: filePath.path)
    }

    /// Remove a cached icon
    /// - Parameter identifier: The app's logicalID or bundleId
    func removeIcon(for identifier: String) {
        let safeIdentifier = sanitizeIdentifier(identifier)

        // Remove from memory cache
        memoryCache.removeValue(forKey: safeIdentifier)

        // Remove from disk
        if let filePath = iconFilePath(for: safeIdentifier) {
            try? fileManager.removeItem(at: filePath)
        }
    }

    /// Clear all cached icons
    func clearCache() {
        memoryCache.removeAll()

        if let cacheDirectory = cacheDirectory {
            try? fileManager.removeItem(at: cacheDirectory)
            createCacheDirectoryIfNeeded()
        }

        #if DEBUG
        print("[AppIconCacheService] Cache cleared")
        #endif
    }

    /// Get the total size of the icon cache in bytes
    func cacheSize() -> Int64 {
        guard let cacheDirectory = cacheDirectory else { return 0 }

        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            var totalSize: Int64 = 0
            for file in files {
                let resourceValues = try file.resourceValues(forKeys: [.fileSizeKey])
                totalSize += Int64(resourceValues.fileSize ?? 0)
            }
            return totalSize
        } catch {
            return 0
        }
    }

    // MARK: - Private Methods

    private var cacheDirectory: URL? {
        guard let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return cachesDirectory.appendingPathComponent(cacheDirectoryName)
    }

    private func createCacheDirectoryIfNeeded() {
        guard let cacheDirectory = cacheDirectory else { return }

        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }

    private func iconFilePath(for identifier: String) -> URL? {
        guard let cacheDirectory = cacheDirectory else {
            return nil
        }
        return cacheDirectory.appendingPathComponent("\(identifier).png")
    }

    private func saveIconToDisk(data: Data, identifier: String) throws {
        guard let filePath = iconFilePath(for: identifier) else {
            throw IconCacheError.saveFailed
        }
        try data.write(to: filePath)
    }

    private func sanitizeIdentifier(_ identifier: String) -> String {
        // Replace characters that aren't safe for filenames
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return identifier
            .components(separatedBy: allowedCharacters.inverted)
            .joined(separator: "_")
    }

    private func addToMemoryCache(_ image: UIImage, for identifier: String) {
        // Simple LRU-like eviction: remove random entries if cache is full
        if memoryCache.count >= maxMemoryCacheSize {
            let keysToRemove = Array(memoryCache.keys.prefix(10))
            for key in keysToRemove {
                memoryCache.removeValue(forKey: key)
            }
        }
        memoryCache[identifier] = image
    }
}

// MARK: - Errors

enum IconCacheError: LocalizedError {
    case invalidURL
    case downloadFailed
    case invalidImageData
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid icon URL"
        case .downloadFailed:
            return "Failed to download icon"
        case .invalidImageData:
            return "Invalid image data"
        case .saveFailed:
            return "Failed to save icon to cache"
        }
    }
}

// MARK: - SwiftUI View for Cached Icons

/// A SwiftUI view that displays a cached app icon or loads it from URL
struct CachedAppIcon: View {
    let iconURL: String?
    let identifier: String
    let size: CGFloat
    let fallbackSymbol: String

    @State private var image: UIImage?
    @State private var isLoading = false

    init(iconURL: String?, identifier: String, size: CGFloat = 40, fallbackSymbol: String = "app.fill") {
        self.iconURL = iconURL
        self.identifier = identifier
        self.size = size
        self.fallbackSymbol = fallbackSymbol
    }

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
            } else if isLoading {
                ProgressView()
                    .frame(width: size, height: size)
            } else {
                // Fallback to SF Symbol
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.5))
                    .foregroundColor(.gray)
                    .frame(width: size, height: size)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
            }
        }
        .task(id: iconURL) {
            await loadIcon()
        }
    }

    @MainActor
    private func loadIcon() async {
        #if DEBUG
        print("[CachedAppIcon] loadIcon() called for \(identifier)")
        print("[CachedAppIcon]   iconURL: \(iconURL ?? "nil")")
        #endif

        let cacheService = AppIconCacheService.shared

        // Check cache first
        if let cached = cacheService.getCachedIcon(for: identifier) {
            #if DEBUG
            print("[CachedAppIcon]   Found in cache")
            #endif
            image = cached
            return
        }

        // Download if URL is available
        guard let urlString = iconURL, !urlString.isEmpty else {
            #if DEBUG
            print("[CachedAppIcon]   No URL available, using fallback")
            #endif
            return
        }

        #if DEBUG
        print("[CachedAppIcon]   Downloading from: \(urlString)")
        #endif

        isLoading = true
        defer { isLoading = false }

        do {
            image = try await cacheService.downloadAndCache(from: urlString, for: identifier)
            #if DEBUG
            print("[CachedAppIcon]   Download successful")
            #endif
        } catch {
            #if DEBUG
            print("[CachedAppIcon] Failed to load icon: \(error)")
            #endif
        }
    }
}
