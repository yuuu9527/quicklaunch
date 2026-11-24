DEBUG = 0
FINALPACKAGE = 1

# Share the SDK and deployment targets with the PreferenceBundle.
include YuQuickLaunchBuild.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YuQuickLaunch
YuQuickLaunch_FILES = $(wildcard Hooks/*.xm Sources/*.m)
YuQuickLaunch_CFLAGS = -fobjc-arc -I./Headers -I./Sources
YuQuickLaunch_FRAMEWORKS = UIKit Foundation CoreFoundation QuartzCore
YuQuickLaunch_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += YuQuickLaunchPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk
