DEBUG ?= 0
FINALPACKAGE ?= 1

# Linux 版 clang 编译出的 arm64e 目标文件 ABI 与 iOS 不兼容（ld 会警告
# "incompatible arm64e ABI compiler"），arm64e 切片在设备上不可靠，
# 因此统一产物为 arm64；arm64 代码可在 arm64e 设备上正常加载。
ifneq ($(filter rootless roothide,$(THEOS_PACKAGE_SCHEME)),)
ARCHS = arm64
TARGET = iphone:clang:16.5:15.0
else
ARCHS = arm64
TARGET = iphone:clang:16.5:14.0
endif
