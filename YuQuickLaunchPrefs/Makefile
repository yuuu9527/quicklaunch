include ../YuQuickLaunchBuild.mk
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = YuQuickLaunchPrefs
YuQuickLaunchPrefs_FILES = $(wildcard *.m)
YuQuickLaunchPrefs_CFLAGS = -fobjc-arc -I../Sources -I../Headers
YuQuickLaunchPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
YuQuickLaunchPrefs_PRIVATE_FRAMEWORKS = Preferences
YuQuickLaunchPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
