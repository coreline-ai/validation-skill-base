# 스킬 설치 전 강제 검증 시스템 설계

## 목표

> **Claude Code에 스킬이 설치되기 전, 반드시 1회 검증을 수행하도록 강제**

---

## 1. 시스템 개요

```
┌─────────────────────────────────────────────────────────────────────┐
│                      스킬 설치 흐름 (강제 검증)                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   사용자 명령                                                       │
│      │                                                             │
│      ▼                                                             │
│   ┌─────────────────┐                                              │
│   │  skills wrapper │  ← 기존 명령을 가로채는 래퍼                  │
│   └────────┬────────┘                                              │
│            │                                                        │
│            ▼                                                        │
│   ┌─────────────────┐                                              │
│   │  사전 검증 단계   │  ← 설치 전 반드시 통과해야 할 관문           │
│   │                 │                                              │
│   │  1. 소스 확인    │     - 신뢰할 수 있는 저장소인지?            │
│   │  2. 정적 분석    │     - 보안 패턴 검사 (53+ 패턴)              │
│   │  3. 구조 검증    │     - SKILL.md 형식 확인                     │
│   │  4. 샌드박스     │     - 안전한 환경에서 실행 테스트             │
│   │  5. 승인 결정    │     - PASS면 설치, FAIL면 차단                │
│   └────────┬────────┘                                              │
│            │                                                        │
│            ▼                                                        │
│        PASS?                                                       │
│       /    \                                                       │
│     NO      YES                                                    │
│      │       │                                                     │
│      │       ▼                                                     │
│      │   ┌─────────────────┐                                       │
│      │   │ 실제 설치 실행   │  ← npx skills@latest add              │
│      │   └─────────────────┘                                       │
│      │       │                                                     │
│      │       ▼                                                     │
│      │   ┌─────────────────┐                                       │
│      │   │ 검증 기록 저장   │  ← .skill-approvals/에 기록            │
│      │   └─────────────────┘                                       │
│      │                                                             │
│      └─────────────────────► 에러 메시지 + 이유                     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. 구현 방안 비교

### 방안 A: Shell 래퍼 (권장)

```bash
# 기존 명령
npx skills@latest add mattpocock/skills/write-a-prd

# 래퍼를 통한 명령 (같은 동작)
skills add mattpocock/skills/write-a-prd
```

**구조:**
```bash
~/.local/bin/skills  ← 쉘 래퍼
├── 검증 로직
├── 정적 분석기
├── 샌드박스 테스터
└── 기존 npx skills 명령 호출 (검증 통과 시)
```

**장점:**
- ✅ 기존 명령과 100% 호환
- ✅ 모든 쉘에서 동작
- ✅ 구현 간단
- ✅ 별도 설치 불필요 (스크립트만)

**단점:**
- ⚠️ 사용자가 `npx skills`를 직접 호출하면 우회 가능

---

### 방안 B: Claude Code Hook

```json
// .claude/settings.json
{
  "hooks": {
    "PreSkillInstall": [
      {
        "type": "command",
        "command": "~/.claude/hooks/skill-validator.sh"
      }
    ]
  }
}
```

**장점:**
- ✅ Claude Code 네이티브 통합
- ✅ 우회 불가능
- ✅ IDE 내 메시지 표시

**단점:**
- ⚠️ Claude Code에서 해당 훅을 지원하지 않을 수 있음
- ⚠️ Claude Code 업데이트에 종속

---

### 방안 C: npm 글로벌 패키지 (하이브리드)

```bash
# 설치
npm install -g @skill-validator/cli

# 사용 (기존 명령 대체)
skills add mattpocock/skills/write-a-prd
```

**구조:**
```
skill-validator/
├── bin/
│   └── skills           # npx skills 래퍼
├── lib/
│   ├── validator.js     # 검증 로직
│   ├── analyzer.js      # 정적 분석
│   └── sandbox.js       # 샌드박스
└── .skill-approvals/    # 검증 기록 (캐시)
```

**장점:**
- ✅ npm 생태계 호환
- ✅ 업데이트 배포 용이
- ✅ 전역 설치로 어디서든 사용

**단점:**
- ⚠️ Node.js 필요
- ⚠️ 직접 npx 호출 시 우회 가능

---

### 방안 D: Alias + Hook (최종 권장)

```bash
# 1. Shell 래퍼 설치 (alias)
alias skills='~/.local/bin/skills-wrapper'

