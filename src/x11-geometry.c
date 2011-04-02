/* x11-geometry.c
 *
 * Copyright (c) 2011 Apple Inc. All Rights Reserved.
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

#include "x11-geometry.h"

#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define MAX(a, b) ((a) > (b) ? (a) : (b))

X11Rect X11EmptyRect = {0, 0, 0, 0};

X11Rect X11RectIntersection(X11Rect a, X11Rect b) {
    pixman_box32_t ba, bb, f;

    ba.x1 = a.x;
    ba.y1 = a.y;
    ba.x2 = a.x + a.width;
    ba.y2 = a.y + a.height;

    bb.x1 = b.x;
    bb.y1 = b.y;
    bb.x2 = b.x + b.width;
    bb.y2 = b.y + b.height;

    f.x1 = MAX(ba.x1, bb.x1);
    f.y1 = MAX(ba.y1, bb.y1);
    f.x2 = MIN(ba.x2, bb.x2);
    f.y2 = MIN(ba.y2, bb.y2);

    if(f.x1 <= f.x2 && f.y1 <= f.y2) {
        return X11RectMake(f.x1, f.y1, f.x2 - f.x1, f.y2 - f.y1);
    } else {
        return X11EmptyRect;
    }
}
