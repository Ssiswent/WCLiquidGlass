ARCHS = arm64
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = rootless
WCLIQUIDGLASS_AUTO_BUMP ?= 1

ifeq ($(WCLIQUIDGLASS_AUTO_BUMP),1)
WCLIQUIDGLASS_VERSION := $(shell sh scripts/bump-version.sh --next)
else
WCLIQUIDGLASS_VERSION := $(shell sed -n 's/^Version:[[:space:]]*//p' control)
endif
PACKAGE_VERSION := $(WCLIQUIDGLASS_VERSION)
WCLIQUIDGLASS_UPLOAD_URL ?= http://192.168.1.145:8088
WCLIQUIDGLASS_UPLOAD_PATH ?= /Plugins/

INSTALL_TARGET_PROCESSES = WeChat

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WCLiquidGlass

WCLiquidGlass_FILES = Tweak.xm WCLiquidGlassMenu.m WCLiquidGlassPreferences.m WCLiquidGlassCrashLogger.m WCLiquidGlassChatTime.m WCLiquidGlass.m WCLiquidGlassIconAssets.c
WCLiquidGlass_CFLAGS = -fobjc-arc -DWCLIQUIDGLASS_VERSION=\"$(WCLIQUIDGLASS_VERSION)\" -DPLCRASHREPORTER_PREFIX=WCLG_ -I$(THEOS_PROJECT_DIR)/Vendor/PLCrashReporter/Headers
WCLiquidGlass_FRAMEWORKS = Foundation UIKit QuartzCore
WCLiquidGlass_LDFLAGS = $(THEOS_PROJECT_DIR)/Vendor/PLCrashReporter/CrashReporter

include $(THEOS_MAKE_PATH)/tweak.mk

before-all::
	@if [ "$(WCLIQUIDGLASS_AUTO_BUMP)" = "1" ]; then sh scripts/bump-version.sh --apply; fi

after-package::
	@WCLIQUIDGLASS_UPLOAD_URL="$(WCLIQUIDGLASS_UPLOAD_URL)" WCLIQUIDGLASS_UPLOAD_PATH="$(WCLIQUIDGLASS_UPLOAD_PATH)" sh scripts/upload-package.sh "$(__THEOS_LAST_PACKAGE_FILENAME)"
