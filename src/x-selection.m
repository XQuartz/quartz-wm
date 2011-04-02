/* x-selection.m
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

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "quartz-wm.h"

#import "x-selection.h"

#include <X11/Xatom.h>

#include <unistd.h>

@implementation x_selection

static unsigned long *
read_prop_32 (Window id, Atom prop, int *nitems_ret)
{
    int r, format;
    Atom type;
    unsigned long nitems, bytes_after;
    unsigned char *data;

    r = XGetWindowProperty (x_dpy, id, prop, 0, 0,
			    False, AnyPropertyType, &type, &format,
			    &nitems, &bytes_after, &data);

    if (r == Success && bytes_after != 0)
    {
	XFree (data);
	r = XGetWindowProperty (x_dpy, id, prop, 0,
				(bytes_after / 4) + 1, False,
				AnyPropertyType, &type, &format,
				&nitems, &bytes_after, &data);
    }

    if (r != Success)
	return NULL;

    if (format != 32)
    {
	XFree (data);
	return NULL;
    }

    *nitems_ret = nitems;
    return (unsigned long *) data;
}

static float
get_time (void)
{
  UnsignedWide usec;
  long long ll;

  Microseconds (&usec);
  ll = ((long long) usec.hi << 32) | usec.lo;

  return ll / 1e6;
}

static Bool
IfEventWithTimeout (Display *dpy, XEvent *e, int timeout,
		    Bool (*pred) (Display *, XEvent *, XPointer),
		    XPointer arg)
{
    float start = get_time ();
    fd_set fds;
    struct timeval tv;

    do {
	if (XCheckIfEvent (x_dpy, e, pred, arg))
	    return True;

	FD_ZERO (&fds);
	FD_SET (ConnectionNumber (x_dpy), &fds);
	tv.tv_usec = 0;
	tv.tv_sec = timeout;

	if (select (FD_SETSIZE, &fds, NULL, NULL, &tv) != 1)
	    break;

    } while (start + timeout > get_time ());

    return False;
}

/* Called when X11 becomes active (i.e. has key focus) */
- (void) x_active:(Time)timestamp
{
    TRACE ();

    if ([_pasteboard changeCount] != _my_last_change)
    {
	if ([_pasteboard availableTypeFromArray: _known_types] != nil)
	{
	    /* Pasteboard has data we should proxy; I think it makes
	       sense to put it on both CLIPBOARD and PRIMARY */

	    XSetSelectionOwner (x_dpy, atoms.clipboard,
				_selection_window, timestamp);
	    XSetSelectionOwner (x_dpy, atoms.primary,
				_selection_window, timestamp);
	}
    }
}

/* Called when X11 loses key focus */
- (void) x_inactive:(Time)timestamp
{
    Window w;

    TRACE ();

    if (_proxied_selection == atoms.primary)
      return;

    w = XGetSelectionOwner (x_dpy, atoms.clipboard);

    if (w != None && w != _selection_window)
    {
	/* An X client has the selection, proxy it to the pasteboard */

	_my_last_change = [_pasteboard declareTypes:_known_types owner:self];
	_proxied_selection = atoms.clipboard;
    }
}

/* Called when the Edit/Copy item on the main X11 menubar is selected
   and no appkit window claims it. */
- (void) x_copy:(Time)timestamp
{
    Window w;

    /* Lazily copies the PRIMARY selection to the pasteboard. */

    w = XGetSelectionOwner (x_dpy, atoms.primary);

    if (w != None && w != _selection_window)
    {
	XSetSelectionOwner (x_dpy, atoms.clipboard,
			    _selection_window, timestamp);
	_my_last_change = [_pasteboard declareTypes:_known_types owner:self];
	_proxied_selection = atoms.primary;
    }
    else
    {
	XBell (x_dpy, 0);
    }
}


/* X events */

- (void) clear_event:(XSelectionClearEvent *)e
{
    TRACE ();

    /* Right now we don't care about this. */
}

static Atom
convert_1 (XSelectionRequestEvent *e, NSString *data, Atom target, Atom prop)
{
    Atom ret = None;

    if (data == nil)
	return ret;

    if (target == atoms.text)
	target = atoms.utf8_string;

    if (target == atoms.string
	|| target == atoms.cstring
	|| target == atoms.utf8_string)
    {
	const char *bytes;

	if (target == atoms.string)
	    bytes = [data cStringUsingEncoding:NSISOLatin1StringEncoding];
	else
	    bytes = [data UTF8String];

	if (bytes != NULL)
	{
	    XChangeProperty (x_dpy, e->requestor, prop, target,
			     8, PropModeReplace, (unsigned char *) bytes,
			     strlen (bytes));
	    ret = prop;
	}
    }
    /* FIXME: handle COMPOUND_TEXT target */

    return ret;
}

- (void) request_event:(XSelectionRequestEvent *)e
{
    /* Someone's asking us for the data on the pasteboard */

    XEvent reply;
    NSString *data;
    Atom target;

    TRACE ();

    reply.xselection.type = SelectionNotify;
    reply.xselection.selection = e->selection;
    reply.xselection.target = e->target;
    reply.xselection.requestor = e->requestor;
    reply.xselection.time = e->time;
    reply.xselection.property = None;

    target = e->target;

    if (target == atoms.targets)
    {
	long data[2];

	data[0] = atoms.utf8_string;
	data[1] = atoms.string;

	XChangeProperty (x_dpy, e->requestor, e->property, target,
			 8, PropModeReplace, (unsigned char *) &data,
			 sizeof (data));
	reply.xselection.property = e->property;
    }
    else if (target == atoms.multiple)
    {
	if (e->property != None)
	{
	    int i, nitems;
	    unsigned long *atoms;

	    atoms = read_prop_32 (e->requestor, e->property, &nitems);

	    if (atoms != NULL)
	    {
		data = [_pasteboard stringForType:NSStringPboardType];

		for (i = 0; i < nitems; i += 2)
		{
		    Atom target = atoms[i], prop = atoms[i+1];

		    atoms[i+1] = convert_1 (e, data, target, prop);
		}

		XChangeProperty (x_dpy, e->requestor, e->property, target,
				 32, PropModeReplace, (unsigned char *) atoms,
				 nitems);
		XFree (atoms);
	    }
	}
    }

    data = [_pasteboard stringForType:NSStringPboardType];
    if (data != nil)
    {
	reply.xselection.property = convert_1 (e, data, target, e->property);
    }

    XSendEvent (x_dpy, e->requestor, False, 0, &reply);
}

