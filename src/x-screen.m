/* x-screen.m
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
#include "utils.h"
#import "x-screen.h"
#import "x-window.h"

#include <AppKit/AppKit.h>

#include <X11/cursorfont.h>
#include <X11/extensions/applewm.h>
#include <X11/extensions/Xinerama.h>

@interface x_screen (local)
- (void) net_wm_init;
@end

@implementation x_screen

static XID default_cursor;

// To rebuild this list:
//
// $ grep _NET_ *.m | sed -e 's/.*\("_NET_[A-Z_]*"\).*/    \1,/' | sort | uniq

static const char *net_wm_supported[] = {
    "_NET_ACTIVE_WINDOW",
    "_NET_CLIENT_LIST",
    "_NET_CLIENT_LIST_STACKING",
    "_NET_CLOSE_WINDOW",
    "_NET_SUPPORTED",
    "_NET_SUPPORTING_WM_CHECK",
    "_NET_WM_ACTION_CLOSE",
    "_NET_WM_ACTION_FULLSCREEN",
    "_NET_WM_ACTION_MAXIMIZE_HORZ",
    "_NET_WM_ACTION_MAXIMIZE_VERT",
    "_NET_WM_ACTION_MINIMIZE",
    "_NET_WM_ACTION_MOVE",
    "_NET_WM_ACTION_RESIZE",
    "_NET_WM_ACTION_SHADE",
    "_NET_WM_ALLOWED_ACTIONS",
    "_NET_WM_NAME",
    "_NET_WM_STATE",
    "_NET_WM_STATE_FULLSCREEN",
    "_NET_WM_STATE_HIDDEN",
    "_NET_WM_STATE_MAXIMIZED_HORZ",
    "_NET_WM_STATE_MAXIMIZED_VERT",
    "_NET_WM_STATE_MODAL",
    "_NET_WM_STATE_SHADED",
    "_NET_WM_STATE_SKIP_PAGER",
    "_NET_WM_STATE_SKIP_TASKBAR",
    "_NET_WM_STATE_STICKY",
    "_NET_WM_WINDOW_TYPE",
    "_NET_WM_WINDOW_TYPE_COMBO",
    "_NET_WM_WINDOW_TYPE_DESKTOP",
    "_NET_WM_WINDOW_TYPE_DIALOG",
    "_NET_WM_WINDOW_TYPE_DND",
    "_NET_WM_WINDOW_TYPE_DOCK",
    "_NET_WM_WINDOW_TYPE_DROPDOWN_MENU",
    "_NET_WM_WINDOW_TYPE_MENU",
    "_NET_WM_WINDOW_TYPE_NORMAL",
    "_NET_WM_WINDOW_TYPE_NOTIFICATION",
    "_NET_WM_WINDOW_TYPE_POPUP_MENU",
    "_NET_WM_WINDOW_TYPE_SPLASH",
    "_NET_WM_WINDOW_TYPE_TOOLBAR",
    "_NET_WM_WINDOW_TYPE_TOOLTIP",
    "_NET_WM_WINDOW_TYPE_UTILITY",
};

#ifdef CHECK_WINDOWS
static void *check_window (void *w, void *data)
{
    assert ([((x_window *) w) isKindOfClass:[x_window class]]);
    return w;
}

- (void) check_window_lists
{
    x_list_map (_window_list, check_window, NULL);
    x_list_map (_stacking_list, check_window, NULL);
}
#endif

static inline BOOL
adoptable (Window xwindow_id)
{
    XWindowAttributes attr;

    XGetWindowAttributes (x_dpy, xwindow_id, &attr);

    return attr.map_state != IsUnmapped && attr.override_redirect != True;
}

- (void) set_property:(Window)xwindow_id name:(const char *)name
type:(const char *)type length:(int)length data:(const long *)data
{
    Atom name_atom, type_atom;

    name_atom = XInternAtom (x_dpy, name, False);
    type_atom = XInternAtom (x_dpy, type, False);

    XChangeProperty (x_dpy, xwindow_id, name_atom, type_atom, 32,
                     PropModeReplace, (const unsigned char *) data, length);
}

- (void) set_root_property:(const char *)name type:(const char *)type
                    length:(int)length data:(const long *)data
{
    [self set_property:_root name:name type:type length:length data:data];
}

- (void) update_geometry
{
    long data[2];
    int i;
    X11Region region_temp;

    TRACE ();

    if (x_get_property (_root, atoms.native_screen_origin, data, 2, 2))
    {
        _x = data[0];
        _y = data[1];
    }

    _width = WidthOfScreen (_screen);
    _height = HeightOfScreen (_screen);

    DB("Screen: %dx%d", _width, _height);

    /* Release the region we had before */
    if(_screen_region != NULL) {
        pixman_region32_fini(_screen_region);
        free(_screen_region);
        _screen_region = NULL;
    }

    if (XineramaIsActive (x_dpy))
    {
        XineramaScreenInfo *info;

        info = XineramaQueryScreens (x_dpy, &_head_count);

        if (info != NULL && _head_count >= 1)
        {
            _heads = realloc (_heads, sizeof (_heads[0]) * _head_count);

            if (_heads != NULL)
            {
                for (i = 0; i < _head_count; i++)
                {
                    DB("head %d: %d,%d %dx%d", i,
                       info[i].x_org, info[i].y_org,
                       info[i].width, info[i].height);

                    _heads[i] = X11RectMake(info[i].x_org, info[i].y_org,
                                            info[i].width, info[i].height);

                    if (_screen_region == NULL) {
                        _screen_region = (X11Region *)malloc(sizeof(X11Region));
                        if(!_screen_region) {
                            asl_log(aslc, NULL, ASL_LEVEL_ERR, "Memory allocation error.");
                            abort();
                        }

                        pixman_region32_init_rect(_screen_region,
                                                  info[i].x_org, info[i].y_org,
                                                  info[i].width, info[i].height);
                    } else {
                        pixman_region32_init(&region_temp);
                        pixman_region32_union_rect(&region_temp, _screen_region,
                                                   info[i].x_org, info[i].y_org,
                                                   info[i].width, info[i].height);
                        pixman_region32_fini(_screen_region);
                        *_screen_region = region_temp;
                    }
                }
            }
            else
                _head_count = 0;
        }
        else
        {
            if (_heads != NULL)
            {
                free (_heads);
                _heads = NULL;
            }
            _head_count = 0;
        }

        if (info != NULL)
            XFree (info);
    }

    if (_head_count == 0) {
        _main_head = X11RectMake(_x, _y, _width, _height);
        _screen_region = (X11Region *)malloc(sizeof(X11Region));
        if(!_screen_region) {
            asl_log(aslc, NULL, ASL_LEVEL_ERR, "Memory allocation error.");
            abort();
        }
        pixman_region32_init_rect(_screen_region, _x, _y, _width, _height);
    } else {
        /* find head nearest to native 0,0 */

        int nearest_i = -1, nearest_d = INT_MAX;

        for (i = 0; i < _head_count; i++)
        {
            int dx, dy, d;

            dx = _heads[i].x + _x;
            dy = _heads[i].y + _y;
            d = dx * dx + dy * dy;

            if (d < nearest_d)
            {
                nearest_d = d;
                nearest_i = i;
            }
        }

        assert (nearest_i >= 0);
        _main_head = _heads[nearest_i];

        DB("main head has index %d", nearest_i);
    }
}

- (void) update_client_list:(x_list *)lst prop:(const char *)name
{
    long *ids = NULL;
    int n_ids, i;
    x_list *node;
    x_window *w;

    n_ids = x_list_length (lst);

    if (n_ids > 0)
    {
        ids = alloca (sizeof (*ids) * n_ids);

        for (i = 0, node = lst; node != NULL; node = node->next, i++)
        {
            w = node->data;
            ids[i] = w->_id;
        }
    }

    [self set_root_property:name type:"WINDOW" length:n_ids data:ids];
}

