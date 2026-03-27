# 스킬 설치 검증 시스템 구현 상세 설계

## 파일 구조 및 역할

```
~/.claude/
├── skill-validator/              # 검증기 본체
│   ├── validator.sh              # ★ 검증 메인 로직
│   ├── static_analyzer.py        # ★ 정적 분석기
│   ├── patterns.json             # ★ 보안 패턴 DB (53개)
│   ├── sandbox_runner.sh         # 샌드박스 테스터
│   └── config/
│       └── default.yaml          # 기본 설정
│
├── skill-approvals/              # 검증 캐시 (이미 검증된 스킬)
│   └── [sha256].json             # 스킬별 검증 결과
│
├── hooks/
│   └── block-direct-skills-install.sh  # Claude Code 훅
│
└── settings.json                 # Claude Code 설정 (훅 등록)

~/.local/bin/
└── skills                        # ★ CLI 래퍼 (진입점)
```

---

## 파일별 상세 설계

### 1. ~/.local/bin/skills (CLI 래퍼)

#### 역할
- 사용자 명령의 진입점 (Entry Point)
- `npx skills` 명령을 가로챔 (Intercept)
- 검증 통과 시에만 실제 명령 실행

#### 동작 흐름
```
사용자: skills add mattpocock/skills/tdd
    │
    ▼
skills 래퍼 실행
    │
    ├─ 1. 검증기 호출 (validator.sh)
    │       │
    │       ├─ PASS (종료 코드 0)
    │       │       │
    │       │       ▼
    │       │   npx skills@latest add mattpocock/skills/tdd
    │       │       │
    │       │       ▼
    │       │   스킬 설치됨
    │       │
    │       └─ FAIL (종료 코드 1)
    │               │
    │               ▼
    │           에러 메시지 + 종료
    │
    └─ 종료 코드 사용자에게 반환
```

#### 구현 코드
```bash
#!/bin/bash
# ~/.local/bin/skills

set -euo pipefail

# 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR_HOME="$HOME/.claude/skill-validator"
VALIDATOR="$VALIDATOR_HOME/validator.sh"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 로그 함수
log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# 도움말
show_help() {
    cat << 'EOF'
Skills - CLI wrapper with security validation

USAGE:
    skills <command> [options]

COMMANDS:
    add <skill-path>     Add a new skill with validation
    remove <skill-name>  Remove a skill
    list                 List installed skills
    update               Update all skills

OPTIONS:
    --skip-validation    Skip security validation (NOT RECOMMENDED)
    --force              Force re-validation even if cached

EXAMPLES:
    skills add mattpocock/skills/write-a-prd
    skills list
    skills remove write-a-prd

For more information, use: skills <command> --help
EOF
}

# 유효성 검사
check_validator() {
    if [ ! -f "$VALIDATOR" ]; then
        log_error "Skill validator not found at: $VALIDATOR"
        echo ""
        echo "Please install the skill validator first:"
        echo "  curl -fsSL https://raw.githubusercontent.com/.../install.sh | bash"
        exit 1
    fi

    if [ ! -x "$VALIDATOR" ]; then
        chmod +x "$VALIDATOR"
    fi
}

# 메인
main() {
    # 인자 없으면 도움말
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi

    # 서브커맨드 추출
    local command="$1"
    shift

    # 검증이 필요 없는 명령들
    case "$command" in
        help|--help|-h)
            show_help
            exit 0
            ;;
        list|remove|update|--version)
            # 검증 없이 바로 실행
            npx skills@latest "$command" "$@"
            exit $?
            ;;
    esac

    # 검증이 필요한 명령: add
    if [ "$command" = "add" ]; then
        # --skip-validation 플래그 확인
        if [[ " $*" == *"--skip-validation"* ]]; then
            log_warn "⚠️  Skipping security validation!"
            log_warn "This is dangerous and not recommended."
            echo ""
            read -p "Are you sure? (yes/no): " confirmation
            if [ "$confirmation" != "yes" ]; then
                echo "Cancelled."
                exit 1
            fi
            # 검증 스킵하고 바로 설치
            npx skills@latest "$command" "$@"
            exit $?
        fi

        # 검증기 실행
        check_validator

        log_info "⏳ Validating skill before installation..."

        # 검증기에 스킬 경로 전달
        "$VALIDATOR" "$@"
        VALIDATOR_EXIT=$?

        if [ $VALIDATOR_EXIT -eq 0 ]; then
            # 검증 통과: 실제 설치 실행
            log_info "✅ Validation passed! Installing skill..."
            npx skills@latest "$command" "$@"
            exit $?
        else
            # 검증 실패
            log_error "❌ Validation failed. Skill installation blocked."
            exit $VALIDATOR_EXIT
        fi
    fi

    # 알 수 없는 명령
    echo "Unknown command: $command"
    echo "Use 'skills --help' for usage information."
    exit 1
}

main "$@"
```

---

### 2. ~/.claude/skill-validator/validator.sh

#### 역할
- 검증 프로세스의 메인 코디네이터
- 스킬 다운로드, 정적 분석, 샌드박스 테스트 조율
- 최종 PASS/FAIL 결정

#### 동작 흐름
```
입력: mattpocock/skills/write-a-prd
    │
    ├─ 1. 스킬 식별
    │       - 저장소: github.com/mattpocock/skills
    │       - 스킬 경로: skills/write-a-prd
    │       - 해시: sha256(repo + path) = abc123...
    │
    ├─ 2. 캐시 확인
    │       - .claude/skill-approvals/abc123.json 존재?
    │       - YES → 30일 이내?
    │             - YES → PASS (재검증 불필요)
    │             - NO → 3단계로
    │       - NO → 3단계로
    │
    ├─ 3. 스킬 다운로드
    │       - git clone --depth 1 --sparse
    │       - /tmp/skill-validator/abc123/
    │
    ├─ 4. 정적 분석
    │       - static_analyzer.py 실행
    │       - CRITICAL/HIGH 이슈 확인
    │       - FAIL → 에러 출력 + 종료
    │
    ├─ 5. 샌드박스 테스트
    │       - 격리 환경에서 실행 테스트
    │       - FAIL → 에러 출력 + 종료
    │
    ├─ 6. 검증 기록 저장
    │       - .claude/skill-approvals/abc123.json
    │
    └─ 7. 종료 코드 반환
        - 0 = PASS
        - 1 = FAIL
```

