#!/bin/bash
# Rosewood Performance Testing Script
# Usage: ./performance_test.sh [typing|scroll|memory|fileopen|all]

set -e

ROSEWOOD_PID=""
TEST_FILE=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Rosewood is running
check_rosewood() {
    ROSEWOOD_PID=$(pgrep -x "Rosewood" || pgrep -x "Rosewood.debug" || echo "")
    if [ -z "$ROSEWOOD_PID" ]; then
        log_error "Rosewood is not running. Please start Rosewood first."
        exit 1
    fi
    log_info "Rosewood PID: $ROSEWOOD_PID"
}

# Get current memory usage
get_memory() {
    local pid=$1
    ps -o rss= -p "$pid" 2>/dev/null || echo "0"
}

# Get current CPU usage
get_cpu() {
    local pid=$1
    ps -o pcpu= -p "$pid" 2>/dev/null || echo "0"
}

# Test: Typing Latency
test_typing_latency() {
    log_info "Testing typing latency..."
    log_info "Manual test: Type rapidly in editor and check for lag"
    
    # Note: This would typically be done via UI automation
    # For now, provide instructions
    echo ""
    echo "Manual Typing Test Instructions:"
    echo "1. Open a large file (10K+ lines)"
    echo "2. Type as fast as possible for 10 seconds"
    echo "3. Check for:"
    echo "   - Characters appearing immediately"
    echo "   - No stuttering or dropped keystrokes"
    echo "   - Target: <16ms per keystroke"
    echo ""
    echo "To measure programmatically, add timing code to EditorView.swift:"
    echo '  let start = Date()'
    echo '  // process input'
    echo '  let latency = Date().timeIntervalSince(start)'
    echo '  print("Latency: \\(latency * 1000)ms")'
}

# Test: Scroll Performance
test_scroll_performance() {
    log_info "Testing scroll performance..."
    
    # Generate a test file if needed
    if [ ! -f "/tmp/scroll_test.swift" ]; then
        log_info "Creating scroll test file..."
        for i in {1..5000}; do
            echo "// Line $i: Lorem ipsum dolor sit amet, consectetur adipiscing elit." >> /tmp/scroll_test.swift
        done
    fi
    
    check_rosewood
    
    local base_memory=$(get_memory $ROSEWOOD_PID)
    log_info "Base memory: ${base_memory}KB"
    
    log_info "Opening test file..."
    open -a Rosewood /tmp/scroll_test.swift
    
    sleep 3
    
    local file_memory=$(get_memory $ROSEWOOD_PID)
    log_info "Memory after opening file: ${file_memory}KB"
    log_info "Memory delta: $((file_memory - base_memory))KB"
    
    echo ""
    echo "Manual Scroll Test Instructions:"
    echo "1. Scroll from top to bottom rapidly"
    echo "2. Check for:"
    echo "   - Smooth scrolling (60 FPS)"
    echo "   - No stuttering"
    echo "   - Minimap updates correctly"
    echo ""
    echo "To profile with Instruments:"
    echo "  xcrun instruments -t 'Core Animation' -p Rosewood"
}

# Test: Memory Usage
test_memory() {
    log_info "Testing memory usage..."
    
    check_rosewood
    
    local base_memory=$(get_memory $ROSEWOOD_PID)
    log_info "Base memory: ${base_memory}KB ($(echo "scale=2; $base_memory/1024" | bc)MB)"
    
    # Test different file sizes
    local sizes=("1K" "5K" "10K")
    for size in "${sizes[@]}"; do
        local lines=$(echo $size | sed 's/K//')
        lines=$((lines * 1000))
        
        local test_file="/tmp/memory_test_${size}.swift"
        if [ ! -f "$test_file" ]; then
            log_info "Creating $size line test file..."
            for i in $(seq 1 $lines); do
                echo "// Line $i: Test content for memory profiling." >> "$test_file"
            done
        fi
        
        log_info "Opening $size file..."
        open -a Rosewood "$test_file"
        sleep 3
        
        local mem=$(get_memory $ROSEWOOD_PID)
        log_info "Memory with $size file: ${mem}KB ($(echo "scale=2; $mem/1024" | bc)MB)"
        
        # Criteria
        case "$size" in
            "1K")
                if [ $mem -gt 150000 ]; then
                    log_warn "Memory usage exceeds 150MB for 1K lines"
                fi
                ;;
            "5K")
                if [ $mem -gt 200000 ]; then
                    log_warn "Memory usage exceeds 200MB for 5K lines"
                fi
                ;;
            "10K")
                if [ $mem -gt 350000 ]; then
                    log_warn "Memory usage exceeds 350MB for 10K lines"
                fi
                ;;
        esac
    done
    
    log_info "Memory test complete"
}

