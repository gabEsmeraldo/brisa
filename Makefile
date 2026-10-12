.PHONY: app dmg run clean

app:
	./scripts/package.sh

dmg:
	./scripts/package.sh dmg

run: app
	open build/Brisa.app

clean:
	rm -rf .build build
