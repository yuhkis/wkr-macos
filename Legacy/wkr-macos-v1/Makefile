ifeq ($(origin DEVELOPER_DIR), undefined)
ifneq ($(wildcard /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild),)
export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
endif
endif

.PHONY: test app
test:
	swift test
app:
	./Scripts/build-app.sh
