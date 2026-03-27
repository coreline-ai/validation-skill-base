<p align="center">
  <h1 align="center">Skill Validation System</h1>
  <p align="center">
    오픈소스 스킬을 설치하기 전에 정적 분석으로 보안 위험을 탐지하는 수동 검증 도구
  </p>
  <p align="center">
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" alt="License"></a>
    <img src="https://img.shields.io/badge/Version-1.2.0-green.svg" alt="Version">
    <img src="https://img.shields.io/badge/Python-3.x-3776AB.svg" alt="Python">
    <img src="https://img.shields.io/badge/Bash-3.2%2B-4EAA25.svg" alt="Bash">
    <img src="https://img.shields.io/badge/Platform-macOS%20%7C%20Linux-lightgrey.svg" alt="Platform">
  </p>
</p>

---

## Why

`npx skills add`는 스킬을 검증 없이 설치합니다. 이 도구는 설치 흐름 앞에 **정적 분석 게이트**를 끼워 넣어, 위험한 패턴이 포함된 스킬을 사전에 차단합니다.

> **한 줄 요약**: `npx skills add` 대신 `skills add`를 사용하면, 설치 전 자동으로 보안 검증이 실행됩니다.

## Features

| | Feature | Detail |
|---|---------|--------|
| **0 Token** | LLM 호출 없음 | Bash + Python 정적 분석만 사용 |
| **3-Tier** | 검증 모드 | Essential(15) · Standard(29) · Thorough(58) 패턴 |
| **HMAC** | 캐시 서명 | `jq -Sc` canonical JSON + HMAC-SHA256 (30일 유효) |
| **Dedup** | 중복 제거 | 동일 줄 겹치는 정규식 매치를 자동 병합 |
| **Shebang** | 확장자 무관 | 확장자 없는 스크립트도 shebang 기반 탐지 |
| **Fence** | 코드 블록 필터 | `.md` 파일 코드 펜스 안의 예시는 분석 제외 |
| **Pinned** | 공급망 보호 | upstream CLI `skills@1.4.6` 고정, tarball+SHA256 옵션 |

## Quick Start

### Install

```bash
# 자동 설치
curl -fsSL https://raw.githubusercontent.com/hwanchoi/skill-validator/main/install.sh | bash

# 또는 수동 설치
git clone https://github.com/hwanchoi/skill-validator ~/.claude/skill-validator
cd ~/.claude/skill-validator && chmod +x install.sh && ./install.sh
```

### Basic Usage

```bash
# 검증 후 설치 (Standard 모드)
skills add mattpocock/skills/write-a-prd

# 모드 지정
skills add mattpocock/skills/tdd --mode=essential
skills add mattpocock/skills/tdd --mode=thorough

# 설치된 스킬 재검증
skills validate write-a-prd
skills check write-a-prd --report
skills audit

# 업데이트 (검증 상태 점검 → upstream 위임)
skills update
```

## Validation Modes

| Mode | Patterns | FAIL 기준 | Use Case |
|------|:--------:|-----------|----------|
| **Essential** | 15 | `CRITICAL > 0` or `HIGH > 2` | 빠른 1차 확인 |
| **Standard** | 29 | `CRITICAL > 0` or `HIGH > 2` | 기본 모드 |
| **Thorough** | 58 | `CRITICAL > 0` or `HIGH > 2` or `MEDIUM > 5` | 가장 보수적 |

<details>
<summary><b>탐지 범주 상세</b></summary>

### CRITICAL — 즉시 차단

- API 키 (OpenAI, Anthropic, AWS, GitHub)
- 하드코딩된 비밀번호 · 개인키
- 위험 명령어 (`rm -rf /`, `curl | bash`, `dd`)
- 신용카드 · 주민번호 · 주민등록번호
- 악성 키워드 (keylogger, stealer, ransomware, trojan)

### HIGH — 주의 필요

- base64 디코드 + 실행 · hex escape 난독화
- 외부 IP URL (localhost/내부망 제외)
- 일반 API 키/시크릿/토큰 할당
- `eval`/`exec`/`system` 변수 실행 (주석/문서 제외)
- 프롬프트 인젝션 패턴 · 파일 삭제 (루트 경로)

