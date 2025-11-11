#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SERVER="./Bin/bank_server"
CLIENT="./Bin/bank_client"
STATE_FILE="enclave_state.bin"
SERVER_PID=""

cleanup() {
    if [ ! -z "$SERVER_PID" ]; then
        kill $SERVER_PID 2>/dev/null
        wait $SERVER_PID 2>/dev/null
    fi
    rm -f /tmp/sgx_bank.sock
}

trap cleanup EXIT

clear

echo -e "${RED}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║           REPLAY ATTACK DEMONSTRATION (MANUAL)                ║
║                                                               ║
║  Demonstrates: Runtime protection vs. Restart vulnerability   ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo ""
echo -e "${CYAN}SCENARIO:${NC}"
echo "John uses a secure banking service. The enclave runs continuously"
echo "as a service and uses an in-memory monotonic counter to detect"
echo "replay attacks. However, when the service restarts, the counter"
echo "is lost, allowing a malicious operator to steal John's money."
echo ""

read -p "Press ENTER to begin..."
clear

# Clean up any previous state
rm -f $STATE_FILE old_state_*.bin 2>/dev/null

# ============================================================================
# STEP 1: Start Service
# ============================================================================
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}STEP 1: Start Banking Service${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Starting the secure banking service with SGX enclave..."
echo ""
read -p "Press ENTER to start server"
echo ""

$SERVER > /tmp/server.log 2>&1 &
SERVER_PID=$!
sleep 2

if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo -e "${RED}❌ Server failed to start${NC}"
    cat /tmp/server.log
    exit 1
fi

echo -e "${GREEN}✅ Server started (PID: $SERVER_PID)${NC}"
echo ""
read -p "Press ENTER to continue..."
clear

# ============================================================================
# STEP 2: Set Initial Balance
# ============================================================================
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}STEP 2: Set Initial Balance${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}[SERVICE IS RUNNING]${NC}"
echo ""
echo "Setting John's initial balance to \$100."
echo ""
read -p "Press ENTER to run: $CLIENT set 100"
echo ""

$CLIENT set 100

echo ""
read -p "Press ENTER to continue..."
clear

# ============================================================================
# STEP 3: Capture State
# ============================================================================
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}STEP 3: Capture State (Balance = \$100)${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}[SERVICE IS RUNNING]${NC}"
echo ""
echo -e "${YELLOW}[MALICIOUS ACTION]${NC}"
echo "The server operator secretly copies the state file."
echo "The service is still running - this is just a file copy."
echo ""
echo "Command: cp $STATE_FILE old_state_balance_100.bin"
echo ""
read -p "Press ENTER to capture state..."

if [ -f "$STATE_FILE" ]; then
    cp $STATE_FILE old_state_balance_100.bin
    echo ""
    echo -e "${RED}✓ Old state captured!${NC}"
    ls -lh old_state_balance_100.bin
else
    echo -e "${RED}❌ State file not found!${NC}"
    exit 1
fi

echo ""
read -p "Press ENTER to continue..."
clear

# ============================================================================
# STEP 4: John Deposits Money
# ============================================================================
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}STEP 4: John Deposits Money${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}[SERVICE IS RUNNING]${NC}"
echo ""
echo "John deposits \$75 into his account."
echo "Balance: \$100 → \$175"
echo ""
read -p "Press ENTER to run: $CLIENT deposit 75"
echo ""

$CLIENT deposit 75

echo ""
read -p "Press ENTER to continue..."
clear

# ============================================================================
# STEP 5: Try Runtime Replay (FAILS)
# ============================================================================
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}STEP 5: Attempt Replay While Service Running (FAILS)${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}[SERVICE IS RUNNING - Counter is in memory]${NC}"
echo ""
echo "Let's try to load the old state (Balance=\$100) while the service"
echo "is still running. The monotonic counter should detect this!"
echo ""
read -p "Press ENTER to run: $CLIENT load old_state_balance_100.bin"
echo ""

