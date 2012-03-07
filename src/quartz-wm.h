/* quartz-wm.h
 *
 * Copyright (c) 2002-2010 Apple Inc. All Rights Reserved.
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

#ifndef QUARTZ_WM_H
#define QUARTZ_WM_H 1

#import  <Foundation/Foundation.h>
#include <ApplicationServices/ApplicationServices.h>

#define  Cursor X_Cursor
#undef _SHAPE_H_
#include <X11/Xlib.h>
#include <X11/extensions/shape.h>
#undef   Cursor

#include "x-list.h"
#include "x11-geometry.h"
#include "dock-support.h"

#define X_ROOT_WINDOW_EVENTS				\
    (SubstructureRedirectMask | SubstructureNotifyMask	\
     | StructureNotifyMask)

#define X_CLIENT_WINDOW_EVENTS				\
    (PropertyChangeMask | StructureNotifyMask		\
     | ColormapChangeMask)

#define X_CLIENT_BUTTON_GRAB_EVENTS			\
    (ButtonPressMask | ButtonReleaseMask)

#define X_FRAME_WINDOW_EVENTS				\
    (ButtonPressMask | ButtonReleaseMask		\
     | ButtonMotionMask | PointerMotionHintMask		\
     | SubstructureRedirectMask | FocusChangeMask	\
     | EnterWindowMask | LeaveWindowMask		\
     | ExposureMask)

#define X_TRACKING_WINDOW_EVENTS			\
    (EnterWindowMask | LeaveWindowMask)

#define X_GROWBOX_WINDOW_EVENTS				\
    (ButtonPressMask | ButtonReleaseMask		\
     | ButtonMotionMask | PointerMotionHintMask)

#define DRAG_THRESHOLD 3

#define PREFS_FFM "wm_ffm"
#define PREFS_CLICK_THROUGH "wm_click_through"
#define PREFS_LIMIT_SIZE "wm_limit_size"
#define PREFS_FOCUS_ON_NEW_WINDOW "wm_focus_on_new_window"
#define PREFS_WINDOW_SHADING "wm_window_shading"
#define PREFS_ROOTLESS "rootless"
#define PREFS_AUTO_QUIT "wm_auto_quit"
#define PREFS_AUTO_QUIT_TIMEOUT "wm_auto_quit_timeout"

/* from main.m */
extern x_list *screen_list;
extern BOOL focus_follows_mouse, focus_click_through, limit_window_size, focus_on_new_window, window_shading, rootless, auto_quit;
extern int auto_quit_timeout;
extern void x_grab_server (Bool sync);
extern void x_ungrab_server (void);
extern void x_update_meta_modifier (void);
extern void x_update_keymap (void);
extern id x_get_screen (Screen *xs);
extern id x_get_screen_with_root (Window xwindow_id);
extern id x_get_window (Window xwindow_id);
extern id x_get_window_by_osx_id (xp_native_window_id osxwindow_id);
extern void x_set_active_window (id w);
extern id x_get_active_window (void);
extern void x_set_is_active (BOOL state);
extern BOOL x_get_is_active (void);
extern void x_bring_one_to_front (Time timestamp);
extern void x_bring_all_to_front (Time timestamp);
extern void x_hide_all (Time timestamp);
extern void x_show_all (Time timestamp, BOOL minimized);
extern void x_update_window_in_menu (id w);
extern void x_add_window_to_menu (id w);
extern void x_remove_window_from_menu (id w);
extern void x_activate_window_in_menu (int n, Time timestamp);
extern void x_change_window_count (int delta);
extern int x_allocate_window_shortcut (void);
extern void x_release_window_shortcut (int x);
extern id x_selection_object (void);
extern Time x_current_timestamp (void);

extern Display *x_dpy;
extern unsigned int x_meta_mod;
extern int x_shape_event_base, x_shape_error_base;
extern int x_apple_wm_event_base, x_apple_wm_error_base;
extern int x_xinerama_event_base, x_xinerama_error_base;
extern BOOL prefs_reload;

/* from x-input.m */
extern void x_input_register (void);
extern void x_input_run (void);

/* Try to work with older libAppleWM for Codeweavers support */
typedef Bool (* XAppleWMSendPSNProcPtr)(Display *dpy);
extern XAppleWMSendPSNProcPtr _XAppleWMSendPSN;

typedef Bool (* XAppleWMAttachTransientProcPtr)(Display *dpy, Window child, Window parent);
extern XAppleWMAttachTransientProcPtr _XAppleWMAttachTransient;

struct atoms_struct_t {
    Atom apple_no_order_in;
    Atom atom;
    Atom clipboard;
    Atom cstring;
    Atom motif_wm_hints;
    Atom multiple;
    Atom native_screen_origin;
    Atom native_window_id;
    Atom net_active_window;
    Atom net_close_window;
    Atom net_wm_action_close;
    Atom net_wm_action_fullscreen;
    Atom net_wm_action_maximize_horz;
    Atom net_wm_action_maximize_vert;
    Atom net_wm_action_minimize;
    Atom net_wm_action_move;
    Atom net_wm_action_resize;
    Atom net_wm_action_shade;
    Atom net_wm_allowed_actions;
    Atom net_wm_name;
    Atom net_wm_state;
    Atom net_wm_state_fullscreen;
    Atom net_wm_state_hidden;
    Atom net_wm_state_maximized_horiz;
    Atom net_wm_state_maximized_vert;
    Atom net_wm_state_modal;
    Atom net_wm_state_shaded;
    Atom net_wm_state_skip_taskbar;
    Atom net_wm_window_type;
    Atom net_wm_window_type_desktop;
    Atom net_wm_window_type_dialog;
    Atom net_wm_window_type_dock;
    Atom net_wm_window_type_menu;
    Atom net_wm_window_type_normal;
    Atom net_wm_window_type_utility;
    Atom net_wm_window_type_splash;
    Atom net_wm_window_type_toolbar;
    Atom primary;
    Atom string;
    Atom targets;
    Atom text;
    Atom utf8_string;
    Atom wm_change_state;
    Atom wm_colormap_windows;
    Atom wm_delete_window;
    Atom wm_hints;
    Atom wm_name;
    Atom wm_normal_hints;
    Atom wm_protocols;
    Atom wm_state;
    Atom wm_take_focus;
    Atom wm_transient_for;
};

extern struct atoms_struct_t atoms;

/* Dock Events */
#include "dock-support.h"
extern void dock_event_handler(xp_dock_event *event);

#ifdef DEBUG
#define DB(msg, args...) debug_printf("%s:%s:%d " msg, __FILE__, __FUNCTION__, __LINE__, ##args)
#else
#define DB(msg, args...) do {} while (0)
#endif

#define TRACE() DB("TRACE\n")
extern void debug_printf (const char *fmt, ...);

#endif /* QUARTZ_WM_H */
