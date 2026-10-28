package com.dishii.soh;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.LinkedHashSet;
import java.util.Set;

/** Adapted from Ocarina ReTuned's normalized, transactional touch-layout model. */
final class TouchLayout {
    private final Map<String, float[]> controls = new LinkedHashMap<>();
    private final Set<String> hidden = new LinkedHashSet<>();
    float[] get(String key) { return controls.get(key); }
    boolean isVisible(String key) { return !hidden.contains(key); }
    void setVisible(String key, boolean visible) {
        if (!key.matches("[a-z]{1,16}") || key.equals("eye") || key.equals("settings")) return;
        if (visible) hidden.remove(key); else hidden.add(key);
    }
    boolean isDpadVisible() { return isVisible("du") || isVisible("dd") || isVisible("dl") || isVisible("dr"); }
    void setDpadVisible(boolean visible) {
        for (String key : new String[]{"du", "dd", "dl", "dr"}) setVisible(key, visible);
    }
    boolean isCButtonsVisible() { return isVisible("cu") || isVisible("cd") || isVisible("cl") || isVisible("cr"); }
    void setCButtonsVisible(boolean visible) {
        for (String key : new String[]{"cu", "cd", "cl", "cr"}) setVisible(key, visible);
    }
    void clear() { controls.clear(); hidden.clear(); }
    static boolean floatingStickContains(int stick, float x, float y) {
        if (!Float.isFinite(x) || !Float.isFinite(y) || x < 0 || x > 1 || y < 0 || y > 1) return false;
        return stick == 0 ? x < .5f : stick == 1 && x >= .5f;
    }
    static float[] modernFaceCenters(float width, float height, float right, float bottom, float unit) {
        float x=width-right-93*unit, y=height-bottom-93*unit;
        return new float[]{x+44*unit,y, x,y+44*unit, x,y-44*unit, x-44*unit,y};
    }
    static float modernDpadTop(float height, float top, float bottom, float unit) {
        return Math.max(top+114*unit,height-bottom-252*unit);
    }
    static float resizedScale(float original, float width, float height, float requestedWidth, float requestedHeight) {
        if (!Float.isFinite(original) || !Float.isFinite(width) || !Float.isFinite(height) ||
                !Float.isFinite(requestedWidth) || !Float.isFinite(requestedHeight) || width <= 0 || height <= 0) return 1;
        float ratio = (requestedWidth * width + requestedHeight * height) / (width * width + height * height);
        return Math.max(.5f, Math.min(2, original * ratio));
    }
    TouchLayout copy() { return decode(encode()); }
    void set(String key, float x, float y, float scale) {
        if (!key.matches("[a-z]{1,16}") || !Float.isFinite(x) || !Float.isFinite(y) || !Float.isFinite(scale)) return;
        controls.put(key, new float[]{Math.max(0, Math.min(1, x)), Math.max(0, Math.min(1, y)),
                Math.max(.5f, Math.min(2, scale))});
    }
    String encode() {
        StringBuilder value = new StringBuilder("v2");
        for (Map.Entry<String, float[]> entry : controls.entrySet()) {
            float[] p = entry.getValue();
            value.append(';').append(entry.getKey()).append('=').append(p[0]).append(',').append(p[1]).append(',').append(p[2]);
        }
        for (String key : hidden) value.append(";!").append(key);
        return value.toString();
    }
    static TouchLayout decode(String value) {
        TouchLayout result = new TouchLayout();
        if (value == null || value.length() > 4096) return result;
        String[] fields = value.split(";", -1);
        boolean visibilityFormat = fields[0].equals("v2");
        if (!visibilityFormat && !fields[0].equals("v1")) return result;
        for (int i = 1; i < fields.length; i++) {
            if (visibilityFormat && fields[i].startsWith("!")) {
                result.setVisible(fields[i].substring(1), false);
                continue;
            }
            String[] pair = fields[i].split("=", -1);
            if (pair.length != 2) continue;
            String[] p = pair[1].split(",", -1);
            if (p.length != 3) continue;
            try { result.set(pair[0], Float.parseFloat(p[0]), Float.parseFloat(p[1]), Float.parseFloat(p[2])); }
            catch (NumberFormatException ignored) { }
        }
        return result;
    }
}
