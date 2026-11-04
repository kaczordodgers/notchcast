#!/usr/bin/env python3
"""Resolve every catalog reference to its declaration and reject missing owners."""
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
sources = list((root / 'Tinycast/Features').rglob('*.swift'))
contents = {p: p.read_text() for p in sources}
catalog = (root / 'Tinycast/Features/Notchcast/Launcher/NotchcastCommandCatalog+All.swift').read_text()
entries = re.findall(r'^        ([\w.]+(?:\[\d+\])?),$', catalog, re.M)
rows = []
def mapped_owner(path, property_name, action):
    body = path.read_text().split('var ' + property_name + ': NotchcastFeature {', 1)[1].split('\n        }', 1)[0]
    for cases, owner in re.findall(r'case ([^:]+): \.(\w+)', body):
        if '.' + action in [value.strip() for value in cases.split(',')]:
            return owner
    return re.search(r'default: \.(\w+)', body)[1]

for entry in entries:
    kind, member = entry.split('.', 1)
    if kind == 'IslandPage':
        path = root / 'Tinycast/Features/Notchcast/Pages/IslandPage+Command.swift'
        text = path.read_text()
    else:
        candidates = [p for p in sources if re.search(r'\b(?:enum|extension|class|struct) ' + kind + r'\b', contents[p])]
        matches = [(p, contents[p]) for p in candidates if re.search(r'\b(?:let|var) ' + member.split('[')[0] + r'\b', contents[p])]
        assert len(matches) == 1, (entry, matches)
        path, text = matches[0]
    if kind in ('IslandPage', 'SystemLevelsCommands', 'MicrophoneMuteCommands', 'NotchcastToolsLauncherCommands'):
        definition = text[text.index('NotchcastCommand('):]
    elif kind == 'MusicCommands' and member.startswith('speaker'):
        definition = text[text.index('NotchcastCommand(slug: slug'):]
    else:
        start = re.search(r'\b(?:let|var) ' + member + r'\b', text).start()
        definition = text[start:]
    symbol = re.search(r'sfSymbol: [^,]+,', definition)
    assert symbol, entry
    match = re.match(r' feature: ([\w.]+)', definition[symbol.end():])
    assert match, f'{entry}: missing feature in {path}'
    owner = match[1]
    if owner == 'action.feature':
        owner = mapped_owner(root / 'Tinycast/Features/Notchcast/Tools/NotchcastToolsCommands.swift', 'feature', member)
    elif owner.endswith('.requiredFeature'):
        action = owner.split('.')[-2]
        owner = mapped_owner(root / 'Tinycast/Features/Notchcast/Downloads/NotchcastDownloadCommands+Action.swift', 'requiredFeature', action)
    else:
        assert owner.startswith('.'), (entry, owner)
        owner = owner[1:]
    rows.append(dict(id=entry, owner=owner))
assert entries and len(rows) == len(entries)
print(json.dumps(rows))
