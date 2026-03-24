# Variables
BINARY_NAME=whatsmail_bin
IDENTIFIER=local.whatsmail
DIST_DIR=dist
SOURCE=whatsmail_bridge.sh

.PHONY: all build clean

# Default action when you just type 'make'
all: build

build:
	@echo "Compiling $(SOURCE)..."
	@mkdir -p $(DIST_DIR)
	@shc -f $(SOURCE) -o $(DIST_DIR)/$(BINARY_NAME)
	@echo "Signing $(BINARY_NAME)..."
	@codesign --force --identifier $(IDENTIFIER) -s - $(DIST_DIR)/$(BINARY_NAME) 2>/dev/null
	@rm -f $(SOURCE).x.c
	@echo "Binary created at $(DIST_DIR)/$(BINARY_NAME)!"

clean:
	@echo "Cleaning up..."
	@rm -rf $(DIST_DIR)
	@rm -f $(SOURCE).x.c
