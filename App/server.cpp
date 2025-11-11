#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <signal.h>
#include "sgx_urts.h"
#include "Enclave_u.h"

#define ENCLAVE_FILE "Bin/enclave.signed.so"
#define STATE_FILE "enclave_state.bin"
#define SOCKET_PATH "/tmp/sgx_bank.sock"

sgx_enclave_id_t global_eid = 0;
int server_fd = -1;

void ocall_save_encrypted_state(const uint8_t* data, size_t data_len) {
    FILE* fp = fopen(STATE_FILE, "wb");
    if (fp) {
        fwrite(data, 1, data_len, fp);
        fclose(fp);
        printf("    💾 Saved state (%zu bytes)\n", data_len);
    }
}

size_t ocall_load_encrypted_state(uint8_t* buffer, size_t max_len) {
    FILE* fp = fopen(STATE_FILE, "rb");
    if (!fp) {
        printf("    ℹ️  No previous state, starting fresh\n");
        return 0;
    }

    fseek(fp, 0, SEEK_END);
    size_t len = ftell(fp);
    fseek(fp, 0, SEEK_SET);

    if (len > max_len) len = max_len;
    size_t read = fread(buffer, 1, len, fp);
    fclose(fp);

    printf("    📂 Loaded state (%zu bytes)\n", read);
    return read;
}

void cleanup(int sig) {
    printf("\n💾 Saving state before shutdown...\n");
    ecall_save_state(global_eid);
    printf("🔒 Shutting down enclave\n");
    sgx_destroy_enclave(global_eid);
    if (server_fd >= 0) close(server_fd);
    unlink(SOCKET_PATH);
    printf("🔴 Server stopped\n");
    exit(0);
}

void handle_client(int client_fd) {
    char cmd[256];
    int n = read(client_fd, cmd, sizeof(cmd) - 1);
    if (n <= 0) return;
    cmd[n] = '\0';

    char response[1024];
    char name[64];
    int balance;
    uint32_t tx_count;

    if (strncmp(cmd, "SET ", 4) == 0) {
        int amount = atoi(cmd + 4);
        ecall_set_balance(global_eid, amount);
        ecall_get_account_info(global_eid, name, sizeof(name), &balance, &tx_count);
        snprintf(response, sizeof(response), "OK|%s|%d|%u", name, balance, tx_count);
        ecall_save_state(global_eid);

    } else if (strncmp(cmd, "DEPOSIT ", 8) == 0) {
        int amount = atoi(cmd + 8);
        ecall_deposit(global_eid, amount);
        ecall_get_account_info(global_eid, name, sizeof(name), &balance, &tx_count);
        snprintf(response, sizeof(response), "OK|%s|%d|%u", name, balance, tx_count);
        ecall_save_state(global_eid);

    } else if (strncmp(cmd, "WITHDRAW ", 9) == 0) {
        int amount = atoi(cmd + 9);
        ecall_withdraw(global_eid, amount);
        ecall_get_account_info(global_eid, name, sizeof(name), &balance, &tx_count);
        snprintf(response, sizeof(response), "OK|%s|%d|%u", name, balance, tx_count);
        ecall_save_state(global_eid);

    } else if (strcmp(cmd, "QUERY") == 0) {
        ecall_get_account_info(global_eid, name, sizeof(name), &balance, &tx_count);
        snprintf(response, sizeof(response), "OK|%s|%d|%u", name, balance, tx_count);

    } else if (strcmp(cmd, "SAVE") == 0) {
        ecall_save_state(global_eid);
        snprintf(response, sizeof(response), "OK|saved");

    } else if (strncmp(cmd, "LOAD ", 5) == 0) {
        char* filename = cmd + 5;
        FILE* fp = fopen(filename, "rb");
        if (!fp) {
            snprintf(response, sizeof(response), "ERROR|Cannot open file");
        } else {
            fseek(fp, 0, SEEK_END);
            size_t len = ftell(fp);
            fseek(fp, 0, SEEK_SET);
            uint8_t* buffer = (uint8_t*)malloc(len);
            fread(buffer, 1, len, fp);
            fclose(fp);

            int result;
            ecall_load_state(global_eid, &result, buffer, len);
            free(buffer);

            if (result == 1) {
                snprintf(response, sizeof(response), "REPLAY|Replay attack detected");
            } else if (result == 0) {
                ecall_get_account_info(global_eid, name, sizeof(name), &balance, &tx_count);
                snprintf(response, sizeof(response), "OK|%s|%d|%u", name, balance, tx_count);
            } else {
                snprintf(response, sizeof(response), "ERROR|Load failed");
            }
        }
    } else {
        snprintf(response, sizeof(response), "ERROR|Unknown command");
    }

    write(client_fd, response, strlen(response));
}

int main() {
    signal(SIGINT, cleanup);
    signal(SIGTERM, cleanup);

    printf("\n");
    printf("═══════════════════════════════════════════════════════\n");
    printf("     STARTING SECURE BANKING SERVICE (SGX Enclave)     \n");
    printf("═══════════════════════════════════════════════════════\n");
    printf("\n");

    sgx_status_t ret = sgx_create_enclave(ENCLAVE_FILE, SGX_DEBUG_FLAG, NULL, NULL, &global_eid, NULL);
    if (ret != SGX_SUCCESS) {
        printf("❌ Failed to create enclave\n");
        return 1;
    }
    printf("✅ Enclave created (ID: %lu)\n", global_eid);

    ecall_initialize_enclave(global_eid);

    uint8_t buffer[1024];
    size_t len = ocall_load_encrypted_state(buffer, sizeof(buffer));
    if (len > 0) {
        int result;
        ecall_load_state(global_eid, &result, buffer, len);
    }

    unlink(SOCKET_PATH);
    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un addr;
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, SOCKET_PATH, sizeof(addr.sun_path) - 1);

    bind(server_fd, (struct sockaddr*)&addr, sizeof(addr));
    listen(server_fd, 5);

    printf("🟢 Banking service RUNNING\n");
    printf("   Listening on: %s\n\n", SOCKET_PATH);

    while (1) {
        int client_fd = accept(server_fd, NULL, NULL);
        if (client_fd < 0) continue;
        handle_client(client_fd);
        close(client_fd);
    }

    return 0;
}
