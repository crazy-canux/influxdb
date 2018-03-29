PREFIX := /usr/local
VERSION := $(shell git describe --exact-match --tags 2>/dev/null)
BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
COMMIT := $(shell git rev-parse --short HEAD)
GOFILES ?= $(shell git ls-files '*.go')
GOFMT ?= $(shell gofmt -l $(GOFILES))

ifdef GOBIN
PATH := $(GOBIN):$(PATH)
else
PATH := $(subst :,/bin:,$(GOPATH))/bin:$(PATH)
endif

INFLUXDB := influxdb$(shell go tool dist env | grep -q 'GOOS=.windows.' && echo .exe)

LDFLAGS := $(LDFLAGS) -X main.commit=$(COMMIT) -X main.branch=$(BRANCH)
ifdef VERSION
	LDFLAGS += -X main.version=$(VERSION)
endif

all:
	$(MAKE) fmtcheck
	$(MAKE) deps
	$(MAKE) influxdb

ci-test:
	$(MAKE) deps
	$(MAKE) fmtcheck
	$(MAKE) vet
	$(MAKE) test

deps:
	go get -u github.com/golang/lint/golint
	go get github.com/sparrc/gdm
	gdm restore

influxdb:
	go build -i -o $(INFLUXDB) -ldflags "$(LDFLAGS)" ./cmd/influx/main.go

go-install:
	go install -ldflags "-w -s $(LDFLAGS)" ./cmd/influxd

install: influxdb
	mkdir -p $(DESTDIR)$(PREFIX)/bin/
	cp $(INFLUXDB) $(DESTDIR)$(PREFIX)/bin/

test:
	go test -short ./...

fmt:
	@gofmt -w $(GOFILES)

fmtcheck:
	@echo '[INFO] running gofmt to identify incorrectly formatted code...'
	@if [ ! -z $(GOFMT) ]; then \
		echo "[ERROR] gofmt has found errors in the following files:"  ; \
		echo "$(GOFMT)" ; \
		echo "" ;\
		echo "Run make fmt to fix them." ; \
		exit 1 ;\
	fi
	@echo '[INFO] done.'

lint:
	golint ./...

test-windows:
	go test ./plugins/inputs/ping/...
	go test ./plugins/inputs/win_perf_counters/...
	go test ./plugins/inputs/win_services/...
	go test ./plugins/inputs/procstat/...

# vet runs the Go source code static analysis tool `vet` to find
# any common errors.
vet:
	@echo 'go vet $$(go list ./...)'
	@go vet $$(go list ./...) ; if [ $$? -eq 1 ]; then \
		echo ""; \
		echo "go vet has found suspicious constructs. Please remediate any reported errors"; \
		echo "to fix them before submitting code for review."; \
		exit 1; \
	fi

test-all: vet
	go test ./...

package:
	./build.py --package --platform=linux --arch=amd64 --clean --no-get --version=1.6.0 --iteration=1

win-package:
	./build.py --package --platform=windows --arch=amd64 --clean --no-get --version=1.6.0 --iteration=1

clean:
	rm -f influxdb
	rm -f influxdb.exe

docker-image:
	./build.py --package --platform=linux --arch=amd64
	cp build/influxdb*$(COMMIT)*.deb .
	docker build -f scripts/dev.docker --build-arg "package=influxdb*$(COMMIT)*.deb" -t "influxdb-dev:$(COMMIT)" .

.PHONY: deps influxdb install test test-windows lint vet test-all package clean docker-image fmtcheck
