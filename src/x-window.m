/* x-window.m
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
#import "x-window.h"
#include "frame.h"
#include "utils.h"

#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <X11/keysym.h>
#include <X11/extensions/applewm.h>

#define WINDOW_PLACE_DELTA_X 20
#define WINDOW_PLACE_DELTA_Y 20

#define XP_FRAME_CLASS_DECOR_MASK  (XP_FRAME_CLASS_DECOR_LARGE | XP_FRAME_CLASS_DECOR_SMALL | XP_FRAME_CLASS_DECOR_NONE)

@interface x_window (local)
- (void) update_wm_name;
- (void) update_wm_protocols;
- (void) update_wm_hints;
- (void) update_size_hints;
- (void) update_frame;
- (void) update_net_wm_type_hints;
- (void) update_net_wm_state_hints;
- (void) update_net_wm_state_property;
- (void) update_motif_hints;
- (void) update_parent;
- (void) update_group;
- (void) update_shape:(X11Rect)or;
- (void) decorate_rect:(X11Rect)or;
- (xp_frame_class) get_xp_frame_class;
- (void) map_unmap_client;
- (BOOL) is_maximized;
- (void) do_maximize;
- (void) do_fullscreen:(BOOL)flag;
- (void) do_uncollapse_and_tell_dock:(BOOL)tell_dock with_animation:(BOOL)anim;
- (x_list *) transient_group;
- (NSString *) resizing_title;
- (NSString *) title;
- (X11Rect) validate_frame_rect:(X11Rect)r
                      from_user:(BOOL)uflag constrain:(BOOL)cflag;
- (X11Rect) frame_inner_rect:(X11Rect)or;
- (X11Rect) client_rect:(X11Rect)or;
- (X11Rect) intended_frame;
@end

static const char *gravity_type(int gravity) {
    switch(gravity) {
        case NorthWestGravity:
            return "NorthWestGravity";
        case NorthGravity:
            return "NorthGravity";
        case NorthEastGravity:
            return "NorthEastGravity";
        case WestGravity:
            return "WestGravity";
        case CenterGravity:
            return "CenterGravity";
        case EastGravity:
            return "EastGravity";
        case SouthWestGravity:
            return "SouthWestGravity";
        case SouthGravity:
            return "SouthGravity";
        case SouthEastGravity:
            return "SouthEastGravity";
        case StaticGravity:
            return "StaticGravity";
        default:
            return "NorthWestGravity";
    }
}

@implementation x_window

#undef TRACE
#define TRACE() DB("TRACE: id: 0x%x frame_id: 0x%x\n", _id, _frame_id)

#define DISABLE_EVENTS(wid, mask)				\
do {							\
x_grab_server (False);					\
XSelectInput (x_dpy, wid, mask);			\
} while (0)

#define ENABLE_EVENTS(wid, mask)				\
do {							\
XSelectInput (x_dpy, wid, mask);			\
x_ungrab_server ();					\
} while (0)

#define BEFORE_LOCAL_MAP \
DISABLE_EVENTS (_id, X_CLIENT_WINDOW_EVENTS & ~StructureNotifyMask)
#define AFTER_LOCAL_MAP \
ENABLE_EVENTS (_id, X_CLIENT_WINDOW_EVENTS)

- (Window) toplevel_id
{
    return _reparented ? _frame_id : _id;
}

- (void) grab_events
{
    int i, code;

    for (i = 1; i <= 3; i++)
    {
        XGrabButton (x_dpy, i, AnyModifier, _id, False,
                     X_CLIENT_BUTTON_GRAB_EVENTS, GrabModeSync,
                     GrabModeSync, None, None);
    }

    code = XKeysymToKeycode (x_dpy, XK_grave);
    if (code != 0 && x_meta_mod != 0)
    {
        // We can't use AnyModifier because of a bug replaying (eg, alt-` doesn't send dead_grave)
        XGrabKey (x_dpy, code, ShiftMask | x_meta_mod, _id,
                  False, GrabModeSync, GrabModeSync);
        XGrabKey (x_dpy, code, x_meta_mod, _id,
                  False, GrabModeSync, GrabModeSync);
    }
}

- (void) ungrab_events
{
    int i, code;

    for (i = 1; i <= 3; i++)
    {
        XUngrabButton (x_dpy, i, AnyModifier, _id);
    }

    code = XKeysymToKeycode (x_dpy, XK_grave);
    if (code != 0)
    {
        XUngrabKey (x_dpy, code, AnyModifier, _id);
    }
}

- (void) reparent_in
{
    if (_reparented)
        return;

    TRACE ();

    if (_frame_id == 0)
    {
        XSetWindowAttributes attr;
        unsigned long attr_mask = 0;

        attr.override_redirect = True;
        attr.colormap = _xattr.colormap;
        attr.border_pixel = 0;
        attr.bit_gravity = StaticGravity;

        attr_mask |= (CWOverrideRedirect | CWColormap
                      | CWBorderPixel | CWBitGravity);

        _frame_id = XCreateWindow (x_dpy, _screen->_root,
                                   _current_frame.x, _current_frame.y,
                                   _current_frame.width, _current_frame.height,
                                   0, _xattr.depth,
                                   InputOutput, _xattr.visual,
                                   attr_mask, &attr);

        XSelectInput (x_dpy, _frame_id, X_FRAME_WINDOW_EVENTS);
    }

    [self update_shape];

    BEFORE_LOCAL_MAP; // _frame_border_width
    XReparentWindow (x_dpy, _id, _frame_id, 0, _frame_title_height);
    XLowerWindow (x_dpy, _id);
    AFTER_LOCAL_MAP;

    XAddToSaveSet (x_dpy, _id);

    _reparented = YES;

    [self map_unmap_client];

    [self raise];
    [self grab_events];
}

- (void) reparent_out {
    X11Rect ir;
    if (!_reparented)
        return;

    TRACE ();

    if(_minimized) {
        [self do_uncollapse_and_tell_dock:YES with_animation:NO];
    }

    if(_shaded) {
        [self do_unshade:CurrentTime];
    }

    if(_hidden) {
        [self do_unhide];
    }

    [self ungrab_events];

    ir = [self frame_inner_rect:_current_frame];
    BEFORE_LOCAL_MAP;
    XReparentWindow(x_dpy, _id, _screen->_root, ir.x, ir.y);
    AFTER_LOCAL_MAP;

    XSetWindowBorderWidth(x_dpy, _id, _xattr.border_width);
    XRemoveFromSaveSet(x_dpy, _id);

    [self map_unmap_client];

    if(_frame_id != 0) {
        XDestroyWindow (x_dpy, _frame_id);
        _frame_id = 0;
        _tracking_id = 0;
        _growbox_id = 0;
        _osx_id = XP_NULL_NATIVE_WINDOW_ID;
    }

    /* Mark us as not transient of a parent */
    if(_transient_for) {
        _transient_for->_transients = x_list_remove(_transient_for->_transients, self);
        _transient_for = NULL;
    }

    /* Update our children to not be transient for us */
    if(_transients) {
        x_list *node;
        for(node = _transients; node; node = node->next) {
            x_window *child = node->data;
            child->_transient_for = NULL;
        }

        x_list_free(_transients);
        _transients = NULL;
    }

    _reparented = NO;
    _decorated = NO;
    _pending_frame_change = NO;
    _queued_frame_change = NO;
}

- (void) send_configure {
    XEvent e;
    X11Rect ir;

    if(_reparented)
        ir = [self frame_inner_rect:_current_frame];

    TRACE ();

    e.type = ConfigureNotify;
    e.xconfigure.display = x_dpy;
    e.xconfigure.event = _id;
    e.xconfigure.window = _id;
    e.xconfigure.x = _reparented ? ir.x : _xattr.x;
    e.xconfigure.y = _reparented ? ir.y : _xattr.y;
    e.xconfigure.width = _xattr.width;
    e.xconfigure.height = _xattr.height;
    e.xconfigure.border_width = _xattr.border_width;
    e.xconfigure.above = _reparented ? _frame_id : _screen->_root;
    e.xconfigure.override_redirect = False;

    XSendEvent(x_dpy, _id, False, StructureNotifyMask, &e);
}

- (void) validate_position {
    X11Rect r;
    
    TRACE();
    
    r = [_screen validate_window_position:_current_frame titlebar_height:_frame_title_height];

    if(r.x != _current_frame.x || r.y != _current_frame.y) {
        XMoveWindow(x_dpy, _frame_id, r.x, r.y);
    }
}

