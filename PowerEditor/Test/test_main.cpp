// PowerEditor/Test/test_main.cpp
// Main test runner entry point for Notepad++ macOS port

#include "test_framework.h"
#include <iostream>

int main(int argc, char* argv[]) {
    return NppTest::TestRunner::getInstance().run(argc, argv);
}
