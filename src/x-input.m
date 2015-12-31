/* x-input.m -- event handling
 *
 * Copyright (c) 2002-2011 Apple Inc. All Rights Reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "quartz-wm.h"
#import "x-screen.h"
#import "x-window.h"
#include "frame.h"
#include "utils.h"

#include <CoreFoundation/CFSocket.h>
#include <CoreFoundation/CFRunLoop.h>

#include <X11/Xatom.h>
#include <X11/keysym.h>
#include <X11/extensions/applewm.h>
#include <X11/extensions/Xrandr.h>

#include <unistd.h>

extern BOOL _proxy_pb;

/* FIXME: .. */
#define DOUBLE_CLICK_TIME 250

#define BUTTON_MASK \
(Button1Mask | Button2Mask | Button3Mask | Button4Mask | Button5Mask)

CFRunLoopSourceRef x_dpy_source;

static struct {
    Window down_id;
    Time down_time;			/* milliseconds */
    X11Point down_location;
    X11Point offset;
    int click_count;
    unsigned int down_attrs;
    unsigned dragging :1;
    unsigned clicking :1;
    unsigned resizing :1;
} pointer_state;

/* Timestamp when the X server last told us it's active */
static Time last_activation_time;

static float
point_distance (X11Point a, X11Point b)
{
    float dx, dy;

    dx = b.x - a.x;
    dy = b.y - a.y;

    return sqrt (dx * dx + dy * dy);
}

static inline int
count_bits (uint32_t x)
{
    x = x - ((x >> 1) & 0x55555555);
    x = (x & 0x33333333) + ((x >> 2) & 0x33333333);
    x = (x + (x >> 4)) & 0x0f0f0f0f;
    x = x + (x >> 8);
    x = x + (x >> 16);
    return x & 63;
}

static inline int
buttons_pressed (unsigned int state)
{
    return count_bits (state & BUTTON_MASK);
}

static void *
list_next (x_list *lst, void *item)
{
    x_list *node;

    node = x_list_find (lst, item);

    if (node != NULL)
    {
        node = node->next;
        if (node == NULL)
            node = lst;
    }

    if (node != NULL && node->data != item)
        return node->data;

    return NULL;
}

static void
next_window (Time timestamp, Bool reversed)
{
    x_window *w, *x;
    x_list *lst;

    w = x_get_active_window ();
    if (w != nil)
    {
        lst = x_list_copy (w->_screen->_window_list);
        if (reversed)
            lst = x_list_reverse (lst);

        x = list_next (lst, w);

        /* Skip minimized windows. */
        while (x != nil && x != w && x->_minimized)
            x = list_next (lst, x);

        [x activate:timestamp];

        x_list_free (lst);
    }
}

