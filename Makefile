# Theos build for VideoStarTool (hson edition)
# Build:  make package   (or `make` and inject .theos/obj/VideoStarTool.dylib into the IPA)
TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
DEBUG = 0
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VideoStarTool
VideoStarTool_FILES = Tweak.m
VideoStarTool_FRAMEWORKS = UIKit Foundation AVFoundation CoreImage CoreMedia QuartzCore
VideoStarTool_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function

include $(THEOS_MAKE_PATH)/tweak.mk
