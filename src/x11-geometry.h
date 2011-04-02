/* x11-geometry.h
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

#ifndef __X11_GEOMETRY_H__
#define __X11_GEOMETRY_H__

#include <pixman.h>
#include <stdbool.h>

typedef pixman_rectangle32_t                    X11Rect;
typedef struct {int32_t x; int32_t y;}          X11Point;
typedef struct {int32_t width; int32_t height;} X11Size;
typedef pixman_region32_t                       X11Region;

extern X11Rect X11EmptyRect;

static inline X11Rect X11RectMake(int32_t x, int32_t y, int32_t w, int32_t h) {
    X11Rect ret;
    ret.x = x;
    ret.y = y;   
    ret.width = w;
    ret.height = h;
    return ret;
}

static inline X11Point X11PointMake(int32_t x, int32_t y) {
    X11Point ret;
    ret.x = x;
    ret.y = y;
    return ret;
}

static inline X11Size X11SizeMake(int32_t width, int32_t height) {
    X11Size ret;
    ret.width = width;
    ret.height = height;
    return ret;
}

static inline X11Point X11RectOrigin(X11Rect r) {
    return X11PointMake(r.x, r.y);
}

static inline X11Size X11RectSize(X11Rect r) {
    return X11SizeMake(r.width, r.height);
}

static inline bool X11PointEqualToPoint(X11Point a, X11Point b) {
    return (a.x == b.x && a.y == b.y);
}

static inline bool X11SizeEqualToSize(X11Size a, X11Size b) {
    return (a.width == b.width && a.height == b.height);
}

static inline bool X11RectEqualToRect(X11Rect a, X11Rect b) {
    return (a.x == b.x && a.y == b.y &&
            a.width == b.width && a.height == b.height);
}

static inline bool X11RectContainsPoint(X11Rect r, X11Point p) {
    return (r.x <= p.x && p.x <= r.x + r.width &&
            r.y <= p.y && p.y <= r.y + r.height);
}

static inline bool X11RectIsEmpty(X11Rect r) {
    return X11RectEqualToRect(r, X11EmptyRect);
}

extern X11Rect X11RectIntersection(X11Rect a, X11Rect b);

#endif /* __X11_GEOMETRY_H__ */
