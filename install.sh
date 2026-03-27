#!/bin/bash
# Skill Validation System 설치 스크립트

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# 스크립트 위치 확인
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"

# 설치 대상 경로
CLAUDE_DIR="$HOME/.claude"
VALIDATOR_DIR="$CLAUDE_DIR/skill-validator"
LOCAL_BIN_DIR="$HOME/.local/bin"

echo -e "${BLUE}"
echo "═══════════════════════════════════════════════════"
echo "  Skill Validation System Installer v1.2.0"
echo "═══════════════════════════════════════════════════"
echo -e "${NC}"
echo ""

# 1. 필수 의존성 확인
log_info "필수 의존성 확인 중..."
command -v python3 >/dev/null 2>&1 || { log_error "Python 3가 필요합니다."; exit 1; }
command -v git >/dev/null 2>&1 || { log_error "Git이 필요합니다."; exit 1; }
command -v jq >/dev/null 2>&1 || { log_error "jq가 필요합니다. brew install jq 또는 sudo apt install jq"; exit 1; }
log_info "✓ 모든 의존성이 설치되어 있습니다."
echo ""

# 2. 디렉토리 생성
log_info "설치 디렉토리 생성 중..."
mkdir -p "$VALIDATOR_DIR"
mkdir -p "$CLAUDE_DIR/skill-approvals"
mkdir -p "$LOCAL_BIN_DIR"
log_info "✓ 디렉토리 생성 완료."
echo ""

# 3. 파일 복사
log_info "파일 복사 중..."
cp "$SRC_DIR/patterns.json" "$VALIDATOR_DIR/"
cp "$SRC_DIR/patterns.standard.json" "$VALIDATOR_DIR/"
cp "$SRC_DIR/patterns.essential.json" "$VALIDATOR_DIR/"
cp "$SRC_DIR/static_analyzer.py" "$VALIDATOR_DIR/"
cp "$SRC_DIR/validator.sh" "$VALIDATOR_DIR/"
cp "$SRC_DIR/skills" "$LOCAL_BIN_DIR/"
log_info "✓ 파일 복사 완료."
echo ""

# 4. 실행 권한 부여
log_info "실행 권한 부여 중..."
chmod +x "$VALIDATOR_DIR/validator.sh"
chmod +x "$VALIDATOR_DIR/static_analyzer.py"
chmod +x "$LOCAL_BIN_DIR/skills"
log_info "✓ 실행 권한 부여 완료."
echo ""

# 5. PATH 설정 확인
log_info "PATH 설정 확인 중..."
if ! echo "$PATH" | grep -q "$LOCAL_BIN_DIR"; then
    log_warn "${LOCAL_BIN_DIR}이 PATH에 없습니다."
    echo ""
    echo "다음을 셸 설정 파일(~/.zshrc 또는 ~/.bashrc)에 추가하세요:"
    echo ""
    echo -e "${GREEN}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
    echo ""
    echo "그런 다음 실행하세요: source ~/.zshrc"
else
    log_info "✓ PATH가 이미 설정되어 있습니다."
fi
echo ""

# 6. 설치 완료
echo -e "${GREEN}"
echo "═══════════════════════════════════════════════════"
echo "  설치 완료!"
echo "═══════════════════════════════════════════════════"
echo -e "${NC}"
echo ""
echo "설치된 파일:"
echo "  • $VALIDATOR_DIR/"
echo "  • $LOCAL_BIN_DIR/skills"
echo "  • $CLAUDE_DIR/skill-approvals/"
echo ""
echo -e "${YELLOW}중요:${NC} 이 도구는 수동 검증 도구입니다."
echo "스킬을 설치할 때 반드시 다음 명령을 사용하세요:"
echo ""
echo -e "${GREEN}  skills add <skill-path>${NC}"
echo ""
echo "예시:"
echo -e "${GREEN}  skills add mattpocock/skills/write-a-prd${NC}"
echo ""
echo -e "${YELLOW}주의:${NC} LLM에게 \"스킬 설치해줘\"라고 요청하면"
echo "검증 없이 설치됩니다. 반드시 직접 ${GREEN}skills add${NC}를 사용하세요."
echo ""