- (void) update_net_client_list
{
    [self update_client_list:_window_list prop:"_NET_CLIENT_LIST"];
}

- (void) update_net_client_list_stacking
{
    [self update_client_list:_stacking_list prop:"_NET_CLIENT_LIST_STACKING"];
}

static int
stacking_order_pred (void *item, void *data)
{
    return x_list_find (data, item) != NULL;
}

- (x_list *) stacking_order:(x_list *)group
{
    return x_list_filter (_stacking_list, stacking_order_pred, group);
}

static int
window_level_less (const void *a, const void *b)
{
    static const int phys[AppleWMNumWindowLevels] = {0, 1, 2, -1, -2};
    const x_window *x = a, *y = b;

    return phys[x->_level] > phys[y->_level];
}

- (void) raise_windows:(id *)array count:(size_t)n
{
    size_t i, j, seen;
    Window *ids;
    x_list *node;

#ifdef CHECK_WINDOWS
    [self check_window_lists];
#endif

    if (n == 0)
        return;

    /* 1. Move all windows being raised to the head of the stacking list. */

    for (i = n - 1; ; i--)
    {
        _stacking_list = x_list_remove (_stacking_list, array[i]);
        _stacking_list = x_list_prepend (_stacking_list, array[i]);

        if(i == 0)
            break;
    }

    /* 2. Sort the new stacking list by window level. */

    _stacking_list = x_list_sort (_stacking_list, window_level_less);

    /* 3. Scan the resulting list for each of the raised windows (ugh),
     raising each below their predecessor. Luckily we'll only ever
     have a small N here. However, we also have to raise all the
     other windows down to the bottommost changed window, to be sure
     that X actually moves the ones we moved to where we want.. */

    ids = alloca (sizeof (Window) * x_list_length (_stacking_list));
    seen = 0;

    for (i = 0, node = _stacking_list;
         seen < n && node != NULL; i++, node = node->next)
    {
        x_window *w = node->data;

        ids[i] = [w toplevel_id];

        for (j = 0; j < n; j++)
        {
            if (node->data == array[j])
            {
                seen++;
                break;
            }
        }
    }

    DB("Gonna call XRaiseWindow and XRestackWindows");

    if(_stacking_list != NULL)
        XRaiseWindow (x_dpy, ids[0]);
	if (i > 1)
	    XRestackWindows (x_dpy, ids, i);

    [self update_net_client_list_stacking];
}

- init_with_screen_id:(int)xscreen_id
{
    self = [super init];
    if (self == nil)
        return nil;

    _id = xscreen_id;
    _screen = ScreenOfDisplay (x_dpy, _id);
    _root = RootWindowOfScreen (_screen);
    _depth = DefaultDepthOfScreen (_screen);
    _visual = DefaultVisualOfScreen (_screen);
    _colormap = DefaultColormapOfScreen (_screen);
    _black_pixel = BlackPixelOfScreen (_screen);

    [self update_geometry];

    DB("%d, %dx%dx%d, root:%lx, %d heads",
       xscreen_id, _width, _height, _depth, _root, _head_count);

    XSelectInput (x_dpy, _root, X_ROOT_WINDOW_EVENTS);

    [self net_wm_init];

    return self;
}

- (void) dealloc
{
    if (_head_count > 0)
        free (_heads);

    if(_screen_region != NULL) {
        pixman_region32_fini(_screen_region);
        free(_screen_region);
    }

    [super dealloc];
}

