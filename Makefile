.PHONY: dev test contracts lint ios-parse ios-build ios-test verify

IOS_PROJECT ?= apps/ios/AimApp.xcodeproj
IOS_SCHEME ?= AimApp
IOS_DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro
IOS_DERIVED_DATA ?= /tmp/aim-derived-data

dev:
	docker compose -f infrastructure/compose/compose.yaml up --build

test:
	$(MAKE) -C services/api test
	$(MAKE) -C services/agent test

contracts:
	$(MAKE) -C services/api contracts

lint:
	$(MAKE) -C services/api lint
	$(MAKE) -C services/agent lint

ios-parse:
	swiftc -parse $$(find apps/ios/AimApp -type f -name '*.swift' | sort)

ios-build:
	xcodebuild -project $(IOS_PROJECT) -scheme $(IOS_SCHEME) -sdk iphonesimulator -configuration Debug -derivedDataPath $(IOS_DERIVED_DATA) CODE_SIGNING_ALLOWED=NO build

ios-test:
	xcodebuild -project $(IOS_PROJECT) -scheme $(IOS_SCHEME) -configuration Debug -destination '$(IOS_DESTINATION)' -derivedDataPath $(IOS_DERIVED_DATA) CODE_SIGNING_ALLOWED=NO test

verify: lint test contracts
	python3 scripts/verify_repo.py
