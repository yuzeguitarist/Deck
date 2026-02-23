#!/bin/bash

# Deck Code Quality Check Script
# 代码质量检查脚本
#
# Usage:
#   ./scripts/code-quality.sh [options]
#
# Common options:
#   --fast              快速模式（默认跳过测试）
#   --ci                精简日志输出
#   --skip-build        跳过构建
#   --skip-tests        跳过测试
#   --skip-lint         跳过 SwiftLint
#   --project <path>    指定 .xcodeproj
#   --scheme <name>     指定 scheme
#   --strict            严格模式（有警告也算未通过）
#   -h, --help          查看帮助
#
# Env (兼容旧用法):
#   SKIP_BUILD=1
#   SKIP_TESTS=1
#   SKIP_LINT=1
#   QUIET=1
#   STRICT=1
#   PROJECT_FILE=Deck.xcodeproj
#   SCHEME=Deck
#   BUILD_CONFIGURATION=Debug
#   DESTINATION='platform=macOS'

set -Eeuo pipefail

usage() {
    cat <<'EOF'
Deck Code Quality Check | 代码质量检查

用法:
  ./scripts/code-quality.sh [options]

参数:
  --fast              快速模式（默认跳过测试）
  --ci                精简输出（日志写入文件）
  --skip-build        跳过构建
  --skip-tests        跳过测试
  --skip-lint         跳过 SwiftLint
  --project <path>    指定 .xcodeproj（默认自动检测）
  --scheme <name>     指定 scheme（默认自动检测）
  --strict            严格模式（有 WARN 也失败）
  --no-color          关闭彩色输出
  -h, --help          显示帮助

示例:
  ./scripts/code-quality.sh
  ./scripts/code-quality.sh --fast
  QUIET=1 ./scripts/code-quality.sh --ci
EOF
}

normalize_flag() {
    case "${1:-}" in
        1|true|TRUE|True|yes|YES|on|ON) echo "1" ;;
        0|false|FALSE|False|no|NO|off|OFF|'') echo "0" ;;
        *) echo "1" ;;
    esac
}

is_on() {
    [ "${1:-0}" = "1" ]
}

safe_tail() {
    local file="${1:-}"
    local lines="${2:-40}"
    if [ -n "$file" ] && [ -f "$file" ]; then
        tail -n "$lines" "$file"
    fi
}

list_swift_files() {
    find . \
        \( -path "./.git" -o -path "./DerivedData" -o -path "./.build" \) -prune -o \
        -name "*.swift" -print
}

list_test_files() {
    find . \
        \( -path "./.git" -o -path "./DerivedData" -o -path "./.build" \) -prune -o \
        \( -name "*Tests.swift" -o -name "*Test.swift" \) -print
}

list_source_files_no_tests() {
    find . \
        \( -path "./.git" -o -path "./DerivedData" -o -path "./.build" \) -prune -o \
        -name "*.swift" ! -name "*Tests.swift" ! -name "*Test.swift" -print
}

# Defaults (env-compatible)
MODE="${MODE:-full}"
SKIP_BUILD="$(normalize_flag "${SKIP_BUILD:-0}")"
SKIP_TESTS="$(normalize_flag "${SKIP_TESTS:-0}")"
SKIP_LINT="$(normalize_flag "${SKIP_LINT:-0}")"
QUIET="$(normalize_flag "${QUIET:-0}")"
STRICT="$(normalize_flag "${STRICT:-0}")"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-Debug}"
DESTINATION="${DESTINATION:-platform=macOS}"
PROJECT_FILE="${PROJECT_FILE:-}"
SCHEME="${SCHEME:-}"
MIN_PASS_SCORE="${MIN_PASS_SCORE:-80}"
MIN_WARN_SCORE="${MIN_WARN_SCORE:-60}"
NO_COLOR="${NO_COLOR:-0}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --fast)
            MODE="fast"
            shift
            ;;
        --ci)
            QUIET="1"
            shift
            ;;
        --skip-build)
            SKIP_BUILD="1"
            shift
            ;;
        --skip-tests)
            SKIP_TESTS="1"
            shift
            ;;
        --skip-lint)
            SKIP_LINT="1"
            shift
            ;;
        --project)
            if [ "$#" -lt 2 ]; then
                echo "Missing value for --project"
                exit 2
            fi
            PROJECT_FILE="$2"
            shift 2
            ;;
        --scheme)
            if [ "$#" -lt 2 ]; then
                echo "Missing value for --scheme"
                exit 2
            fi
            SCHEME="$2"
            shift 2
            ;;
        --strict)
            STRICT="1"
            shift
            ;;
        --no-color)
            NO_COLOR="1"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo ""
            usage
            exit 2
            ;;
    esac
