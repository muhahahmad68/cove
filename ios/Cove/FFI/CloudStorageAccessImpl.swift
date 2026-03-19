import CloudKit

@_exported import CoveCore
import Foundation

final class CloudStorageAccessImpl: CloudStorageAccess, @unchecked Sendable {
    private let container = CKContainer(identifier: "iCloud.com.covebitcoinwallet")
    private var db: CKDatabase {
        container.privateCloudDatabase
    }

    private static let recordType = "CSPPBackup"
    private static let dataField = "data"

    // MARK: - Upload

    func uploadMasterKeyBackup(data: Data) throws {
        try uploadRecord(recordId: csppMasterKeyRecordId(), data: data)
    }

    func uploadWalletBackup(recordId: String, data: Data) throws {
        try uploadRecord(recordId: recordId, data: data)
    }

    func uploadManifest(data: Data) throws {
        try uploadRecord(recordId: csppManifestRecordId(), data: data)
    }

    // MARK: - Download

    func downloadMasterKeyBackup() throws -> Data {
        try downloadRecord(recordId: csppMasterKeyRecordId())
    }

    func downloadWalletBackup(recordId: String) throws -> Data {
        try downloadRecord(recordId: recordId)
    }

    func downloadManifest() throws -> Data {
        try downloadRecord(recordId: csppManifestRecordId())
    }

    // MARK: - Presence check

    func hasCloudBackup() throws -> Bool {
        let recordID = CKRecord.ID(recordName: csppManifestRecordId())
        let semaphore = DispatchSemaphore(value: 0)
        var fetchResult: Result<Bool, CloudStorageError>?

        let operation = CKFetchRecordsOperation(recordIDs: [recordID])
        operation.perRecordResultBlock = { _, result in
            switch result {
            case .success:
                fetchResult = .success(true)
            case let .failure(error):
                if let ckError = error as? CKError, ckError.code == .unknownItem {
                    fetchResult = .success(false)
                } else {
                    fetchResult = .failure(Self.mapFetchError(error, recordId: "manifest"))
                }
            }
        }
        operation.fetchRecordsResultBlock = { result in
            if fetchResult == nil {
                if case let .failure(error) = result {
                    Log.error("CloudKit hasCloudBackup operation failed: \(error)")
                    fetchResult = .failure(Self.mapFetchError(error, recordId: "manifest"))
                } else {
                    fetchResult = .success(false)
                }
            }
            semaphore.signal()
        }

        db.add(operation)
        semaphore.wait()
        return try fetchResult!.get()
    }

    // MARK: - Private helpers

    private func uploadRecord(recordId: String, data: Data) throws {
        let record = CKRecord(
            recordType: Self.recordType,
            recordID: CKRecord.ID(recordName: recordId)
        )
        record[Self.dataField] = data as CKRecordValue

        let semaphore = DispatchSemaphore(value: 0)
        var uploadError: CloudStorageError?

        let operation = CKModifyRecordsOperation(
            recordsToSave: [record],
            recordIDsToDelete: nil
        )
        operation.savePolicy = .allKeys
        operation.modifyRecordsResultBlock = { result in
            if case let .failure(error) = result {
                if let ckError = error as? CKError, ckError.code == .quotaExceeded {
                    uploadError = .QuotaExceeded
                } else {
                    uploadError = .UploadFailed(error.localizedDescription)
                }
            }
            semaphore.signal()
        }

        db.add(operation)
        semaphore.wait()

        if let error = uploadError {
            throw error
        }
    }

    private func downloadRecord(recordId: String) throws -> Data {
        let recordID = CKRecord.ID(recordName: recordId)
        let semaphore = DispatchSemaphore(value: 0)
        var fetchResult: Result<Data, CloudStorageError>?

        let operation = CKFetchRecordsOperation(recordIDs: [recordID])
        operation.perRecordResultBlock = { _, result in
            switch result {
            case let .success(record):
                if let data = record[Self.dataField] as? Data {
                    fetchResult = .success(data)
                } else {
                    fetchResult = .failure(
                        .DownloadFailed("record '\(recordId)' exists but data field is nil")
                    )
                }
            case let .failure(error):
                fetchResult = .failure(Self.mapFetchError(error, recordId: recordId))
            }
        }
        operation.fetchRecordsResultBlock = { result in
            if fetchResult == nil {
                if case let .failure(error) = result {
                    Log.error("CloudKit fetch operation failed: \(error)")
                    fetchResult = .failure(Self.mapFetchError(error, recordId: recordId))
                } else {
                    fetchResult = .failure(.NotFound(recordId))
                }
            }
            semaphore.signal()
        }

        db.add(operation)
        semaphore.wait()
        return try fetchResult!.get()
    }

    private static func mapFetchError(_ error: Error, recordId: String) -> CloudStorageError {
        if let ckError = error as? CKError {
            Log.error(
                "CloudKit CKError code=\(ckError.code.rawValue) "
                    + "domain=\(ckError.errorCode) "
                    + "userInfo=\(ckError.userInfo)"
            )
            switch ckError.code {
            case .unknownItem:
                return .NotFound(recordId)
            case .networkUnavailable, .networkFailure, .serviceUnavailable:
                return .NotAvailable(ckError.localizedDescription)
            default:
                return .DownloadFailed(ckError.localizedDescription)
            }
        }
        Log.error("CloudKit non-CK error: \(error)")
        return .DownloadFailed(error.localizedDescription)
    }
}
