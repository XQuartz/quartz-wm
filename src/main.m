/* main.m
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
#include "x-list.h"
#include "frame.h"
#import "x-screen.h"
#import "x-window.h"
#import "x-selection.h"

#include <pthread.h>
#include <stdlib.h>
#include <dlfcn.h>

#include <X11/keysym.h>
#include <X11/extensions/applewm.h>
#include <X11/extensions/Xinerama.h>

Display *x_dpy;
unsigned int x_meta_mod;
int x_shape_event_base, x_shape_error_base;
int x_apple_wm_event_base, x_apple_wm_error_base;
int x_xinerama_event_base, x_xinerama_error_base;

struct atoms_struct_t atoms;

static int x_grab_count;
static Bool x_grab_synced;

x_list *screen_list;

static x_window *_active_window;
static BOOL _is_active = YES;		/* FIXME: should query server */

static int _window_count;

static x_selection *_selection_object;

static BOOL _only_proxy = NO;
static BOOL _force_proxy = NO;
BOOL _proxy_pb  = YES;

BOOL focus_follows_mouse = NO;
BOOL focus_click_through = NO;
BOOL limit_window_size   = NO;
BOOL focus_on_new_window = YES;
BOOL window_shading = NO;
BOOL rootless = YES;
BOOL auto_quit = NO;
int auto_quit_timeout = 3;   /* Seconds to wait before auto-quiting */
BOOL minimize_on_double_click = YES;

XAppleWMSendPSNProcPtr _XAppleWMSendPSN;
XAppleWMAttachTransientProcPtr _XAppleWMAttachTransient;

/* X11 code */
static void x_error_shutdown(void);

static const char *app_prefs_domain = BUNDLE_ID_PREFIX".X11";
static CFStringRef app_prefs_domain_cfstr = NULL;

void
x_grab_server (Bool sync)
{
    if (x_grab_count++ == 0)
    {
        XGrabServer (x_dpy);
    }

    if (sync && !x_grab_synced)
    {
        XSync (x_dpy, False);
        x_grab_synced = True;
    }
}

void
x_ungrab_server (void)
{
    if (--x_grab_count == 0)
    {
        XUngrabServer (x_dpy);
        XFlush (x_dpy);
        x_grab_synced = False;
    }
}

static int
x_init_error_handler (Display *dpy, XErrorEvent *e)
{
    fprintf (stderr, "quartz-wm: another window manager is running; exiting\n");
    exit(EXIT_FAILURE);
}

static int
x_error_handler (Display *dpy, XErrorEvent *e)
{
    char buf[256];
    x_window *w;

    XGetErrorText (dpy, e->error_code, buf, sizeof (buf));

    DB ("X Error: %s\n", buf);
    DB ("  code:%d.%d resource:%x\n",
        e->request_code, e->minor_code, e->resourceid);

    if (e->resourceid == 0)
        return 0;

    if (e->error_code == BadWindow || e->error_code == BadDrawable)
    {
        w = x_get_window (e->resourceid);

        if (w != nil && ! w->_removed)
            [w->_screen remove_window:w safe:NO];
    }

    return 0;
}

void
x_update_meta_modifier (void)
{
    int min_code, max_code;
    XModifierKeymap *mods;
    int syms_per_code, row, col, code_col, sym;
    KeySym *syms;
    KeyCode code;

    x_meta_mod = 0;

    XDisplayKeycodes (x_dpy, &min_code, &max_code);

    syms = XGetKeyboardMapping (x_dpy, min_code, max_code - min_code + 1,
                                &syms_per_code);
    mods = XGetModifierMapping (x_dpy);

    for (row = 3; row < 8; row++)
    {
        for (col = 0; col < mods->max_keypermod; col++)
        {
            code = mods->modifiermap[(row * mods->max_keypermod) + col];
            if(code == 0)
                continue;
            for (code_col = 0; code_col < syms_per_code; code_col++)
            {
                sym = syms[((code - min_code) * syms_per_code) + code_col];
                if (sym == XK_Meta_L || sym == XK_Meta_R)
                {
                    x_meta_mod = 1 << row;
                    goto done;
                }
            }
        }
    }

done:
    XFree((char *)syms);
    XFreeModifiermap(mods);
}

void
x_update_keymap (void)
{
    x_list *node;

    for (node = screen_list; node != NULL; node = node->next)
    {
        x_screen *s = node->data;
        [s foreach_window:@selector(ungrab_events)];
    }

    x_update_meta_modifier ();

    for (node = screen_list; node != NULL; node = node->next)
    {
        x_screen *s = node->data;
        [s foreach_window:@selector(grab_events)];
    }
}

static int
x_io_error_handler (Display *dpy)
{
    /* We lost our connection to the server. */

    TRACE ();

	x_error_shutdown ();

    return 0;
}

