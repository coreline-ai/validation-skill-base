# Skill Validation System

> 오픈소스 스킬을 설치하기 전에 정적 분석으로 위험 신호를 점검하는 수동 검증 도구 v1.2.0

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-1.2.0-green.svg)]()

## 개요

**Skill Validation System**은 오픈소스 스킬을 설치하기 전에 다운로드한 파일을 정적 분석하여 위험 패턴을 찾는 수동 검증 도구입니다.

이 프로젝트의 핵심은 `npx skills`를 직접 대체하는 것이 아니라, 사용자가 `skills ...` 래퍼를 통해 설치 흐름을 시작할 때 검증을 끼워 넣는 것입니다.

## 현재 구현 범위

| 시나리오 | 현재 동작 |
|----------|----------|
| `skills add <repo/skill>` | 원격 스킬 다운로드 후 검증 수행 |
| `skills validate <name>` | 설치된 로컬 스킬 재검증 |
| `skills check <name> --report` | 설치된 로컬 스킬 상세 보고서 출력 |
| `skills audit` | 설치된 스킬 전체 순회 검증 |
| `skills update` | 검증 상태를 점검하고 경고 후 upstream `skills update`에 위임 |
| 직접 `npx skills add ...` 실행 | 검증 불가 |
| LLM에게 "스킬 설치해줘" 요청 | 보통 검증 없이 직접 설치로 흐를 수 있음 |

## 핵심 특징

- 토큰 비용 0: LLM 호출 없이 Bash + Python 정적 분석만 사용
- 3단계 검증 모드: Essential 15개, Standard 29개, Thorough 58개 패턴
- 캐시 무결성: `jq -Sc` 기반 canonical JSON + HMAC-SHA256 서명 사용
- 원격/로컬 검증 지원: 새 스킬 설치 전 검증과 설치된 스킬 재검증 모두 지원
- 설치 경로 바인딩: approval에 `installed_path`를 기록해 update/audit에서 이름 충돌을 줄임
- 분석 정확도 보강: 동일 줄 중복 매칭 dedup, shebang 기반 확장자 없는 스크립트 분석 지원
- 확장자 보강: `.jsx`, `.tsx`, `.mjs`, `.cjs`, `.zsh`도 분석 대상
- 정책 메타데이터화: PASS/FAIL 임계값을 패턴 JSON의 `failure_thresholds`에서 읽음
- 구조 검사 강화: 읽을 수 없는 `SKILL.md`는 `CRITICAL`로 처리
- 분석 커버리지 가시화: 읽지 못한 파일은 `skipped_files`로 보고
- 수동 설치 흐름 보강: `skills` 래퍼로 `add`, `validate`, `check`, `audit`, `update` 제공
- upstream CLI 고정: 기본적으로 `skills@1.4.6`을 사용하고 `SKILLS_CLI_VERSION`은 exact semver만 허용
- 공급망 hardening 옵션: `SKILLS_CLI_TARBALL`과 `SKILLS_CLI_TARBALL_SHA256`로 로컬 tarball + checksum 고정 가능

## 중요한 한계

- 이 도구는 자동 차단 시스템이 아닙니다. 사용자가 `skills add ...` 래퍼를 직접 사용해야만 검증이 실행됩니다.
- 현재 저장소에는 Claude Code 훅이나 `settings.json` 기반 차단 로직이 포함되어 있지 않습니다.
- `skills update`는 검증 상태를 확인해 경고할 수는 있지만, upstream `skills` CLI가 전체 업데이트만 제공하므로 현재 버전은 검증되지 않은 스킬만 선택적으로 건너뛰지는 못합니다.
- 현재 approval 매칭은 가능하면 `installed_path`를 우선 사용하고, 경로 정보가 없는 오래된 approval은 `update/audit`에서 자동 신뢰하지 않습니다.
- 따라서 과거 approval만 남아 있거나 동일 이름 스킬이 경로 바인딩 없이 이미 공존하던 환경에서는 완전한 출처 구분이 아직 어려울 수 있습니다.
- upstream `npx skills`가 machine-readable 출력이나 lockfile schema를 명확히 제공하면, 설치 스킬과 원본 repo 매핑은 그 기준으로 다시 정리하는 편이 안전합니다.

## 검증 모드

| 모드 | 패턴 수 | 설명 | 기본 용도 |
|------|---------|------|----------|
| Essential | 15 | 코드 실행, 프롬프트 인젝션, 위험 명령 | 빠른 1차 확인 |
| Standard | 29 | Essential + API 키, 시크릿, 난독화 | 기본 모드 |
| Thorough | 58 | Standard + 개인정보, IP, 추가 의심 신호 | 가장 보수적인 점검 (`CRITICAL > 0`, `HIGH > 2`, 또는 `MEDIUM > 5`면 FAIL) |

```bash
skills add mattpocock/skills/write-a-prd --mode=essential
skills add mattpocock/skills/write-a-prd --mode=standard
skills add mattpocock/skills/write-a-prd --mode=thorough
```