- (void) place_window {
    x_list *group, *order;
    X11Rect r;
    
    TRACE();

    r = _current_frame;

    group = [self window_group];
    order = x_list_remove ([_screen stacking_order:group], self);
    x_list_free (group);

    if (_size_hints.flags & (USPosition | PPosition)) {
        /* Do nothing except check position is valid. */
        DB("USPosition | PPosition\n");
    } else if (_transient_for_id == _screen->_root) {
        X11Point p;

        DB("Transient for root\n");

        /* Convention is this is an unparented dialog. Center on head
         * of topmost window in group.
         */

        if (order == NULL)
            p = X11PointMake (0 - _screen->_x, 0 - _screen->_y);
        else
            p = X11RectOrigin(((x_window *) order->data)->_current_frame);

        p = [_screen center_on_head:p];

        r.x = p.x - _current_frame.width / 2.0;
        r.y = p.y - (_frame_height >> 1);
    } else if (_transient_for != NULL) {
        /* Dialog style placement. Try to center ourselves on top
         of the parent window. */

        DB("Transient for someone (not root).  Dialog placement\n");

        r.x =   _transient_for->_current_frame.x
        + (_transient_for->_current_frame.width / 2.0)
        - (_current_frame.width / 2.0);
        r.y = _transient_for->_current_frame.y +
        _transient_for->_frame_title_height;
    } else {
        DB("Document style placement.\n");

        /* Document style placement. Find the topmost document window
         * in the group, then place ourselves down and to the right of it.
         */
        if (order == NULL)
        {
            /* No group members. Place ourselves below the menubar. */
            X11Rect zoom_rect = [_screen zoomed_rect];
            r.x = zoom_rect.x;
            r.y = zoom_rect.y;

            /* But cascade from other windows here. */
            while ([_screen find_window_at:X11RectOrigin(r) slop:8] != nil)
            {
                r.x += WINDOW_PLACE_DELTA_X;
                r.y += WINDOW_PLACE_DELTA_Y;
            }

            DB("Check for room for r:(%d,%d %dx%d) zoom_rect:(%d,%d %dx%d)\n",
               r.x, r.y, r.width, r.height,
               zoom_rect.x, zoom_rect.y, zoom_rect.width, zoom_rect.height);    
            
            /* No room */
            if(r.x + r.width > zoom_rect.width ||
               r.y + r.height > zoom_rect.height)
            {
                r.x = zoom_rect.x;
                r.y = zoom_rect.y;

                DB("Nope.  Now at the origin: r:(%d,%d %dx%d) zoom_rect:(%d,%d %dx%d)\n",
                   r.x, r.y, r.width, r.height,
                   zoom_rect.x, zoom_rect.y, zoom_rect.width, zoom_rect.height);    
                
                /* Shrink if there still isn't room */
                if(r.x + r.width > zoom_rect.x +  zoom_rect.width)
                    r.width = zoom_rect.x + zoom_rect.width - r.x;
                if(r.y + r.height > zoom_rect.y + zoom_rect.height)
                    r.height = zoom_rect.y + zoom_rect.height - r.y;
                
            }
        }
        else
        {
            x_window *w = order->data;

            r.x = w->_current_frame.x + WINDOW_PLACE_DELTA_X;
            r.y = w->_current_frame.y + WINDOW_PLACE_DELTA_Y;

            /* Shrink if there isn't room */
            if(r.x + r.width > _screen->_width)
                r.width = _screen->_width - r.x;
            if(r.y + r.height > _screen->_height)
                r.height = _screen->_height - r.y;
        }
    }

    x_list_free (order);

    DB("r:(%d,%d %dx%d)\n", r.x, r.y, r.width, r.height);    
    
    r = [self validate_frame_rect:r from_user:NO constrain:NO];
    [self resize_frame:r];
}

-(xp_frame_class) get_xp_frame_class {
    if(_fullscreen || _shaped_empty)
        return _frame_behavior | XP_FRAME_CLASS_DECOR_NONE;
    return _frame_behavior | _frame_decor;
}

/* Given the x/y/w/h from a ConfigureRequest, what is our frame's
 * rect considering the current gravity?
 */
- (X11Rect)construct_frame_from_winrect:(X11Rect) winrect {
    int gravity = (_size_hints.flags & PWinGravity) ? _size_hints.win_gravity : NorthWestGravity;
    int x = winrect.x;
    int y = winrect.y;
    int x_pad_r = 0; // _frame_border_width
    int x_pad_l = 0; // _frame_border_width
    int y_pad_t = _frame_title_height;
    int y_pad_b = 0; // _frame_border_width

    switch(gravity) {
        case NorthWestGravity:
            break;
        case NorthGravity:
            x -= (x_pad_l + x_pad_r) >> 1;
            break;
        case NorthEastGravity:
            x -= x_pad_l + x_pad_r;
            break;
        case WestGravity:
            y -= (y_pad_t + y_pad_b) >> 1;
            break;
        case CenterGravity:
            x -= (x_pad_l + x_pad_r) >> 1;
            y -= (y_pad_t + y_pad_b) >> 1;
            break;
        case EastGravity:
            x -= x_pad_l + x_pad_r;
            y -= (y_pad_t + y_pad_b) >> 1;
            break;
        case SouthWestGravity:
            y -= (y_pad_t + y_pad_b);
            break;
        case SouthGravity:
            x -= (x_pad_l + x_pad_r) >> 1;
            y -= (y_pad_t + y_pad_b);
            break;
        case SouthEastGravity:
            x -= x_pad_l + x_pad_r;
            y -= (y_pad_t + y_pad_b);
            break;
        case StaticGravity:
            x -= x_pad_l;
            y -= y_pad_t;
            break;
        default:
            break;
    }

    DB("Window %ul gravity: %s %d,%d %dx%d -> %d,%d %dx%d\n",
       (unsigned int)_id, gravity_type(_size_hints.win_gravity),
       (int)winrect.x, (int)winrect.y, (int)winrect.width, (int)winrect.height,
       x, y, (int)winrect.width + x_pad_l + x_pad_r, (int)winrect.height + y_pad_t + y_pad_b);

    return X11RectMake(x, y, (int)winrect.width + x_pad_l + x_pad_r, (int)winrect.height + y_pad_t + y_pad_b);
}

- init_with_id:(Window)id screen:screen initializing:(BOOL)flag {
    self = [super init];
    if (self == nil)
        return nil;

    _id = id;
    _screen = screen;

    _drawn_frame_decor = 0;
    _current_frame = X11EmptyRect;
    
    _transient_for = NULL;
    _transient_for_id = _screen->_root;
    _transients = NULL;

    _fullscreen = NO;
    
    DB ("initializing: %s\n", flag ? "YES" : "NO");

    XSelectInput(x_dpy, _id, X_CLIENT_WINDOW_EVENTS);
    XShapeSelectInput(x_dpy, _id, ShapeNotifyMask);

    /* Get the initial attr of the child window */
    XGetWindowAttributes(x_dpy, _id, &_xattr);

    /* Get unmutable hints from attributes on the window */
    [self update_shaped];

    /* Set the window name */
    [self update_wm_name];
    
    /* Window grouping hints */
    [self update_parent];
    [self update_wm_hints];
    [self update_group];

    /* Get our colormap */
    [self update_colormaps];

    /* Update wm_protocols */
    [self update_wm_protocols];
    
    /* Setup our look */
    _frame_attr = 0;
    [self update_frame];
    XSetWindowBorderWidth (x_dpy, _id, 0);

    /* Figure out our frame dimensions from XGetWindowAttributes if it wasn't
     * set from other hints (fullscreen, maximized, etc)
     */
    if(X11RectEqualToRect(_current_frame, X11EmptyRect))
    	_current_frame = [self construct_frame_from_winrect:X11RectMake(_xattr.x, _xattr.y, _xattr.width, _xattr.height)];
    _frame_height = _current_frame.height;

    [self reparent_in];

    if(flag)
        [self validate_position];
    else
        [self place_window];

    XMapWindow(x_dpy, _id);
    if(_reparented)
        XMapWindow(x_dpy, _frame_id);

    if(_level != AppleWMWindowLevelNormal)
        XAppleWMSetWindowLevel(x_dpy, _reparented ? _frame_id : _id, _level);

    [self set_wm_state:NormalState];
    [self send_configure];

    if (_wm_hints != NULL &&
        _wm_hints->flags & StateHint &&
        _wm_hints->initial_state == IconicState) {
        [self do_collapse];
    } else {
        /* FIXME: don't want to do this if user is typing someplace else? */
        [self focus:CurrentTime];
    }

    if(_in_window_menu) {
        _shortcut_index = x_allocate_window_shortcut ();
        x_add_window_to_menu (self);
    }

    if(focus_on_new_window) {
        XAppleWMSetFrontProcess(x_dpy);
    }

    /* We need to do update_parent again here, since we now have the CGWindow */
    [self update_parent];

    return self;
}

- (void) do_resize:(X11Rect)r
{
    BOOL resized;

    /* _pending_frame_change should be false when this is called */
    assert (!_pending_frame_change);

    resized = !(_current_frame.width == r.width && _current_frame.height == r.height);

    DB("id: 0x%x frame_id: 0x%x resized: %d r:(%d,%d %dx%d) current_frame:(%d,%d %dx%d)\n",
       _id, _frame_id, resized, r.x, r.y, r.width, r.height,
       _current_frame.x, _current_frame.y, _current_frame.width, _current_frame.height);

    /* The window is not yet mapped, so just adjust _current_frame */
    if(!_reparented) {
        _current_frame = r;
        [self update_net_wm_state_property];
        return;
    }
    
    if (resized)
        [_screen disable_update];

    XMoveResizeWindow (x_dpy, _frame_id,
                       (int) r.x, (int) r.y,
                       (int) r.width, (int) r.height);
    _pending_frame = r;
    _pending_frame_change = YES;

    if (resized)
    {
        X11Rect or = X11RectMake(0, 0, r.width, r.height);

        [self update_shape:or];
        [self decorate_rect:or];

        [_screen reenable_update];

        /* we'll physically resize the client window when we receive
         the ConfigureNotify for the frame being resized, which
         will cause a real ConfigureNotify event to be sent. */
        _needs_configure_notify = NO;
    }

    [self update_net_wm_state_property];
}

- (void) resize_frame:(X11Rect)r force:(BOOL)flag {
    X11Rect fr;

    DB("id: 0x%x frame_id: 0x%x rect:(%d,%d %dx%d) force:%d\n", _id, _frame_id,
       r.x, r.y, r.width, r.height, flag);

    fr = r;

    if(_shaded) {
        fr.height = _frame_title_height;
        _frame_height = r.height;
    }

    if(!_pending_frame_change) {
        if(!flag && X11RectEqualToRect(_current_frame, fr))
            return;

        [self do_resize:fr];
        return;
    }

    if(!_queued_frame_change) {
        if(!flag && _pending_frame.width == r.width && _pending_frame.height == r.height) {
            if(_pending_frame.x == r.x && _pending_frame.y == r.y)
                return;

            /* Moves can be pipelined. */
            XMoveWindow(x_dpy, _frame_id, (int) r.x, (int) r.y);
            _pending_frame.x = r.x;
            _pending_frame.y = r.y;
            _needs_configure_notify = NO;
            [self update_net_wm_state_property];
            return;
        }
    }

    _queued_frame = r;
    _queued_frame_change = YES;
    [self update_net_wm_state_property];
}

