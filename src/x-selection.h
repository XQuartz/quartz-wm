/* x-selection.h -- proxies between NSPasteboard and X11 selections
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

#ifndef X_SELECTION_H
#define X_SELECTION_H 1

#include <AppKit/NSPasteboard.h>

#define  Cursor X_Cursor
#include <X11/Xlib.h>
#undef   Cursor

@interface x_selection : NSObject
{
@private

    /* The unmapped window we use for fetching selections. */
    Window _selection_window;

    /* Cached general pasteboard and array of types we can handle. */
    NSPasteboard *_pasteboard;
    NSArray *_known_types;

    /* Last time we declared anything on the pasteboard. */
    int _my_last_change;

    /* Name of the selection we're proxying onto the pasteboard. */
    Atom _proxied_selection;

    /* When true, we're expecting a SelectionNotify event. */
    unsigned int _pending_notify :1;
}

- (void) x_active:(Time)timestamp;
- (void) x_inactive:(Time)timestamp;

- (void) x_copy:(Time)timestamp;

- (void) clear_event:(XSelectionClearEvent *)e;
- (void) request_event:(XSelectionRequestEvent *)e;
- (void) notify_event:(XSelectionEvent *)e;

@end

#endif /* X_SELECTION_H */
