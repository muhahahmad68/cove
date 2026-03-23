import SwiftUI

extension WeakReconciler: CloudBackupDetailManagerReconciler where Reconciler == CloudBackupDetailManager {}

@Observable
final class CloudBackupDetailManager: AnyReconciler, CloudBackupDetailManagerReconciler, @unchecked Sendable {
    typealias Message = CloudBackupDetailReconcileMessage
    typealias Action = CloudBackupDetailAction

    @ObservationIgnored let rust: RustCloudBackupDetailManager

    var detail: CloudBackupDetail?
    var verification: VerificationState = .idle
    var sync: SyncState = .idle
    var recovery: RecoveryState = .idle
    var cloudOnly: CloudOnlyState = .notFetched
    var cloudOnlyOperation: CloudOnlyOperation = .idle

    init() {
        let rust = RustCloudBackupDetailManager()
        self.rust = rust
        rust.listenForUpdates(reconciler: WeakReconciler(self))
    }

    private let rustBridge = DispatchQueue(label: "cove.CloudBackupDetailManager.rustbridge", qos: .userInitiated)

    func dispatch(_ action: Action) {
        rustBridge.async {
            self.rust.dispatch(action: action)
        }
    }

    func dispatch(action: Action) {
        dispatch(action)
    }

    private func apply(_ message: Message) {
        switch message {
        case let .detailUpdated(newDetail):
            detail = newDetail
        case let .verificationChanged(state):
            verification = state
        case let .syncChanged(state):
            sync = state
        case let .recoveryChanged(state):
            recovery = state
        case let .cloudOnlyChanged(state):
            cloudOnly = state
        case let .cloudOnlyWalletRemoved(recordId):
            if case let .loaded(wallets) = cloudOnly {
                cloudOnly = .loaded(wallets: wallets.filter { $0.recordId != recordId })
            }
        case let .cloudOnlyOperationChanged(state):
            cloudOnlyOperation = state
        }
    }

    func reconcile(message: Message) {
        DispatchQueue.main.async { [weak self] in self?.apply(message) }
    }

    func reconcileMany(messages: [Message]) {
        DispatchQueue.main.async { [weak self] in
            messages.forEach { self?.apply($0) }
        }
    }
}
