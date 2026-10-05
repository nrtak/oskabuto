from pathlib import Path
import hashlib
import plistlib

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'PrivacyGuard.xcodeproj'
CONFIG = ROOT / 'Configuration'
CONFIG.mkdir(exist_ok=True)
OUT.mkdir(exist_ok=True)
objects = {}

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
target_ids = {name: ident('target:' + name) for name in ['PrivacyGuard', 'CallDirectory', 'MessageFilter']}

for name in target_ids:
    is_app = name == 'PrivacyGuard'
    sources = sorted((ROOT / ('App' if is_app else 'Extensions/' + name)).glob('*.swift'))
    sources += [ROOT / 'Shared' / file for file in (['CallStore.swift', 'SafetyEngine.swift'] if is_app else ['CallStore.swift'] if name == 'CallDirectory' else ['SafetyEngine.swift'])]
    refs, builds = [], []
    for file in sources:
        path = file.relative_to(ROOT).as_posix()
        ref = obj('file:' + path, 'PBXFileReference', lastKnownFileType='sourcecode.swift', path=path, sourceTree='SOURCE_ROOT')
        refs.append(ref)
        builds.append(obj('build:' + name + ':' + path, 'PBXBuildFile', fileRef=ref))
    group = obj('group:' + name, 'PBXGroup', children=refs, name=name, sourceTree='<group>')
    product = obj('product:' + name, 'PBXFileReference', explicitFileType='wrapper.application' if is_app else 'wrapper.app-extension', includeInIndex='0', path=name + ('.app' if is_app else '.appex'), sourceTree='BUILT_PRODUCTS_DIR')
    products.append(product)
    info = dict(CFBundleDevelopmentRegion='$(DEVELOPMENT_LANGUAGE)', CFBundleExecutable='$(EXECUTABLE_NAME)', CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)', CFBundleInfoDictionaryVersion='6.0', CFBundleName='$(PRODUCT_NAME)', CFBundlePackageType='APPL' if is_app else 'XPC!', CFBundleShortVersionString='1.0', CFBundleVersion='1')
    if is_app:
        info.update(CFBundleDisplayName='Privacy Guard', UILaunchScreen={}, NSCameraUsageDescription='Scan QR codes locally before opening them.', UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'])
    else:
        info['NSExtension'] = dict(NSExtensionPointIdentifier='com.apple.callkit.call-directory' if name == 'CallDirectory' else 'com.apple.identitylookup.message-filter', NSExtensionPrincipalClass='$(PRODUCT_MODULE_NAME).' + ('CallDirectoryHandler' if name == 'CallDirectory' else 'MessageFilterHandler'))
    info_path = plist(name + '-Info.plist', info)
    settings = dict(PRODUCT_BUNDLE_IDENTIFIER='com.example.privacyguard' + ('' if is_app else '.' + name), PRODUCT_NAME='$(TARGET_NAME)', INFOPLIST_FILE=info_path, SWIFT_VERSION='5.0', IPHONEOS_DEPLOYMENT_TARGET='17.0', TARGETED_DEVICE_FAMILY='1,2', CODE_SIGN_STYLE='Automatic', SDKROOT='iphoneos', LD_RUNPATH_SEARCH_PATHS=['$(inherited)', '@executable_path/Frameworks'] + ([] if is_app else ['@executable_path/../../Frameworks']), GENERATE_INFOPLIST_FILE='NO')
    if name != 'MessageFilter':
        settings['CODE_SIGN_ENTITLEMENTS'] = plist(name + '.entitlements', {'com.apple.security.application-groups': ['group.com.example.privacyguard']})
    if not is_app:
        settings.update(APPLICATION_EXTENSION_API_ONLY='YES', SKIP_INSTALL='YES')
    configs = []
    for mode in ['Debug', 'Release']:
        mode_settings = dict(settings, SWIFT_OPTIMIZATION_LEVEL='-Onone' if mode == 'Debug' else '-O')
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
        for child in ['CallDirectory', 'MessageFilter']:
            proxy = obj('proxy:' + child, 'PBXContainerItemProxy', containerPortal=ident('project'), proxyType='1', remoteGlobalIDString=target_ids[child], remoteInfo=child)
            dependencies.append(obj('dependency:' + child, 'PBXTargetDependency', target=target_ids[child], targetProxy=proxy))
            embed.append(obj('embed:' + child, 'PBXBuildFile', fileRef=ident('product:' + child), settings={'ATTRIBUTES': ['RemoveHeadersOnCopy']}))
        phases.append(obj('embed-phase', 'PBXCopyFilesBuildPhase', buildActionMask='2147483647', dstPath='', dstSubfolderSpec='13', files=embed, name='Embed App Extensions', runOnlyForDeploymentPostprocessing='0'))
    targets.append(obj('target:' + name, 'PBXNativeTarget', name=name, productName=name, buildConfigurationList=config_list, buildPhases=phases, buildRules=[], dependencies=dependencies, productReference=product, productType='com.apple.product-type.application' if is_app else 'com.apple.product-type.app-extension'))

product_group = obj('products', 'PBXGroup', children=products, name='Products', sourceTree='<group>')
main_group = obj('main', 'PBXGroup', children=[ident('group:' + name) for name in target_ids] + [product_group], sourceTree='<group>')
project_configs = [obj('project-config:' + mode, 'XCBuildConfiguration', name=mode, buildSettings={'CLANG_ENABLE_MODULES': 'YES'}) for mode in ['Debug', 'Release']]
project_config_list = obj('project-configs', 'XCConfigurationList', buildConfigurations=project_configs, defaultConfigurationIsVisible='0', defaultConfigurationName='Release')
project = obj('project', 'PBXProject', attributes={'LastUpgradeCheck': '1600'}, buildConfigurationList=project_config_list, compatibilityVersion='Xcode 14.0', developmentRegion='en', knownRegions=['en', 'Base'], mainGroup=main_group, productRefGroup=product_group, projectDirPath='', projectRoot='', targets=targets)
content = '// !$*UTF8*$!\n' + serialize(dict(archiveVersion='1', classes={}, objectVersion='56', objects=objects, rootObject=project)) + '\n'
(OUT / 'project.pbxproj').write_text(content, encoding='utf-8')
scheme_dir = OUT / 'xcshareddata' / 'xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_ids["PrivacyGuard"]}" BuildableName="PrivacyGuard.app" BlueprintName="PrivacyGuard" ReferencedContainer="container:PrivacyGuard.xcodeproj"/>'
(scheme_dir / 'PrivacyGuard.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''', encoding='utf-8')
print('Generated PrivacyGuard.xcodeproj with app and two embedded extensions.')
