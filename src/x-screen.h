/* x-screen.h
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

#ifndef X_SCREEN_H
#define X_SCREEN_H 1

#import  <Foundation/Foundation.h>

#define  Cursor X_Cursor
#include <X11/Xlib.h>
#undef Cursor

#include "x-list.h"
#include "x11-geometry.h"
#include "dock-support.h"

@class x_window;

@interface x_screen : NSObject
{
@public
    Screen *_screen;
    int _id;
    Window _root;
    int _x, _y;
    int _width, _height;

    int _depth;
    Visual *_visual;
    Colormap _colormap;
    unsigned long _black_pixel;

    X11Rect *_heads;
    int _head_count;
    X11Rect _main_head;

    X11Region * _screen_region;

    x_list *_window_list;
    x_list *_stacking_list;

    Window _net_wm_window;

    unsigned _updates_disabled :1;
}

- (void) set_root_property:(const char *)name type:(const char *)type
                    length:(int)length data:(const long *)data;
- init_with_screen_id:(int)id;
- (void) update_geometry;
- (void) focus_topmost:(Time)timestamp;
- (x_list *) stacking_order:(x_list *)group;
- (void) raise_windows:(id *)array count:(size_t)n;
- (void) adopt_window:(Window)id initializing:(BOOL)flag;
- (void) remove_window:(x_window *)w safe:(BOOL)safe;
- (void) remove_window:(x_window *)w;
- (void) remove_callback:(NSTimer *)timer;
- (void) window_hidden:(x_window *)w;
- (void) adopt_windows;
- (void) unadopt_windows;
- (void) error_shutdown;
- get_window:(Window)xwindow_id;
- get_window_by_osx_id:(xp_native_window_id)id;
- (X11Rect) validate_window_position:(X11Rect)r titlebar_height:(size_t)titlebar_height;
- (X11Rect) zoomed_rect:(X11Point)p;
- (X11Rect) zoomed_rect;
- (X11Point) center_on_head:(X11Point)p;
- (void) disable_update;
- (void) reenable_update;
- (void) raise_all;
- (void) hide_all;
- (void) show_all:(BOOL)flag;
- (void) foreach_window:(SEL)selector;
- find_window_at:(X11Point)p slop:(int)epsilon;

/* Convert geometry on this screen */
- (X11Point) CGToX11Point:(CGPoint)p;
- (X11Point) NSToX11Point:(NSPoint)p;
- (X11Rect) CGToX11Rect:(CGRect)r;
- (X11Rect) NSToX11Rect:(NSRect)r;
- (CGPoint) X11ToCGPoint:(X11Point)p;
- (NSPoint) X11ToNSPoint:(X11Point)p;
- (CGRect)  X11ToCGRect:(X11Rect)r;
- (NSRect)  X11ToNSRect:(X11Rect)r;

@end

#endif /* X_SCREEN_H */