- (void) resize_frame:(X11Rect)r
{
    [self resize_frame:r force:NO];
}

- (void) report_frame_size:(X11Rect)r
{
    BOOL moved = NO, resized = NO;

    TRACE ();

    if(_current_frame.x != r.x ||
       _current_frame.y != r.y) {

        _xattr.x = [self client_rect:r].x;
        _xattr.y = [self client_rect:r].y;

        moved = YES;
    }

    if(_current_frame.width  != r.width ||
       _current_frame.height != r.height) {
        if(!_shaded)
            _frame_height = r.height;

        _xattr.width = r.width; // (_frame_border_width << 1);
        _xattr.height = _frame_height - _frame_title_height;

        DISABLE_EVENTS(_id, 0);
        XResizeWindow(x_dpy, _id, _xattr.width, _xattr.height);
        ENABLE_EVENTS(_id, X_CLIENT_WINDOW_EVENTS);

        resized = YES;
    }

    _current_frame = r;
    [self update_net_wm_state_property];

    if(moved && !resized)
        [self send_configure];

    if(_pending_frame_change) {
        _pending_frame_change = NO;

        if(_queued_frame_change) {
            X11Rect fr;

            fr = _queued_frame;

            if(_shaded) {
                fr.height = _frame_title_height;
                _frame_height = r.height;
            }

            _queued_frame_change = NO;
            [self do_resize:fr];
        }
    }

    if (!_pending_frame_change && _pending_decorate)
        [self decorate];
}

- (void) resize_client:(X11Rect)r {
    X11Rect fr;

    TRACE ();

    if (!_reparented) {
        r = [self validate_frame_rect:r];

        _xattr.x = r.x;
        _xattr.y = r.y;
        _xattr.width = r.width;
        _xattr.height = r.height;

        XMoveResizeWindow(x_dpy, _id, _xattr.x, _xattr.y,
                          _xattr.width, _xattr.height);
        return;
    }

    /* Called from ConfigureRequest handler. */
    _needs_configure_notify = YES;

    fr = [self construct_frame_from_winrect:r];
    fr = [self validate_frame_rect:fr];

    if(_frame_id) {
        [self resize_frame:fr];
    } else {
        _frame_height = fr.height;
    }

    if (_needs_configure_notify) {
        [self send_configure];
        _needs_configure_notify = NO;
    }
}

- (X11Rect) frame_outer_rect {
    return X11RectMake (0, 0, _current_frame.width, _current_frame.height);
}

- (X11Rect) frame_inner_rect:(X11Rect)or {
    int height = _shaded ? 0 : or.height - _frame_title_height;

    // _frame_border_width
    return X11RectMake(or.x,
                       or.y + _frame_title_height,
                       or.width, height);
}

/* Calculate the client rect that would be required to generate this outer
 * frame given the current gravity.
 */
- (X11Rect) client_rect:(X11Rect)or {
    int gravity = (_size_hints.flags & PWinGravity) ? _size_hints.win_gravity : NorthWestGravity;
    int x = or.x;
    int y = or.y;
    int x_pad_r = 0; // _frame_border_width
    int x_pad_l = 0; // _frame_border_width
    int y_pad_t = _frame_title_height;
    int y_pad_b = 0; // _frame_border_width
    int w, h;

    switch(gravity) {
        case NorthWestGravity:
            break;
        case NorthGravity:
            x += (x_pad_l + x_pad_r) >> 1;
            break;
        case NorthEastGravity:
            x += x_pad_l + x_pad_r;
            break;
        case WestGravity:
            y += (y_pad_t + y_pad_b) >> 1;
            break;
        case CenterGravity:
            x += (x_pad_l + x_pad_r) >> 1;
            y += (y_pad_t + y_pad_b) >> 1;
            break;
        case EastGravity:
            x += x_pad_l + x_pad_r;
            y += (y_pad_t + y_pad_b) >> 1;
            break;
        case SouthWestGravity:
            y += (y_pad_t + y_pad_b);
            break;
        case SouthGravity:
            x += (x_pad_l + x_pad_r) >> 1;
            y += (y_pad_t + y_pad_b);
            break;
        case SouthEastGravity:
            x += x_pad_l + x_pad_r;
            y += (y_pad_t + y_pad_b);
            break;
        case StaticGravity:
            x += x_pad_l;
            y += y_pad_t;
            break;
        default:
            break;
    }

    /* w and h are the easy ones */
    w = or.width - x_pad_r - x_pad_l;
    h = or.height - y_pad_t - y_pad_b;

    return X11RectMake(x, y, w, h);
}


- (void) update_inner_windows:(BOOL)reposition outer:(X11Rect)or inner:(X11Rect)ir
{
    if (_frame_title_height > 0 && _tracking_id == 0)
    {
        XSetWindowAttributes attr;

        /* Initialize pointer tracking window for prelighting */
        _tracking_rect = frame_tracking_rect(or, ir, [self get_xp_frame_class]);
        attr.override_redirect = True;
        _tracking_id = XCreateWindow (x_dpy, _frame_id,
                                      _tracking_rect.x,
                                      _tracking_rect.y,
                                      _tracking_rect.width,
                                      _tracking_rect.height,
                                      0, 0, InputOnly, _xattr.visual,
                                      CWOverrideRedirect, &attr);
        XMapRaised (x_dpy, _tracking_id);
        XSelectInput (x_dpy, _tracking_id, X_TRACKING_WINDOW_EVENTS);
    }

    if (_growbox_id == 0 && !_shaded && _resizable &&
        XP_FRAME_ATTR_IS_SET (_frame_attr, XP_FRAME_ATTR_GROW_BOX))
    {
        XSetWindowAttributes attr;
        unsigned long attr_mask = 0;

        TRACE ();

        attr.override_redirect = True;
        attr.win_gravity = SouthEastGravity;
        attr.colormap = _xattr.colormap;
        attr.border_pixel = 0;

        attr_mask |= (CWOverrideRedirect | CWColormap
                      | CWBorderPixel | CWWinGravity);

        _growbox_rect = frame_growbox_rect (or, ir, [self get_xp_frame_class]);
        _growbox_id = XCreateWindow (x_dpy, _frame_id,
                                     _growbox_rect.x,
                                     _growbox_rect.y,
                                     _growbox_rect.width,
                                     _growbox_rect.height,
                                     0, _xattr.depth,
                                     InputOutput, _xattr.visual,
                                     attr_mask, &attr);
        XMapRaised (x_dpy, _growbox_id);
        XSelectInput (x_dpy, _growbox_id, X_GROWBOX_WINDOW_EVENTS);
    }
    else if (_growbox_id != 0 && (_shaded || !_resizable || !XP_FRAME_ATTR_IS_SET (_frame_attr, XP_FRAME_ATTR_GROW_BOX)))
    {
        XDestroyWindow (x_dpy, _growbox_id);
        _growbox_id = 0;
    }
    else if (_growbox_id != 0 && reposition)
    {
#ifdef MORE_ROUNDTRIPS
        _growbox_rect = frame_growbox_rect (or, ir, [self get_xp_frame_class]);
#else
        _growbox_rect.x = or.width - _growbox_rect.width;
        _growbox_rect.y = or.height - _growbox_rect.height;
#endif
        XMoveResizeWindow (x_dpy, _growbox_id,
                           _growbox_rect.x,
                           _growbox_rect.y,
                           _growbox_rect.width,
                           _growbox_rect.height);
    }
}

- (void) update_shaped
{
    int xws, yws, xbs, ybs;
    unsigned int wws, hws, wbs, hbs;
    int bounding, clip;

    XShapeQueryExtents (x_dpy, _id, &bounding, &xws, &yws,
                        &wws, &hws, &clip, &xbs, &ybs, &wbs, &hbs);

    _shaped = bounding ? YES : NO;
    _shaped_empty = (bounding && (wws <= 0 || hws <= 0));
}

- (void) update_shape:(X11Rect)or
{
    X11Rect ir;
    XRectangle r[2];
    int nr;

    TRACE ();

    ir = [self frame_inner_rect:or];

    [self update_inner_windows:YES outer:or inner:ir];

    if (_shaped)
    {
        r[0].x = 0;
        r[0].y = 0;
        r[0].width = or.width;
        r[0].height = ((_shaped || _shaded)
                       ? _frame_title_height : or.height);
        nr = 1;

        if (_growbox_id != 0)
        {
            r[1].x = _growbox_rect.x;
            r[1].y = _growbox_rect.y;
            r[1].width = _growbox_rect.width;
            r[1].height = _growbox_rect.height;
            nr = 2;
        }

        XShapeCombineRectangles (x_dpy, _frame_id, ShapeBounding,
                                 0, 0, r, nr, ShapeSet, Unsorted);

        XShapeCombineShape (x_dpy, _frame_id, ShapeBounding,
                            ir.x, ir.y, _id,
                            ShapeBounding, ShapeUnion);

        _set_shape = YES;
    }
    else if (_set_shape)
    {
        XShapeCombineMask (x_dpy, _frame_id, ShapeBounding,
                           0, 0, None, ShapeSet);

        _set_shape = NO;
    }
}

- (void) update_shape
{
    TRACE();
    [self update_shape:[self frame_outer_rect]];
}

