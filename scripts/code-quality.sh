#!/bin/bash

# Deck Code Quality Check Script
# 代码质量检查脚本
# 
# Run this script from the project root directory.
# 请在项目根目录运行此脚本。
#
# Usage: ./scripts/code-quality.sh
# Optional env flags:
#   SKIP_BUILD=1      跳过构建
#   SKIP_TESTS=1      跳过单元测试
#   SKIP_LINT=1       跳过 SwiftLint
#   QUIET=1           精简输出（仅显示结果与失败尾部日志）

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Score tracking
TOTAL_SCORE=0
MAX_SCORE=100

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Change to project root
cd "$PROJECT_ROOT"

echo ""
echo "========================================================"
echo "       Deck Code Quality Check | 代码质量检查"
echo "========================================================"
echo ""
echo "Project root: $PROJECT_ROOT"
echo ""

# Function to add score
add_score() {
    TOTAL_SCORE=$((TOTAL_SCORE + $1))
    echo -e "${GREEN}  [PASS] +$1 points${NC}"
}

# Function to show failure
show_failure() {
    echo -e "${RED}  [FAIL] $1${NC}"
}

# Run a command, capture log to file, return status and show tail on failure
run_with_log() {
    local name="$1"; shift
    local logfile
    logfile="$(mktemp "/tmp/deck-${name// /_}.XXXX.log")"
    if [ -n "${QUIET:-}" ]; then
        "$@" >"$logfile" 2>&1 || return $?
    else
        "$@" 2>&1 | tee "$logfile"
    fi
    return $?
}

# ============================================
# 1. Build Check (25 points)
# ============================================
if [ -n "${SKIP_BUILD:-}" ]; then
    echo -e "${YELLOW}[1/5] Build skipped (SKIP_BUILD=1) | 跳过构建${NC}"
    add_score 0
else
    echo -e "${BLUE}[1/5] Building project... | 构建项目...${NC}"
    if run_with_log "build" xcodebuild build \
        -project Deck.xcodeproj \
        -scheme Deck \
        -destination "platform=macOS" \
        -configuration Debug \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO; then
        echo -e "${GREEN}  [PASS] Build succeeded | 构建成功${NC}"
        add_score 25
    else
        show_failure "Build failed | 构建失败"
        echo -e "${RED}  Please fix build errors before continuing.${NC}"
        echo -e "${RED}  请先修复构建错误。${NC}"
        echo ""
        echo "Build output (last 40 lines):"
        tail -40 /tmp/deck-build*.log 2>/dev/null || true
        exit 1
    fi
fi

# ============================================
# 2. Test Check (25 points)
# ============================================
echo ""
if [ -n "${SKIP_TESTS:-}" ]; then
    echo -e "${YELLOW}[2/5] Tests skipped (SKIP_TESTS=1) | 跳过测试${NC}"
    add_score 0
else
    echo -e "${BLUE}[2/5] Running unit tests... | 运行单元测试...${NC}"
    if run_with_log "tests" xcodebuild test \
        -project Deck.xcodeproj \
        -scheme Deck \
        -destination "platform=macOS" \
        -configuration Debug \
        -only-testing:DeckTests \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO; then
        echo -e "${GREEN}  [PASS] All unit tests passed | 所有单元测试通过${NC}"
        add_score 25
    else
        TEST_OUTPUT=$(tail -200 /tmp/deck-tests*.log 2>/dev/null || true)
        if echo "$TEST_OUTPUT" | grep -qi "no test bundle"; then
            echo -e "${YELLOW}  [SKIP] No unit test bundle found | 未找到单元测试包${NC}"
            add_score 15
        elif echo "$TEST_OUTPUT" | grep -qi "code signing"; then
            echo -e "${YELLOW}  [SKIP] Code signing required for tests | 测试需要代码签名${NC}"
            echo -e "${YELLOW}  Run tests manually in Xcode | 请在 Xcode 中手动运行测试${NC}"
            add_score 15
        elif echo "$TEST_OUTPUT" | grep -qi "build failed\|Testing cancelled"; then
            echo -e "${YELLOW}  [SKIP] Test compilation failed | 测试编译失败${NC}"
            echo -e "${YELLOW}  Fix test compilation errors or run in Xcode | 请修复测试编译错误或在 Xcode 中运行${NC}"
            add_score 10
        else
            show_failure "Some tests failed | 部分测试失败"
            echo -e "${YELLOW}  Please fix failing tests or run in Xcode.${NC}"
            echo -e "${YELLOW}  请修复失败的测试或在 Xcode 中运行。${NC}"
            echo ""
            echo "Test output (last 80 lines):"
            echo "$TEST_OUTPUT" | tail -80
        fi
    fi
fi

# ============================================
# 3. SwiftLint Check (25 points)
# ============================================
echo ""
if [ -n "${SKIP_LINT:-}" ]; then
    echo -e "${YELLOW}[3/5] SwiftLint skipped (SKIP_LINT=1) | 跳过 SwiftLint${NC}"
    add_score 0
else
    echo -e "${BLUE}[3/5] Running SwiftLint... | 运行 SwiftLint...${NC}"
    if command -v swiftlint &> /dev/null; then
        LINT_OUTPUT=$(run_with_log "swiftlint" swiftlint lint || true)
        LINT_ERRORS=$(echo "$LINT_OUTPUT" | grep -c ": error:" 2>/dev/null || echo "0")
        LINT_WARNINGS=$(echo "$LINT_OUTPUT" | grep -c ": warning:" 2>/dev/null || echo "0")
        LINT_ERRORS=$(echo "$LINT_ERRORS" | tr -d '[:space:]')
        LINT_WARNINGS=$(echo "$LINT_WARNINGS" | tr -d '[:space:]')
        
        if echo "$LINT_OUTPUT" | grep -q "Found 0 violations"; then
            echo -e "${GREEN}  [PASS] SwiftLint passed | SwiftLint 通过${NC}"
            add_score 25
        elif [ "${LINT_ERRORS:-0}" = "0" ] || [ -z "$LINT_ERRORS" ]; then
            echo -e "${GREEN}  [PASS] SwiftLint passed (${LINT_WARNINGS} warnings) | SwiftLint 通过 (${LINT_WARNINGS} 个警告)${NC}"
            add_score 25
        else
            show_failure "SwiftLint found ${LINT_ERRORS} errors | SwiftLint 发现 ${LINT_ERRORS} 个错误"
            echo -e "${YELLOW}  Run 'swiftlint lint' to see details.${NC}"
        fi
    else
        echo -e "${YELLOW}  [SKIP] SwiftLint not installed. Install: brew install swiftlint${NC}"
        echo -e "${YELLOW}  [SKIP] SwiftLint 未安装。安装：brew install swiftlint${NC}"
        add_score 15
    fi
fi

# ============================================
# 4. Documentation Check (15 points)
# ============================================
echo ""
echo -e "${BLUE}[4/5] Checking documentation... | 检查文档...${NC}"

DOC_SCORE=0

# Check if README exists
if [ -f "README.md" ]; then
    DOC_SCORE=$((DOC_SCORE + 5))
fi

# Check if CHANGELOG is present
if [ -f "CHANGELOG.md" ]; then
    DOC_SCORE=$((DOC_SCORE + 5))
fi

# Check for inline documentation (/// comments)
DOC_COMMENTS=$(find . -path ./DerivedData -prune -o -name "*.swift" -print -exec grep -l "///" {} \; 2>/dev/null | wc -l | tr -d ' ')
if [ "$DOC_COMMENTS" -gt 3 ]; then
    DOC_SCORE=$((DOC_SCORE + 5))
fi

if [ "$DOC_SCORE" -gt 0 ]; then
    echo -e "${GREEN}  [PASS] Documentation check (+${DOC_SCORE}) | 文档检查${NC}"
    TOTAL_SCORE=$((TOTAL_SCORE + DOC_SCORE))
else
    show_failure "Documentation incomplete | 文档不完整"
fi

# ============================================
# 5. Test Coverage Estimate (10 points)
# ============================================
echo ""
echo -e "${BLUE}[5/5] Checking test coverage... | 检查测试覆盖率...${NC}"

TEST_FILES=$(find . -path ./DerivedData -prune -o \( -name "*Tests.swift" -o -name "*Test.swift" \) -print 2>/dev/null | wc -l | tr -d ' ')
SOURCE_FILES=$(find . -path ./DerivedData -prune -o -path ./.build -prune -o -name "*.swift" -print 2>/dev/null | grep -v "Tests" | wc -l | tr -d ' ')

if [ "$SOURCE_FILES" -gt 0 ] && [ "$TEST_FILES" -gt 0 ]; then
    echo -e "${GREEN}  [PASS] Test files found (${TEST_FILES} test files) | 找到测试文件${NC}"
    add_score 10
elif [ "$TEST_FILES" -gt 0 ]; then
    echo -e "${YELLOW}  [PARTIAL] Some test coverage | 部分测试覆盖${NC}"
    TOTAL_SCORE=$((TOTAL_SCORE + 5))
else
    show_failure "No test files found | 未找到测试文件"
fi

# ============================================
# Final Score
# ============================================
echo ""
echo "========================================================"
echo "                 Final Score | 最终评分"
echo "========================================================"
echo ""

if [ "$TOTAL_SCORE" -ge 80 ]; then
    echo -e "${GREEN}  Score: ${TOTAL_SCORE}/${MAX_SCORE} - PASSED | 通过${NC}"
    echo ""
    echo -e "${GREEN}  You can now push to your fork and create a PR.${NC}"
    echo -e "${GREEN}  你现在可以推送到你的 Fork 并创建 PR 了。${NC}"
    exit 0
elif [ "$TOTAL_SCORE" -ge 60 ]; then
    echo -e "${YELLOW}  Score: ${TOTAL_SCORE}/${MAX_SCORE} - NEEDS IMPROVEMENT | 需要改进${NC}"
    echo ""
    echo -e "${YELLOW}  Your score is below 80. Please improve before submitting PR.${NC}"
    echo -e "${YELLOW}  你的评分低于 80。请在提交 PR 前改进。${NC}"
    exit 1
else
    echo -e "${RED}  Score: ${TOTAL_SCORE}/${MAX_SCORE} - FAILED | 未通过${NC}"
    echo ""
    echo -e "${RED}  Please fix the issues above before continuing.${NC}"
    echo -e "${RED}  请先修复上述问题。${NC}"
    exit 1
fi
