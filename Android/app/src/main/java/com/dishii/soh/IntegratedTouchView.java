package com.dishii.soh;

import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ColorMatrix;
import android.graphics.ColorMatrixColorFilter;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.util.SparseArray;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowInsets;
import java.util.ArrayList;

/** SOH adapter for Ocarina ReTuned's normalized layout/editor and pointer ownership. */
final class IntegratedTouchView extends View {
    private final MainActivity host;
    private final SharedPreferences preferences;
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private Typeface iconTypeface;
    private final Drawable modernCross, modernCrossItems;
    private final RectF modernDpad = new RectF();
    private float lastDpadOpacity = -1;
    private ColorMatrixColorFilter dpadOpacityFilter;
    private final ArrayList<Control> controls = new ArrayList<>();
    private final SparseArray<Control> fingers = new SparseArray<>();
    private final RectF[] editorButtons = {new RectF(), new RectF(), new RectF(), new RectF()};
    private final float[] anchors = new float[30]; // B, three C items, four D-pad items, Navi/C-up, A action
    private TouchLayout placement = new TouchLayout(), saved;
    private int mode, dragPointer = -1, state;
    private int[] bindings;
    private boolean enabled, shown = true, editing, floatingLeft = true, floatingRight = true, suspended, transparentSticks;
    private float scale = 1, opacity = .55f, unit = 1, left, top, right, bottom;
    private String selected = "";
    private float dragX, dragY;
    private Control dragged;
    private int resizeCorner = -1;
    private float resizeStartX, resizeStartY, resizeWidth, resizeHeight, resizeScale, fixedX, fixedY;
    private TouchLayout gestureStart;

    private static final class Control {
        final String key, label;
        final int mask, slot, color, stick;
        final RectF bounds;
        int pointer = -1;
        float cx, cy, dx, dy;
        Control(String key, String label, int mask, int slot, int color, int stick, RectF bounds) {
            this.key = key; this.label = label; this.mask = mask; this.slot = slot; this.color = color;
            this.stick = stick; this.bounds = bounds; cx = bounds.centerX(); cy = bounds.centerY();
        }
    }

    IntegratedTouchView(MainActivity host) {
        super(host); this.host = host;
        preferences = host.getSharedPreferences("soh-integrated-touch-layouts", Context.MODE_PRIVATE);
        modernCross = host.getDrawable(R.drawable.modern_touch_cross).mutate();
        modernCrossItems = host.getDrawable(R.drawable.modern_touch_cross_items).mutate();
        try {
            paint.setTypeface(Typeface.createFromAsset(host.getAssets(), "fonts/FiraSansCondensed-Bold.ttf"));
        } catch (RuntimeException missingFont) {
            paint.setTypeface(Typeface.create("sans-serif-condensed", Typeface.BOLD));
        }
        try {
            iconTypeface = Typeface.createFromAsset(host.getAssets(), "fonts/MaterialSymbolsRounded-Regular.ttf");
        } catch (RuntimeException missingFont) { iconTypeface = null; }
        setFocusable(false); setContentDescription("Integrated touch controller");
        setVisibility(GONE);
    }

    void configure(int nextMode, boolean enabled, boolean floatingLeft, boolean floatingRight, float scale, float opacity, boolean transparentSticks) {
        if (mode != nextMode) {
            cancelInputs(); editing = false; mode = nextMode;
            placement = TouchLayout.decode(preferences.getString("preset" + mode, ""));
            shown = true;
        }
        this.enabled = enabled && mode > 0;
        bindings = host.integratedTouchBindings(mode);
        this.floatingLeft = floatingLeft;
        this.floatingRight = floatingRight;
        this.transparentSticks = transparentSticks;
        this.scale = Math.max(.75f, Math.min(1.5f, scale));
        this.opacity = Math.max(.15f, Math.min(1, opacity));
        setVisibility(this.enabled ? VISIBLE : GONE);
        cancelInputs(); layoutControls(); invalidate();
    }

