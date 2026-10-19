#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - "${1:-dist/Luma.app}" <<'PY'
import json,pathlib,subprocess,sys,tempfile
folder=pathlib.Path(tempfile.mkdtemp(prefix='luma-window-sizing-'))
bundle=pathlib.Path(sys.argv[1]).resolve()
required=['nativeResizableStyle','qaDoesNotAutosave','restoresWideDefault','monitoringContinues','reopenKeepsWideSize','savedUserFrameUnchanged']
required += [page+suffix for page in ['Overview','System','Maintenance'] for suffix in ['KeepsRequestedSizeAcrossUpdates','NoContentMaximumLock','AutosavingStaysDisabled']]
for appearance in ['light','dark','system']:
    output=folder/(appearance+'.json')
    subprocess.run(['/usr/bin/open','-W','-n',str(bundle),'--args','--check-window-sizing',str(output),'-luma.appearance',appearance,'-luma.menuBar','YES'],check=True,timeout=50)
    data=json.loads(output.read_text())
    assert 'error' not in data,data
    assert all(data.get(key) is True for key in required),data
    assert data['mutationInvoked'] is False and data['personalFoldersScanned'] is False,data
    print(f'Passed {appearance}: flexible native limits, sizes retained during monitoring, wide restore/reopen, user frame unchanged.')
print('Reports:',folder)
print('Physical pointer edge dragging remains a manual check; programmatic size checks do not establish cursor behavior.')
PY