# 2. Claude Code PreToolUse 훅 (우회 방지)
# 3. Git-style pre-install hook
```

**조합:**
- **기본**: Shell 래퍼 (사용자 편의성)
- **안전장치**: Claude Code 훅 (직접 호출 차단)
- **검증 기록**: `.skill-approvals/` 캐시 (재검증 방지)

---

## 3. 최종 설계 (방안 D)

### 파일 구조

```
~/.claude/
├── settings.json                    # Claude Code 설정
├── hooks/
│   ├── skill-validator.sh           # PreToolUse 훅
│   └── block-direct-skills-install.sh
├── skill-validator/                 # 검증기 본체
│   ├── validator.sh                 # 메인 검증기
│   ├── static_analyzer.py           # 정적 분석
│   ├── patterns.json                # 보안 패턴 DB
│   └── sandbox_runner.sh            # 샌드박스
└── skill-approvals/                 # 검증 기록 (캐시)
    └── [skill-hash].json            # 스킬별 검증 결과

~/.local/bin/
└── skills                           # CLI 래퍼 (심볼릭 링크)
```

### 검증 플로우 상세

```
┌─────────────────────────────────────────────────────────────────────┐
│ 1단계: 스킬 식별                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  입력: mattpocock/skills/write-a-prd                                │
│  분석:                                                              │
│    - 저장소: github.com/mattpocock/skills                           │
│    - 스킬 경로: skills/write-a-prd                                  │
│    - 해시: sha256(repo + skill_path + version)                      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 2단계: 캐시 확인 (이미 검증된 스킬인지?)                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  $ ls ~/.claude/skill-approvals/[hash].json                         │
│                                                                     │
│  존재?                                                              │
│    YES → 검증 기록 확인                                             │
│           - 기간 내(30일)? → PASS, 설치 진행                         │
│           - 기간 경과? → 3단계로                                     │
│    NO  → 3단계로                                                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 3단계: 스킬 다운로드 및 압축 해제                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  $ git clone --depth 1 --sparse                                     │
│      https://github.com/mattpocock/skills.git                       │
│      /tmp/skill-validator/[hash]/                                   │
│                                                                     │
│  $ git sparse-checkout set skills/write-a-prd                       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 4단계: 정적 분석 (자동, 빠름)                                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  $ python3 ~/.claude/skill-validator/static_analyzer.py             │
│      --input /tmp/skill-validator/[hash]/                           │
│      --output /tmp/skill-validator/[hash]/report.json               │
│                                                                     │
│  검사 항목:                                                         │
│    ✓ 보안 패턴 (53개)                                               │
│    ✓ 구조 검증                                                      │
│    ✓ OWASP LLM Top 10 기본 검사                                     │
│    ✓ 파일 크기/개수 확인                                            │
│                                                                     │
│  결과:                                                              │
│    - CRITICAL 이슈 > 0  → FAIL (5단계 생략, 바로 차단)               │
│    - HIGH 이슈 > 2     → FAIL                                      │
│    - 그 외            → PASS                                       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
                            │
                    PASS / FAIL
                    /        \
                  FAIL        PASS
                   │            │
                   │            ▼
                   │   ┌─────────────────────────────────────────────┐
                   │   │ 5단계: 샌드박스 테스트 (선택, 신규만)        │
                   │   ├─────────────────────────────────────────────┤
                   │   │                                             │
                   │   │ $ ~/.claude/skill-validator/sandbox_runner.sh│
                   │   │     --skill /tmp/skill-validator/[hash]/     │
                   │   │                                             │
                   │   │ 테스트:                                     │
                   │   │   - Docker/venv 격리 환경                   │
                   │   │   - 정상 동작 확인                           │
                   │   │   - 부작용 모니터링                          │
                   │   │                                             │
                   │   └─────────────────────────────────────────────┘
                   │                │
                   │                ▼
                   │            PASS / FAIL
                   │            /        \
                   │          FAIL        PASS
                   │           │            │
