from pathlib import Path
import re,json
root=Path(__file__).resolve().parent.parent
keys=set()
for p in (root/'NoBadge').rglob('*.swift'):
 keys.update(re.findall(r'L\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"\)',p.read_text()))
for p in (root/'Packages/NoBadgeCore/Sources/NoBadgeCore').glob('*.swift'):
 keys.update(re.findall(r'case [^\n]+: "([^"\n]+)"',p.read_text()))
ko={
'Update NoBadge for this macOS version':'이 macOS 버전에 맞게 NoBadge를 업데이트하세요',
'This macOS version or Mac architecture needs a compatible NoBadge update.':'이 macOS 버전 또는 Mac 아키텍처를 지원하는 NoBadge 업데이트가 필요합니다.',
'This macOS family is supported. Settings are checked before changes.':'지원하는 macOS 계열입니다. 변경 전에 설정 형식을 확인합니다.',
'Cannot synchronize notification settings.':'알림 설정을 동기화할 수 없습니다.','Cannot persist notification settings.':'알림 설정을 저장할 수 없습니다.','Cannot prepare notification settings.':'알림 설정 변경을 준비할 수 없습니다.','Cannot identify the current user.':'현재 사용자를 확인할 수 없습니다.',
'Edit':'편집','Undo':'실행 취소','Redo':'다시 실행','Cut':'잘라내기','Copy':'복사','Paste':'붙여넣기','Select All':'모두 선택','Window':'윈도우','Close':'닫기',
'Open NoBadge':'NoBadge 열기',
'Review diagnostics':'진단 정보 확인','Save…':'저장…','Cancel':'취소','The export contains only version, compatibility, state, and counts. It does not include Focus names, app lists, message data, or recovery journals.':'버전, 호환성, 상태와 개수만 저장됩니다. 집중 모드 이름, 앱 목록, 메시지 데이터와 복원 기록은 포함하지 않습니다.',
'Check for updates automatically':'업데이트 자동 확인','Updates are temporarily unavailable.':'지금은 업데이트를 확인할 수 없습니다.','Updates are not available for this preview yet. This version will keep working offline.':'이 미리보기 버전의 업데이트는 아직 제공되지 않습니다. 현재 버전은 오프라인에서도 사용할 수 있어요.','Restore previous badge settings before installing the update.':'업데이트를 설치하기 전에 이전 배지 설정을 복원하세요.',
'NoBadge cannot read Focus yet. Turn on a Focus once, then check access again.':'아직 집중 모드를 읽을 수 없습니다. 집중 모드를 한 번 켠 뒤 접근 권한을 다시 확인하세요.',
'NoBadge':'NoBadge','OK':'확인','Settings':'설정','NoBadge Settings':'NoBadge 설정',
'General':'일반','Apps':'앱','Help & Recovery':'도움말 및 복원','About':'정보','Language':'언어',
'A quieter Dock when you focus.':'집중할 때, 더 조용한 Dock.',
'NoBadge hides supported app badges during Focus and restores your previous badge settings afterward.':'집중 모드가 켜지면 지원하는 앱의 배지를 숨기고, 끝나면 이전 배지 설정으로 복원합니다.',
'Set up NoBadge':'NoBadge 설정하기','Not now':'나중에','Back':'뒤로','Continue':'계속',
'Before':'평소','During Focus':'집중할 때','Preview':'미리보기',
'Allow NoBadge to manage badge settings.':'NoBadge가 배지 설정을 관리하도록 허용하세요.',
'macOS requires Full Disk Access for these settings. This permission can allow broad file access. NoBadge uses it only for Focus settings and notification preferences; it does not read your messages or documents.':'이 설정을 사용하려면 전체 디스크 접근 권한이 필요합니다. 이 권한은 폭넓은 파일 접근을 허용하지만, NoBadge는 집중 모드와 알림 설정에만 사용합니다. 메시지나 문서는 읽지 않습니다.',
'1. Open Privacy & Security → Full Disk Access.':'1. 개인정보 보호 및 보안 → 전체 디스크 접근 권한을 여세요.',
'2. Add NoBadge from Applications and turn it on.':'2. 응용 프로그램의 NoBadge를 추가하고 켜세요.',
'3. Return here and check access.':'3. 이 화면으로 돌아와 접근 권한을 확인하세요.',
'Open System Settings':'시스템 설정 열기','Show NoBadge in Finder':'Finder에서 NoBadge 보기','Check access':'접근 권한 확인','Access confirmed.':'접근 권한을 확인했습니다.',
'Finish setup':'설정을 완료하세요','Continue setup':'설정 계속하기','Ready for Focus':'집중할 준비가 됐어요',
'Turn on Focus as usual.':'평소처럼 집중 모드를 켜세요.','Ready. Turn on Focus as usual.':'준비됐어요. 평소처럼 집중 모드를 켜세요.',
'Hide badges during any Focus':'모든 집중 모드에서 배지 숨기기','Hide automatically during Focus':'집중 모드에서 자동으로 숨기기',
'You can keep badges for specific apps in Settings.':'특정 앱의 배지는 설정에서 계속 표시할 수 있어요.',
'Open at login':'로그인 시 실행','Open at login is enabled.':'로그인 시 실행이 켜져 있습니다.','Open at login is off.':'로그인 시 실행이 꺼져 있습니다.',
'Approve NoBadge in Login Items to finish.':'로그인 항목에서 NoBadge를 허용하면 완료됩니다.',
'Optional: check a supported app that already has a Dock badge.':'선택 사항: Dock에 배지가 있는 앱으로 확인해 보세요.',
'Test app':'테스트할 앱','Choose an app':'앱 선택','Test this badge':'이 배지 테스트하기',
'Check the Dock badge. Restore it when you are done; the test ends automatically after 30 seconds.':'Dock의 배지를 확인하세요. 확인 후 복원해 주세요. 테스트는 30초 후 자동으로 끝납니다.',
'Restore test badge':'테스트 배지 복원','You can skip this test and enable NoBadge.':'테스트를 건너뛰고 NoBadge를 켜도 됩니다.',
'Enable NoBadge':'NoBadge 켜기','Hiding badges':'배지를 숨기고 있어요','No supported enabled badges to hide.':'숨길 수 있는 활성 배지가 없어요.',
'Showing badges':'배지를 표시하고 있어요','Automatic hiding is off':'자동 숨김이 꺼져 있어요','You can still hide badges for 30 minutes.':'30분 동안 수동으로 숨길 수 있어요.',
'Updating badge settings…':'배지 설정 적용 중…','Please wait…':'잠시 기다려 주세요…','Until':'종료 시각','supported apps':'개 앱',
'Show badges for 15 minutes':'15분 동안 배지 표시','Show badges now':'지금 배지 표시','Resume now':'지금 다시 시작','Hide for 30 minutes':'30분 동안 숨기기',
'Apps to keep visible…':'배지를 계속 표시할 앱…','Help & Recovery…':'도움말 및 복원…','Restore & Quit':'복원하고 종료',
'Access needs attention':'접근 권한이 필요해요','Allow access to read Focus and manage badge settings.':'집중 모드와 배지 설정을 사용하도록 접근 권한을 허용하세요.',
'This macOS version needs an update':'macOS 호환성 업데이트가 필요해요','Automatic hiding stays off until this macOS build is qualified.':'이 macOS 버전의 호환성을 확인할 때까지 자동 숨김이 중지됩니다.',
'Focus needs attention':'집중 모드를 확인해 주세요','NoBadge cannot read Focus right now. Manual hiding is still available.':'지금 집중 모드를 읽을 수 없습니다. 수동 숨김은 사용할 수 있어요.',
'Some badge settings still need restoring':'일부 배지 설정을 복원해야 해요','Restore previous settings':'이전 설정 복원','Retry safely':'안전하게 다시 시도','Automatic hiding is paused':'자동 숨김이 일시 중지됐어요',
'Your previous settings are restored.':'이전 배지 설정으로 복원했습니다.',
'When to hide':'숨기는 시점','Any Focus':'모든 집중 모드','Selected Focus modes':'선택한 집중 모드','Choose at least one Focus.':'집중 모드를 하나 이상 선택하세요.','Unavailable Focus':'사용할 수 없는 집중 모드','Remove':'제거',
'Badges do not control notification sounds, banners, or message delivery. Focus handles those settings.':'배지 숨김은 알림 소리, 배너, 메시지 수신을 제어하지 않습니다. 해당 설정은 집중 모드에서 관리합니다.',
'Keep badges visible for these apps.':'이 앱들의 배지를 계속 표시합니다.','Search apps':'앱 검색',
'Some apps draw their own badges and cannot be controlled. Only registered supported apps appear here.':'자체 배지를 표시하는 일부 앱은 제어할 수 없습니다. 등록된 지원 앱만 이 목록에 표시됩니다.',
'Full Disk Access allows broad file access. NoBadge uses it only for Focus and notification settings; it does not read messages or documents.':'전체 디스크 접근 권한은 폭넓은 파일 접근을 허용합니다. NoBadge는 집중 모드와 알림 설정에만 사용하며 메시지나 문서를 읽지 않습니다.',
'Pause NoBadge before changing badge settings in System Settings. If the app is force-quit, open it again to restore pending settings.':'시스템 설정에서 배지 설정을 바꾸기 전에 NoBadge를 일시 중지하세요. 앱을 강제 종료했다면 다시 열어 남은 설정을 복원하세요.',
'Prepare to uninstall':'앱 삭제 준비','Export diagnostics…':'진단 정보 저장…',
'Diagnostics stay on your Mac. The export excludes Focus names, application lists, message data, and recovery journals.':'진단 정보는 Mac에만 저장됩니다. 집중 모드 이름, 앱 목록, 메시지 데이터, 복원 기록은 포함하지 않습니다.',
'Compatibility details':'호환성 상세 정보','This build is qualified for the current adapter.':'현재 어댑터에서 확인한 macOS 버전입니다.','This build has not been qualified.':'아직 확인하지 않은 macOS 버전입니다.',
'Verification mode · synthetic apps only':'검증 모드 · 테스트 앱만 제어','Version':'버전','Check for Updates':'업데이트 확인',
'Badge and Focus processing happens locally. No usage analytics or automatic diagnostic uploads.':'배지와 집중 모드 처리는 Mac 안에서 이루어집니다. 사용 분석이나 진단 정보 자동 업로드는 없습니다.',
'Inspired by FocusNoBadges and FocusPlsNoBadges. Original implementation; no upstream code or artwork included.':'FocusNoBadges와 FocusPlsNoBadges에서 영감을 받았습니다. 코드는 직접 구현했으며 원본 코드나 이미지가 포함되어 있지 않습니다.',
'Saved settings could not be read. Your recovery information has been kept.':'저장된 설정을 읽을 수 없습니다. 복원 정보는 보관되어 있습니다.',
'macOS settings are not available yet. Turn on a Focus once, then check again.':'macOS 설정이 아직 없습니다. 집중 모드를 한 번 켠 뒤 다시 확인하세요.',
'NoBadge could not save your settings.':'NoBadge 설정을 저장할 수 없습니다.','Login settings could not be updated.':'로그인 설정을 변경할 수 없습니다.','Diagnostics could not be saved.':'진단 정보를 저장할 수 없습니다.',
'Retry restoration or keep NoBadge open. Quitting anyway may leave some badges turned off; open NoBadge again to recover.':'복원을 다시 시도하거나 NoBadge를 계속 열어 두세요. 그냥 종료하면 일부 배지가 꺼진 채 남을 수 있습니다. 다시 열면 복원할 수 있어요.',
'Retry restoration':'복원 다시 시도','Keep open':'계속 열어 두기','Quit anyway':'그냥 종료',
'Update hosting is not configured for this preview. Keep using this version offline; check the release notes for availability.':'이 미리보기 버전은 아직 업데이트 서버가 연결되지 않았습니다. 현재 버전은 오프라인에서도 사용할 수 있어요.',
'These macOS settings have changed. Automatic hiding is paused.':'macOS 설정 형식이 변경되었습니다. 자동 숨김을 일시 중지했습니다.',
'Your notification settings changed. NoBadge paused to keep them safe.':'알림 설정이 변경되어 안전하게 유지하기 위해 일시 중지했습니다.',
'Saved recovery information could not be read.':'저장된 복원 정보를 읽을 수 없습니다.','Badge settings could not be confirmed.':'배지 설정 적용을 확인할 수 없습니다.','This macOS version needs a compatibility update.':'이 macOS 버전의 호환성 업데이트가 필요합니다.'
}
ko.update({'1. Open System Settings below.': '1. 아래에서 시스템 설정을 여세요.', '3. Return here. Quit and reopen NoBadge if macOS asks.': '3. 여기로 돌아오세요. macOS가 요청하면 NoBadge를 종료 후 다시 여세요.', 'Apps appear after they register for notifications.': '알림에 등록된 앱이 여기에 표시됩니다.', 'Apps with their own badge system may not respond to macOS badge settings.': '자체 배지를 사용하는 앱에는 macOS 배지 설정이 적용되지 않을 수 있습니다.', 'Check Focus again': '집중 모드 다시 확인', 'Check again': '다시 확인', 'Checking Focus…': '집중 모드 확인 중…', 'Choose apps to keep visible in Settings → Apps. You can pause or quit from the menu bar at any time.': '설정 → 앱에서 배지를 계속 표시할 앱을 선택하세요. 메뉴 막대에서 언제든 일시 중지하거나 종료할 수 있습니다.', 'Choose…': '선택…', 'Diagnostics contain only app version, compatibility and status. Your Focus names, app list and messages stay private.': '진단에는 앱 버전, 호환성, 상태만 포함됩니다. 집중 모드 이름, 앱 목록, 메시지는 포함되지 않습니다.', 'Done': '완료', 'Fix access': '접근 권한 설정', 'Focus could not be read. Check access below.': '집중 모드를 읽을 수 없습니다. 접근 권한을 확인하세요.', 'Focus is not available yet. Turn on a Focus once, then check again.': '집중 모드를 아직 읽을 수 없습니다. 집중 모드를 한 번 켠 뒤 다시 확인하세요.', 'Focus is off': '집중 모드가 꺼져 있습니다', 'Full Disk Access is enabled': '전체 디스크 접근 권한이 켜져 있습니다', 'Full Disk Access is needed': '전체 디스크 접근 권한이 필요합니다', 'Hide badges while you focus.': '집중하는 동안 배지를 숨기세요.', 'Kept visible': '계속 표시', 'No supported apps yet': '아직 지원 앱이 없습니다', 'NoBadge needs Full Disk Access to read Focus and change badge settings.': '집중 모드를 읽고 배지 설정을 변경하려면 전체 디스크 접근 권한이 필요합니다.', 'On': '켜짐', 'Only badges change. Focus controls notification sounds and banners.': '배지만 변경합니다. 알림 소리와 배너는 집중 모드에서 제어합니다.', 'Pause NoBadge before changing badge settings in System Settings. Reopen NoBadge after a force quit to restore pending settings.': '시스템 설정에서 배지 설정을 바꾸기 전에 NoBadge를 일시 중지하세요. 강제 종료했다면 다시 열어 남은 설정을 복원하세요.', 'Restore badges before removing NoBadge.': 'NoBadge를 삭제하기 전에 배지를 복원하세요.', 'Review setup': '설정 안내 다시 보기', 'Start NoBadge': 'NoBadge 시작', 'This permission allows broad file access. NoBadge only uses Focus and notification settings. It does not read messages or documents.': '이 권한은 폭넓은 파일 접근을 허용합니다. NoBadge는 집중 모드와 알림 설정에만 사용하며 메시지나 문서는 읽지 않습니다.', 'Turn on Focus as usual. NoBadge hides supported badges and restores your previous settings when Focus ends.': '평소처럼 집중 모드를 켜세요. NoBadge가 지원 앱의 배지를 숨기고 집중 모드가 끝나면 이전 설정으로 복원합니다.', 'Verification mode': '검증 모드', "You're ready.": '준비됐습니다.', 'Allow Full Disk Access to read Focus and manage badges.': '집중 모드를 읽고 배지를 관리하도록 전체 디스크 접근 권한을 허용하세요.'})
ko.update({'Install NoBadge first':'먼저 NoBadge를 설치하세요', 'Show installer':'설치 창 보기', 'Quit':'종료', 'Drag NoBadge to Applications in the installer window, then open the copy in Applications. Complete the access guide from the installed app.':'설치 창에서 NoBadge를 응용 프로그램으로 드래그한 다음, 응용 프로그램 안의 앱을 여세요. 설치된 앱에서 접근 권한 안내를 따라 주세요.'})
ko.update({'Download purchased updates':'구매한 업데이트 다운로드', 'Open My Orders':'내 주문 열기', 'Get the latest download from Lemon Squeezy My Orders using the email address on your receipt. NoBadge does not check for updates or download files automatically.':'영수증의 이메일 주소로 Lemon Squeezy 내 주문에 로그인하면 최신 파일을 받을 수 있습니다. NoBadge는 업데이트를 자동으로 확인하거나 파일을 다운로드하지 않습니다.'})
ko.update({'How is NoBadge?':'NoBadge는 어떠셨나요?', 'Rate or review':'평점 및 리뷰', 'Support':'지원', 'Privacy':'개인정보 보호'})
ko.update({'License': '라이선스', 'Activate NoBadge': 'NoBadge 활성화', 'Enter your purchase license key to use NoBadge.': '구매한 라이선스 키를 입력해 NoBadge를 사용하세요.', 'Cannot reach the license service. Check your connection and try again.': '라이선스 서버에 연결할 수 없습니다. 인터넷 연결 후 다시 시도하세요.', 'This license is not valid. Check the key in your purchase receipt.': '유효하지 않은 라이선스입니다. 구매 영수증의 키를 확인하세요.', 'This key belongs to a different product. Use your NoBadge license key.': '다른 제품의 키입니다. NoBadge 라이선스 키를 사용하세요.', 'This key has no available activations. Deactivate another Mac or contact support.': '활성화 한도에 도달했습니다. 다른 Mac을 비활성화하거나 지원팀에 문의하세요.', 'NoBadge could not save your license in Keychain. Please try again.': '라이선스를 키체인에 저장할 수 없습니다. 다시 시도하세요.', 'Your license is active. It will be checked when you are back online.': '라이선스가 활성화되어 있습니다. 인터넷 연결 시 다시 확인합니다.', 'Connect to the internet to verify your license.': '라이선스를 확인하려면 인터넷에 연결하세요.', 'Your license is no longer active. Check your purchase or contact support.': '라이선스가 더 이상 활성화되어 있지 않습니다. 구매를 확인하거나 지원팀에 문의하세요.', 'License active': '라이선스 활성화됨', 'Your purchase is activated on this Mac.': '이 Mac에서 구매 라이선스가 활성화되었습니다.', 'Deactivate this Mac': '이 Mac 비활성화', 'Paste the license key from your purchase receipt to start using NoBadge.': '구매 영수증의 라이선스 키를 붙여 넣으면 NoBadge를 사용할 수 있습니다.', 'License key': '라이선스 키', 'Activate': '활성화', 'Buy NoBadge — $2.99': 'NoBadge 구매 — $2.99', 'Find my license key': '내 라이선스 키 찾기', 'One purchase, up to 3 Macs. Internet is needed for activation and occasional license checks. After verification, NoBadge can work offline for up to 30 days.': '한 번 구매로 Mac 3대까지 사용할 수 있습니다. 활성화와 주기적 라이선스 확인에는 인터넷이 필요합니다. 확인 후 최대 30일간 오프라인으로 사용할 수 있습니다.', 'Purchase help': '구매 도움말'})
ko.update({'Updates are checked daily. You choose when to download and install. Badge settings are restored before restarting.':'매일 업데이트를 확인합니다. 다운로드와 설치 시점은 직접 선택합니다. 재시작 전에 배지 설정을 복원합니다.'})
ko.update({'Built from source':'소스에서 빌드됨', 'This copy needs no purchase key. Rebuild from the latest source to update it.':'이 버전에는 구매 키가 필요하지 않습니다. 최신 소스로 다시 빌드하면 업데이트할 수 있습니다.', 'Source & updates':'소스 및 업데이트', 'Get the signed app':'서명된 앱 다운로드'})
keys.update(ko)  # Include dynamic enum labels and typed error messages.
missing=keys-set(ko)
if missing:raise SystemExit('Missing Korean translations: '+repr(sorted(missing)))
d={'sourceLanguage':'en','strings':{k:{'localizations':{'en':{'stringUnit':{'state':'translated','value':k}},'ko':{'stringUnit':{'state':'translated','value':ko[k]}}}} for k in sorted(keys)},'version':'1.0'}
(root/'NoBadge/Resources/Localizable.xcstrings').write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
print({'localizedKeys':len(keys),'missing':len(missing)})