- (xp_native_window_id) get_osx_id
{
    if (_osx_id == XP_NULL_NATIVE_WINDOW_ID) {
        Window xwindow_id = [self toplevel_id];
        long data;

        if (x_get_property (xwindow_id, atoms.native_window_id, &data, 1, 1))
            _osx_id = (xp_native_window_id) data;

        DB("Window 0x%x with frame 0x%x has a new _osx_id: %u\n", _id, _frame_id, _osx_id);
    }

    return _osx_id;
}

- (void) set_wm_state:(int)state
{
    long data[2];

    data[0] = state;
    data[1] = 0;			/* icon window */

    XChangeProperty (x_dpy, _id, atoms.wm_state, atoms.wm_state,
                     32, PropModeReplace, (unsigned char *) data, 2);
}

/* Don't allow us to close the window if there are modal windows
 * <rdar://problem/5880438> Close widget should be disabled if window has modal children
 */
- (BOOL) has_modal_descendents {
    if(_transients) {
        x_list *node;
        for(node = _transients; node; node = node->next) {
            x_window *child = node->data;
            if(child->_modal) {
                return YES;
            }
        }
    }

    return NO;
}

- (void) decorate_rect:(X11Rect)or
{
    X11Rect ir;
    unsigned frame_attr = _frame_attr;

    if (!_reparented || _hidden)
    {
        _pending_decorate = YES;
        return;
    }

    TRACE ();

    ir = [self frame_inner_rect:or];

    [self update_inner_windows:NO outer:or inner:ir];

    if ((frame_attr & XP_FRAME_ATTR_CLOSE_BOX) && [self has_modal_descendents]) {
        frame_attr &= ~XP_FRAME_ATTR_CLOSE_BOX;
    }

    /* Save the *decoration* of our last draw */
    _drawn_frame_decor = [self get_xp_frame_class] & XP_FRAME_CLASS_DECOR_MASK;
    
    draw_frame (_screen->_id, _frame_id, or, ir, [self get_xp_frame_class],
                frame_attr, (CFStringRef) [self title]);

    _decorated = YES;
    _pending_decorate = NO;
}

- (void) decorate
{
    if (_pending_frame_change)
    {
        _pending_decorate = YES;
        return;
    }

    [self decorate_rect:[self frame_outer_rect]];
}

- (void) expose
{
    [self decorate];
}

- (NSString *) title
{
    NSString *resizing;

    resizing = _resizing_title ? [self resizing_title] : nil;

    if (_title != nil && resizing != nil)
        return [NSString stringWithFormat:@"%@ - %@", _title, resizing];
    else if (_title != nil)
        return _title;
    else if (resizing != nil)
        return resizing;
    else
        return @"";
}

- (void) update_wm_name
{
    XTextProperty prop;
    NSString *old, *new_;

    old = _title;

    new_ = x_get_string_property (_id, atoms.net_wm_name);

    if (new_ == nil && XGetWMName (x_dpy, _id, &prop) && prop.value)
    {
        if (prop.nitems > 0)
        {
            char **list;
            int err, count;

            prop.nitems = strlen((char *) prop.value);
            err = Xutf8TextPropertyToTextList (x_dpy, &prop, &list, &count);

            if (err >= Success)
            {
                if (count > 0)
                {
                    new_ = [NSString stringWithUTF8String: list[0]];
                    XFreeStringList (list);
                }
            }
            else
                new_ = [NSString stringWithUTF8String:(char *) prop.value];

            XFree (prop.value);
        }
    }

    if (new_ != nil && (old == nil || ![old isEqualToString:new_]))
    {
        _title = [new_ retain];
    }

    if (old != nil && _title != old)
    {
        [old release];
    }

    if (_title != old)
    {
        [self decorate];
        x_update_window_in_menu (self);
    }
}

- (void) update_wm_protocols
{
    Atom *protocols;
    int n, i;

    _does_wm_take_focus = NO;
    _does_wm_delete_window = NO;

    if (XGetWMProtocols (x_dpy, _id, &protocols, &n) != 0)
    {
        for (i = 0; i < n; i++)
        {
            if (protocols[i] == atoms.wm_take_focus)
                _does_wm_take_focus = YES;
            else if (protocols[i] == atoms.wm_delete_window)
                _does_wm_delete_window = YES;
        }
        XFree (protocols);
    }
}

- (void) update_wm_hints
{
    if (_wm_hints != NULL)
        XFree (_wm_hints);

    _wm_hints = XGetWMHints (x_dpy, _id);
}

- (void) update_size_hints
{
    XGetWMNormalHints (x_dpy, _id, &_size_hints, &_size_hints_supplied);
    
    if ((_size_hints.flags & (PMinSize | PMaxSize)) == (PMinSize | PMaxSize) &&
        _size_hints.min_width >= _size_hints.max_width &&
        _size_hints.min_height >= _size_hints.max_height) {
        _resizable = NO;
    }
}

- (void) update_net_wm_type_hints
{
    long _atoms[33];
    int i, n;

    n = x_get_property (_id, atoms.net_wm_window_type, _atoms, 32, 0);

    /* Append the default type in case we see no understood types */
    if(_transient_for)
        _atoms[n++] = atoms.net_wm_window_type_dialog;
    else
        _atoms[n++] = atoms.net_wm_window_type_normal;
    
    for (i = 0; i < n; i++) {
        if((Atom)_atoms[i] == atoms.net_wm_window_type_combo ||
           (Atom)_atoms[i] == atoms.net_wm_window_type_dnd ||
           (Atom)_atoms[i] == atoms.net_wm_window_type_dropdown_menu ||
           (Atom)_atoms[i] == atoms.net_wm_window_type_notification ||
           (Atom)_atoms[i] == atoms.net_wm_window_type_popup_menu ||
           (Atom)_atoms[i] == atoms.net_wm_window_type_tooltip) {
            /* _NET_WM_WINDOW_TYPE_COMBO should be used on the windows that are
             * popped up by combo boxes. An example is a window that appears
             * below a text field with a list of suggested completions. This
             * property is typically used on override-redirect windows.
             */

            /* _NET_WM_WINDOW_TYPE_DND indicates that the window is being
             * dragged. Clients should set this hint when the window in
             * question contains a representation of an object being dragged
             * from one place to another. An example would be a window
             * containing an icon that is being dragged from one file manager
             * window to another. This property is typically used on
             * override-redirect windows.
             */

            /* _NET_WM_WINDOW_TYPE_DROPDOWN_MENU indicates that the window in
             * question is a dropdown menu, ie., the kind of menu that
             * typically appears when the user clicks on a menubar, as opposed
             * to a popup menu which typically appears when the user
             * right-clicks on an object. This property is typically used on
             * override-redirect windows.
             */

            /* _NET_WM_WINDOW_TYPE_NOTIFICATION indicates a notification. An
             * example of a notification would be a bubble appearing with
             * informative text such as "Your laptop is running out of power"
             * etc. This property is typically used on override-redirect
             * windows.
             */

            /* _NET_WM_WINDOW_TYPE_POPUP_MENU indicates that the window in
             * question is a popup menu, ie., the kind of menu that typically
             * appears when the user right clicks on an object, as opposed to a
             * dropdown menu which typically appears when the user clicks on a
             * menubar. This property is typically used on override-redirect
             * windows.
             */
            
            /* _NET_WM_WINDOW_TYPE_TOOLTIP indicates that the window in
             * question is a tooltip, ie., a short piece of explanatory text
             * that typically appear after the mouse cursor hovers over an
             * object for a while. This property is typically used on
             * override-redirect windows.
             */

            /* We should not be here because this type should be used for
             * override-redirect windows.  Just draw withour decoration.
             */

            _always_click_through = YES;
            _frame_behavior = XP_FRAME_CLASS_BEHAVIOR_TRANSIENT;
            _frame_decor = XP_FRAME_CLASS_DECOR_NONE;
            _in_window_menu = NO;
            _level = AppleWMWindowLevelTornOff;
            _movable = NO;
            _resizable = NO;
            _shadable = NO;

            break;
        } else if((Atom)_atoms[i] == atoms.net_wm_window_type_desktop) {
            /* _NET_WM_WINDOW_TYPE_DESKTOP indicates a desktop feature. This
             * can include a single window containing desktop icons with the
             * same dimensions as the screen, allowing the desktop environment
             * to have full control of the desktop, without the need for
             * proxying root window clicks.
             */

            _always_click_through = YES;
            _frame_behavior = XP_FRAME_CLASS_BEHAVIOR_TRANSIENT;
            _frame_decor = XP_FRAME_CLASS_DECOR_NONE;
            _in_window_menu = NO;
            _level = AppleWMWindowLevelDesktop;
            _movable = NO;
            _resizable = NO;
            _shadable = NO;

            break;
        } else if ((Atom)_atoms[i] == atoms.net_wm_window_type_dialog) {
            /* _NET_WM_WINDOW_TYPE_DIALOG indicates that this is a dialog
             * window. If _NET_WM_WINDOW_TYPE is not set, then windows with
             * WM_TRANSIENT_FOR set MUST be taken as this type.
             */

            _in_window_menu = NO;
            _frame_attr &= ~XP_FRAME_ATTR_ZOOM;

            break;
        } else if ((Atom)_atoms[i] == atoms.net_wm_window_type_dock) {
            /* _NET_WM_WINDOW_TYPE_DOCK indicates a dock or panel feature.
             * Typically a Window Manager would keep such windows on top of
             * all other windows.
             */

            /* Old versions of KDE had issues, so we used to leave dock windows
             * at the normal level, but that should not be the case any more.
             * <rdar://problem/3205836> tooltips from KDE kicker show behind the kicker
             */
            _always_click_through = YES;
            _frame_behavior = XP_FRAME_CLASS_BEHAVIOR_TRANSIENT;
            _frame_decor = XP_FRAME_CLASS_DECOR_NONE;
            _in_window_menu = NO;
            _level = AppleWMWindowLevelDock;
            _movable = NO;
            _resizable = NO;
            _shadable = NO;

            break;
        } else if ((Atom)_atoms[i] == atoms.net_wm_window_type_normal) {
            /* _NET_WM_WINDOW_TYPE_NORMAL indicates that this is a normal,
             * top-level window. Windows with neither _NET_WM_WINDOW_TYPE nor
             * WM_TRANSIENT_FOR set MUST be taken as this type.
             */

            /* We do this by default, so nothing to do here. */

            break;
        } else if ((Atom)_atoms[i] == atoms.net_wm_window_type_splash) {
            /* _NET_WM_WINDOW_TYPE_SPLASH indicates that the window is a splash
             * screen displayed as an application is starting up.
             */
            
            _always_click_through = YES;
            _frame_behavior = XP_FRAME_CLASS_BEHAVIOR_TRANSIENT;
            _frame_decor = XP_FRAME_CLASS_DECOR_NONE;
            _in_window_menu = NO;
            _level = AppleWMWindowLevelFloating;
            _movable = NO;
            _resizable = NO;
            _shadable = NO;

            break;
            
        } else if ((Atom)_atoms[i] == atoms.net_wm_window_type_menu ||
                   (Atom)_atoms[i] == atoms.net_wm_window_type_toolbar) {
            /* _NET_WM_WINDOW_TYPE_TOOLBAR and _NET_WM_WINDOW_TYPE_MENU
             * indicate toolbar and pinnable menu windows, respectively
             * (i.e. toolbars and menus "torn off" from the main application).
             * Windows of this type may set the WM_TRANSIENT_FOR hint
             * indicating the main application window. Note that the
             * _NET_WM_WINDOW_TYPE_MENU should be set on torn-off managed
             * windows, where _NET_WM_WINDOW_TYPE_DROPDOWN_MENU and
             * _NET_WM_WINDOW_TYPE_POPUP_MENU are typically used on
             * override-redirect windows.
             */

            _always_click_through = YES;
            _frame_behavior = XP_FRAME_CLASS_BEHAVIOR_TRANSIENT;
            _frame_decor = XP_FRAME_CLASS_DECOR_SMALL;
            _in_window_menu = NO;
            _level = AppleWMWindowLevelTornOff;
            _resizable = NO;
            _shadable = NO;

            break;            
        } else if ((Atom)_atoms[i] == atoms.net_wm_window_type_utility) {
            /* _NET_WM_WINDOW_TYPE_UTILITY indicates a small persistent utility
             * window, such as a palette or toolbox. It is distinct from type
             * TOOLBAR because it does not correspond to a toolbar torn off from
             * the main application. It's distinct from type DIALOG because it
             * isn't a transient dialog, the user will probably keep it open
             * while they're working. Windows of this type may set the
             * WM_TRANSIENT_FOR hint indicating the main application window.
             */

            _frame_behavior = XP_FRAME_CLASS_BEHAVIOR_TRANSIENT;
            _frame_decor = XP_FRAME_CLASS_DECOR_SMALL;
            _level = AppleWMWindowLevelFloating;
            _in_window_menu = NO;
            _always_click_through = YES;
            _resizable = NO;
            _shadable = NO;

            break;
        }
    }
}

