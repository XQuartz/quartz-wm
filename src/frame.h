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

extern void draw_frame (int screen, Window id, X11Rect outer_r,
			X11Rect inner_r, unsigned int class,
			unsigned int attr, CFStringRef title);
extern int frame_titlebar_height (unsigned int class);
extern X11Rect frame_titlebar_rect (X11Rect outer_r, X11Rect inner_r,
                                    unsigned int attr);
extern X11Rect frame_tracking_rect (X11Rect outer_r, X11Rect inner_r,
				   unsigned int attr, unsigned int class);
extern X11Rect frame_growbox_rect (X11Rect outer_r, X11Rect inner_r,
				  unsigned int attr, unsigned int class);
extern unsigned int frame_hit_test (X11Rect outer_r, X11Rect inner_r,
				    unsigned int class, X11Point p);

#endif /* XP_FRAME_H */