### MEDIUM — 참고

- 긴 base64 · 의심 TLD (`.tk`, `.ml`, `.ga` 등)
- `String.fromCharCode` · `subprocess(shell=True)`
- 이메일/전화번호/IP · 외부 HTTP 요청
- 파일 시스템 수정 기능 (주석/문서 제외)

> 패턴 소스 오브 트루스: `src/patterns.essential.json` · `src/patterns.standard.json` · `src/patterns.json`

</details>

## Example Output

<details>
<summary><b>PASS</b></summary>

```
═══ SKILL VALIDATION ═══

[✓] Repository: mattpocock/skills
[✓] Skill Path: write-a-skill

[→] Downloading skill from mattpocock/skills...
[→] Running static analysis...
[✓] ✓ Approval record saved with signature

═══ VALIDATION PASSED ═══
```

</details>

<details>
<summary><b>FAIL</b></summary>

```
═══ SKILL VALIDATION ═══

[✗] Static analysis failed validation thresholds:

  CRITICAL: 1
  HIGH: 2

CRITICAL: API key detected (line 15)
HIGH: Base64 decode followed by execution (line 42)
HIGH: Direct IP address URL (line 58)

❌ Validation failed. Skill installation blocked.
```

</details>

## Architecture

```
┌──────────────┐     ┌───────────────┐     ┌─────────────────────┐
│  skills CLI  │────▶│ validator.sh  │────▶│ static_analyzer.py  │
│  (래퍼)       │     │ (다운로드/캐시) │     │ (패턴 매칭/판정)     │
└──────────────┘     └───────────────┘     └─────────────────────┘
       │                    │                        │
       ▼                    ▼                        ▼
  npx skills@1.4.6   ~/.claude/            patterns.{essential,
  (검증 통과 시)       skill-approvals/      standard,json}.json
```

### Repository Structure

```
skill-validator/
├── SKILL.md                     # 스킬 런타임 문서 (npx skills가 로드)
├── CLAUDE.md                    # Claude Code 개발 컨텍스트
├── README.md
├── install.sh                   # 설치 스크립트
├── LICENSE
├── src/
│   ├── static_analyzer.py       # 정적 분석 엔진
│   ├── validator.sh             # 검증 오케스트레이터
│   ├── skills                   # CLI 래퍼 (진입점)
│   ├── patterns.essential.json  # 15 patterns
│   ├── patterns.standard.json   # 29 patterns
│   └── patterns.json            # 58 patterns (Thorough)
└── docs/
    ├── IMPLEMENTATION_COMPLETE.md
    ├── SKILLS_VALIDATION_GUIDE.md
    └── archive/
```

### Installed Files

```
~/.claude/
├── skill-validator/             # 런타임 파일
│   ├── static_analyzer.py
│   ├── validator.sh
│   ├── patterns.essential.json
│   ├── patterns.standard.json
│   └── patterns.json
└── skill-approvals/             # 검증 캐시 (HMAC 서명)
    ├── .signing-key
    └── [sha256].json

~/.local/bin/
└── skills                       # CLI 래퍼
```

## Advanced Usage

### Supply Chain Hardening

```bash
# exact semver로 고정 (기본값: 1.4.6)
SKILLS_CLI_VERSION=1.4.6 skills add mattpocock/skills/tdd

# 로컬 tarball + SHA-256 체크섬
SKILLS_CLI_TARBALL=/path/to/skills-1.4.6.tgz \
SKILLS_CLI_TARBALL_SHA256=<sha256> \
skills add mattpocock/skills/tdd
```

### Force Install / Skip Validation

```bash
# 검증 실패를 무시하고 설치 (확인 프롬프트)
skills add <skill> --force

# 검증 자체를 건너뜀 (비권장)
skills add <skill> --skip-validation
```

## Requirements

| Dependency | Version | Note |
|------------|---------|------|
| Python | 3.x | 정적 분석 실행 |
| Git | any | sparse clone |
| jq | any | JSON 처리 |
| Bash | 3.2+ | macOS 기본 호환 |
| sha256sum / shasum / openssl | any | 해시/서명 (하나만 필요) |