static void
x_init (void)
{
    int i;
    int AppleWMMajorVersion, AppleWMMinorVersion, AppleWMPatchVersion;
    x_list *node;
    unsigned applewm_mask;

    x_dpy = XOpenDisplay (NULL);
    if (x_dpy == NULL)
    {
        fprintf (stderr, "quartz-wm: can't open default display\n");
        exit(EXIT_FAILURE);
    }

    XSetErrorHandler (x_error_handler);
    XSetIOErrorHandler (x_io_error_handler);

    atoms.apple_no_order_in = XInternAtom (x_dpy, "_APPLE_NO_ORDER_IN", False);
    atoms.atom = XInternAtom (x_dpy, "ATOM", False);
    atoms.clipboard = XInternAtom (x_dpy, "CLIPBOARD", False);
    atoms.cstring = XInternAtom (x_dpy, "CSTRING", False);
    atoms.motif_wm_hints = XInternAtom (x_dpy, "_MOTIF_WM_HINTS", False);
    atoms.multiple = XInternAtom (x_dpy, "MULTIPLE", False);
    atoms.native_screen_origin = XInternAtom (x_dpy, "_NATIVE_SCREEN_ORIGIN", False);
    atoms.native_window_id = XInternAtom (x_dpy, "_NATIVE_WINDOW_ID", False);
    atoms.net_active_window = XInternAtom (x_dpy, "_NET_ACTIVE_WINDOW", False);
    atoms.net_close_window = XInternAtom (x_dpy, "_NET_CLOSE_WINDOW", False);
    atoms.net_wm_action_close = XInternAtom (x_dpy, "_NET_WM_ACTION_CLOSE", False);
    atoms.net_wm_action_fullscreen = XInternAtom (x_dpy, "_NET_WM_ACTION_FULLSCREEN", False);
    atoms.net_wm_action_maximize_horz = XInternAtom (x_dpy, "_NET_WM_ACTION_MAXIMIZE_HORZ", False);
    atoms.net_wm_action_maximize_vert = XInternAtom (x_dpy, "_NET_WM_ACTION_MAXIMIZE_VERT", False);
    atoms.net_wm_action_minimize = XInternAtom (x_dpy, "_NET_WM_ACTION_MINIMIZE", False);
    atoms.net_wm_action_move = XInternAtom (x_dpy, "_NET_WM_ACTION_MOVE", False);
    atoms.net_wm_action_resize = XInternAtom (x_dpy, "_NET_WM_ACTION_RESIZE", False);
    atoms.net_wm_action_shade = XInternAtom (x_dpy, "_NET_WM_ACTION_SHADE", False);
    atoms.net_wm_allowed_actions = XInternAtom (x_dpy, "_NET_WM_ALLOWED_ACTIONS", False);
    atoms.net_wm_name = XInternAtom (x_dpy, "_NET_WM_NAME", False);
    atoms.net_wm_state = XInternAtom (x_dpy, "_NET_WM_STATE", False);
    atoms.net_wm_state_fullscreen = XInternAtom (x_dpy, "_NET_WM_STATE_FULLSCREEN", False);
    atoms.net_wm_state_hidden = XInternAtom (x_dpy, "_NET_WM_STATE_HIDDEN", False);
    atoms.net_wm_state_maximized_horz = XInternAtom (x_dpy, "_NET_WM_STATE_MAXIMIZED_HORZ", False);
    atoms.net_wm_state_maximized_vert = XInternAtom (x_dpy, "_NET_WM_STATE_MAXIMIZED_VERT", False);
    atoms.net_wm_state_modal = XInternAtom (x_dpy, "_NET_WM_STATE_MODAL", False);
    atoms.net_wm_state_shaded = XInternAtom (x_dpy, "_NET_WM_STATE_SHADED", False);
    atoms.net_wm_state_skip_pager = XInternAtom (x_dpy, "_NET_WM_STATE_SKIP_PAGER", False);
    atoms.net_wm_state_skip_taskbar = XInternAtom (x_dpy, "_NET_WM_STATE_SKIP_TASKBAR", False);
    atoms.net_wm_state_sticky = XInternAtom (x_dpy, "_NET_WM_STATE_STICKY", False);
    atoms.net_wm_window_type = XInternAtom (x_dpy, "_NET_WM_WINDOW_TYPE", False);
    atoms.net_wm_window_type_combo = XInternAtom (x_dpy, "_NET_WM_WINDOW_TYPE_COMBO", False);
    atoms.net_wm_window_type_desktop = XInternAtom (x_dpy, "_NET_WM_WINDOW_TYPE_DESKTOP", False);
    atoms.net_wm_window_type_dialog = XInternAtom (x_dpy, "_NET_WM_WINDOW_TYPE_DIALOG", False);
    atoms.net_wm_window_type_dock = XInternAtom (x_dpy, "_NET_WM_WINDOW_TYPE_DOCK", False);
    atoms.net_wm_window_type_dnd = XInternAtom (x_dpy, "_NET_WM_WINDOW_TYPE_DND", False);
    atoms.net_wm_window_type_dropdown_menu = XInternAtom (x_dpy, "_NET_WM_WINDOW_TYPE_DROPDOWN_MENU", False);
    atoms.net_wm_window_type_menu = XInternAtom (x_dpy, "_NET_WM_WINDOW_TYPE_MENU", False);
    atoms.net_wm_window_type_normal = XInternAtom (x_dpy, "_NET_WM_WINDOW_TYPE_NORMAL", False);
    atoms.net_wm_window_type_notification = XInternAtom (x_dpy, "_NET_WM_WINDOW_TYPE_NOTIFICATION", False);
    atoms.net_wm_window_type_popup_menu = XInternAtom (x_dpy, "_NET_WM_WINDOW_TYPE_POPUP_MENU", False);
    atoms.net_wm_window_type_splash = XInternAtom (x_dpy, "_NET_WM_WINDOW_TYPE_SPLASH", False);
    atoms.net_wm_window_type_tooltip = XInternAtom (x_dpy, "_NET_WM_WINDOW_TYPE_TOOLTIP", False);
    atoms.net_wm_window_type_toolbar = XInternAtom (x_dpy, "_NET_WM_WINDOW_TYPE_TOOLBAR", False);
    atoms.net_wm_window_type_utility = XInternAtom (x_dpy, "_NET_WM_WINDOW_TYPE_UTILITY", False);
    atoms.primary = XInternAtom (x_dpy, "PRIMARY", False);;
    atoms.targets = XInternAtom (x_dpy, "STRING", False);
    atoms.targets = XInternAtom (x_dpy, "TARGETS", False);
    atoms.text = XInternAtom (x_dpy, "TEXT", False);
    atoms.utf8_string = XInternAtom (x_dpy, "UTF8_STRING", False);
    atoms.wm_change_state = XInternAtom (x_dpy, "WM_CHANGE_STATE", False);
    atoms.wm_colormap_windows = XInternAtom (x_dpy, "WM_COLORMAP_WINDOWS", False);
    atoms.wm_delete_window = XInternAtom (x_dpy, "WM_DELETE_WINDOW", False);
    atoms.wm_hints = XInternAtom (x_dpy, "WM_HINTS", False);
    atoms.wm_name = XInternAtom (x_dpy, "WM_NAME", False);
    atoms.wm_normal_hints = XInternAtom (x_dpy, "WM_NORMAL_HINTS", False);
    atoms.wm_protocols = XInternAtom (x_dpy, "WM_PROTOCOLS", False);
    atoms.wm_state = XInternAtom (x_dpy, "WM_STATE", False);
    atoms.wm_take_focus = XInternAtom (x_dpy, "WM_TAKE_FOCUS", False);
    atoms.wm_transient_for = XInternAtom (x_dpy, "WM_TRANSIENT_FOR", False);

    if (!XShapeQueryExtension (x_dpy, &x_shape_event_base,
                               &x_shape_error_base))
    {
        fprintf (stderr, "quartz-wm: can't open SHAPE server extension\n");
        exit(EXIT_FAILURE);
    }

    if (!XAppleWMQueryExtension (x_dpy, &x_apple_wm_event_base,
                                 &x_apple_wm_error_base))
    {
        fprintf (stderr, "quartz-wm: can't open AppleWM server extension\n");
        exit(EXIT_FAILURE);
    }

    XineramaQueryExtension (x_dpy, &x_xinerama_event_base,
                            &x_xinerama_error_base);

    x_update_meta_modifier ();

    XAppleWMQueryVersion(x_dpy, &AppleWMMajorVersion, &AppleWMMinorVersion, &AppleWMPatchVersion);

    if(!_force_proxy && (AppleWMMajorVersion > 1 || (AppleWMMajorVersion == 1 && AppleWMMinorVersion >= 1))) {
        /* Server handles PB proxy */
        _proxy_pb = NO;
        if(_only_proxy) {
            fprintf(stderr, "You asked quartz-wm to only proxy, but the server is already doing it.\nquartz-wm is not doing anything but waiting to be told to quit.\n");
        }
    }

    /* We do this with dlsym() to help support Codeweavers' wine which may
     * override libAppleWM with an older version of the library
     */
    _XAppleWMSendPSN = dlsym(RTLD_DEFAULT, "XAppleWMSendPSN");
    _XAppleWMAttachTransient = dlsym(RTLD_DEFAULT, "XAppleWMAttachTransient");

    /* Let the server know our Canonical PSN */
    if(_XAppleWMSendPSN)
        _XAppleWMSendPSN(x_dpy);

    applewm_mask = AppleWMActivationNotifyMask;
    if(_proxy_pb)
        applewm_mask |= AppleWMPasteboardNotifyMask;
    if(!_only_proxy)
        applewm_mask |= AppleWMControllerNotifyMask;

    XAppleWMSelectInput (x_dpy, applewm_mask);
    if (!_only_proxy) {
        XSync (x_dpy, False);
        XSetErrorHandler (x_init_error_handler);

        for (i = 0; i < ScreenCount (x_dpy); i++) {
            x_screen *s = [[x_screen alloc] init_with_screen_id:i];
            if(s == nil) {
                fprintf(stderr, "quartz-wm: Memory allocation error\n");
                exit(EXIT_FAILURE);
            }

            screen_list = x_list_prepend (screen_list, s);
        }

        XSync (x_dpy, False);
        XSetErrorHandler (x_error_handler);

        /* Let X11 quit without dialog box confirmation until we have a window */
        XAppleWMSetCanQuit (x_dpy, True);

        for (node = screen_list; node != NULL; node = node->next) {
            x_screen *s = node->data;
            [s adopt_windows];
        }
    }

    _selection_object = [[x_selection alloc] init];

    x_input_register ();
    x_input_run ();
}

