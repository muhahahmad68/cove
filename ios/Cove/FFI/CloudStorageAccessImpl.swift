@_exported import CoveCore
import Foundation

final class CloudStorageAccessImpl: CloudStorageAccess, @unchecked Sendable {
    private let helper = ICloudDriveHelper.shared

    // MARK: - Upload

    func uploadMasterKeyBackup(namespace: String, data: Data) throws {
        let url = try helper.masterKeyFileURL(namespace: namespace)
        try helper.coordinatedWrite(data: data, to: url)
        try helper.waitForUpload(url: url)
    }

    func uploadWalletBackup(namespace: String, recordId: String, data: Data) throws {
        let url = try helper.walletFileURL(namespace: namespace, recordId: recordId)
        try helper.coordinatedWrite(data: data, to: url)
        try helper.waitForUpload(url: url)
    }

    // MARK: - Download

    func downloadMasterKeyBackup(namespace: String) throws -> Data {
        let url = try helper.masterKeyFileURL(namespace: namespace)
        try helper.ensureDownloaded(url: url, recordId: "masterkey-\(namespace)")
        return try helper.coordinatedRead(from: url)
    }

    func downloadWalletBackup(namespace: String, recordId: String) throws -> Data {
        let url = try helper.walletFileURL(namespace: namespace, recordId: recordId)
        try helper.ensureDownloaded(url: url, recordId: recordId)
        return try helper.coordinatedRead(from: url)
    }

    func deleteWalletBackup(namespace: String, recordId: String) throws {
        let url = try helper.walletFileURL(namespace: namespace, recordId: recordId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CloudStorageError.NotFound(recordId)
        }
        try helper.coordinatedDelete(at: url)
    }

    // MARK: - Namespace discovery

    func listNamespaces() throws -> [String] {
        let namespacesRoot = try helper.namespacesRootURL()
        return try helper.listSubdirectories(parentPath: namespacesRoot.path)
    }

    func listWalletBackups(namespace: String) throws -> [String] {
        let nsDir = try helper.namespaceDirectoryURL(namespace: namespace)
        let walletFiles = try helper.listFiles(namespacePath: nsDir.path, prefix: "wallet-")

        // extract record IDs from filenames: wallet-{hash}.json -> {hash}
        return walletFiles.compactMap { filename in
            guard filename.hasPrefix("wallet-"), filename.hasSuffix(".json") else { return nil }
            let start = filename.index(filename.startIndex, offsetBy: 7) // "wallet-".count
            let end = filename.index(filename.endIndex, offsetBy: -5) // ".json".count
            guard start < end else { return nil }
            return String(filename[start ..< end])
        }
    }

    func hasAnyCloudBackup() throws -> Bool {
        let namespaces = try listNamespaces()
        if !namespaces.isEmpty { return true }

        return try helper.hasLegacyFlatFiles()
    }

    // MARK: - Cleanup

    func deleteAllFlatFiles() throws {
        let dataDir = try helper.dataDirectoryURL()
        let resolvedDataDir = dataDir.resolvingSymlinksInPath().path
        let prefix = resolvedDataDir + "/"

        // use NSMetadataQuery to find all .json files (including evicted cloud-only files)
        let predicate = NSPredicate(
            format: "%K BEGINSWITH %@ AND %K ENDSWITH[c] %@",
            NSMetadataItemPathKey, resolvedDataDir,
            NSMetadataItemFSNameKey, ".json"
        )
        let results = try helper.metadataQuery(predicate: predicate)

        for item in results {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else {
                continue
            }

            // only delete files directly in Data/, not in subdirectories
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            guard resolved.hasPrefix(prefix) else { continue }
            let relative = String(resolved.dropFirst(prefix.count))
            guard !relative.contains("/") else { continue }

            try helper.coordinatedDelete(at: URL(fileURLWithPath: path))
        }
    }
}
