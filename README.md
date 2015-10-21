## About ##

quartz-wm is the window manager used by XQuartz to bring an OS X-like experience to X11 applications.  It makes use of the AppleWM X11 protocol extension to have libXplugin within XQuartz render window decoration on its behalf and handles basic window manager functionality as described by the [ICCM](http://tronche.com/gui/x/icccm).

## OSS ##

quartz-wm was release by Apple under the terms of the [Apple Public Source License Version 2](http://www.opensource.apple.com/license/apsl) in December 2011 including git history covering recent changes.  A small portion of quartz-wm has been released binary-only for use by older OS versions.  The functionality provided by this binary has been merged into libXplugin on newer versions of OS X.

## Source Releases ##

Please visit our Github [releases](https://github.com/XQuartz/quartz-wm/releases) page for a full listing of quartz-wm releases.

## Building ##

You can check out, build, and install the latest version with:

    git clone https://github.com/XQuartz/quartz-wm.git
    cd quartz-wm
    ACLOCAL="aclocal -I /opt/X11/share/aclocal" autoreconf -fvi
    PKG_CONFIG_PATH=/opt/X11/share/pkgconfig:/opt/X11/lib/pkgconfig ./configure --prefix=/opt/X11
    make
