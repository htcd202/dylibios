TARGET := iphone:clang:latest:14.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = KritikaModMenu

KritikaModMenu_FILES = Tweak.xm
KritikaModMenu_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
KritikaModMenu_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