static void
x_event_button (XButtonEvent *e)
{
    x_window *w = x_get_window (e->window);

    if (w == nil)
        return;

    if (e->window == w->_id)
    {
        /* Swallow the first activating click. Since the X server activates
         us we need to look at timestamps to handle the case where the
         user activated X by clicking on the already focused window. Use
         a 100ms window for this. */

        if ((!w->_focused || (e->time - last_activation_time) < 100)
            && [w focus:e->time])
        {
            if (w->_always_click_through || focus_click_through)
            {
                XAllowEvents (x_dpy, ReplayPointer, e->time);
                XUngrabPointer (x_dpy, e->time);
            }
            else
            {
                XAllowEvents (x_dpy, AsyncPointer, e->time);
            }
        }
        else
        {
            [w raise];
            XAllowEvents (x_dpy, ReplayPointer, e->time);
            XUngrabPointer (x_dpy, e->time);
        }
    }
    else if (e->button <= 3
             && (e->window == w->_frame_id || e->window == w->_growbox_id))
    {
        unsigned int old_attrs = w->_frame_attr;
        X11Point p = X11PointMake (e->x, e->y);

        if (e->window == w->_growbox_id)
        {
            p.x += w->_growbox_rect.x;
            p.y += w->_growbox_rect.y;
        }

        if (e->type == ButtonPress)
        {
            if (buttons_pressed (e->state) == 0)
            {
                /* First button press */

                /* FIXME: wrap around? */
                if (e->time - pointer_state.down_time < DOUBLE_CLICK_TIME)
                    pointer_state.click_count++;
                else
                    pointer_state.click_count = 1;

                pointer_state.down_location.x = e->x_root;
                pointer_state.down_location.y = e->y_root;
                pointer_state.down_id = e->window;
                pointer_state.down_time = e->time;
                pointer_state.down_attrs = [w hit_test_frame:p];

                if ((pointer_state.down_attrs
                     & (w->_frame_attr & XP_FRAME_ATTRS_ANY_BUTTON)) != 0)
                {
                    pointer_state.clicking = YES;
                    XP_FRAME_ATTR_SET_CLICKED (w->_frame_attr,
                                               pointer_state.down_attrs
                                               & XP_FRAME_ATTRS_ANY_BUTTON);
                }
                else
                {
                    [w focus:e->time raise:!(e->state & x_meta_mod)];
                }
            }
        }
        else if (e->type == ButtonRelease)
        {
            if (buttons_pressed (e->state) == 1)
            {
                /* Releasing last button */

                if (pointer_state.dragging)
                {
#if MAC_OS_X_VERSION_MIN_REQUIRED >= 1050
                    qwm_dock_drag_end([w get_osx_id]);
#endif
                    pointer_state.dragging = NO;
                }
                else if (pointer_state.resizing)
                {
                    pointer_state.resizing = NO;
                    [w remove_resizing_title];
                }
                else if (pointer_state.clicking)
                {
                    unsigned int attrs;

                    /* Test the release location */
                    attrs = [w hit_test_frame:p];

                    /* Only if it went pressed the same button it came released on */
                    attrs &= pointer_state.down_attrs;

                    if (attrs & XP_FRAME_ATTR_CLOSE_BOX)
                        [w do_close:e->time];
                    else if (attrs & XP_FRAME_ATTR_COLLAPSE)
                        [w do_collapse];
                    else if (attrs & XP_FRAME_ATTR_ZOOM)
                        [w do_zoom];

                    XP_FRAME_ATTR_UNSET_CLICKED (w->_frame_attr,
                                                 XP_FRAME_ATTRS_ANY_BUTTON);

                    /* Update prelight bit, we ignored tracking events
                     while clickiing. */
                    w->_frame_attr &= ~XP_FRAME_ATTR_PRELIGHT;
                    w->_frame_attr |= attrs & XP_FRAME_ATTR_PRELIGHT;

                    pointer_state.clicking = NO;
                }
                else if (pointer_state.click_count == 2)
                {
                    if (w->_shadable && window_shading)
                        [w do_toggle_shaded:e->time];
                    else if ((w->_frame_attr & XP_FRAME_ATTR_COLLAPSE) &&
                             minimize_on_double_click)
                        [w do_collapse];
                }

                pointer_state.down_id = 0;
            }
        }

        if (w->_frame_attr != old_attrs)
        {
            [w decorate];
        }
    }
}

