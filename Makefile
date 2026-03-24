# Variables
BINARY_NAME=whatsmail_bin
IDENTIFIER=local.whatsmail
DIST_DIR=dist
MAIN_SOURCE=src/whatsmail_bridge.sh
WORKER_SOURCE=src/unread_messages.sh

PLIST_NAME=$(IDENTIFIER).plist
PLIST_DIR=$(HOME)/Library/LaunchAgents
PLIST_PATH=$(PLIST_DIR)/$(PLIST_NAME)

.PHONY: all build install run clean

# Default action when you just type 'make'
all: build

build: clean
	@mkdir -p $(DIST_DIR)
	@echo "Fusing scripts..."
	@printf '#!/bin/bash\nfetch_unread_logic() {\n' > $(DIST_DIR)/temp_build.sh
	@tail -n +2 $(WORKER_SOURCE) >> $(DIST_DIR)/temp_build.sh
	@printf '\n}\n' >> $(DIST_DIR)/temp_build.sh
	@tail -n +2 $(MAIN_SOURCE) >> $(DIST_DIR)/temp_build.sh
	@echo "Compiling..."
	@shc -r -f $(DIST_DIR)/temp_build.sh -o $(DIST_DIR)/$(BINARY_NAME)
	@echo "Signing..."
	@codesign --force --identifier $(IDENTIFIER) -s - $(DIST_DIR)/$(BINARY_NAME) 2>/dev/null
	@rm -f $(DIST_DIR)/temp_build.sh $(DIST_DIR)/temp_build.sh.x.c
	@echo "Baked binary created in $(DIST_DIR)/$(BINARY_NAME)!"

install:
	@launchctl unload $(PLIST_PATH) 2>/dev/null; true
	@launchctl bootstrap gui/$$(id -u) $(PLIST_PATH)

run:
	@(script -q /dev/null /usr/bin/log stream --predicate 'eventMessage contains "$(IDENTIFIER)"' --style compact --info --debug & sleep 1 && launchctl start $(IDENTIFIER)) | sed -l '/Bridge finished/q'

clean:
	@rm -rf $(DIST_DIR)
