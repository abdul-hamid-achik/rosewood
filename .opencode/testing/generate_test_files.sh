#!/bin/bash
# Rosewood Test File Generator
# Generates test files of various sizes for performance testing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${1:-$SCRIPT_DIR/test_files}"
mkdir -p "$OUTPUT_DIR"

echo "Generating Rosewood test files in: $OUTPUT_DIR"
echo ""

# Function to generate Swift test file
generate_swift_file() {
    local lines=$1
    local output="$2"
    local complexity=$3
    
    echo "Generating Swift file: $lines lines..."
    
    cat > "$output" << EOF
// Rosewood Test File
// Generated: $(date)
// Lines: $lines
// Complexity: $complexity
// Purpose: Performance testing

import Foundation

// MARK: - Test Module

EOF

    for i in $(seq 1 $lines); do
        if [ $((i % 100)) -eq 0 ]; then
            echo "  Progress: $i/$lines"
        fi
        
        case "$complexity" in
            "minimal")
                echo "// Line $i" >> "$output"
                ;;
            "moderate")
                echo "func function_$i() { // Line $i" >> "$output"
                echo "    let value = $i" >> "$output"
                echo "    print(value)" >> "$output"
                echo "}" >> "$output"
                ;;
            "heavy")
                echo "public func processData_$i<T: Collection>(" >> "$output"
                echo "    items: T," >> "$output"
                echo "    transform: (T.Element) throws -> T.Element" >> "$output"
                echo ") rethrows -> [T.Element] where T.Element: Codable {" >> "$output"
                echo "    return try items.map(transform)" >> "$output"
                echo "}" >> "$output"
                ;;
            "extreme")
                echo "public struct Configuration_$i<" >> "$output"
                echo "    Input: Decodable & Encodable & Sendable," >> "$output"
                echo "    Output: Encodable & Sendable," >> "$output"
                echo "    Error: Swift.Error & LocalizedError" >> "$output"
                echo ">: Codable, Equatable, Hashable, Sendable where Input: Hashable, Output: Comparable {" >> "$output"
                echo "    @Published var value: Input" >> "$output"
                echo "    let transformer: (Input) async throws -> Output" >> "$output"
                echo "    " >> "$output"
                echo "    func process() async throws -> Output {" >> "$output"
                echo "        try await Task.sleep(nanoseconds: 100_000_000)" >> "$output"
                echo "        return try await transformer(value)" >> "$output"
                echo "    }" >> "$output"
                echo "}" >> "$output"
                ;;
        esac
    done
    
    local size=$(stat -f%z "$output" 2>/dev/null || stat -c%s "$output" 2>/dev/null || echo "0")
    echo "  Created: $output ($(numfmt --to=iec $size 2>/dev/null || echo "${size} bytes"))"
}

# Function to generate JavaScript test file
generate_js_file() {
    local lines=$1
    local output="$2"
    
    echo "Generating JavaScript file: $lines lines..."
    
    cat > "$output" << EOF
// Rosewood Test File
// Generated: $(date)
// Lines: $lines
// Purpose: Performance testing

EOF

    for i in $(seq 1 $lines); do
        if [ $((i % 100)) -eq 0 ]; then
            echo "  Progress: $i/$lines"
        fi
        
        echo "async function process_$i(data) {" >> "$output"
        echo "    const result = await Promise.all(data.map(async (item) => {" >> "$output"
        echo "        return await process_$((i+1))(item);" >> "$output"
        echo "    }));" >> "$output"
        echo "    return result;" >> "$output"
        echo "}" >> "$output"
    done
    
    local size=$(stat -f%z "$output" 2>/dev/null || stat -c%s "$output" 2>/dev/null || echo "0")
    echo "  Created: $output ($(numfmt --to=iec $size 2>/dev/null || echo "${size} bytes"))"
}

# Function to generate JSON test file
generate_json_file() {
    local items=$1
    local output="$2"
    
    echo "Generating JSON file: $items items..."
    
    echo '{"data":[' > "$output"
    
    for i in $(seq 1 $items); do
        if [ $((i % 1000)) -eq 0 ]; then
            echo "  Progress: $i/$items"
        fi
        
        if [ $i -lt $items ]; then
            echo "  {\"id\":$i,\"name\":\"Item $i\",\"value\":$((i*10)),\"nested\":{\"a\":$i,\"b\":\"string_$i\"}}," >> "$output"
        else
            echo "  {\"id\":$i,\"name\":\"Item $i\",\"value\":$((i*10)),\"nested\":{\"a\":$i,\"b\":\"string_$i\"}}" >> "$output"
        fi
    done
    
    echo ']}' >> "$output"
    
    local size=$(stat -f%z "$output" 2>/dev/null || stat -c%s "$output" 2>/dev/null || echo "0")
    echo "  Created: $output ($(numfmt --to=iec $size 2>/dev/null || echo "${size} bytes"))"
}

# Generate files
main() {
    echo "=== Rosewood Test File Generator ==="
    echo ""
    
    # Swift files
    echo "--- Swift Test Files ---"
    generate_swift_file 1000 "$OUTPUT_DIR/swift_small_1k.swift" "minimal"
    generate_swift_file 5000 "$OUTPUT_DIR/swift_medium_5k.swift" "moderate"
    generate_swift_file 10000 "$OUTPUT_DIR/swift_large_10k.swift" "heavy"
    generate_swift_file 50000 "$OUTPUT_DIR/swift_xlarge_50k.swift" "extreme"
    
    echo ""
    echo "--- JavaScript Test Files ---"
    generate_js_file 5000 "$OUTPUT_DIR/javascript_5k.js"
    
    echo ""
    echo "--- JSON Test Files ---"
    generate_json_file 10000 "$OUTPUT_DIR/json_10k.json"
    
    echo ""
    echo "=== Generation Complete ==="
    echo "Files created in: $OUTPUT_DIR"
    ls -lh "$OUTPUT_DIR"
}

main