- (void) update_net_wm_state_hints {
    long _atoms[32];
    int i, n;
    BOOL shaded = NO;
    BOOL maximized = NO;
    BOOL fullscreen = NO;

    n = x_get_property (_id, atoms.net_wm_state, _atoms, 32, 0);

    for (i = 0; i < n; i++)  {
        if ((Atom)_atoms[i] == atoms.net_wm_state_modal)
            _modal = YES;
        else if ((Atom)_atoms[i] == atoms.net_wm_state_shaded)
            shaded = YES;
        else if ((Atom)_atoms[i] == atoms.net_wm_state_skip_pager ||
                 (Atom)_atoms[i] == atoms.net_wm_state_skip_taskbar)
            _in_window_menu = NO;
        else if ((Atom)_atoms[i] == atoms.net_wm_state_fullscreen)
            fullscreen = YES;
        else if ((Atom)_atoms[i] == atoms.net_wm_state_maximized_horz ||
                 (Atom)_atoms[i] == atoms.net_wm_state_maximized_vert)
            maximized = YES;
        else if ((Atom)_atoms[i] == atoms.net_wm_state_sticky)
            _frame_behavior = XP_FRAME_CLASS_BEHAVIOR_STATIONARY;
    }

    if(_frame_attr & XP_FRAME_ATTR_ZOOM) {
        if(fullscreen)
            [self do_fullscreen:YES]; // Can set !_shadable
        else if(maximized)
            [self do_maximize];
    }

    if (_shaded && !shaded)
        [self do_unshade:CurrentTime];
    else if (!_shaded && shaded && _shadable && window_shading)
        [self do_shade:CurrentTime];
}

- (void) update_net_wm_state_property
{
    long _atoms[32];
    int n_atoms = 0;

    TRACE();
    
    if(_modal)
        _atoms[n_atoms++] = atoms.net_wm_state_modal;
    if(_minimized)
        _atoms[n_atoms++] = atoms.net_wm_state_hidden;
    if(_shaded)
        _atoms[n_atoms++] = atoms.net_wm_state_shaded;
    if(!_in_window_menu) {
        _atoms[n_atoms++] = atoms.net_wm_state_skip_pager;
        _atoms[n_atoms++] = atoms.net_wm_state_skip_taskbar;
    }
    if(_fullscreen)
        _atoms[n_atoms++] = atoms.net_wm_state_fullscreen;
    if([self is_maximized]) {
        _atoms[n_atoms++] = atoms.net_wm_state_maximized_horz;
        _atoms[n_atoms++] = atoms.net_wm_state_maximized_vert;
    }
    if(_frame_behavior == XP_FRAME_CLASS_BEHAVIOR_STATIONARY)
        _atoms[n_atoms++] = atoms.net_wm_state_sticky;

    XChangeProperty (x_dpy, _id, atoms.net_wm_state,
                     atoms.atom, 32, PropModeReplace, (unsigned char *) _atoms,
                     n_atoms);
}

- (void) do_net_wm_state_change:(int)mode atom:(Atom)state
{
    /* _NET_WM_STATE_REMOVE        0    remove/unset property
     * _NET_WM_STATE_ADD           1    add/set property
     * _NET_WM_STATE_TOGGLE        2    toggle property
     */
    
    DB("Atom: %s Action: %s\n", str_for_atom(state), mode ? (mode == 1 ? "_NET_WM_STATE_ADD" : "_NET_WM_STATE_TOGGLE") : "_NET_WM_STATE_REMOVE");
    
    if(state == atoms.net_wm_state_shaded) {
        if (mode == 0 || (mode == 2 && _shaded))
            [self do_unshade:CurrentTime];
        else
            [self do_shade:CurrentTime];
    } else if (state == atoms.net_wm_state_skip_taskbar ||
               state == atoms.net_wm_state_skip_pager) {
        if (mode == 0)
            _in_window_menu = YES;
        else if (mode == 1)
            _in_window_menu = NO;
        else
            _in_window_menu = !_in_window_menu;

        if (_in_window_menu)
            x_add_window_to_menu (self);
        else
            x_remove_window_from_menu (self);
    } else if(state == atoms.net_wm_state_maximized_horz ||
              state == atoms.net_wm_state_maximized_vert) {
        BOOL maximized = [self is_maximized];
        if(mode == 1 || (mode == 2 && !maximized))
            [self do_maximize];
        else if(maximized)
            [self do_zoom];
    } if(state == atoms.net_wm_state_sticky) {
        if(mode == 1 || (mode == 2 && _frame_behavior != XP_FRAME_CLASS_BEHAVIOR_STATIONARY))
            _frame_behavior = XP_FRAME_CLASS_BEHAVIOR_STATIONARY;
        else
            _frame_behavior = XP_FRAME_CLASS_BEHAVIOR_MANAGED;
        // We don't care about the TRANSIENT case because we'll update it in update_frame:
    } else if(state == atoms.net_wm_state_fullscreen) {
        [self do_fullscreen:(mode == 1 || (mode == 2 && !_fullscreen))];
    } else if(state == atoms.net_wm_state_modal) {
        _modal = (state == 1 || (mode == 2 && !_modal));
    }

    DB("update_net_wm_state_property from do_net_wm_state_change\n");
    [self update_net_wm_state_property];
    [self update_frame];
}

- (void) update_net_wm_action_property
{
    long _atoms[32];
    int n_atoms = 0;

    if (_movable)
        _atoms[n_atoms++] = atoms.net_wm_action_move;
    if (_resizable)
        _atoms[n_atoms++] = atoms.net_wm_action_resize;
    if (_frame_attr & XP_FRAME_ATTR_COLLAPSE)
        _atoms[n_atoms++] = atoms.net_wm_action_minimize;
    if (_shadable && window_shading)
        _atoms[n_atoms++] = atoms.net_wm_action_shade;
    if (_frame_attr & XP_FRAME_ATTR_ZOOM)
    {
        _atoms[n_atoms++] = atoms.net_wm_action_maximize_horz;
        _atoms[n_atoms++] = atoms.net_wm_action_maximize_vert;
        _atoms[n_atoms++] = atoms.net_wm_action_fullscreen;
    } else if (_fullscreen) {
        // We strip XP_FRAME_ATTR_ZOOM while in fullscreen
        _atoms[n_atoms++] = atoms.net_wm_action_fullscreen;
    }
    if ((_frame_attr & XP_FRAME_ATTR_CLOSE_BOX) && ![self has_modal_descendents]) {
        _atoms[n_atoms++] = atoms.net_wm_action_close;
    }

    XChangeProperty (x_dpy, _id, atoms.net_wm_allowed_actions, atoms.atom,
                     32, PropModeReplace, (unsigned char *) _atoms, n_atoms);
}

