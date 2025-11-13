# SGX Replay Attack Demonstration

A proof-of-concept demonstrating replay attack vulnerabilities in Intel SGX enclaves due to lack of persistent monotonic counters.

## Overview

This project implements a secure banking service using Intel SGX to demonstrate:
- **Runtime Protection**: In-memory monotonic counters successfully detect replay attacks while the enclave is running
- **Restart Vulnerability**: Counter loss on restart allows malicious operators to roll back encrypted state

## Components

### Enclave (`Enclave/`)
- **Enclave.cpp**: Core banking logic with AES-GCM state sealing
- **Enclave.edl**: Interface definition (ECALLs/OCALLs)
- **Enclave.config.xml**: SGX configuration
- **Enclave.lds**: Linker script

### Application (`App/`)
- **server.cpp**: Unix socket server managing enclave lifecycle
- **client.cpp**: CLI client for banking operations

### Scripts (`Scripts/`)
- **demo.sh**: Interactive demonstration of the vulnerability

## Building

### Prerequisites
```bash
# Install Intel SGX SDK
# Download from: https://github.com/intel/linux-sgx

# Verify installation
ls /opt/intel/sgxsdk
```

### Compile
```bash
make
```

### Output
```
Bin/
├── bank_server          # Server executable
├── bank_client          # Client executable
├── enclave.so           # Unsigned enclave
└── enclave.signed.so    # Signed enclave
```

## Usage

### Start Server
```bash
./Bin/bank_server
```

### Client Commands
```bash
./Bin/bank_client set 100        # Set balance to $100
./Bin/bank_client deposit 50     # Deposit $50
./Bin/bank_client withdraw 25    # Withdraw $25
./Bin/bank_client query          # Check balance
./Bin/bank_client save           # Save encrypted state
./Bin/bank_client load file.bin  # Load encrypted state
```

## Demonstration

Run the automated attack demonstration:

```bash
./Scripts/demo.sh
```

### Attack Scenario

1. **Initial State**: John has $100 (counter = 1)
2. **Capture**: Operator copies encrypted state file
3. **Transaction**: John deposits $75 → Balance = $175 (counter = 2)
4. **Runtime Replay**: Attempt to load old state → **BLOCKED** ✓
5. **Service Restart**: Enclave destroyed, counter lost
6. **Malicious Rollback**: Operator replaces state file
7. **Service Start**: Counter resets to 0
8. **Successful Replay**: Old state loaded → **ACCEPTED** ✗
9. **Result**: John's $75 deposit stolen

## Vulnerability Analysis

### Root Cause
SGXv2 lacks **persistent monotonic counters**. The in-memory counter provides runtime protection but is lost on restart.

### Protection Status
| Scenario | Protected | Reason |
|----------|-----------|--------|
| Runtime replay | ✓ Yes | In-memory counter detects rollback |
| Post-restart replay | ✗ No | Counter resets, cannot detect old state |


## Cleanup

```bash
make clean      # Remove build artifacts
make clean-all  # Remove build artifacts and keys
```

## Notes

- **Demo Purpose Only**: Uses hardcoded seal key for demonstration
- **SGX Mode**: Defaults to hardware mode (HW), use `SGX_MODE=SIM` for simulation
- **Debug Build**: Enabled by default (`SGX_DEBUG=1`)

- ## AI Assistance Disclosure

This codebase was developed with assistance from large language models (LLMs) including Claude and Gemini. These tools were used to assist with code generation, debugging, and optimization during development. All code in this repository has been carefully reviewed, tested, and verified by me. I take full responsibility for its correctness, functionality, and adherence to the project requirements.

