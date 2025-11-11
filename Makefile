# SGX SDK Configuration
SGX_SDK ?= /opt/intel/sgxsdk
SGX_MODE ?= HW
SGX_ARCH ?= x64
SGX_DEBUG ?= 1

# Directories
APP_DIR := App
ENCLAVE_DIR := Enclave
BUILD_DIR := Build
BIN_DIR := Bin
INCLUDE_DIR := Include
KEYS_DIR := Keys

# Tools
CC := gcc
CXX := g++
SGX_EDGER8R := $(SGX_SDK)/bin/x64/sgx_edger8r
SGX_SIGN := $(SGX_SDK)/bin/x64/sgx_sign

# SGX Library Paths
SGX_LIBRARY_PATH := $(SGX_SDK)/lib64
TRUST_LIB := $(SGX_LIBRARY_PATH)/libsgx_trts.a
SERVICE_LIB := $(SGX_LIBRARY_PATH)/libsgx_tservice.a
CRYPTO_LIB := $(SGX_LIBRARY_PATH)/libsgx_tcrypto.a

# Compiler Flags
ifeq ($(SGX_DEBUG), 1)
	SGX_COMMON_CFLAGS := -O0 -g
else
	SGX_COMMON_CFLAGS := -O2
endif

# Enclave Flags
ENCLAVE_CFLAGS := $(SGX_COMMON_CFLAGS) -nostdinc -fvisibility=hidden -fpie -fstack-protector-strong \
	-fno-builtin -fno-builtin-printf -I$(SGX_SDK)/include -I$(SGX_SDK)/include/tlibc \
	-I$(SGX_SDK)/include/stlport -I$(INCLUDE_DIR)

ENCLAVE_LDFLAGS := -Wl,--no-undefined -nostdlib -nodefaultlibs -nostartfiles \
	-L$(SGX_LIBRARY_PATH) \
	-Wl,--whole-archive -lsgx_trts -Wl,--no-whole-archive \
	-Wl,--start-group -lsgx_tstdc -lsgx_tcrypto -lsgx_tservice -Wl,--end-group \
	-Wl,-Bstatic -Wl,-Bsymbolic -Wl,--no-undefined \
	-Wl,-pie,-eenclave_entry -Wl,--export-dynamic \
	-Wl,--defsym,__ImageBase=0 \
	-Wl,--version-script=$(ENCLAVE_DIR)/Enclave.lds

# App Flags
APP_CFLAGS := $(SGX_COMMON_CFLAGS) -fPIC -Wno-attributes -I$(SGX_SDK)/include -I$(INCLUDE_DIR)

ifeq ($(SGX_MODE), HW)
	URTS_LIB := sgx_urts
else
	URTS_LIB := sgx_urts_sim
endif

APP_LDFLAGS := -L$(SGX_LIBRARY_PATH) -l$(URTS_LIB) -lpthread

# Files
EDL_FILE := $(ENCLAVE_DIR)/Enclave.edl
ENCLAVE_CONFIG := $(ENCLAVE_DIR)/Enclave.config.xml
ENCLAVE_LDS := $(ENCLAVE_DIR)/Enclave.lds

# Generated Files
ENCLAVE_T_C := $(BUILD_DIR)/Enclave_t.c
ENCLAVE_T_H := $(INCLUDE_DIR)/Enclave_t.h
ENCLAVE_T_O := $(BUILD_DIR)/Enclave_t.o

ENCLAVE_U_C := $(BUILD_DIR)/Enclave_u.c
ENCLAVE_U_H := $(INCLUDE_DIR)/Enclave_u.h
ENCLAVE_U_O := $(BUILD_DIR)/Enclave_u.o

# Enclave Source Files
ENCLAVE_CPP := $(ENCLAVE_DIR)/Enclave.cpp
ENCLAVE_O := $(BUILD_DIR)/Enclave.o

# Output Files
ENCLAVE_SO := $(BIN_DIR)/enclave.so
SIGNED_ENCLAVE := $(BIN_DIR)/enclave.signed.so
SIGNING_KEY := $(KEYS_DIR)/enclave_private.pem

# Targets
.PHONY: all clean directories

all: directories $(BIN_DIR)/bank_server $(BIN_DIR)/bank_client $(SIGNED_ENCLAVE)