┌──────────────────┴───────────┴────────────┐                       │
│ 6단계: 결정 및 실행                         │                       │
├────────────────────────────────────────────┤
│                                            │                       │
│ FAIL 경로:                                 │                       │
│   ┌──────────────────────────────────┐    │                       │
│   │ 에러 메시지 출력                   │    │                       │
│   │                                  │    │                       │
│   │ ❌ 스킬 설치 차단                  │    │                       │
│   │                                  │    │                       │
│   │ 이유: [상세 이유]                  │    │                       │
│   │                                  │    │                       │
│   │ 발견된 이슈:                      │    │                       │
│   │   - [HIGH] Line 42: ...           │    │                       │
│   │   - [MEDIUM] Line 78: ...         │    │                       │
│   │                                  │    │                       │
│   │ 강제 설치를 원하시면:              │    │                       │
│   │   skills add --skip-validation    │    │                       │
│   │                                  │    │                       │
│   └──────────────────────────────────┘    │                       │
│                                            │                       │
│ PASS 경로:                                 │                       │
│   ┌──────────────────────────────────┐    │                       │
│   │ 7단계: 실제 설치                   │    │                       │
│   │                                  │    │                       │
│   │ npx skills@latest add [skill]     │    │                       │
│   │                                  │    │                       │
│   └──────────┬───────────────────────┘    │                       │
│              │                              │                       │
│              ▼                              │                       │
│   ┌──────────────────────────────────┐    │                       │
│   │ 8단계: 검증 기록 저장              │    │                       │
│   │                                  │    │                       │
│   │ $ cat > ~/.claude/skill-approvals/ │    │                       │
│   │        [hash].json << EOF            │                       │
│   │ {                                   │                       │
│   │   "skill": "mattpocock/skills/...", │                       │
│   │   "validated_at": "2025-03-21...",  │                       │
│   │   "hash": "...",                   │                       │
│   │   "status": "PASS",                │                       │
│   │   "issues": {...}                  │                       │
│   │ }                                   │                       │
│   │ EOF                                 │                       │
│   │                                  │    │                       │
│   └──────────────────────────────────┘    │                       │
│                                            │                       │
│   ✅ 스킬 설치 완료                         │                       │
│                                            │                       │
└────────────────────────────────────────────┘
```

---

## 4. 사용자 경험

### 정상 설치 (검증 통과)

```bash
$ skills add mattpocock/skills/write-a-prd

⏳  스킬 검증 중...
  ✓ 소스 확인 (github.com/mattpocock/skills)
  ✓ 캐시 확인 (신규 스킬)
  ✓ 스킬 다운로드
  ✓ 정적 분석 (53개 패턴, 0개 이슈)
  ✓ 샌드박스 테스트
  ✓ 검증 기록 저장

✅  검증 통과! 스킬을 설치합니다...
   npx skills@latest add mattpocock/skills/write-a-prd

[기존 skills 출력]

✅  스킬 설치 완료: write-a-prd
```

### 설치 차단 (검증 실패)

```bash
$ skills add unknown/repo/suspicious-skill

⏳  스킬 검증 중...
  ✓ 소스 확인 (github.com/unknown/repo)
  ✓ 캐시 확인 (신규 스킬)
  ✓ 스킬 다운로드
  ✗ 정적 분석 실패

❌  스킬 설치 차단됨

