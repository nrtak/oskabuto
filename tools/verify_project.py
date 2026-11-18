import importlib.util
import plistlib
from pathlib import Path
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('generator', root / 'tools/generate_project.py')
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)
objects = generator.objects
reference_keys = {'fileRef', 'target', 'targetProxy', 'containerPortal', 'remoteGlobalIDString', 'productReference', 'buildConfigurationList', 'mainGroup', 'productRefGroup'}
reference_arrays = {'children', 'files', 'targets', 'buildPhases', 'dependencies', 'buildConfigurations'}
for identity, record in objects.items():
    for key, value in record.items():
        if key in reference_keys:
            assert value in objects, (identity, key, value)
        if key in reference_arrays:
            assert all(item in objects for item in value), (identity, key)
    if record['isa'] == 'PBXFileReference' and record.get('sourceTree') == 'SOURCE_ROOT':
        assert (root / record['path']).exists(), record['path']
    if record['isa'] == 'XCBuildConfiguration':
        settings = record['buildSettings']
        for key in ['INFOPLIST_FILE', 'CODE_SIGN_ENTITLEMENTS']:
            if key in settings:
                with (root / settings[key]).open('rb') as handle:
                    plistlib.load(handle)
targets = [value for value in objects.values() if value['isa'] == 'PBXNativeTarget']
assert {t['name'] for t in targets} == {'PrivacyGuard', 'MessageFilter', 'CallDirectory', 'ShareLink', 'KabutoUITests'}
for target in targets:
    phases = [objects[phase] for phase in target['buildPhases']]
    assert any(phase['isa'] == 'PBXSourcesBuildPhase' and phase['files'] for phase in phases)
app = next(target for target in targets if target['name'] == 'PrivacyGuard')
assert len(app['dependencies']) == 3
assert len(next(objects[p] for p in app['buildPhases'] if objects[p]['isa'] == 'PBXCopyFilesBuildPhase')['files']) == 3
ET.parse(root / 'PrivacyGuard.xcodeproj/xcshareddata/xcschemes/PrivacyGuard.xcscheme')
assert 'NSExtension' in plistlib.loads((root / 'Configuration/MessageFilter-Info.plist').read_bytes())
assert 'com.apple.developer.networking.networkextension' not in (root / 'Configuration/PrivacyGuard.entitlements').read_text()
print('PASS: source references, build graph, embedded extensions, plists, entitlements and scheme XML.')
print('NOT TESTED: Swift compilation, Xcode project loading, simulator or physical-device behavior.')