- (void) net_wm_init
{
    long data, *supported_atoms;

    if (_net_wm_window != 0)
        return;

    _net_wm_window = XCreateSimpleWindow (x_dpy, _root, 0, 0, 1, 1, 0, 0, 0);

    if (_net_wm_window != 0)
    {
        int i, n;

        data = _net_wm_window;

        [self set_property:_net_wm_window name:"_NET_SUPPORTING_WM_CHECK"
                      type:"WINDOW" length:1 data:&data];
        [self set_root_property:"_NET_SUPPORTING_WM_CHECK"
                           type:"WINDOW" length:1 data:&data];

        n = sizeof (net_wm_supported) / sizeof (net_wm_supported[0]);
        supported_atoms = alloca (n * sizeof (long));

        for (i = 0; i < n; i++)
            supported_atoms[i] = XInternAtom (x_dpy, net_wm_supported[i], False);

        [self set_root_property:"_NET_SUPPORTED"
                           type:"ATOM" length:n data:supported_atoms];
    }
}

- (void) focus_topmost:(Time)timestamp
{
    x_window *w;
    x_list *sl;
    CGError err;
    xp_bool isVisible;

    for(sl = _stacking_list; sl; sl = sl->next) {
        w = sl->data;
        err = qwm_dock_is_window_visible([w get_osx_id], &isVisible);
        if(!err && isVisible) {
            [w focus:timestamp];
            return;
        }
    }
}

- (void) adopt_window:(Window)xwindow_id initializing:(BOOL)flag
{
    x_window *w;

    DB("id: %lx initializing: %s", xwindow_id, flag ? "YES" : "NO");

    w = [[x_window alloc] init_with_id:xwindow_id screen:self initializing:flag];

    /* Need to preserve oldest-first order. */
    _window_list = x_list_append (_window_list, w);
    _stacking_list = x_list_append (_stacking_list, w);

    if (!flag)
        [self update_net_client_list];

    x_change_window_count (+1);
}

- (void) remove_window:(x_window *)w safe:(BOOL)safe
{
    DB("w:%lx safe:%s", w->_id, safe ? "YES" : "NO");

#ifdef CHECK_WINDOWS
    [self check_window_lists];
#endif

    if (!safe)
    {
        /* Being called from somewhere where we can't make X protocol
         request. (the error handler) */

        if (!w->_removed)
        {
            [NSTimer scheduledTimerWithTimeInterval:0.01
                                             target:self selector:@selector(remove_callback:)
                                           userInfo:w repeats:NO];

            w->_removed = YES;
        }
    }
    else if (!w->_deleted)
    {
        _stacking_list = x_list_remove (_stacking_list, w);

        w->_removed = YES;
        [w reparent_out];

        if (w->_focused)
            [self focus_topmost:CurrentTime];

        x_remove_window_from_menu (w);

        /* Don't remove the window from the list until after successfully
         removing it from the display. If an X I/O error occurs while
         removing it, we want to have it in the list when exiting, so
         that its dock icon can be removed it necessary. */

        _window_list = x_list_remove (_window_list, w);
        w->_deleted = YES;
        [w release];

        [self update_net_client_list];

        x_change_window_count (-1);
    }

#ifdef CHECK_WINDOWS
    [self check_window_lists];
#endif
}

- (void) remove_window:(x_window *)w
{
    [self remove_window:w safe:YES];
}

- (void) remove_callback:(NSTimer *)timer
{
    [self remove_window:[timer userInfo] safe:YES];

    XFlush (x_dpy);
}

- (void) window_hidden:(x_window *)w
{
    if (!w->_removed)
    {
        _stacking_list = x_list_remove (_stacking_list, w);
        _stacking_list = x_list_append (_stacking_list, w);

        if (w->_focused)
            [self focus_topmost:CurrentTime];
    }
}

