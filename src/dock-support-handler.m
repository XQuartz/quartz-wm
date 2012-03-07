/* dock-support-handler.m
 *
 * Copyright (c) 2012 Apple Inc. All Rights Reserved.
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

#include <X11/Xlib.h>
#include <X11/extensions/applewm.h>

#include "quartz-wm.h"
#include "x-list.h"
#include "x-window.h"

#include "dock-support.h"

void dock_event_handler(xp_dock_event *event) {
    x_list *s_node = NULL, *w_node = NULL;
    x_window *w = NULL;
    x_screen *s = NULL;
    xp_native_window_id *native_wid;

    switch (event->type) {
        case XP_DOCK_EVENT_RESTORE_ALL_WINDOWS:
            for (s_node = screen_list; s_node != NULL; s_node = s_node->next) {
                s = s_node->data;
                for (w_node = s->_window_list; w_node != NULL; w_node = w_node->next) {
                    w = w_node->data;
                    if (w->_minimized) {
                        DB("  restoring window wid:%x\n", [w get_osx_id]);
                        [w do_uncollapse_and_tell_dock:FALSE];
                    }
                }
            }
            break;
        case XP_DOCK_EVENT_RESTORE_WINDOWS:
        case XP_DOCK_EVENT_SELECT_WINDOWS:
        case XP_DOCK_EVENT_RESTORE_DONE:
        case XP_DOCK_EVENT_MINIMIZE_DONE:
            if (event->type == XP_DOCK_EVENT_RESTORE_WINDOWS ||
                event->type == XP_DOCK_EVENT_SELECT_WINDOWS)
                XAppleWMSetFrontProcess (x_dpy);

            for (native_wid = event->windows; *native_wid != XP_NULL_NATIVE_WINDOW_ID; native_wid++) {
                w = x_get_window_by_osx_id (*native_wid);
                if (w == NULL) {
                    DB("Invalid native window id: %u\n", *native_wid);
                    return;
                }

                switch (event->type) {
                    case XP_DOCK_EVENT_RESTORE_WINDOWS:
                        [w do_uncollapse_and_tell_dock:FALSE];
                        [w activate:CurrentTime];
                        break;
                    case XP_DOCK_EVENT_SELECT_WINDOWS:
                        [w activate:CurrentTime];
                        break;
                    case XP_DOCK_EVENT_RESTORE_DONE:
                        [w uncollapse_finished:event->success];
                        break;
                    case XP_DOCK_EVENT_MINIMIZE_DONE:
                        [w collapse_finished:event->success];
                        break;
                    default:
                        break;
                }
            }
            XFlush (x_dpy);
            break;
        default:
            break;
    }
}
