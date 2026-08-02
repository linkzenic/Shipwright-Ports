#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Returns to the title/file-select flow without running OnExitGame hooks, including soft-reset autosave.
bool SohResetToFileSelectWithoutSaving(void);

#ifdef __cplusplus
}
#endif