static void x_shutdown (void) {
    x_list *node;

    [_selection_object release];
    _selection_object = nil;

    for (node = screen_list; node != NULL; node = node->next) {
        x_screen *s = node->data;
        [s unadopt_windows];
    }

    /* Leave focus in a usable state. */
    XSetInputFocus (x_dpy, PointerRoot, RevertToPointerRoot, CurrentTime);

    /* Reenable can-quit dialog */
    XAppleWMSetCanQuit (x_dpy, False);

    XCloseDisplay (x_dpy);
    x_dpy = NULL;
    exit(EXIT_SUCCESS);
}

static void x_error_shutdown (void) {
    x_list *node;

    for (node = screen_list; node != NULL; node = node->next) {
        x_screen *s = node->data;
        [s error_shutdown];
    }
    exit(EXIT_FAILURE);
}

id
x_selection_object (void)
{
    return _selection_object;
}

Time
x_current_timestamp (void)
{
    /* FIXME: may want to fetch a timestamp from the server.. */

    return CurrentTime;
}


/* Window menu management */

static x_list *window_menu;

static void
x_update_window_menu_focused (void)
{
    int n, m;

    n = x_list_length (window_menu);
    if (_is_active)
        m = x_list_length (x_list_find (window_menu, _active_window));
    else
        m = 0;

    if (m > 0)
        XAppleWMSetWindowMenuCheck (x_dpy, n - m);
    else
        XAppleWMSetWindowMenuCheck (x_dpy, -1);
}

