# Skill Validation System 구현 현황

이 문서는 `validation-skills` 저장소의 **현재 워크트리 기준 구현 상태**를 기록합니다. 초기 설계 문서나 보관 문서와 달리, 이 문서는 지금 실제로 존재하는 파일과 현재 확인된 동작만 다룹니다.

## 1. 현재 저장소에 존재하는 핵심 파일

```text
validation-skills/
├── SKILL.md
├── CLAUDE.md
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

## 2. 구현 완료된 기능

### 2.1 정적 분석

- `src/static_analyzer.py`
- 패턴 JSON 로드 후 파일 단위 정규식 검사 수행
- `failure_thresholds` 메타데이터로 PASS/FAIL 임계값을 로드
- `structural_only` 메타데이터로 구조 검사를 regex 매칭과 분리
- 읽을 수 없는 `SKILL.md`는 `structure_skill_md_unreadable` CRITICAL 이슈로 처리
- 같은 줄에서 겹치는 정규식 매치 dedup 처리
- shebang 기반으로 확장자 없는 스크립트도 검사
- `.jsx`, `.tsx`, `.mjs`, `.cjs`, `.zsh` 확장자도 검사
- `SKILL.md` 존재 여부와 YAML frontmatter를 구조적으로 검사
- 읽지 못한 파일은 `skipped_files`로 기록
- 심각도 집계 후 PASS/FAIL 판정
- Thorough 모드에서는 `MEDIUM > 5`도 FAIL로 처리

### 2.2 원격 스킬 검증

- `src/validator.sh`
- Git sparse clone으로 필요한 스킬 경로만 다운로드
- 분석 결과를 `~/.claude/skill-approvals/*.json`에 저장
- `jq -Sc` canonical JSON + HMAC-SHA256 서명으로 캐시 무결성 검증
- 로컬 재검증(`validate`/`check`)도 approval 기록 저장
- 로컬 approval은 `installed_path`를 포함하고 경로 기반 해시를 사용

### 2.3 CLI 래퍼

- `src/skills`
- 제공 명령:
  - `add`
  - `validate`
  - `check`
  - `audit`
  - `list`
  - `remove`
  - `update`
- 설치된 스킬 탐색 경로:
  - `~/.agents/skills`
  - `~/.claude/skills`
  - `~/.codex/skills`
  - `~/.skills`
- 최신 `npx skills list` / `list -g` 출력도 함께 파싱해 installed skill 탐색을 보강
- upstream CLI는 기본적으로 `skills@1.4.6`으로 고정 호출하며 `SKILLS_CLI_VERSION`은 exact semver만 허용
- 필요하면 `SKILLS_CLI_TARBALL` + `SKILLS_CLI_TARBALL_SHA256`로 로컬 tarball을 checksum과 함께 고정 가능
- `add` 성공 후 approval에 `installed_path`를 바인딩해 update/audit의 이름 충돌을 줄임

### 2.4 설치 스크립트

- `install.sh`
- 런타임 파일을 `~/.claude/skill-validator/`와 `~/.local/bin/skills`로 복사
- `jq`, `python3`, `git` 의존성 확인

## 3. 현재 패턴 수

실제 JSON 기준 패턴 수는 다음과 같습니다.

| 파일 | 패턴 수 |
|------|---------|
| `src/patterns.essential.json` | 15 |
| `src/patterns.standard.json` | 29 |
| `src/patterns.json` | 58 |

즉, 현재 기준 정식 카운트는 **15 / 29 / 58**입니다.

## 4. 설치 산출물

`install.sh` 실행 시 현재 설치되는 파일은 다음과 같습니다.

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

주의:

- 저장소 루트 `SKILL.md`는 스킬 런타임 문서이며, `CLAUDE.md`와 함께 `install.sh`가 설치하지 않습니다.
- 현재 저장소에는 훅 스크립트나 `settings.json` 기반 차단 로직이 포함되어 있지 않습니다.
- 실제 설치된 스킬 본체는 upstream `npx skills`가 관리하며, 현재 실검증에서 `~/.agents/skills/...` 경로를 확인했습니다.

## 5. 수동 검증 결과

다음 항목을 현재 워크트리에서 확인했습니다.

### 5.1 구문 검증

```bash
bash -n src/validator.sh
bash -n src/skills
python3 -m py_compile src/static_analyzer.py
jq empty src/patterns.essential.json
jq empty src/patterns.standard.json
jq empty src/patterns.json
```

결과: 통과

### 5.2 원격 스킬 검증 실행

임시 HOME에서 아래 명령을 실행했습니다.

```bash
HOME="$(mktemp -d)" bash src/validator.sh mattpocock/skills/write-a-skill --mode=essential
```

결과:

- 원격 저장소 다운로드 성공
- 정적 분석 실행 성공
- `VALIDATION PASSED` 확인

### 5.3 캐시 히트 확인

임시 HOME에서 한 번 승인된 스킬에 대해 아래 명령을 다시 실행했습니다.

```bash
"$HOME/.claude/skill-validator/validator.sh" mattpocock/skills/write-a-skill --mode=essential
```

결과:

- `Using cached validation` 확인
- canonical JSON 서명 검증 후 캐시 재사용 확인

### 5.4 중복 매칭 dedup 확인

샘플 파일에 `eval($foo)`와 `exec($bar)`를 넣고 Essential 모드로 분석했습니다.

결과:

- HIGH 2건으로 집계
- `owasp_llm02_insecure_output` 중복 카운팅으로 HIGH가 부풀지 않음

### 5.5 확장자 없는 스크립트 검사 확인

shebang이 있는 확장자 없는 파일 `runner`에 `curl ... | bash`를 넣고 Essential 모드로 분석했습니다.

결과:

- `dangerous_curl_pipe`가 CRITICAL로 탐지됨
- 확장자 없는 실행 파일도 검사 대상에 포함됨

### 5.6 래퍼 end-to-end 확인

임시 HOME에 설치 후 아래 흐름을 확인했습니다.

```bash
skills add mattpocock/skills/write-a-skill -g -y --mode=essential
skills validate write-a-skill --mode=essential
skills audit
skills update
```

결과:

- `skills validate`: PASS
- `skills audit`: 설치된 스킬 1건을 찾아 PASS
- `skills update`: 검증 상태 확인 후 upstream update로 정상 위임

## 6. 현재 구현의 제한 사항

### 6.1 자동 차단 미구현

이 저장소는 현재 **수동 래퍼 기반 검증 도구**입니다.

- `skills add ...`를 사용하면 검증이 수행됨
- 직접 `npx skills add ...`를 실행하면 이 저장소가 개입하지 못함
- LLM이 래퍼 대신 `npx skills`를 직접 호출하면 우회될 수 있음

### 6.2 update 동작의 한계

`src/skills`는 업데이트 전에 검증 상태를 확인하고 경고를 보여주지만, 최종적으로 기본값 기준 upstream `npx skills@1.4.6 update`를 호출합니다.

따라서 현재 구현은:

- 검증 상태 점검: 가능
- 미검증 스킬 경고: 가능
- 미검증 스킬만 선택적으로 업데이트 제외: 불가

이 한계는 upstream `skills` CLI가 `update all skills`만 제공하는 현재 인터페이스에도 영향을 받습니다.

추가로 현재 approval 매칭은 가능하면 `installed_path`를 우선 사용하고, 경로 정보가 없는 오래된 approval은 `update/audit`에서 자동으로 신뢰하지 않습니다. 따라서 오래된 approval만 남아 있는 환경에서는 재검증이 한 번 더 필요할 수 있습니다.

upstream `skills` CLI가 machine-readable 출력이나 lockfile schema를 안정적으로 제공하면, 향후에는 그 기준으로 source-to-installed mapping을 교체하는 편이 맞습니다.

### 6.3 문서 자산과 런타임 자산 분리

- 저장소 루트 `SKILL.md`: `npx skills add`로 설치 시 Claude Code가 로드하는 스킬 런타임 문서
- `CLAUDE.md`: Claude Code가 이 저장소를 작업할 때 참고하는 개발자 가이드

설치 스크립트(`install.sh`)는 `src/` 내 런타임 실행 파일만 복사합니다.

## 7. 이번 문서 정리에서 반영한 사항

- 오래된 53개 패턴 표기를 58개 기준으로 정리
- 저장소에 없는 hook/settings 관련 설명 제거
- `skills update`의 실제 동작과 한계를 문서에 명시
- 루트 `SKILL.md`를 추가해 저장소 구조 설명과 실제 파일 구조를 맞춤

## 8. 다음 우선순위

1. installed skill과 원본 repo를 1:1로 매핑할 수 있는 upstream metadata 경로 조사
2. selective update 제한을 우회할 수 있는지 upstream CLI 옵션 조사
3. 필요하면 실제 차단용 훅을 별도 기능으로 재도입
