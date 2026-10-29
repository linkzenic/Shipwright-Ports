#pragma once
#include <string>
#include <string_view>

namespace SaveSync {
enum class Action { None, Upload, Download, Conflict };

// Empty digests mean missing files. Deletions never propagate automatically.
// A baseline is the last content verified on both sides, not a timestamp.
inline Action Plan(std::string_view local, std::string_view remote,
                   std::string_view baseline) {
    if (local == remote) return Action::None;
    if (local.empty()) return remote.empty() ? Action::None : Action::Download;
    if (remote.empty()) return Action::Upload;
    if (baseline.empty()) return Action::Conflict;
    if (local == baseline) return Action::Download;
    if (remote == baseline) return Action::Upload;
    return Action::Conflict;
}

inline bool IsSaveName(std::string_view name) {
    return name == "file1.sav" || name == "file2.sav" || name == "file3.sav" || name == "global.sav";
}

// A download remains staged if play or another sync changed the local save
// after its manifest was read. Never replace the new local content blindly.
inline bool CanApply(std::string_view expectedLocal, std::string_view currentLocal,
                     bool gameRunning) {
    return !gameRunning && expectedLocal == currentLocal;
}
}
