.PHONY: dev test contracts lint web-build ios-parse ios-build ios-test verify

IOS_PROJECT ?= apps/ios/AimApp.xcodeproj
IOS_SCHEME ?= AimApp
IOS_DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro
IOS_DERIVED_DATA ?= /tmp/aim-derived-data
COMPOSE_ENV_FILE := $(if $(wildcard .env),--env-file .env,)
COMPOSE := docker compose $(COMPOSE_ENV_FILE) -f infrastructure/compose/compose.yaml

dev:
	$(COMPOSE) up --build

test:
	$(MAKE) -C services/api test
	$(MAKE) -C services/agent test

contracts:
	$(MAKE) -C services/api contracts

lint:
	$(MAKE) -C services/api lint
	$(MAKE) -C services/agent lint

# 对话面的 web 产物打进 App bundle。产物本身不进版本库——它是构建结果，
# 而且每次构建文件名带新哈希，留在库里只会制造无意义的 diff。
AGENT_WEB_DIST := apps/agent-web/dist
AGENT_WEB_BUNDLE := apps/ios/AimApp/Resources/AgentWeb

web-build:
	npm ci --prefix apps/agent-web
	npm run build --prefix apps/agent-web
	rm -rf $(AGENT_WEB_BUNDLE)
	mkdir -p $(AGENT_WEB_BUNDLE)
	cp -R $(AGENT_WEB_DIST)/. $(AGENT_WEB_BUNDLE)/

ios-parse:
	swiftc -parse $$(find apps/ios/AimApp -type f -name '*.swift' | sort)

ios-build: web-build
	xcodebuild -project $(IOS_PROJECT) -scheme $(IOS_SCHEME) -sdk iphonesimulator -configuration Debug -derivedDataPath $(IOS_DERIVED_DATA) CODE_SIGNING_ALLOWED=NO build

ios-test: web-build
	xcodebuild -project $(IOS_PROJECT) -scheme $(IOS_SCHEME) -configuration Debug -destination '$(IOS_DESTINATION)' -derivedDataPath $(IOS_DERIVED_DATA) CODE_SIGNING_ALLOWED=NO test

verify: lint test contracts
	python3 scripts/verify_repo.py
