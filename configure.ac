dnl Copyright (c) 2010 Apple Inc. All Rights Reserved.
dnl
dnl @APPLE_LICENSE_HEADER_START@
dnl
dnl This file contains Original Code and/or Modifications of Original Code
dnl as defined in and that are subject to the Apple Public Source License
dnl Version 2.0 (the 'License'). You may not use this file except in
dnl compliance with the License. Please obtain a copy of the License at
dnl http://www.opensource.apple.com/apsl/ and read it before using this
dnl file.
dnl
dnl The Original Code and all software distributed under the License are
dnl distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
dnl EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
dnl INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
dnl FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
dnl Please see the License for the specific language governing rights and
dnl limitations under the License.
dnl
dnl @APPLE_LICENSE_HEADER_END@

AC_PREREQ([2.61])
AC_INIT(quartz-wm,[1.2.2], [http://xquartz.macosforge.org],quartz-wm)
AM_INIT_AUTOMAKE([foreign dist-bzip2])
AM_MAINTAINER_MODE

AC_CONFIG_HEADERS([config.h])

# Require xorg-macros: XORG_DEFAULT_OPTIONS
m4_ifndef([XORG_MACROS_VERSION],
          [m4_fatal([must install xorg-macros 1.3 or later before running autoconf/autogen])])
XORG_MACROS_VERSION(1.3)
XORG_DEFAULT_OPTIONS

AC_PROG_CC
AC_PROG_OBJC
AC_PROG_INSTALL

# Checks for pkg-config packages
PKG_CHECK_MODULES(QUARTZWM, [applewm >= 1.4] pixman-1 x11 xext xinerama xrandr)
AC_SUBST(QUARTZWM_CFLAGS)
AC_SUBST(QUARTZWM_LIBS)

AC_ARG_WITH(bundle-id-prefix,  AS_HELP_STRING([--with-bundle-id-prefix=PATH], [Prefix to use for bundle identifiers (default: org.x)]),
                               [BUNDLE_ID_PREFIX="${withval}"],
                               [BUNDLE_ID_PREFIX="org.x"])
AC_SUBST([BUNDLE_ID_PREFIX])
AC_DEFINE_UNQUOTED(BUNDLE_ID_PREFIX, "$BUNDLE_ID_PREFIX", [Prefix to use for bundle identifiers])

AC_ARG_ENABLE(xplugin-dock-support, AS_HELP_STRING([--enable-xplugin-dock-support], [Enable using libXplugin directly for dock support (default: NO)]),
                                    [XPLUGIN_DOCK_SUPPORT="${enableval}"],
                                    [XPLUGIN_DOCK_SUPPORT="no"])
AC_SUBST([XPLUGIN_DOCK_SUPPORT])
if test "x$XPLUGIN_DOCK_SUPPORT" = "xyes"; then
    AC_DEFINE(XPLUGIN_DOCK_SUPPORT, 1, [Use libXplugin directly for dock support])
fi
AM_CONDITIONAL(XPLUGIN_DOCK_SUPPORT, [test "x$XPLUGIN_DOCK_SUPPORT" = "xyes"])

AC_OUTPUT([Makefile
	   lib/Makefile
	   src/Makefile
	   man/Makefile])
