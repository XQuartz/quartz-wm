/* dock-support.h
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

#ifndef __DOCK_SUPPORT_H__
#define __DOCK_SUPPORT_H__

#include <Xplugin.h>
#include <ApplicationServices/ApplicationServices.h>
#include <objc/objc.h>

#ifdef XPLUGIN_DOCK_SUPPORT

#if !defined(XPLUGIN_VERSION) || XPLUGIN_VERSION < 5
#error "The installed version of libXplugin is not recent enough to support quartz-wm.  Please reconfigure and use the provided libquartz-wm-ds instead."
#endif

#define qwm_dock_get_orientation xp_dock_get_orientation
#define qwm_dock_get_rect xp_dock_get_rect
#define qwm_dock_is_window_visible xp_dock_is_window_visible
#define qwm_dock_minimize_item_with_title_async xp_dock_minimize_item_with_title_async
#define qwm_dock_restore_item_async xp_dock_restore_item_async
#define qwm_dock_remove_item xp_dock_remove_item
#define qwm_dock_drag_begin xp_dock_drag_begin
#define qwm_dock_drag_end xp_dock_drag_end
#define qwm_dock_event_set_handler xp_dock_event_set_handler

static inline void qwm_dock_init(bool only_proxy) {
    int options = XP_IN_BACKGROUND;

    if (!only_proxy)
        options |= XP_DOCK_SUPPORT;
    xp_init(options);
}

#else

/* If our Xplugin headers aren't new enough, provide missing types */
#if !defined(XPLUGIN_VERSION) || XPLUGIN_VERSION < 5
typedef unsigned int xp_native_window_id;

#define XP_NULL_NATIVE_WINDOW_ID ((xp_native_window_id)0)

/* Dock location */
enum xp_dock_orientation_enum {
    XP_DOCK_ORIENTATION_BOTTOM = 2,
    XP_DOCK_ORIENTATION_LEFT   = 3,
    XP_DOCK_ORIENTATION_RIGHT  = 4,
};
typedef enum xp_dock_orientation_enum xp_dock_orientation;

/* Event handling */
typedef enum {
    XP_DOCK_EVENT_RESTORE_ALL_WINDOWS = 1,
    XP_DOCK_EVENT_RESTORE_WINDOWS     = 2,
    XP_DOCK_EVENT_SELECT_WINDOWS      = 3,
    XP_DOCK_EVENT_RESTORE_DONE        = 4,
    XP_DOCK_EVENT_MINIMIZE_DONE       = 5,
} xp_dock_event_type;

typedef struct {
    xp_dock_event_type type;

    /* XP_NULL_NATIVE_WINDOW_ID terminated list of windows affected by this event */
    xp_native_window_id *windows;

    /* YES if the event was successful (for XP_DOCK_EVENT_RESTORE_DONE and XP_DOCK_EVENT_MINIMIZE_DONE) */
    xp_bool success;
} xp_dock_event;

typedef void (*xp_dock_event_handler)(xp_dock_event *event);
#endif

extern xp_dock_orientation qwm_dock_get_orientation(void);
extern xp_box qwm_dock_get_rect(void);

/* Window Visibility */
extern xp_error qwm_dock_is_window_visible(xp_native_window_id osxwindow_id, xp_bool *is_visible);

/* Minimize / Restore */
extern xp_error qwm_dock_minimize_item_with_title_async(xp_native_window_id osxwindow_id, const char * title);
extern xp_error qwm_dock_restore_item_async(xp_native_window_id osxwindow_id);
extern xp_error qwm_dock_remove_item(xp_native_window_id osxwindow_id);

/* Window dragging */
extern xp_error qwm_dock_drag_begin(xp_native_window_id osxwindow_id);
extern xp_error qwm_dock_drag_end(xp_native_window_id osxwindow_id);

/* Initialization */
extern void qwm_dock_init(bool only_proxy);
extern void qwm_dock_event_set_handler(xp_dock_event_handler new_handler);

#endif /* XPLUGIN_DOCK_SUPPORT */
#endif /* __DOCK_SUPPORT_H__ */
