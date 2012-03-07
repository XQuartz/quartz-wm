/* x-window.h
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

#ifndef X_WINDOW_H
#define X_WINDOW_H 1

#import "x-screen.h"
#include "x-list.h"
#include "frame.h"

#include <X11/Xutil.h>

@interface x_window : NSObject
{
@public
    Window _id;
    Window _frame_id;
    Window _group_id;

    X11Rect _current_frame;

    Window _tracking_id;
    X11Rect _tracking_rect;

    Window _growbox_id;
    X11Rect _growbox_rect;

    x_screen *_screen;

    /*_xattr is for the Window _id, NOT _frame_id.  Note that this is also
     * contains the x/y from a ConfigureRequestEvent or XGetWindowAttributes
     * This is NOT the actual position (inner or outer) since these coordinates
     * need to go through a transformation based on the window's gravity setting.
     */
    XWindowAttributes _xattr;

    xp_frame_attr  _frame_attr;

    int _frame_title_height;

    int _level;

    unsigned _reparented :1;
    unsigned _shaped :1;
    unsigned _shaped_empty :1;
    unsigned _removed :1;
    unsigned _deleted :1;
    unsigned _focused :1;
    unsigned _minimized :1;
    unsigned _unmapped :1;
    unsigned _always_click_through :1;
    unsigned _movable :1;
    unsigned _shadable :1;

    NSString *_title;
    int _shortcut_index;		/* 0 for unset */

@private
    unsigned _set_shape :1;
    unsigned _decorated :1;
    unsigned _fullscreen :1;
    unsigned _resizable :1;
    unsigned _animating :1;		/* (by the dock) */
    unsigned _shaded :1;
    unsigned _hidden :1;
    unsigned _client_unmapped :1;
    unsigned _does_wm_take_focus :1;
    unsigned _does_wm_delete_window :1;
    unsigned _pending_frame_change :1;
    unsigned _queued_frame_change :1;
    unsigned _has_unzoomed_frame :1;
    unsigned _pending_decorate :1;
    unsigned _resizing_title :1;
    unsigned _needs_configure_notify :1;
    unsigned _modal :1;
    unsigned _in_window_menu :1;
    unsigned _pending_raise :1;

    /* This differs from _current_frame.height in that it is the height
     * when the frame is not shaded.
     */
    int _frame_height;

    /* "pending" is new frame bounds we've dispatched to X server, but
     not yet seen come through in a configure-notify. "queued" is a
     new set of bounds we want to set, but won't until we've seen
     the configure-notify from the "pending" change. */

    X11Rect _pending_frame;
    X11Rect _queued_frame;
    X11Rect _unzoomed_frame;

    /* Stored result from XGetWMHints() and XGetWMNormalHints() */
    XWMHints *_wm_hints;

    /* Stored result from XGetWMNormalHints() */
    XSizeHints _size_hints;
    long _size_hints_supplied;

    xp_frame_class _frame_decor;
    xp_frame_class _frame_behavior;

    Window *_colormap_windows;
    int _n_colormap_windows;

    /* Store what our decorations were the last time we drew the frame.
     * This is different from _frame_decor because it may be NONE due
     * to _fullscreen.
     */
    xp_frame_class _drawn_frame_decor;

    /* Mac IDs corresponding to these windows */
    xp_native_window_id _osx_id;
    xp_native_window_id _minimized_osx_id;

    /* Transience tree */
    Window _transient_for_id;
    x_window *_transient_for;
    x_list *_transients;
}

- (Window) toplevel_id;
- (void) reparent_in;
- (void) reparent_out;
- (void) send_configure;
- init_with_id:(Window)xwindow_id screen:screen initializing:(BOOL)flag;
- (void) resize_frame:(X11Rect)r;
- (void) report_frame_size:(X11Rect)r;
- (void) resize_client:(X11Rect)r;
- (void) update_shaped;
- (void) update_shape;
- (void) expose;
- (void) decorate;
- (void) property_changed:(Atom)atom;
- (void) update_net_wm_action_property;
- (x_list *) window_group;
- (xp_native_window_id) get_osx_id;
- (void) set_wm_state:(int)state;
- (void) raise;
- (BOOL) focus:(Time)timestamp;
- (BOOL) focus:(Time)timestamp raise:(BOOL)flag;
- (BOOL) focus:(Time)timestamp raise:(BOOL)raise force:(BOOL)force;
- (void) set_is_active:(BOOL)state;
- (void) show;
- (void) activate:(Time)timestamp;
- (void) x_focus_in;
- (void) x_focus_out;
- (unsigned) hit_test_frame:(X11Point)point;
- (void) do_close:(Time)timestamp;
- (void) do_collapse;
- (void) do_uncollapse;
- (void) do_uncollapse_and_tell_dock:(BOOL)tell_dock;
- (void) do_zoom;
- (void) do_shade:(Time)timestamp;
- (void) do_unshade:(Time)timestamp;
- (void) do_toggle_shaded:(Time)timestamp;
- (void) do_hide;
- (void) do_unhide;
- (void) do_net_wm_state_change:(int)mode atom:(Atom)state;
- (X11Size) validate_window_size:(X11Rect)r;
- (X11Rect) validate_client_rect:(X11Rect)r;
- (X11Rect) validate_frame_rect:(X11Rect)r;
- (X11Rect) validate_frame_rect:(X11Rect)r from_user:(BOOL)flag;
- (void) set_resizing_title:(X11Rect)r;
- (void) remove_resizing_title;
- (void) error_shutdown;
- (void) update_colormaps;
- (void) install_colormaps;
- (void) collapse_finished:(BOOL)success;
- (void) uncollapse_finished:(BOOL)success;

@end

#endif /* X_WINDOW_H */