static void
x_event_motion_notify (XMotionEvent *e)
{
    x_window *w = x_get_window (e->window);

    if (w == nil)
        return;

#if 0
    if (e->window == w->_id)
    {
        XAllowEvents (x_dpy, ReplayPointer, e->time);
        XUngrabPointer (x_dpy, e->time);
    }
    else
#endif
        if (e->window == pointer_state.down_id)
        {
            X11Point p, wp;
            X11Rect r;
            unsigned int old_attrs = w->_frame_attr, attrs;

            Window tem_w;
            unsigned int tem_i;
            int x, y, wx, wy;

            XQueryPointer (x_dpy, e->window, &tem_w, &tem_w,
                           &x, &y, &wx, &wy, &tem_i);

            p = X11PointMake(x, y);
            wp = X11PointMake(wx, wy);

            if (buttons_pressed (e->state) == 0)
            {
                /* We must have missed the button-release */
                if(pointer_state.dragging) {
#if MAC_OS_X_VERSION_MIN_REQUIRED >= 1050
                    qwm_dock_drag_end([w get_osx_id]);
#endif
                    pointer_state.dragging = NO;
                }
                if (pointer_state.resizing) {
                    pointer_state.resizing = NO;
                    [w remove_resizing_title];
                }
            }

            if (pointer_state.dragging)
            {
            do_drag:
                r = X11RectMake(p.x + pointer_state.offset.x, p.y + pointer_state.offset.y,
                                w->_current_frame.width, w->_current_frame.height);
                r = [w->_screen validate_window_position:r titlebar_height:w->_frame_title_height];
#if MAC_OS_X_VERSION_MIN_REQUIRED >= 1050
                qwm_dock_drag_begin([w get_osx_id]);
#endif
                [w resize_frame:r];
            }
            else if (pointer_state.resizing)
            {
            do_resize:
                r = X11RectMake(w->_current_frame.x, w->_current_frame.y,
                                pointer_state.offset.x + (p.x - pointer_state.down_location.x),
                                pointer_state.offset.y + (p.y - pointer_state.down_location.y));
                if (r.width > 0 && r.height > 0)
                {
                    r = [w validate_frame_rect:r from_user:YES];
                    [w resize_frame:r];
                    [w set_resizing_title:r];
                }
            }
            else if (pointer_state.clicking)
            {
                attrs = [w hit_test_frame:wp];

                if ((attrs & XP_FRAME_ATTRS_ANY_BUTTON)
                    != (pointer_state.down_attrs & XP_FRAME_ATTRS_ANY_BUTTON))
                {
                    /* Moved off the button we clicked on, change its state. */

                    XP_FRAME_ATTR_UNSET_CLICKED (w->_frame_attr, XP_FRAME_ATTRS_ANY_BUTTON);
                }
                else
                {
                    XP_FRAME_ATTR_SET_CLICKED (w->_frame_attr,
                                               pointer_state.down_attrs
                                               & XP_FRAME_ATTRS_ANY_BUTTON);
                }
            }
            else
            {
                /* See if we moved far enough to start dragging the window. */

                if ((e->state & BUTTON_MASK) != 0
                    && point_distance (pointer_state.down_location, p) >= DRAG_THRESHOLD)
                {
                    if (e->window == w->_growbox_id)
                    {
                        pointer_state.offset.x = w->_current_frame.width;
                        pointer_state.offset.y = w->_current_frame.height;
                        pointer_state.resizing = YES;
                        goto do_resize;
                    }
                    else if (e->window == w->_frame_id
                             && w->_movable && e->subwindow == None)
                    {
                        pointer_state.offset.x = w->_current_frame.x - pointer_state.down_location.x;
                        pointer_state.offset.y = w->_current_frame.y - pointer_state.down_location.y;
                        pointer_state.dragging = YES;
                        goto do_drag;
                    }
                }
            }

            if (w->_frame_attr != old_attrs)
            {
                [w decorate];
            }
        }
}

static void
x_event_key (XKeyEvent *e)
{
    int grave_code = XKeysymToKeycode (x_dpy, XK_grave);

    if(grave_code != 0 && grave_code == e->keycode && x_meta_mod != 0)
    {
        if(e->state == (ShiftMask | x_meta_mod)) {
            if(e->type == KeyPress)
                next_window (e->time, TRUE);
            XAllowEvents (x_dpy, AsyncKeyboard, e->time);
            return;
        } else if(e->state == x_meta_mod) {
            if(e->type == KeyPress)
                next_window (e->time, FALSE);
            XAllowEvents (x_dpy, AsyncKeyboard, e->time);
            return;
        }
    }
    XAllowEvents (x_dpy, ReplayKeyboard, e->time);
    XUngrabKeyboard (x_dpy, e->time);
}

static void
x_event_property_notify (XPropertyEvent *e)
{
    x_window *w = x_get_window (e->window);

    if (w == nil || e->window != w->_id)
        return;

    [w property_changed:e->atom];
}

