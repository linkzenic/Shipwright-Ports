#include "../../soh/ios/SaveSyncPolicy.h"
#include "../../soh/ios/UserFolderPolicy.h"
#include <cassert>
int main() {
    using namespace SaveSync;
    assert(Plan("a","a","")==Action::None);
    assert(Plan("","a","")==Action::Download);
    assert(Plan("a","","")==Action::Upload);
    assert(Plan("a","b","")==Action::Conflict);
    assert(Plan("a","b","a")==Action::Download);
    assert(Plan("b","a","a")==Action::Upload);
    assert(Plan("b","c","a")==Action::Conflict);
    assert(Plan("","a","a")==Action::Download);
    assert(Plan("a","","a")==Action::Upload);
    assert(!CanApply("a","a",true));
    assert(!CanApply("a","b",false));
    assert(CanApply("a","a",false));
    assert(IsSaveName("file1.sav"));
    assert(!IsSaveName("../file1.sav"));
    assert(!IsSaveName("file1.sav/other"));
    assert(!IsSaveName("shipofharkinian.json"));
    assert(UserFolder::Include("shipofharkinian.json"));
    assert(UserFolder::Include("mods/HD.o2r"));
    assert(UserFolder::Include("Save/file1.sav"));
    assert(UserFolder::Include("oot.o2r"));
    assert(!UserFolder::Include("../outside.json"));
    assert(!UserFolder::Include("mods/../outside.json"));
    assert(!UserFolder::Include("SaveSync/state.json"));
    assert(!UserFolder::Include("Conflicts/snapshot.json"));
    assert(!UserFolder::Include("Ship of Harkinian.log"));
    assert(!UserFolder::Include("/absolute.json"));
}
