.PHONY: build lint lint-fix test clean

build:
	shards build

lint:
	node check-syntax.js

lint-fix:
	npm run lint:fix

test:
	crystal spec

clean:
	rm -rf bin
	rm -f temp_*.js

all: lint build test