# Test: File Open Performance
test_file_open() {
    log_info "Testing file open performance..."
    
    check_rosewood
    
    # Create test files of different sizes
    local sizes=("200K" "500K" "1M")
    for size in "${sizes[@]}"; do
        local test_file="/tmp/open_test_${size}.swift"
        
        if [ ! -f "$test_file" ]; then
            log_info "Creating $size test file..."
            local target_size=$(echo $size | sed 's/K/*1024/;s/M/*1024*1024/' | bc)
            local current_size=0
            local i=1
            
            while [ $current_size -lt $target_size ]; do
                echo "// Line $i: $(head -c 100 /dev/urandom | base64 | head -c 100)" >> "$test_file"
                current_size=$(stat -f%z "$test_file" 2>/dev/null || stat -c%s "$test_file" 2>/dev/null || echo "0")
                i=$((i + 1))
            done
        fi
        
        local file_size=$(stat -f%z "$test_file" 2>/dev/null || stat -c%s "$test_file" 2>/dev/null || echo "0")
        log_info "Testing open: $size target ($(numfmt --to=iec $file_size 2>/dev/null || echo "${file_size} bytes"))"
        
        local start_time=$(date +%s.%N)
        open -a Rosewood "$test_file"
        sleep 5  # Wait for file to fully load
        local end_time=$(date +%s.%N)
        
        local duration=$(echo "$end_time - $start_time" | bc)
        log_info "Open time: ${duration}s"
        
        # Criteria
        case "$size" in
            "200K")
                if [ $(echo "$duration > 0.5" | bc) -eq 1 ]; then
                    log_warn "Open time > 500ms for 200KB file"
                fi
                ;;
            "500K")
                if [ $(echo "$duration > 1.0" | bc) -eq 1 ]; then
                    log_warn "Open time > 1s for 500KB file"
                fi
                ;;
            "1M")
                if [ $(echo "$duration > 2.0" | bc) -eq 1 ]; then
                    log_warn "Open time > 2s for 1MB file"
                fi
                ;;
        esac
    done
}

# Run all tests
test_all() {
    test_typing_latency
    echo ""
    test_scroll_performance
    echo ""
    test_memory
    echo ""
    test_file_open
}

# Cleanup
cleanup() {
    log_info "Cleaning up..."
    rm -f /tmp/scroll_test.swift /tmp/memory_test_*.swift /tmp/open_test_*.swift
}

# Main
main() {
    local command="${1:-all}"
    
    case "$command" in
        typing)
            test_typing_latency
            ;;
        scroll)
            test_scroll_performance
            ;;
        memory)
            test_memory
            ;;
        fileopen)
            test_file_open
            ;;
        all)
            test_all
            ;;
        clean)
            cleanup
            ;;
        *)
            echo "Usage: $0 [typing|scroll|memory|fileopen|all|clean]"
            echo ""
            echo "Commands:"
            echo "  typing   - Test typing latency"
            echo "  scroll   - Test scroll performance"
            echo "  memory   - Test memory usage"
            echo "  fileopen - Test file open performance"
            echo "  all      - Run all tests (default)"
            echo "  clean    - Remove test files"
            exit 1
            ;;
    esac
}

main "$@"