static void x_event_client_message (XClientMessageEvent *e) {
    x_window *w = x_get_window(e->window);

    if (w == nil || e->format != 32)
        return;

    if(e->message_type == atoms.wm_change_state) {
        if (e->data.l[0] == IconicState)
            [w do_collapse];
    } else if(e->message_type == atoms.net_active_window) {
        [w focus:x_current_timestamp ()];
    } else if(e->message_type == atoms.net_close_window) {
        [w do_close:x_current_timestamp ()];
    } else if(e->message_type == atoms.net_wm_state) {
        if (e->data.l[1] != 0)
            [w do_net_wm_state_change:e->data.l[0] atom:e->data.l[1]];
        if (e->data.l[2] != 0)
            [w do_net_wm_state_change:e->data.l[0] atom:e->data.l[2]];
    }
}

static void
x_event_destroy_notify (XDestroyWindowEvent *e)
{
    x_window *w = x_get_window (e->window);

    if (w == nil || e->window != w->_id)
        return;

    [w->_screen remove_window:w];
}

static void
x_event_map_request (XMapRequestEvent *e)
{
    x_window *w = x_get_window (e->window);

    if (w == nil)
    {
        XWindowAttributes attr;
        x_screen *s;

        XGetWindowAttributes (x_dpy, e->window, &attr);
        s = x_get_screen (attr.screen);
        if (s == nil)
            return;

        [s adopt_window:e->window initializing:NO];
    }
    else
    {
        /* Remapping a window is the signal to make it become non-iconic. */

        w->_unmapped = NO;
        [w activate:CurrentTime];
    }
}

static void
x_event_reparent_notify (XReparentEvent *e)
{
    x_window *w = x_get_window (e->window);

    if (w == nil || w->_id != e->window || w->_id != e->event)
        return;

    [w->_screen remove_window:w];

    XReparentWindow (x_dpy, e->window, e->parent, e->x, e->y);
}

static void
x_event_unmap_notify (XUnmapEvent *e)
{
    x_window *w = x_get_window (e->window);

    if (w == nil || w->_id != e->window
        || (e->event != w->_id && !e->send_event))
    {
        return;
    }

    w->_unmapped = YES;
    [w->_screen remove_window:w];

    XDeleteProperty (x_dpy, e->window, atoms.wm_state);
}

static void
x_event_focus (XFocusChangeEvent *e)
{
    x_window *w = x_get_window (e->window);

    if (e->detail == NotifyPointer || w == nil)
        return;

    if (e->type == FocusIn)
    {
        [w x_focus_in];
    }
    else if (e->type == FocusOut)
    {
        if (e->detail != NotifyInferior)
        {
            [w x_focus_out];
        }
    }
}

static void
x_event_crossing (XCrossingEvent *e)
{
    x_window *w = x_get_window (e->window);

    if (w == nil)
        return;

    if (e->window == w->_tracking_id)
    {
        if (pointer_state.clicking)
            return;

        if (e->type == EnterNotify)
            w->_frame_attr |= XP_FRAME_ATTR_PRELIGHT;
        else if (e->type == LeaveNotify)
            w->_frame_attr &= ~XP_FRAME_ATTR_PRELIGHT;

        [w decorate];
    }
    else if (e->window == w->_frame_id && focus_follows_mouse)
    {
        if (e->type == EnterNotify)
            [w focus:e->time raise:NO];
    }
}

static void
x_event_configure_notify (XConfigureEvent *e)
{
    x_window *w;
    x_screen *s;

    if (e->send_event) {
        DB("Received ConfigureNotify for %lx from a SendEvent request, ignoring", e->window);
        return;
    }

    w = x_get_window (e->window);

    if (w != nil)
    {
        DB("Received ConfigureNotify for %lx->%lx (%d,%d) %dx%d", e->window, w->_id, e->x, e->y, e->width, e->height);

        X11Rect r = X11RectMake (e->x, e->y, e->width, e->height);

        if (e->window == w->_frame_id)
        {
            [w report_frame_size:r];
        }
    }
    else
    {
        s = x_get_screen_with_root (e->window);

        if (s != nil)
        {
            if(!XRRUpdateConfiguration((XEvent *)e)) {
                asl_log(aslc, NULL, ASL_LEVEL_WARNING, "XRRUpdateConfiguration failed.");
            }

            [s update_geometry];
            [s foreach_window:@selector (validate_position)];
        }
    }
}