- (void) notify_event:(XSelectionEvent *)e
{
    /* Someone sent us data we're waiting for. */

    Atom type = None;
    int format, r, offset;
    unsigned long nitems, bytes_after;
    unsigned char *data, *buf;
    NSString *string;

    TRACE ();

    if (e->target == atoms.targets)
    {
	/* Was trying to fetch the TARGETS property; it lists the
	   formats supported by the selection owner. */

	unsigned long *_atoms;
	int natoms;
	int i;

	/* May as well try as STRING if nothing else, it can only
	   fail, and it will help broken clients who don't support
	   the TARGETS selection.. */
	type = atoms.string;

	if (e->property != None
	    && (_atoms = read_prop_32 (e->requestor,
				      e->property, &natoms)) != NULL)
	{
	    for (i = 0; i < natoms; i++)
	    {
		if (_atoms[i] == atoms.utf8_string) {
		    type = atoms.utf8_string;
		    break;
                }
	    }
	    XFree (_atoms);
	}

	XConvertSelection (x_dpy, e->selection, type,
			   e->selection, e->requestor, e->time);
	_pending_notify = YES;
	return;
    }

    if (e->property == None)
	return;				/* FIXME: notify pasteboard? */

    /* Should be the data. Find out how big it is and what format it's in. */

    r = XGetWindowProperty (x_dpy, e->requestor, e->property,
			    0, 0, False, AnyPropertyType, &type,
			    &format, &nitems, &bytes_after, &data);
    if (r != Success)
	return;

    XFree (data);
    if (type == None || format != 8)
	return;

    bytes_after += nitems;
    
    /* Read it into a buffer. */

    buf = malloc (bytes_after + 1);
    if (buf == NULL)
	return;

    for (offset = 0; bytes_after > 0; offset += nitems)
    {
	r = XGetWindowProperty (x_dpy, e->requestor, e->property,
				offset / 4, (bytes_after / 4) + 1,
				False, AnyPropertyType, &type,
				&format, &nitems, &bytes_after, &data);
	if (r != Success)
	{
	    free (buf);
	    return;
	}

	memcpy (buf + offset, data, nitems);
	XFree (data);
    }
    buf[offset] = 0;
    XDeleteProperty (x_dpy, e->requestor, e->property);

    /* Convert to an NSString and write to the pasteboard. */

    if (type == atoms.string)
	string = [NSString stringWithCString:(char *) buf];
    else /* if (type == atoms.utf8_string) */
	string = [NSString stringWithUTF8String:(char *) buf];

    free (buf);

    [_pasteboard setString:string forType:NSStringPboardType];
}


/* NSPasteboard-required methods */

static Bool
selnotify_pred (Display *dpy, XEvent *e, XPointer arg)
{
    return e->type == SelectionNotify;
}

- (void) pasteboard:(NSPasteboard *)sender provideDataForType:(NSString *)type
{
    XEvent e;
    Atom request;

    TRACE ();

    /* Don't ask for the data yet, first find out which formats
       the selection owner supports. */

    request = atoms.targets;

again:
    XConvertSelection (x_dpy, _proxied_selection, request,
		       _proxied_selection, _selection_window, CurrentTime);

    _pending_notify = YES;

    /* Seems like we need to be synchronous here.. Actually, this really
       sucks, since it means we could get deadlocked if people don't
       respond to our request. So we need to implement our own timeout
       code.. */

    while (_pending_notify
	   && IfEventWithTimeout (x_dpy, &e, 1, selnotify_pred, NULL))
    {
	_pending_notify = NO;
	[self notify_event:&e.xselection];
    }

    if (_pending_notify && request == atoms.targets)
    {
	/* App didn't respond to request for TARGETS selection. Let's
	   try the STRING selection as a last resort.. Helps broken
	   applications (e.g. nedit, see #3199867) */

	request = atoms.string;
	goto again;
    }

    _pending_notify = NO;
}

- (void) pasteboardChangedOwner:(NSPasteboard *)sender
{
    TRACE ();

    /* Right now we don't care with this. */
}


/* Allocation */

- init
{
    unsigned long pixel;

    self = [super init];
    if (self == nil)
	return nil;

    _pasteboard = [[NSPasteboard generalPasteboard] retain];

    _known_types = [[NSArray arrayWithObject:NSStringPboardType] retain];

    pixel = BlackPixel (x_dpy, DefaultScreen (x_dpy));
    _selection_window = XCreateSimpleWindow (x_dpy, DefaultRootWindow (x_dpy),
					     0, 0, 1, 1, 0, pixel, pixel);

    return self;
}

- (void) dealloc
{
    [_pasteboard releaseGlobally];
    [_pasteboard release];
    _pasteboard = nil;

    [_known_types release];
    _known_types = nil;

    if (_selection_window != 0)
    {
	XDestroyWindow (x_dpy, _selection_window);
	_selection_window = 0;
    }

    [super dealloc];
}

@end
