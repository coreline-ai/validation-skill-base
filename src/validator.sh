#!/bin/bash
# ~/.claude/skill-validator/validator.sh
#
# 스킬 검증 메인 로직
# 스킬을 다운로드하고 정적 분석을 수행한 뒤 PASS/FAIL를 결정

set -euo pipefail

# =============================================================================
# 설정
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPROVALS_DIR="$HOME/.claude/skill-approvals"
ANALYZER="$SCRIPT_DIR/static_analyzer.py"
SIGNING_KEY="$APPROVALS_DIR/.signing-key"
DEFAULT_SKILLS_CLI_VERSION="1.4.6"
SKILLS_CLI_VERSION="${SKILLS_CLI_VERSION:-$DEFAULT_SKILLS_CLI_VERSION}"
SKILLS_CLI_PACKAGE="skills@${SKILLS_CLI_VERSION}"
SKILLS_CLI_TARBALL="${SKILLS_CLI_TARBALL:-}"
SKILLS_CLI_TARBALL_SHA256="${SKILLS_CLI_TARBALL_SHA256:-}"

# 기본 모드: standard
VALIDATION_MODE="${VALIDATION_MODE:-standard}"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# 로그 함수
# =============================================================================

log_info() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*" >&2; }
log_step() { echo -e "${BLUE}[→]${NC} $*"; }
log_header() { echo -e "${CYAN}══${NC} $* ${CYAN}══${NC}"; }

