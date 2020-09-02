GOPATH := $(shell go env GOPATH 2> /dev/null)
GOBIN := $(GOPATH)/bin
COMMIT := $(shell scripts/git/commit.sh)
# LAST_RELEASE_TAG determines the version of the DSS and is baked into
# the executable using linker flags. We gracefully ignore any tag that
# does not satisfy the naming pattern v*, thus supporting interleaving release
# and ordinary tags.
LAST_RELEASE_TAG := $(shell git describe --tags --abbrev=0 --match='v*' 2> /dev/null | grep -E 'v[0-9]+\.[0-9]+\.[0-9]+')
LAST_RELEASE_TAG := $(or $(LAST_RELEASE_TAG), v0.0.0)

GENERATOR_TAG := generator:$(LAST_RELEASE_TAG)

# Build and version information is baked into the executable itself.
BUILD_LDFLAGS := -X github.com/interuss/dss/pkg/build.time=$(shell date -u '+%Y-%m-%d.%H:%M:%S') -X github.com/interuss/dss/pkg/build.commit=$(COMMIT) -X github.com/interuss/dss/pkg/build.host=$(shell hostname)
VERSION_LDFLAGS := -X github.com/interuss/dss/pkg/version.tag=$(LAST_RELEASE_TAG) -X github.com/interuss/dss/pkg/version.commit=$(COMMIT)
LDFLAGS := $(BUILD_LDFLAGS) $(VERSION_LDFLAGS)

ifeq ($(OS),Windows_NT)
  detected_OS := Windows
else
  detected_OS := $(shell uname -s)
endif

.PHONY: interuss
interuss:
	go install -ldflags "$(LDFLAGS)" ./cmds/...

go-mod-download: go.mod
	go mod download

go.mod:
	go mod tidy

.PHONY: format
format:
	clang-format -style=file -i pkg/api/v1/ridpb/rid.proto
	clang-format -style=file -i pkg/api/v1/scdpb/scd.proto
	clang-format -style=file -i pkg/api/v1/auxpb/aux_service.proto

.PHONY: lint
lint:
	docker run --rm -v $(CURDIR):/dss -w /dss golangci/golangci-lint:v1.26.0 golangci-lint run --timeout 5m -v -E gofmt,bodyclose,rowserrcheck,misspell,golint -D staticcheck,vet
	docker run --rm -v $(CURDIR):/dss -w /dss golangci/golangci-lint:v1.26.0 golangci-lint run --timeout 5m -v --disable-all  -E staticcheck --skip-dirs '^cmds/http-gateway,^pkg/logging'
	find . -name '*.sh' | xargs docker run --rm -v $(CURDIR):/dss -w /dss koalaman/shellcheck

pkg/api/v1/ridpb/rid.pb.go: pkg/api/v1/ridpb/rid.proto generator
	docker run -v$(CURDIR):/src:delegated -w /src $(GENERATOR_TAG) protoc \
		-I/usr/include \
		-I/src \
		-I/go/src \
		-I/go/pkg/mod/github.com/grpc-ecosystem/grpc-gateway@v1.14.3/third_party/googleapis \
		--go_out=plugins=grpc:. $<

pkg/api/v1/ridpb/rid.pb.gw.go: pkg/api/v1/ridpb/rid.proto pkg/api/v1/ridpb/rid.pb.go generator
	docker run -v$(CURDIR):/src:delegated -w /src $(GENERATOR_TAG) protoc \
		-I/usr/include \
		-I. \
		-I/go/src \
		-I/go/pkg/mod/github.com/grpc-ecosystem/grpc-gateway@v1.14.3/third_party/googleapis \
		--grpc-gateway_out=logtostderr=true,allow_delete_body=true:. $<

pkg/api/v1/ridpb/rid.proto: generator
	docker run -v$(CURDIR):/src:delegated -w /src $(GENERATOR_TAG) openapi2proto \
		-spec interfaces/uastech/standards/remoteid/augmented.yaml -annotate \
		-tag dss \
		-indent 2 \
		-package ridpb > $@

pkg/api/v1/auxpb/aux_service.pb.go: pkg/api/v1/auxpb/aux_service.proto generator
	docker run -v$(CURDIR):/src:delegated -w /src $(GENERATOR_TAG) protoc \
		-I/usr/include \
		-I. \
		-I/go/src \
		-I/go/pkg/mod/github.com/grpc-ecosystem/grpc-gateway@v1.14.3/third_party/googleapis \
		--go_out=plugins=grpc:. $<

pkg/api/v1/auxpb/aux_service.pb.gw.go: pkg/api/v1/auxpb/aux_service.proto pkg/api/v1/auxpb/aux_service.pb.go generator
	docker run -v$(CURDIR):/src:delegated -w /src $(GENERATOR_TAG) protoc \
		-I/usr/include \
		-I. \
		-I/go/src \
		-I/go/pkg/mod/github.com/grpc-ecosystem/grpc-gateway@v1.14.3/third_party/googleapis \
		--grpc-gateway_out=logtostderr=true,allow_delete_body=true:. $<

