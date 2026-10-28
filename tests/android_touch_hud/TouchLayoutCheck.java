package com.dishii.soh;

public final class TouchLayoutCheck {
    static void check(boolean value) { if (!value) throw new AssertionError(); }
    public static void main(String[] args) {
        float[] modern=TouchLayout.modernFaceCenters(1000,600,16,16,1);
        check(modern[0]==935 && modern[1]==491); // A: right of diamond
        check(modern[2]==891 && modern[3]==535); // B: bottom
        check(modern[4]==891 && modern[5]==447); // X: top
        check(modern[6]==847 && modern[7]==491); // Y: left
        float[] wider=TouchLayout.modernFaceCenters(1200,600,16,16,1);
        check(wider[0]-modern[0]==200 && wider[1]==modern[1]);
        check(TouchLayout.modernDpadTop(600,16,16,1)==332);
        check(TouchLayout.modernDpadTop(1080,48,48,3)==390);
        check(TouchLayout.floatingStickContains(1,.98f,.98f));
        check(!TouchLayout.floatingStickContains(0,.98f,.98f));
        check(TouchLayout.floatingStickContains(0,.02f,.98f));
        check(!TouchLayout.floatingStickContains(1,.02f,.98f));
        check(TouchLayout.floatingStickContains(1,.5f,.5f));
        check(!TouchLayout.floatingStickContains(0,.5f,.5f));
        check(!TouchLayout.floatingStickContains(1,Float.NaN,.5f));
        check(!TouchLayout.floatingStickContains(1,1.1f,.5f));
        check(!TouchLayout.floatingStickContains(-1,.5f,.5f));
        check(TouchBindings.KEYS.length == 16);
        check(TouchBindings.mask(16,false) == 0x10000 && TouchBindings.slot(16,false) == -1);
        check(TouchBindings.index("cr") == 4 && TouchBindings.index("look") == -1);
        check(TouchBindings.mask(1,false) == 0x8000 && TouchBindings.slot(1,false) == 9);
        check(TouchBindings.mask(2,false) == 0x4000 && TouchBindings.slot(2,false) == 0);
        check(TouchBindings.mask(TouchBindings.NAVI,false) == 0x20000);
        check(TouchBindings.mask(TouchBindings.NAVI,true) == 0x20000);
        check(TouchBindings.mask(TouchBindings.NAVI,true,true) == 8);
        check(TouchBindings.mask(TouchBindings.NAVI,false,true) == 8);
        check(TouchBindings.mask(17,false) == 0x01000000 && TouchBindings.slot(17,false) == -1);
        check(TouchBindings.mask(18,false) == 0x40 && TouchBindings.slot(18,false) == -1);
        check(TouchBindings.mask(19,false) == 0x80 && TouchBindings.slot(19,false) == -1);
        check(TouchBindings.mask(18,false,true) == 0x40 && TouchBindings.mask(19,false,true) == 0x80);
        check(TouchBindings.slot(TouchBindings.NAVI,true) == 8);
        check(TouchBindings.mask(6,false) == 2 && TouchBindings.slot(6,false) == 1);
        check(TouchBindings.mask(7,false) == 4 && TouchBindings.slot(7,false) == 2);
        check(TouchBindings.mask(8,false) == 1 && TouchBindings.slot(8,false) == 3);
        check(TouchBindings.mask(12,false) == 0x800 && TouchBindings.slot(12,false) == 4);
        check(TouchBindings.mask(13,false) == 0x400 && TouchBindings.slot(13,false) == 5);
        check(TouchBindings.mask(14,false) == 0x200 && TouchBindings.slot(14,false) == 6);
        check(TouchBindings.mask(15,false) == 0x100 && TouchBindings.slot(15,false) == 7);
        check(TouchBindings.mask(0,false) == 0 && TouchBindings.slot(0,false) == -1);
        check(TouchBindings.mask(999,false) == 0 && TouchBindings.slot(999,false) == -1);
        TouchLayout original = new TouchLayout();
        original.set("a", .8f, .7f, 1);
        TouchLayout draft = original.copy();
        draft.set("a", .4f, .2f, 1.5f);
        check(original.get("a")[0] == .8f); // Cancel restores the untouched snapshot.
        TouchLayout saved = TouchLayout.decode(draft.encode());
        check(saved.get("a")[0] == .4f && saved.get("a")[2] == 1.5f);
        saved.clear(); check(saved.get("a") == null && original.get("a") != null);
        TouchLayout invalid = TouchLayout.decode("v1;a=NaN,0,1;b=0,Infinity,1;cl=-3,8,100;cr=0,0,-1");
        check(invalid.get("a") == null && invalid.get("b") == null);
        check(invalid.get("cl")[0] == 0 && invalid.get("cl")[1] == 1 && invalid.get("cl")[2] == 2);
        check(invalid.get("cr")[2] == .5f);
        check(TouchLayout.decode("v3;a=0,0,1").get("a") == null);
        check(TouchLayout.decode("v1;a=0.2,0.3,1.2").get("a")[0] == .2f);
        original.setDpadVisible(false);
        check(!original.isDpadVisible());
        TouchLayout visibilityDraft = original.copy();
        visibilityDraft.setDpadVisible(true);
        check(!original.isDpadVisible() && visibilityDraft.isDpadVisible());
        visibilityDraft.setVisible("b", false);
        TouchLayout visibleSaved = TouchLayout.decode(visibilityDraft.encode());
        check(!visibleSaved.isVisible("b") && visibleSaved.isDpadVisible());
        visibleSaved.clear();
        check(visibleSaved.isVisible("b") && visibleSaved.isDpadVisible());
        check(!TouchLayout.decode("v2;!du;!dd;!dl;!dr").isDpadVisible());
        original.setCButtonsVisible(false);
        check(!original.isCButtonsVisible() && !original.isDpadVisible());
        TouchLayout groups = TouchLayout.decode(original.encode());
        check(!groups.isCButtonsVisible() && !groups.isDpadVisible());
        groups.setCButtonsVisible(true);
        check(groups.isCButtonsVisible() && !groups.isDpadVisible());
        groups.setVisible("cl", false);
        check(groups.isCButtonsVisible());
        groups.setCButtonsVisible(false);
        check(!groups.isCButtonsVisible() && !groups.isVisible("cu") && !groups.isVisible("cd"));
        groups.clear(); check(groups.isCButtonsVisible() && groups.isDpadVisible());
        check(TouchLayout.resizedScale(1,100,100,150,150)==1.5f);
        check(TouchLayout.resizedScale(1,100,100,100,100)==1);
        check(TouchLayout.resizedScale(1,200,100,300,150)==1.5f);
        check(TouchLayout.resizedScale(1,100,100,-100,-100)==.5f);
        check(TouchLayout.resizedScale(1,100,100,1000,1000)==2);
        check(TouchLayout.resizedScale(1,0,100,100,100)==1);
        check(TouchLayout.resizedScale(1,100,100,Float.NaN,100)==1);
        check(TouchLayout.decode("v2;!eye;!settings;!bad-key").isVisible("eye"));
        check(TouchLayout.decode("v2;!eye;!settings").isVisible("settings"));
        check(TouchLayout.decode(null).get("a") == null);
        check(TouchLayout.decode("x".repeat(4097)).get("a") == null);
        java.util.Locale.setDefault(java.util.Locale.FRANCE);
        check(TouchLayout.decode(original.encode()).get("a")[0] == .8f);
        System.out.println("Touch layout save/cancel/reset, scale, malformed-data and locale checks passed");
    }
}
