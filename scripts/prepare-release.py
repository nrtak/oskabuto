import datetime
import json
import os
from pathlib import Path
import plistlib

team = os.environ['TEAM_ID']
bundle = os.environ['BUNDLE_ID']
with (Path(os.environ['RUNNER_TEMP']) / 'app.plist').open('rb') as file:
    profile = plistlib.load(file)
entitlements = profile['Entitlements']
if team not in profile.get('TeamIdentifier', []):
    raise SystemExit('Provisioning profile belongs to another team.')
prefix = profile['ApplicationIdentifierPrefix'][0]
if entitlements.get('application-identifier') != f'{prefix}.{bundle}':
    raise SystemExit('Provisioning profile does not match the app bundle ID.')
if profile['ExpirationDate'] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
    raise SystemExit('Provisioning profile has expired.')
if entitlements.get('get-task-allow') or profile.get('ProvisionedDevices') or profile.get('ProvisionsAllDevices'):
    raise SystemExit('An App Store distribution profile is required.')

# XcodeGen merges this app-specific overlay with the base specification.
spec = {
    'include': ['project.yml'],
    'targets': {'SimpleCurrency': {'settings': {'base': {
        'PRODUCT_BUNDLE_IDENTIFIER': bundle,
        'DEVELOPMENT_TEAM': team,
        'CODE_SIGN_STYLE': 'Manual',
        'CODE_SIGN_IDENTITY': 'Apple Distribution',
        'PROVISIONING_PROFILE_SPECIFIER': profile['UUID'],
    }}}},
}
Path('project-release.yml').write_text(json.dumps(spec, indent=2), encoding='utf-8')
with Path('ExportOptions.plist').open('wb') as file:
    plistlib.dump({
        'method': 'app-store-connect', 'destination': 'export',
        'teamID': team, 'signingStyle': 'manual',
        'signingCertificate': 'Apple Distribution',
        'manageAppVersionAndBuildNumber': False,
        'provisioningProfiles': {bundle: profile['UUID']},
    }, file)