# Run silently and check return code
if $CLIENT --silent load old_state_balance_100.bin; then
    echo -e "${RED}❌ UNEXPECTED: Replay was accepted!${NC}"
else
    echo -e "${GREEN}✓ RUNTIME PROTECTION WORKS!${NC}"
    echo "🛡️  The enclave detected the replay attack and rejected it."
fi

echo ""
echo "Let's verify John still has his money:"
echo ""
read -p "Press ENTER to run: $CLIENT query"
echo ""

$CLIENT query

echo ""
echo -e "${GREEN}✓ John's balance is still \$175 - the attack was blocked!${NC}"
echo ""
read -p "Press ENTER to continue..."
clear

# ============================================================================
# STEP 6: Stop Service
# ============================================================================
echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${RED}STEP 6: Stop the Service (Counter Lost)${NC}"
echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Now we'll stop the banking service. This destroys the enclave"
echo "and LOSES the monotonic counter from memory."
echo ""
read -p "Press ENTER to stop server"
echo ""

kill -TERM $SERVER_PID
wait $SERVER_PID 2>/dev/null
SERVER_PID=""

echo ""
echo -e "${RED}🔴 SERVICE STOPPED - Counter lost from memory${NC}"
echo ""
read -p "Press ENTER to continue..."
clear

# ============================================================================
# STEP 7: Replace State File
# ============================================================================
echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${RED}STEP 7: Replace State File (Malicious)${NC}"
echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${RED}[SERVICE IS DOWN - Counter is lost]${NC}"
echo ""
echo -e "${YELLOW}[MALICIOUS ACTION]${NC}"
echo "The server operator replaces the current state file"
echo "(Balance=\$175) with the old captured state (Balance=\$100)."
echo ""
echo "Command: cp old_state_balance_100.bin $STATE_FILE"
echo ""
read -p "Press ENTER to perform replay attack..."

cp old_state_balance_100.bin $STATE_FILE

echo ""
echo -e "${RED}✓ State file replaced!${NC}"
echo "John's \$75 deposit will be erased when service restarts."
echo ""
read -p "Press ENTER to continue..."
clear

# ============================================================================
# STEP 8: Restart and Verify
# ============================================================================
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}STEP 8: Restart Service and Verify Attack${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Restarting the service. The counter resets to 0, so the enclave"
echo "cannot detect that the state is old."
echo ""
read -p "Press ENTER to restart server"
echo ""

$SERVER > /tmp/server.log 2>&1 &
SERVER_PID=$!
sleep 2

echo -e "${GREEN}✅ Server restarted${NC}"
echo ""
read -p "Press ENTER to check balance: $CLIENT query"
echo ""

$CLIENT query

echo ""
read -p "Press ENTER to see analysis..."
clear

echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${RED}              ATTACK SUCCESSFUL - MONEY STOLEN                 ${NC}"
echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}What happened:${NC}"
echo "  1. John had \$100 (counter = 1)"
echo "  2. Server captured that state"
echo "  3. John deposited \$75 → Balance = \$175 (counter = 2)"
echo "  4. Tried replay while running → BLOCKED (counter 1 < 2)"
echo "  5. Service stopped → counter lost from memory"
echo "  6. Server replaced state file with old version"
echo "  7. Service restarted → counter reset to 0"
echo "  8. Loaded old state → ACCEPTED (counter 1 > 0)"
echo "  9. John's \$75 deposit STOLEN!"
echo ""
echo -e "${RED}Impact:${NC}"
echo "  • John deposited \$75 but it disappeared"
echo "  • The malicious operator stole the money"
echo "  • SGX provided no protection against this"
echo ""
echo -e "${CYAN}Root Cause:${NC}"
echo "SGXv2 lacks PERSISTENT monotonic counters."
echo "Runtime protection works, but restart vulnerability remains."
echo ""
echo ""
read -p "Press ENTER to cleanup and exit..."

cleanup