#### 구현 코드
```bash
#!/bin/bash
# ~/.claude/skill-validator/validator.sh

set -euo pipefail

# =============================================================================
# 설정
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPROVALS_DIR="$HOME/.claude/skill-approvals"
WORK_DIR_BASE="/tmp/skill-validator"
PATTERNS_FILE="$SCRIPT_DIR/patterns.json"
ANALYZER="$SCRIPT_DIR/static_analyzer.py"
SANDBOX="$SCRIPT_DIR/sandbox_runner.sh"

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 로그 함수
log_info() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*" >&2; }
log_step() { echo -e "${BLUE}[→]${NC} $*"; }

# =============================================================================
# 유틸리티 함수
# =============================================================================

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
        exit 1
    fi

    # 스킬 해시 생성 (캐시 키로 사용)
    SKILL_HASH=$(echo -n "${REPO}/${SKILL_PATH}" | sha256sum | cut -d' ' -f1)
}

# 캐시 확인
check_cache() {
    local cache_file="$APPROVALS_DIR/$SKILL_HASH.json"

    if [ ! -f "$cache_file" ]; then
        return 1  # 캐시 미스
    fi

    # 캐시 만료 확인 (30일)
    local cache_time=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file")
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

    log_step "Downloading skill from ${REPO}..."

    # 임시 디렉토리 생성
    mkdir -p "$work_dir"

    # Git sparse clone (속도 최적화)
    git clone --depth 1 --quiet --filter=blob:none --sparse \
        "https://github.com/${REPO}.git" \
        "$work_dir/repo" 2>/dev/null || {
        log_error "Failed to clone repository: ${REPO}"
        return 1
    }

    # Sparse checkout으로 필요한 부분만 체크아웃
    cd "$work_dir/repo"
    git sparse-checkout set "$SKILL_PATH" 2>/dev/null || {
        log_error "Skill path not found: ${SKILL_PATH}"
        return 1
    }

    local skill_dir="$work_dir/repo/$SKILL_PATH"

    # SKILL.md 존재 확인
    if [ ! -f "$skill_dir/SKILL.md" ]; then
        log_error "SKILL.md not found in: ${SKILL_PATH}"
        return 1
    fi

    echo "$skill_dir"
}

# 정적 분석 실행
run_static_analysis() {
    local skill_dir="$1"
    local report_file="$2"

    log_step "Running static analysis..."

    # Python 버전 확인
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 not found"
        return 1
    fi

    # 정적 분석기 실행
    python3 "$ANALYZER" \
        --input "$skill_dir" \
        --output "$report_file" \
        --patterns "$PATTERNS_FILE" || {
        log_error "Static analysis failed"
        return 1
    }

    # 결과 확인
    local status=$(jq -r '.status' "$report_file")

    if [ "$status" = "FAIL" ]; then
        local critical=$(jq -r '.summary.critical // 0' "$report_file")
        local high=$(jq -r '.summary.high // 0' "$report_file")

        if [ "$critical" -gt 0 ] || [ "$high" -gt 2 ]; then
            log_error "Static analysis detected severe issues:"
            echo ""
            jq -r '.issues[] | select(.severity == "CRITICAL" or .severity == "HIGH") |
                   "\(.severity): \(.description) (line \(.line))"' "$report_file" | head -20
            echo ""
            return 1
        fi
    fi

    log_info "✓ Static analysis passed"
    return 0
}

# 샌드박스 테스트 실행
run_sandbox_test() {
    local skill_dir="$1"

    log_step "Running sandbox test..."

    if [ ! -x "$SANDBOX" ]; then
        log_warn "Sandbox runner not found, skipping..."
        return 0
    fi

    "$SANDBOX" --skill "$skill_dir" || {
        log_error "Sandbox test failed"
        return 1
    }

    log_info "✓ Sandbox test passed"
    return 0
}

# 검증 기록 저장
save_approval() {
    local report_file="$1"

    # 승인 디렉토리 생성
    mkdir -p "$APPROVALS_DIR"

    local approval_file="$APPROVALS_DIR/$SKILL_HASH.json"

    # 승인 정보 추가
    jq --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
       --arg repo "$REPO" \
       --arg path "$SKILL_PATH" \
       '. + {
           validated_at: $ts,
           repository: $repo,
           skill_path: $path,
           skill_hash: "'$SKILL_HASH'"
       }' "$report_file" > "$approval_file"

    log_info "✓ Approval record saved"
}

# 임시 파일 정리
cleanup() {
    if [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}

# =============================================================================
# 메인
# =============================================================================

main() {
    # 인자 확인
    if [ $# -lt 1 ]; then
        log_error "Usage: validator.sh <skill-spec>"
        exit 1
    fi

    # 1. 스킬 식별
    parse_skill_spec "$1"

    local WORK_DIR="$WORK_DIR_BASE/$SKILL_HASH"
    local REPORT_FILE="$WORK_DIR/report.json"

    # 종료 시 정리
    trap cleanup EXIT

    echo ""
    log_info "═══════════════════════════════════════════════"
    log_info "  SKILL VALIDATION"
    log_info "═══════════════════════════════════════════════"
    echo ""
    log_info "Repository: ${REPO}"
    log_info "Skill Path: ${SKILL_PATH}"
    echo ""

    # 2. 캐시 확인
    if check_cache; then
        exit 0  # 캐시 히트, 재검증 불필요
    fi

    # 3. 스킬 다운로드
    local skill_dir
    skill_dir=$(download_skill "$WORK_DIR") || exit 1

    # 4. 정적 분석
    run_static_analysis "$skill_dir" "$REPORT_FILE" || exit 1

    # 5. 샌드박스 테스트
    run_sandbox_test "$skill_dir" || exit 1

    # 6. 검증 기록 저장
    save_approval "$REPORT_FILE"

    # 7. 성공
    echo ""
    log_info "═══════════════════════════════════════════════"
    log_info "  ✓ VALIDATION PASSED"
    log_info "═══════════════════════════════════════════════"
    echo ""

    exit 0
}

main "$@"
```

---

### 3. ~/.claude/skill-validator/static_analyzer.py

#### 역할
- 정적 분석 수행 (패턴 매칭)
- 보안 취약점 탐지
- JSON 보고서 생성

