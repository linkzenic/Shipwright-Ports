#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
void SOHUserFolderSync_Start(void);
void SOHUserFolderSync_Changed(void);
void SOHUserFolderSync_ApplyAtLaunch(void);
void SOHUserFolderSync_ChooseFallback(void);
int SOHUserFolderSync_HasNativeFolder(void);
void SOHUserFolderSync_GetStatus(char* buffer,size_t size);
#ifdef __cplusplus
}
#endif
