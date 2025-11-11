#include "Enclave_t.h"
#include "sgx_trts.h"
#include "sgx_tcrypto.h"
#include <string.h>

typedef struct {
    char account_name[32];
    int balance;
    uint32_t transaction_count;
    uint8_t padding[20];
} enclave_state_t;

static enclave_state_t g_state = {{0}, 0, 0, {0}};
static sgx_aes_gcm_128bit_key_t g_seal_key;
static bool g_initialized = false;
static uint32_t g_runtime_counter = 0;  // In-memory monotonic counter (lost on restart)

void derive_seal_key() {
    const char* seed = "DEMO_SEAL_KEY_SEED_DO_NOT_USE_IN_PRODUCTION";
    sgx_sha256_hash_t hash;
    sgx_sha256_msg((const uint8_t*)seed, strlen(seed), &hash);
    memcpy(&g_seal_key, &hash, sizeof(g_seal_key));
}

void ecall_initialize_enclave() {
    if (!g_initialized) {
        derive_seal_key();
        strncpy(g_state.account_name, "John's Account", sizeof(g_state.account_name) - 1);
        g_state.balance = 0;
        g_state.transaction_count = 0;
        g_runtime_counter = 0;  // Start at 0 on fresh enclave
        g_initialized = true;
    }
}

void ecall_set_balance(int amount) {
    g_state.balance = amount;
    g_state.transaction_count++;
    g_runtime_counter++;  // Increment runtime counter
}

void ecall_get_account_info(char* name, size_t name_len, int* balance, uint32_t* tx_count) {
    if (name && name_len > 0) {
        strncpy(name, g_state.account_name, name_len - 1);
        name[name_len - 1] = '\0';
    }
    if (balance) *balance = g_state.balance;
    if (tx_count) *tx_count = g_state.transaction_count;
}

void ecall_deposit(int amount) {
    g_state.balance += amount;
    g_state.transaction_count++;
    g_runtime_counter++;  // Increment runtime counter
}

void ecall_withdraw(int amount) {
    if (g_state.balance >= amount) {
        g_state.balance -= amount;
        g_state.transaction_count++;
        g_runtime_counter++;  // Increment runtime counter
    }
}

void ecall_save_state() {
    uint8_t encrypted_buffer[256];
    uint8_t iv[12] = {0};
    sgx_aes_gcm_128bit_tag_t mac;

    sgx_read_rand(iv, sizeof(iv));

    // Include runtime counter in the saved state
    typedef struct {
        enclave_state_t state;
        uint32_t saved_counter;
    } sealed_data_t;

    sealed_data_t sealed;
    memcpy(&sealed.state, &g_state, sizeof(enclave_state_t));
    sealed.saved_counter = g_runtime_counter;

    sgx_status_t ret = sgx_rijndael128GCM_encrypt(
        &g_seal_key,
        (uint8_t*)&sealed,
        sizeof(sealed_data_t),
        encrypted_buffer + 12,
        iv,
        sizeof(iv),
        NULL,
        0,
        &mac
    );

    if (ret == SGX_SUCCESS) {
        memcpy(encrypted_buffer, iv, sizeof(iv));
        memcpy(encrypted_buffer + 12 + sizeof(sealed_data_t), &mac, sizeof(mac));

        size_t total_len = 12 + sizeof(sealed_data_t) + sizeof(mac);
        ocall_save_encrypted_state(encrypted_buffer, total_len);
    }
}

int ecall_load_state(const uint8_t* encrypted_state, size_t data_len) {
    typedef struct {
        enclave_state_t state;
        uint32_t saved_counter;
    } sealed_data_t;

    if (data_len < 12 + sizeof(sealed_data_t) + 16) {
        return -1;  // Invalid data
    }

    uint8_t iv[12];
    sgx_aes_gcm_128bit_tag_t mac;
    sealed_data_t decrypted;

    memcpy(iv, encrypted_state, 12);
    memcpy(&mac, encrypted_state + 12 + sizeof(sealed_data_t), sizeof(mac));

    sgx_status_t ret = sgx_rijndael128GCM_decrypt(
        &g_seal_key,
        encrypted_state + 12,
        sizeof(sealed_data_t),
        (uint8_t*)&decrypted,
        iv,
        sizeof(iv),
        NULL,
        0,
        &mac
    );

    if (ret != SGX_SUCCESS) {
        return -2;  // Decryption failed
    }

    // RUNTIME PROTECTION: Check if counter is going backwards
    if (g_initialized && decrypted.saved_counter <= g_runtime_counter) {
        // Replay detected during runtime!
        return 1;  // Replay attack detected
    }

    // VULNERABILITY: On fresh restart, g_runtime_counter is 0
    // So any valid encrypted state will pass the check
    memcpy(&g_state, &decrypted.state, sizeof(enclave_state_t));
    g_runtime_counter = decrypted.saved_counter;

    return 0;  // Success
}
