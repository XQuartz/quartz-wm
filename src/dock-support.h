/* dock-support.h
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

#ifndef __DOCK_SUPPORT_H__
#define __DOCK_SUPPORT_H__

#include <CoreGraphics/CoreGraphics.h>
#include <stdint.h>

typedef uint32_t OSXWindowID;

#define kOSXNullWindowID ((OSXWindowID)0)

/* Dock location */
typedef enum {
   kDockBottom = 2,
   kDockLeft   = 3,
   kDockRight  = 4,
} DockOrientation;

extern DockOrientation DockGetOrientation(void);
extern CGRect DockGetRect(void);

/* Window Visibility */
extern CGError DockIsWindowVisible(OSXWindowID window_id, BOOL *isVisible);

/* Minimize / Restore */
extern OSStatus DockMinimizeItemWithTitleAsync(OSXWindowID osxwindow_id, CFStringRef title);
extern OSStatus DockRestoreItemAsync(OSXWindowID osxwindow_id);
extern OSStatus DockRemoveItem(OSXWindowID osxwindow_id);

/* Window dragging */
extern OSStatus DockDragBegin(OSXWindowID osxwindow_id);
extern OSStatus DockDragEnd(OSXWindowID osxwindow_id);

/* Initialization */
extern void DockInit(bool only_proxy);

#endif /* __DOCK_SUPPORT_H__ */