pkg/api/v1/scdpb/scd.pb.go: pkg/api/v1/scdpb/scd.proto generator
	docker run -v$(CURDIR):/src:delegated -w /src $(GENERATOR_TAG) protoc \
		-I/usr/include \
		-I. \
		-I/go/src \
		-I/go/pkg/mod/github.com/grpc-ecosystem/grpc-gateway@v1.14.3/third_party/googleapis \
		--go_out=plugins=grpc:. $<

pkg/api/v1/scdpb/scd.pb.gw.go: pkg/api/v1/scdpb/scd.proto pkg/api/v1/scdpb/scd.pb.go generator
	docker run -v$(CURDIR):/src:delegated -w /src $(GENERATOR_TAG) protoc \
		-I/usr/include \
		-I. \
		-I/go/src \
		-I/go/pkg/mod/github.com/grpc-ecosystem/grpc-gateway@v1.14.3/third_party/googleapis \
		--grpc-gateway_out=logtostderr=true,allow_delete_body=true:. $<

interfaces/scd_adjusted.yaml: interfaces/astm-utm/Protocol/utm.yaml
	./interfaces/adjuster/adjust_openapi_yaml.sh ./interfaces/astm-utm/Protocol/utm.yaml ./interfaces/scd_adjusted.yaml

pkg/api/v1/scdpb/scd.proto: interfaces/scd_adjusted.yaml generator
	docker run -v$(CURDIR):/src:delegated -w /src $(GENERATOR_TAG) openapi2proto \
		-spec interfaces/scd_adjusted.yaml -annotate \
		-tag dss \
		-indent 2 \
		-package scdpb > $@

generator:
	docker build --rm -t $(GENERATOR_TAG) build/generator

.PHONY: protos
protos: pkg/api/v1/auxpb/aux_service.pb.gw.go pkg/api/v1/ridpb/rid.pb.gw.go pkg/api/v1/scdpb/scd.pb.gw.go

.PHONY: install-staticcheck
install-staticcheck:
	go get honnef.co/go/tools/cmd/staticcheck

.PHONY: staticcheck
staticcheck: install-staticcheck
	staticcheck -go 1.12 ./...

.PHONY: test
test:
	go test -ldflags "$(LDFLAGS)" -count=1 -v ./pkg/... ./cmds/...

.PHONY: test-cockroach
test-cockroach: cleanup-test-cockroach
	@docker run -d --name dss-crdb-for-testing -p 26257:26257 -p 8080:8080  cockroachdb/cockroach:v20.1.1 start --insecure > /dev/null
	go run ./cmds/db-manager/main.go --schemas_dir ./build/deploy/db_schemas/defaultdb --db_version 3.1.0 --cockroach_host localhost
	go test -count=1 -v ./pkg/rid/store/cockroach -store-uri "postgresql://root@localhost:26257?sslmode=disable"
	go test -count=1 -v ./pkg/scd/store/cockroach -store-uri "postgresql://root@localhost:26257?sslmode=disable"
	go test -count=1 -v ./pkg/rid/application -store-uri "postgresql://root@localhost:26257?sslmode=disable"
	@docker stop dss-crdb-for-testing > /dev/null
	@docker rm dss-crdb-for-testing > /dev/null

.PHONY: cleanup-test-cockroach
cleanup-test-cockroach:
	@docker stop dss-crdb-for-testing > /dev/null 2>&1 || true
	@docker rm dss-crdb-for-testing > /dev/null 2>&1 || true

.PHONY: test-e2e
test-e2e: start-locally
	true > "$(CURDIR)/e2e_test_result"
	true > "$(CURDIR)/grpc-backend-for-testing.log"
	true > "$(CURDIR)/http-gateway-for-testing.log"
	sleep 10 # This provides time for the system to come up.  TODO: Replace when health status is reliably available
	build/dev/run_locally.sh run --rm -v "$(CURDIR)/e2e_test_result:/app/test_result" local-dss-e2e-tests . --junitxml=/app/test_result --dss-endpoint http://local-dss-http-gateway:8082 --rid-auth "DummyOAuth(http://local-dss-dummy-oauth:8085/token,sub=fake_uss)" --scd-auth1 "DummyOAuth(http://local-dss-dummy-oauth:8085/token,sub=fake_uss)" --scd-auth2 "DummyOAuth(http://local-dss-dummy-oauth:8085/token,sub=fake_uss2)"
	build/dev/run_locally.sh logs -t --no-color local-dss-grpc-backend > "$(CURDIR)/grpc-backend-for-testing.log"
	build/dev/run_locally.sh logs -t --no-color local-dss-http-gateway > "$(CURDIR)/http-gateway-for-testing.log"

release: VERSION = v$(MAJOR).$(MINOR).$(PATCH)

release:
		scripts/release.sh $(VERSION)

start-locally:
	build/dev/run_locally.sh build
	build/dev/run_locally.sh up --detach
	echo "Local DSS instance started; run 'make watch-locally' to view current status"

stop-locally:
	build/dev/run_locally.sh down

watch-locally:
	build/dev/run_locally.sh logs -t -f