### Platform Support

| Platform | Status | Note |
|----------|:------:|------|
| macOS | **Supported** | 네이티브 |
| Linux | **Supported** | 네이티브 |
| Windows | Partial | WSL2 또는 Git Bash 필요 |

## Troubleshooting

<details>
<summary><code>skills: command not found</code></summary>

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

</details>

<details>
<summary><code>jq: command not found</code></summary>

```bash
brew install jq        # macOS
sudo apt install jq    # Debian/Ubuntu
```

</details>

<details>
<summary>캐시 초기화</summary>

```bash
rm ~/.claude/skill-approvals/*.json
skills add <skill>
```

`.signing-key`는 그대로 두어도 됩니다. 서명 키까지 재생성하려면 함께 삭제하세요.

</details>

## Known Limitations

- **수동 도구**: `skills add` 래퍼를 사용해야만 검증이 실행됩니다. 직접 `npx skills add`를 실행하면 우회됩니다.
- **선택적 차단 미지원**: `skills update`는 미검증 스킬을 경고할 수 있지만, upstream CLI 제약으로 선택적 스킵은 불가합니다.
- **hooks 미포함**: 현재 Claude Code 훅이나 `settings.json` 기반 자동 차단 로직은 포함되어 있지 않습니다.

## Documentation

| Document | Description |
|----------|-------------|
| [IMPLEMENTATION_COMPLETE.md](docs/IMPLEMENTATION_COMPLETE.md) | 현재 구현 현황 · 수동 검증 결과 |
| [SKILLS_VALIDATION_GUIDE.md](docs/SKILLS_VALIDATION_GUIDE.md) | mattpocock/skills 검증 시나리오 가이드 |
| [docs/archive/](docs/archive/) | 초기 설계 · 검토 문서 보관 |

## Changelog

### v1.2.0 (2026-03-28)

**Analysis Engine**
- 동일 줄 중복 매칭 dedup 로직 도입
- shebang 기반 확장자 없는 스크립트 분석 지원
- `.jsx` · `.tsx` · `.mjs` · `.cjs` · `.zsh` 확장자 추가
- Markdown 코드 블록 내 예시 코드 분석 제외
- `failure_thresholds`를 패턴 JSON에서 로드하도록 메타데이터화
- `structural_only` 플래그로 구조 검사와 regex 매칭 분리
- `skipped_files` 보고로 분석 커버리지 가시화

**Pattern Quality**
- OWASP 패턴(prompt inject, insecure output, excessive agency) 주석/문서 제외
- `malware_keylogger`의 `key.?log` 오탐 완화
- `password_hardcoded` placeholder/example 제외
- `network_ip_url` localhost/내부망 IP 제외
- `ssn_pattern` · `credit_card` · `korean_rrn` 경계/구분자 필수화
- Thorough 모드에 `MEDIUM > 5` 임계값 추가

**Security & Infra**
- upstream CLI `skills@1.4.6` 고정 + tarball/SHA256 공급망 hardening
- approval에 `installed_path` 바인딩
- `is_validator_system` 판별 강화
- 임시 디렉토리를 `mktemp -d`로 변경
- 자체 플래그를 npx에 전달하지 않도록 필터링

**Docs**
- SKILL.md 이중 구조 통합 (루트 = 런타임 문서)
- CLAUDE.md 신규 (개발 컨텍스트)
- 문서 정합성 수정 (경로, 버전, 의존성)

### v1.1.0 (2026-03-21)

- 3단계 검증 모드 도입: Essential / Standard / Thorough
- HMAC 기반 캐시 무결성 검증 추가
- 로컬 스킬 검증 명령 (`validate`, `check`, `audit`)
- 패턴 수 53 → 58개 확장

### v1.0.0 (2026-03-21)

- 초기 수동 검증 래퍼 구현
- 53개 패턴 기반 정적 분석

## License

[Apache 2.0](LICENSE)

---

<p align="center">
  보안 검증이 자동으로 일어나지 않는다면, <b>사용 습관이 곧 보안 정책</b>입니다.<br>
  스킬 설치 전에는 항상 <code>skills add</code> 래퍼를 사용하세요.
</p>