static void
x_update_window_menu (void)
{
    int nitems, i;
    const char **items = NULL;
    char *shortcuts = NULL;
    x_list *node;

    nitems = x_list_length (window_menu);
    if (nitems > 0)
    {
        items = alloca (sizeof (char *) * nitems);
        shortcuts = alloca (sizeof (char) * nitems);

        for (i = 0, node = window_menu; node != NULL; node = node->next)
        {
            x_window *w = node->data;

            if (w->_title != nil)
            {
                items[i] = [w->_title UTF8String];
                shortcuts[i] = w->_shortcut_index;
                i++;
            }
            else
                nitems--;
        }
    }

    XAppleWMSetWindowMenuWithShortcuts (x_dpy, nitems, items, shortcuts);

    x_update_window_menu_focused ();
}

void
x_update_window_in_menu (id w)
{
    if (x_list_find (window_menu, w))
    {
        x_update_window_menu ();
    }
}

void
x_add_window_to_menu (id w)
{
    if (!x_list_find (window_menu, w))
    {
        window_menu = x_list_append (window_menu, [w retain]);
    }

    x_update_window_menu ();
}

void
x_remove_window_from_menu (id w)
{
    if (x_list_find (window_menu, w))
    {
        window_menu = x_list_remove (window_menu, w);
        [w release];
        x_update_window_menu ();
    }
}

void
x_activate_window_in_menu (int n, Time timestamp)
{
    x_list *node;
    x_window *w;

    node = x_list_nth (window_menu, n);
    if (node != nil)
    {
        w = node->data;
        [w activate:timestamp];
    }
}


/* Finding things */

id
x_get_screen (Screen *xs)
{
    x_list *node;

    for (node = screen_list; node != NULL; node = node->next)
    {
        x_screen *s = node->data;

        if (s->_screen == xs)
            return s;
    }

    return nil;
}

id
x_get_screen_with_root (Window id)
{
    x_list *node;

    for (node = screen_list; node != NULL; node = node->next)
    {
        x_screen *s = node->data;

        if (s->_root == id)
            return s;
    }

    return nil;
}