validate_skills_cli_version() {
    [[ "$SKILLS_CLI_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]
}

sha256_file() {
    local target="$1"

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$target" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$target" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 -r "$target" | awk '{print $1}'
    else
        log_error "No SHA-256 utility found (sha256sum, shasum, or openssl required)"
        return 1
    fi
}

run_skills_cli() {
    if [ -n "$SKILLS_CLI_TARBALL" ]; then
        if [ ! -f "$SKILLS_CLI_TARBALL" ]; then
            log_error "SKILLS_CLI_TARBALL not found: $SKILLS_CLI_TARBALL"
            return 1
        fi

        if [ -n "$SKILLS_CLI_TARBALL_SHA256" ]; then
            local actual_sha256
            actual_sha256=$(sha256_file "$SKILLS_CLI_TARBALL") || return 1

            if [ "$actual_sha256" != "$SKILLS_CLI_TARBALL_SHA256" ]; then
                log_error "SKILLS_CLI_TARBALL_SHA256 mismatch"
                log_error "Expected: $SKILLS_CLI_TARBALL_SHA256"
                log_error "Actual:   $actual_sha256"
                return 1
            fi
        fi

        npx --yes --package "$SKILLS_CLI_TARBALL" skills "$@"
        return $?
    fi

    if ! validate_skills_cli_version; then
        log_error "Invalid SKILLS_CLI_VERSION: $SKILLS_CLI_VERSION"
        log_error "Use an exact semver such as ${DEFAULT_SKILLS_CLI_VERSION}, not tags like 'latest'."
        return 1
    fi

    npx --yes --package "$SKILLS_CLI_PACKAGE" skills "$@"
}

# =============================================================================
# 유틸리티 함수
# =============================================================================

# SHA-256 해시 생성
sha256_hex() {
    local data="$1"

    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$data" | sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        printf '%s' "$data" | shasum -a 256 | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        printf '%s' "$data" | openssl dgst -sha256 -r | awk '{print $1}'
    else
        log_error "No SHA-256 utility found (sha256sum, shasum, or openssl required)"
        return 1
    fi
}

# 서명용 JSON을 안정적으로 직렬화
canonicalize_json_file() {
    local json_file="$1"
    jq -Sc 'del(.signature)' "$json_file" 2>/dev/null
}

# 파일 수정 시각 조회
file_mtime() {
    local target="$1"

    if stat -f %m "$target" >/dev/null 2>&1; then
        stat -f %m "$target"
    else
        stat -c %Y "$target"
    fi
}

create_temp_json() {
    mktemp "${TMPDIR:-/tmp}/skill-validation.XXXXXX.json"
}

resolve_path() {
    local path="$1"

    case "$path" in
        "~/"*)
            path="$HOME/${path#"~/"}"
            ;;
    esac

    if [ -d "$path" ]; then
        path=$(cd "$path" 2>/dev/null && pwd -P) || true
    elif [ -e "$path" ]; then
        local parent_dir
        parent_dir=$(cd "$(dirname "$path")" 2>/dev/null && pwd -P) || true
        if [ -n "${parent_dir:-}" ]; then
            path="$parent_dir/$(basename "$path")"
        fi
    fi

    printf '%s' "$path"
}

# 서명 키 생성 또는 로드
get_or_create_signing_key() {
    if [ ! -f "$SIGNING_KEY" ]; then
        mkdir -p "$APPROVALS_DIR"
        # 랜덤 32바이트 키 생성 (hex로 인코딩)
        openssl rand -hex 32 > "$SIGNING_KEY" 2>/dev/null || {
            # openssl 없으면 SHA-256 기반 대안
            sha256_hex "$(hostname)_$(date +%s)_$$" > "$SIGNING_KEY"
        }
        chmod 600 "$SIGNING_KEY" 2>/dev/null || true
    fi
    cat "$SIGNING_KEY"
}

# 캐시 서명 생성
sign_cache() {
    local data="$1"

    local key
    key=$(get_or_create_signing_key)

    # HMAC-SHA256 서명 생성 (openssl 있으면)
    if command -v openssl &> /dev/null; then
        echo -n "$data" | openssl dgst -sha256 -hmac "$key" | awk '{print $2}'
    else
        # openssl 없으면 간단한 해시
        sha256_hex "${data}${key}"
    fi
}

# 캐시 서명 검증
verify_cache_signature() {
    local cache_file="$1"
    local stored_signature
    local computed_signature

    # 저장된 서명 읽기
    stored_signature=$(jq -r '.signature // empty' "$cache_file" 2>/dev/null)

    if [ -z "$stored_signature" ] || [ "$stored_signature" = "null" ]; then
        return 1  # 서명 없음 (구버전 캐시)
    fi

    # 서명을 제외한 페이로드로 서명 재계산
    local data
    data=$(canonicalize_json_file "$cache_file")

    if [ -z "$data" ]; then
        return 1  # JSON 파싱 실패
    fi

    computed_signature=$(sign_cache "$data")

    if [ "$computed_signature" = "$stored_signature" ]; then
        return 0  # 서명 유효
    else
        log_warn "Cache signature verification failed - cache may be tampered"
        return 1  # 서명 불일치
    fi
}

# 스킬 경로 파싱
parse_skill_spec() {
    local spec="$1"

    # 형식: username/repo/skill-path 또는 repo/skill-path
    if [[ "$spec" =~ ^([^/]+)/([^/]+)/(.+)$ ]]; then
        REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        SKILL_PATH="${BASH_REMATCH[3]}"
    elif [[ "$spec" =~ ^([^/]+)/(.+)$ ]]; then
        # 기본 저장소: mattpocock/skills
        REPO="mattpocock/skills"
        SKILL_PATH="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    else
        log_error "Invalid skill specification: $spec"
        log_error "Expected format: username/repo/skill-path"
        exit 1
    fi

    # 스킬 해시 생성 (캐시 키로 사용)
    SKILL_HASH=$(sha256_hex "${REPO}/${SKILL_PATH}")
}

# 캐시 확인
check_cache() {
    local cache_file="$APPROVALS_DIR/$SKILL_HASH.json"

    if [ ! -f "$cache_file" ]; then
        return 1  # 캐시 미스
    fi

    # 서명 검증
    if ! verify_cache_signature "$cache_file"; then
        log_warn "Cache integrity check failed - re-validating..."
        return 1  # 캐시 무결성 실패
    fi

    # 캐시 만료 확인 (30일)
    local cache_time
    cache_time=$(file_mtime "$cache_file")

    local current_time=$(date +%s)
    local cache_age=$(( (current_time - cache_time) / 86400 ))

    if [ $cache_age -lt 30 ]; then
        log_info "✓ Using cached validation (validated ${cache_age} days ago)"
        return 0  # 캐시 유효
    fi

    log_warn "Cache expired (${cache_age} days old), re-validating..."
    return 1  # 캐시 만료
}

# 스킬 다운로드
download_skill() {
    local work_dir="$1"
    local repo_url="https://github.com/${REPO}.git"

    # 임시 디렉토리 생성
    mkdir -p "$work_dir"

    # Git sparse clone (속도 최적화)
    if ! git clone --depth 1 --quiet --filter=blob:none --sparse \
            "$repo_url" \
            "$work_dir/repo" 2>/dev/null; then
        log_error "Failed to clone repository: ${REPO}" >&2
        return 1
    fi

    # Sparse checkout으로 필요한 부분만 체크아웃
    if ! git -C "$work_dir/repo" sparse-checkout set "$SKILL_PATH" 2>/dev/null; then
        log_error "Skill path not found: ${SKILL_PATH}" >&2
        return 1
    fi

    local skill_dir="$work_dir/repo/$SKILL_PATH"

    # SKILL.md 존재 확인
    if [ ! -f "$skill_dir/SKILL.md" ]; then
        log_error "SKILL.md not found in: ${SKILL_PATH}" >&2
        return 1
    fi

    # 결과 출력 (stderr로 로그가 이미 나감)
    echo "$skill_dir"
}

# 정적 분석 실행
run_static_analysis() {
    local skill_dir="$1"
    local report_file="$2"

    # Python 버전 확인
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 not found" >&2
        return 1
    fi

    # 정적 분석기 실행
    local analyzer_status=0
    python3 "$ANALYZER" \
        --input "$skill_dir" \
        --output "$report_file" \
        --patterns "$PATTERNS_FILE" >/dev/null 2>&1 || analyzer_status=$?

    if [ ! -f "$report_file" ]; then
        log_error "Static analysis failed" >&2
        return 1
    fi

    # 결과 확인
    local status
    status=$(jq -r '.status' "$report_file" 2>/dev/null || echo "UNKNOWN")

    if [ "$status" = "UNKNOWN" ]; then
        log_error "Static analysis failed" >&2
        return 1
    fi

    if [ "$status" = "FAIL" ]; then
        local critical
        local high
        local medium
        local low
        critical=$(jq -r '.summary.critical // 0' "$report_file" 2>/dev/null || echo 0)
        high=$(jq -r '.summary.high // 0' "$report_file" 2>/dev/null || echo 0)
        medium=$(jq -r '.summary.medium // 0' "$report_file" 2>/dev/null || echo 0)
        low=$(jq -r '.summary.low // 0' "$report_file" 2>/dev/null || echo 0)

        log_error "Static analysis failed validation thresholds:" >&2
        echo "" >&2
        echo "  CRITICAL: $critical" >&2
        echo "  HIGH: $high" >&2
        echo "  MEDIUM: $medium" >&2
        echo "  LOW: $low" >&2
        echo "" >&2

        if [ "$critical" -gt 0 ] || [ "$high" -gt 0 ] || [ "$medium" -gt 0 ]; then
            jq -r '.issues[]
                   | select(.severity == "CRITICAL" or .severity == "HIGH" or .severity == "MEDIUM")
                   | "\(.severity): \(.description) (line \(.line))"' "$report_file" 2>/dev/null >&2 | head -20
            echo "" >&2
        fi

        return 1
    fi

    if [ "$analyzer_status" -ne 0 ]; then
        log_error "Static analysis failed" >&2
        return 1
    fi

    return 0
}

# 검증 기록 저장
save_approval() {
    local report_file="$1"

    # 승인 디렉토리 생성
    mkdir -p "$APPROVALS_DIR"

    local approval_file="$APPROVALS_DIR/$SKILL_HASH.json"
    local skill_name="${SKILL_PATH##*/}"

    # 승인 정보 추가
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    jq --arg ts "$timestamp" \
       --arg repo "$REPO" \
       --arg path "$SKILL_PATH" \
       --arg name "$skill_name" \
       --arg hash "$SKILL_HASH" \
       '. + {
           validated_at: $ts,
           repository: $repo,
           skill_path: $path,
           skill_name: $name,
           skill_hash: $hash
       }' "$report_file" > "$approval_file" 2>/dev/null

    # 서명 추가
    local data
    data=$(canonicalize_json_file "$approval_file")
    local signature
    signature=$(sign_cache "$data")

    jq --arg sig "$signature" '. + {signature: $sig}' "$approval_file" > "${approval_file}.tmp"
    mv "${approval_file}.tmp" "$approval_file"

    log_info "✓ Approval record saved with signature" >&2
}

