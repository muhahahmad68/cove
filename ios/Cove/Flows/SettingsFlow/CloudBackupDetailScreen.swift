import SwiftUI

struct CloudBackupDetailScreen: View {
    @State private var detail: CloudBackupDetail?
    @State private var isSyncing = false
    @State private var syncError: String?
    @State private var loadError: String?
    @State private var cloudOnlyWallets: [CloudBackupWalletItem]?
    @State private var isLoadingCloudOnly = false

    var body: some View {
        Form {
            if let detail {
                DetailFormContent(
                    detail: detail,
                    isSyncing: $isSyncing,
                    syncError: $syncError,
                    cloudOnlyWallets: $cloudOnlyWallets,
                    isLoadingCloudOnly: $isLoadingCloudOnly
                )
            } else if let loadError {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.icloud.fill")
                            .foregroundColor(.orange)
                            .font(.largeTitle)

                        Text(loadError)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            } else {
                Section {
                    VStack {
                        ProgressView("Checking cloud backup...")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Cloud Backup")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshFromCloud()
        }
        .onChange(of: CloudBackupManager.shared.state) { _, newState in
            guard isSyncing, newState != .enabling else { return }

            Task { await refreshFromCloud() }
            isSyncing = false
        }
        .onChange(of: CloudBackupManager.shared.syncError) { _, error in
            syncError = error
            CloudBackupManager.shared.syncError = nil
        }
    }

    private func refreshFromCloud() async {
        let refreshed = await Task.detached {
            CloudBackupManager.shared.rust.refreshCloudBackupDetail()
        }.value

        if let refreshed {
            detail = refreshed
            loadError = nil
        } else {
            loadError = "Unable to verify backup status from iCloud"
        }
    }
}

// MARK: - Detail Form Content

private struct DetailFormContent: View {
    let detail: CloudBackupDetail
    @Binding var isSyncing: Bool
    @Binding var syncError: String?
    @Binding var cloudOnlyWallets: [CloudBackupWalletItem]?
    @Binding var isLoadingCloudOnly: Bool

    var body: some View {
        HeaderSection(lastSync: detail.lastSync)
        if !detail.backedUp.isEmpty { BackedUpSections(wallets: detail.backedUp) }
        if !detail.notBackedUp.isEmpty {
            NotBackedUpSections(wallets: detail.notBackedUp)
            SyncSection(isSyncing: $isSyncing, syncError: $syncError)
        }
        if detail.cloudOnlyCount > 0 {
            CloudOnlySection(
                count: detail.cloudOnlyCount,
                wallets: $cloudOnlyWallets,
                isLoading: $isLoadingCloudOnly
            )
        }
    }
}

// MARK: - Header

private struct HeaderSection: View {
    let lastSync: UInt64?

    var body: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.icloud.fill")
                    .foregroundColor(.green)
                    .font(.largeTitle)

                Text("Cloud Backup Active")
                    .fontWeight(.semibold)

                if let lastSync {
                    Text("Last synced \(formatDate(lastSync))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private func formatDate(_ timestamp: UInt64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Sync Section

private struct SyncSection: View {
    @Binding var isSyncing: Bool
    @Binding var syncError: String?

    var body: some View {
        Section {
            Button {
                syncError = nil
                isSyncing = true
                CloudBackupManager.shared.rust.syncUnsyncedWallets()
            } label: {
                HStack {
                    if isSyncing {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("Syncing...")
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Sync Now")
                    }
                }
            }
            .disabled(isSyncing)

            if let syncError {
                Text(syncError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Cloud Only Section

private struct CloudOnlySection: View {
    let count: UInt32
    @Binding var wallets: [CloudBackupWalletItem]?
    @Binding var isLoading: Bool

    var body: some View {
        Section(header: Text("Not on This Device")) {
            if let wallets {
                ForEach(wallets, id: \.name) { item in
                    WalletItemRow(item: item)
                }
            } else {
                HStack {
                    Image(systemName: "icloud.and.arrow.down")
                    Text("\(count) wallet(s) in cloud not on this device")
                }
                .foregroundStyle(.secondary)

                Button {
                    isLoading = true
                    Task.detached {
                        let items = CloudBackupManager.shared.rust.fetchCloudOnlyWallets()
                        await MainActor.run {
                            wallets = items
                            isLoading = false
                        }
                    }
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Loading...")
                        } else {
                            Image(systemName: "info.circle")
                            Text("Get More Info")
                        }
                    }
                }
                .disabled(isLoading)
            }
        }
    }
}

// MARK: - Backed Up Sections

private struct BackedUpSections: View {
    let wallets: [CloudBackupWalletItem]

    var body: some View {
        let grouped = Dictionary(grouping: wallets) {
            GroupKey(network: $0.network, walletMode: $0.walletMode)
        }

        ForEach(grouped.keys.sorted(), id: \.self) { key in
            Section(header: Text(key.title)) {
                ForEach(grouped[key]!, id: \.name) { item in
                    WalletItemRow(item: item)
                }
            }
        }
    }
}

// MARK: - Not Backed Up Sections

private struct NotBackedUpSections: View {
    let wallets: [CloudBackupWalletItem]

    var body: some View {
        let grouped = Dictionary(grouping: wallets) {
            GroupKey(network: $0.network, walletMode: $0.walletMode)
        }

        ForEach(grouped.keys.sorted(), id: \.self) { key in
            Section(header: HStack {
                Text(key.title)
                Text("NOT BACKED UP")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red, in: Capsule())
            }) {
                ForEach(grouped[key]!, id: \.name) { item in
                    WalletItemRow(item: item)
                }
            }
        }
    }
}

// MARK: - Wallet Item Row

private struct WalletItemRow: View {
    let item: CloudBackupWalletItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.name)
                    .fontWeight(.medium)
                Spacer()
                StatusBadge(status: item.status)
            }

            HStack(spacing: 12) {
                IconLabel("globe", item.network.displayName())
                IconLabel("wallet.bifold", item.walletType.displayName())
                if let fingerprint = item.fingerprint {
                    IconLabel("touchid", fingerprint)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let status: CloudBackupWalletStatus

    private var label: String {
        switch status {
        case .backedUp: "Backed up"
        case .notBackedUp: "Not backed up"
        case .deletedFromDevice: "Not on device"
        }
    }

    private var color: Color {
        switch status {
        case .backedUp: .green
        case .notBackedUp: .red
        case .deletedFromDevice: .orange
        }
    }

    var body: some View {
        Text(label)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }
}

// MARK: - Group Key

private struct GroupKey: Hashable, Comparable {
    let network: Network
    let walletMode: WalletMode

    var title: String {
        switch walletMode {
        case .decoy: "\(network.displayName()) · Decoy"
        default: network.displayName()
        }
    }

    static func < (lhs: GroupKey, rhs: GroupKey) -> Bool {
        if lhs.network != rhs.network {
            return lhs.network.displayName() < rhs.network.displayName()
        }
        return lhs.walletMode == .main && rhs.walletMode != .main
    }
}
