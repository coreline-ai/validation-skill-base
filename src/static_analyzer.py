#!/usr/bin/env python3
"""
Skill Static Analyzer
정적 분석을 통해 스킬 파일의 보안 취약점을 탐지

Usage:
    python static_analyzer.py --input /path/to/skill --output report.json
"""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import List, Dict, Any, Tuple, Optional
from dataclasses import dataclass, asdict
from datetime import datetime

@dataclass
class Issue:
    """발견된 이슈"""
    file: str
    line: int
    severity: str  # CRITICAL, HIGH, MEDIUM, LOW
    category: str  # security, privacy, structure, owasp, malicious
    pattern_id: str
    description: str
    match: str

@dataclass
class IssueMatch:
    """중복 제거 전의 내부 매치 정보"""
    issue: Issue
    span_start: int
    span_end: int
    regex_length: int

@dataclass
class SkippedFile:
    """분석에서 건너뛴 파일 정보"""
    file: str
    reason: str

@dataclass
class AnalysisResult:
    """분석 결과"""
    status: str  # PASS, FAIL
    skill_path: str
    files_scanned: int
    issues: List[Dict[str, Any]]
    skipped_files: List[Dict[str, str]]
    summary: Dict[str, int]
    analyzed_at: str

class SkillAnalyzer:
    """스킬 정적 분석기"""
    SEVERITY_RANK = {
        'CRITICAL': 4,
        'HIGH': 3,
        'MEDIUM': 2,
        'LOW': 1,
    }

    DEFAULT_FAILURE_THRESHOLDS = {
        'critical': 0,
        'high': 2,
    }

    def __init__(
        self,
        patterns: List[Dict],
        validation_mode: str = 'thorough',
        failure_thresholds: Optional[Dict[str, int]] = None,
    ):
        self.patterns = patterns
        self.validation_mode = validation_mode
        self.failure_thresholds = self.DEFAULT_FAILURE_THRESHOLDS.copy()
        if failure_thresholds:
            for key, value in failure_thresholds.items():
                self.failure_thresholds[str(key).lower()] = int(value)

        # 정규식 컴파일 (성능 최적화)
        for pattern in self.patterns:
            if pattern.get('structural_only'):
                pattern['compiled'] = None
                continue

            try:
                pattern['compiled'] = re.compile(
                    pattern['regex'],
                    re.MULTILINE | re.DOTALL
                )
            except re.error as e:
                print(f"Warning: Invalid regex for pattern {pattern['id']}: {e}", file=sys.stderr)
                pattern['compiled'] = None

    @staticmethod
    def has_yaml_frontmatter(file_path: Path) -> bool:
        """파일 시작부에 YAML frontmatter가 있는지 확인"""
        content = file_path.read_text(encoding='utf-8')
        if not content.startswith('---\n'):
            return False

        return '\n---\n' in content[4:] or content.rstrip().endswith('\n---')

    @staticmethod
    def is_script_without_extension(file_path: Path) -> Tuple[bool, Optional[str]]:
        """확장자가 없는 파일의 shebang 여부 확인"""
        if file_path.suffix:
            return False, None

        try:
            with file_path.open('rb') as handle:
                first_line = handle.readline(256)
        except OSError as exc:
            return False, f"Could not read file header: {exc}"

        if first_line.startswith(b'#!'):
            return True, None

        return False, None

    @staticmethod
    def is_validator_system_dir(skill_dir: Path) -> bool:
        """이 저장소 자체인지 판별"""
        repo_runtime = (
            (skill_dir / 'install.sh').exists()
            and all((skill_dir / 'src' / name).exists() for name in ('validator.sh', 'static_analyzer.py', 'skills'))
        )
        installed_runtime = all((skill_dir / name).exists() for name in ('validator.sh', 'static_analyzer.py'))

        return repo_runtime or installed_runtime

    def should_analyze_file(
        self,
        file_path: Path,
        skill_dir: Path,
        is_validator_system: bool,
    ) -> Tuple[bool, Optional[str]]:
        """파일 분석 대상 여부 판별"""
        extensions = {'.py', '.sh', '.js', '.jsx', '.ts', '.tsx', '.bash', '.zsh', '.mjs', '.cjs'}
        doc_extensions = {'.md', '.txt', '.json', '.yaml', '.yml'}

        if file_path.stat().st_size > 10_000_000:
            return False, "Skipped file larger than 10MB"

        if is_validator_system:
            relative_path = file_path.relative_to(skill_dir)
            if relative_path.parts and relative_path.parts[0] == 'docs':
                return False, None
            if file_path.name in {'README.md', 'LICENSE'}:
                return False, None

        if file_path.name in {
            'patterns.json',
            'patterns.essential.json',
            'patterns.standard.json',
            'patterns.thorough.json',
        }:
            return False, None

        if file_path.name == 'SKILL.md' and is_validator_system:
            return False, None

        is_shebang_script, shebang_error = self.is_script_without_extension(file_path)
        if shebang_error:
            return False, shebang_error

        if is_validator_system:
            if (
                file_path.suffix in extensions
                or file_path.name in {'SKILL.md', 'REFERENCE.md'}
                or is_shebang_script
            ):
                return True, None
            return False, None

        if (
            file_path.suffix in extensions
            or file_path.suffix in doc_extensions
            or file_path.name in {'SKILL.md', 'REFERENCE.md'}
            or is_shebang_script
        ):
            return True, None

        return False, None

    def should_replace_issue(self, candidate: IssueMatch, existing: IssueMatch) -> bool:
        """겹치는 매치가 있을 때 더 의미 있는 이슈를 선택"""
        candidate_rank = self.SEVERITY_RANK.get(candidate.issue.severity, 0)
        existing_rank = self.SEVERITY_RANK.get(existing.issue.severity, 0)

        if candidate_rank != existing_rank:
            return candidate_rank > existing_rank

        candidate_span = candidate.span_end - candidate.span_start
        existing_span = existing.span_end - existing.span_start
        if candidate_span != existing_span:
            return candidate_span > existing_span

        if candidate.regex_length != existing.regex_length:
            return candidate.regex_length > existing.regex_length

        return candidate.issue.pattern_id < existing.issue.pattern_id

    def deduplicate_matches(self, matches: List[IssueMatch]) -> List[Issue]:
        """같은 줄에서 겹치는 정규식 매치를 하나의 이슈로 정리"""
        deduped: List[IssueMatch] = []

        sorted_matches = sorted(
            matches,
            key=lambda item: (
                item.issue.file,
                item.issue.line,
                item.span_start,
                item.span_end,
            ),
        )

        for candidate in sorted_matches:
            merged = False

            for index, existing in enumerate(deduped):
                same_location = (
                    candidate.issue.file == existing.issue.file
                    and candidate.issue.line == existing.issue.line
                )
                overlaps = (
                    candidate.span_start < existing.span_end
                    and existing.span_start < candidate.span_end
                )

                if not same_location or not overlaps:
                    continue

                if self.should_replace_issue(candidate, existing):
                    deduped[index] = candidate

                merged = True
                break

            if not merged:
                deduped.append(candidate)

        return [item.issue for item in deduped]

    @staticmethod
    def _build_code_block_ranges(content: str) -> List[Tuple[int, int]]:
        """Markdown 코드 블록(``` 또는 ~~~)의 내부 범위 목록을 반환"""
        ranges: List[Tuple[int, int]] = []
        fence_char: Optional[str] = None
        fence_len = 0
        body_start = 0
        pos = 0

        for line in content.split('\n'):
            line_start = pos
            pos += len(line) + 1  # +1 for \n

            stripped = line.strip()
            if fence_char is None:
                if (stripped.startswith('```') or stripped.startswith('~~~')):
                    ch = stripped[0]
                    run = len(stripped) - len(stripped.lstrip(ch))
                    if run >= 3:
                        fence_char = ch
                        fence_len = run
                        body_start = min(pos, len(content))
            else:
                if stripped.startswith(fence_char * fence_len) and stripped.strip(fence_char) == '':
                    ranges.append((body_start, line_start))
                    fence_char = None

        return ranges

    @staticmethod
    def _inside_code_block(pos: int, ranges: List[Tuple[int, int]]) -> bool:
        for start, end in ranges:
            if start <= pos < end:
                return True
        return False

    def analyze_file(self, file_path: Path, skill_dir: Path) -> List[Issue]:
        """단일 파일 분석"""
        matches: List[IssueMatch] = []
        content = file_path.read_text(encoding='utf-8')

        # Markdown 파일이면 코드 블록 범위를 미리 계산
        code_block_ranges: List[Tuple[int, int]] = []
        if file_path.suffix == '.md':
            code_block_ranges = self._build_code_block_ranges(content)

        for pattern in self.patterns:
            if pattern['compiled'] is None or pattern.get('structural_only'):
                continue

            for match in pattern['compiled'].finditer(content):
                # Markdown 코드 블록 안이면 건너뜀
                if code_block_ranges and self._inside_code_block(match.start(), code_block_ranges):
                    continue

                line_num = content[:match.start()].count('\n') + 1

                start = max(0, match.start() - 30)
                end = min(len(content), match.end() + 30)
                context = content[start:end].replace('\n', '\\n')

                matches.append(IssueMatch(
                    issue=Issue(
                        file=str(file_path.relative_to(skill_dir)),
                        line=line_num,
                        severity=pattern['severity'],
                        category=pattern['category'],
                        pattern_id=pattern['id'],
                        description=pattern['description'],
                        match=context.strip()
                    ),
                    span_start=match.start(),
                    span_end=match.end(),
                    regex_length=len(pattern['regex'])
                ))

        return self.deduplicate_matches(matches)

    def determine_status(self, summary: Dict[str, int]) -> str:
        """패턴 메타데이터에 정의된 심각도 임계값으로 PASS/FAIL 결정"""
        for severity, threshold in self.failure_thresholds.items():
            if severity in summary and summary[severity] > threshold:
                return 'FAIL'

        return 'PASS'

    def analyze(self, skill_dir: Path) -> AnalysisResult:
        """스킬 디렉토리 분석"""
        issues = []
        skipped_files = []
        files_scanned = 0
        skip_scan_paths = set()

        # 검증 시스템 자체인지 확인 (패턴 파일 존재 여부로 판단)
        has_pattern_files = any(
            (skill_dir / name).exists() or (skill_dir / 'src' / name).exists()
            for name in ['patterns.json', 'patterns.essential.json', 'patterns.standard.json']
        )
        is_validator_system = has_pattern_files and self.is_validator_system_dir(skill_dir)

        # SKILL.md 필수 확인
        skill_md = skill_dir / "SKILL.md"
        if not skill_md.exists():
            issues.append(Issue(
                file="<root>",
                line=0,
                severity="CRITICAL",
                category="structure",
                pattern_id="structure_skill_md_missing",
                description="SKILL.md not found",
                match="Required file SKILL.md is missing"
            ))
        elif not is_validator_system:
            try:
                if not self.has_yaml_frontmatter(skill_md):
                    issues.append(Issue(
                        file="SKILL.md",
                        line=1,
                        severity="MEDIUM",
                        category="structure",
                        pattern_id="structure_yaml_frontmatter",
                        description="YAML frontmatter should be present in SKILL.md",
                        match="SKILL.md is missing YAML frontmatter at the top of the file"
                    ))
            except (OSError, UnicodeDecodeError) as exc:
                issues.append(Issue(
                    file="SKILL.md",
                    line=1,
                    severity="CRITICAL",
                    category="structure",
                    pattern_id="structure_skill_md_unreadable",
                    description="SKILL.md could not be read for structural validation",
                    match=f"Could not read SKILL.md: {exc}"
                ))
                skipped_files.append(SkippedFile(
                    file="SKILL.md",
                    reason=f"Could not read SKILL.md for frontmatter check: {exc}"
                ))
                skip_scan_paths.add(skill_md.resolve())

        for file_path in skill_dir.rglob('*'):
            if not file_path.is_file():
                continue

            if file_path.resolve() in skip_scan_paths:
                continue

            try:
                should_scan, skip_reason = self.should_analyze_file(
                    file_path,
                    skill_dir,
                    is_validator_system,
                )
            except OSError as exc:
                skipped_files.append(SkippedFile(
                    file=str(file_path.relative_to(skill_dir)),
                    reason=f"Could not inspect file metadata: {exc}"
                ))
                continue

            if skip_reason:
                skipped_files.append(SkippedFile(
                    file=str(file_path.relative_to(skill_dir)),
                    reason=skip_reason
                ))
            if not should_scan:
                continue

            try:
                issues.extend(self.analyze_file(file_path, skill_dir))
                files_scanned += 1
            except (OSError, UnicodeDecodeError) as exc:
                skipped_files.append(SkippedFile(
                    file=str(file_path.relative_to(skill_dir)),
                    reason=f"Could not analyze file: {exc}"
                ))
            except Exception as exc:
                skipped_files.append(SkippedFile(
                    file=str(file_path.relative_to(skill_dir)),
                    reason=f"Unexpected analyzer error: {exc}"
                ))

        # 심각도별 집계
        summary = {
            'critical': sum(1 for i in issues if i.severity == 'CRITICAL'),
            'high': sum(1 for i in issues if i.severity == 'HIGH'),
            'medium': sum(1 for i in issues if i.severity == 'MEDIUM'),
            'low': sum(1 for i in issues if i.severity == 'LOW'),
        }

        status = self.determine_status(summary)

        return AnalysisResult(
            status=status,
            skill_path=str(skill_dir),
            files_scanned=files_scanned,
            issues=[asdict(issue) for issue in issues],
            skipped_files=[asdict(item) for item in skipped_files],
            summary=summary,
            analyzed_at=datetime.now().isoformat()
        )

