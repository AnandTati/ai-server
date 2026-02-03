#!/usr/bin/env bash
# =============================================================================
# AI Stack Test Script
# =============================================================================
#
# Tests the Smart Router routing logic, streaming, and API compatibility.
# Run after starting the stack with ./ai-on.sh
#
# Usage:
#   ./tests/run_tests.sh
#
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

ROUTER_URL="http://localhost:8000"
TIMEOUT=120
PASS=0
FAIL=0

print_test() {
    echo ""
    echo "=== TEST: $1 ==="
}

# Check if services are running
echo "Checking services..."
if ! curl -s --max-time 5 "$ROUTER_URL/health" > /dev/null 2>&1; then
    echo "ERROR: Router not running. Start with ./ai-on.sh first."
    exit 1
fi
echo "Services are running."

# =============================================================================
# Basic Health & API Tests
# =============================================================================

print_test "Health Check"
HEALTH=$(curl -s --max-time 5 "$ROUTER_URL/health" 2>/dev/null)
if echo "$HEALTH" | grep -q '"status":"healthy"'; then
    echo "[PASS] Router is healthy"
    ((PASS++))
else
    echo "[FAIL] Router health check failed"
    ((FAIL++))
fi

print_test "Model List Endpoint"
MODELS=$(curl -s --max-time 5 "$ROUTER_URL/v1/models" 2>/dev/null)
if echo "$MODELS" | grep -q '"id":"auto"'; then
    echo "[PASS] /v1/models returns auto model"
    ((PASS++))
else
    echo "[FAIL] /v1/models missing auto model"
    ((FAIL++))
fi

print_test "Memory Stats Endpoint"
STATS=$(curl -s --max-time 5 "$ROUTER_URL/v1/memory/stats" 2>/dev/null)
if echo "$STATS" | grep -q "total_messages"; then
    echo "[PASS] Memory stats available"
    ((PASS++))
else
    echo "[FAIL] Could not get memory stats"
    ((FAIL++))
fi

# =============================================================================
# Routing Tests - Coding Keywords
# =============================================================================

print_test "Routing: Coding Query (python)"
MODEL=$(curl -s --max-time $TIMEOUT "$ROUTER_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model": "auto", "messages": [{"role": "user", "content": "Write python code to sort a list"}], "stream": false}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('model', 'unknown'))" 2>/dev/null)
if [[ "$MODEL" == *"deepseek"* ]]; then
    echo "[PASS] Python query -> $MODEL"
    ((PASS++))
else
    echo "[FAIL] Python query should route to deepseek, got: $MODEL"
    ((FAIL++))
fi

print_test "Routing: Coding Query (debug)"
MODEL=$(curl -s --max-time $TIMEOUT "$ROUTER_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model": "auto", "messages": [{"role": "user", "content": "Debug this error please"}], "stream": false}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('model', 'unknown'))" 2>/dev/null)
if [[ "$MODEL" == *"deepseek"* ]]; then
    echo "[PASS] Debug query -> $MODEL"
    ((PASS++))
else
    echo "[FAIL] Debug query should route to deepseek, got: $MODEL"
    ((FAIL++))
fi

print_test "Routing: Coding Query (function)"
MODEL=$(curl -s --max-time $TIMEOUT "$ROUTER_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model": "auto", "messages": [{"role": "user", "content": "Create a function that calculates factorial"}], "stream": false}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('model', 'unknown'))" 2>/dev/null)
if [[ "$MODEL" == *"deepseek"* ]]; then
    echo "[PASS] Function query -> $MODEL"
    ((PASS++))
else
    echo "[FAIL] Function query should route to deepseek, got: $MODEL"
    ((FAIL++))
fi

# =============================================================================
# Routing Tests - General Queries
# =============================================================================

print_test "Routing: General Query (greeting)"
MODEL=$(curl -s --max-time $TIMEOUT "$ROUTER_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model": "auto", "messages": [{"role": "user", "content": "Hello, how are you today?"}], "stream": false}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('model', 'unknown'))" 2>/dev/null)
if [[ "$MODEL" == *"qwen"* ]]; then
    echo "[PASS] Greeting -> $MODEL"
    ((PASS++))
else
    echo "[FAIL] Greeting should route to qwen, got: $MODEL"
    ((FAIL++))
fi

print_test "Routing: General Query (question)"
MODEL=$(curl -s --max-time $TIMEOUT "$ROUTER_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model": "auto", "messages": [{"role": "user", "content": "What is the capital of France?"}], "stream": false}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('model', 'unknown'))" 2>/dev/null)
if [[ "$MODEL" == *"qwen"* ]]; then
    echo "[PASS] Question -> $MODEL"
    ((PASS++))
else
    echo "[FAIL] Question should route to qwen, got: $MODEL"
    ((FAIL++))
fi

print_test "Routing: General Query (ideas)"
MODEL=$(curl -s --max-time $TIMEOUT "$ROUTER_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model": "auto", "messages": [{"role": "user", "content": "Give me ideas"}], "stream": false}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('model', 'unknown'))" 2>/dev/null)
if [[ "$MODEL" == *"qwen"* ]]; then
    echo "[PASS] Ideas query -> $MODEL"
    ((PASS++))
else
    echo "[FAIL] Ideas query should route to qwen, got: $MODEL"
    ((FAIL++))
fi

# =============================================================================
# Routing Tests - Summarization
# =============================================================================