id
x_get_window (Window id)
{
    x_list *node;

    for (node = screen_list; node != NULL; node = node->next)
    {
        x_screen *s = node->data;
        x_window *w;

        w = [s get_window:id];
        if (w != nil)
            return w;
    }

    return nil;
}

id
x_get_window_by_osx_id (xp_native_window_id osxwindow_id)
{
    x_list *node;

    for (node = screen_list; node != NULL; node = node->next)
    {
        x_screen *s = node->data;
        x_window *w;

        w = [s get_window_by_osx_id:osxwindow_id];
        if (w != nil)
            return w;
    }

    return nil;
}

id
x_get_active_window (void)
{
    if (_active_window != nil && _active_window->_deleted)
    {
        [_active_window release];
        _active_window = nil;
    }

    return _active_window;
}

void
x_set_active_window (id w)
{
    if (_active_window == w)
        return;

    /* When X11 becomes inactive, we unfocus the active window.. but we
     want to remember which window was focused for later reactivation */

    if (!_is_active && w == nil)
        return;

    if (_active_window != nil)
    {
        if (_is_active)
            [_active_window set_is_active:NO];

        [_active_window release];
        _active_window = nil;
    }

    if (w != nil)
    {
        _active_window = [w retain];

        if (_is_active)
            [_active_window set_is_active:YES];

        x_update_window_menu_focused ();
    }
}

BOOL
x_get_is_active (void)
{
    return _is_active;
}

void
x_set_is_active (BOOL state)
{
    x_window *active;

    if (_is_active == state)
        return;

    active = x_get_active_window ();
    if (active != nil)
    {
        if (!state)
        {
            [active set_is_active:state];
            XSetInputFocus (x_dpy, None, RevertToNone, CurrentTime);
        }
        else
        {
            /* Don't redraw the window immediately, the activation
             may have been caused by clicking on a non-focused
             window, in which case we don't want the previously
             focused window to be drawn active then inactive. */

            [NSTimer scheduledTimerWithTimeInterval:0.1
                                             target:active selector:@selector (update_state:)
                                           userInfo:nil repeats:NO];
        }
    }

    _is_active = state;

    x_update_window_menu_focused ();
}

void
x_bring_one_to_front (Time timestamp)
{
    x_window *w = x_get_active_window ();

    if (w != nil)
    {
        [w activate:timestamp];
    }
}

void
x_bring_all_to_front (Time timestamp)
{
    x_list *node;

    for (node = screen_list; node != NULL; node = node->next)
    {
        x_screen *s = node->data;

        [s raise_all];
    }
}

void
x_hide_all (Time timestamp)
{
    x_list *node;

    for (node = screen_list; node != NULL; node = node->next)
    {
        x_screen *s = node->data;

        [s hide_all];
    }
}

void
x_show_all (Time timestamp, BOOL minimized)
{
    x_list *node;

    for (node = screen_list; node != NULL; node = node->next)
    {
        x_screen *s = node->data;

        [s show_all:minimized];
        [s focus_topmost:timestamp];
    }
}

/* wm_auto_quit support */
CFRunLoopTimerRef auto_quit_timer = NULL;

/* Cancel the auto-quit timer */
static void cancel_auto_quit(void) {
    if(auto_quit_timer) {
        if(CFRunLoopTimerIsValid(auto_quit_timer)) {
            CFRunLoopTimerInvalidate(auto_quit_timer);
        }
        CFRelease(auto_quit_timer);
        auto_quit_timer = NULL;
    }
}

/* Shutdown now */
static void auto_quit_callback(CFRunLoopTimerRef timer __attribute__((unused)), void *info __attribute__((unused))) {
    if(_window_count == 0) {
        x_shutdown();
    } else {
        cancel_auto_quit();
    }
}

/* Start the auto-quit timer */
static void start_auto_quit(void) {
    CFAbsoluteTime fireDate;

    /* If we have a negative or zero timeout, just quit now */
    if(auto_quit_timeout <= 0) {
        x_shutdown();
    }

    if(auto_quit_timer) {
        cancel_auto_quit();
    }

    /* Now */
    fireDate = CFAbsoluteTimeGetCurrent();
    fireDate += (double)auto_quit_timeout;

    auto_quit_timer = CFRunLoopTimerCreate(kCFAllocatorDefault, fireDate, 0, 0, 0, auto_quit_callback, NULL);

    if(auto_quit_timer) {
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), auto_quit_timer, kCFRunLoopCommonModes);
    } else {
        fprintf (stderr, "quartz-wm: couldn't create a shutdown timer, quitting now.\n");
        x_shutdown();
    }
}

void
x_change_window_count (int delta)
{
    BOOL old_state, new_state;


    old_state = _window_count == 0;

    _window_count += delta;

    new_state = _window_count == 0;

    if (new_state != old_state) {
        XAppleWMSetCanQuit (x_dpy, new_state);

        if (auto_quit) {
            if(new_state) {
                start_auto_quit();
            } else {
                cancel_auto_quit();
            }
        }
    }
}