- (void) update_motif_hints
{
    long hints[4];
    int n;

    memset (hints, 0, sizeof (hints));
    n = x_get_property (_id, atoms.motif_wm_hints, hints, 4, 1);

    if(n == 0)
        return;

    if (hints[0] & 1)
    {
        /* hints[1] = functional hints */

        if (!(hints[1] & 3))
            _frame_attr &= ~XP_FRAME_ATTR_GROW_BOX;
        if (!(hints[1] & 9))
            _frame_attr &= ~XP_FRAME_ATTR_COLLAPSE;
        if (!(hints[1] & 17))
            _frame_attr &= ~XP_FRAME_ATTR_ZOOM;
        if (!(hints[1] & 33))
            _frame_attr &= ~XP_FRAME_ATTR_CLOSE_BOX;
    }
    if (hints[0] & 2)
    {
        /* hints[2] = decoration hints */

        if (!(hints[2] & 9)) {
            _frame_decor = XP_FRAME_CLASS_DECOR_NONE;
            _frame_attr &= ~XP_FRAME_ATTR_GROW_BOX;
        }
    }
    if (hints[3] != 0)
    {
        /* hints[3] = input class */

        switch (hints[3])
        {
            case 1:
            case 2:
            case 3:
                _modal = YES;
        }
    }
}

- (void) update_frame
{
    int old_level = _level;

    TRACE();
    
    /* Start with the default set. */
    _always_click_through = NO;
    _frame_attr  |= (XP_FRAME_ATTR_CLOSE_BOX | XP_FRAME_ATTR_COLLAPSE | XP_FRAME_ATTR_ZOOM | XP_FRAME_ATTR_GROW_BOX);
    _frame_behavior = XP_FRAME_CLASS_BEHAVIOR_MANAGED;
    _frame_decor = XP_FRAME_CLASS_DECOR_LARGE;
    _in_window_menu = YES;
    _level = AppleWMWindowLevelNormal;
    _modal = NO;
    _movable = YES;
    _resizable = YES;
    _shadable = YES;
    
    [self update_size_hints]; // Can set !_resizable
    [self update_motif_hints];
    [self update_net_wm_type_hints];
    [self update_net_wm_state_hints];
    
    /* Handle determined properties */
    if(_modal) {
        _in_window_menu = NO;
        _frame_attr &= ~(XP_FRAME_ATTR_ZOOM | XP_FRAME_ATTR_COLLAPSE);
    }
    
    if(!_resizable) {
        _frame_attr &= ~(XP_FRAME_ATTR_ZOOM | XP_FRAME_ATTR_GROW_BOX);
    }

    _frame_title_height = frame_titlebar_height([self get_xp_frame_class]);
    
    /* Notify listeners about our updated properties */
    [self update_net_wm_action_property];
    DB("update_net_wm_state_property from update_frame\n");
    [self update_net_wm_state_property];

    /* Only adjust if we're already reparented */
    if(_reparented) {
        xp_frame_class pending_frame_decor = [self get_xp_frame_class] & XP_FRAME_CLASS_DECOR_MASK;
        
        DB("id: 0x%x frame_id: 0x%x old decor: 0x%x new decor: 0x%x%s\n", _id,
           _frame_id, _drawn_frame_decor, pending_frame_decor,
           (pending_frame_decor == _drawn_frame_decor) ? "" : " FRAME CHANGE");

        /* Handle difficult task of dealing with XP_FRAME_CLASS_DECOR changing */
        if(pending_frame_decor != _drawn_frame_decor) {
            BOOL need_resize_frame = (_pending_frame_change || _queued_frame_change);
            X11Rect new_frame_size;
            
            if(_queued_frame_change)
                new_frame_size = _queued_frame;
            else if(_pending_frame_change)
                new_frame_size = _pending_frame;
            
            [self reparent_out];
            [self reparent_in];
            
            if(need_resize_frame)
                [self resize_frame:new_frame_size force:YES];

            [self map_unmap_client];
            if(_reparented)
                XMapWindow(x_dpy, _frame_id);

            /* If we are focused, we need to re-acquire input focus after changing fullscreen
             * status because we have a new frame_id */
            if(_focused)
                [self focus:CurrentTime raise:YES force:YES];

            XAppleWMSetWindowLevel(x_dpy, _frame_id, _level);
        } else if(_level != old_level) {
            XAppleWMSetWindowLevel(x_dpy, _frame_id, _level);
        }

        [self decorate];
    }
}

- (void) update_parent
{
    long data;
    Window wm_transient_for = 0;

    if(x_get_property(_id, atoms.wm_transient_for, &data, 1, 1))
        wm_transient_for = data;

    if(wm_transient_for != _transient_for_id) {
        /* We have a change */

        /* Remove this window from the parent's transient list */
        if(_transient_for) {
            _transient_for->_transients = x_list_remove(_transient_for->_transients, self);
        }

        /* Set our local state */
        _transient_for_id = wm_transient_for;
        if(_transient_for_id == 0 ||
           (_transient_for = x_get_window(_transient_for_id)) == NULL) {

            /* Not transient */
            _transient_for_id = 0;
            _transient_for = NULL;
        } else {
            /* Update the parent's transients */
            _transient_for->_transients = x_list_prepend(_transient_for->_transients, self);
        }
    }

    /* We do this outside of the change-check since get_osx_id can be NULL during init or
     * can change when we change XP_FRAME_CLASS_DECOR.
     */
    if([self get_osx_id] != XP_NULL_NATIVE_WINDOW_ID) {
        if(_XAppleWMAttachTransient) {
            Window transient_frame_id = _transient_for ? _transient_for->_frame_id : 0;
            _XAppleWMAttachTransient(x_dpy, _frame_id, transient_frame_id);
        }
    }
}

- (void) update_group
{
    if (_wm_hints != NULL && (_wm_hints->flags & WindowGroupHint) != 0)
        _group_id = _wm_hints->window_group;
    else if (_transient_for)
        _group_id = _transient_for->_group_id;
    else
        _group_id = _id;
}

- (void) property_changed:(Atom)atom
{
    DB("Atom: %s %ld\n", str_for_atom(atom), atom);

    if(atom == atoms.wm_name ||
       atom == atoms.net_wm_name) {
        [self update_wm_name];
    } else if (atom == atoms.wm_transient_for) {
        [self update_parent];
        [self update_group];
        [self update_frame];
    } else if(atom == atoms.wm_hints) {
        [self update_wm_hints];
        [self update_group];
    } else if(atom == atoms.wm_normal_hints ||
              atom == atoms.wm_protocols) {
        [self update_frame];
    } else if (atom == atoms.native_window_id) {
        _osx_id = XP_NULL_NATIVE_WINDOW_ID;

        /* XAppleWMAttachTransient needs to be called again when the native_window_id changes
         *
         * TODO: Handle this in the server? Xplugin?
         */
        [self update_parent];
        if(_transients) {
            x_list *node;
            for(node = _transients; node; node = node->next) {
                x_window *child = node->data;
                [child update_parent];
            }
        }
    } else if (atom == atoms.wm_colormap_windows) {
        [self update_colormaps];
    }
}

- (BOOL) my_dialog:(x_window *)w {
    x_window *ptr, *next;
    x_list *seen = NULL;
    BOOL ret = NO;

    for (ptr = w; ptr != NULL && ptr->_transient_for; ptr = next) {
        if (ptr->_transient_for == self) {
            ret = YES;
            break;
        }

        if(x_list_find(seen, ptr))
            break;

        seen = x_list_prepend (seen, ptr);
        next = ptr->_transient_for;
    }

    x_list_free(seen);
    return ret;
}

- (x_list *) transient_group {
    x_list *group, *node, *ptr;
    BOOL again;

    /* FIXME: this "algorithm" sucks */

    group = x_list_prepend(NULL, self);

    do {
        again = NO;

        for(node = _screen->_window_list; node != NULL; node = node->next) {
            x_window *w = node->data;

            if(x_list_find(group, w))
                continue;

            if(w->_transient_for && x_list_find(group, w->_transient_for)) {
                group = x_list_prepend(group, w);
                again = YES;
            } else {
                for (ptr = group; ptr != NULL; ptr = ptr->next) {
                    x_window *p = ptr->data;
                    if(p->_transient_for == w) {
                        group = x_list_prepend(group, w);
                        again = YES;
                        break;
                    }
                }
            }
        }
    } while (again);

    return group;
}

- (x_list *) window_group
{
    x_list *group, *node;

    group = NULL;

    for (node = _screen->_window_list; node != NULL; node = node->next)
    {
        x_window *w = node->data;

        if (w->_group_id == _group_id)
        {
            group = x_list_prepend (group, w);
        }
    }

    return group;
}

- (void) raise
{
    x_list *group, *order, *node;
    x_window **ids;
    size_t out;

    if (_removed)
        return;

    _pending_raise = NO;

    group = [self transient_group];
    order = x_list_remove ([_screen stacking_order:group], self);
    x_list_free (group);

    if (order == NULL)
    {
        /* Simple case, we're the only group member. */

        [_screen raise_windows:&self count:1];
        return;
    }

    /* Harder case. Work down the list until we find a window that's
     not a dialog for us. That's where we insert ourselves. */

    ids = alloca (sizeof (x_window *) * (x_list_length (order) + 1));
    out = 0;

    for (node = order; node != NULL; node = node->next)
    {
        x_window *w = node->data;

        if (![self my_dialog:w])
        {
            /* Found our insertion point. */
            ids[out++] = self;
            break;
        }

        ids[out++] = w;
    }

    if (node == NULL)
    {
        ids[out++] = self;
    }
    else
    {
        for (; node != NULL; node = node->next)
            ids[out++] = node->data;
    }

    [_screen raise_windows:ids count:out];

    x_list_free (order);
}