static void x_event_configure_request(XConfigureRequestEvent *e) {
    x_window *w = x_get_window (e->window);

    XWindowChanges client_changes, real_frame_changes, *frame_changes;
    unsigned long client_mask, real_frame_mask, *frame_mask;

    if(w != nil && e->window != w->_id)
        w = nil;

    if(w == nil) {
        /* whatever.. */

        client_changes.stack_mode = e->detail;
        client_changes.sibling = e->above;
        client_changes.x = e->x;
        client_changes.y = e->y;
        client_changes.width = e->width;
        client_changes.height = e->height;

        DB("Calling XConfigureWindow: window: %lx, (%d,%d)", e->window, e->x, e->y);

        XConfigureWindow (x_dpy, e->window, e->value_mask, &client_changes);

        return;
    }

    if(e->value_mask & CWBorderWidth)
        w->_xattr.border_width = e->border_width;

    //[w update_shaped];

    client_mask = real_frame_mask = 0;

    frame_changes = w->_reparented ? &real_frame_changes : &client_changes;
    frame_mask = w->_reparented ? &real_frame_mask : &client_mask;

    if (e->value_mask & CWStackMode) {
        frame_changes->stack_mode = e->detail;
        *frame_mask |= CWStackMode;

        if(e->value_mask & CWSibling) {
            frame_changes->sibling = e->above;
            *frame_mask |= CWSibling;
        }
    }

    if(e->value_mask & (CWX | CWY | CWWidth | CWHeight)) {
        X11Rect client_rect = X11RectMake(w->_xattr.x, w->_xattr.y,
                                          w->_xattr.width, w->_xattr.height);
        if (e->value_mask & CWX)
            client_rect.x = e->x;
        if (e->value_mask & CWY)
            client_rect.y = e->y;
        if (e->value_mask & CWWidth)
            client_rect.width = e->width;
        if (e->value_mask & CWHeight)
            client_rect.height = e->height;

        if (e->value_mask & CWX) DB("The following XConfigureWindow will change the window's origin.x");
        if (e->value_mask & CWY) DB("The following XConfigureWindow will change the window's origin.y");
        if (e->value_mask & CWWidth) DB("The following XConfigureWindow will change the window's size.width");
        if (e->value_mask & CWHeight) DB("The following XConfigureWindow will change the window's size.height");
        DB("The following XConfigureWindow will move the client to: (%d,%d) %dx%d", client_rect.x, client_rect.y, client_rect.width, client_rect.height);

        [w resize_client:client_rect];
    }

    if(real_frame_mask) {
        DB("Calling XConfigureWindow for frame: window: %lx", w->_frame_id);

        XConfigureWindow(x_dpy, w->_frame_id,
                         real_frame_mask, &real_frame_changes);
    }

    if(client_mask) {
        DB("Calling XConfigureWindow for client: window: %lx", w->_id);

        XConfigureWindow(x_dpy, w->_id, client_mask, &client_changes);
    }
}

static void
x_event_shape_notify (XShapeEvent *e)
{
    x_window *w = x_get_window (e->window);

    if (w == nil || w->_id != e->window || e->kind != ShapeBounding)
        return;

    w->_shaped = e->shaped ? YES : NO;
    w->_shaped_empty = (e->shaped && (e->width <= 0 || e->height <= 0));

    [w update_shape];
}

static void
x_event_expose (XExposeEvent *e)
{
    x_window *w = x_get_window (e->window);

    if (w == nil || w->_frame_id != e->window)
        return;

    if (e->count == 0)
        [w expose];
}

static void
x_event_colormap_notify (XColormapEvent *e)
{
    x_window *w = x_get_window (e->window);

    if (w == nil || w->_id != e->window || e->new == 0)
        return;

    if (w->_focused)
        [w install_colormaps];
}

static void
x_event_mapping_notify (XMappingEvent *e)
{
    x_update_keymap ();
}