    void resume() { suspended = false; invalidate(); }
    void suspend() { suspended = true; if (editing) finishEditing(false); cancelInputs(); host.integratedTouchReset(); }
    boolean cancelEditing() { if (!editing) return false; finishEditing(false); return true; }
    void startEditing() {
        if (!enabled || editing) return;
        cancelInputs(); saved = placement.copy(); editing = true; selected = "";
        layoutControls(); invalidate();
        announceForAccessibility("Drag controls to move them. Select a control and drag a corner handle to resize. Save, Reset, Cancel and Hide or Show are at the top.");
    }
    private void finishEditing(boolean save) {
        if (save) preferences.edit().putString("preset" + mode, placement.encode()).apply();
        else placement = saved;
        editing = false; dragged = null; dragPointer = -1; resizeCorner = -1; gestureStart = null;
        cancelInputs(); layoutControls(); invalidate();
    }

    private void add(String key, String label, int mask, int slot, int color,
                     float x, float y, float width, float height, int stick) {
        int bindingIndex = TouchBindings.index(key);
        if (bindingIndex >= 0 && bindings != null && bindings.length == TouchBindings.KEYS.length) {
            int action = bindings[bindingIndex];
            if (action == 0 && !editing) return;
            if (key.equals("fairy") && action != TouchBindings.NAVI) label = "Item";
            mask = TouchBindings.mask(action, (state & 4) != 0, (state & 64) != 0);
            slot = TouchBindings.slot(action, (state & 4) != 0);
        }
        float[] p = mode == 3 && isDpadDirection(key) ? null : placement.get(key);
        float s = p == null ? 1 : p[2];
        boolean sharedFooter = mode == 3 && (key.equals("settings") || key.equals("start") ||
                key.equals("map") || key.equals("cu"));
        // Modern's other controls use ReTuned's 16-unit margin. This shared row
        // uses GameCube's 12-unit margin too, including at larger UI scales.
        float adjustment = sharedFooter ? 4*unit : 0;
        float insetLeft=left-adjustment,insetRight=right-adjustment,insetTop=top-adjustment,insetBottom=bottom-adjustment;
        float w = Math.min(width * unit * s, getWidth() - insetLeft - insetRight);
        float h = Math.min(height * unit * s, getHeight() - insetTop - insetBottom);
        float cx = p == null ? x * getWidth() : p[0] * getWidth();
        float cy = p == null ? y * getHeight() : p[1] * getHeight();
        cx = Math.max(insetLeft + w/2, Math.min(getWidth() - insetRight - w/2, cx));
        cy = Math.max(insetTop + h/2, Math.min(getHeight() - insetBottom - h/2, cy));
        controls.add(new Control(key, label, mask, slot, color, stick, new RectF(cx-w/2,cy-h/2,cx+w/2,cy+h/2)));
    }
    private void face(String key, String label, int mask, int slot, int color, float x, float y, float size) {
        add(key, label, mask, slot, color, x, y, size, size, -1);
    }
    private void dockedFace(String key, String label, int mask, int slot, int color,
                            float rightOffset, float bottomOffset, float size) {
        // Dusklight's GameCube cluster uses fixed edge offsets instead of stretching
        // the button spacing with the display's aspect ratio. Saved centers still win.
        face(key,label,mask,slot,color,
                (getWidth()-(rightOffset+size/2)*unit)/getWidth(),
                (getHeight()-(bottomOffset+size/2)*unit)/getHeight(),size);
    }