# 로컬 검증 기록 저장
save_local_approval() {
    local report_file="$1"
    local skill_name="$2"
    local installed_path="$3"

    mkdir -p "$APPROVALS_DIR"

    local skill_hash
    skill_hash=$(sha256_hex "local/${installed_path}")

    local approval_file="$APPROVALS_DIR/$skill_hash.json"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    jq --arg ts "$timestamp" \
       --arg name "$skill_name" \
       --arg installed_path "$installed_path" \
       --arg hash "$skill_hash" \
       '. + {
           validated_at: $ts,
           repository: "local",
           skill_path: $name,
           skill_name: $name,
           installed_path: $installed_path,
           skill_hash: $hash
       }' "$report_file" > "$approval_file" 2>/dev/null

    local data
    data=$(canonicalize_json_file "$approval_file")
    local signature
    signature=$(sign_cache "$data")

    jq --arg sig "$signature" '. + {signature: $sig}' "$approval_file" > "${approval_file}.tmp"
    mv "${approval_file}.tmp" "$approval_file"

    log_info "✓ Local approval record saved with signature" >&2
}

# 임시 파일 정리
cleanup() {
    if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}

# =============================================================================
# 로컬 스킬 검증 (설치된 스킬 재검증)
# =============================================================================

# 설치된 스킬 경로 찾기
find_installed_skill() {
    local skill_ref="$1"

    if [ -d "$skill_ref" ]; then
        resolve_path "$skill_ref"
        return 0
    fi

    # 가능한 경로들
    local possible_paths=(
        "$HOME/.agents/skills/$skill_ref"
        "$HOME/.codex/skills/$skill_ref"
        "$HOME/.claude/skills/$skill_ref"
        "$HOME/.skills/$skill_ref"
    )

    for path in "${possible_paths[@]}"; do
        if [ -d "$path" ]; then
            resolve_path "$path"
            return 0
        fi
    done

    local list_output
    local line
    local parsed_name
    local parsed_path

    for scope in "" "-g"; do
        list_output=$(run_skills_cli list $scope 2>/dev/null || true)

        while IFS= read -r line; do
            line=$(printf '%s\n' "$line" | sed -E $'s/\x1B\\[[0-9;?]*[ -/]*[@-~]//g')
            if [[ "$line" =~ ^([A-Za-z0-9._-]+)[[:space:]]+([~/].+)$ ]]; then
                parsed_name="${BASH_REMATCH[1]}"
                parsed_path="${BASH_REMATCH[2]}"

                if [ "$parsed_name" = "$skill_ref" ]; then
                    parsed_path=$(resolve_path "$parsed_path")

                    if [ -d "$parsed_path" ]; then
                        echo "$parsed_path"
                        return 0
                    fi
                fi
            fi
        done <<< "$list_output"
    done

    return 1
}