static void
x_event_apple_wm_notify (XAppleWMNotifyEvent *e)
{
    static const char *controller_kinds[] = {
        "Minimizewindow", "ZoomWindow", "CloseWindow",
        "BringAllToFront", "HideWindow", "HideAll", "ShowAll",
        "Unknown", "Unknown", "WindowMenuItem", "WindowMenuNotify",
        "NextWindow", "PreviousWindow",
    };

    static const char *activation_kinds[] = {
        "IsActive", "IsInactive", "ReloadPreferences"
    };

    switch (e->type - x_apple_wm_event_base)
    {
        case AppleWMControllerNotify:
            if (e->kind >= 0 && e->kind < (int) (sizeof (controller_kinds)
                                                 / sizeof (controller_kinds[0])))
            {
                DB("kind %s arg %d", controller_kinds[e->kind], e->arg);
            }
            else
            {
                DB("kind %d arg %d", e->kind, e->arg);
            }

            switch (e->kind)
        {
                x_window *w;

            case AppleWMMinimizeWindow:
            case AppleWMZoomWindow:
            case AppleWMCloseWindow:
            case AppleWMHideWindow:
                w = x_get_active_window ();
                if (w != nil)
                {
                    if (e->kind == AppleWMMinimizeWindow)
                        [w do_collapse];
                    else if (e->kind == AppleWMZoomWindow)
                        [w do_zoom];
                    else if (e->kind == AppleWMCloseWindow)
                        [w do_close:e->time];
                    else if (e->kind == AppleWMHideWindow)
                        [w do_hide];
                }
                break;

            case AppleWMBringAllToFront:
                x_show_all (e->time, NO);
                x_bring_all_to_front (e->time);
                break;

            case AppleWMHideAll:
                x_hide_all (e->time);
                break;

            case AppleWMShowAll:
                x_show_all (e->time, NO);
                break;

            case AppleWMWindowMenuItem:
                x_activate_window_in_menu (e->arg, e->time);
                break;

            case AppleWMWindowMenuNotify:
                /* FIXME: do something? */
                break;

            case AppleWMNextWindow:
                next_window (e->time, FALSE);
                break;

            case AppleWMPreviousWindow:
                next_window (e->time, TRUE);
                break;
        }
            break;

        case AppleWMActivationNotify:
            if (e->kind >= 0 && e->kind < (int) (sizeof (activation_kinds)
                                                 / sizeof (activation_kinds[0])))
            {
                DB("kind %s arg %d", activation_kinds[e->kind], e->arg);
            }
            else
            {
                DB("kind %d arg %d", e->kind, e->arg);
            }

            switch (e->kind)
        {
            case AppleWMIsActive:
                last_activation_time = e->time;
                x_set_is_active (YES);
                break;

            case AppleWMIsInactive:
                x_set_is_active (NO);
                break;

            case AppleWMReloadPreferences:
                prefs_reload = YES;
                break;
        }
            break;
    }
}

static const char *
event_name (int type)
{
    switch (type)
    {
        static char buf[64];

        case KeyPress: return "KeyPress";
        case KeyRelease: return "KeyRelease";
        case ButtonPress: return "ButtonPress";
        case ButtonRelease: return "ButtonRelease";
        case MotionNotify: return "MotionNotify";
        case EnterNotify: return "EnterNotify";
        case LeaveNotify: return "LeaveNotify";
        case FocusIn: return "FocusIn";
        case FocusOut: return "FocusOut";
        case KeymapNotify: return "KeymapNotify";
        case Expose: return "Expose";
        case GraphicsExpose: return "GraphicsExpose";
        case NoExpose: return "NoExpose";
        case VisibilityNotify: return "VisibilityNotify";
        case CreateNotify: return "CreateNotify";
        case DestroyNotify: return "DestroyNotify";
        case UnmapNotify: return "UnmapNotify";
        case MapNotify: return "MapNotify";
        case MapRequest: return "MapRequest";
        case ReparentNotify: return "ReparentNotify";
        case ConfigureNotify: return "ConfigureNotify";
        case ConfigureRequest: return "ConfigureRequest";
        case GravityNotify: return "GravityNotify";
        case ResizeRequest: return "ResizeRequest";
        case CirculateNotify: return "CirculateNotify";
        case CirculateRequest: return "CirculateRequest";
        case PropertyNotify: return "PropertyNotify";
        case SelectionClear: return "SelectionClear";
        case SelectionRequest: return "SelectionRequest";
        case SelectionNotify: return "SelectionNotify";
        case ColormapNotify: return "ColormapNotify";
        case ClientMessage: return "ClientMessage";
        case MappingNotify: return "MappingNotify";

        default:
            if (type == x_shape_event_base + ShapeNotify)
                return "ShapeNotify";
            else if (type == x_apple_wm_event_base + AppleWMControllerNotify)
                return "AppleWMControllerNotify";
            sprintf (buf, "Unknown:%d", type);
            return buf;
    }
}

