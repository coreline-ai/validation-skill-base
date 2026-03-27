# Skills Validation Guide

> Legacy guide: 이 문서는 원래 `skills-main` 검증 워크시트를 기반으로 작성되었습니다. 현재 설치/검증의 소스 오브 트루스는 [README.md](/Users/hwanchoi/projects_202603/collect_skills_claude/validation-skills/README.md)이며, 스킬 설치는 직접 `skills ...` 래퍼를 사용해야 합니다.

이 가이드는 `skills-main` 계열 스킬을 검증할 때 참고하는 체크리스트입니다. 현재 명령 예시는 validator 래퍼 기준으로 갱신되었습니다.

## 목차

- [사전 준비](#사전-준비)
- [스킬 설치](#스킬-설치)
- [카테고리별 검증 방법](#카테고리별-검증-방법)
- [검증 체크리스트](#검증-체크리스트)

---

## 사전 준비

### 1. 필수 도구 설치

```bash
# GitHub CLI (gh issue 생성 필요)
brew install gh

# Node.js 및 패키지 매니저
# npm, pnpm, yarn 중 하나 사용
```

### 2. GitHub 인증

```bash
gh auth login
```

### 3. validator 래퍼 설치

```bash
git clone https://github.com/hwanchoi/skill-validator ~/skill-validator
cd ~/skill-validator
./install.sh
```

---

## 스킬 설치

### 개별 설치

```bash
# Planning & Design
skills add mattpocock/skills/write-a-prd
skills add mattpocock/skills/prd-to-plan
skills add mattpocock/skills/prd-to-issues
skills add mattpocock/skills/grill-me
skills add mattpocock/skills/design-an-interface
skills add mattpocock/skills/request-refactor-plan

# Development
skills add mattpocock/skills/tdd
skills add mattpocock/skills/triage-issue
skills add mattpocock/skills/improve-codebase-architecture
skills add mattpocock/skills/migrate-to-shoehorn
skills add mattpocock/skills/scaffold-exercises

# Tooling & Setup
skills add mattpocock/skills/setup-pre-commit
skills add mattpocock/skills/git-guardrails-claude-code

# Writing & Knowledge
skills add mattpocock/skills/write-a-skill
skills add mattpocock/skills/edit-article
skills add mattpocock/skills/ubiquitous-language
skills add mattpocock/skills/obsidian-vault
```

### 설치 확인

```bash
skills list
```

---

## 카테고리별 검증 방법

### 1. Planning & Design 스킬

#### write-a-prd

**검증 시나리오:**
```
"사용자 인증 기능을 위한 PRD를 작성해줘"
```

**예상 결과:**
- 사용자 인터뷰 진행
- 코드베이스 탐색
- 모듈 설계 제안
- GitHub 이슈로 PRD 생성

**검증 포인트:**
- [ ] PRD 템플릿이 올바르게 적용되었는가?
- [ ] User Stories가 충분히 상세한가?
- [ ] Implementation Decisions에 구현 세부사항(파일路径 등)이 포함되지 않았는가?

---

#### prd-to-plan

**검증 시나리오:**
```
"이 PRD를 구현 계획으로 변환해줘"
```

**예상 결과:**
- `./plans/` 디렉토리 생성
- Markdown 파일로 계획 저장
- Vertical slices로 phased plan 작성

**검증 포인트:**
- [ ] plans 폴더가 생성되었는가?
- [ ] 각 phase가 vertical slice인가?
- [ ] Durable decisions가 포함되었는가?

---

#### prd-to-issues

**검증 시나리오:**
```
"PRD #123을 GitHub 이슈로 변환해줘"
```

**예상 결과:**
- 복수의 GitHub 이슈 생성
- 의존성 관계 (Blocked by) 설정
- HITL/AFK 슬라이스 구분

**검증 포인트:**
- [ ] 이슈가 의존성 순서대로 생성되었는가?
- [ ] Vertical slice 형태인가?
- [ ] Parent PRD 참조가 있는가?

---

#### grill-me

**검증 시나리오:**
```
"이 설계안에 대해 grill-me 해줘"
```

**예상 결과:**
- 집요한 질문 세션
- 결정 나무의 모든 분기 탐색
- 추천 답변 제공

**검증 포인트:**
- [ ] 모든 결정 지점이 탐색되었는가?
- [ ] 코드베이스 탐색으로 답변 가능한 경우 탐색했는가?

---

#### design-an-interface

**검증 시나리오:**
```
"사용자 관리 모듈의 인터페이스를 설계해줘"
```

**예상 결과:**
- 3개 이상의 병렬 하위 에이전트 실행
- 각기 다른 제약조건을 가진 인터페이스 제안
- 비교 분석 및 종합 제안

**검증 포인트:**
- [ ] 3개 이상의 다른 설계가 제시되었는가?
- [ ] 각 설계가 근본적으로 다른가?
- [ ] Trade-off 분석이 있는가?

---

#### request-refactor-plan

**검증 시나리오:**
```
"인증 로직을 리팩토링하는 계획을 세워줘"
```

**예상 결과:**
- 상세한 인터뷰
- Tiny commits로 구분된 계획
- GitHub 이슈로 RFC 생성

**검증 포인트:**
- [ ] 각 commit이 독립적으로 동작하는가?
- [ ] Martin Fowler의 조언이 반영되었는가?

---

### 2. Development 스킬

#### tdd

**검증 시나리오:**
```
"TDD로 사용자 로그인 기능을 구현해줘"
```

**예상 결과:**
- Red-Green-Refactor 루프
- Vertical slices (한 테스트 → 한 구현)
- 동작을 검증하는 테스트

**검증 포인트:**
- [ ] 수직 슬라이스로 진행되었는가? (수평 슬라이스 아님)
- [ ] 테스트가 public interface만 검증하는가?
- [ ] 테스트가 내부 리팩토링 후에도 통과하는가?

---

#### triage-issue

**검증 시나리오:**
```
"로그인이 안 되는 버그가 있어. 조사해줘"
```

**예상 결과:**
- 코드베이스 탐색
- 근본 원인 식별
- TDD 수정 계획과 함께 GitHub 이슈 생성

**검증 포인트:**
- [ ] Root cause가 명확히 식별되었는가?
- [ ] 수정 계획이 내부 구조에 의존하지 않는가?
- [ ] GitHub 이슈가 생성되었는가?

---

#### improve-codebase-architecture

**검증 시나리오:**
```
"이 코드베이스의 아키텍처 개선 기회를 찾아줘"
```

**예상 결과:**
- 코드베이스 탐색 (Explore 에이전트)
- 얕은 모듈 식별
- 깊은 모듈로 통합 제안

**검증 포인트:**
- [ ] 마찰 지점이 식별되었는가?
- [ ] Dependency category가 분류되었는가?
- [ ] GitHub 이슈 RFC가 생성되었는가?

---

#### migrate-to-shoehorn

**검증 시나리오:**
```
"테스트 파일의 as 단언을 shoehorn으로 변환해줘"
```

**예상 결과:**
- @total-typescript/shoehorn 설치
- `as Type` → `fromPartial()` 변환
- `as unknown as Type` → `fromAny()` 변환

**검증 포인트:**
- [ ] 패키지가 설치되었는가?
- [ ] import 문이 추가되었는가?
- [ ] 타입 체크가 통과하는가?

---

#### scaffold-exercises

**검증 시나리오:**
```
"TDD 연습 섹션을 스캐폴딩해줘"
```

**예상 결과:**
- 섹션 및 연습 디렉토리 생성
- readme.md 스텁 생성
- `pnpm ai-hero-cli internal lint` 통과

**검증 포인트:**
- [ ] 디렉토리 명명 규칙을 따르는가?
- [ ] readme가 비어있지 않은가?
- [ ] Lint가 통과하는가?

---

### 3. Tooling & Setup 스킬

#### setup-pre-commit

**검증 시나리오:**
```
"pre-commit 훅을 설정해줘"
```

**예상 결과:**
- Husky 설치 및 초기화
- lint-staged 설정
- Prettier config 생성
- pre-commit 훅 생성

**검증 포인트:**
- [ ] .husky/pre-commit이 존재하는가?
- [ ] .lintstagedrc가 존재하는가?
- [ ] package.json에 prepare 스크립트가 있는가?
- [ ] Commit이 훅을 통해 실행되는가?

---

#### git-guardrails-claude-code

**검증 시나리오:**
```
"Claude Code에서 위험한 git 명령을 차단하도록 설정해줘"
```

**예상 결과:**
- 훅 스크립트 복사
- settings.json에 훅 등록
- 위험한 명령 테스트 차단

**검증 포인트:**
- [ ] .claude/hooks/block-dangerous-git.sh가 존재하는가?
- [ ] settings.json에 PreToolUse 훅이 있는가?
- [ ] git push가 차단되는가?

**테스트 명령:**
```bash
echo '{"tool_input":{"command":"git push origin main"}}' | .claude/hooks/block-dangerous-git.sh
# Should exit with code 2
```

---

### 4. Writing & Knowledge 스킬

#### write-a-skill

**검증 시나리오:**
```
"새로운 스킬을 작성하고 싶어. 도와줘"
```

**예상 결과:**
- 요구사항 수집
- SKILL.md 생성
- 구조 검토

**검증 포인트:**
- [ ] description에 "Use when" 트리거가 포함되었는가?
- [ ] SKILL.md가 100줄 이내인가?
- [ ] 적절한 파일 구조인가?

---

#### edit-article

**검증 시나리오:**
```
"이 문서를 편집해줘"
```

**예상 결과:**
- 섹션별 재구성
- 명확성 개선
- 문단 간결화 (최대 240자)

**검증 포인트:**
- [ ] 정보 의존성이 존중되는가?
- [ ] 각 문단이 240자 이내인가?

---

#### ubiquitous-language

**검증 시나리오:**
```
"대화에서 사용된 용어를 정리해줘"
```

**예상 결과:**
- UBIQUITOUS_LANGUAGE.md 생성
- 용어 정의표
- 모호성 플래그

**검증 포인트:**
- [ ] 파일이 생성되었는가?
- [ ] 용어가 명확히 정의되었는가?
- [ ] 모순이 플래그되었는가?

---

#### obsidian-vault

**검증 시나리오:**
```
"Obsidian vault에서 관련 노트를 찾아줘"
```

**예상 결과:**
- 노트 검색
- 위키링크 사용
- 새 노트 생성

**검증 포인트:**
- [ ] 올바른 경로를 사용하는가?
- [ ] wikilink 구문을 사용하는가?

---

## 검증 체크리스트

### 전체 스킬 검증

- [ ] 모든 스킬이 성공적으로 설치되었는가?
- [ ] 각 스킬의 description이 트리거를 포함하는가?
- [ ] Claude Code가 스킬을 올바르게 로드하는가?

### 기능별 검증

| 카테고리 | 스킬 | 상태 |
|----------|------|------|
| Planning & Design | write-a-prd | ⬜ |
| Planning & Design | prd-to-plan | ⬜ |
| Planning & Design | prd-to-issues | ⬜ |
| Planning & Design | grill-me | ⬜ |
| Planning & Design | design-an-interface | ⬜ |
| Planning & Design | request-refactor-plan | ⬜ |
| Development | tdd | ⬜ |
| Development | triage-issue | ⬜ |
| Development | improve-codebase-architecture | ⬜ |
| Development | migrate-to-shoehorn | ⬜ |
| Development | scaffold-exercises | ⬜ |
| Tooling & Setup | setup-pre-commit | ⬜ |
| Tooling & Setup | git-guardrails-claude-code | ⬜ |
| Writing & Knowledge | write-a-skill | ⬜ |
| Writing & Knowledge | edit-article | ⬜ |
| Writing & Knowledge | ubiquitous-language | ⬜ |
| Writing & Knowledge | obsidian-vault | ⬜ |

---

## 문제 해결

### 스킬이 로드되지 않을 때

```bash
# 스킬 목록 확인
skills list

# 스킬 재설치
skills remove <skill-name>
skills add mattpocock/skills/<skill-name>
```

### GitHub 인증 문제

```bash
gh auth status
gh auth login
```

### git guardrails 훅이 작동하지 않을 때

```bash
# 훅 스크립트 실행 권한 확인
chmod +x .claude/hooks/block-dangerous-git.sh

# settings.json 확인
cat .claude/settings.json | jq .
```

---

## 참고 자료

- [skills-main README](../skills-main/README.md)
- [Matt Pocock's Skills Repository](https://github.com/mattpocock/skills)
- [Claude Code Documentation](https://github.com/anthropics/claude-code)