- (void) adopt_windows
{
    Window root, parent, *children;
    unsigned n_children, i;

    x_grab_server (True);

    n_children = 0;
    XQueryTree (x_dpy, _root, &root, &parent, &children, &n_children);

    for (i = 0; i < n_children; i++)
    {
        if (adoptable (children[i]))
        {
            [self adopt_window:children[i] initializing:YES];
        }
    }

    if (n_children > 0)
        XFree (children);

    x_ungrab_server ();

    [self update_net_client_list];

    if (default_cursor == 0)
        default_cursor = XCreateFontCursor (x_dpy, XC_left_ptr);

    XDefineCursor (x_dpy, _root, default_cursor);
}

- (void) unadopt_windows
{
    x_list *copy, *node;

    copy = x_list_copy (_window_list);

    for (node = copy; node != NULL; node = node->next)
    {
        x_window *w = node->data;

        [self remove_window:w];
    }

    x_list_free (copy);
}

- (void) error_shutdown
{
    x_list *node;

    for (node = _window_list; node != NULL; node = node->next)
    {
        x_window *w = node->data;

        [w error_shutdown];
    }
}

- get_window:(Window)xwindow_id
{
    x_list *node;

    for (node = _window_list; node != NULL; node = node->next)
    {
        x_window *w = node->data;

        if (w->_id == xwindow_id)
            return w;

        if (!w->_deleted && (w->_frame_id == xwindow_id
                             || w->_tracking_id == xwindow_id
                             || w->_growbox_id == xwindow_id))
        {
            return w;
        }
    }

    return nil;
}

- get_window_by_osx_id:(xp_native_window_id)osxwindow_id
{
    x_list *node;

    for (node = _window_list; node != NULL; node = node->next)
    {
        x_window *w = node->data;
        xp_native_window_id wid;

        if (w->_deleted)
            continue;

        wid = [w get_osx_id];
        if (osxwindow_id == wid)
            return w;
    }

    return nil;
}