발견된 이슈:
  🔴 [CRITICAL] Line 15: API 키 노출
     sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

  🟠 [HIGH] Line 42: 위험한 명령어
     rm -rf /home/user/*

  🟠 [HIGH] Line 58: 악성 URL
     http://malicious-server.com/steal

권장사항:
  - 이 스킬의 출처를 확인하세요
  - 작성자에게 이슈를 신고하세요
  - 안전한 대안을 찾아보세요

강제 설치 (--skip-validation 사용 시 위험 감수):
  $ skills add unknown/repo/suspicious-skill --skip-validation

설치가 취소되었습니다. (종료 코드: 1)
```

### 재설치 (이미 검증됨)

```bash
$ skills add mattpocock/skills/write-a-prd

⏳  스킬 검증 중...
  ✓ 소스 확인
  ✓ 캐시 확인 (2025-03-15 검증 완료, 6일 전)
  ✓ 검증 유효함

✅  캐시된 검증 사용, 스킬을 설치합니다...
   npx skills@latest add mattpocock/skills/write-a-prd

✅  스킬 설치 완료: write-a-prd
```

---

## 5. 구현 파일 명세

### 5.1 Shell 래퍼 (`~/.local/bin/skills`)

```bash
#!/bin/bash
# ~/.local/bin/skills

SKILL_VALIDATOR_HOME="$HOME/.claude/skill-validator"
APPROVALS_DIR="$HOME/.claude/skill-approvals"

# 검증기 실행
"$SKILL_VALIDATOR_HOME/validator.sh" "$@"

# 종료 코드 확인
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    # 검증 통과: 실제 설치 실행
    npx skills@latest "$@"
else
    # 검증 실패: 종료
    exit $EXIT_CODE
fi
```

### 5.2 검증기 (`~/.claude/skill-validator/validator.sh`)

```bash
#!/bin/bash
# 스킬 검증 메인 로직

# 1. 스킬 식별
SKILL_SPEC="$2"
REPO=$(echo "$SKILL_SPEC" | cut -d'/' -f1-2)
SKILL_PATH=$(echo "$SKILL_SPEC" | cut -d'/' -f3-)
SKILL_HASH=$(echo -n "$REPO/$SKILL_PATH" | sha256sum | cut -d' ' -f1)

# 2. 캐시 확인
if [ -f "$APPROVALS_DIR/$SKILL_HASH.json" ]; then
    # 검증 기록 확인 (30일 유효)
    if cache_valid "$APPROVALS_DIR/$SKILL_HASH.json"; then
        exit 0  # PASS
    fi
fi

# 3. 스킬 다운로드
WORK_DIR="/tmp/skill-validator/$SKILL_HASH"
git clone --depth 1 --sparse "https://github.com/$REPO.git" "$WORK_DIR"
git -C "$WORK_DIR" sparse-checkout set "$SKILL_PATH"

# 4. 정적 분석
REPORT="$WORK_DIR/report.json"
python3 "$SKILL_VALIDATOR_HOME/static_analyzer.py" \
    --input "$WORK_DIR/$SKILL_PATH" \
    --output "$REPORT"

# 5. 결과 판단
if has_critical_issues "$REPORT"; then
    print_error "$REPORT"
    exit 1  # FAIL
fi

# 6. 샌드박스 테스트 (신규만)
if [ ! -f "$APPROVALS_DIR/$SKILL_HASH.json" ]; then
    if ! "$SKILL_VALIDATOR_HOME/sandbox_runner.sh" \
            --skill "$WORK_DIR/$SKILL_PATH"; then
        exit 1  # FAIL
    fi
fi

# 7. 검증 기록 저장
save_approval "$SKILL_HASH" "$REPORT"

exit 0  # PASS
```

### 5.3 정적 분석기 (`~/.claude/skill-validator/static_analyzer.py`)

```python
#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path

# 53개 보안 패턴 로드
PATTERNS = json.load(open('patterns.json'))

def analyze(skill_dir):
    issues = []

    for file in skill_dir.rglob('*'):
        if not file.is_file():
            continue

        content = file.read_text()

        # 각 패턴 검사
        for pattern in PATTERNS:
            matches = re.finditer(pattern['regex'], content)
            for match in matches:
                issues.append({
                    'file': str(file.relative_to(skill_dir)),
                    'line': content[:match.start()].count('\n') + 1,
                    'severity': pattern['severity'],
                    'category': pattern['category'],
                    'description': pattern['description'],
                })

    return {
        'status': 'PASS' if no_critical(issues) else 'FAIL',
        'issues': issues,
    }

if __name__ == '__main__':
    result = analyze(Path(sys.argv[2]))
    json.dump(result, open(sys.argv[4], 'w'), indent=2)
```

### 5.4 Claude Code Hook (`~/.claude/hooks/block-direct-skills-install.sh`)

```bash
#!/bin/bash
# npx skills 직접 호출 차단

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

# npx skills 명령 차단
if echo "$COMMAND" | grep -q "npx skills.*add"; then
    echo "❌ 직접 스킬 설치가 차단되었습니다." >&2
    echo "" >&2
    echo "대신 'skills add' 명령을 사용하세요:" >&2
    echo "  $ skills add <skill-path>" >&2
    echo "" >&2
    echo "이렇게 하면 설치 전 보안 검증이 수행됩니다." >&2
    exit 2
fi

exit 0
```

### 5.5 Claude Code 설정 (`~/.claude/settings.json`)

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

## 6. 설치 방법

### 원스크립트 설치

```bash
curl -fsSL https://raw.githubusercontent.com/your-repo/skill-validator/main/install.sh | bash
```

### 수동 설치

```bash
# 1. 저장소 클론
git clone https://github.com/your-repo/skill-validator.git ~/.claude/skill-validator

# 2. 실행 권한 부여
chmod +x ~/.claude/skill-validator/*.sh
chmod +x ~/.claude/skill-validator/*.py

# 3. CLI 래퍼 설치
ln -s ~/.claude/skill-validator/skills-wrapper.sh ~/.local/bin/skills

# 4. Claude Code 훅 설정
cp ~/.claude/skill-validator/config/block-direct-skills-install.sh \
   ~/.claude/hooks/

# 5. settings.json에 훅 추가
# (자동 또는 수동으로)

# 6. 승인 디렉토리 생성
mkdir -p ~/.claude/skill-approvals
```

---

## 7. 보안 고려사항

### 우회 방지

| 위협 | 방어 |
|------|------|
| `npx skills` 직접 호출 | Claude Code PreToolUse 훅 |
| 래퍼 삭제 후 설치 | 사용자 교육 + 로그 감사 |
| `--skip-validation` 악용 | 경고 + 로그 기록 |

### 검증 기록 무결성

```
.skill-approvals/
└── [hash].json  ← 파일 무결성 확인 (HMAC)
```

### 샌드박스 격리

- Docker container 사용 (권장)
- 또는 Python venv
- 네트워크 차단 (옵션)

---

## 8. 토큰 소요 (실제 검증 시)

| 단계 | 토큰 | LLM 사용 |
|------|------|----------|
| 스킬 식별 | 0 | ✗ |
| 캐시 확인 | 0 | ✗ |
| 스킬 다운로드 | 0 | ✗ |
| 정적 분석 | 0 | ✗ (정규식만) |
| 샌드박스 | 0 | ✗ |
| **합계** | **0** | **✗** |

> **중요**: 이 방식은 LLM을 사용하지 않으므로 **토큰 비용 0**

---

## 9. 요약

### 핵심 특징

| 특징 | 설명 |
|------|------|
| **강제 검증** | `npx skills add`를 우회할 수 없음 |
| **토큰 비용 0** | LLM 사용하지 않음 |
| **캐싱** | 한 번 검증하면 30일간 유효 |
| **빠름** | 5-10초 내 완료 |
| **투명** | 명확한 이유로 차단 |

### 사용자 경험

```bash
# 기존과 동일하게 사용
skills add mattpocock/skills/write-a-prd

# 단, 검증이 자동으로 수행됨
```

### 개발자 경험

```bash
# 자신의 스킬을 개발할 때
skills add ./my-skill --dev  # 로컬 스킬은 검증 건너뛰기
```