#ifdef CHECK_WINDOWS
void
x_check_windows (void)
{
    x_list *node;

    for (node = screen_list; node != NULL; node = node->next)
    {
        x_screen *s = node->data;

        [s check_window_lists];
    }
}
#endif


/* Window shortcut management */

static unsigned int _shortcut_map;

int
x_allocate_window_shortcut (void)
{
    int i;

    for (i = 1; i < 10; i++)
    {
        if (!(_shortcut_map & (1 << i)))
        {
            _shortcut_map |= (1 << i);
            return i;
        }
    }

    return 0;
}

void
x_release_window_shortcut (int x)
{
    _shortcut_map = _shortcut_map & ~(1 << x);
}

/* Preferences */

BOOL prefs_reload = NO;
static BOOL do_shutdown = NO;

static BOOL prefs_get_bool (CFStringRef key, BOOL def) {
    int ret;
    Boolean ok;

    ret = CFPreferencesGetAppBooleanValue (key, app_prefs_domain_cfstr, &ok);

    return ok ? (BOOL) ret : def;
}

static int prefs_get_int (CFStringRef key, BOOL def) {
    int ret;
    Boolean ok;

    ret = CFPreferencesGetAppIntegerValue (key, app_prefs_domain_cfstr, &ok);

    return ok ? (BOOL) ret : def;
}

static inline void prefs_read(void) {
    CFPreferencesAppSynchronize(app_prefs_domain_cfstr);
    focus_follows_mouse = prefs_get_bool (CFSTR (PREFS_FFM), focus_follows_mouse);
    focus_on_new_window = prefs_get_bool (CFSTR (PREFS_FOCUS_ON_NEW_WINDOW), focus_on_new_window);
    focus_click_through = prefs_get_bool (CFSTR (PREFS_CLICK_THROUGH), focus_click_through);
    limit_window_size   = prefs_get_bool (CFSTR (PREFS_LIMIT_SIZE), limit_window_size);
    window_shading      = prefs_get_bool (CFSTR (PREFS_WINDOW_SHADING), window_shading);
    rootless            = prefs_get_bool (CFSTR (PREFS_ROOTLESS), rootless);
    auto_quit           = prefs_get_bool (CFSTR (PREFS_AUTO_QUIT), auto_quit);
    auto_quit_timeout   = prefs_get_int (CFSTR (PREFS_AUTO_QUIT_TIMEOUT), auto_quit_timeout);
    minimize_on_double_click = prefs_get_bool (CFSTR(PREFS_MINIMIZE_ON_DOUBLE_CLICK), minimize_on_double_click);
}

static void signal_handler_cb(CFRunLoopObserverRef observer,
                              CFRunLoopActivity activity, void *info) {

    if(do_shutdown)
        x_shutdown();

    if(prefs_reload) {
        x_list *s_node, *w_node;
        x_window *w;
        x_screen *s;

        prefs_reload = NO;
        prefs_read();

        /* We need to update the click_through/shading policy on our windows */
        for (s_node = screen_list; s_node != NULL; s_node = s_node->next) {
            s = s_node->data;
            for(w_node = s->_window_list; w_node != NULL; w_node = w_node->next) {
                w = w_node->data;
                if(w->_shadable) {
                    if(!window_shading)
                        [w do_unshade:CurrentTime];
                    [w update_net_wm_action_property];
                }
            }
        }
    }
}

static void signal_handler_cb_init(void) {
    CFRunLoopObserverContext context = {0};
    CFRunLoopObserverRef ref;

    ref = CFRunLoopObserverCreate(kCFAllocatorDefault, kCFRunLoopBeforeWaiting,
                                  true, 0, signal_handler_cb, &context);

    CFRunLoopAddObserver(CFRunLoopGetCurrent(), ref, kCFRunLoopDefaultMode);
}

static void appearance_pref_changed_cb(CFNotificationCenterRef center, void *observer,
                CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
    prefs_read();
}


/* Startup */

static void signal_handler (int sig) {
    switch(sig) {
        case SIGHUP:
            prefs_reload = YES;
            break;
        default:
            do_shutdown = YES;
            break;
    }
}

