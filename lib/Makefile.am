# Copyright (c) 2012 Apple Inc. All Rights Reserved.
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

DIST_LIB = libquartz-wm-ds.apsl.dylib
LIBRARY_BASENAME = libquartz-wm-ds.1.dylib
LIBRARY_SYMLINK = libquartz-wm-ds.dylib

all : $(LIBRARY_SYMLINK)

$(LIBRARY_SYMLINK) : $(LIBRARY_BASENAME)
	rm -f $@
	ln -s $^ $@

$(LIBRARY_BASENAME) : $(DIST_LIB)
	cp $^ $@
	install_name_tool -id $(libdir)/$@ $@

install-exec-hook : $(LIBRARY_BASENAME)
	install -d -m 755 $(DESTDIR)$(libdir)
	install -m 755 $(LIBRARY_BASENAME) $(DESTDIR)$(libdir)
	rm -f $(DESTDIR)$(libdir)/$(LIBRARY_SYMLINK)
	ln -s $(LIBRARY_BASENAME) $(DESTDIR)$(libdir)/$(LIBRARY_SYMLINK)

CLEANFILES = $(LIBRARY_SYMLINK) $(LIBRARY_BASENAME)

EXTRA_DIST = dock-support.h $(DIST_LIB)
