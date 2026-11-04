import Foundation

public struct RequestNavigation: Sendable {
    public private(set) var ids: [UUID] = []
    public private(set) var selectedID: UUID?
    public private(set) var showsOverview = false

    public init() {}

    public mutating func update(_ next: [UUID]) {
        let index = selectedID.flatMap { ids.firstIndex(of: $0) } ?? 0
        ids = next
        if let selectedID, next.contains(selectedID) { return }
        selectedID = next.isEmpty ? nil : next[min(index, next.count - 1)]
    }

    public mutating func openOldest() {
        showsOverview = false
        selectedID = ids.first
    }

    public mutating func overview() { showsOverview = true }

    public mutating func select(_ id: UUID) {
        guard ids.contains(id) else { return }
        selectedID = id
        showsOverview = false
    }
}

public struct QuestionDraft: Sendable {
    public var index = 0
    public var answers: [String: String] = [:]
    public var picked: Set<String> = []
    public var typed = ""

    public init() {}
}