int main (int argc, const char *argv[]) {
    NSAutoreleasePool *pool;
    int i;
    const char *s;

    pool = [[NSAutoreleasePool alloc] init];

    if((s = getenv("X11_PREFS_DOMAIN")))
        app_prefs_domain = s;

    for (i = 1; i < argc; i++)
    {
        if (strcmp (argv[i], "--version") == 0) {
            printf("%s\n", VERSION);
            return 0;
        } else if(strcmp (argv[i], "--prefs-domain") == 0 && i+1 < argc) {
            app_prefs_domain = argv[++i];
        } else if(strcmp (argv[i], "--display") == 0 && i+1 < argc) {
            setenv("DISPLAY", argv[++i], 1);
        } else if(strcmp (argv[i], "-display") == 0 && i+1 < argc) {
            setenv("DISPLAY", argv[++i], 1);
        } else if (strcmp (argv[i], "--only-proxy") == 0) {
            _only_proxy = YES;
        } else if (strcmp (argv[i], "--force-proxy") == 0) {
            _force_proxy = YES;
        } else if (strcmp (argv[i], "--no-pasteboard") == 0) {
            _proxy_pb = NO;
        } else if (strcmp (argv[i], "--synchronous") == 0) {
            _Xdebug = 1;
        } else if (strcmp (argv[i], "--help") == 0) {
            printf("usage: quartz-wm OPTIONS\n"
                   "Aqua window manager for X11.\n\n"
                   "--version                 Print the version string\n"
                   "--only-proxy              Don't manage windows, just proxy pasteboard\n"
                   "--no-pasteboard           Don't proxy pasteboard, just manage windows\n"
                   "--prefs-domain <domain>   Change the domain used for reading preferences\n"
                   "                          (default: "BUNDLE_ID_PREFIX".X11)\n");
            return 0;
        } else {
            fprintf(stderr, "usage: quartz-wm OPTIONS...\n"
                    "Try 'quartz-wm --help' for more information.\n");
            return 1;
        }
    }

    app_prefs_domain_cfstr = CFStringCreateWithCString(NULL, app_prefs_domain, kCFStringEncodingUTF8);

    prefs_read();

    if(_only_proxy && !_proxy_pb) {
        fprintf(stderr, "quartz-wm: You can't do both --only-proxy and --no-pasteboard at the same time.");
        return 1;
    }

    signal_handler_cb_init();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDistributedCenter(),
        NULL, appearance_pref_changed_cb, CFSTR("AppleNoRedisplayAppearancePreferenceChanged"),
        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    qwm_dock_event_set_handler(dock_event_handler);
    qwm_dock_init(_only_proxy);
    x_init ();

    signal (SIGINT, signal_handler);
    signal (SIGTERM, signal_handler);
    signal (SIGHUP, signal_handler);
    signal (SIGPIPE, SIG_IGN);

    while (1) {
        NS_DURING
        CFRunLoopRun ();
        NS_HANDLER
        NSString *s = [NSString stringWithFormat:@"%@ - %@",
                       [localException name], [localException reason]];
        fprintf(stderr, "quartz-wm: caught exception: %s\n", [s UTF8String]);
        NS_ENDHANDLER
    }

    return 0;
}

