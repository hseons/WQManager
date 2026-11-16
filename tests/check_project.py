#!/usr/bin/env python3
"""Portable repository checks, shared by local runs and CI."""
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'WQManager' / 'WQManager'

def run(*args):
    subprocess.run(args, cwd=ROOT, check=True)

run('git', 'diff', '--check')
run('bash', '-n', 'tests/run_tests.sh')
run('bash', '-n', 'tests/UI/run_ui_tests.sh')
run('ruby', '-c', 'tests/prepare_ci_project.rb')
for path in (ROOT / 'tests').rglob('*.py'):
    compile(path.read_text(), str(path), 'exec')
strings = {}
for language in ('en', 'zh-Hans'):
    path = SOURCE / f'{language}.lproj' / 'Localizable.strings'
    run('plutil', '-lint', str(path))
    keys = re.findall(r'^\s*"((?:[^"\\]|\\.)*)"\s*=', path.read_text(), re.M)
    assert len(keys) == len(set(keys)), f'duplicate keys: {language}'
    strings[language] = set(keys)
assert strings['en'] == strings['zh-Hans'], f'localization mismatch: {strings["en"] ^ strings["zh-Hans"]}'
for path in list(SOURCE.glob('*.plist')) + list(SOURCE.glob('*.entitlements')) + list((ROOT / 'WQManager/WQManagerShare').glob('*.plist')) + list((ROOT / 'WQManager/WQManagerShare').glob('*.entitlements')):
    run('plutil', '-lint', str(path))
# WQML supports Objective-C adjacent string literals; keys themselves are literal.
used = set()
for path in SOURCE.glob('*.[mh]'):
    used.update(re.findall(r'WQML\(\s*@"([A-Z0-9_]+)"', path.read_text()))
assert used <= strings['en'], f'missing localization keys: {sorted(used - strings["en"])}'
for language in ('en', 'zh-Hans'):
    data = subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(SOURCE / f'{language}.lproj/Localizable.strings')])
    strings[language] = json.loads(data)
for key in used:
    pattern = r'%(?:\d+\$)?(?:[-+0 #]*\d*(?:\.\d+)?)?(?:hh|ll|h|l|z|t|j)?[@diuoxXfFeEgGcCsSpaA]'
    assert re.findall(pattern, strings['en'][key]) == re.findall(pattern, strings['zh-Hans'][key]), f'format mismatch: {key}'
print('Project configuration and localization checks passed')
