mkfat32: main.go
	GO111MODULE=on go build -mod=vendor -o mkfat32 .

install: mkfat32
	install -D -m 755 -t $(DESTDIR)/bin mkfat32

.PHONY: install