def main():
    parser = argparse.ArgumentParser(
        description='Skill Static Analyzer',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  %(prog)s --input ./skills/write-a-prd --output report.json
  %(prog)s --input ./skills/write-a-prd --output report.json --verbose
        '''
    )
    parser.add_argument('--input', required=True, help='Skill directory to analyze')
    parser.add_argument('--output', required=True, help='Output JSON report path')
    parser.add_argument('--patterns', default='patterns.json', help='Patterns JSON file path')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose output')

    args = parser.parse_args()

    # 입력 경로 확인
    input_path = Path(args.input)
    if not input_path.exists():
        print(f"Error: Input path not found: {args.input}", file=sys.stderr)
        sys.exit(1)

    # 패턴 파일 로드
    patterns_path = Path(args.patterns)
    if not patterns_path.is_absolute():
        # 상대 경로인 경우 스크립트 위치 기준
        patterns_path = Path(__file__).parent / args.patterns

    try:
        with open(patterns_path, 'r') as f:
            pattern_data = json.load(f)
            patterns = pattern_data.get('patterns', [])
            validation_mode = pattern_data.get('mode', 'thorough')
            failure_thresholds = pattern_data.get('failure_thresholds', {})
    except FileNotFoundError:
        print(f"Error: Patterns file not found: {patterns_path}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in patterns file: {e}", file=sys.stderr)
        sys.exit(1)

    # 분석 실행
    analyzer = SkillAnalyzer(
        patterns,
        validation_mode=validation_mode,
        failure_thresholds=failure_thresholds,
    )
    result = analyzer.analyze(input_path)

    # 출력 디렉토리 확인
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # 결과 저장
    with open(output_path, 'w') as f:
        json.dump(asdict(result), f, indent=2)

    # 출력
    if args.verbose or result.status == 'FAIL':
        print(json.dumps(asdict(result), indent=2, ensure_ascii=False))
    else:
        print(f"Status: {result.status}")
        print(f"Files scanned: {result.files_scanned}")
        print(f"Skipped files: {len(result.skipped_files)}")
        print(f"Issues found: {len(result.issues)}")

    # 종료 코드
    sys.exit(0 if result.status == 'PASS' else 1)

if __name__ == '__main__':
    main()
