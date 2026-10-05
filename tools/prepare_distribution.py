"""Prepare App Store profiles using the existing release certificate and API key."""
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from urllib.error import HTTPError
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen


def b64(value):
    return base64.urlsafe_b64encode(value).rstrip(b'=').decode()


def raw_signature(der):
    if not der or der[0] != 0x30 or der[1] != len(der) - 2:
        raise ValueError('Invalid ES256 signature')
    offset, parts = 2, []
    for _ in range(2):
        if der[offset] != 2:
            raise ValueError('Invalid ES256 signature integer')
        length = der[offset + 1]
        part = der[offset + 2:offset + 2 + length].lstrip(b'\0')
        if not part or len(part) > 32:
            raise ValueError('Invalid ES256 signature size')
        parts.append(part.rjust(32, b'\0'))
        offset += 2 + length
    if offset != len(der):
        raise ValueError('Invalid ES256 signature length')
    return b''.join(parts)


class AppleAPI:
    def __init__(self, key_path):
        now = int(time.time())
        header = {'alg': 'ES256', 'kid': os.environ['ASC_KEY_ID'], 'typ': 'JWT'}
        claims = {'iss': os.environ['ASC_ISSUER_ID'], 'iat': now, 'exp': now + 600,
                  'aud': 'appstoreconnect-v1'}
        data = '.'.join(b64(json.dumps(v, separators=(',', ':')).encode()) for v in [header, claims])
        signature = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', str(key_path)],
                                   input=data.encode(), capture_output=True, check=True).stdout
        self.token = data + '.' + b64(raw_signature(signature))

    def request(self, path, payload=None):
        url = path if path.startswith('https://') else 'https://api.appstoreconnect.apple.com' + path
        parsed = urlparse(url)
        if parsed.scheme != 'https' or parsed.netloc != 'api.appstoreconnect.apple.com':
            raise ValueError('Unexpected Apple API destination')
        request = Request(url, data=json.dumps(payload).encode() if payload else None,
                          headers={'Authorization': 'Bearer ' + self.token, 'Content-Type': 'application/json'})
        try:
            with urlopen(request, timeout=45) as response:
                return json.load(response)
        except HTTPError as error:
            # Never log raw responses, bearer tokens, keys or certificate contents.
            try:
                codes = [e.get('code', '') for e in json.loads(error.read()).get('errors', [])]
            except (ValueError, TypeError):
                codes = []
            safe_codes = ','.join(c for c in codes if re.fullmatch(r'[A-Za-z0-9_.-]+', c))
            raise RuntimeError(f'Apple signing API {request.get_method()} {parsed.path}: HTTP {error.code} ({safe_codes}). '
                               'Check the existing key permissions and Apple Developer setup.') from None

    def listing(self, path, filters=None):
        path += '?' + urlencode({'limit': 50, **(filters or {})})
        items = []
        while path:
            result = self.request(path)
            items.extend(result['data'])
            path = result.get('links', {}).get('next')
        return items


def decode_profile(path):
    return plistlib.loads(subprocess.run(['security', 'cms', '-D', '-i', str(path)],
                                        capture_output=True, check=True).stdout)


def valid_profile(profile, bundle, certificate, group=None):
    entitlements = profile.get('Entitlements', {})
    expiry = profile.get('ExpirationDate')
    return (profile.get('TeamIdentifier') == [os.environ['APPLE_TEAM_ID']]
            and entitlements.get('application-identifier', '').split('.', 1)[-1] == bundle
            and expiry and expiry.replace(tzinfo=timezone.utc) > datetime.now(timezone.utc)
            and entitlements.get('get-task-allow') is False
            and not profile.get('ProvisionedDevices') and not profile.get('ProvisionsAllDevices')
            and any(hashlib.sha256(c).digest() == certificate for c in profile.get('DeveloperCertificates', []))
            and (group is None or group in entitlements.get('com.apple.security.application-groups', [])))