- (BOOL) focus:(Time)timestamp raise:(BOOL)raise force:(BOOL)force
{
    BOOL changed;

    TRACE ();

    if (_removed)
        return NO;

    if (raise)
    {
        if (x_get_is_active ())
            [self raise];
        else
            _pending_raise = YES;
    }

    if (!force && _focused)		/* FIXME: race condition? */
        return NO;

    changed = NO;

    if (_wm_hints == NULL
        || (_wm_hints->flags & InputHint) == 0
        || _wm_hints->input != 0)
    {
        XSetInputFocus (x_dpy, !_shaded ? _id : _frame_id,
                        RevertToNone, timestamp);
        changed = YES;
    }

    if (!_shaded && _does_wm_take_focus)
    {
        XEvent e;

        e.xclient.type = ClientMessage;
        e.xclient.window = _id;
        e.xclient.message_type = atoms.wm_protocols;
        e.xclient.format = 32;
        e.xclient.data.l[0] = atoms.wm_take_focus;
        e.xclient.data.l[1] = timestamp;

        XSendEvent (x_dpy, _id, False, 0, &e);

        changed = YES;
    }

    return changed;
}

- (BOOL) focus:(Time)timestamp raise:(BOOL)raise
{
    return [self focus:timestamp raise:raise force:NO];
}

- (BOOL) focus:(Time)timestamp
{
    return [self focus:timestamp raise:YES force:NO];
}

- (void) set_is_active:(BOOL)state
{
    unsigned int orig_attr = _frame_attr;

    if (state)
        _frame_attr |= XP_FRAME_ATTR_ACTIVE;
    else
        _frame_attr &= ~XP_FRAME_ATTR_ACTIVE;

    if (_frame_attr != orig_attr)
        [self decorate];

    if (_pending_raise)
        [self raise];
}

- (void) show
{
    TRACE ();

    [self do_unhide];

    if (_minimized)
        [self do_uncollapse_and_tell_dock:YES with_animation:YES];
}

- (void) activate:(Time)timestamp
{
    TRACE ();

    [self show];

    [self focus:timestamp raise:YES];
}

- (void) x_focus_in
{
    long data;

    TRACE ();

    if (_focused)
        return;

    _focused = YES;
    [self install_colormaps];

    x_set_active_window (self);

    data = _id;
    [_screen set_root_property:"_NET_ACTIVE_WINDOW"
                          type:"WINDOW" length:1 data:&data];
}

- (void) x_focus_out
{
    TRACE ();

    _pending_raise = NO;

    if (!_focused)
        return;

    _focused = NO;

    x_set_active_window (nil);
}

- (void) update_state:(NSTimer *)timer
{
    BOOL state;

    if (_deleted)
        return;

    state = x_get_is_active () && x_get_active_window () == self;
    [self set_is_active:state];

    if (state && !_focused)
        [self focus:CurrentTime raise:NO];

    if (_pending_raise)
        [self raise];

    XFlush (x_dpy);
}

- (void) dealloc {
    TRACE ();

    if(_wm_hints != NULL)
        XFree (_wm_hints);

    if(_title != NULL)
        [_title release];

    if(_n_colormap_windows > 0)
        XFree (_colormap_windows);

    if(_shortcut_index != 0)
        x_release_window_shortcut (_shortcut_index);

    if(_transients)
        x_list_free(_transients);

    [super dealloc];
}

- (unsigned) hit_test_frame:(X11Point)p {
    X11Rect or, ir;
    unsigned int attr;

    or = [self frame_outer_rect];
    ir = [self frame_inner_rect:or];

    attr = frame_hit_test(or, ir, [self get_xp_frame_class], p);

    /* Only return buttons that we actually have */
    attr &= _frame_attr;

    if([self has_modal_descendents])
        attr &= ~XP_FRAME_ATTR_CLOSE_BOX;
    if (_tracking_id != 0 && X11RectContainsPoint (_tracking_rect, p))
        attr |= XP_FRAME_ATTR_PRELIGHT;
    if (_growbox_id != 0 && X11RectContainsPoint (_growbox_rect, p))
        attr |= XP_FRAME_ATTR_GROW_BOX;

    return attr;
}

- (void) map_unmap_client
{
    BOOL unmapped = _shaded || _hidden || _minimized || _unmapped;

    if (unmapped && !_client_unmapped)
    {
        BEFORE_LOCAL_MAP;
        XUnmapWindow (x_dpy, _id);
        AFTER_LOCAL_MAP;
    }
    else if (!unmapped && _client_unmapped)
    {
        BEFORE_LOCAL_MAP;
        XMapWindow (x_dpy, _id);
        AFTER_LOCAL_MAP;
    }

    _client_unmapped = unmapped;
}

- (void) do_close:(Time)timestamp
{
    TRACE ();

    if (_does_wm_delete_window)
    {
        XEvent e;

        e.xclient.type = ClientMessage;
        e.xclient.window = _id;
        e.xclient.message_type = atoms.wm_protocols;
        e.xclient.format = 32;
        e.xclient.data.l[0] = atoms.wm_delete_window;
        e.xclient.data.l[1] = timestamp;

        XSendEvent (x_dpy, _id, False, 0, &e);
    }
    else
    {
        XKillClient (x_dpy, _id);
    }
}

- (void) collapse_finished:(BOOL)success
{
    _animating = NO;

    DB("success:%s\n", success ? "YES" : "NO");

    if (!success) {
        _minimized = NO;
        _minimized_osx_id = XP_NULL_NATIVE_WINDOW_ID;
        return;
    }

    XUnmapWindow (x_dpy, _frame_id);
    [self set_wm_state:IconicState];
    [self map_unmap_client];

    [_screen window_hidden:self];
}

- (void) do_collapse
{
    xp_native_window_id wid;
    OSStatus err;
    char *title_c;

    DB ("_minimized: %s _animating: %s\n", _minimized ? "YES" : "NO", _animating ? "YES" : "NO");

    if (_minimized || _animating)
        return;

    wid = [self get_osx_id];
    if (wid == XP_NULL_NATIVE_WINDOW_ID)
        return;

    title_c = strdup([[self title] UTF8String]);
    assert(title_c);

    err = qwm_dock_minimize_item_with_title_async (wid, title_c);
    free(title_c);

    if (err == noErr)
    {
        _animating = YES;
        _minimized = YES;
        _minimized_osx_id = wid;
    }
    else
    {
        fprintf (stderr, "couldn't minimize window: %d\n", (int) err);
    }
}

- (void) uncollapse_finished:(BOOL)success
{
    _animating = NO;
    _minimized = !success;

    DB("success:%s\n", success ? "YES" : "NO");

    XDeleteProperty (x_dpy, _frame_id, atoms.apple_no_order_in);

    if(success)
        [self raise];
}

- (void) do_uncollapse_and_tell_dock:(BOOL)tell_dock with_animation:(BOOL)anim
{
    OSStatus err = noErr;
    long data = 1;

    DB ("tell_dock: %s with_animation: %s _animating: %s\n", tell_dock ? "YES" : "NO", anim ? "YES" : "NO", _animating ? "YES" : "NO");

    if (!_minimized || (anim && _animating))
        return;

    _minimized = NO;

    if (_minimized_osx_id == XP_NULL_NATIVE_WINDOW_ID)
        return;

    [self map_unmap_client];

    /* Need to map the frame here, so that it has content when genieing.
     But we don't want the physical window ordered in yet, since that
     will cause flicker if it beats the Dock to its first animation
     state. So we have a hack in the X server to check for this
     property when restacking windows. */

    XChangeProperty (x_dpy, _frame_id, atoms.apple_no_order_in,
                     atoms.apple_no_order_in, 32,
                     PropModeReplace, (unsigned char *) &data, 1);
    XMapWindow (x_dpy, _frame_id);

    if(tell_dock) {
        if (anim)
            err = qwm_dock_restore_item_async (_minimized_osx_id);
        else
            err = qwm_dock_remove_item (_minimized_osx_id);
    }

    if (err == noErr) {
        _animating = YES;
        _minimized_osx_id = XP_NULL_NATIVE_WINDOW_ID;
        [self set_wm_state:NormalState];
        [self send_configure];

        if (!(tell_dock && anim))
            [self uncollapse_finished:YES];
    } else {
        fprintf (stderr, "couldn't restore window: %d\n", (int) err);

        _minimized = YES;

        [self map_unmap_client];
        XUnmapWindow (x_dpy, _frame_id);
    }
}

- (void) do_uncollapse_and_tell_dock:(BOOL)tell_dock
{
    /* If we don't want to tell the dock, we don't want to animate either */
    [self do_uncollapse_and_tell_dock:tell_dock with_animation:tell_dock];
}

- (void) do_uncollapse
{
    [self do_uncollapse_and_tell_dock:TRUE with_animation:TRUE];
}

- (void) error_shutdown
{
    /* Called when we're terminating abnormally. Can't make any
     X protocol requests. */

    if (_minimized_osx_id != XP_NULL_NATIVE_WINDOW_ID)
    {
        qwm_dock_remove_item (_minimized_osx_id);
        _minimized_osx_id = XP_NULL_NATIVE_WINDOW_ID;
    }
}

- (void) do_shade:(Time)timestamp
{
    X11Rect r;

    if (_shaded)
        return;

    TRACE ();

    _shaded = YES;
    _frame_attr |= XP_FRAME_ATTR_SHADED;

    r = _current_frame;
    r.height = _frame_height;
    [self resize_frame:r force:YES];

    [self map_unmap_client];

    if (_focused)
        [self focus:timestamp raise:YES force:YES];

    DB("update_net_wm_state_property from do_shade\n");
    [self update_net_wm_state_property];
}