#### 검사 패턴 (53개)
```json
{
  "patterns": [
    {
      "id": "api_key_1",
      "name": "OpenAI API Key",
      "severity": "CRITICAL",
      "category": "security",
      "regex": "sk-[a-zA-Z0-9]{48}",
      "description": "OpenAI API key detected"
    },
    {
      "id": "dangerous_cmd_1",
      "name": "rm -rf root",
      "severity": "HIGH",
      "category": "security",
      "regex": "rm\\s+-rf\\s+/",
      "description": "Dangerous command: rm -rf from root"
    },
    {
      "id": "email_1",
      "name": "Email address",
      "severity": "MEDIUM",
      "category": "privacy",
      "regex": "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}",
      "description": "Email address detected"
    }
  ]
}
```

#### 구현 코드
```python
#!/usr/bin/env python3
"""
Skill Static Analyzer
정적 분석을 통해 스킬 파일의 보안 취약점을 탐지
"""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import List, Dict, Any
from dataclasses import dataclass, asdict
from datetime import datetime

@dataclass
class Issue:
    """발견된 이슈"""
    file: str
    line: int
    severity: str  # CRITICAL, HIGH, MEDIUM, LOW
    category: str  # security, privacy, structure, etc.
    pattern_id: str
    description: str
    match: str

@dataclass
class AnalysisResult:
    """분석 결과"""
    status: str  # PASS, FAIL
    skill_path: str
    files_scanned: int
    issues: List[Issue]
    summary: Dict[str, int]
    analyzed_at: str

class SkillAnalyzer:
    """스킬 정적 분석기"""

    def __init__(self, patterns: List[Dict]):
        self.patterns = patterns
        # 정규식 컴파일 (성능 최적화)
        for pattern in self.patterns:
            pattern['compiled'] = re.compile(
                pattern['regex'],
                re.MULTILINE | re.DOTALL
            )

    def analyze_file(self, file_path: Path, skill_dir: Path) -> List[Issue]:
        """단일 파일 분석"""
        issues = []

        try:
            content = file_path.read_text(encoding='utf-8')
            lines = content.split('\n')
            relative_path = str(file_path.relative_to(skill_dir))

            for pattern in self.patterns:
                for match in pattern['compiled'].finditer(content):
                    # 라인 번호 계산
                    line_num = content[:match.start()].count('\n') + 1

                    # 매치된 내용 추출 (주변 텍스트 포함)
                    start = max(0, match.start() - 20)
                    end = min(len(content), match.end() + 20)
                    context = content[start:end]

                    issues.append(Issue(
                        file=relative_path,
                        line=line_num,
                        severity=pattern['severity'],
                        category=pattern['category'],
                        pattern_id=pattern['id'],
                        description=pattern['description'],
                        match=context.strip()
                    ))
        except Exception as e:
            # 바이너리 파일 등은 무시
            pass

        return issues

    def analyze(self, skill_dir: Path) -> AnalysisResult:
        """스킬 디렉토리 분석"""
        issues = []
        files_scanned = 0

        # 분석할 파일 확장자
        extensions = {'.md', '.txt', '.py', '.sh', '.js', '.ts', '.json', '.yaml', '.yml'}

        # 순회하며 분석
        for file_path in skill_dir.rglob('*'):
            if not file_path.is_file():
                continue

            # 파일 크기 제한 (10MB)
            if file_path.stat().st_size > 10_000_000:
                continue

            # 확장자 필터 또는 SKILL.md 등 핵심 파일
            if file_path.suffix not in extensions and file_path.name != 'SKILL.md':
                continue

            files_scanned += 1
            issues.extend(self.analyze_file(file_path, skill_dir))

        # 심각도별 집계
        summary = {
            'critical': sum(1 for i in issues if i.severity == 'CRITICAL'),
            'high': sum(1 for i in issues if i.severity == 'HIGH'),
            'medium': sum(1 for i in issues if i.severity == 'MEDIUM'),
            'low': sum(1 for i in issues if i.severity == 'LOW'),
        }

        # PASS/FAIL 결정
        if summary['critical'] > 0 or summary['high'] > 2:
            status = 'FAIL'
        else:
            status = 'PASS'

        return AnalysisResult(
            status=status,
            skill_path=str(skill_dir),
            files_scanned=files_scanned,
            issues=[asdict(issue) for issue in issues],
            summary=summary,
            analyzed_at=datetime.now().isoformat()
        )

def main():
    parser = argparse.ArgumentParser(description='Skill Static Analyzer')
    parser.add_argument('--input', required=True, help='Skill directory to analyze')
    parser.add_argument('--output', required=True, help='Output JSON report')
    parser.add_argument('--patterns', default='patterns.json', help='Patterns JSON file')
    parser.add_argument('--verbose', action='store_true', help='Verbose output')

    args = parser.parse_args()

    # 패턴 로드
    try:
        with open(args.patterns, 'r') as f:
            pattern_data = json.load(f)
            patterns = pattern_data.get('patterns', [])
    except FileNotFoundError:
        print(f"Error: Patterns file not found: {args.patterns}", file=sys.stderr)
        sys.exit(1)

    # 분석 실행
    analyzer = SkillAnalyzer(patterns)
    result = analyzer.analyze(Path(args.input))

    # 결과 저장
    with open(args.output, 'w') as f:
        json.dump(asdict(result), f, indent=2)

    # 출력
    if args.verbose or result['status'] == 'FAIL':
        print(json.dumps(asdict(result), indent=2))
    else:
        print(f"Status: {result['status']}")
        print(f"Files scanned: {result['files_scanned']}")
        print(f"Issues found: {len(result['issues'])}")

    # 종료 코드
    sys.exit(0 if result['status'] == 'PASS' else 1)

if __name__ == '__main__':
    main()
```

