/* frame.h
 *
 * Copyright (c) 2002-2010 Apple Inc. All Rights Reserved
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

#ifndef FRAME_H
#define FRAME_H 1

#include <Foundation/Foundation.h>

#define XP_NO_X_HEADERS 1
#include <Xplugin.h>

#define  Cursor X_Cursor
#include <X11/Xlib.h>
#undef   Cursor

#include "x11-geometry.h"

#if XPLUGIN_VERSION < 4
#warning "Old libXplugin version detected.  Some features may not be supported."

typedef enum xp_frame_class_enum xp_frame_class;
typedef enum xp_frame_attr_enum xp_frame_attr;

#define XP_FRAME_CLASS_DECOR_LARGE          XP_FRAME_CLASS_DOCUMENT
#define XP_FRAME_CLASS_DECOR_SMALL          XP_FRAME_CLASS_UTILITY
#define XP_FRAME_CLASS_DECOR_NONE           XP_FRAME_CLASS_SPLASH
#define XP_FRAME_CLASS_BEHAVIOR_MANAGED     (1 << 15)
#define XP_FRAME_CLASS_BEHAVIOR_TRANSIENT   (1 << 16)
#define XP_FRAME_CLASS_BEHAVIOR_STATIONARY  (1 << 17)

#define XP_FRAME_ATTR_ACTIVE XP_FRAME_ACTIVE
#define XP_FRAME_ATTR_URGENT XP_FRAME_URGENT
#define XP_FRAME_ATTR_TITLE XP_FRAME_TITLE
#define XP_FRAME_ATTR_PRELIGHT XP_FRAME_PRELIGHT
#define XP_FRAME_ATTR_SHADED XP_FRAME_SHADED
#define XP_FRAME_ATTR_CLOSE_BOX XP_FRAME_CLOSE_BOX
#define XP_FRAME_ATTR_COLLAPSE XP_FRAME_COLLAPSE
#define XP_FRAME_ATTR_ZOOM XP_FRAME_ZOOM
#define XP_FRAME_ATTR_CLOSE_BOX_CLICKED XP_FRAME_CLOSE_BOX_CLICKED
#define XP_FRAME_ATTR_COLLAPSE_BOX_CLICKED XP_FRAME_COLLAPSE_BOX_CLICKED
#define XP_FRAME_ATTR_ZOOM_BOX_CLICKED XP_FRAME_ZOOM_BOX_CLICKED
#define XP_FRAME_ATTR_GROW_BOX XP_FRAME_GROW_BOX

#define XP_FRAME_ATTRS_ANY_BUTTON XP_FRAME_ANY_BUTTON
#define XP_FRAME_ATTRS_ANY_CLICKED XP_FRAME_ANY_CLICKED
#define XP_FRAME_ATTRS_POINTER XP_FRAME_POINTER_ATTRS
#endif

extern void draw_frame (int screen, Window id, X11Rect outer_r,
			X11Rect inner_r, xp_frame_class class,
			xp_frame_attr attr, CFStringRef title);
extern int frame_titlebar_height (xp_frame_class class);
extern X11Rect frame_tracking_rect (X11Rect outer_r, X11Rect inner_r,
                                   xp_frame_class class);
extern X11Rect frame_growbox_rect (X11Rect outer_r, X11Rect inner_r, 
                                   xp_frame_class class);
extern unsigned int frame_hit_test (X11Rect outer_r, X11Rect inner_r,
				    xp_frame_class class, X11Point p);

#endif /* XP_FRAME_H */
