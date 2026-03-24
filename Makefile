# Variables
BINARY_NAME=whatsmail_bin
IDENTIFIER=local.whatsmail
DIST_DIR=dist
MAIN_SOURCE=whatsmail_bridge.sh
WORKER_SOURCE=unread_messages.sh

.PHONY: all build clean

# Default action when you just type 'make'
all: build

build: clean
	@mkdir -p $(DIST_DIR)
	@echo "Fusing scripts..."
	@cp $(MAIN_SOURCE) $(DIST_DIR)/temp_build.sh
	@echo "\nfetch_unread_logic() {" >> $(DIST_DIR)/temp_build.sh
	@cat $(WORKER_SOURCE) >> $(DIST_DIR)/temp_build.sh
	@echo "\n}" >> $(DIST_DIR)/temp_build.sh
	@echo "Compiling..."
	@shc -r -f $(DIST_DIR)/temp_build.sh -o $(DIST_DIR)/$(BINARY_NAME)
	@echo "Signing..."
	@codesign --force --identifier $(IDENTIFIER) -s - $(DIST_DIR)/$(BINARY_NAME) 2>/dev/null
	@rm -f $(DIST_DIR)/temp_build.sh $(DIST_DIR)/temp_build.sh.x.c
	@echo "Baked binary created in $(DIST_DIR)/$(BINARY_NAME)!"

clean:
	@rm -rf $(DIST_DIR)
