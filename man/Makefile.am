# Copyright (c) 2010-2011 Apple Inc. All Rights Reserved.
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

appmandir = $(APP_MAN_DIR)
appman_PRE = quartz-wm.man
appman_DATA = $(appman_PRE:man=$(APP_MAN_SUFFIX))

EXTRA_DIST = $(appman_PRE)
CLEANFILES = $(appman_DATA)
SUFFIXES = .$(APP_MAN_SUFFIX) .man

MAN_SUBSTS += 	-e 's|__bundle_id_prefix__|$(BUNDLE_ID_PREFIX)|g'

.man.$(APP_MAN_SUFFIX):
	$(AM_V_GEN)$(SED) $(MAN_SUBSTS) < $< > $@
