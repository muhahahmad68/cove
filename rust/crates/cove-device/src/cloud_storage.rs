use std::sync::Arc;

use once_cell::sync::OnceCell;
use tracing::warn;

#[derive(Debug, Clone, Hash, Eq, PartialEq, uniffi::Error, thiserror::Error)]
#[uniffi::export(Display)]
pub enum CloudStorageError {
    #[error("not available: {0}")]
    NotAvailable(String),

    #[error("upload failed: {0}")]
    UploadFailed(String),

    #[error("download failed: {0}")]
    DownloadFailed(String),

    #[error("not found: {0}")]
    NotFound(String),

    #[error("quota exceeded")]
    QuotaExceeded,
}

#[uniffi::export(callback_interface)]
pub trait CloudStorageAccess: Send + Sync + std::fmt::Debug + 'static {
    fn upload_master_key_backup(
        &self,
        namespace: String,
        data: Vec<u8>,
    ) -> Result<(), CloudStorageError>;

    fn upload_wallet_backup(
        &self,
        namespace: String,
        record_id: String,
        data: Vec<u8>,
    ) -> Result<(), CloudStorageError>;

    fn download_master_key_backup(&self, namespace: String) -> Result<Vec<u8>, CloudStorageError>;

    fn download_wallet_backup(
        &self,
        namespace: String,
        record_id: String,
    ) -> Result<Vec<u8>, CloudStorageError>;

    fn delete_wallet_backup(
        &self,
        namespace: String,
        record_id: String,
    ) -> Result<(), CloudStorageError>;

    /// List all namespace IDs (subdirectories of cspp-namespaces/)
    fn list_namespaces(&self) -> Result<Vec<String>, CloudStorageError>;

    /// List wallet backup record IDs within a namespace (excludes master key file)
    fn list_wallet_backups(&self, namespace: String) -> Result<Vec<String>, CloudStorageError>;

    /// Check if any cloud backup namespaces exist
    fn has_any_cloud_backup(&self) -> Result<bool, CloudStorageError>;

    /// Delete all flat-format files directly in Data/ (legacy cleanup)
    fn delete_all_flat_files(&self) -> Result<(), CloudStorageError>;
}

static REF: OnceCell<CloudStorage> = OnceCell::new();

#[derive(Debug, Clone, uniffi::Object)]
pub struct CloudStorage(Arc<Box<dyn CloudStorageAccess>>);

impl CloudStorage {
    pub fn global() -> &'static Self {
        REF.get().expect("cloud storage is not initialized")
    }
}

#[uniffi::export]
impl CloudStorage {
    #[uniffi::constructor]
    pub fn new(cloud_storage: Box<dyn CloudStorageAccess>) -> Self {
        if let Some(me) = REF.get() {
            warn!("cloud storage is already initialized");
            return me.clone();
        }

        let me = Self(Arc::new(cloud_storage));
        REF.set(me).expect("failed to set cloud storage");

        Self::global().clone()
    }
}

impl CloudStorage {
    pub fn upload_master_key_backup(
        &self,
        namespace: String,
        data: Vec<u8>,
    ) -> Result<(), CloudStorageError> {
        self.0.upload_master_key_backup(namespace, data)
    }

    pub fn upload_wallet_backup(
        &self,
        namespace: String,
        record_id: String,
        data: Vec<u8>,
    ) -> Result<(), CloudStorageError> {
        self.0.upload_wallet_backup(namespace, record_id, data)
    }

    pub fn download_master_key_backup(
        &self,
        namespace: String,
    ) -> Result<Vec<u8>, CloudStorageError> {
        self.0.download_master_key_backup(namespace)
    }

    pub fn download_wallet_backup(
        &self,
        namespace: String,
        record_id: String,
    ) -> Result<Vec<u8>, CloudStorageError> {
        self.0.download_wallet_backup(namespace, record_id)
    }

    pub fn delete_wallet_backup(
        &self,
        namespace: String,
        record_id: String,
    ) -> Result<(), CloudStorageError> {
        self.0.delete_wallet_backup(namespace, record_id)
    }

    pub fn list_namespaces(&self) -> Result<Vec<String>, CloudStorageError> {
        self.0.list_namespaces()
    }

    pub fn list_wallet_backups(&self, namespace: String) -> Result<Vec<String>, CloudStorageError> {
        self.0.list_wallet_backups(namespace)
    }

    pub fn has_any_cloud_backup(&self) -> Result<bool, CloudStorageError> {
        self.0.has_any_cloud_backup()
    }

    pub fn delete_all_flat_files(&self) -> Result<(), CloudStorageError> {
        self.0.delete_all_flat_files()
    }
}
