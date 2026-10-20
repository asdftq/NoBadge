#!/usr/bin/env python3
"""Generate a small deterministic Xcode project using a local Swift package."""
from pathlib import Path
import argparse,hashlib,json
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source-build',action='store_true',help='Build without purchase activation or the commercial update feed.')
args=parser.parse_args()
root=Path(__file__).resolve().parent.parent
objects={}
def ID(s):return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def add(key,isa,**kw):
 i=ID(key);objects[i]={'isa':isa,**kw};return i
def q(s):return json.dumps(str(s))
appFiles=sorted((root/'NoBadge').rglob('*.swift'))
refs=[];builds=[]
for p in appFiles:
 rel=str(p.relative_to(root));r=add(rel,'PBXFileReference',lastKnownFileType='sourcecode.swift',path=rel,sourceTree='<group>');refs.append(r);builds.append(add(rel+'build','PBXBuildFile',fileRef=r))
resources=[]
for p in sorted((root/'NoBadge/Resources').rglob('*')):
 if p.is_file() and p.suffix in ['.json','.xcstrings','.icns','.txt']:
  rel=str(p.relative_to(root));r=add(rel,'PBXFileReference',lastKnownFileType={'.json':'text.json','.xcstrings':'text.json.xcstrings','.icns':'image.icns','.txt':'text'}[p.suffix],path=rel,sourceTree='<group>');refs.append(r);resources.append(add(rel+'build','PBXBuildFile',fileRef=r))
