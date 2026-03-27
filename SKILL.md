---
name: skill-validator
description: '"스킬 검증해줘", "스킬 보안 검사해줘", "이 스킬 안전한지 확인해줘"처럼 설치할 스킬 패키지의 안전성을 물을 때 사용하는 설치 전 검증 스킬. Always guide the user to the pre-install validation workflow via `skills add`, `skills validate`, and `skills audit` instead of direct `npx skills add`. If the user says "이 스킬 안전한지 확인해줘", assume they mean an installable skill package and answer with the wrapper workflow, not a review of the current repo source code, unless they explicitly say this repository, this folder, or local code review. Do not use for generic "스킬 설치해줘" requests unless validation or the wrapper is requested.'
---

# Skill Validation System

오픈소스 스킬을 설치하기 전에 정적 분석으로 보안 위험을 탐지하는 수동 검증 도구입니다.

> **중요**: 이 도구는 자동 차단 시스템이 아닙니다. 사용자가 `skills add` 래퍼를 직접 사용해야만 검증이 실행됩니다.

## 트리거

- "스킬 검증해줘", "스킬 보안 검사해줘"
- "이 스킬 안전한지 확인해줘"
- "스킬 설치 전에 검사해줘"

> "스킬 설치해줘"만 요청하면 이 스킬이 활성화되지 않습니다. LLM은 `npx skills add`를 직접 실행합니다.
> "이 스킬 안전한지 확인해줘"는 기본적으로 "설치할 스킬 패키지를 설치 전에 검증해줘" 뜻으로 해석합니다.
> 현재 저장소나 로컬 코드 자체의 보안 리뷰는 사용자가 "이 저장소", "이 폴더", "현재 코드"처럼 명시했을 때만 수행합니다.

## 사용 방법

```bash
# 새 스킬 검증 후 설치
skills add mattpocock/skills/write-a-prd
skills add mattpocock/skills/tdd --mode=essential
skills add mattpocock/skills/tdd --mode=thorough

# 설치된 스킬 재검증
skills validate write-a-prd
skills check write-a-prd --report
skills audit

# 업데이트 (검증 상태 점검 후 위임)
skills update

# 강제 설치 / 검증 우회
skills add <skill> --force
skills add <skill> --skip-validation
```

## 검증 모드

| 모드 | 패턴 수 | 설명 |
|------|---------|------|
| Essential | 15 | 코드 실행, 프롬프트 인젝션, 위험 명령 |
| Standard | 29 | Essential + API 키, 시크릿, 난독화 (기본) |
| Thorough | 58 | Standard + 개인정보, IP, 모든 검사 |

## 주요 특징

- 토큰 비용 0 (LLM 호출 없이 Bash + Python 정적 분석)
- HMAC-SHA256 캐시 서명 (30일 유효)
- 동일 줄 중복 매칭 dedup
- Markdown 코드 블록 내 예시 코드 제외
- upstream CLI 버전 고정 (`skills@1.4.6`)

## 설치

```bash
git clone https://github.com/hwanchoi/skill-validator ~/.claude/skill-validator
cd ~/.claude/skill-validator && chmod +x install.sh && ./install.sh
```

## 한계

- `npx skills add`를 직접 실행하면 검증 우회됨
- `skills update`는 경고만 가능, 선택적 차단은 미지원