void
x_input_run (void)
{
    while (XPending (x_dpy) != 0)
    {
        XEvent e;

        XNextEvent (x_dpy, &e);

        DB("<%s window:%lx>", event_name (e.type), e.xany.window);

        switch (e.type)
        {
            case KeyPress:
            case KeyRelease:
                x_event_key (&e.xkey);
                break;

            case ButtonPress:
            case ButtonRelease:
                x_event_button (&e.xbutton);
                break;

            case MotionNotify:
                x_event_motion_notify (&e.xmotion);
                break;

            case FocusIn:
            case FocusOut:
                x_event_focus (&e.xfocus);
                break;

            case EnterNotify:
            case LeaveNotify:
                x_event_crossing (&e.xcrossing);
                break;

            case DestroyNotify:
                x_event_destroy_notify (&e.xdestroywindow);
                break;

            case UnmapNotify:
                x_event_unmap_notify (&e.xunmap);
                break;

            case MapRequest:
                x_event_map_request (&e.xmaprequest);
                break;

            case ReparentNotify:
                x_event_reparent_notify (&e.xreparent);
                break;

            case ConfigureRequest:
                x_event_configure_request (&e.xconfigurerequest);
                break;

            case ConfigureNotify:
                x_event_configure_notify (&e.xconfigure);
                break;

            case PropertyNotify:
                x_event_property_notify (&e.xproperty);
                break;

            case ClientMessage:
                x_event_client_message (&e.xclient);
                break;

            case Expose:
                x_event_expose (&e.xexpose);
                break;

            case ColormapNotify:
                x_event_colormap_notify (&e.xcolormap);
                break;

            case MappingNotify:
                x_event_mapping_notify (&e.xmapping);
                break;

            default:
                if (e.type == x_shape_event_base + ShapeNotify)
                    x_event_shape_notify ((XShapeEvent *) &e);
                else if (e.type - x_apple_wm_event_base >= 0
                         && e.type - x_apple_wm_event_base < AppleWMNumberEvents)
                {
                    x_event_apple_wm_notify ((XAppleWMNotifyEvent *) &e);
                }
                break;
        }

#ifdef CHECK_WINDOWS
        x_check_windows ();
#endif
    }
}

static int
add_input_socket (int sock, CFOptionFlags callback_types,
                  CFSocketCallBack callback, const CFSocketContext *ctx,
                  CFRunLoopSourceRef *cf_source)
{
    CFSocketRef cf_sock;

    cf_sock = CFSocketCreateWithNative (kCFAllocatorDefault, sock,
                                        callback_types, callback, ctx);
    if (cf_sock == NULL)
    {
        close (sock);
        return FALSE;
    }

    *cf_source = CFSocketCreateRunLoopSource (kCFAllocatorDefault,
                                              cf_sock, 0);
    CFRelease (cf_sock);

    if (*cf_source == NULL)
        return FALSE;

    CFRunLoopAddSource (CFRunLoopGetCurrent (),
                        *cf_source, kCFRunLoopDefaultMode);
    return TRUE;
}

static void
x_input_callback (CFSocketRef sock, CFSocketCallBackType type,
                  CFDataRef address, const void *data, void *info)
{
    x_input_run ();
}

void
x_input_register (void)
{
    if (!add_input_socket (ConnectionNumber (x_dpy), kCFSocketReadCallBack,
                           x_input_callback, NULL, &x_dpy_source))
    {
        exit (1);
    }
}
