TARGET = iphone:clang:latest:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BiliPure
BiliPure_FILES = Tweak.xm HGCore.m
BiliPure_CFLAGS = -fobjc-arc
BiliPure_FRAMEWORKS = UIKit Foundation
BiliPure_LDFLAGS = -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk
