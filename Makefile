DIST := dist
VERSION ?= $(shell sed -n 's/^version = "\(.*\)"/\1/p' cli/Cargo.toml | head -1)
DARWIN_TARGET := aarch64-apple-darwin
LINUX_TARGETS := aarch64-unknown-linux-musl x86_64-unknown-linux-musl

.PHONY: release app cli-darwin cli-linux clean

release: cli-darwin cli-linux app
	@echo "Release artifacts in $(DIST)/"

cli-darwin:
	cargo build --release --manifest-path cli/Cargo.toml --target $(DARWIN_TARGET)
	mkdir -p $(DIST)
	tar -czf $(DIST)/miaou-$(VERSION)-$(DARWIN_TARGET).tar.gz \
		-C cli/target/$(DARWIN_TARGET)/release miaou

cli-linux:
	@command -v zig >/dev/null 2>&1 || { \
		echo "error: zig not found (needed by cargo-zigbuild)."; \
		echo "Install it first: brew install zig && cargo install cargo-zigbuild"; exit 1; }
	@for t in $(LINUX_TARGETS); do \
		echo "==> $$t"; \
		rustup target add $$t >/dev/null; \
		cargo zigbuild --release --manifest-path cli/Cargo.toml --target $$t || exit 1; \
		tar -czf $(DIST)/miaou-$(VERSION)-$$t.tar.gz -C cli/target/$$t/release miaou || exit 1; \
	done

app:
	make -C app app
	mkdir -p $(DIST)
	rm -rf $(DIST)/Miaou.app
	cp -R app/Miaou.app $(DIST)/
	ditto -c -k --keepParent app/Miaou.app $(DIST)/Miaou-$(VERSION)-macos-arm64.zip

clean:
	rm -rf $(DIST)
	make -C app clean
