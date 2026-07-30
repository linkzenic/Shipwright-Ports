#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Reconciles cloud saves before SaveManager reads its local metadata. This may
// briefly wait for iCloud so a newer save is available on first use.
void SOHiCloudSync_PrepareSaves(void);

// Reconciles save metadata while the app is running. Newer cloud saves are
// intentionally applied on the next launch so an active in-memory save cannot
// overwrite them.
void SOHiCloudSync_SyncNow(void);

// Queues reconciliation after a local save is atomically committed or deleted.
void SOHiCloudSync_LocalSaveChanged(const char* path);
void SOHiCloudSync_LocalSaveDeleted(const char* path);

// Copies the current user-facing state into buffer as UTF-8.
void SOHiCloudSync_GetStatus(char* buffer, size_t bufferSize);

#ifdef __cplusplus
}
#endif
