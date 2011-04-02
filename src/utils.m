/* utils.m
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

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "utils.h"
#include "quartz-wm.h"

#include <X11/Xatom.h>

int
x_get_property (Window id, Atom atom, long *dest,
                unsigned int dest_size, unsigned int min_items)
{
    Atom type;
    int format;
    unsigned int i;
    unsigned long nitems;
    unsigned char *data = 0;
    int ret = 0;

    do {
        long long_length = 32;
        u_long bytes_after;
        while (1)
        {
            if (data != NULL)
                XFree (data);

            if (XGetWindowProperty (x_dpy, id, atom, 0, long_length, False,
                                    AnyPropertyType, &type, &format,
                                    &nitems, &bytes_after, &data) != Success)
                return 0;
            if (type == None)
                return 0;
            if (bytes_after == 0)
                break;
            long_length += (bytes_after / sizeof(unsigned long)) + 1;
        }
    } while (0);

    if (format == 32 && nitems >= min_items)
    {
        for (i = 0; i < MIN (nitems, dest_size); i++)
            dest[i] = ((unsigned long *) data)[i];
        ret = i;
    }

    XFree (data);

    return ret;
}

NSString *
x_get_string_property (Window id, Atom atom)
{
    Atom type;
    int format;
    unsigned long nitems;
    unsigned char *data = 0;
    NSString *ret = nil;

    do {
        long long_length = 32;
        u_long bytes_after;
        while (1)
        {
            if (data != NULL)
                XFree (data);

            if (XGetWindowProperty (x_dpy, id, atom, 0, long_length, False,
                                    AnyPropertyType, &type, &format,
                                    &nitems, &bytes_after, &data) != Success)
                return nil;
            if (type == None)
                return nil;
            if (bytes_after == 0)
                break;
            long_length += (bytes_after / sizeof(unsigned long)) + 1;
        }
    } while (0);

    if (format == 8) {
        if (type == atoms.utf8_string)
            ret = [NSString stringWithUTF8String:(char *) data];
        else
            ret = [NSString stringWithCString:(char *) data];
    }

    XFree (data);

    return ret;
}