done

case "$MODE" in
    fast|FAST|Fast)
        MODE="fast"
        ;;
    full|FULL|Full|'')
        MODE="full"
        ;;
    *)
        echo "Unknown MODE: $MODE (supported: full, fast)"
        exit 2
        ;;
esac

if [ "$MODE" = "fast" ]; then
    SKIP_TESTS="1"
fi

# CI 下默认精简输出
if [ -n "${CI:-}" ] && [ "$QUIET" = "0" ]; then
    QUIET="1"
fi

# Colors
if [ -t 1 ] && [ "$NO_COLOR" = "0" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Score tracking
TOTAL_SCORE=0
MAX_SCORE=100
FAIL_COUNT=0
WARN_COUNT=0

# Step summary tracking
STEP_NAMES=()
STEP_STATES=()
STEP_POINTS=()
STEP_NOTES=()
STEP_LOGS=()

add_score() {
    local points="$1"
    TOTAL_SCORE=$((TOTAL_SCORE + points))
}

record_step() {
    local name="$1"
    local state="$2"
    local points="$3"
    local note="$4"
    local log="${5:--}"
    STEP_NAMES+=("$name")
    STEP_STATES+=("$state")
    STEP_POINTS+=("$points")
    STEP_NOTES+=("$note")
    STEP_LOGS+=("$log")
    if [ "$state" = "FAIL" ]; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
    elif [ "$state" = "WARN" ]; then
        WARN_COUNT=$((WARN_COUNT + 1))
    fi
}

show_failure() {
    echo -e "${RED}  [FAIL] $1${NC}"
}

show_warn() {
    echo -e "${YELLOW}  [WARN] $1${NC}"
}

show_pass() {
    echo -e "${GREEN}  [PASS] $1${NC}"
}

LAST_LOG=""
LOG_DIR="$(mktemp -d "/tmp/deck-quality.XXXXXX")"

run_with_log() {
    local name="$1"
    shift
    local safe_name
    safe_name="$(echo "$name" | tr ' /' '__' | tr -cd '[:alnum:]_-')"
    LAST_LOG="$LOG_DIR/${safe_name}.log"
    if [ "$QUIET" = "1" ]; then
        "$@" >"$LAST_LOG" 2>&1
    else
        "$@" 2>&1 | tee "$LAST_LOG"
    fi
}

detect_project_file() {
    if [ -n "$PROJECT_FILE" ]; then
        if [ -d "$PROJECT_FILE" ]; then
            return 0
        fi
        return 1
    fi

    if [ -d "Deck.xcodeproj" ]; then
        PROJECT_FILE="Deck.xcodeproj"
        return 0
    fi

    local first_project
    first_project="$(find . -maxdepth 2 -type d -name "*.xcodeproj" | head -n 1 || true)"
    if [ -n "$first_project" ]; then
        PROJECT_FILE="${first_project#./}"
        return 0
    fi

    return 1
}

detect_scheme() {
    if [ -n "$SCHEME" ]; then
        return 0
    fi
    SCHEME="$(basename "${PROJECT_FILE}" .xcodeproj)"
    return 0
}

resolve_scheme_from_xcode() {
    local list_log="$LOG_DIR/xcodebuild-list.log"
    if ! xcodebuild -list -project "$PROJECT_FILE" >"$list_log" 2>&1; then
        return 1
    fi

    if grep -Eq "^[[:space:]]+${SCHEME}\$" "$list_log"; then
        return 0
    fi

    local first_scheme
    first_scheme="$(awk '
        /^Schemes:/ { in_schemes=1; next }
        in_schemes && NF {
            gsub(/^[[:space:]]+/, "", $0)
            print $0
            exit
        }
    ' "$list_log")"

    if [ -n "$first_scheme" ]; then
        SCHEME="$first_scheme"
        return 0
    fi
    return 1
}

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

PROJECT_READY=1
if ! detect_project_file; then
    PROJECT_READY=0
fi
if [ "$PROJECT_READY" -eq 1 ]; then
    detect_scheme
fi

# 如果需要构建/测试，尽量先自动校准 scheme
if [ "$PROJECT_READY" -eq 1 ] && { [ "$SKIP_BUILD" = "0" ] || [ "$SKIP_TESTS" = "0" ]; }; then
    if command -v xcodebuild >/dev/null 2>&1; then
        resolve_scheme_from_xcode || true
    fi
fi

echo ""
echo "========================================================"
echo "       Deck Code Quality Check | 代码质量检查"
echo "========================================================"
echo ""
echo "Project root: $PROJECT_ROOT"
if [ "$PROJECT_READY" -eq 1 ]; then
    echo "Project file: $PROJECT_FILE"
    echo "Scheme: $SCHEME"
else
    echo "Project file: (not found)"
fi
echo "Mode: $MODE"
echo "Quiet: $QUIET"
echo "Logs: $LOG_DIR"
echo ""

# ============================================
# 1. Build Check (25 points)
# ============================================
BUILD_FAILED=0
echo -e "${BLUE}[1/5] Building project... | 构建项目...${NC}"

if [ "$SKIP_BUILD" = "1" ]; then
    show_warn "Build skipped (SKIP_BUILD=1) | 已跳过构建"
    record_step "Build" "SKIP" 0 "手动跳过" "-"
elif [ "$PROJECT_READY" -eq 0 ]; then
    show_failure "No .xcodeproj found | 未找到 .xcodeproj"
    record_step "Build" "FAIL" 0 "项目文件缺失" "-"
    BUILD_FAILED=1
elif ! command -v xcodebuild >/dev/null 2>&1; then
    show_failure "xcodebuild not found | 系统缺少 xcodebuild"
    record_step "Build" "FAIL" 0 "环境缺少 xcodebuild" "-"
    BUILD_FAILED=1
else
    if run_with_log "build" xcodebuild build \
        -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -destination "$DESTINATION" \
        -configuration "$BUILD_CONFIGURATION" \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO; then
        show_pass "Build succeeded | 构建成功 (+25)"
        add_score 25
        record_step "Build" "PASS" 25 "构建通过" "$LAST_LOG"
    else
        show_failure "Build failed | 构建失败"
        echo "  Build output (last 50 lines):"
        safe_tail "$LAST_LOG" 50
        record_step "Build" "FAIL" 0 "构建失败" "$LAST_LOG"
        BUILD_FAILED=1
    fi
fi

# ============================================
# 2. Test Check (25 points)
# ============================================
echo ""
echo -e "${BLUE}[2/5] Running unit tests... | 运行单元测试...${NC}"

if [ "$SKIP_TESTS" = "1" ]; then
    show_warn "Tests skipped (SKIP_TESTS=1) | 已跳过测试"
    record_step "Tests" "SKIP" 0 "手动跳过" "-"
elif [ "$PROJECT_READY" -eq 0 ]; then
    show_failure "Cannot run tests without project file | 缺少项目文件，无法测试"
    record_step "Tests" "FAIL" 0 "项目文件缺失" "-"
elif [ "$BUILD_FAILED" -eq 1 ]; then
    show_warn "Build failed earlier, tests skipped | 构建失败，测试已跳过"
    record_step "Tests" "WARN" 0 "构建失败后自动跳过测试" "-"
elif ! command -v xcodebuild >/dev/null 2>&1; then
    show_failure "xcodebuild not found | 系统缺少 xcodebuild"
    record_step "Tests" "FAIL" 0 "环境缺少 xcodebuild" "-"
else
    if run_with_log "tests" xcodebuild test \
        -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -destination "$DESTINATION" \
        -configuration "$BUILD_CONFIGURATION" \
        -only-testing:DeckTests \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO; then
        show_pass "All unit tests passed | 单元测试通过 (+25)"
        add_score 25
        record_step "Tests" "PASS" 25 "测试通过" "$LAST_LOG"
    else
        if grep -qi "no test bundle\|No tests were executed" "$LAST_LOG"; then
            show_warn "No test bundle found | 未找到测试包 (+15)"
            add_score 15
            record_step "Tests" "WARN" 15 "未找到测试包" "$LAST_LOG"
        elif grep -qi "code signing" "$LAST_LOG"; then
            show_warn "Code signing blocked tests | 签名问题导致测试未跑 (+15)"
            add_score 15
            record_step "Tests" "WARN" 15 "签名问题" "$LAST_LOG"
        elif grep -qi "build failed\|Testing cancelled" "$LAST_LOG"; then
            show_warn "Test build failed | 测试编译失败 (+10)"
            add_score 10
            record_step "Tests" "WARN" 10 "测试编译失败" "$LAST_LOG"
        else
            show_failure "Some tests failed | 有测试失败"
            echo "  Test output (last 80 lines):"
            safe_tail "$LAST_LOG" 80
            record_step "Tests" "FAIL" 0 "测试失败" "$LAST_LOG"
        fi
    fi
fi

# ============================================
# 3. SwiftLint Check (25 points)
# ============================================
echo ""
echo -e "${BLUE}[3/5] Running SwiftLint... | 运行 SwiftLint...${NC}"

if [ "$SKIP_LINT" = "1" ]; then
    show_warn "SwiftLint skipped (SKIP_LINT=1) | 已跳过 SwiftLint"
    record_step "SwiftLint" "SKIP" 0 "手动跳过" "-"
elif ! command -v swiftlint >/dev/null 2>&1; then
    show_warn "SwiftLint not installed. Install: brew install swiftlint | 未安装 SwiftLint (+15)"
    add_score 15
    record_step "SwiftLint" "WARN" 15 "未安装 SwiftLint" "-"
else
    if run_with_log "swiftlint" swiftlint lint; then
        LINT_WARNINGS="$(grep -c ": warning:" "$LAST_LOG" 2>/dev/null || true)"
        LINT_ERRORS="$(grep -c ": error:" "$LAST_LOG" 2>/dev/null || true)"
        LINT_WARNINGS="$(echo "$LINT_WARNINGS" | tr -d '[:space:]')"
        LINT_ERRORS="$(echo "$LINT_ERRORS" | tr -d '[:space:]')"
        if [ "${LINT_ERRORS:-0}" = "0" ]; then
            show_pass "SwiftLint passed (warnings: ${LINT_WARNINGS:-0}) | SwiftLint 通过 (+25)"
            add_score 25
            record_step "SwiftLint" "PASS" 25 "warnings=${LINT_WARNINGS:-0}" "$LAST_LOG"
        else
            show_failure "SwiftLint has errors (${LINT_ERRORS}) | SwiftLint 有错误"
            record_step "SwiftLint" "FAIL" 0 "errors=${LINT_ERRORS}" "$LAST_LOG"
        fi
    else
        LINT_WARNINGS="$(grep -c ": warning:" "$LAST_LOG" 2>/dev/null || true)"
        LINT_ERRORS="$(grep -c ": error:" "$LAST_LOG" 2>/dev/null || true)"
        LINT_WARNINGS="$(echo "$LINT_WARNINGS" | tr -d '[:space:]')"
        LINT_ERRORS="$(echo "$LINT_ERRORS" | tr -d '[:space:]')"
        if [ "${LINT_ERRORS:-0}" = "0" ] && [ "${LINT_WARNINGS:-0}" != "0" ]; then
            show_warn "SwiftLint warnings in strict config (${LINT_WARNINGS}) | 严格模式下警告导致失败 (+20)"
            add_score 20
            record_step "SwiftLint" "WARN" 20 "warnings=${LINT_WARNINGS}" "$LAST_LOG"
        else
            show_failure "SwiftLint failed (errors: ${LINT_ERRORS:-0}, warnings: ${LINT_WARNINGS:-0}) | SwiftLint 未通过"
            echo "  SwiftLint output (last 60 lines):"
            safe_tail "$LAST_LOG" 60
            record_step "SwiftLint" "FAIL" 0 "errors=${LINT_ERRORS:-0}, warnings=${LINT_WARNINGS:-0}" "$LAST_LOG"
        fi
    fi
fi

# ============================================
# 4. Documentation Check (15 points)
# ============================================
echo ""
echo -e "${BLUE}[4/5] Checking documentation... | 检查文档...${NC}"

DOC_SCORE=0
DOC_NOTE="README/CHANGELOG/注释占比"

if [ -f "README.md" ]; then
    DOC_SCORE=$((DOC_SCORE + 4))
fi
if [ -f "CHANGELOG.md" ]; then
    DOC_SCORE=$((DOC_SCORE + 4))
fi

SWIFT_TOTAL="$(list_swift_files | wc -l | tr -d '[:space:]')"
DOC_COMMENTED=0
if [ "${SWIFT_TOTAL:-0}" -gt 0 ]; then
    while IFS= read -r swift_file; do
        if [ -n "$swift_file" ] && grep -q "///" "$swift_file"; then
            DOC_COMMENTED=$((DOC_COMMENTED + 1))
        fi
    done < <(list_swift_files)
    DOC_RATIO=$((DOC_COMMENTED * 100 / SWIFT_TOTAL))
else
    DOC_RATIO=0
fi

if [ "${DOC_RATIO:-0}" -ge 20 ]; then
    DOC_SCORE=$((DOC_SCORE + 7))
elif [ "${DOC_RATIO:-0}" -ge 10 ]; then
    DOC_SCORE=$((DOC_SCORE + 5))
elif [ "${DOC_RATIO:-0}" -gt 0 ]; then
    DOC_SCORE=$((DOC_SCORE + 3))
fi

if [ "$DOC_SCORE" -ge 10 ]; then
    show_pass "Documentation good (+${DOC_SCORE}/15, doc ratio ${DOC_RATIO}%) | 文档较完整"
    add_score "$DOC_SCORE"
    record_step "Docs" "PASS" "$DOC_SCORE" "${DOC_NOTE}, ratio=${DOC_RATIO}%" "-"
elif [ "$DOC_SCORE" -gt 0 ]; then
    show_warn "Documentation partial (+${DOC_SCORE}/15, doc ratio ${DOC_RATIO}%) | 文档部分缺失"
    add_score "$DOC_SCORE"
    record_step "Docs" "WARN" "$DOC_SCORE" "${DOC_NOTE}, ratio=${DOC_RATIO}%" "-"
else
    show_failure "Documentation incomplete | 文档不完整"
    record_step "Docs" "FAIL" 0 "${DOC_NOTE}, ratio=${DOC_RATIO}%" "-"
fi

# ============================================
# 5. Test Coverage Estimate (10 points)
# ============================================
echo ""
echo -e "${BLUE}[5/5] Estimating test coverage... | 估算测试覆盖...${NC}"

TEST_FILES="$(list_test_files | wc -l | tr -d '[:space:]')"
SOURCE_FILES="$(list_source_files_no_tests | wc -l | tr -d '[:space:]')"

if [ "${SOURCE_FILES:-0}" -gt 0 ] && [ "${TEST_FILES:-0}" -gt 0 ]; then
    TEST_RATIO=$((TEST_FILES * 100 / SOURCE_FILES))
else
    TEST_RATIO=0
fi

if [ "${TEST_RATIO:-0}" -ge 20 ]; then
    show_pass "Test coverage estimate looks good (${TEST_FILES}/${SOURCE_FILES}, ${TEST_RATIO}%) | 估算覆盖较好 (+10)"
    add_score 10
    record_step "Coverage" "PASS" 10 "tests=${TEST_FILES}, sources=${SOURCE_FILES}, ratio=${TEST_RATIO}%" "-"
elif [ "${TEST_RATIO:-0}" -ge 12 ]; then
    show_warn "Coverage is okay but can improve (${TEST_RATIO}%) | 覆盖率一般 (+7)"
    add_score 7
    record_step "Coverage" "WARN" 7 "tests=${TEST_FILES}, sources=${SOURCE_FILES}, ratio=${TEST_RATIO}%" "-"
elif [ "${TEST_RATIO:-0}" -ge 6 ]; then
    show_warn "Coverage is low (${TEST_RATIO}%) | 覆盖率偏低 (+5)"
    add_score 5
    record_step "Coverage" "WARN" 5 "tests=${TEST_FILES}, sources=${SOURCE_FILES}, ratio=${TEST_RATIO}%" "-"
elif [ "${TEST_FILES:-0}" -gt 0 ]; then
    show_warn "Some tests found but too few (${TEST_RATIO}%) | 有测试但偏少 (+3)"
    add_score 3
    record_step "Coverage" "WARN" 3 "tests=${TEST_FILES}, sources=${SOURCE_FILES}, ratio=${TEST_RATIO}%" "-"
else
    show_failure "No test files found | 未找到测试文件"
    record_step "Coverage" "FAIL" 0 "tests=${TEST_FILES}, sources=${SOURCE_FILES}" "-"
fi

# ============================================
# Step Summary
# ============================================
echo ""
echo "========================================================"
echo "               Step Summary | 步骤汇总"
echo "========================================================"
echo ""

i=0
while [ "$i" -lt "${#STEP_NAMES[@]}" ]; do
    step_name="${STEP_NAMES[$i]}"
    step_state="${STEP_STATES[$i]}"
    step_points="${STEP_POINTS[$i]}"
    step_note="${STEP_NOTES[$i]}"
    step_log="${STEP_LOGS[$i]}"

    state_color="$NC"
    if [ "$step_state" = "PASS" ]; then
        state_color="$GREEN"
    elif [ "$step_state" = "WARN" ] || [ "$step_state" = "SKIP" ]; then
        state_color="$YELLOW"
    elif [ "$step_state" = "FAIL" ]; then
        state_color="$RED"
    fi

    echo -e "  - ${step_name}: ${state_color}${step_state}${NC} (+${step_points}) | ${step_note}"
    if [ "$step_log" != "-" ]; then
        echo "    log: $step_log"
    fi
    i=$((i + 1))
done

# ============================================
# Final Score
# ============================================
echo ""
echo "========================================================"
echo "                 Final Score | 最终评分"
echo "========================================================"
echo ""

STRICT_BLOCK=0
if [ "$STRICT" = "1" ] && [ "$WARN_COUNT" -gt 0 ]; then
    STRICT_BLOCK=1
fi

if [ "$FAIL_COUNT" -eq 0 ] && [ "$TOTAL_SCORE" -ge "$MIN_PASS_SCORE" ] && [ "$STRICT_BLOCK" -eq 0 ]; then
    echo -e "${GREEN}  Score: ${TOTAL_SCORE}/${MAX_SCORE} - PASSED | 通过${NC}"
    echo -e "${GREEN}  Logs: ${LOG_DIR}${NC}"
    echo ""
    echo -e "${GREEN}  You can now push to your fork and create a PR.${NC}"
    echo -e "${GREEN}  你现在可以推送到你的 Fork 并创建 PR 了。${NC}"
    exit 0
elif [ "$FAIL_COUNT" -eq 0 ] && [ "$TOTAL_SCORE" -ge "$MIN_WARN_SCORE" ] && [ "$STRICT_BLOCK" -eq 0 ]; then
    echo -e "${YELLOW}  Score: ${TOTAL_SCORE}/${MAX_SCORE} - NEEDS IMPROVEMENT | 需要改进${NC}"
    echo -e "${YELLOW}  Logs: ${LOG_DIR}${NC}"
    echo ""
    echo -e "${YELLOW}  Quality is close, but still below the pass line.${NC}"
    echo -e "${YELLOW}  距离通过很接近，但还需要再优化一下。${NC}"
    exit 1
else
    if [ "$STRICT_BLOCK" -eq 1 ]; then
        echo -e "${RED}  Strict mode blocked because WARN exists | 严格模式下有警告即失败${NC}"
    fi
    echo -e "${RED}  Score: ${TOTAL_SCORE}/${MAX_SCORE} - FAILED | 未通过${NC}"
    echo -e "${RED}  Logs: ${LOG_DIR}${NC}"
    echo ""
    echo -e "${RED}  Please fix the issues above before continuing.${NC}"
    echo -e "${RED}  请先修复上述问题。${NC}"
    exit 1
fi
