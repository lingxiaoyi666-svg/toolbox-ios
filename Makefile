TARGET = iphone:clang:latest:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BiliPure
BiliPure_FILES = Tweak.xm HGCore.m HGSettings.m
BiliPure_CFLAGS = -fobjc-arc
BiliPure_FRAMEWORKS = UIKit Foundation
BiliPure_LDFLAGS = -undefined dynamic_lookup -install_name @executable_path/Frameworks/BiliPure.dylib

include $(THEOS_MAKE_PATH)/tweak.mk