    private void layoutControls() {
        controls.clear();
        if (getWidth() <= 0 || getHeight() <= 0 || !enabled) return;
        float density = getResources().getDisplayMetrics().density;
        unit = scale * density * Math.max(.82f, Math.min(1.35f, getHeight()/(390*density)));
        left = right = bottom = top = (mode == 3 ? 16 : 12) * unit;
        WindowInsets insets = getRootWindowInsets();
        if (insets != null && android.os.Build.VERSION.SDK_INT >= 30) {
            android.graphics.Insets safe = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            left += safe.left; right += safe.right; top += safe.top; bottom += safe.bottom;
        }
        final int gray = 0xff626b78, yellow = 0xffdfb52b;
        if (shown || editing) {
            if (mode == 1) {
                face("a", "A", 0x8000, 9, 0xff346bcc, .79f,.80f,52);
                face("b", "B", 0x4000, 0, 0xff38a05f, .70f,.69f,44);
                face("cl", "◀", 2, 1, yellow, .84f,.54f,36);
                face("cd", "▼", 4, 2, yellow, .90f,.66f,36);
                face("cr", "▶", 1, 3, yellow, .96f,.54f,36);
                face("cu", "▲", 8, 8, yellow, .90f,.42f,36);
                add("z", "Z", 0x2000,-1,gray,.10f,.13f,64,32,-1);
                add("l", "L", 0x20,-1,gray,.10f,.25f,64,30,-1);
                add("r", "R", 0x10,-1,gray,.90f,.13f,64,32,-1);
            } else if (mode == 2) {
                dockedFace("a", "A",0x8000,9,0xff22707b,62,64,74);
                dockedFace("b", "B",0x4000,0,0xffa13d42,158,48,58);
                dockedFace("cl", "Y",2,1,0xff715b96,124,138,58);
                dockedFace("cr", "X",1,3,0xff537397,28,144,58);
                float triggerX=(getWidth()-63*unit)/getWidth();
                add("cd", "Z",4,2,0xff764f9e,triggerX,95*unit/getHeight(),78,46,-1);
                face("cu", "C↑", 8,8,yellow,.69f,.47f,28);
                add("z", "L",0x2000,-1,gray,63*unit/getWidth(),41*unit/getHeight(),78,46,-1);
                add("r", "R",0x10,-1,gray,triggerX,41*unit/getHeight(),78,46,-1);
                add("l", "Extra",0x20,-1,gray,.10f,.25f,52,27,-1);
            } else {
                // Match ReTuned's Nintendo/Modern preset in density-independent,
                // edge-anchored coordinates rather than stretching a diamond.
                float[] face=TouchLayout.modernFaceCenters(getWidth(),getHeight(),right,bottom,unit);
                face("a","A",0x8000,9,0xff426e54,face[0]/getWidth(),face[1]/getHeight(),44);
                face("b","B",0x4000,0,0xff85535b,face[2]/getWidth(),face[3]/getHeight(),44);
                face("cl","X",2,1,0xff4d6d91,face[4]/getWidth(),face[5]/getHeight(),44);
                face("cd","Y",4,2,0xff918157,face[6]/getWidth(),face[7]/getHeight(),44);
                float lx=(left+31.5f*unit)/getWidth(), rx=(getWidth()-right-31.5f*unit)/getWidth();
                add("z","ZL",0x2000,-1,gray,lx,(top+17.25f*unit)/getHeight(),63,34.5f,-1);
                add("l","L",0x20,-1,gray,lx,(top+61.75f*unit)/getHeight(),63,34.5f,-1);
                add("cr","ZR",1,3,gray,rx,(top+17.25f*unit)/getHeight(),63,34.5f,-1);
                add("r","R",0x10,-1,gray,rx,(top+61.75f*unit)/getHeight(),63,34.5f,-1);
            }
            // D-pad items use SOH's four existing extra equipment slots.
            if (mode == 3) {
                float padTop=TouchLayout.modernDpadTop(getHeight(),top,bottom,unit);
                add("pad","D-pad",0,-1,gray,(left+48*unit)/getWidth(),(padTop+48*unit)/getHeight(),96,96,-1);
                modernDpad.set(find("pad").bounds);
                float arm=modernDpad.width()/3, armUnits=arm/unit;
                face("du","▲",0x800,4,gray,modernDpad.centerX()/getWidth(),(modernDpad.top+arm/2)/getHeight(),armUnits);
                face("dd","▼",0x400,5,gray,modernDpad.centerX()/getWidth(),(modernDpad.bottom-arm/2)/getHeight(),armUnits);
                face("dl","◀",0x200,6,gray,(modernDpad.left+arm/2)/getWidth(),modernDpad.centerY()/getHeight(),armUnits);
                face("dr","▶",0x100,7,gray,(modernDpad.right-arm/2)/getWidth(),modernDpad.centerY()/getHeight(),armUnits);
            } else {
                face("du","▲",0x800,4,gray,.12f,.43f,28);
                face("dd","▼",0x400,5,gray,.12f,.59f,28);
                face("dl","◀",0x200,6,gray,.075f,.51f,28);
                face("dr","▶",0x100,7,gray,.165f,.51f,28);
            }
            add("start","Start",0x1000,-1,gray,.54f,.91f,66,28,-1);
            add("settings","Settings",0,-1,gray,.42f,.91f,72,28,-1);
            if (mode == 2 || mode == 3 || (mode == 1 && (state & 32) != 0)) {
                Control start = find("start"), settings = find("settings");
                float gap = start != null && settings != null
                        ? Math.max(8*unit,start.bounds.left-settings.bounds.right) : 8*unit;
                float mapX = start == null ? .63f : (start.bounds.right+gap+18*unit)/getWidth();
                float mapY = start == null ? .91f : start.bounds.centerY()/getHeight();
                add("map","Map",0x10000,-1,gray,mapX,mapY,36,28,-1);
                if (mode == 2 || mode == 3) {
                    float fairyX = settings == null ? .28f : (settings.bounds.left-gap-18*unit)/getWidth();
                    float fairyY = settings == null ? .91f : settings.bounds.centerY()/getHeight();
                    add(mode==3?"cu":"fairy","Fairy",8,8,gray,fairyX,fairyY,36,28,-1);
                }
            }
            add("move","Move",0,-1,gray,mode==3?(left+75*unit)/getWidth():.15f,
                    mode==3?(getHeight()-bottom-75*unit)/getHeight():.80f,mode==3?150:132,mode==3?150:132,0);
            if (mode != 1 || editing || (state & 16) != 0)
                add("look","Look",0,-1,gray,mode==3?.62f:.59f,mode==3?.62f:.69f,mode==3?150:120,mode==3?150:120,1);
        }
        face("eye","◉",0,-1,gray,mode==3?(getWidth()-right-15*unit)/getWidth():.95f,
                mode==3?(getHeight()-bottom-15*unit)/getHeight():.92f,mode==3?30:28);
        publishLayout();
    }