directories:
	@mkdir -p $(BUILD_DIR) $(BIN_DIR) $(INCLUDE_DIR) $(KEYS_DIR)

# Generate signing key
$(SIGNING_KEY): | $(KEYS_DIR)
	@echo "Generating enclave signing key..."
	@openssl genrsa -out $@ -3 3072

# Generate EDL bridge files
$(ENCLAVE_T_C) $(ENCLAVE_T_H): $(EDL_FILE) | $(BUILD_DIR) $(INCLUDE_DIR)
	@echo "Generating trusted bridge files..."
	@cd $(ENCLAVE_DIR) && $(SGX_EDGER8R) --trusted $(notdir $(EDL_FILE)) \
		--search-path $(SGX_SDK)/include \
		--search-path . \
		--trusted-dir ../$(BUILD_DIR)
	@mv $(BUILD_DIR)/Enclave_t.h $(INCLUDE_DIR)/

$(ENCLAVE_U_C) $(ENCLAVE_U_H): $(EDL_FILE) | $(BUILD_DIR) $(INCLUDE_DIR)
	@echo "Generating untrusted bridge files..."
	@cd $(ENCLAVE_DIR) && $(SGX_EDGER8R) --untrusted $(notdir $(EDL_FILE)) \
		--search-path $(SGX_SDK)/include \
		--search-path . \
		--untrusted-dir ../$(BUILD_DIR)
	@mv $(BUILD_DIR)/Enclave_u.h $(INCLUDE_DIR)/

# Compile trusted bridge
$(ENCLAVE_T_O): $(ENCLAVE_T_C) $(ENCLAVE_T_H)
	@echo "Compiling trusted bridge..."
	$(CC) $(ENCLAVE_CFLAGS) -c $< -o $@

# Compile untrusted bridge
$(ENCLAVE_U_O): $(ENCLAVE_U_C) $(ENCLAVE_U_H)
	@echo "Compiling untrusted bridge..."
	$(CC) $(APP_CFLAGS) -c $< -o $@

# Compile enclave
$(ENCLAVE_O): $(ENCLAVE_CPP) $(ENCLAVE_T_H)
	@echo "Compiling enclave..."
	$(CXX) $(ENCLAVE_CFLAGS) -c $< -o $@

# Link enclave
$(ENCLAVE_SO): $(ENCLAVE_O) $(ENCLAVE_T_O) | $(BIN_DIR)
	@echo "Linking enclave..."
	$(CXX) $^ -o $@ $(ENCLAVE_LDFLAGS)

# Sign enclave
$(SIGNED_ENCLAVE): $(ENCLAVE_SO) $(SIGNING_KEY) $(ENCLAVE_CONFIG)
	@echo "Signing enclave..."
	$(SGX_SIGN) sign -key $(SIGNING_KEY) -enclave $(ENCLAVE_SO) -out $@ -config $(ENCLAVE_CONFIG)
	@echo "Enclave signed successfully: $@"

# Build server
$(BIN_DIR)/bank_server: $(APP_DIR)/server.cpp $(ENCLAVE_U_O) $(ENCLAVE_U_H) | $(BIN_DIR)
	@echo "Building server..."
	$(CXX) $< $(ENCLAVE_U_O) -o $@ $(APP_CFLAGS) $(APP_LDFLAGS)

# Build client
$(BIN_DIR)/bank_client: $(APP_DIR)/client.cpp | $(BIN_DIR)
	@echo "Building client..."
	$(CXX) $< -o $@ -I$(INCLUDE_DIR) -Wall

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR) $(BIN_DIR) $(INCLUDE_DIR)/Enclave_t.h $(INCLUDE_DIR)/Enclave_u.h
	@rm -f enclave_state.bin old_state_*.bin .enclave_pid
	@echo "Clean complete"

clean-all: clean
	@echo "Cleaning generated keys..."
	@rm -rf $(KEYS_DIR)
	@echo "Full clean complete"

help:
	@echo "SGX Replay Attack PoC - Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  all        - Build everything (default)"
	@echo "  clean      - Remove build artifacts"
	@echo "  clean-all  - Remove build artifacts and keys"
	@echo "  help       - Show this help message"
	@echo ""
	@echo "Usage:"
	@echo "  make              # Build all"
	@echo "  make clean        # Clean build"
	@echo "  make SGX_MODE=SIM # Build in simulation mode"
