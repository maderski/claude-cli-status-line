.PHONY: test install

test:
	@command -v bats >/dev/null 2>&1 || { echo "bats not found — install with: brew install bats-core"; exit 1; }
	bats tests/statusline.bats

install:
	./setup.sh
