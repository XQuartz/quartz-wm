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
AC_INIT(quartz-wm,[1.2.0], [http://xquartz.macosforge.org],quartz-wm)
AM_INIT_AUTOMAKE([foreign dist-bzip2])
AM_MAINTAINER_MODE

AM_CONFIG_HEADER(config.h)

# Require xorg-macros: XORG_DEFAULT_OPTIONS
m4_ifndef([XORG_MACROS_VERSION],
          [m4_fatal([must install xorg-macros 1.3 or later before running autoconf/autogen])])
XORG_MACROS_VERSION(1.3)
XORG_DEFAULT_OPTIONS

AC_PROG_CC
AC_PROG_OBJC
AC_PROG_INSTALL

# Checks for pkg-config packages
PKG_CHECK_MODULES(QUARTZWM, [applewm >= 1.4] pixman-1 x11 xext xinerama)
AC_SUBST(QUARTZWM_CFLAGS)
AC_SUBST(QUARTZWM_LIBS)

AC_MSG_CHECKING(which object file to use for dok-support.o)
case $host_os in
	darwin[678]*)
		DOCK_SUPPORT_O="dock-support-10.4.o"
		;;
	darwin*)
		DOCK_SUPPORT_O="dock-support-10.5.o" 
		;;
	*)
		AC_ERROR([quartz-wm is not supported on your system.])
		;;
esac
AC_SUBST(DOCK_SUPPORT_O)
AC_MSG_RESULT($DOCK_SUPPORT_O)

AC_OUTPUT([Makefile
	   src/Makefile
	   man/Makefile])
