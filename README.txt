README
------

ElectropaintOSX v. 0.4.0

ElectropaintOSX is a macOS screensaver port of Kent Rosenkoetter's clone
of SGI's Electropaint screensaver "the most mesmerizing screensaver ever
written".  This version replaces the original OpenGL renderer with a fully
Metal-based renderer, restoring compatibility with macOS 26 (Sequoia) and
later where OpenGL and NSOpenGLView are no longer functional in screensaver
contexts.

Kent's page can be found here:

    http://legolas.homelinux.org/~kent/electropaint/
    https://web.archive.org/web/20041210033146/http://legolas.homelinux.org/~kent/electropaint/

The OS X port by Douglas McInnes lives here:

    http://www.lloydslounge.org/electropaint/
    https://web.archive.org/web/20110222022854/http://www.lloydslounge.org/electropaint/

History
-------

    For the 0.2 version, Modifications for antialiasing, VBL, parameter 
    tweak has been done by Vincent Fiano <ynniv-ep@ynniv.com>.  Thanks 
    Vincent!

    Version 0.3 is a universal binary, currently raising the minimum 
    system requirements to 10.3.9. Changes by Alexander von Below 
    <Alex@vonBelow.Com>

    Version 0.3.1 is a universal binary, currently raising the minimum 
    system requirements to 10.5. It supports 64-bit and Garbage Collection 
    under 10.6.  Changes by Thomas Vo�en <info@crimsonmagic.net>.

    Version 0.3.2 has been build against the 10.8 SDK. It is compatible 
    with Mac OS X 10.8, raising the minimum system requirements to 
    10.8.0. No changes in code. Build by Thomas Vo�en 
    <info@crimsonmagic.net>.

    Version 0.3.3 includes normal and HIPDI icons used in the system
    preferences panel. Thanks to Peter Leonard for kindly supplying the 
    image files.

    Version 0.3.4 fixes a warning during build under Mac OS X 10.10.  
    Thanks to Douglas Carmichael for sending the bug report.

    Version 0.3.5 is notarised and some autorelease initializer have 
    been changed.

    Version 0.3.6 is a minor update for BigSur (MacOSX 11) and M1 macs.
    The minimum system requirement is now 10.9.

    Version 0.3.7 is a minor update to support hi-res displays.

    Version 0.4.0 is a complete rewrite of the renderer for macOS 26
    (Sequoia) compatibility. Key changes:

    - OpenGL/NSOpenGLView replaced with Metal (CAMetalLayer as sublayer).
      OpenGL is non-functional in screensaver contexts on macOS 26 due to
      layer-backed view changes.

    - Rendering logic extracted into ElectropaintRenderer, a standalone
      NSObject class that owns the Metal pipeline, animation state, and
      CAMetalLayer.  ElectropaintView is now a thin ScreenSaverView
      subclass that delegates to the renderer.

    - Per-instance state stored via Objective-C associated objects
      (objc_setAssociatedObject). macOS 26 runs screensavers inside
      legacyScreenSaver.appex, an XPC extension that creates multiple
      ElectropaintView instances per process (probe views for display
      enumeration plus the actual view). Using associated objects ensures
      each instance has independent state with no cross-instance
      interference or ivar offset collisions with ScreenSaverView
      private ivars.

    - Visibility tracking for soft-stop. On macOS 26, the framework
      often does NOT call stopAnimation when the screensaver is
      dismissed, leaving the legacyScreenSaver process alive with its
      internal _oneStep: timer consuming CPU. The view now detects
      dismissal via NSWindowWillCloseNotification, viewDidMoveToWindow,
      and a watchdog in animateOneFrame. When any view detects dismissal,
      all views in the process are soft-stopped (stopAnimation called on
      each) to reach 0% residual CPU.

    - NSPrincipalClass corrected to "ElectropaintView" (was
      "ElectropaintOSXView"). An incorrect value causes the ScreenSaver
      framework to scan all NSObject subclasses and call
      initWithFrame:isPreview: on each one, resulting in a crash.

    - Code signing required after installation. Copying the bundle with
      cp -R changes the binary mtime, invalidating Xcode's embedded
      signature. macOS 26 enforces cs_mtime == mtime strictly and will
      silently remove bundles that fail dlopen. Always run:
        codesign --force --sign - ~/Library/Screen\ Savers/ElectropaintOSX.saver
      immediately after copying.

    - Minimum system requirement raised to macOS 26.0.
    - Universal binary: arm64 + x86_64.
    - Build requires Xcode 26 or later.
    - Legacy Carbon Resources build phase removed from project.

Building and Installing
-----------------------

    Build:
        xcodebuild -project ElectropaintOSX.xcodeproj -configuration Development

    Install (must re-sign after copy):
        cp -R build/Development/ElectropaintOSX.saver ~/Library/Screen\ Savers/
        codesign --force --sign - ~/Library/Screen\ Savers/ElectropaintOSX.saver

License
-------

    Copyright (C) 2004 Kent Rosenkoetter, Douglas McInnes

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; either version 2
    of the License, or (at your option) any later version. Please 
    see the included gpl.txt for the full license text.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