- (X11Rect) validate_window_position:(X11Rect)win_rect titlebar_height:(size_t)titlebar_height {
    X11Region tem;
    X11Region win_int, title_int;
    X11Region win_region, title_region, dock_region;
    X11Region screen_region_no_dock;
    X11Rect title_rect, title_int_rect;
    X11Rect ret, dock_rect;
    pixman_box32_t *e;
    xp_box dock_box;

    TRACE();

    // Figure out where the dock is to handle
    // <rdar://problem/7595340> X11 window can get lost under the dock
    // http://xquartz.macosforge.org/trac/ticket/329
    dock_box = qwm_dock_get_rect();
    dock_rect = [self CGToX11Rect:CGRectMake(dock_box.x1, dock_box.y1,
                                             dock_box.x2 - dock_box.x1,
                                             dock_box.y2 - dock_box.y1)];

    ret = title_rect = win_rect;
    title_rect.height = titlebar_height;

    // make a region of just the dock, window, and titlebar
    pixman_region32_init_rect(&dock_region, dock_rect.x, dock_rect.y,
                              dock_rect.width, dock_rect.height);
    pixman_region32_init_rect(&win_region, win_rect.x, win_rect.y,
                              win_rect.width, win_rect.height);
    pixman_region32_init_rect(&title_region, title_rect.x, title_rect.y,
                              title_rect.width, title_rect.height);

    // Make a region of our screen without the dock
    pixman_region32_init(&screen_region_no_dock);
    pixman_region32_init(&tem);
    // This should always be dock_region, but we're being careful
    pixman_region32_intersect(&tem, _screen_region, &dock_region);
    pixman_region32_subtract(&screen_region_no_dock, _screen_region, &tem);
    pixman_region32_fini(&tem);

    // Make win_int the region of our window that is on our display and not
    // in the dock
    pixman_region32_init(&win_int);
    pixman_region32_intersect(&win_int, &screen_region_no_dock, &win_region);

    // Make title_int the region of our titlebar that is on our display and not
    // in the dock
    pixman_region32_init(&title_int);
    pixman_region32_intersect(&title_int, &screen_region_no_dock, &title_region);

    // Get a rect of the bounding box for the internal titlebar.
    e = pixman_region32_extents(&title_int);
    title_int_rect = X11RectMake(e->x1, e->y1, e->x2 - e->x1, e->y2 - e->y1);
    pixman_region32_fini(&title_int);

    DB("        win_rect: %d,%d %dx%d", win_rect.x, win_rect.y, win_rect.width, win_rect.height);
    DB("        dock_rect: %d,%d %dx%d", dock_rect.x, dock_rect.y, dock_rect.width, dock_rect.height);
    e = pixman_region32_extents(_screen_region);
    DB("        screen_rect: %d,%d %dx%d", e->x1, e->y1, e->x2 - e->x1, e->y2 - e->y1);
    e = pixman_region32_extents(&screen_region_no_dock);
    DB("        screen_no_dock: %d,%d %dx%d", e->x1, e->y1, e->x2 - e->x1, e->y2 - e->y1);
    DB("        title_rect: %d,%d %dx%d", title_rect.x, title_rect.y, title_rect.width, title_rect.height);
    DB("        title_int_rect: %d,%d %dx%d", title_int_rect.x, title_int_rect.y, title_int_rect.width, title_int_rect.height);
    e = pixman_region32_extents(&win_int);
    DB("        win_int_rect: %d,%d %dx%d", e->x1, e->y1, e->x2 - e->x1, e->y2 - e->y1);

    // Done with our screen_region_no_dock
    pixman_region32_fini(&screen_region_no_dock);

    if (!pixman_region32_not_empty(&win_int)) {
        X11Region win_dock_int;

        /* Check if we're behind the dock or offscreen */
        pixman_region32_init(&win_dock_int);
        pixman_region32_intersect(&win_dock_int, _screen_region, &win_region);

        if(!pixman_region32_not_empty(&win_dock_int) || titlebar_height == 0) {
            /* Window wouldn't be on any display, so put it at top-left of
             * the main head.
             */
            ret.y = _main_head.y;
        } else {
            /* Window is partially behind our dock. */
            switch(qwm_dock_get_orientation()) {
                case XP_DOCK_ORIENTATION_BOTTOM:
                    ret.y = dock_rect.y - titlebar_height;
                    break;
                case XP_DOCK_ORIENTATION_LEFT:
                    ret.x = dock_rect.x + dock_rect.width - ret.width + 40;
                    break;
                case XP_DOCK_ORIENTATION_RIGHT:
                    ret.x = dock_rect.x - 40;
                    break;
                default:
                    asl_log(aslc, NULL, ASL_LEVEL_WARNING, "Invalid response from qwm_dock_get_orientation()");
                    break;
            }
        }
        pixman_region32_fini(&win_dock_int);

        /* Try to preserve X position */
        pixman_region32_init(&tem);
        pixman_region32_intersect(&tem, _screen_region, &title_region);

        if (!pixman_region32_not_empty(&tem)) {
            ret.x = _main_head.x;
            ret.y = _main_head.y;
        }

        pixman_region32_fini(&tem);
    } else if(title_int_rect.height < titlebar_height) {
        // The titlebar needs to have its full height on-screen
        int i;

        for (i = 0; i < _head_count; i++) {
            X11Rect dpy_rect, intersection;
            int dock_bottom_height = 0;

            dpy_rect = _heads[i];

            if(qwm_dock_get_orientation() == XP_DOCK_ORIENTATION_BOTTOM &&
               X11RectContainsPoint(dpy_rect, X11PointMake(dock_rect.x, dock_rect.y)))
                dock_bottom_height = dock_rect.height;

            /* Does it touch this display? */
            intersection = X11RectIntersection(win_rect, dpy_rect);
            if(X11RectIsEmpty(intersection))
                continue;

            if (ret.y < dpy_rect.y) {
                ret.y = dpy_rect.y;
                break;
            }

            if (ret.y + title_rect.height > dpy_rect.y + dpy_rect.height - dock_bottom_height) {
                ret.y = (dpy_rect.y + dpy_rect.height - title_rect.height - dock_bottom_height);
                break;
            }
        }
    }

    pixman_region32_fini(&win_int);
    pixman_region32_fini(&win_region);
    pixman_region32_fini(&title_region);
    pixman_region32_fini(&dock_region);

    DB("        ret: %d,%d %dx%d", ret.x, ret.y, ret.width, ret.height);
    return ret;
}

