from pathlib import Path
import hashlib
import plistlib
import os
import re
import json

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'PrivacyGuard.xcodeproj'
CONFIG = ROOT / 'Configuration'
CONFIG.mkdir(exist_ok=True)
OUT.mkdir(exist_ok=True)
objects = {}
BUNDLE_ID = os.environ.get('APP_BUNDLE_ID', 'com.example.privacyguard')
GROUP_ID = os.environ.get('APP_GROUP_ID', 'group.' + BUNDLE_ID + '.privacyguard')
BUILD_NUMBER = os.environ.get('APP_BUILD_NUMBER', '1')
TEAM_ID = os.environ.get('APPLE_TEAM_ID', '')
SIGNING = json.loads(Path(os.environ['APP_SIGNING_CONFIG']).read_text()) if os.environ.get('APP_SIGNING_CONFIG') else {}
assert re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', BUNDLE_ID)
assert re.fullmatch(r'group\.[A-Za-z0-9.-]+', GROUP_ID)
assert re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', BUILD_NUMBER)

def ident(key):
    return hashlib.sha256(key.encode()).hexdigest()[:24].upper()

def quote(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'

def serialize(value):
    if isinstance(value, dict):
        return '{ ' + ' '.join(f'{k} = {serialize(v)};' for k, v in value.items()) + ' }'
    if isinstance(value, list):
        return '(' + ', '.join(serialize(v) for v in value) + ')'
    return quote(value)

def obj(key, isa, **fields):
    key = ident(key)
    objects[key] = dict(isa=isa, **fields)
    return key

def plist(name, content):
    path = CONFIG / name
    path.write_bytes(plistlib.dumps(content, sort_keys=True))
    return str(path.relative_to(ROOT)).replace('\\', '/')

targets = []
products = []
target_ids = {name: ident('target:' + name) for name in ['PrivacyGuard', 'CallDirectory', 'MessageFilter', 'ShareLink']}

for name in target_ids:
    is_app = name == 'PrivacyGuard'
    sources = sorted((ROOT / ('App' if is_app else 'Extensions/' + name)).glob('*.swift'))
    sources += [ROOT / 'Shared' / file for file in (['CallStore.swift', 'SafetyEngine.swift', 'AppleReleaseCatalog.swift'] if is_app else ['CallStore.swift'] if name == 'CallDirectory' else ['SafetyEngine.swift'])]
    refs, builds = [], []
    if name in ['PrivacyGuard', 'ShareLink']:
        sources.append(ROOT / 'Shared' / 'CheckResultSection.swift')
    for file in sources:
        path = file.relative_to(ROOT).as_posix()
        ref = obj('file:' + path, 'PBXFileReference', lastKnownFileType='sourcecode.swift', path=path, sourceTree='SOURCE_ROOT')
        refs.append(ref)
        builds.append(obj('build:' + name + ':' + path, 'PBXBuildFile', fileRef=ref))
    group = obj('group:' + name, 'PBXGroup', children=refs, name=name, sourceTree='<group>')
    product = obj('product:' + name, 'PBXFileReference', explicitFileType='wrapper.application' if is_app else 'wrapper.app-extension', includeInIndex='0', path=name + ('.app' if is_app else '.appex'), sourceTree='BUILT_PRODUCTS_DIR')
    products.append(product)
    info = dict(CFBundleDevelopmentRegion='$(DEVELOPMENT_LANGUAGE)', CFBundleExecutable='$(EXECUTABLE_NAME)', CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)', CFBundleInfoDictionaryVersion='6.0', CFBundleName='$(PRODUCT_NAME)', CFBundleDisplayName='Kabuto Call Protection' if name == 'CallDirectory' else 'Kabuto Message Filter', CFBundlePackageType='APPL' if is_app else 'XPC!', CFBundleShortVersionString='1.0', CFBundleVersion=BUILD_NUMBER)
    if name in ['PrivacyGuard', 'CallDirectory']:
        info['ProtectionAppGroup'] = GROUP_ID
    if is_app:
        info.update(CFBundleDisplayName='Kabuto', UILaunchScreen={}, NSCameraUsageDescription='Scan QR codes locally before opening them.', UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationPortraitUpsideDown', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'])
    else:
        info['NSExtension'] = dict(NSExtensionPointIdentifier='com.apple.callkit.call-directory' if name == 'CallDirectory' else 'com.apple.identitylookup.message-filter', NSExtensionPrincipalClass='$(PRODUCT_MODULE_NAME).' + ('CallDirectoryHandler' if name == 'CallDirectory' else 'MessageFilterHandler'))
    if name == 'ShareLink':
        info['CFBundleDisplayName'] = 'Check with Kabuto'
        info['NSExtension'] = dict(NSExtensionPointIdentifier='com.apple.share-services', NSExtensionPrincipalClass='$(PRODUCT_MODULE_NAME).ShareViewController', NSExtensionAttributes={'NSExtensionActivationRule': {'NSExtensionActivationSupportsWebURLWithMaxCount': 1, 'NSExtensionActivationSupportsText': True}})
    info_path = plist(name + '-Info.plist', info)
    settings = dict(PRODUCT_BUNDLE_IDENTIFIER='com.example.privacyguard' + ('' if is_app else '.' + name), PRODUCT_NAME='$(TARGET_NAME)', INFOPLIST_FILE=info_path, SWIFT_VERSION='5.0', IPHONEOS_DEPLOYMENT_TARGET='17.0', TARGETED_DEVICE_FAMILY='1,2', CODE_SIGN_STYLE='Automatic', SDKROOT='iphoneos', LD_RUNPATH_SEARCH_PATHS=['$(inherited)', '@executable_path/Frameworks'] + ([] if is_app else ['@executable_path/../../Frameworks']), GENERATE_INFOPLIST_FILE='NO')
    settings['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID + ('' if is_app else '.' + name)
    settings['CURRENT_PROJECT_VERSION'] = BUILD_NUMBER
    if TEAM_ID:
        settings['DEVELOPMENT_TEAM'] = TEAM_ID
    if is_app:
        info['ITSAppUsesNonExemptEncryption'] = False
        info['NSFaceIDUsageDescription'] = 'Kabuto checks whether Face ID is set up on this device.'
        info_path = plist(name + '-Info.plist', info)
    if name in ['PrivacyGuard', 'CallDirectory']:
        settings['REGISTER_APP_GROUPS'] = 'YES'
        settings['CODE_SIGN_ENTITLEMENTS'] = plist(name + '.entitlements', {'com.apple.security.application-groups': [GROUP_ID]})
    if not is_app:
        settings.update(APPLICATION_EXTENSION_API_ONLY='YES', SKIP_INSTALL='YES')
    configs = []
    for mode in ['Debug', 'Release']:
        mode_settings = dict(settings, SWIFT_OPTIMIZATION_LEVEL='-Onone' if mode == 'Debug' else '-O')
        if mode == 'Release' and SIGNING:
            profile = SIGNING[name]
            assert re.fullmatch(r'[A-Fa-f0-9-]{36}', profile)
            mode_settings.update(CODE_SIGN_STYLE='Manual', CODE_SIGN_IDENTITY='Apple Distribution',
                                 PROVISIONING_PROFILE_SPECIFIER=profile)
        if mode == 'Debug':
            mode_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
        configs.append(obj('config:' + name + mode, 'XCBuildConfiguration', name=mode, buildSettings=mode_settings))
    config_list = obj('configs:' + name, 'XCConfigurationList', buildConfigurations=configs, defaultConfigurationIsVisible='0', defaultConfigurationName='Release')
    phases = [obj('sources:' + name, 'PBXSourcesBuildPhase', buildActionMask='2147483647', files=builds, runOnlyForDeploymentPostprocessing='0'), obj('frameworks:' + name, 'PBXFrameworksBuildPhase', buildActionMask='2147483647', files=[], runOnlyForDeploymentPostprocessing='0')]
    if is_app:
        asset_ref = obj('assets', 'PBXFileReference', lastKnownFileType='folder.assetcatalog', path='App/Assets.xcassets', sourceTree='SOURCE_ROOT')
        objects[group]['children'].append(asset_ref)
        asset_build = obj('assets-build', 'PBXBuildFile', fileRef=asset_ref)
        privacy_ref = obj('privacy', 'PBXFileReference', lastKnownFileType='text.xml', path='App/PrivacyInfo.xcprivacy', sourceTree='SOURCE_ROOT')
        objects[group]['children'].append(privacy_ref)
        privacy_build = obj('privacy-build', 'PBXBuildFile', fileRef=privacy_ref)
        phases.append(obj('resources:' + name, 'PBXResourcesBuildPhase', buildActionMask='2147483647', files=[asset_build, privacy_build], runOnlyForDeploymentPostprocessing='0'))
        for config in configs:
            objects[config]['buildSettings']['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
    dependencies = []
    if is_app:
        embed = []
        for child in ['CallDirectory', 'MessageFilter', 'ShareLink']:
            proxy = obj('proxy:' + child, 'PBXContainerItemProxy', containerPortal=ident('project'), proxyType='1', remoteGlobalIDString=target_ids[child], remoteInfo=child)
            dependencies.append(obj('dependency:' + child, 'PBXTargetDependency', target=target_ids[child], targetProxy=proxy))
            embed.append(obj('embed:' + child, 'PBXBuildFile', fileRef=ident('product:' + child), settings={'ATTRIBUTES': ['RemoveHeadersOnCopy']}))
        phases.append(obj('embed-phase', 'PBXCopyFilesBuildPhase', buildActionMask='2147483647', dstPath='', dstSubfolderSpec='13', files=embed, name='Embed App Extensions', runOnlyForDeploymentPostprocessing='0'))
    targets.append(obj('target:' + name, 'PBXNativeTarget', name=name, productName=name, buildConfigurationList=config_list, buildPhases=phases, buildRules=[], dependencies=dependencies, productReference=product, productType='com.apple.product-type.application' if is_app else 'com.apple.product-type.app-extension'))

# The UI test runner is built only by the scheme's Test action.
ui_name = 'KabutoUITests'
ui_source = obj('file:ui-tests', 'PBXFileReference', lastKnownFileType='sourcecode.swift', path='UITests/HomeFlowTests.swift', sourceTree='SOURCE_ROOT')
ui_build = obj('build:ui-tests', 'PBXBuildFile', fileRef=ui_source)
ui_phase = obj('sources:ui-tests', 'PBXSourcesBuildPhase', buildActionMask='2147483647', files=[ui_build], runOnlyForDeploymentPostprocessing='0')
ui_product = obj('product:ui-tests', 'PBXFileReference', explicitFileType='wrapper.cfbundle', path=ui_name + '.xctest', sourceTree='BUILT_PRODUCTS_DIR')
products.append(ui_product)
ui_configs = [obj('ui-config:' + mode, 'XCBuildConfiguration', name=mode, buildSettings=dict(
    PRODUCT_BUNDLE_IDENTIFIER=BUNDLE_ID + '.uitests', PRODUCT_NAME='$(TARGET_NAME)', GENERATE_INFOPLIST_FILE='YES',
    IPHONEOS_DEPLOYMENT_TARGET='17.0', SDKROOT='iphoneos', TARGETED_DEVICE_FAMILY='1,2',
    SWIFT_VERSION='5.0', TEST_TARGET_NAME='PrivacyGuard', SKIP_INSTALL='YES')) for mode in ['Debug', 'Release']]
ui_config_list = obj('ui-configs', 'XCConfigurationList', buildConfigurations=ui_configs, defaultConfigurationIsVisible='0', defaultConfigurationName='Release')
ui_proxy = obj('ui-app-proxy', 'PBXContainerItemProxy', containerPortal=ident('project'), proxyType='1', remoteGlobalIDString=target_ids['PrivacyGuard'], remoteInfo='PrivacyGuard')
ui_dep = obj('ui-app-dependency', 'PBXTargetDependency', target=target_ids['PrivacyGuard'], targetProxy=ui_proxy)
ui_target = obj('target:ui-tests', 'PBXNativeTarget', name=ui_name, productName=ui_name, buildConfigurationList=ui_config_list,
                buildPhases=[ui_phase], buildRules=[], dependencies=[ui_dep], productReference=ui_product, productType='com.apple.product-type.bundle.ui-testing')
targets.append(ui_target)

product_group = obj('products', 'PBXGroup', children=products, name='Products', sourceTree='<group>')
main_group = obj('main', 'PBXGroup', children=[ident('group:' + name) for name in target_ids] + [ui_source, product_group], sourceTree='<group>')
project_configs = [obj('project-config:' + mode, 'XCBuildConfiguration', name=mode, buildSettings={'CLANG_ENABLE_MODULES': 'YES'}) for mode in ['Debug', 'Release']]
project_config_list = obj('project-configs', 'XCConfigurationList', buildConfigurations=project_configs, defaultConfigurationIsVisible='0', defaultConfigurationName='Release')
target_attributes = {target_ids[name]: {'SystemCapabilities': {'com.apple.ApplicationGroups.iOS': {'enabled': '1'}}} for name in ['PrivacyGuard', 'CallDirectory']}
target_attributes[ui_target] = {'TestTargetID': target_ids['PrivacyGuard']}
project = obj('project', 'PBXProject', attributes={'LastUpgradeCheck': '1600', 'TargetAttributes': target_attributes}, buildConfigurationList=project_config_list, compatibilityVersion='Xcode 14.0', developmentRegion='en', knownRegions=['en', 'Base'], mainGroup=main_group, productRefGroup=product_group, projectDirPath='', projectRoot='', targets=targets)
content = '// !$*UTF8*$!\n' + serialize(dict(archiveVersion='1', classes={}, objectVersion='56', objects=objects, rootObject=project)) + '\n'
(OUT / 'project.pbxproj').write_text(content, encoding='utf-8')
scheme_dir = OUT / 'xcshareddata' / 'xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_ids["PrivacyGuard"]}" BuildableName="PrivacyGuard.app" BlueprintName="PrivacyGuard" ReferencedContainer="container:PrivacyGuard.xcodeproj"/>'
(scheme_dir / 'PrivacyGuard.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ui_target}" BuildableName="{ui_name}.xctest" BlueprintName="{ui_name}" ReferencedContainer="container:PrivacyGuard.xcodeproj"/></TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''', encoding='utf-8')
print('Generated PrivacyGuard.xcodeproj with app and three embedded extensions.')