# 로컬 스킬 검증
validate_local_skill() {
    local skill_ref="$1"
    local mode="${2:-standard}"
    local show_report="${3:-false}"

    # 스킬 경로 찾기
    local skill_dir
    skill_dir=$(find_installed_skill "$skill_ref") || {
        log_error "Skill not found: $skill_ref"
        echo ""
        echo "Installed skills:"
        run_skills_cli list -g 2>/dev/null | grep -v "^$" | head -20
        return 1
    }

    local skill_name
    skill_name=$(basename "$skill_dir")

    # 모드에 따른 패턴 파일 선택
    case "$mode" in
        essential)
            PATTERNS_FILE="$SCRIPT_DIR/patterns.essential.json"
            ;;
        standard)
            PATTERNS_FILE="$SCRIPT_DIR/patterns.standard.json"
            ;;
        thorough)
            PATTERNS_FILE="$SCRIPT_DIR/patterns.json"
            ;;
        *)
            log_warn "Unknown mode: $mode, using standard"
            PATTERNS_FILE="$SCRIPT_DIR/patterns.standard.json"
            mode="standard"
            ;;
    esac

    # 패턴 파일 존재 확인
    if [ ! -f "$PATTERNS_FILE" ]; then
        log_error "Patterns file not found: $PATTERNS_FILE"
        return 1
    fi

    # 검증 실행
    echo ""
    log_header "SKILL VALIDATION (INSTALLED)"
    echo ""
    log_info "Skill: ${skill_name}"
    log_info "Path: ${skill_dir}"
    log_info "Mode: ${mode}"
    echo ""

    log_step "Running static analysis..."

    # 임시 보고서 파일
    local report_file
    report_file=$(create_temp_json)

    # 정적 분석 실행
    local analyzer_status=0
    python3 "$ANALYZER" \
        --input "$skill_dir" \
        --output "$report_file" \
        --patterns "$PATTERNS_FILE" >/dev/null 2>&1 || analyzer_status=$?

    if [ ! -f "$report_file" ]; then
        log_error "Static analysis failed"
        rm -f "$report_file"
        return 1
    fi

    # 결과 확인
    local status
    status=$(jq -r '.status' "$report_file" 2>/dev/null || echo "UNKNOWN")

    if [ "$status" = "UNKNOWN" ]; then
        log_error "Static analysis failed"
        rm -f "$report_file"
        return 1
    fi

    local critical high medium low
    critical=$(jq -r '.summary.critical // 0' "$report_file" 2>/dev/null || echo 0)
    high=$(jq -r '.summary.high // 0' "$report_file" 2>/dev/null || echo 0)
    medium=$(jq -r '.summary.medium // 0' "$report_file" 2>/dev/null || echo 0)
    low=$(jq -r '.summary.low // 0' "$report_file" 2>/dev/null || echo 0)

    local files_scanned
    files_scanned=$(jq -r '.files_scanned // 0' "$report_file" 2>/dev/null || echo 0)

    echo ""
    echo "Files scanned: $files_scanned"

    if [ "$status" = "FAIL" ]; then
        echo ""
        log_error "❌ VALIDATION FAILED"
        echo ""
        echo "Issues found:"
        echo "  CRITICAL: $critical"
        echo "  HIGH: $high"
        echo "  MEDIUM: $medium"
        echo "  LOW: $low"

        # 이슈 표시
        if [ "$show_report" = true ] || [ "$critical" -gt 0 ] || [ "$high" -gt 0 ]; then
            echo ""
            echo "Details:"
            jq -r '.issues[] | select(.severity == "CRITICAL" or .severity == "HIGH") |
                   "\(.severity): \(.description) (line \(.line))"' "$report_file" 2>/dev/null | head -20
        fi

        rm -f "$report_file"
        return 1
    else
        if [ "$analyzer_status" -ne 0 ]; then
            log_error "Static analysis failed"
            rm -f "$report_file"
            return 1
        fi

        echo ""
        log_info "✅ VALIDATION PASSED"
        echo ""
        echo "Issues found:"
        echo "  CRITICAL: $critical"
        echo "  HIGH: $high"
        echo "  MEDIUM: $medium"
        echo "  LOW: $low"

        # 보고서 요청 시 상세 표시
        if [ "$show_report" = true ]; then
            echo ""
            echo "Full report:"
            jq '.' "$report_file" 2>/dev/null
        fi

        save_local_approval "$report_file" "$skill_name" "$skill_dir"

        rm -f "$report_file"
        return 0
    fi
}