- (void) do_unshade:(Time)timestamp
{
    X11Rect r;

    if (!_shaded)
        return;

    TRACE ();

    _shaded = NO;
    _frame_attr &= ~XP_FRAME_ATTR_SHADED;

    [self map_unmap_client];

    r = _current_frame;
    r.height = _frame_height;
    [self resize_frame:r force:YES];

    if (_focused)
        [self focus:timestamp raise:YES force:NO];

    DB("update_net_wm_state_property from do_unshade\n");
    [self update_net_wm_state_property];
}

- (void) do_toggle_shaded:(Time)timestamp
{
    if (!_shaded)
        [self do_shade:timestamp];
    else
        [self do_unshade:timestamp];
}

- (BOOL) is_maximized
{
    X11Rect r = [self intended_frame];
    return X11RectEqualToRect(r, [self validate_frame_rect:[_screen zoomed_rect:X11RectOrigin(r)]]);
}

- (void) do_zoom {
    X11Rect r = [self intended_frame];
    X11Rect new_rect;

    TRACE ();

    if (!_has_unzoomed_frame) {
        _unzoomed_frame = r;
        _has_unzoomed_frame = YES;
    }

    if([self is_maximized]) {
        new_rect = [self validate_frame_rect:_unzoomed_frame];
    } else {
        new_rect = [self validate_frame_rect:[_screen zoomed_rect:X11RectOrigin(r)]];
        _unzoomed_frame = r;
    }

    [self resize_frame:new_rect];
}

- (void) do_maximize {

    TRACE ();

    if(![self is_maximized]) {
        X11Rect r = [self intended_frame];
        X11Rect maximized_rect = [self validate_frame_rect:[_screen zoomed_rect:X11RectOrigin(r)]];

        _unzoomed_frame = r;
        _has_unzoomed_frame = YES;

        [self resize_frame:maximized_rect];
    }
}

/* This is purely X11-focused.  We don't do anything with OSX's presentation
 * mode.  After calling this, we need to reparent_out and reparent_in to update
 * the actual frame for Xplugin (done in update_frame).
 */
- (void) do_fullscreen:(BOOL) flag {

    DB("id: 0x%x frame_id: 0x%x currently: %d requested: %d\n", _id, _frame_id, _fullscreen, flag);

    if(flag) {
        _movable = NO;
        _resizable = NO;
        _shadable = NO;
        if(_shaded)
            [self do_unshade:CurrentTime];
    }

    if(_fullscreen == flag)
        return;

    if(flag) {
        X11Rect r = [self intended_frame];
        X11Rect maximized_rect = [self validate_frame_rect:[_screen zoomed_rect:X11RectOrigin(r)]];

        _unzoomed_frame = r;
        _has_unzoomed_frame = YES;

        [self resize_frame:maximized_rect force:YES];
    } else {
        [self resize_frame:[self validate_frame_rect:_unzoomed_frame] force:YES];
    }

    _fullscreen = flag;

    DB("update_net_wm_state_property from do_fullscreen\n");
    [self update_net_wm_state_property];
}

- (void) do_hide
{
    if (_hidden)
        return;

    TRACE ();

    _hidden = YES;

    if (_reparented)
    {
        XUnmapWindow (x_dpy, _frame_id);
    }

    [self map_unmap_client];
}

- (void) do_unhide
{
    if (!_hidden)
        return;

    TRACE ();

    _hidden = NO;

    [self map_unmap_client];

    if (_reparented && !_minimized)
    {
        XMapWindow (x_dpy, _frame_id);
        [self decorate];
    }
}

static int
constrain_1 (int x, int base, int minimum, int maximum, int inc)
{
    int bottom = base ? base : minimum ? minimum : 1;

    if (inc > 1 && (x - bottom) % inc != 0)
    {
        x = bottom + (((x - bottom) / inc)) * inc;
    }

    if (x < minimum)
        x = minimum;
    else if (maximum > 0 && x > maximum)
        x = maximum;

    return x;
}

static int
get_logical_1 (int x, int base, int minimum, int inc)
{
    int bottom = base ? base : minimum ? minimum : 1;

    if (inc <= 1)
        return x - bottom;
    else
        return (x - bottom) / inc;
}

static void
decode_size_hints (XSizeHints *hints, int base[2], int min[2],
                   int max[2], int inc[2])
{
    if (hints->flags & PMinSize)
    {
        min[0] = hints->min_width;
        min[1] = hints->min_height;
    }
    else
        min[0] = min[1] = 0;

    if (hints->flags & PMaxSize)
    {
        max[0] = hints->max_width;
        max[1] = hints->max_height;
    }
    else
        max[0] = max[1] = 0;

    if (hints->flags & PBaseSize)
    {
        base[0] = hints->base_width;
        base[1] = hints->base_height;
    }
    else
        base[0] = base[1] = 0;

    if (hints->flags & PResizeInc)
    {
        inc[0] = hints->width_inc;
        inc[1] = hints->height_inc;
    }
    else
        inc[0] = inc[1] = 0;
}

- (X11Size) validate_window_size:(X11Rect)r
                       from_user:(BOOL)uflag constrain:(BOOL)cflag
{
    int base[2], min[2], max[2], inc[2];

    decode_size_hints (&_size_hints, base, min, max, inc);

    if (!uflag)
    {
        X11Size s;
        /* Constrain maximum size to head dimensions. */

        if (limit_window_size)
            s = X11RectSize([_screen zoomed_rect:X11RectOrigin(r)]);
        else
            s = X11SizeMake(_screen->_width, _screen->_height);

        // _frame_border_width
        max[0] = (max[0] > 0 ? MIN (max[0], s.width)
                  : s.width);
        max[1] = (max[1] > 0 ? MIN (max[1], s.height)
                  : s.height - _frame_title_height);
    }

    if (!cflag)
    {
        inc[0] = inc[1] = 1;
    }

    r.width = constrain_1 (r.width, base[0],
                           min[0], max[0], inc[0]);
    r.height = constrain_1 (r.height, base[1],
                            min[1], max[1], inc[1]);

    r.width = MAX (72, r.width);
    r.height = MAX (16, r.height);

    return X11RectSize(r);
}

- (X11Size) validate_window_size:(X11Rect)r
{
    return [self validate_window_size:r from_user:NO constrain:YES];
}

- (X11Rect) validate_client_rect:(X11Rect)r
{
    X11Size s = [self validate_window_size:r];
    r.width = s.width;
    r.height = s.height;
    return [_screen validate_window_position:r titlebar_height:_frame_title_height];
}

- (X11Rect) validate_frame_rect:(X11Rect)r
                      from_user:(BOOL)uflag constrain:(BOOL)cflag
{
    X11Size s;
    r.height -= _frame_title_height;
    s = [self validate_window_size:r from_user:uflag constrain:cflag];
    r.width = s.width;
    r.height = s.height + _frame_title_height;
    return [_screen validate_window_position:r titlebar_height:_frame_title_height];
}

- (X11Rect) validate_frame_rect:(X11Rect)r from_user:(BOOL)flag;
{
    return [self validate_frame_rect:r from_user:flag constrain:YES];
}

- (X11Rect) validate_frame_rect:(X11Rect)r
{
    return [self validate_frame_rect:r from_user:NO constrain:YES];
}

- (NSString *) resizing_title
{
    X11Rect r;
    int base[2], min[2], max[2], inc[2];
    int w, h;

    if ((_size_hints.flags & PResizeInc) == 0)
        return nil;

    r = _pending_frame_change ? _pending_frame : _current_frame;
    r.height -= _frame_title_height;

    decode_size_hints (&_size_hints, base, min, max, inc);

    w = get_logical_1 (r.width, base[0], min[0], inc[0]);
    h = get_logical_1 (r.height, base[1], min[1], inc[1]);

    return [NSString stringWithFormat:@"%dx%d", (int)w, (int)h];
}

- (void) set_resizing_title:(X11Rect)r
{
    if (!_resizing_title)
    {
        _resizing_title = YES;
        [self decorate];
    }
}

- (void) remove_resizing_title
{
    if (_resizing_title)
    {
        _resizing_title = NO;
        [self decorate];
    }
}

- (void) update_colormaps
{
    if (_n_colormap_windows > 0)
        XFree (_colormap_windows);

    if (!XGetWMColormapWindows (x_dpy, _id, &_colormap_windows,
                                &_n_colormap_windows))
    {
        _n_colormap_windows = 0;
    }

    if (_focused)
        [self install_colormaps];
}

- (void) install_colormaps
{
    BOOL done_this_one = NO;
    XWindowAttributes attr;
    int i;

    if (_n_colormap_windows > 0)
    {
        for (i = _n_colormap_windows - 1; i >= 0; i--)
        {
            XGetWindowAttributes (x_dpy, _colormap_windows[i], &attr);
            XInstallColormap (x_dpy, attr.colormap);

            if (_colormap_windows[i] == _id)
                done_this_one = YES;
        }
    }

    if (!done_this_one)
    {
        XGetWindowAttributes (x_dpy, _id, &attr);
        XInstallColormap (x_dpy, attr.colormap);
    }
}

- (NSString *)description
{
    if (_title != nil)
        return [NSString stringWithFormat:@"{x-window %@}", _title];
    else
        return [NSString stringWithFormat:@"{x-window 0x%x}", _id];
}

- (X11Rect) intended_frame
{
    X11Rect r;

    if (_queued_frame_change)
        r = _queued_frame;
    else if (_pending_frame_change)
        r = _pending_frame;
    else
        r = _current_frame;

    return r;
}

@end
