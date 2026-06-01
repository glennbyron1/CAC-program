#!/usr/bin/env python3
"""
scap_summary.py — SCAP XCCDF Results Parser
Author: Glenn Byron
Purpose: Parse DISA SCAP SCC XCCDF results files and produce a plain-language
         CAT I / CAT II / CAT III compliance summary. Designed to replicate the
         kind of finding triage a DoD IA technician performs after an ACAS/SCAP scan.

Usage:
    python scap_summary.py <results.xml> [--output report.txt] [--format text|json]

Frameworks: NIST SP 800-53 Rev. 5 · DISA STIG methodology · DoD RMF
"""

import argparse
import json
import sys
import xml.etree.ElementTree as ET
from datetime import datetime
from pathlib import Path


# XCCDF namespace map — DISA SCAP SCC output uses these namespaces
NAMESPACES = {
    'xccdf': 'http://checklists.nist.gov/xccdf/1.2',
    'xccdf11': 'http://checklists.nist.gov/xccdf/1.1',
    'dc': 'http://purl.org/dc/elements/1.1/',
}

# DISA severity → DoD CAT mapping
# CAT I = Critical/High — immediate threat to mission
# CAT II = Medium      — significant but not immediate
# CAT III = Low/Info   — best practice / defense-in-depth
SEVERITY_TO_CAT = {
    'high':   'CAT I',
    'medium': 'CAT II',
    'low':    'CAT III',
    'info':   'CAT III',
    'unknown': 'CAT III',
}

CAT_DESCRIPTIONS = {
    'CAT I':   'Critical — Immediate remediation required. Exploitable vulnerability that '
               'directly enables privilege escalation, code execution, or data exfiltration.',
    'CAT II':  'High — Remediate within 30 days. Significant vulnerability that degrades '
               'defense-in-depth or enables chained exploitation.',
    'CAT III': 'Medium/Low — Remediate within 180 days. Best-practice deviation or '
               'configuration weakness that reduces security posture.',
}


def detect_namespace(root):
    """Detect whether the XCCDF file uses 1.1 or 1.2 namespace."""
    tag = root.tag
    if 'xccdf/1.2' in tag:
        return 'xccdf'
    if 'xccdf/1.1' in tag:
        return 'xccdf11'
    # Fallback — try both
    return 'xccdf'


def parse_xccdf(filepath: Path) -> dict:
    """Parse an XCCDF results file and return structured finding data."""
    try:
        tree = ET.parse(filepath)
    except ET.ParseError as exc:
        print(f"[ERROR] Cannot parse XML: {exc}", file=sys.stderr)
        sys.exit(1)

    root = tree.getroot()
    ns_key = detect_namespace(root)
    ns = {ns_key: NAMESPACES[ns_key]}
    prefix = ns_key

    # Extract benchmark metadata
    benchmark_id = root.get('id', 'Unknown')
    title_el = root.find(f'{prefix}:title', ns)
    title = title_el.text if title_el is not None else 'Unknown Benchmark'

    # Extract scan target info
    target_el = root.find(f'.//{prefix}:target', ns)
    target = target_el.text if target_el is not None else 'Unknown'

    # Extract scan date
    date_el = root.find(f'.//{prefix}:end-time', ns)
    if date_el is None:
        date_el = root.find(f'.//{prefix}:start-time', ns)
    scan_date = date_el.text if date_el is not None else datetime.utcnow().isoformat()

    findings = {
        'metadata': {
            'benchmark_id': benchmark_id,
            'title': title,
            'target': target,
            'scan_date': scan_date,
            'parsed_at': datetime.utcnow().isoformat() + 'Z',
        },
        'by_cat': {'CAT I': [], 'CAT II': [], 'CAT III': []},
        'by_result': {},
        'totals': {},
    }

    # Parse rule results
    for rule_result in root.findall(f'.//{prefix}:rule-result', ns):
        rule_id = rule_result.get('idref', 'unknown')
        severity = rule_result.get('severity', 'unknown').lower()
        cat = SEVERITY_TO_CAT.get(severity, 'CAT III')

        result_el = rule_result.find(f'{prefix}:result', ns)
        result = result_el.text.strip() if result_el is not None else 'unknown'

        # Only report actual failures — skip pass, notapplicable, notchecked
        if result not in ('fail', 'error'):
            findings['by_result'][result] = findings['by_result'].get(result, 0) + 1
            continue

        # Extract rule title and description from the result element
        title_el = rule_result.find(f'{prefix}:title', ns)
        check_title = title_el.text if title_el is not None else rule_id

        finding = {
            'rule_id': rule_id,
            'title': check_title,
            'severity': severity,
            'cat': cat,
            'result': result,
        }

        findings['by_cat'][cat].append(finding)
        findings['by_result'][result] = findings['by_result'].get(result, 0) + 1

    # Compute totals
    findings['totals'] = {
        'CAT I': len(findings['by_cat']['CAT I']),
        'CAT II': len(findings['by_cat']['CAT II']),
        'CAT III': len(findings['by_cat']['CAT III']),
        'total_findings': sum(len(v) for v in findings['by_cat'].values()),
    }
    findings['totals'].update(findings['by_result'])

    return findings