---

### 4. ~/.claude/hooks/block-direct-skills-install.sh

#### 역할
- Claude Code에서 `npx skills add`를 직접 호출하는 것을 차단
- PreToolUse 훅으로 작동

#### 구현 코드
```bash
#!/bin/bash
# ~/.claude/hooks/block-direct-skills-install.sh

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# npx skills 명령 차단
if echo "$COMMAND" | grep -qE "npx\\s+skills.*(add|install|remove)"; then
    cat >&2 << 'EOF'
❌ BLOCKED: Direct skill installation is not allowed!

For security reasons, all skill installations must go through
the validated installation wrapper.

Instead of: npx skills add <skill>
Use: skills add <skill>

This ensures all skills are validated before installation,
protecting you from potential security risks.

To bypass this protection (not recommended):
  skills add <skill> --skip-validation

EOF
    exit 2  # BLOCKED
fi

exit 0  # ALLOWED
```

---

### 5. ~/.claude/settings.json

#### 역할
- Claude Code에 훅 등록
- 전역 설정이므로 모든 프로젝트에 적용

#### 구현
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/block-direct-skills-install.sh"
          }
        ]
      }
    ]
  }
}
```

---

## 설치 순서

### 1. 저장소 생성

```bash
mkdir -p ~/skill-validator-project
cd ~/skill-validator-project
git init
```

### 2. 파일 생성 (위 순서대로)

```bash
# 1. 디렉토리 구조 생성
mkdir -p ~/.claude/skill-validator
mkdir -p ~/.claude/skill-approvals
mkdir -p ~/.claude/hooks
mkdir -p ~/.local/bin

# 2. 파일 생성 순서
# (1) patterns.json
# (2) static_analyzer.py
# (3) validator.sh
# (3) sandbox_runner.sh (선택)
# (4) block-direct-skills-install.sh
# (5) ~/.local/bin/skills
# (6) ~/.claude/settings.json
```

---

## 구현 시작 확인

```
준비 완료된 파일:
  ☐ ~/.claude/skill-validator/patterns.json
  ☐ ~/.claude/skill-validator/static_analyzer.py
  ☐ ~/.claude/skill-validator/validator.sh
  ☐ ~/.claude/hooks/block-direct-skills-install.sh
  ☐ ~/.claude/settings.json
  ☐ ~/.local/bin/skills

구현 순서:
  1. patterns.json (보안 패턴 DB)
  2. static_analyzer.py (정적 분석기)
  3. validator.sh (메인 로직)
  4. block-direct-skills-install.sh (훅)
  5. skills (CLI 래퍼)
  6. settings.json (Claude 설정)
```

---

이제 구현을 시작할까요?
