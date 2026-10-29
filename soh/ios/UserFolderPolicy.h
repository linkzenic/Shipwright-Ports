#pragma once
#include <string_view>
namespace UserFolder {
inline bool Include(std::string_view path) {
    if (path.empty() || path.front()=='/' || path.find('\\')!=path.npos) return false;
    auto remaining=path;
    while (!remaining.empty()) {
        auto end=remaining.find('/');
        auto part=remaining.substr(0,end);
        if (part.empty() || part.front()=='.' || part=="SaveSync" || part=="Caches" || part=="cache" ||
            part=="logs" || part=="Logs" || part=="tmp" || part=="Conflicts") return false;
        if (end==remaining.npos) break;
        remaining.remove_prefix(end+1);
    }
    return !path.ends_with(".log") && !path.ends_with(".tmp") && !path.ends_with(".icloud") && !path.ends_with(".lock");
}
}
