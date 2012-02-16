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

#include <ApplicationServices/ApplicationServices.h>
#include <objc/objc.h>

typedef uint32_t qwm_native_window_id;

#define QWM_NULL_NATIVE_WINDOW_ID ((qwm_native_window_id)0)

/* Dock location */
typedef enum {
    QWM_DOCK_ORIENTATION_BOTTOM = 2,
    QWM_DOCK_ORIENTATION_LEFT   = 3,
    QWM_DOCK_ORIENTATION_RIGHT  = 4,
} qwm_dock_orientation;

extern qwm_dock_orientation qwm_dock_get_orientation(void);
extern CGRect qwm_dock_get_rect(void);

/* Window Visibility */
extern CGError qwm_dock_is_window_visible(qwm_native_window_id window_id, BOOL *is_visible);

/* Minimize / Restore */
extern OSStatus qwm_dock_minimize_item_with_title_async(qwm_native_window_id osxwindow_id, CFStringRef title);
extern OSStatus qwm_dock_restore_item_async(qwm_native_window_id osxwindow_id);
extern OSStatus qwm_dock_remove_item(qwm_native_window_id osxwindow_id);

/* Window dragging */
extern OSStatus qwm_dock_drag_begin(qwm_native_window_id osxwindow_id);
extern OSStatus qwm_dock_drag_end(qwm_native_window_id osxwindow_id);

/* Initialization */
extern void qwm_dock_init(bool only_proxy);

/* Event handling */
typedef enum {
    QWM_DOCK_EVENT_RESTORE_ALL_WINDOWS = 1,
    QWM_DOCK_EVENT_RESTORE_WINDOWS    = 2,
    QWM_DOCK_EVENT_SELECT_WINDOWS     = 3,
    QWM_DOCK_EVENT_RESTORE_DONE       = 4,
    QWM_DOCK_EVENT_MINIMIZE_DONE      = 5,
} qwm_dock_event_type;

typedef struct {
    qwm_dock_event_type type;

    /* QWM_NULL_NATIVE_WINDOW_ID terminated list of windows affected by this event */
    qwm_native_window_id *windows;

    /* YES if the event was successful (for QWM_DOCK_EVENT_RESTORE_DONE and QWM_DOCK_EVENT_MINIMIZE_DONE) */
    BOOL success;
} qwm_dock_event;

typedef void (*qwm_dock_event_handler)(qwm_dock_event *event);
extern void qwm_dock_event_set_handler(qwm_dock_event_handler new_handler);

#endif /* __DOCK_SUPPORT_H__ */
