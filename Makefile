# Makefile for ElectropaintOSX

PROJNAME   = ElectropaintOSX
PROJEXT    = saver
PROJVERS   = 0.4.0
BUNDLEID   = "org.lloydslounge.electropaint"

# extra files to include in the package

SUPPORT_FILES = README.txt gpl.txt

# code signing information

include sign.mk

# build and packaging tools

XCODEBUILD = /usr/bin/xcodebuild
XCRUN      = /usr/bin/xcrun
ALTOOL     = $(XCRUN) altool
STAPLER    = $(XCRUN) stapler
HDIUTIL    = /usr/bin/hdiutil
CODESIGN   = /usr/bin/codesign

# code sign arguments

CODESIGN_ARGS = --force \
                --verify \
                --verbose \
                --timestamp \
                --options runtime \
                --sign $(SIGNID)

# build results directory

BUILD_RESULTS_DIR = build/Development/$(PROJNAME).$(PROJEXT)

# build the screensaver

all:
	$(XCODEBUILD) -project $(PROJNAME).xcodeproj -configuration Development

install: all
	cp -R $(BUILD_RESULTS_DIR) ~/Library/Screen\ Savers/
	$(CODESIGN) --force --sign - ~/Library/Screen\ Savers/$(PROJNAME).$(PROJEXT)

sign: all
	$(CODESIGN) $(CODESIGN_ARGS) $(BUILD_RESULTS_DIR)
	if [ -d $(BUILD_RESULTS_DIR)/Contents/Frameworks/ ] ; then \
        $(CODESIGN) $(CODESIGN_ARGS) \
                $(BUILD_RESULTS_DIR)/Contents/Frameworks/* ; \
    fi

# sign the disk image

sign_dmg: dmg
	$(CODESIGN) $(CODESIGN_ARGS) $(PROJNAME)-$(PROJVERS).dmg

dmg: clean all sign
	/bin/mkdir $(PROJNAME)-$(PROJVERS)
	/bin/mv $(BUILD_RESULTS_DIR) $(PROJNAME)-$(PROJVERS)
	/bin/cp $(SUPPORT_FILES) $(PROJNAME)-$(PROJVERS)
	$(HDIUTIL) create -srcfolder $(PROJNAME)-$(PROJVERS) \
                      -format UDBZ $(PROJNAME)-$(PROJVERS).dmg

# notarize the signed disk image

notarize: sign_dmg
	$(ALTOOL) --notarize-app \
              --primary-bundle-id $(BUNDLEID) \
              --username $(USERID) \
              --file $(PROJNAME)-$(PROJVERS).dmg

# staple the ticket to the dmg

staple:
	$(STAPLER) staple $(PROJNAME)-$(PROJVERS).dmg
	$(STAPLER) validate $(PROJNAME)-$(PROJVERS).dmg

clean:
	/bin/rm -rf ./build $(PROJNAME)-$(PROJVERS) $(PROJNAME)-$(PROJVERS).dmg
	$(XCODEBUILD) -project $(PROJNAME).xcodeproj -alltargets clean