def main():
    os.umask(0o077)
    temp = Path(os.environ['RUNNER_TEMP'])
    key = Path.home() / '.appstoreconnect/private_keys' / ('AuthKey_' + os.environ['ASC_KEY_ID'] + '.p8')
    seed_path = temp / 'PrivacyGuard-existing.mobileprovision'
    seed_path.write_bytes(base64.b64decode(os.environ['APP_PROFILE']))
    seed = decode_profile(seed_path)
    if seed.get('TeamIdentifier') != [os.environ['APPLE_TEAM_ID']]:
        raise RuntimeError('Existing release profile belongs to a different Apple team.')
    hashes = {hashlib.sha256(c).digest() for c in seed['DeveloperCertificates']}
    api = AppleAPI(key)
    certificates = api.listing('/v1/certificates')
    cert = next((c for c in certificates if c['attributes']['certificateType'] in
                 ['DISTRIBUTION', 'IOS_DISTRIBUTION'] and hashlib.sha256(base64.b64decode(
                     c['attributes']['certificateContent'])).digest() in hashes), None)
    if cert is None:
        raise RuntimeError('The existing distribution certificate was not found in the Apple account.')
    certificate_hash = hashlib.sha256(base64.b64decode(cert['attributes']['certificateContent'])).digest()
    base = os.environ['APP_BUNDLE_ID']
    group = os.environ.get('APP_GROUP_ID', 'group.' + base + '.privacyguard')
    profiles, installed = {}, []
    for target in ['PrivacyGuard', 'CallDirectory', 'MessageFilter']:
        bundle = base + ('' if target == 'PrivacyGuard' else '.' + target)
        bundles = api.listing('/v1/bundleIds', {'filter[identifier]': bundle, 'filter[platform]': 'IOS'})
        if not bundles:
            if target == 'PrivacyGuard':
                raise RuntimeError('Existing app bundle identifier was not found; refusing to replace the app record.')
            bundles = [api.request('/v1/bundleIds', {'data': {'type': 'bundleIds', 'attributes': {
                'identifier': bundle, 'name': 'PrivacyGuard ' + target, 'platform': 'IOS'}}})['data']]
        bundle_resource = bundles[0]
        required_group = group if target != 'MessageFilter' else None
        if required_group:
            capabilities = api.listing('/v1/bundleIds/' + bundle_resource['id'] + '/bundleIdCapabilities')
            if not any(c['attributes']['capabilityType'] == 'APP_GROUPS' for c in capabilities):
                api.request('/v1/bundleIdCapabilities', {'data': {'type': 'bundleIdCapabilities',
                    'attributes': {'capabilityType': 'APP_GROUPS'}, 'relationships': {'bundleId': {
                        'data': {'type': 'bundleIds', 'id': bundle_resource['id']}}}}})
        name = 'PrivacyGuard App Store ' + target
        candidates = api.listing('/v1/profiles', {'filter[name]': name})
        data, decoded = None, None
        for candidate in candidates:
            if candidate['attributes']['profileType'] != 'IOS_APP_STORE':
                continue
            blob = base64.b64decode(candidate['attributes']['profileContent'])
            candidate_path = temp / 'PrivacyGuard-candidate.mobileprovision'
            candidate_path.write_bytes(blob)
            candidate_profile = decode_profile(candidate_path)
            if valid_profile(candidate_profile, bundle, certificate_hash, required_group):
                data, decoded = blob, candidate_profile
                break
        if data is None:
            created = api.request('/v1/profiles', {'data': {'type': 'profiles',
                'attributes': {'name': name, 'profileType': 'IOS_APP_STORE'}, 'relationships': {
                    'bundleId': {'data': {'type': 'bundleIds', 'id': bundle_resource['id']}},
                    'certificates': {'data': [{'type': 'certificates', 'id': cert['id']}]}}}})['data']
            data = base64.b64decode(created['attributes']['profileContent'])
            candidate_path = temp / 'PrivacyGuard-candidate.mobileprovision'
            candidate_path.write_bytes(data)
            decoded = decode_profile(candidate_path)
        if not valid_profile(decoded, bundle, certificate_hash, required_group):
            if required_group and required_group not in decoded.get('Entitlements', {}).get('com.apple.security.application-groups', []):
                raise RuntimeError(f'Register App Group {group} in Apple Developer and assign it to '
                                   f'{base} and {base}.CallDirectory, then rerun this workflow.')
            raise RuntimeError('Apple returned a profile that does not match the required distribution settings.')
        uuid = decoded['UUID']
        if not re.fullmatch(r'[A-Fa-f0-9-]{36}', uuid):
            raise RuntimeError('Unexpected provisioning profile identifier')
        for directory in [Path.home() / 'Library/MobileDevice/Provisioning Profiles',
                          Path.home() / 'Library/Developer/Xcode/UserData/Provisioning Profiles']:
            directory.mkdir(parents=True, exist_ok=True)
            destination = directory / (uuid + '.mobileprovision')
            destination.write_bytes(data)
            installed.append(str(destination))
            (temp / 'PrivacyGuard-installed-profiles.json').write_text(json.dumps(installed))
        profiles[target] = uuid
        print('Prepared App Store distribution profile for ' + target + '.')
    (temp / 'PrivacyGuard-installed-profiles.json').write_text(json.dumps(installed))
    (temp / 'PrivacyGuard-signing.json').write_text(json.dumps(profiles))
    export = {'method': 'app-store-connect', 'destination': 'export', 'teamID': os.environ['APPLE_TEAM_ID'],
              'signingStyle': 'manual', 'signingCertificate': 'Apple Distribution',
              'manageAppVersionAndBuildNumber': False,
              'provisioningProfiles': {base + ('' if name == 'PrivacyGuard' else '.' + name): uuid
                                       for name, uuid in profiles.items()}}
    (temp / 'PrivacyGuard-ExportOptions.plist').write_bytes(plistlib.dumps(export))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        if isinstance(error, RuntimeError):
            print('::error::' + str(error), file=sys.stderr)
        else:
            print('::error::Distribution preparation failed (' + type(error).__name__ + ').', file=sys.stderr)
        sys.exit(1)
