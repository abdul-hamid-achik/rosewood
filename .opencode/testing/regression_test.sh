#!/bin/bash
# Rosewood Regression Test Suite
# Run before any commit or release

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_DIR"

PASSED=0
FAILED=0

log_info() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED++))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Test: Build
test_build() {
    echo "=== Test: Build ==="
    if xcodebuild build -project Rosewood.xcodeproj -scheme Rosewood > /tmp/build.log 2>&1; then
        log_info "Build successful"
    else
        log_error "Build failed"
        tail -20 /tmp/build.log
        return 1
    fi
}

# Test: Unit Tests
test_unit_tests() {
    echo ""
    echo "=== Test: Unit Tests ==="
    if xcodebuild test -project Rosewood.xcodeproj -scheme RosewoodTests > /tmp/unit_tests.log 2>&1; then
        log_info "All unit tests passed"
    else
        log_error "Unit tests failed"
        tail -50 /tmp/unit_tests.log
        return 1
    fi
}

# Test: Critical UI Tests
test_critical_ui() {
    echo ""
    echo "=== Test: Critical UI Tests ==="
    
    local tests=(
        "testLaunchShowsMainShellAndSearchSidebar"
        "testQuickOpenSupportsLineAndSymbolNavigation"
        "testProjectSearchUpdatesResultsWhileTyping"
        "testFoldingFixtureCollapsesAndExpandsFromGutter"
        "testMinimapFixtureClickMovesVisibleRange"
    )
    
    local all_passed=true
    for test in "${tests[@]}"; do
        echo "  Running $test..."
        if xcodebuild test \
            -project Rosewood.xcodeproj \
            -scheme RosewoodUITests \
            -only-testing:"RosewoodUITests/RosewoodUITests/$test" > /tmp/ui_test_"$test".log 2>&1; then
            log_info "$test"
        else
            log_error "$test"
            all_passed=false
        fi
    done
    
    if [ "$all_passed" = true ]; then
        return 0
    else
        return 1
    fi
}

# Test: Static Analysis
test_static_analysis() {
    echo ""
    echo "=== Test: Static Analysis ==="
    
    # Check for obvious issues
    local issues=0
    
    # Check for force unwraps in new code (warning)
    if git diff --name-only HEAD | xargs grep -l "!" 2>/dev/null | head -5; then
        log_warn "Potential force unwraps found in changed files"
        ((issues++))
    fi
    
    # Check for print statements (warning)
    if git diff --name-only HEAD | xargs grep -l "print(" 2>/dev/null | grep "\.swift$" | head -5; then
        log_warn "Print statements found in changed files"
        ((issues++))
    fi
    
    # Check for TODO comments (info)
    if git diff --name-only HEAD | xargs grep -h "TODO\|FIXME\|XXX" 2>/dev/null | head -3; then
        log_warn "TODO/FIXME comments found"
    fi
    
    if [ $issues -eq 0 ]; then
        log_info "Static analysis passed"
    fi
}

# Test: Manual Verification Reminder
test_manual_reminder() {
    echo ""
    echo "=== Manual Verification Required ==="
    echo ""
    echo "Please verify the following manually:"
    echo ""
    echo "1. Basic Functionality:"
    echo "   [ ] App launches without crash"
    echo "   [ ] Can open a folder"
    echo "   [ ] Can open a file"
    echo "   [ ] Can type in editor"
    echo "   [ ] Can save file"
    echo ""
    echo "2. Large File Performance:"
    echo "   [ ] Open a 10,000 line file"
    echo "   [ ] Type rapidly - should be smooth"
    echo "   [ ] Scroll - should be smooth"
    echo ""
    echo "3. Key Features:"
    echo "   [ ] Quick Open (Cmd+P)"
    echo "   [ ] Command Palette (Cmd+Shift+P)"
    echo "   [ ] Find/Replace (Cmd+F)"
    echo "   [ ] Project Search (Cmd+Shift+F)"
    echo ""
    
    read -p "Have you completed manual verification? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Manual verification confirmed"
    else
        log_warn "Manual verification skipped"
    fi
}

# Summary
print_summary() {
    echo ""
    echo "========================================"
    echo "           Test Summary"
    echo "========================================"
    echo -e "  Passed: ${GREEN}$PASSED${NC}"
    echo -e "  Failed: ${RED}$FAILED${NC}"
    echo "========================================"
    
    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        return 1
    fi
}

# Main
main() {
    local mode="${1:-full}"
    
    echo "========================================"
    echo "    Rosewood Regression Test Suite"
    echo "========================================"
    echo ""
    
    case "$mode" in
        quick)
            test_build
            test_static_analysis
            ;;
        full)
            test_build
            test_unit_tests
            test_critical_ui
            test_static_analysis
            test_manual_reminder
            ;;
        ci)
            test_build
            test_unit_tests
            ;;
        *)
            echo "Usage: $0 [quick|full|ci]"
            echo ""
            echo "Modes:"
            echo "  quick - Build + static analysis only (fast)"
            echo "  full  - Complete test suite (default)"
            echo "  ci    - CI-friendly (no manual steps)"
            exit 1
            ;;
    esac
    
    print_summary
}

main "$@"
