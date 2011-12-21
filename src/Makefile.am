# Copyright (c) 2010 Apple Inc. All Rights Reserved.
#
# @APPLE_LICENSE_HEADER_START@
#
# This file contains Original Code and/or Modifications of Original Code
# as defined in and that are subject to the Apple Public Source License
# Version 2.0 (the 'License'). You may not use this file except in
# compliance with the License. Please obtain a copy of the License at
# http://www.opensource.apple.com/apsl/ and read it before using this
# file.
# 
# The Original Code and all software distributed under the License are
# distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
# EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
# INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
# Please see the License for the specific language governing rights and
# limitations under the License.
#
# @APPLE_LICENSE_HEADER_END@

bin_PROGRAMS = quartz-wm

AM_CPPFLAGS = -F /System/Library/Frameworks/ApplicationServices.framework/Frameworks
AM_OBJCFLAGS = $(QUARTZWM_CFLAGS) $(CWARNFLAGS)
AM_CFLAGS = $(QUARTZWM_CFLAGS) $(CWARNFLAGS)

quartz_wm_LDFLAGS = $(QUARTZWM_LIBS) \
	-framework AppKit \
	-framework Foundation \
	-framework ApplicationServices \
	-undefined dynamic_lookup

quartz_wm_LDADD = dock-support.o

quartz_wm_SOURCES = \
	dock-support.h \
	frame.h \
	frame.m \
	main.m \
	quartz-wm.h \
	utils.h \
	utils.m \
	x-input.m \
	x-list.c \
	x-list.h \
	x-screen.h \
	x-screen.m \
	x-selection.h \
	x-selection.m \
	x-window.h \
	x-window.m \
	x11-geometry.c \
	x11-geometry.h

EXTRA_DIST = binary/dock-support-10.4.o binary/dock-support-10.5.o

BUILT_SOURCES = dock-support.o
MAINTAINERCLEANFILES = $(BUILT_SOURCES)

dock-support.o : $(srcdir)/binary/@DOCK_SUPPORT_O@
	cp $(srcdir)/binary/@DOCK_SUPPORT_O@ dock-support.o
