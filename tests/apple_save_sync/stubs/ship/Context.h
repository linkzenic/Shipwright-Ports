#pragma once
#include <string>
extern std::string SaveSyncTestRoot;
namespace Ship {
struct Context {
    static std::string GetAppDirectoryPath() { return SaveSyncTestRoot; }
};
}
