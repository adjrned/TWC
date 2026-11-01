// The tests' checks: a line per check ("ok" / "FAIL"), and the count of
// failures as the test's exit code (run-tests.bat adds them up).
#pragma once
#include <stdio.h>

static int g_fails;

#define CHECK(c, ...) do { bool ok_ = (c); printf("%s  ", ok_ ? "ok  " : "FAIL"); printf(__VA_ARGS__); printf("\n"); g_fails += !ok_; } while (0)

static void Verdict() {
    printf(g_fails ? "%d FAILED\n" : "all passed\n", g_fails);
}