product=add('product','PBXFileReference',explicitFileType='wrapper.application',path='NoBadge.app',sourceTree='BUILT_PRODUCTS_DIR')
products=add('products','PBXGroup',children=[product],name='Products',sourceTree='<group>')
main=add('main','PBXGroup',children=refs+[products],sourceTree='<group>')
package=add('core-package','XCLocalSwiftPackageReference',relativePath='Packages/NoBadgeCore')
sparklePackage=add('sparkle-package','XCRemoteSwiftPackageReference',repositoryURL='https://github.com/sparkle-project/Sparkle',requirement={'kind':'exactVersion','version':'2.10.0'})
sparkleDependency=add('sparkle-product','XCSwiftPackageProductDependency',package=sparklePackage,productName='Sparkle')
dependency=add('core-product','XCSwiftPackageProductDependency',package=package,productName='NoBadgeCore')
frameworks=add('frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[add('core-link','PBXBuildFile',productRef=dependency),add('sparkle-link','PBXBuildFile',productRef=sparkleDependency)],runOnlyForDeploymentPostprocessing=0)
sources=add('sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=builds,runOnlyForDeploymentPostprocessing=0)
res=add('resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=resources,runOnlyForDeploymentPostprocessing=0)
testRefs=[];testBuilds=[]
for p in sorted((root/'Packages/NoBadgeCore/Tests/NoBadgeCoreTests').glob('*.swift')):
 rel=str(p.relative_to(root));r=add(rel,'PBXFileReference',lastKnownFileType='sourcecode.swift',path=rel,sourceTree='<group>');testRefs.append(r);testBuilds.append(add(rel+'testbuild','PBXBuildFile',fileRef=r))
for p in sorted((root/'Tests/AppModel').glob('*.swift')) + [root/'NoBadge/Model/AppModel.swift', root/'NoBadge/Platform/ChangeObserver.swift', root/'NoBadge/App/MenuBarIcon.swift']:
 rel=str(p.relative_to(root));r=add(rel,'PBXFileReference',lastKnownFileType='sourcecode.swift',path=rel,sourceTree='<group>')
 if r not in refs:testRefs.append(r)
 testBuilds.append(add(rel+'testbuild','PBXBuildFile',fileRef=r))
objects[main]['children'].extend(testRefs)
testProduct=add('tests-product','PBXFileReference',explicitFileType='wrapper.cfbundle',path='NoBadgeTests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
objects[products]['children'].append(testProduct)
testSources=add('tests-sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=testBuilds,runOnlyForDeploymentPostprocessing=0)
testFrameworks=add('tests-frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[add('test-core-link','PBXBuildFile',productRef=dependency)],runOnlyForDeploymentPostprocessing=0)
testConfigs=[]
for name in ['Debug','Release']:
 testConfigs.append(add('tests'+name,'XCBuildConfiguration',buildSettings={'PRODUCT_NAME':'NoBadgeTests','PRODUCT_BUNDLE_IDENTIFIER':'com.asdftq.nobadge.tests','GENERATE_INFOPLIST_FILE':'YES','SWIFT_VERSION':'6.0','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'NOBADGE_TESTING','MACOSX_DEPLOYMENT_TARGET':'15.0','SDKROOT':'macosx','ENABLE_TESTABILITY':'YES','ONLY_ACTIVE_ARCH':'YES','SWIFT_OPTIMIZATION_LEVEL':'-Onone','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @loader_path/Frameworks @executable_path/../Frameworks'},name=name))
testConfigList=add('tests-configlist','XCConfigurationList',buildConfigurations=testConfigs,defaultConfigurationIsVisible=0,defaultConfigurationName='Debug')
testTarget=add('tests-target','PBXNativeTarget',buildConfigurationList=testConfigList,buildPhases=[testSources,testFrameworks],buildRules=[],dependencies=[],name='NoBadgeTests',packageProductDependencies=[dependency],productName='NoBadgeTests',productReference=testProduct,productType='com.apple.product-type.bundle.unit-test')
version=(root/'VERSION').read_text().strip()
configs=[];projectconfigs=[]
for name in ['Debug','Release']:
 s={'PRODUCT_NAME':'NoBadge','PRODUCT_BUNDLE_IDENTIFIER':'com.asdftq.nobadge','DEVELOPMENT_TEAM':'G83X74Z537','CODE_SIGN_STYLE':'Manual','CODE_SIGN_IDENTITY':'Developer ID Application','ENABLE_HARDENED_RUNTIME':'YES','CODE_SIGN_INJECT_BASE_ENTITLEMENTS':'NO','OTHER_CODE_SIGN_FLAGS':'--timestamp','INFOPLIST_FILE':'NoBadge/Resources/Info.plist','GENERATE_INFOPLIST_FILE':'NO','MARKETING_VERSION':version,'CURRENT_PROJECT_VERSION':str(100+int(version.split('.')[-1])),'SWIFT_VERSION':'6.0','MACOSX_DEPLOYMENT_TARGET':'15.0','SDKROOT':'macosx','SUPPORTED_PLATFORMS':'macosx','COMBINE_HIDPI_IMAGES':'YES','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if name=='Debug' else '-O','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if name=='Debug' else '', 'ENABLE_APP_SANDBOX':'NO','ONLY_ACTIVE_ARCH':'YES' if name=='Debug' else 'NO'}
 if args.source_build:
  s.update({'DEVELOPMENT_TEAM':'','CODE_SIGN_IDENTITY':'-','OTHER_CODE_SIGN_FLAGS':'--timestamp=none','SWIFT_ACTIVE_COMPILATION_CONDITIONS':('DEBUG ' if name=='Debug' else '')+'NOBADGE_SOURCE_BUILD'})
 configs.append(add('app'+name,'XCBuildConfiguration',buildSettings=s,name=name))
 projectconfigs.append(add('project'+name,'XCBuildConfiguration',buildSettings={'CLANG_ENABLE_MODULES':'YES','MACOSX_DEPLOYMENT_TARGET':'15.0','SDKROOT':'macosx'},name=name))
cl=add('appconfiglist','XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
pcl=add('projectconfiglist','XCConfigurationList',buildConfigurations=projectconfigs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
target=add('target','PBXNativeTarget',buildConfigurationList=cl,buildPhases=[sources,frameworks,res],buildRules=[],dependencies=[],name='NoBadge',packageProductDependencies=[dependency,sparkleDependency],productName='NoBadge',productReference=product,productType='com.apple.product-type.application')
project=add('project','PBXProject',attributes={'LastUpgradeCheck':'2600','TargetAttributes':{target:{'CreatedOnToolsVersion':'26.6'}}},buildConfigurationList=pcl,compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','ko','Base'],mainGroup=main,packageReferences=[package,sparklePackage],productRefGroup=products,projectDirPath='',projectRoot='',targets=[target,testTarget])
def render(v):
 if isinstance(v,dict):return '{ '+''.join(q(k)+' = '+render(x)+'; ' for k,x in v.items())+'}'
 if isinstance(v,list):return '( '+', '.join(render(x) for x in v)+', )' if v else '()'
 if isinstance(v,int):return str(v)
 if v in objects:return str(v)
 return q(v)
p=root/'NoBadge.xcodeproj';p.mkdir(exist_ok=True)
(p/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = '+render(objects)+'; rootObject = '+project+'; }\n')
s=p/'xcshareddata/xcschemes';s.mkdir(parents=True,exist_ok=True)
(s/'NoBadge.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.7"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="NoBadge.app" BlueprintName="NoBadge" ReferencedContainer="container:NoBadge.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{testTarget}" BuildableName="NoBadgeTests.xctest" BlueprintName="NoBadgeTests" ReferencedContainer="container:NoBadge.xcodeproj"/></TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="NoBadge.app" BlueprintName="NoBadge" ReferencedContainer="container:NoBadge.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>\n''')