def format_text(findings: dict) -> str:
    """Render findings as a plain-text report matching DoD IA reporting style."""
    meta = findings['metadata']
    totals = findings['totals']
    lines = []

    lines.append('=' * 72)
    lines.append('  SCAP COMPLIANCE SUMMARY REPORT')
    lines.append('  Author: Glenn Byron | Tool: scap-summary | Framework: DISA STIG')
    lines.append('=' * 72)
    lines.append(f"  Benchmark : {meta['title']}")
    lines.append(f"  Target    : {meta['target']}")
    lines.append(f"  Scan Date : {meta['scan_date']}")
    lines.append(f"  Parsed At : {meta['parsed_at']}")
    lines.append('=' * 72)
    lines.append('')
    lines.append('FINDING SUMMARY')
    lines.append('-' * 40)
    lines.append(f"  CAT I  (Critical) : {totals.get('CAT I', 0):>4}  finding(s)")
    lines.append(f"  CAT II (High)     : {totals.get('CAT II', 0):>4}  finding(s)")
    lines.append(f"  CAT III (Med/Low) : {totals.get('CAT III', 0):>4}  finding(s)")
    lines.append(f"  {'─' * 30}")
    lines.append(f"  Total Findings    : {totals.get('total_findings', 0):>4}")
    lines.append('')

    # Pass/fail/other counts
    pass_count = findings['by_result'].get('pass', 0)
    na_count = findings['by_result'].get('notapplicable', 0)
    nc_count = findings['by_result'].get('notchecked', 0)
    lines.append(f"  Passed      : {pass_count}")
    lines.append(f"  N/A         : {na_count}")
    lines.append(f"  Not Checked : {nc_count}")
    lines.append('')

    # CAT I findings — always list in full
    for cat in ('CAT I', 'CAT II', 'CAT III'):
        cat_findings = findings['by_cat'][cat]
        if not cat_findings:
            continue
        lines.append('=' * 72)
        lines.append(f'  {cat} FINDINGS ({len(cat_findings)})')
        lines.append(f'  {CAT_DESCRIPTIONS[cat]}')
        lines.append('-' * 72)
        for i, f in enumerate(cat_findings, 1):
            lines.append(f"  [{i:02d}] {f['rule_id']}")
            lines.append(f"       {f['title']}")
            lines.append(f"       Severity: {f['severity'].upper()}  |  Result: {f['result'].upper()}")
            lines.append('')

    lines.append('=' * 72)
    lines.append('  END OF REPORT')
    lines.append(f"  Generated: {datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')}")
    lines.append('=' * 72)

    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(
        description='Parse DISA SCAP SCC XCCDF results and produce a CAT I/II/III summary.'
    )
    parser.add_argument('results_file', help='Path to XCCDF results XML file')
    parser.add_argument('--output', '-o', help='Write report to file (default: stdout)')
    parser.add_argument(
        '--format', '-f', choices=['text', 'json'], default='text',
        help='Output format: text (default) or json'
    )
    args = parser.parse_args()

    filepath = Path(args.results_file)
    if not filepath.exists():
        print(f"[ERROR] File not found: {filepath}", file=sys.stderr)
        sys.exit(1)

    findings = parse_xccdf(filepath)

    if args.format == 'json':
        output = json.dumps(findings, indent=2)
    else:
        output = format_text(findings)

    if args.output:
        Path(args.output).write_text(output, encoding='utf-8')
        print(f"Report written to: {args.output}")
    else:
        print(output)


if __name__ == '__main__':
    main()
