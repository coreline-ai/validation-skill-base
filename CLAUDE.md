# Skill Validator — Developer Guide

> Claude Code가 이 저장소를 작업할 때 참고하는 컨텍스트입니다.

## Repository Layout

| Path | Role |
|------|------|
| `SKILL.md` | 스킬 런타임 문서 — `npx skills add`로 설치 시 Claude Code가 로드 |
| `src/static_analyzer.py` | 정적 분석 엔진 (패턴 매칭, dedup, 판정) |
| `src/validator.sh` | 검증 오케스트레이터 (다운로드, 캐시, HMAC 서명) |
| `src/skills` | CLI 래퍼 (사용자 진입점) |
| `src/patterns*.json` | Essential / Standard / Thorough 패턴 정의 |
| `install.sh` | 설치 스크립트 (`src/` → `~/.claude/skill-validator/`) |

## Documentation Priority

1. **`README.md`** — 현재 동작 기준, 사용법, 아키텍처
2. **`docs/IMPLEMENTATION_COMPLETE.md`** — 구현 현황, 수동 검증 결과
3. **`SKILL.md`** — 스킬 런타임 설명 (Claude Code가 로드)

## Key Constraints

- 검증은 `skills add` 래퍼를 사용해야만 실행됨. `npx skills add`는 우회.
- upstream CLI는 `skills@1.4.6`으로 고정. `SKILLS_CLI_VERSION`은 exact semver만 허용.
- `skills update`는 경고만 가능, 선택적 차단은 upstream CLI 제약으로 미지원.
- `install.sh`는 `src/` 내 런타임 파일만 복사. `SKILL.md`, `CLAUDE.md`, `docs/`는 배포에 포함되지 않음.

## Pattern File Convention

- 3개 파일은 항상 **Essential ⊆ Standard ⊆ Thorough** 포함 관계 유지.
- 동일 ID의 패턴은 파일 간 `regex`, `severity`, `category`가 완전히 일치해야 함.
- `failure_thresholds`는 각 패턴 JSON 최상위에 정의.
- `structural_only: true`인 패턴은 regex 매칭 대신 코드에서 별도 검사.

## Version Management

버전을 변경할 때 아래 **모든 위치**를 함께 수정:

- `README.md` — 상단 뱃지 + Changelog
- `install.sh` — 배너
- `src/patterns.essential.json` — `"version"`
- `src/patterns.standard.json` — `"version"`
- `src/patterns.json` — `"version"`
- `SKILL.md` — (필요시 하단 버전 표기)
