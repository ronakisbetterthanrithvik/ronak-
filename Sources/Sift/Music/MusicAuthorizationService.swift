import MusicKit
import SwiftUI
import Combine

@MainActor
final class MusicAuthorizationService: ObservableObject {
    static let shared = MusicAuthorizationService()

    @Published private(set) var status: MusicAuthorization.Status = MusicAuthorization.currentStatus

    var isAuthorized: Bool { status == .authorized }

    func refreshStatus() {
        status = MusicAuthorization.currentStatus
    }

    @discardableResult
    func requestAccess() async -> MusicAuthorization.Status {
        let result = await MusicAuthorization.request()
        status = result
        return result
    }
}
