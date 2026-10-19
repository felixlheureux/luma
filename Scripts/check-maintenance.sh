#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - "${1:-dist/Luma.app/Contents/MacOS/Luma}" <<'PY'
import json, os, pathlib, subprocess, sys, tempfile
root = pathlib.Path(os.environ.get('LUMA_MAINTENANCE_QA_OUTPUT_DIR') or tempfile.mkdtemp(prefix='luma-maintenance-'))
root.mkdir(parents=True, exist_ok=True)
required = ['emptyInitialSelection', 'independentTrashObservation', 'oneTrashApproval', 'cancelPreservesTrash', 'approvedFixturePermanentlyRemoved', 'permanentOutcomePersisted', 'ignoredLastResultHasZeroActionableTotal', 'oneCacheApprovalWithoutReviewSheet', 'cancelPreservesCache', 'cacheUsesJournal', 'postMutationTotalsAgree', 'cacheRestoreVerified', 'monitoringContinues', 'narrowWindow']
for appearance in ['light', 'dark', 'system']:
    output = root / (appearance + '.json')
    output.unlink(missing_ok=True)
    args = [sys.argv[1], '--check-maintenance', str(output), '--maintenance-workspace', str(pathlib.Path.cwd()), '-luma.appearance', appearance, '-luma.menuBar', 'YES']
    bundle = pathlib.Path(sys.argv[1]).resolve().parents[2]
    command = ['/usr/bin/open', '-W', '-n', str(bundle), '--args', *args[1:]] if bundle.suffix == '.app' else args
    subprocess.run(command, check=True, timeout=90)
    report = json.loads(output.read_text())
    assert 'error' not in report, report
    assert all(report.get(key) is True for key in required), report
    assert all(report.get(key) is False for key in ['personalTrashEmptied', 'personalAppsQuit', 'personalFoldersScanned']), report
    print(f'Passed {appearance}: one approval, cancellation, fixture permanent removal, journal cache/Restore, ignored totals, monitoring and narrow view.')
print(f'Own-process renders and reports: {root}')
PY