print_test "Routing: Summarization Query"
MODEL=$(curl -s --max-time $TIMEOUT "$ROUTER_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model": "auto", "messages": [{"role": "user", "content": "Summarize this article for me"}], "stream": false}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('model', 'unknown'))" 2>/dev/null)
if [[ "$MODEL" == *"qwen"* ]]; then
    echo "[PASS] Summarize -> $MODEL"
    ((PASS++))
else
    echo "[FAIL] Summarize should route to qwen, got: $MODEL"
    ((FAIL++))
fi

print_test "Routing: TL;DR Query"
MODEL=$(curl -s --max-time $TIMEOUT "$ROUTER_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model": "auto", "messages": [{"role": "user", "content": "TL;DR of the above"}], "stream": false}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('model', 'unknown'))" 2>/dev/null)
if [[ "$MODEL" == *"qwen"* ]]; then
    echo "[PASS] TL;DR -> $MODEL"
    ((PASS++))
else
    echo "[FAIL] TL;DR should route to qwen, got: $MODEL"
    ((FAIL++))
fi

# =============================================================================
# Word Boundary Tests (prevent false positives)
# =============================================================================

print_test "Word Boundary: 'json' in name (should be general)"
MODEL=$(curl -s --max-time $TIMEOUT "$ROUTER_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model": "auto", "messages": [{"role": "user", "content": "Tell me about Jason who lives in Boston"}], "stream": false}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('model', 'unknown'))" 2>/dev/null)
if [[ "$MODEL" == *"qwen"* ]]; then
    echo "[PASS] Jason (not json) -> $MODEL"
    ((PASS++))
else
    echo "[FAIL] Jason should not trigger coding, got: $MODEL"
    ((FAIL++))
fi

print_test "Word Boundary: 'class' as school (should be general)"
MODEL=$(curl -s --max-time $TIMEOUT "$ROUTER_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model": "auto", "messages": [{"role": "user", "content": "I have a math class tomorrow"}], "stream": false}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('model', 'unknown'))" 2>/dev/null)
if [[ "$MODEL" == *"qwen"* ]]; then
    echo "[PASS] Math class (not programming class) -> $MODEL"
    ((PASS++))
else
    echo "[FAIL] School class should not trigger coding, got: $MODEL"
    ((FAIL++))
fi

# =============================================================================
# Streaming Tests
# =============================================================================

print_test "Streaming: Basic Response"
STREAM_OUTPUT=$(curl -s --max-time $TIMEOUT "$ROUTER_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model": "auto", "messages": [{"role": "user", "content": "Say hi"}], "stream": true}' 2>&1)
if echo "$STREAM_OUTPUT" | grep -q "data: " && echo "$STREAM_OUTPUT" | grep -q "\[DONE\]"; then
    CHUNK_COUNT=$(echo "$STREAM_OUTPUT" | grep -c "data: ")
    echo "[PASS] Streaming works ($CHUNK_COUNT chunks)"
    ((PASS++))
else
    echo "[FAIL] Streaming incomplete"
    ((FAIL++))
fi

print_test "Streaming: Coding Query"
STREAM_OUTPUT=$(curl -s --max-time $TIMEOUT "$ROUTER_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model": "auto", "messages": [{"role": "user", "content": "Write hello world in python"}], "stream": true}' 2>&1)
if echo "$STREAM_OUTPUT" | grep -q "deepseek" && echo "$STREAM_OUTPUT" | grep -q "\[DONE\]"; then
    echo "[PASS] Streaming coding query works"
    ((PASS++))
else
    echo "[FAIL] Streaming coding query failed"
    ((FAIL++))
fi

# =============================================================================
# Response Content Tests
# =============================================================================

print_test "Response: Has Required Fields"
RESPONSE=$(curl -s --max-time $TIMEOUT "$ROUTER_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model": "auto", "messages": [{"role": "user", "content": "Hi"}], "stream": false}' 2>/dev/null)
if echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'choices' in d and 'model' in d and 'id' in d" 2>/dev/null; then
    echo "[PASS] Response has required OpenAI fields"
    ((PASS++))
else
    echo "[FAIL] Response missing required fields"
    ((FAIL++))
fi

print_test "Response: Message Content Present"
CONTENT=$(curl -s --max-time $TIMEOUT "$ROUTER_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model": "auto", "messages": [{"role": "user", "content": "Say hello"}], "stream": false}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'])" 2>/dev/null)
if [[ -n "$CONTENT" && ${#CONTENT} -gt 0 ]]; then
    echo "[PASS] Response has content (${#CONTENT} chars)"
    ((PASS++))
else
    echo "[FAIL] Response content empty"
    ((FAIL++))
fi

# =============================================================================
# Error Handling Tests
# =============================================================================

print_test "Error: Empty Messages"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$ROUTER_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model": "auto", "messages": [], "stream": false}' 2>/dev/null)
if [[ "$HTTP_CODE" =~ ^(400|422|500)$ ]]; then
    echo "[PASS] Empty messages returns error ($HTTP_CODE)"
    ((PASS++))
else
    echo "[FAIL] Empty messages should error, got: $HTTP_CODE"
    ((FAIL++))
fi

print_test "Error: Invalid JSON"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$ROUTER_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d 'not json' 2>/dev/null)
if [[ "$HTTP_CODE" =~ ^(400|422|500)$ ]]; then
    echo "[PASS] Invalid JSON returns error ($HTTP_CODE)"
    ((PASS++))
else
    echo "[FAIL] Invalid JSON should error, got: $HTTP_CODE"
    ((FAIL++))
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=============================================="
echo "  Test Results: $PASS passed, $FAIL failed"
echo "=============================================="

if [ $FAIL -gt 0 ]; then
    exit 1
fi
exit 0