## 탐지 범주

실제 패턴 정의는 다음 파일이 소스 오브 트루스입니다.

- `src/patterns.essential.json`
- `src/patterns.standard.json`
- `src/patterns.json`

현재 패턴은 대략 다음 범주를 다룹니다.

- CRITICAL: API 키, 개인키, 하드코딩된 비밀번호, `rm -rf /`, `curl | bash`, 디스크 직접 쓰기, 신용카드/주민번호
- HIGH: base64 디코드 후 실행, hex escape 난독화, IP 기반 URL, 일반 토큰 할당, 프롬프트 인젝션, 악성 키워드
- MEDIUM: 긴 base64, 의심스러운 TLD, `String.fromCharCode`, 이메일/전화번호/IP, 외부 요청

## 설치 방법

### 자동 설치

```bash
curl -fsSL https://raw.githubusercontent.com/hwanchoi/skill-validator/main/install.sh | bash
```

### 수동 설치

```bash
git clone https://github.com/hwanchoi/skill-validator ~/.claude/skill-validator
cd ~/.claude/skill-validator
chmod +x install.sh
./install.sh
```

### 지원 플랫폼

| 플랫폼 | 지원 여부 | 비고 |
|--------|----------|------|
| macOS | ✅ | 기본 유틸리티 + `jq` 필요 |
| Linux | ✅ | 기본 유틸리티 + `jq` 필요 |
| Windows | ⚠️ | WSL2 또는 Git Bash 권장 |

## 사용 방법

### 새 스킬 설치 전 검증

```bash
# 기본 모드(Standard)
skills add mattpocock/skills/write-a-prd

# 모드 지정
skills add mattpocock/skills/tdd --mode=essential
skills add mattpocock/skills/tdd --mode=thorough

# 검증 실패를 무시하고 설치
skills add <skill> --force

# 검증 자체를 건너뜀
skills add <skill> --skip-validation
```

### 설치된 스킬 검증

```bash
skills validate write-a-prd
skills validate write-a-prd --mode=thorough
skills check write-a-prd --report
skills audit
```

### 업데이트

```bash
skills update
```

현재 `skills update`는 설치된 스킬들의 검증 상태를 확인하고 경고를 보여준 뒤 기본값 기준 upstream `npx skills@1.4.6 update`를 실행합니다. 즉, "검증 상태 점검"은 되지만 "선택적 업데이트 차단"은 아직 구현되지 않았습니다.

현재 래퍼는 설치된 스킬을 `~/.agents/skills`, `~/.claude/skills`, `~/.codex/skills`, `~/.skills`와 최신 `npx skills list/-g` 출력에서 함께 탐색합니다.

기본 upstream 호출은 `skills@1.4.6`으로 고정되며, 필요하면 `SKILLS_CLI_VERSION=1.4.6` 같은 exact semver만 허용됩니다. `latest` 같은 태그는 거부합니다.

더 강하게 고정하려면 로컬 tarball 경로와 SHA-256을 함께 지정할 수 있습니다.

```bash
SKILLS_CLI_TARBALL=/path/to/skills-1.4.6.tgz
SKILLS_CLI_TARBALL_SHA256=<sha256>
```

## 예시 출력

### PASS

```text
═══ SKILL VALIDATION ═══

[✓] Repository: mattpocock/skills
[✓] Skill Path: write-a-skill

[→] Downloading skill from mattpocock/skills...
[→] Running static analysis...
[✓] ✓ Approval record saved with signature

═══ VALIDATION PASSED ═══
```

### FAIL

```text
═══ SKILL VALIDATION ═══

[✗] Static analysis detected severe issues:

CRITICAL: API key detected (line 15)
HIGH: Base64 decode followed by execution (line 42)
HIGH: Direct IP address URL (line 58)

❌ Validation failed. Skill installation blocked.
```

## 저장소 구조

```text
skill-validator/
├── SKILL.md                      # 스킬 런타임 문서 (npx skills가 로드)
├── CLAUDE.md                     # Claude Code 개발 컨텍스트
├── README.md
├── install.sh
├── LICENSE
├── src/
│   ├── patterns.essential.json
│   ├── patterns.standard.json
│   ├── patterns.json
│   ├── static_analyzer.py
│   ├── validator.sh
│   └── skills
└── docs/
    ├── IMPLEMENTATION_COMPLETE.md
    ├── SKILLS_VALIDATION_GUIDE.md
    └── archive/
```

## 설치 후 파일 구조

`install.sh`는 다음 파일만 설치합니다.

```text
~/.claude/
├── skill-validator/
│   ├── patterns.essential.json
│   ├── patterns.standard.json
│   ├── patterns.json
│   ├── static_analyzer.py
│   └── validator.sh
└── skill-approvals/
    └── [sha256].json

~/.local/bin/
└── skills
```

저장소 문서(`README.md`, `CLAUDE.md`, `docs/`)는 설치 대상이 아니라 소스 저장소 자산입니다.

