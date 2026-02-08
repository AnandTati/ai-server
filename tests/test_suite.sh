#!/usr/bin/env bash
# =============================================================================
# AI Stack Comprehensive Test Suite
# =============================================================================
#
# Tests all major features of the AI Stack:
#   1. Health & Infrastructure
#   2. Smart Routing
#   3. Conversation History
#   4. Web Search
#   5. URL Fetching
#   6. Memory System
#   7. API Compatibility
#   8. Error Handling
#   9. LLM Intent Detection
#  10. Model Indicator Display
#
# Usage:
#   ./tests/test_suite.sh           # Run all tests
#   ./tests/test_suite.sh --quick   # Run quick tests only (no LLM calls)
#   ./tests/test_suite.sh --verbose # Show detailed output
#
# =============================================================================

set -uo pipefail

# Configuration
ROUTER_URL="${ROUTER_URL:-http://localhost:8000}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
SEARXNG_URL="${SEARXNG_URL:-http://localhost:8080}"
OPENWEBUI_URL="${OPENWEBUI_URL:-http://localhost:3000}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Options
QUICK_MODE=false
VERBOSE=false

for arg in "$@"; do
    case $arg in
        --quick) QUICK_MODE=true ;;
        --verbose) VERBOSE=true ;;
    esac
done

# =============================================================================
# Helper Functions
# =============================================================================

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((TESTS_PASSED++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((TESTS_FAILED++)); }
log_skip() { echo -e "${YELLOW}[SKIP]${NC} $1"; ((TESTS_SKIPPED++)); }
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }

log_section() {
    echo ""
    echo -e "${BLUE}==============================================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}==============================================================================${NC}"
    echo ""
}

# =============================================================================
# Test 1: Health & Infrastructure
# =============================================================================

test_health_infrastructure() {
    log_section "1. HEALTH & INFRASTRUCTURE TESTS"

    # 1.1 Router health
    log_info "Testing router health endpoint..."
    if curl -sf "$ROUTER_URL/health" | grep -q "healthy"; then
        log_pass "Router health check"
    else
        log_fail "Router health check"
    fi

    # 1.2 Ollama
    log_info "Testing Ollama connectivity..."
    if curl -sf "$OLLAMA_URL/api/tags" | grep -q "models"; then
        log_pass "Ollama is accessible"
    else
        log_fail "Ollama is not accessible"
    fi

    # 1.3 SearXNG
    log_info "Testing SearXNG connectivity..."
    if curl -sf "$SEARXNG_URL" 2>/dev/null | grep -qi "searx"; then
        log_pass "SearXNG is accessible"
    else
        log_fail "SearXNG is not accessible"
    fi

    # 1.4 OpenWebUI
    log_info "Testing OpenWebUI connectivity..."
    if curl -sf "$OPENWEBUI_URL" 2>/dev/null | grep -qi "html"; then
        log_pass "OpenWebUI is accessible"
    else
        log_fail "OpenWebUI is not accessible"
    fi

    # 1.5 Models endpoint
    log_info "Testing models endpoint..."
    if curl -sf "$ROUTER_URL/v1/models" | grep -q "auto"; then
        log_pass "Models endpoint returns auto model"
    else
        log_fail "Models endpoint missing auto model"
    fi
}

# =============================================================================
# Test 2: Smart Routing
# =============================================================================

