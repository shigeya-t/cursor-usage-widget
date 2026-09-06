import Foundation

protocol UsageProvider: Sendable {
    var id: String { get }
    var displayNameKey: String { get }
    var dashboardURL: URL { get }
    func fetchSnapshot() async throws -> UsageSnapshot
}

enum UsageProviderRegistry {
    static let all: [any UsageProvider] = [
        CursorProvider()
    ]

    static func provider(id: String) -> (any UsageProvider)? {
        all.first { $0.id == id }
    }

    static var defaultProviderID: String { CursorProvider.id }
}
