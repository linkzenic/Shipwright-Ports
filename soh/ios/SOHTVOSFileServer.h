#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

void SOHTVOSFileServer_Start(void);
void SOHTVOSFileServer_Stop(void);
int SOHTVOSFileServer_IsRunning(void);
void SOHTVOSFileServer_GetStatus(char* buffer, size_t bufferSize);

#ifdef __cplusplus
}
#endif