test_smart_routing() {
    log_section "2. SMART ROUTING TESTS"

    if $QUICK_MODE; then
        log_skip "Smart routing tests (quick mode)"
        return
    fi

    # 2.1 Coding query
    log_info "Testing coding query routing..."
    cat > /tmp/test_coding.json << 'TESTEOF'
{"model":"auto","messages":[{"role":"user","content":"Write a Python function to add two numbers"}]}
TESTEOF

    local response
    response=$(curl -sf --max-time 120 "$ROUTER_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d @/tmp/test_coding.json)

    if echo "$response" | grep -qi "def\|function\|return"; then
        log_pass "Coding query routed correctly"
    else
        log_fail "Coding query routing failed"
        if $VERBOSE; then echo "  Response: $response"; fi
    fi

    # 2.2 General query
    log_info "Testing general query routing..."
    cat > /tmp/test_general.json << 'TESTEOF'
{"model":"auto","messages":[{"role":"user","content":"What is the capital of Japan?"}]}
TESTEOF

    response=$(curl -sf --max-time 120 "$ROUTER_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d @/tmp/test_general.json)

    if echo "$response" | grep -qi "Tokyo"; then
        log_pass "General query answered correctly"
    else
        log_fail "General query failed"
        if $VERBOSE; then echo "  Response: $response"; fi
    fi

    # 2.3 Summarization query
    log_info "Testing summarization query..."
    cat > /tmp/test_summary.json << 'TESTEOF'
{"model":"auto","messages":[{"role":"user","content":"Summarize: AI is transforming technology."}]}
TESTEOF

    response=$(curl -sf --max-time 120 "$ROUTER_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d @/tmp/test_summary.json)

    if [ -n "$response" ]; then
        log_pass "Summarization query handled"
    else
        log_fail "Summarization query failed"
        if $VERBOSE; then echo "  Response: $response"; fi
    fi

    rm -f /tmp/test_coding.json /tmp/test_general.json /tmp/test_summary.json
}

# =============================================================================
# Test 3: Conversation History
# =============================================================================

test_conversation_history() {
    log_section "3. CONVERSATION HISTORY TESTS"

    if $QUICK_MODE; then
        log_skip "Conversation history tests (quick mode)"
        return
    fi

    # 3.1 Remember context
    log_info "Testing conversation context retention..."

    cat > /tmp/test_conv.json << 'TESTEOF'
{
    "model": "auto",
    "messages": [
        {"role": "user", "content": "My name is Alice and I am from Seattle."},
        {"role": "assistant", "content": "Hello Alice! Seattle is a beautiful city."},
        {"role": "user", "content": "What is my name and where am I from?"}
    ]
}
TESTEOF

    local response
    response=$(curl -sf --max-time 120 "$ROUTER_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d @/tmp/test_conv.json)

    if echo "$response" | grep -qi "Alice" && echo "$response" | grep -qi "Seattle"; then
        log_pass "Conversation context retained"
    else
        log_fail "Conversation context not retained"
        if $VERBOSE; then echo "  Response: $response"; fi
    fi

    rm -f /tmp/test_conv.json
}

# =============================================================================
# Test 4: Web Search
# =============================================================================

test_web_search() {
    log_section "4. WEB SEARCH TESTS"

    # 4.1 Manual search endpoint
    log_info "Testing manual search endpoint..."
    local response
    response=$(curl -sf --max-time 30 "$ROUTER_URL/v1/search" \
        -H "Content-Type: application/json" \
        -d '{"query":"python programming"}')

    if echo "$response" | grep -q "results"; then
        log_pass "Manual search endpoint works"
    else
        log_fail "Manual search endpoint failed"
    fi

    if $QUICK_MODE; then
        log_skip "Web search chat tests (quick mode)"
        return
    fi

    # 4.2 Search trigger in chat
    log_info "Testing web search in chat..."
    cat > /tmp/test_search.json << 'TESTEOF'
{"model":"auto","messages":[{"role":"user","content":"Search the web for latest Python news"}]}
TESTEOF

    response=$(curl -sf --max-time 120 "$ROUTER_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d @/tmp/test_search.json)

    if [ -n "$response" ]; then
        log_pass "Web search in chat works"
    else
        log_fail "Web search in chat failed"
    fi

    rm -f /tmp/test_search.json
}

# =============================================================================
# Test 5: URL Fetching
# =============================================================================

test_url_fetching() {
    log_section "5. URL FETCHING TESTS"

    # 5.1 Fetch endpoint
    log_info "Testing URL fetch endpoint..."
    local response
    response=$(curl -sf "$ROUTER_URL/v1/fetch" \
        -H "Content-Type: application/json" \
        -d '{"url":"https://example.com"}')

    if echo "$response" | grep -qi "example\|content"; then
        log_pass "URL fetch endpoint works"
    else
        log_fail "URL fetch endpoint failed"
    fi

    # 5.2 Invalid URL
    log_info "Testing invalid URL handling..."
    response=$(curl -s "$ROUTER_URL/v1/fetch" \
        -H "Content-Type: application/json" \
        -d '{"url":"invalid-url"}')

    if echo "$response" | grep -qi "error\|fail"; then
        log_pass "Invalid URL handled gracefully"
    else
        log_fail "Invalid URL not handled"
    fi
}

# =============================================================================
# Test 6: Memory System
# =============================================================================

test_memory_system() {
    log_section "6. MEMORY SYSTEM TESTS"

    # 6.1 Memory stats
    log_info "Testing memory stats endpoint..."
    local response
    response=$(curl -sf "$ROUTER_URL/v1/memory/stats")

    if echo "$response" | grep -q "total_messages"; then
        log_pass "Memory stats endpoint works"
        if $VERBOSE; then echo "  Stats: $response"; fi
    else
        log_fail "Memory stats endpoint failed"
    fi

    # 6.2 Memory search
    log_info "Testing memory search endpoint..."
    response=$(curl -sf "$ROUTER_URL/v1/memory/search" \
        -H "Content-Type: application/json" \
        -d '{"query":"test","k":3}')

    if echo "$response" | grep -q "results"; then
        log_pass "Memory search endpoint works"
    else
        log_fail "Memory search endpoint failed"
    fi
}

# =============================================================================
# Test 7: API Compatibility
# =============================================================================

test_api_compatibility() {
    log_section "7. API COMPATIBILITY TESTS"

    # 7.1 OpenAI models format
    log_info "Testing OpenAI-compatible models format..."
    local response
    response=$(curl -sf "$ROUTER_URL/v1/models")

    if echo "$response" | grep -q '"object":"list"'; then
        log_pass "Models endpoint is OpenAI-compatible"
    else
        log_fail "Models endpoint not OpenAI-compatible"
    fi

    if $QUICK_MODE; then
        log_skip "Chat format tests (quick mode)"
        return
    fi

    # 7.2 Chat response format
    log_info "Testing OpenAI-compatible chat format..."
    cat > /tmp/test_format.json << 'TESTEOF'
{"model":"auto","messages":[{"role":"user","content":"Hi"}]}
TESTEOF

    response=$(curl -sf --max-time 120 "$ROUTER_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d @/tmp/test_format.json)

    if echo "$response" | grep -q '"choices"' && echo "$response" | grep -q '"message"'; then
        log_pass "Chat response is OpenAI-compatible"
    else
        log_fail "Chat response not OpenAI-compatible"
        if $VERBOSE; then echo "  Response: $response"; fi
    fi

    rm -f /tmp/test_format.json
}

# =============================================================================
# Test 8: Error Handling
# =============================================================================

test_error_handling() {
    log_section "8. ERROR HANDLING TESTS"

    # 8.1 Empty messages
    log_info "Testing empty messages handling..."
    local response
    response=$(curl -s "$ROUTER_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{"model":"auto","messages":[]}')

    if echo "$response" | grep -qi "error\|empty\|400"; then
        log_pass "Empty messages rejected"
    else
        log_fail "Empty messages not handled"
    fi

    # 8.2 Missing messages field
    log_info "Testing missing messages field..."
    response=$(curl -s "$ROUTER_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{"model":"auto"}')

    if echo "$response" | grep -qi "error\|detail\|empty\|cannot"; then
        log_pass "Missing messages handled"
    else
        log_fail "Missing messages not handled"
    fi

    # 8.3 Invalid JSON
    log_info "Testing invalid JSON handling..."
    response=$(curl -s "$ROUTER_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d 'not valid json')

    if echo "$response" | grep -qi "error\|invalid\|422"; then
        log_pass "Invalid JSON handled"
    else
        log_fail "Invalid JSON not handled"
    fi
}

# =============================================================================
# Test 9: LLM Intent Detection
# =============================================================================

test_llm_intent_detection() {
    log_section "9. LLM INTENT DETECTION TESTS"

    # 9.1 Classify endpoint exists
    log_info "Testing classify endpoint availability..."
    local response
    response=$(curl -sf --max-time 60 "$ROUTER_URL/v1/classify" \
        -H "Content-Type: application/json" \
        -d '{"query":"hello"}')

    if echo "$response" | grep -q "intent"; then
        log_pass "Classify endpoint is available"
    else
        log_fail "Classify endpoint not available"
    fi

    if $QUICK_MODE; then
        log_skip "LLM intent classification tests (quick mode)"
        return
    fi

    # 9.2 CODING intent detection
    log_info "Testing CODING intent detection..."
    response=$(curl -sf --max-time 60 "$ROUTER_URL/v1/classify" \
        -H "Content-Type: application/json" \
        -d '{"query":"Write a Python function to sort a list"}')

    if echo "$response" | grep -qi "CODING"; then
        log_pass "CODING intent detected for programming query"
    else
        log_fail "CODING intent not detected"
        if $VERBOSE; then echo "  Response: $response"; fi
    fi

    # 9.3 SEARCH intent for current information (the bug we fixed)
    log_info "Testing SEARCH intent for current info query..."
    response=$(curl -sf --max-time 60 "$ROUTER_URL/v1/classify" \
        -H "Content-Type: application/json" \
        -d '{"query":"what is the current python version?"}')

    if echo "$response" | grep -qi "SEARCH"; then
        log_pass "SEARCH intent detected for current info query"
    else
        log_fail "SEARCH intent not detected for current info query"
        if $VERBOSE; then echo "  Response: $response"; fi
    fi

    # 9.4 SEARCH intent for news/recent events
    log_info "Testing SEARCH intent for news query..."
    response=$(curl -sf --max-time 60 "$ROUTER_URL/v1/classify" \
        -H "Content-Type: application/json" \
        -d '{"query":"What are the latest news about AI?"}')

    if echo "$response" | grep -qi "SEARCH"; then
        log_pass "SEARCH intent detected for news query"
    else
        log_fail "SEARCH intent not detected for news query"
        if $VERBOSE; then echo "  Response: $response"; fi
    fi

    # 9.5 GENERAL intent for factual query
    log_info "Testing GENERAL intent for factual query..."
    response=$(curl -sf --max-time 60 "$ROUTER_URL/v1/classify" \
        -H "Content-Type: application/json" \
        -d '{"query":"What is the capital of France?"}')

    if echo "$response" | grep -qi "GENERAL"; then
        log_pass "GENERAL intent detected for factual query"
    else
        log_fail "GENERAL intent not detected for factual query"
        if $VERBOSE; then echo "  Response: $response"; fi
    fi

    # 9.6 SUMMARIZE intent detection
    log_info "Testing SUMMARIZE intent detection..."
    response=$(curl -sf --max-time 60 "$ROUTER_URL/v1/classify" \
        -H "Content-Type: application/json" \
        -d '{"query":"Summarize this article about climate change"}')

    if echo "$response" | grep -qi "SUMMARIZE"; then
        log_pass "SUMMARIZE intent detected"
    else
        log_fail "SUMMARIZE intent not detected"
        if $VERBOSE; then echo "  Response: $response"; fi
    fi

    # 9.7 Web search integration with new intent detection
    log_info "Testing web search triggers on SEARCH intent..."
    cat > /tmp/test_current.json << 'TESTEOF'
{"model":"auto","messages":[{"role":"user","content":"What is the current version of Node.js?"}]}
TESTEOF

    response=$(curl -sf --max-time 180 "$ROUTER_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d @/tmp/test_current.json)

    # Check that we get a response (web search should be triggered)
    if [ -n "$response" ] && echo "$response" | grep -q "choices"; then
        log_pass "Chat with current info query returns response"
    else
        log_fail "Chat with current info query failed"
        if $VERBOSE; then echo "  Response: $response"; fi
    fi

    rm -f /tmp/test_current.json
}

# =============================================================================
# Test 10: Model Indicator Display
# =============================================================================

test_model_indicator() {
    log_section "10. MODEL INDICATOR DISPLAY TESTS"

    if $QUICK_MODE; then
        log_skip "Model indicator tests (quick mode)"
        return
    fi

    # 10.1 Model indicator appears in general query response
    log_info "Testing model indicator in general query..."
    local response
    response=$(curl -sf --max-time 120 "$ROUTER_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{"model":"auto","messages":[{"role":"user","content":"What is 2+2?"}]}')

    local content
    content=$(echo "$response" | jq -r '.choices[0].message.content')

    if echo "$content" | grep -q "Model:.*Intent: general"; then
        log_pass "Model indicator appears in general query"
    else
        log_fail "Model indicator missing in general query"
        if $VERBOSE; then echo "  Content: $content"; fi
    fi

    # 10.2 Correct model shown for coding query
    log_info "Testing correct model for coding query..."
    response=$(curl -sf --max-time 120 "$ROUTER_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{"model":"auto","messages":[{"role":"user","content":"Write a Python hello world"}]}')

    content=$(echo "$response" | jq -r '.choices[0].message.content')

    if echo "$content" | grep -q "qwen2.5-coder" && echo "$content" | grep -q "Intent: coding"; then
        log_pass "Coding query shows coder model"
    else
        log_fail "Coding query does not show coder model"
        if $VERBOSE; then echo "  Content: $content"; fi
    fi

    # 10.3 Correct model shown for search query
    log_info "Testing correct model for search query..."
    response=$(curl -sf --max-time 180 "$ROUTER_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{"model":"auto","messages":[{"role":"user","content":"What are the latest tech news?"}]}')

    content=$(echo "$response" | jq -r '.choices[0].message.content')

    if echo "$content" | grep -q "Intent: search"; then
        log_pass "Search query shows search intent"
    else
        log_fail "Search query does not show search intent"
        if $VERBOSE; then echo "  Content: $content"; fi
    fi

    # 10.4 No indicator when not using auto model
    log_info "Testing no indicator when using specific model..."
    response=$(curl -sf --max-time 120 "$ROUTER_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{"model":"qwen2.5:14b","messages":[{"role":"user","content":"Hello"}]}')

    content=$(echo "$response" | jq -r '.choices[0].message.content')

    if echo "$content" | grep -q "Model:.*Intent:"; then
        log_fail "Model indicator appears when not using auto"
        if $VERBOSE; then echo "  Content: $content"; fi
    else
        log_pass "No indicator when using specific model"
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    echo -e "${BLUE}==============================================================================${NC}"
    echo -e "${BLUE}              AI STACK COMPREHENSIVE TEST SUITE${NC}"
    echo -e "${BLUE}==============================================================================${NC}"

    if $QUICK_MODE; then
        echo -e "${YELLOW}Running in QUICK MODE (skipping LLM-dependent tests)${NC}"
    fi

    test_health_infrastructure
    test_smart_routing
    test_conversation_history
    test_web_search
    test_url_fetching
    test_memory_system
    test_api_compatibility
    test_error_handling
    test_llm_intent_detection
    test_model_indicator

    # Summary
    log_section "TEST SUMMARY"

    echo -e "  ${GREEN}Passed:${NC}  $TESTS_PASSED"
    echo -e "  ${RED}Failed:${NC}  $TESTS_FAILED"
    echo -e "  ${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
    echo ""

    local total=$((TESTS_PASSED + TESTS_FAILED))
    if [ $total -gt 0 ]; then
        local pct=$((TESTS_PASSED * 100 / total))
        echo "  Success Rate: ${pct}%"
    fi
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        return 1
    fi
}

main "$@"