# =============================================================================
# 메인
# =============================================================================

main() {
    # 인자 확인
    if [ $# -lt 1 ]; then
        log_error "Usage: validator.sh <skill-spec> [--mode=essential|standard|thorough]"
        echo ""
        echo "For remote skills:"
        echo "  validator.sh mattpocock/skills/write-a-prd"
        echo "  validator.sh mattpocock/skills/write-a-prd --mode=essential"
        echo ""
        echo "For local/installed skills:"
        echo "  validator.sh --local <skill-name> [--mode=standard] [--report]"
        echo ""
        exit 1
    fi

    # --local 옵션 처리 (설치된 스킬 검증)
    if [ "$1" = "--local" ]; then
        if [ $# -lt 2 ]; then
            log_error "Usage: validator.sh --local <skill-name> [--mode=essential|standard|thorough] [--report]"
            exit 1
        fi

        local skill_name="$2"
        local mode="standard"
        local show_report=false

        # 옵션 파싱
        shift 2
        while [ $# -gt 0 ]; do
            case "$1" in
                --mode=*)
                    mode="${1#*=}"
                    ;;
                --report)
                    show_report=true
                    ;;
            esac
            shift
        done

        validate_local_skill "$skill_name" "$mode" "$show_report"
        exit $?
    fi

    # 일반 스킬 사양 검증
    local skill_spec="$1"

    # 모드 파싱 (--mode=xxx)
    for arg in "$@"; do
        case "$arg" in
            --mode=*)
                VALIDATION_MODE="${arg#*=}"
                ;;
        esac
    done

    # 모드에 따른 패턴 파일 선택
    case "$VALIDATION_MODE" in
        essential)
            PATTERNS_FILE="$SCRIPT_DIR/patterns.essential.json"
            ;;
        standard)
            PATTERNS_FILE="$SCRIPT_DIR/patterns.standard.json"
            ;;
        thorough)
            PATTERNS_FILE="$SCRIPT_DIR/patterns.json"
            ;;
        *)
            log_warn "Unknown mode: $VALIDATION_MODE, using standard"
            PATTERNS_FILE="$SCRIPT_DIR/patterns.standard.json"
            VALIDATION_MODE="standard"
            ;;
    esac

    # 패턴 파일 존재 확인
    if [ ! -f "$PATTERNS_FILE" ]; then
        log_error "Patterns file not found: $PATTERNS_FILE"
        exit 1
    fi

    # 1. 스킬 식별
    parse_skill_spec "$skill_spec"

    local WORK_DIR
    WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/skill-validator.${SKILL_HASH}.XXXXXX")
    local REPORT_FILE="$WORK_DIR/report.json"

    # 종료 시 정리
    trap cleanup EXIT

    echo ""
    log_header "SKILL VALIDATION"
    echo ""
    log_info "Repository: ${REPO}"
    log_info "Skill Path: ${SKILL_PATH}"
    echo ""

    # 2. 캐시 확인
    if check_cache; then
        exit 0  # 캐시 히트, 재검증 불필요
    fi

    # 3. 스킬 다운로드
    log_step "Downloading skill from ${REPO}..."
    local skill_dir
    skill_dir=$(download_skill "$WORK_DIR") || exit 1

    # 4. 정적 분석
    log_step "Running static analysis..."
    run_static_analysis "$skill_dir" "$REPORT_FILE" || exit 1

    # 5. 검증 기록 저장
    save_approval "$REPORT_FILE"

    # 6. 성공
    echo ""
    log_header "VALIDATION PASSED"
    echo ""

    exit 0
}

main "$@"