- (X11Rect) head_containing_point:(X11Point)p
{
    int i;

    if (_head_count == 0)
        return X11RectMake(0, 0, _width, _height);

    for (i = 0; i < _head_count; i++) {
        if (X11RectContainsPoint(_heads[i], p))
            return _heads[i];
    }

    return _main_head;
}

/* NSPointInRect seems to follow the standard graphics ownership model which is
 * that the borders are owned by the region by taking an epsilon step in +x (and
 * if still a border, another epsilon step in +y)... that would work for us
 * if we didn't have an inverted Y.
 */
static inline BOOL MyNSPointInRect(NSPoint p, NSRect r) {
    // Move us to the origin to eliminate headaches
    p.y -= r.origin.y;
    r.origin.y = 0;

    // Mirror y across the center of the rect
    p.y = r.size.height - p.y;

    // Now use the normal check
    return NSPointInRect(p, r);
}

- (X11Rect) zoomed_rect:(X11Point)xp {
    NSPoint nsp;
    NSRect NSvisibleFrame;
#if MAC_OS_X_VERSION_MIN_REQUIRED < 1050
    NSEnumerator *screenEnumerator;
#endif
    X11Rect ret;

    /* If the server is in rootless mode, we need to trim off the menu bar and dock */
    if(!rootless) {
        /* We need to jump out early here becasue of:
         * <rdar://problem/6395220> [NSScreen visibleFrame] subtracts dock and menubar even when hidden by another app
         */
        ret = [self head_containing_point:xp];
        DB("ret: (%d,%d %dx%d)", ret.x, ret.y, ret.width, ret.height);
        return ret;
    }

    nsp = [self X11ToNSPoint:xp];
    NSvisibleFrame = [[NSScreen mainScreen] visibleFrame];

#if MAC_OS_X_VERSION_MIN_REQUIRED >= 1050
    for(id screen in [NSScreen screens]) {
#else
        screenEnumerator = [[NSScreen screens] objectEnumerator];
        id screen;
        while((screen = [screenEnumerator nextObject])) {
#endif
        if(MyNSPointInRect(nsp, [screen frame])) {
            NSvisibleFrame = [screen visibleFrame];
            break;
        }
    }

    ret = [self NSToX11Rect:NSvisibleFrame];
    DB("ret: (%d,%d %dx%d)", ret.x, ret.y, ret.width, ret.height);
    return ret;
}

- (X11Rect) zoomed_rect
{
    return [self zoomed_rect:X11RectOrigin(_main_head)];
}

- (X11Point) center_on_head:(X11Point)p
{
    X11Point q;
    int i;

    q.x = _width / 2;
    q.y = _height / 3;

    for (i = 0; i < _head_count; i++)
    {
        if (X11RectContainsPoint (_heads[i], p))
        {
            q.x = _heads[i].x + _heads[i].width / 2;
            q.y = _heads[i].y + _heads[i].height / 3;
            break;
        }
    }

    return q;
}

- (void) disable_update
{
    if (_updates_disabled)
        return;

    XAppleWMDisableUpdate (x_dpy, _id);

    _updates_disabled = YES;
}

- (void) reenable_update
{
    if (!_updates_disabled)
        return;

    XAppleWMReenableUpdate (x_dpy, _id);

    _updates_disabled = NO;
}

- (void) raise_all
{
    x_list *node;
    Window *ids;
    int id_count, i;

    id_count = x_list_length (_window_list);
    ids = alloca (id_count * sizeof (Window));

    for (i = 0, node = _window_list; node != NULL; node = node->next)
    {
        x_window *w = node->data;

        if (!w->_deleted && i < id_count)
            ids[i++] = [w toplevel_id];
    }

    if (i > 0)
    {
        DB("Gonna call XRaiseWindow and XRestackWindows");
        XRaiseWindow (x_dpy, ids[0]);
        if (i > 1)
            XRestackWindows (x_dpy, ids, i);
    }
}

- (void) hide_all
{
    [self foreach_window:@selector (do_hide)];
}

- (void) show_all:(BOOL)flag
{
    if (!flag)
        [self foreach_window:@selector (do_unhide)];
    else
        [self foreach_window:@selector (show)];
}

- (void) foreach_window:(SEL)selector
{
    x_list *node;
    x_window *w;

    for (node = _window_list; node != NULL; node = node->next)
    {
        w = node->data;
        [w performSelector:selector];
    }
}

- (id) find_window_at:(X11Point)p slop:(int)epsilon
{
    int epsilon_squared = epsilon * epsilon;
    x_list *node;
    x_window *w;
    int dx, dy;

    for (node = _window_list; node != NULL; node = node->next)
    {
        w = node->data;

        dx = p.x - w->_current_frame.x;
        dy = p.y - w->_current_frame.y;

        if (dx * dx + dy * dy <= epsilon_squared)
            return w;
    }

    return nil;
}

/* OK, This is straight up hell for incompatible coordinate systems.
 *
 * [NSScreen visibleFrame] and [NSScreen frame] return rects with origins in the
 * lower left (y increases upward) of the mainScreen (menu bar).
 *
 * CG's screen origin is the upper-left (y increases downward) of the mainScreen (menubar)
 *
 * X11's screen origin is the upper-left of the upper-left-most screen
 *
 * X11Rect's origin point is the upper-left
 * CGRect's origin point is the upper-left
 * NSRect's origin point is the lower-left
 */

- (X11Point) CGToX11Point:(CGPoint)p {
    X11Point ret;
    ret.x = p.x - _x;
    ret.y = p.y - _y;
    return ret;
}

- (X11Point) NSToX11Point:(NSPoint)p {
    NSRect fr = [[NSScreen mainScreen] frame];
    X11Point ret;
    ret.x = p.x - _x;
    ret.y = (fr.size.height - p.y) - _y;
    return ret;
}

- (X11Rect) CGToX11Rect:(CGRect)r {
    X11Rect ret;
    ret.x = r.origin.x - _x;
    ret.y = r.origin.y - _y;
    ret.width = r.size.width;
    ret.height = r.size.height;
    return ret;
}

- (X11Rect) NSToX11Rect:(NSRect)r {
    NSRect fr = [[NSScreen mainScreen] frame];
    X11Rect ret;
    ret.x = r.origin.x - _x;
    ret.y = fr.size.height - (r.size.height + r.origin.y + _y);
    ret.width = r.size.width;
    ret.height = r.size.height;
    return ret;
}

- (CGPoint) X11ToCGPoint:(X11Point)p {
    return CGPointMake(p.x + _x, p.y + _y);
}

- (NSPoint) X11ToNSPoint:(X11Point)p {
    NSRect fr = [[NSScreen mainScreen] frame];
    return NSMakePoint(p.x + _x,
                       fr.size.height - p.y - _y);
}

- (CGRect) X11ToCGRect:(X11Rect)r {
    return CGRectMake(r.x + _x, r.y + _y, r.width, r.height);
}

- (NSRect) X11ToNSRect:(X11Rect)r {
    NSRect fr = [[NSScreen mainScreen] frame];
    return NSMakeRect(r.x + _x,
                      fr.size.height - (r.height + r.y + _y),
                      r.width,
                      r.height);
}

@end
