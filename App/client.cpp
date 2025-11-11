#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

#define SOCKET_PATH "/tmp/sgx_bank.sock"

int send_command(const char* cmd, int silent) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un addr;
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, SOCKET_PATH, sizeof(addr.sun_path) - 1);

    if (connect(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        if (!silent) {
            printf("❌ Cannot connect to server. Is it running?\n");
            printf("   Start with: ./Bin/bank_server\n");
        }
        close(fd);
        return 1;
    }

    write(fd, cmd, strlen(cmd));

    char response[1024];
    int n = read(fd, response, sizeof(response) - 1);
    response[n] = '\0';
    close(fd);

    char* type = strtok(response, "|");

    if (strcmp(type, "OK") == 0) {
        char* name = strtok(NULL, "|");
        char* bal = strtok(NULL, "|");
        char* tx = strtok(NULL, "|");

        if (name && bal && tx) {
            printf("\n");
            printf("    ╔════════════════════════════════════════╗\n");
            printf("    ║         SECURE BANK ACCOUNT            ║\n");
            printf("    ╠════════════════════════════════════════╣\n");
            printf("    ║ Account: %-29s ║\n", name);
            printf("    ║ Balance: $%-28s ║\n", bal);
            printf("    ║ Transactions: %-24s ║\n", tx);
            printf("    ╚════════════════════════════════════════╝\n");
            printf("\n");
        } else {
            if (!silent) printf("✅ %s\n", strtok(NULL, "|"));
        }
        return 0;
    } else if (strcmp(type, "REPLAY") == 0) {
        if (!silent) {
            printf("🛡️  REPLAY ATTACK DETECTED!\n");
            printf("❌ %s\n", strtok(NULL, "|"));
        }
        return 1;
    } else {
        if (!silent) printf("❌ Error: %s\n", strtok(NULL, "|"));
        return 1;
    }
}

int main(int argc, char* argv[]) {
    int silent = 0;

    // Check for --silent flag
    if (argc > 1 && strcmp(argv[1], "--silent") == 0) {
        silent = 1;
        argc--;
        argv++;
    }

    if (argc < 2) {
        printf("Usage: %s [--silent] <command> [args]\n", argv[0]);
        printf("Commands:\n");
        printf("  set <amount>\n");
        printf("  deposit <amount>\n");
        printf("  withdraw <amount>\n");
        printf("  query\n");
        printf("  load <file>\n");
        printf("  save\n");
        return 1;
    }

    char cmd[256];

    if (strcmp(argv[1], "set") == 0 && argc > 2) {
        snprintf(cmd, sizeof(cmd), "SET %s", argv[2]);
        if (!silent) printf("⚙️  Setting balance to $%s...\n", argv[2]);
    } else if (strcmp(argv[1], "deposit") == 0 && argc > 2) {
        snprintf(cmd, sizeof(cmd), "DEPOSIT %s", argv[2]);
        if (!silent) printf("💰 Depositing $%s...\n", argv[2]);
    } else if (strcmp(argv[1], "withdraw") == 0 && argc > 2) {
        snprintf(cmd, sizeof(cmd), "WITHDRAW %s", argv[2]);
        if (!silent) printf("💸 Withdrawing $%s...\n", argv[2]);
    } else if (strcmp(argv[1], "query") == 0) {
        snprintf(cmd, sizeof(cmd), "QUERY");
        if (!silent) printf("📊 Querying account...\n");
    } else if (strcmp(argv[1], "load") == 0 && argc > 2) {
        snprintf(cmd, sizeof(cmd), "LOAD %s", argv[2]);
        if (!silent) printf("🔄 Loading state from %s...\n", argv[2]);
    } else if (strcmp(argv[1], "save") == 0) {
        snprintf(cmd, sizeof(cmd), "SAVE");
        if (!silent) printf("💾 Saving state...\n");
    } else {
        if (!silent) printf("❌ Unknown command\n");
        return 1;
    }

    return send_command(cmd, silent);
}
