ARCHS = arm64
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = rootless

INSTALL_TARGET_PROCESSES = WeChat

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WCLiquidGlass

WCLiquidGlass_FILES = Tweak.xm WCLiquidGlassMenu.m WCLiquidGlassPreferences.m WCLiquidGlassCrashLogger.m WCLiquidGlass.m WCLiquidGlassIconAssets.c
WCLiquidGlass_CFLAGS = -fobjc-arc -DWCLIQUIDGLASS_VERSION=\"$(shell sed -n 's/^Version: //p' control)\" -DPLCRASHREPORTER_PREFIX=WCLG_ -I$(THEOS_PROJECT_DIR)/Vendor/PLCrashReporter/Headers
WCLiquidGlass_FRAMEWORKS = Foundation UIKit QuartzCore
WCLiquidGlass_LDFLAGS = $(THEOS_PROJECT_DIR)/Vendor/PLCrashReporter/CrashReporter

include $(THEOS_MAKE_PATH)/tweak.mk