// for atom in $(grep XInternAtom main.m | grep \" | cut -f2 -d\" | sort -u); do printf "    if(atom == atoms.$(echo ${atom} | sed 's/^_//' | tr [:upper:] [:lower:]))\n        return \"${atom}\";\n"; done
const char *str_for_atom(Atom atom) {
    if(atom == atoms.atom)
        return "ATOM";
    if(atom == atoms.clipboard)
        return "CLIPBOARD";
    if(atom == atoms.cstring)
        return "CSTRING";
    if(atom == atoms.multiple)
        return "MULTIPLE";
    if(atom == atoms.primary)
        return "PRIMARY";
    if(atom == atoms.string)
        return "STRING";
    if(atom == atoms.targets)
        return "TARGETS";
    if(atom == atoms.text)
        return "TEXT";
    if(atom == atoms.utf8_string)
        return "UTF8_STRING";
    if(atom == atoms.wm_change_state)
        return "WM_CHANGE_STATE";
    if(atom == atoms.wm_colormap_windows)
        return "WM_COLORMAP_WINDOWS";
    if(atom == atoms.wm_delete_window)
        return "WM_DELETE_WINDOW";
    if(atom == atoms.wm_hints)
        return "WM_HINTS";
    if(atom == atoms.wm_name)
        return "WM_NAME";
    if(atom == atoms.wm_normal_hints)
        return "WM_NORMAL_HINTS";
    if(atom == atoms.wm_protocols)
        return "WM_PROTOCOLS";
    if(atom == atoms.wm_state)
        return "WM_STATE";
    if(atom == atoms.wm_take_focus)
        return "WM_TAKE_FOCUS";
    if(atom == atoms.wm_transient_for)
        return "WM_TRANSIENT_FOR";
    if(atom == atoms.apple_no_order_in)
        return "_APPLE_NO_ORDER_IN";
    if(atom == atoms.motif_wm_hints)
        return "_MOTIF_WM_HINTS";
    if(atom == atoms.native_screen_origin)
        return "_NATIVE_SCREEN_ORIGIN";
    if(atom == atoms.native_window_id)
        return "_NATIVE_WINDOW_ID";
    if(atom == atoms.net_active_window)
        return "_NET_ACTIVE_WINDOW";
    if(atom == atoms.net_close_window)
        return "_NET_CLOSE_WINDOW";
    if(atom == atoms.net_wm_action_close)
        return "_NET_WM_ACTION_CLOSE";
    if(atom == atoms.net_wm_action_fullscreen)
        return "_NET_WM_ACTION_FULLSCREEN";
    if(atom == atoms.net_wm_action_maximize_horz)
        return "_NET_WM_ACTION_MAXIMIZE_HORZ";
    if(atom == atoms.net_wm_action_maximize_vert)
        return "_NET_WM_ACTION_MAXIMIZE_VERT";
    if(atom == atoms.net_wm_action_minimize)
        return "_NET_WM_ACTION_MINIMIZE";
    if(atom == atoms.net_wm_action_move)
        return "_NET_WM_ACTION_MOVE";
    if(atom == atoms.net_wm_action_resize)
        return "_NET_WM_ACTION_RESIZE";
    if(atom == atoms.net_wm_action_shade)
        return "_NET_WM_ACTION_SHADE";
    if(atom == atoms.net_wm_allowed_actions)
        return "_NET_WM_ALLOWED_ACTIONS";
    if(atom == atoms.net_wm_name)
        return "_NET_WM_NAME";
    if(atom == atoms.net_wm_state)
        return "_NET_WM_STATE";
    if(atom == atoms.net_wm_state_fullscreen)
        return "_NET_WM_STATE_FULLSCREEN";
    if(atom == atoms.net_wm_state_hidden)
        return "_NET_WM_STATE_HIDDEN";
    if(atom == atoms.net_wm_state_maximized_horz)
        return "_NET_WM_STATE_MAXIMIZED_HORZ";
    if(atom == atoms.net_wm_state_maximized_vert)
        return "_NET_WM_STATE_MAXIMIZED_VERT";
    if(atom == atoms.net_wm_state_modal)
        return "_NET_WM_STATE_MODAL";
    if(atom == atoms.net_wm_state_shaded)
        return "_NET_WM_STATE_SHADED";
    if(atom == atoms.net_wm_state_skip_pager)
        return "_NET_WM_STATE_SKIP_PAGER";
    if(atom == atoms.net_wm_state_skip_taskbar)
        return "_NET_WM_STATE_SKIP_TASKBAR";
    if(atom == atoms.net_wm_state_sticky)
        return "_NET_WM_STATE_STICKY";
    if(atom == atoms.net_wm_window_type)
        return "_NET_WM_WINDOW_TYPE";
    if(atom == atoms.net_wm_window_type_combo)
        return "_NET_WM_WINDOW_TYPE_COMBO";
    if(atom == atoms.net_wm_window_type_desktop)
        return "_NET_WM_WINDOW_TYPE_DESKTOP";
    if(atom == atoms.net_wm_window_type_dialog)
        return "_NET_WM_WINDOW_TYPE_DIALOG";
    if(atom == atoms.net_wm_window_type_dnd)
        return "_NET_WM_WINDOW_TYPE_DND";
    if(atom == atoms.net_wm_window_type_dock)
        return "_NET_WM_WINDOW_TYPE_DOCK";
    if(atom == atoms.net_wm_window_type_dropdown_menu)
        return "_NET_WM_WINDOW_TYPE_DROPDOWN_MENU";
    if(atom == atoms.net_wm_window_type_menu)
        return "_NET_WM_WINDOW_TYPE_MENU";
    if(atom == atoms.net_wm_window_type_normal)
        return "_NET_WM_WINDOW_TYPE_NORMAL";
    if(atom == atoms.net_wm_window_type_notification)
        return "_NET_WM_WINDOW_TYPE_NOTIFICATION";
    if(atom == atoms.net_wm_window_type_popup_menu)
        return "_NET_WM_WINDOW_TYPE_POPUP_MENU";
    if(atom == atoms.net_wm_window_type_splash)
        return "_NET_WM_WINDOW_TYPE_SPLASH";
    if(atom == atoms.net_wm_window_type_toolbar)
        return "_NET_WM_WINDOW_TYPE_TOOLBAR";
    if(atom == atoms.net_wm_window_type_tooltip)
        return "_NET_WM_WINDOW_TYPE_TOOLTIP";
    if(atom == atoms.net_wm_window_type_utility)
        return "_NET_WM_WINDOW_TYPE_UTILITY";
    return "(unknown atom)";
}

void
debug_printf (const char *fmt, ...)
{
    static int spew = -1;

    if (spew == -1)
    {
        char *x = getenv ("DEBUG");
        spew = (x != NULL && atoi (x) != 0);
    }

    if (spew)
    {
        va_list args;

        va_start(args, fmt);

        vfprintf (stderr, fmt, args);

        va_end(args);
    }
}