    private void publishLayout() {
        java.util.Arrays.fill(anchors, 0);
        boolean naviUtilityIcon = false;
        for (Control c : controls) if (c.slot >= 0 && placement.isVisible(c.key)) {
            anchors[c.slot*3] = c.bounds.centerX()/getWidth();
            anchors[c.slot*3+1] = c.bounds.centerY()/getHeight();
            anchors[c.slot*3+2] = Math.min(c.bounds.width(), c.bounds.height())*.76f/getHeight();
            if (c.slot == 8) naviUtilityIcon = c.key.equals("fairy") || c.key.equals("map") || (mode==3&&c.key.equals("cu"));
        }
        host.integratedTouchLayout(anchors, enabled && shown && !editing && !suspended && (state & 1) == 0, naviUtilityIcon);
    }

    private void release(Control c) {
        if (c.stick == 0) host.integratedTouchStick(0,0);
        else if (c.stick == 1) host.integratedLook(0,0,false);
        else if (c.mask != 0) host.integratedTouchButton(c.mask,false);
        c.pointer = -1; c.dx = c.dy = 0;
    }
    private void cancelInputs() {
        for (int i=0;i<fingers.size();i++) release(fingers.valueAt(i));
        fingers.clear(); host.integratedTouchReset();
    }
    private void move(Control c, float x, float y) {
        float radius = Math.min(c.bounds.width(),c.bounds.height())*.34f;
        c.dx=(x-c.cx)/radius; c.dy=(y-c.cy)/radius;
        float length=(float)Math.hypot(c.dx,c.dy);
        if(length>1){c.dx/=length;c.dy/=length;}
        if(c.stick==0) host.integratedTouchStick(Math.round(c.dx*85),Math.round(-c.dy*85));
        else host.integratedLook(c.dx,c.dy,true);
    }
    private boolean isFloating(Control c) {
        return c.stick == 0 ? floatingLeft : c.stick == 1 && floatingRight;
    }
    private static boolean isDpadDirection(String key) {
        return key.equals("du") || key.equals("dd") || key.equals("dl") || key.equals("dr");
    }
    private boolean controlVisible(String key) {
        return key.equals("pad") ? placement.isDpadVisible() : placement.isVisible(key);
    }
    private void drawModernDpad(Canvas canvas) {
        if (mode != 3 || !(shown || editing) || (!editing && ((state&1)!=0 || !placement.isDpadVisible()))) return;
        float alpha = editing ? (placement.isDpadVisible() ? .75f : .25f) : opacity;
        if (alpha != lastDpadOpacity) {
            lastDpadOpacity=alpha;
            dpadOpacityFilter=new ColorMatrixColorFilter(new ColorMatrix(new float[]{
                1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,alpha/.28f,0}));
        }
        Drawable cross=!editing && (state&0xf000)!=0 ? modernCrossItems : modernCross;
        cross.setBounds(Math.round(modernDpad.left),Math.round(modernDpad.top),Math.round(modernDpad.right),Math.round(modernDpad.bottom));
        cross.setColorFilter(dpadOpacityFilter);
        int save=canvas.save();
        if (!editing) for(Control c:controls) if(isDpadDirection(c.key)&&!placement.isVisible(c.key)) canvas.clipOutRect(c.bounds);
        cross.draw(canvas);canvas.restoreToCount(save);
    }
    @Override protected void onSizeChanged(int w,int h,int ow,int oh) { cancelInputs(); layoutControls(); }
    @Override protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        if (!enabled || suspended) return;
        int next = host.integratedTouchState();
        if (next != state) {
            // Icon/action changes affect lettering, not pointer ownership or held input.
            boolean sceneChanged = ((next ^ state) & 255) != 0;
            if (((next ^ state) & (8|64|128)) != 0) bindings = host.integratedTouchBindings(mode);
            state=next;
            if (sceneChanged) { cancelInputs(); layoutControls(); }
        }
        if (editing) { paint.setColor(0xee080b12); canvas.drawRect(0,0,getWidth(),getHeight(),paint); }
        drawModernDpad(canvas);
        for (Control c : controls) {
            if (mode==3 && (c.key.equals("pad") || isDpadDirection(c.key))) continue;
            boolean visible = controlVisible(c.key);
            if (!editing && !visible) continue;
            // The N64 layout keeps its original C-buttons; free camera is a
            // touch-only right-side region with no circle or knob drawn in play.
            if (!editing && mode == 1 && c.stick == 1) continue;
            if (!editing && (state&1)!=0 && !c.key.equals("settings") && !c.key.equals("eye")) continue;
            boolean down=c.pointer>=0;
            if(c.stick>=0 && !editing && isFloating(c) && !down) continue;
            paint.setStyle(Paint.Style.FILL);
            // Item-bearing centers remain transparent so native HD icon textures show through.
            boolean hasContent = !editing && c.slot >= 0 && (state & (1 << (8+c.slot))) != 0;
            int alpha = editing ? (visible ? 190 : 45) : Math.round(255 * opacity * (hasContent ? .12f : .70f));
            boolean transparentBase = c.stick >= 0 && (transparentSticks || isFloating(c)) && !editing;
            if (transparentBase) alpha = 0;
            paint.setColor((c.color&0xffffff)|(alpha<<24));
            if(c.stick>=0 || Math.abs(c.bounds.width()-c.bounds.height())<.5f)canvas.drawOval(c.bounds,paint);
            else canvas.drawRoundRect(c.bounds,12*unit,12*unit,paint);
            paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth((selected.equals(c.key)?3:1.5f)*unit);
            paint.setColor(editing&&selected.equals(c.key)?0xffffcf64:editing&&!visible?0xff777777:((Math.round(opacity*255)<<24)|(c.color&0xffffff)));
            if (transparentBase) paint.setColor(Color.TRANSPARENT);
            if(c.stick>=0 || Math.abs(c.bounds.width()-c.bounds.height())<.5f)canvas.drawOval(c.bounds,paint);
            else canvas.drawRoundRect(c.bounds,12*unit,12*unit,paint);
            paint.setStyle(Paint.Style.FILL);paint.setColor(Color.WHITE);
            float buttonScale = Math.min(c.bounds.width(),c.bounds.height()) / (c.key.equals("a") && mode==2 ? 74*unit : 58*unit);
            boolean faceLetter = (c.slot >= 0 || c.mask == 0x01000000) && c.label.length() == 1;
            paint.setTextAlign(hasContent ? Paint.Align.RIGHT : Paint.Align.CENTER);
            paint.setTextSize((faceLetter ? (hasContent ? 13 : c.key.equals("a") && mode==2 ? 31 : 24)*buttonScale : 13)*unit);
            if(c.stick>=0&&!editing) {
                canvas.drawCircle(c.cx+c.dx*c.bounds.width()*.34f,c.cy+c.dy*c.bounds.height()*.34f,12*unit,paint);
            } else if ((c.key.equals("fairy") || c.key.equals("map") || (mode==3&&c.key.equals("cu"))) && (c.slot == 8 || c.mask == 0x10000)) {
                Typeface letters = paint.getTypeface();
                if (iconTypeface != null) paint.setTypeface(iconTypeface);
                paint.setTextAlign(Paint.Align.CENTER);
                paint.setTextSize(Math.min(c.bounds.width(), c.bounds.height()) * .72f);
                paint.setColor(c.slot == 8 && hasContent ? 0xffffdf79 : Color.WHITE);
                String glyph = iconTypeface == null ? (c.slot == 8 ? "✦" : "▧") : (c.slot == 8 ? "\ue65f" : "\ue55b");
                canvas.drawText(glyph,c.bounds.centerX(),c.bounds.centerY()-(paint.ascent()+paint.descent())/2,paint);
                paint.setTypeface(letters);
            } else if (!(hasContent && c.key.equals("fairy"))) {
                float y=hasContent?c.bounds.bottom-6*unit*buttonScale-paint.descent():c.bounds.centerY()-(paint.ascent()+paint.descent())/2;
                float x=hasContent?c.bounds.right-6*unit*buttonScale:c.bounds.centerX();
                canvas.drawText(c.label + (editing&&!visible?" (off)":""),x,y,paint);
            }
        }
        if(editing) {
            paint.setTextAlign(Paint.Align.CENTER);
            Control selectedControl = find(selected);
            if (selectedControl != null) {
                RectF frame = new RectF(selectedControl.bounds);
                frame.inset(-4*unit,-4*unit);
                paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(1.5f*unit);paint.setColor(0xffffcf64);
                canvas.drawRect(frame,paint);
                paint.setStyle(Paint.Style.FILL);
                for(int corner=0;corner<4;corner++) {
                    float x=(corner&1)==0?frame.left:frame.right;
                    float y=(corner&2)==0?frame.top:frame.bottom;
                    paint.setColor(0xff273340);canvas.drawCircle(x,y,8*unit,paint);
                    paint.setStyle(Paint.Style.STROKE);paint.setColor(0xffffcf64);canvas.drawCircle(x,y,8*unit,paint);
                    paint.setStyle(Paint.Style.FILL);
                }
            }
            boolean canHide = !selected.isEmpty() && !selected.equals("settings") && !selected.equals("eye");
            String[] names={"Save","Reset","Cancel",canHide&&!controlVisible(selected)?"Show":"Hide"};
            float panelUnit = Math.min(unit, getWidth()/500f);
            float gap=8*panelUnit,width=Math.min(90*panelUnit,(getWidth()-left-right-3*gap)/4);
            float start=(getWidth()-4*width-3*gap)/2, panelY=top+32*panelUnit;
            for(int i=0;i<4;i++) {
                RectF b=editorButtons[i];b.set(start+i*(width+gap),panelY,start+i*(width+gap)+width,panelY+40*panelUnit);
                paint.setColor(i==0?0xff66572c:i==3&&!canHide?0xff20252d:0xff2b3a4b);
                canvas.drawRoundRect(b,5*unit,5*unit,paint);
                paint.setColor(i==3&&!canHide?0xff888888:Color.WHITE);paint.setTextSize(14*panelUnit);
                float textWidth=paint.measureText(names[i]);
                if(textWidth>width-10*panelUnit)paint.setTextSize(paint.getTextSize()*(width-10*panelUnit)/textWidth);
                canvas.drawText(names[i],b.centerX(),b.centerY()-(paint.ascent()+paint.descent())/2,paint);
            }
            paint.setColor(Color.WHITE);paint.setTextSize(12*panelUnit);
            canvas.drawText(selectedControl==null?"Select a control · Drag to move · Drag corner handles to resize":
                    "Selected: "+controlName(selectedControl)+" · "+(controlVisible(selected)?"On":"Off"),
                    getWidth()/2,panelY-12*panelUnit,paint);
        }
        publishLayout(); postInvalidateOnAnimation();
    }

    private boolean editorTouch(MotionEvent e) {
        int action=e.getActionMasked();
        if(action==MotionEvent.ACTION_DOWN) {
            float x=e.getX(),y=e.getY();
            for(int i=0;i<4;i++)if(editorButtons[i].contains(x,y)) {
                if(i==0)finishEditing(true);
                else if(i==1){placement.clear();selected="";layoutControls();}
                else if(i==2)finishEditing(false);
                else if(i==3)toggleSelectedVisibility();
                invalidate();return true;
            }
            dragged=null;resizeCorner=-1;gestureStart=placement.copy();
            Control current=find(selected);
            if(current!=null) {
                RectF frame=new RectF(current.bounds);frame.inset(-4*unit,-4*unit);
                for(int corner=0;corner<4;corner++) {
                    float hx=(corner&1)==0?frame.left:frame.right;
                    float hy=(corner&2)==0?frame.top:frame.bottom;
                    if(Math.hypot(x-hx,y-hy)<=16*unit) {
                        dragged=current;resizeCorner=corner;dragPointer=e.getPointerId(0);
                        resizeStartX=x;resizeStartY=y;resizeWidth=current.bounds.width();resizeHeight=current.bounds.height();
                        float[] old=placement.get(selected);resizeScale=old==null?1:old[2];
                        fixedX=(corner&1)==0?current.bounds.right:current.bounds.left;
                        fixedY=(corner&2)==0?current.bounds.bottom:current.bounds.top;
                        return true;
                    }
                }
            }
            for(Control c:controls)if(c.stick<0&&c.bounds.contains(x,y)){dragged=c;break;}
            if(dragged==null)for(Control c:controls)if(c.bounds.contains(x,y)){dragged=c;break;}
            if(dragged!=null){selected=dragged.key;dragPointer=e.getPointerId(0);dragX=x-dragged.bounds.centerX();dragY=y-dragged.bounds.centerY();}
        } else if(action==MotionEvent.ACTION_MOVE && dragged!=null) {
            int index=e.findPointerIndex(dragPointer);
            if(index>=0) {
                if(resizeCorner>=0) {
                    float sx=(resizeCorner&1)==0?-1:1,sy=(resizeCorner&2)==0?-1:1;
                    float next=TouchLayout.resizedScale(resizeScale,resizeWidth,resizeHeight,
                            resizeWidth+sx*(e.getX(index)-resizeStartX),resizeHeight+sy*(e.getY(index)-resizeStartY));
                    float ratio=next/resizeScale;
                    placement.set(selected,(fixedX+sx*resizeWidth*ratio/2)/getWidth(),
                            (fixedY+sy*resizeHeight*ratio/2)/getHeight(),next);
                } else {
                    float[] old=placement.get(selected);
                    placement.set(selected,(e.getX(index)-dragX)/getWidth(),(e.getY(index)-dragY)/getHeight(),old==null?1:old[2]);
                }
                layoutControls();
            }
        } else if(action==MotionEvent.ACTION_UP||action==MotionEvent.ACTION_CANCEL ||
                (action==MotionEvent.ACTION_POINTER_UP&&e.getPointerId(e.getActionIndex())==dragPointer)) {
            if(action==MotionEvent.ACTION_CANCEL&&gestureStart!=null){placement=gestureStart;layoutControls();}
            dragged=null;dragPointer=-1;resizeCorner=-1;gestureStart=null;
        }
        invalidate();return true;
    }
    private String controlName(Control c) {
        if (mode == 2 || mode == 3) return c.label;
        switch(c.key) {
            case "cu": return "C-up / Navi"; case "cl": return "C-left";
            case "cd": return "C-down"; case "cr": return "C-right";
            case "du": return "D-pad up"; case "dd": return "D-pad down";
            case "dl": return "D-pad left"; case "dr": return "D-pad right";
            default: return c.label;
        }
    }
    private void toggleSelectedVisibility() {
        final String key=selected;
        Control c=find(key);
        if(!editing||c==null||key.equals("settings")||key.equals("eye"))return;
        boolean visible=!controlVisible(key);
        if(key.equals("pad")) {
            placement.setDpadVisible(visible);
        } else {
            placement.setVisible(key,visible);
        }
        layoutControls();invalidate();
        announceForAccessibility((visible?"Shown ":"Hidden ")+controlName(c));
    }
    private Control find(String key){for(Control c:controls)if(c.key.equals(key))return c;return null;}
    @Override public boolean onTouchEvent(MotionEvent e) {
        if(!enabled||suspended)return false;
        if(editing)return editorTouch(e);
        int action=e.getActionMasked(),index=e.getActionIndex(),id=e.getPointerId(index);
        if(action==MotionEvent.ACTION_DOWN||action==MotionEvent.ACTION_POINTER_DOWN) {
            float x=e.getX(index),y=e.getY(index);Control chosen=null;
            for(Control c:controls)if(!c.key.equals("pad")&&placement.isVisible(c.key)&&c.stick<0&&c.pointer<0&&c.bounds.contains(x,y)&&
                    ((state&1)==0||c.key.equals("settings")||c.key.equals("eye"))){chosen=c;break;}
            // Fixed sticks use their editable bounds. Floating sticks use their
            // screen side, not the decorative/editor circle's old hit rectangle.
            if(chosen==null && (state&1)==0)for(Control c:controls)
                if(placement.isVisible(c.key)&&c.stick>=0&&!isFloating(c)&&c.pointer<0&&c.bounds.contains(x,y)){chosen=c;break;}
            if(chosen==null && (state&1)==0)for(Control c:controls)
                if(placement.isVisible(c.key)&&c.stick>=0&&isFloating(c)&&c.pointer<0&&
                        TouchLayout.floatingStickContains(c.stick,x/getWidth(),y/getHeight())){chosen=c;break;}
            if(chosen==null)return fingers.size()>0;
            if(chosen.key.equals("eye")){cancelInputs();shown=!shown;layoutControls();return true;}
            if(chosen.key.equals("settings")){cancelInputs();host.nativeGamepadBackPressed();return true;}
            chosen.pointer=id;fingers.put(id,chosen);
            if(chosen.stick>=0){if(isFloating(chosen)){chosen.cx=x;chosen.cy=y;}move(chosen,x,y);}
            else if((state&1)!=0)host.integratedMenuButton(chosen.mask,true);
            else host.integratedTouchButton(chosen.mask,true);
            invalidate();return true;
        }
        if(action==MotionEvent.ACTION_MOVE){for(int i=0;i<e.getPointerCount();i++){Control c=fingers.get(e.getPointerId(i));if(c!=null&&c.stick>=0)move(c,e.getX(i),e.getY(i));}invalidate();return fingers.size()>0;}
        if(action==MotionEvent.ACTION_UP||action==MotionEvent.ACTION_POINTER_UP){Control c=fingers.get(id);if(c!=null){host.integratedMenuButton(c.mask,false);release(c);fingers.remove(id);invalidate();return true;}}
        if(action==MotionEvent.ACTION_CANCEL){cancelInputs();layoutControls();return true;}
        return fingers.size()>0;
    }
}