## 구현 요약

- `SKILL.md`: 스킬 런타임 문서 (`npx skills add`로 설치 시 Claude Code가 로드)
- `CLAUDE.md`: Claude Code가 이 저장소 작업 시 참고하는 개발자 가이드
- `src/static_analyzer.py`: 패턴 로드, `failure_thresholds`/`structural_only` 메타데이터 반영, 파일 순회, 중복 매칭 dedup, shebang/`.zsh`/`.tsx` 계열 검사, Markdown 코드 블록 필터, `skipped_files` 기록, PASS/FAIL 결정
- `src/validator.sh`: 원격 스킬 다운로드, canonical JSON 기반 캐시 서명 검증, 로컬/원격 approval 기록 저장
- `src/skills`: 사용자가 직접 쓰는 CLI 래퍼, 설치된 스킬 탐색, approval `installed_path` 바인딩, update/audit 상태 점검
- `install.sh`: 런타임 파일을 `~/.claude/skill-validator`와 `~/.local/bin`에 복사

## 의존성

- Python 3
- Git
- jq
- Bash 3.2+
- `sha256sum` 또는 `shasum` 또는 `openssl`

## 트러블슈팅

### `skills: command not found`

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### `jq: command not found`

```bash
brew install jq
# 또는
sudo apt install jq
```

### 캐시를 초기화하고 다시 검증하고 싶을 때

```bash
rm ~/.claude/skill-approvals/*.json
skills add <skill>
```

`skill-approvals/.signing-key`는 그대로 두어도 됩니다. 서명 키까지 바꾸고 싶다면 해당 파일도 함께 삭제하면 됩니다.

## 문서

- [docs/IMPLEMENTATION_COMPLETE.md](docs/IMPLEMENTATION_COMPLETE.md): 현재 워크트리 기준 구현 현황
- [docs/SKILLS_VALIDATION_GUIDE.md](docs/SKILLS_VALIDATION_GUIDE.md): `skills-main` 검증 시나리오 가이드
- [docs/archive/](docs/archive/): 초기 설계와 검토 문서 보관

## Changelog

### v1.2.0 (2026-03-28)

- 동일 줄 중복 매칭 dedup 로직 도입 (PASS/FAIL 오판 방지)
- shebang 기반 확장자 없는 스크립트 분석 지원
- `.jsx`, `.tsx`, `.mjs`, `.cjs`, `.zsh` 확장자 추가
- PASS/FAIL 임계값을 패턴 JSON `failure_thresholds`에서 로드하도록 메타데이터화
- Thorough 모드에 `MEDIUM > 5` 임계값 추가
- 구조 검사(`SKILL.md` 존재, YAML frontmatter)를 `structural_only` 플래그로 분리
- 읽지 못한 파일을 `skipped_files`로 보고
- OWASP 패턴(prompt inject, insecure output) 주석/문서 제외 로직 추가
- `owasp_llm08` 패턴에 주석/문서 제외 적용
- `malware_keylogger` 패턴 `key.?log` 오탐 완화
- `password_hardcoded` placeholder/example 등 제외 (negative lookahead)
- `network_ip_url` localhost/내부망 IP 제외
- `network_no_tld` 정상 URL 오탐 수정
- `ssn_pattern`, `credit_card`, `korean_rrn` 경계/구분자 필수화로 오탐 완화
- `.md` 파일 코드 블록 내 예시 코드 분석 제외
- upstream CLI `skills@1.4.6` 고정 + `SKILLS_CLI_TARBALL`/`SKILLS_CLI_TARBALL_SHA256` 공급망 hardening
- approval에 `installed_path` 바인딩으로 update/audit 이름 충돌 감소
- `is_validator_system` 판별을 `install.sh` + 3파일 동시 존재로 강화
- 임시 디렉토리를 `mktemp -d`로 변경 (보안)
- 자체 플래그(`--mode`, `--force`, `--skip-validation`)를 npx에 전달하지 않도록 필터링
- 문서 정합성 수정: `.signing-key` 경로, clone 경로, Bash 버전 요구사항

### v1.1.0 (2026-03-21)

- 3단계 검증 모드 도입: Essential/Standard/Thorough
- HMAC 기반 캐시 무결성 검증 추가
- 로컬 스킬 검증 명령(`validate`, `check`, `audit`) 정리
- 패턴 수 53개에서 58개로 확장
- 문서를 현재 구현 기준으로 다시 정렬

### v1.0.0 (2026-03-21)

- 초기 수동 검증 래퍼 구현
- 53개 패턴 기반 정적 분석 도입

## 라이선스

Apache 2.0. 자세한 내용은 [LICENSE](LICENSE)를 참고하세요.

---

보안 검증이 자동으로 일어나지 않는다면, 사용 습관이 곧 보안 정책입니다. 스킬 설치 전에는 항상 `skills add ...` 래퍼를 사용하세요.
