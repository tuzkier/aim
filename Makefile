.PHONY: dev test contracts lint web-build ios-parse ios-build ios-test verify

IOS_PROJECT ?= apps/ios/AimApp.xcodeproj
IOS_SCHEME ?= AimApp
IOS_DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro
IOS_DERIVED_DATA ?= /tmp/aim-derived-data
COMPOSE_ENV_FILE := $(if $(wildcard .env),--env-file .env,)
# 本地带上 local profile 才会起网关；生产用系统 nginx。
COMPOSE := docker compose $(COMPOSE_ENV_FILE) --profile local -f infrastructure/compose/compose.yaml

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

# 对话面的 web 产物。由网关提供，和 /api/ /eve/ 同源——事件流是长连接，
# 只有同源的真实网络请求 fetch 才能边收边解。本地由 compose 的 gateway 挂载
# dist 目录，生产由 deploy.sh 上传到 /opt/aim/web。产物不进版本库。
web-build:
	npm ci --prefix apps/agent-web
	npm run build --prefix apps/agent-web

ios-parse:
	swiftc -parse $$(find apps/ios/AimApp -type f -name '*.swift' | sort)

ios-build:
	xcodebuild -project $(IOS_PROJECT) -scheme $(IOS_SCHEME) -sdk iphonesimulator -configuration Debug -derivedDataPath $(IOS_DERIVED_DATA) CODE_SIGNING_ALLOWED=NO build

ios-test:
	xcodebuild -project $(IOS_PROJECT) -scheme $(IOS_SCHEME) -configuration Debug -destination '$(IOS_DESTINATION)' -derivedDataPath $(IOS_DERIVED_DATA) CODE_SIGNING_ALLOWED=NO test

verify: lint test contracts
	python3 scripts/verify_repo.py
