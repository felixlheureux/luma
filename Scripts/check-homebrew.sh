#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - "${1:-dist/Luma.app/Contents/MacOS/Luma}" <<'PY'
import json, os, pathlib, subprocess, sys, tempfile
root = pathlib.Path(os.environ.get('LUMA_HOMEBREW_QA_OUTPUT_DIR') or tempfile.mkdtemp(prefix='luma-homebrew-ui-'))
root.mkdir(parents=True, exist_ok=True)
required = ['fixtureProviderSucceeded', 'separateUsageStates', 'staleSuggestions', 'unrelatedSelectionPreserved', 'verifiedAppsBadge', 'nativeTrashDisabled', 'blockedActionCannotMove', 'failedRefreshHonest']
for appearance in ['light', 'dark', 'system']:
    output = root / (appearance + '.json')
    subprocess.run([sys.argv[1], '--check-homebrew', str(output), '-luma.appearance', appearance, '-luma.menuBar', 'YES'], check=True, timeout=45)
    report = json.loads(output.read_text())
    assert 'error' not in report, report
    assert all(report.get(key) is True for key in required), report
    assert report['realBrewExecuted'] is False and report['realTrashInvoked'] is False, report
    print(f'Passed {appearance}: synthetic Brew inventory, distinct groups, Apps badge/block, retained selection and failure.')
print(f'Own-process renders and reports: {root}')
PY
