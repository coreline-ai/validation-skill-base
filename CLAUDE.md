# Validation Skills — 개발자 가이드

이 파일은 Claude Code가 이 저장소를 작업할 때 참고하는 컨텍스트입니다.

## 저장소 구성

- `src/validator.sh`: 원격 스킬 다운로드, 분석 실행, 캐시 서명 검증
- `src/static_analyzer.py`: 패턴 기반 정적 분석기
- `src/skills`: `npx skills` 래퍼 (CLI 진입점)
- `src/patterns*.json`: Essential/Standard/Thorough 패턴 정의
- `install.sh`: 설치 스크립트

## 문서 우선순위

1. 현재 동작 기준 설명은 `README.md`
2. 구현 현황과 검증 결과는 `docs/IMPLEMENTATION_COMPLETE.md`
3. 스킬로서의 런타임 설명은 `SKILL.md` (루트)

## 현재 구현의 중요한 한계

- 검증은 사용자가 `skills add ...` 래퍼를 직접 사용할 때만 실행됩니다.
- 직접 `npx skills add ...`를 실행하면 이 저장소가 개입하지 못합니다.
- `skills update`는 검증 상태를 점검하고 경고하지만, upstream CLI 제약 때문에 현재는 선택적 업데이트 차단까지는 하지 못합니다.
