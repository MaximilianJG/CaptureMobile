//
//  TagManager.swift
//  CaptureMobile

import Foundation
import Combine

final class TagManager: ObservableObject {
    static let shared = TagManager()

    @Published var tags: [APIService.UserTag] = []
    @Published var isLoading = false

    private init() {}

    @MainActor
    func loadTags() async {
        guard let userID = AppleAuthManager.shared.getUserID() else { return }
        isLoading = true
        let fetched = await APIService.shared.getUserTags(userID: userID)
        tags = fetched.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        isLoading = false
    }

    @MainActor
    func createTag(name: String) async {
        guard let userID = AppleAuthManager.shared.getUserID() else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !tags.contains(where: { $0.name.lowercased() == trimmed.lowercased() }) else { return }

        if let tag = await APIService.shared.createUserTag(userID: userID, name: trimmed) {
            tags.append(tag)
            tags.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    @MainActor
    func deleteTag(id: String) async {
        guard let userID = AppleAuthManager.shared.getUserID() else { return }
        tags.removeAll { $0.id == id }
        _ = await APIService.shared.deleteUserTag(tagID: id, userID: userID)
    }
}
