# Skills Validation Guide

> [mattpocock/skills](https://github.com/mattpocock/skills) 스킬을 검증할 때 참고하는 시나리오별 체크리스트입니다.
> 설치/검증 명령은 `skills` 래퍼 기준입니다. 상세 사용법은 [README.md](../README.md)를 참고하세요.

---

## Prerequisites

```bash
# 1. Skill Validator 설치
git clone https://github.com/hwanchoi/skill-validator ~/.claude/skill-validator
cd ~/.claude/skill-validator && chmod +x install.sh && ./install.sh

# 2. GitHub CLI (이슈 생성이 필요한 스킬용)
brew install gh && gh auth login
```

## Skill Installation

```bash
# 개별 설치 (검증 자동 실행)
skills add mattpocock/skills/<skill-name>

# 설치 확인
skills list
```

---

## Validation Scenarios by Category

### 1. Planning & Design

<details>
<summary><b>write-a-prd</b> — PRD 작성</summary>

**시나리오**: `"사용자 인증 기능을 위한 PRD를 작성해줘"`

**체크리스트**:
- [ ] PRD 템플릿이 올바르게 적용되었는가?
- [ ] User Stories가 충분히 상세한가?
- [ ] Implementation Decisions에 파일 경로 등 구현 세부사항이 없는가?
</details>

<details>
<summary><b>prd-to-plan</b> — PRD → 구현 계획</summary>

**시나리오**: `"이 PRD를 구현 계획으로 변환해줘"`

**체크리스트**:
- [ ] `./plans/` 디렉토리가 생성되었는가?
- [ ] 각 phase가 vertical slice인가?
- [ ] Durable decisions가 포함되었는가?
</details>

<details>
<summary><b>prd-to-issues</b> — PRD → GitHub Issues</summary>

**시나리오**: `"PRD #123을 GitHub 이슈로 변환해줘"`

**체크리스트**:
- [ ] 이슈가 의존성 순서대로 생성되었는가?
- [ ] Vertical slice 형태인가?
- [ ] Parent PRD 참조가 있는가?
</details>

<details>
<summary><b>grill-me</b> — 설계 검증 질문</summary>

**시나리오**: `"이 설계안에 대해 grill-me 해줘"`

**체크리스트**:
- [ ] 모든 결정 지점이 탐색되었는가?
- [ ] 코드베이스 탐색으로 답변 가능한 경우 탐색했는가?
</details>

<details>
<summary><b>design-an-interface</b> — 인터페이스 설계</summary>

**시나리오**: `"사용자 관리 모듈의 인터페이스를 설계해줘"`

**체크리스트**:
- [ ] 3개 이상의 다른 설계가 제시되었는가?
- [ ] 각 설계가 근본적으로 다른가?
- [ ] Trade-off 분석이 있는가?
</details>

<details>
<summary><b>request-refactor-plan</b> — 리팩토링 계획</summary>

**시나리오**: `"인증 로직을 리팩토링하는 계획을 세워줘"`

**체크리스트**:
- [ ] 각 commit이 독립적으로 동작하는가?
- [ ] Martin Fowler의 리팩토링 원칙이 반영되었는가?
</details>

### 2. Development

<details>
<summary><b>tdd</b> — TDD 개발</summary>

**시나리오**: `"TDD로 사용자 로그인 기능을 구현해줘"`

**체크리스트**:
- [ ] 수직 슬라이스로 진행되었는가? (수평 아님)
- [ ] 테스트가 public interface만 검증하는가?
- [ ] 내부 리팩토링 후에도 테스트가 통과하는가?
</details>

<details>
<summary><b>triage-issue</b> — 이슈 트리아지</summary>

**시나리오**: `"로그인이 안 되는 버그가 있어. 조사해줘"`

**체크리스트**:
- [ ] Root cause가 명확히 식별되었는가?
- [ ] 수정 계획이 내부 구조에 의존하지 않는가?
- [ ] GitHub 이슈가 생성되었는가?
</details>

<details>
<summary><b>improve-codebase-architecture</b> — 아키텍처 개선</summary>

**시나리오**: `"이 코드베이스의 아키텍처 개선 기회를 찾아줘"`

**체크리스트**:
- [ ] 마찰 지점이 식별되었는가?
- [ ] Dependency category가 분류되었는가?
- [ ] GitHub 이슈 RFC가 생성되었는가?
</details>

<details>
<summary><b>migrate-to-shoehorn</b> — as 단언 마이그레이션</summary>

**시나리오**: `"테스트 파일의 as 단언을 shoehorn으로 변환해줘"`

**체크리스트**:
- [ ] `@total-typescript/shoehorn` 패키지가 설치되었는가?
- [ ] import 문이 추가되었는가?
- [ ] 타입 체크가 통과하는가?
</details>

<details>
<summary><b>scaffold-exercises</b> — 연습 스캐폴딩</summary>

**시나리오**: `"TDD 연습 섹션을 스캐폴딩해줘"`

**체크리스트**:
- [ ] 디렉토리 명명 규칙을 따르는가?
- [ ] readme가 비어있지 않은가?
- [ ] `pnpm ai-hero-cli internal lint` 통과하는가?
</details>

### 3. Tooling & Setup

<details>
<summary><b>setup-pre-commit</b> — Pre-commit 훅 설정</summary>

**시나리오**: `"pre-commit 훅을 설정해줘"`

**체크리스트**:
- [ ] `.husky/pre-commit`이 존재하는가?
- [ ] `.lintstagedrc`가 존재하는가?
- [ ] `package.json`에 prepare 스크립트가 있는가?
- [ ] Commit이 훅을 통해 실행되는가?
</details>

<details>
<summary><b>git-guardrails-claude-code</b> — Git 안전장치</summary>

**시나리오**: `"Claude Code에서 위험한 git 명령을 차단하도록 설정해줘"`

**체크리스트**:
- [ ] `.claude/hooks/block-dangerous-git.sh`가 존재하는가?
- [ ] `settings.json`에 PreToolUse 훅이 있는가?
- [ ] `git push`가 차단되는가?

**Quick test**:
```bash
echo '{"tool_input":{"command":"git push origin main"}}' | .claude/hooks/block-dangerous-git.sh
# Expected: exit code 2
```
</details>

### 4. Writing & Knowledge

<details>
<summary><b>write-a-skill</b> — 스킬 작성</summary>

**시나리오**: `"새로운 스킬을 작성하고 싶어. 도와줘"`

**체크리스트**:
- [ ] description에 "Use when" 트리거가 포함되었는가?
- [ ] SKILL.md가 100줄 이내인가?
- [ ] 적절한 파일 구조인가?
</details>

<details>
<summary><b>edit-article</b> — 문서 편집</summary>

**시나리오**: `"이 문서를 편집해줘"`

**체크리스트**:
- [ ] 정보 의존성이 존중되는가?
- [ ] 각 문단이 240자 이내인가?
</details>

<details>
<summary><b>ubiquitous-language</b> — 용어 정리</summary>

**시나리오**: `"대화에서 사용된 용어를 정리해줘"`

**체크리스트**:
- [ ] `UBIQUITOUS_LANGUAGE.md`가 생성되었는가?
- [ ] 용어가 명확히 정의되었는가?
- [ ] 모순이 플래그되었는가?
</details>

<details>
<summary><b>obsidian-vault</b> — Obsidian 노트 검색</summary>

**시나리오**: `"Obsidian vault에서 관련 노트를 찾아줘"`

**체크리스트**:
- [ ] 올바른 경로를 사용하는가?
- [ ] `[[wikilink]]` 구문을 사용하는가?
</details>

---

## Summary Checklist

| Category | Skill | Status |
|----------|-------|:------:|
| Planning & Design | write-a-prd | |
| Planning & Design | prd-to-plan | |
| Planning & Design | prd-to-issues | |
| Planning & Design | grill-me | |
| Planning & Design | design-an-interface | |
| Planning & Design | request-refactor-plan | |
| Development | tdd | |
| Development | triage-issue | |
| Development | improve-codebase-architecture | |
| Development | migrate-to-shoehorn | |
| Development | scaffold-exercises | |
| Tooling & Setup | setup-pre-commit | |
| Tooling & Setup | git-guardrails-claude-code | |
| Writing & Knowledge | write-a-skill | |
| Writing & Knowledge | edit-article | |
| Writing & Knowledge | ubiquitous-language | |
| Writing & Knowledge | obsidian-vault | |

---

## Troubleshooting

<details>
<summary>스킬이 로드되지 않을 때</summary>

```bash
skills list
skills remove <skill-name>
skills add mattpocock/skills/<skill-name>
```
</details>

<details>
<summary>GitHub 인증 문제</summary>

```bash
gh auth status
gh auth login
```
</details>

## References

- [Matt Pocock's Skills Repository](https://github.com/mattpocock/skills)
- [Claude Code Documentation](https://github.com/anthropics/claude-code)
