#!/usr/bin/env python3
"""Keep feature registrations safe for append-only union merges, and hold the spec facts no harness can run."""

import plistlib
import re
import sys
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FEATURE = Path("Tinycast/Features/Notchcast/Core/NotchcastFeature.swift")
GROUPS = FEATURE.with_name("NotchcastFeature+SettingsGroup.swift")
DESCRIPTORS = FEATURE.with_name("NotchcastFeature+Descriptor.swift")
MODULES = FEATURE.with_name("NotchcastCore+Modules.swift")
REGISTRANTS = FEATURE.with_name("NotchcastCore+Registrants.swift")
CATALOG = Path("Tinycast/Features/Notchcast/Launcher/NotchcastCommandCatalog+All.swift")
TREE = Path("Tinycast/Features/Notchcast/Settings/Tree/NotchcastSettingsModule+Groups.swift")
SEARCH = Path("Tinycast/Features/Notchcast/Settings/NotchcastSettingsSearch.swift")
# Union-merged lists: each entry's identity, so an edited line a union kept twice is caught.
LISTS = {
    MODULES: r"module: ([\w.]+)",
    SEARCH: r"^(.*?)(?:, keywords: .*)?\),$",
    DESCRIPTORS: r"^\.(\w+):",
    REGISTRANTS: r"^(\w+)\.self,$",
    FEATURE.with_name("NotchcastBackupKeys.swift"): r"^\.(\w+),$",
    CATALOG: r"^([\w.\[\]]+),$",
}
# The feature's code folder at any depth, beside its layers: harnesses glob Model/ and Service/.
FEATURE_FOLDER = r"Tinycast/Features/(?!Notchcast/(?:Core/|[^/]+$))(?:(?!(?:Model|Service|UI|Settings)/)\w+/)+"
DESCRIPTOR_FILE = re.compile(FEATURE_FOLDER + r"(\w+)Descriptor\.swift")
REGISTRATION_FILE = re.compile(FEATURE_FOLDER + r"(\w+)\+Registration\.swift")
# A body, with its brace on any following line; the protocol's bodiless requirement is not one.
REGISTER = re.compile(r"\bstatic\s++func\s++register\s*+\(\s*+\)\s*+"
                      r"(?:async\s++)?(?:throws\s++)?(?:->[^{}\n]*+)?\s*+\{")
DESCRIPTOR_DECLARATION = re.compile(r"extension\s+NotchcastFeature\.Descriptor\b|\bDescriptor\s*(?:\.init\s*)?\("
                                    r"|\bstatic\s+(?:let|var)\s+\w+\s*:\s*(?:NotchcastFeature\.)?Descriptor\b"
                                    r"|->\s*(?:NotchcastFeature\.)?Descriptor\b")
# Switches without a default: a feature without a descriptor needs an arm in each.
EXHAUSTIVE = ("settingsGroup", "title", "subtitle")

# One line per command, "<slug> <owning feature>": a slug is a persisted id (hotkeys, deeplinks), so it never changes.
SLUGS = Path("notchcast/command-slugs.txt")
COMMAND = Path("Tinycast/Features/Notchcast/Launcher/NotchcastCommand.swift")
PLIST = Path("Tinycast/Info.plist")
SETTINGS = TREE.with_name("NotchcastSetting.swift")
BACKUPS = TREE.with_name("NotchcastBackupGroups.swift")
APP_SETTINGS = Path("Tinycast/Features/Settings/AppSettings.swift")
ARCHIVE_FORMATS = Path("Tinycast/Features/Archives/Model/ArchiveFormat.swift")
MACH_LINK = Path("Tinycast/Features/MachLink/Service/MachLinkManager.swift")
LOCAL_NETWORK = "Notchcast connects to your other Mac on the local network."
# Imported types that are not ours to name: Info.plist declares them because macOS ships no declaration.
FOREIGN_TYPES = {"org.bittorrent.torrent", "com.rarlab.rar-archive"}
# What a harness used to assert about one feature, as Swift text; changing a value here is a spec change.
PINS = {
    "archives": {"group": ".archives", "dependencies": "[]", "requiredGrants": "[]", "module": ".filesAndClipboard"},
    "archivesInPlace": {"group": ".archives", "defaultEnabled": "false", "dependencies": "[.archives]",
                        "requiredGrants": "[]", "module": ".filesAndClipboard"},
    "archivesDefaultApp": {"group": ".archives", "defaultEnabled": "false", "dependencies": "[.archives]",
                           "requiredGrants": "[]", "module": ".filesAndClipboard"},
    "captureEditor": {"group": ".captureAndDictation", "defaultEnabled": "false", "wired": "true", "requiredGrants": "[]"},
    "captureTrimmer": {"group": ".captureAndDictation", "defaultEnabled": "true", "wired": "false", "requiredGrants": "[]"},
    "colorPicker": {"group": ".captureAndDictation", "defaultEnabled": "true", "requiredGrants": "[]"},
    "recording": {"group": ".captureAndDictation", "defaultEnabled": "true", "requiredGrants": "[.screenRecording]"},
    "screenshot": {"group": ".captureAndDictation", "defaultEnabled": "true", "needsIsland": "false",
                   "requiredGrants": "[.screenRecording]"},
    "screenText": {"settings": "[.captureScreenTextLineBreaks]"},
    "scrollingCapture": {"group": ".captureAndDictation", "defaultEnabled": "true", "requiredGrants": "[.screenRecording]",
                         "settings": "[]"},
    "dictationHistory": {"defaultEnabled": "true"},
    "globeDictation": {"needsIsland": "false", "requiredGrants": "[.accessibility, .microphone]"},
    "markdownFiles": {"group": ".system", "needsIsland": "false"},
    "plainTextFiles": {"needsIsland": "false"},
    "finderCutPaste": {"group": ".finder", "needsIsland": "false", "requiredGrants": "[.accessibility]"},
    "finderRename": {"group": ".finder", "needsIsland": "false", "requiredGrants": "[.accessibility]"},
    "startupItems": {"wired": "true"},
    "notificationCleanup": {"wired": "true", "requiredGrants": "[.accessibility]"},
    "sudoTouchID": {"wired": "true"},
    "aiFeaturesOff": {"wired": "true"},
    "spotlightOff": {"wired": "true"},
    "privacyChoices": {"wired": "true"},
    "quickLookSpace": {"group": ".launcher", "needsIsland": "false", "requiredGrants": "[]"},
    "backupRunNow": {"group": ".system", "needsIsland": "false", "isSystemFeature": "false"},
    "backupBrowseRestore": {"group": ".system", "needsIsland": "false", "isSystemFeature": "false"},
    "openBotAgents": {"defaultEnabled": "false", "wired": "true", "needsIsland": "false"},
    "musicNowPlaying": {"requiredGrants": "[]"},
    "musicLastPlayer": {"requiredGrants": "[.accessibility]"},
    "musicBlockAppleMusic": {"requiredGrants": "[.accessibility]"},
    "spotifyConnect": {"requiredGrants": "[]"},
    "microphoneMute": {"requiredGrants": "[.accessibility]"},
    "inUseMarks": {"requiredGrants": "[]"},
    "tasks": {"group": ".tasks", "needsIsland": "false", "dependencies": "[]", "requiredGrants": "[]"},
    "tasksSync": {"group": ".tasks", "dependencies": "[.tasks, .machLink]"},
    "katana": {"group": ".system", "isSystemFeature": "true"},
    "treadmillWalk": {"needsIsland": "false"},
    "treadmillHistory": {"needsIsland": "false"},
}
# The same for a class of features: every feature whose first fact has that value keeps the second.
CLASS_PINS = (
    ("isSystemTweak", "true", "needsIsland", "false"),
    ("group", ".torrents", "needsIsland", "false"),
)
# Lines a fork behaviour hangs on, in files no harness compiles: a path, then its needles in order.
HOOKS = (
    ("Tinycast/App/AppCore.swift", "func handleOpenURL(_ url: URL)", "if pendingURLs != nil",
     "if ArchiveModule.shared.open(url) { return }", "if deepLinkCoordinator.handles(url)"),
    ("Tinycast/App/AppCore.swift", "await ArchiveModule.shared.prepareForTermination()"),
    ("Tinycast/App/AppCore.swift", "if settings.extensionsEnabled { extensions.start("),
    ("Tinycast/App/AppDelegate.swift", "AppCore.shared.handleOpenURL(url)"),
    ("Tinycast/App/MenuBarItem.swift",
     'Button("About \\(appName)") { AppCore.shared.settingsCoordinator.showAbout() }'),
    (COMMAND, '"command:nc-" + slug'),
    ("Tinycast/Features/Notchcast/Core/NotchcastCore.swift",
     "ScreenshotModule.shared.openInEditor = { try CaptureEditorCoordinator.shared.openCapture(url: $0, clipboard: $1) }"),
    ("Tinycast/Features/Notchcast/Core/NotchcastCore.swift", "NotchcastHost.current = .live(core: core)",
     "ShelfModule.shared.linkStatus = shelfChannel", "ShelfModule.shared.transport = shelfChannel",
     "RemoteFanModule.linkChannel = macLink.channel", "RemoteScreenModule.linkChannel = macLink.channel",
     "BlockedDialogModule.linkChannel = macLink.channel", "LinkQuickFixModule.shared.state = {",
     "return (macLink.isRunning && macLink.isPaired, reachability)", "registrants.flatMap { $0.register() }"),
    ("Tinycast/Features/Notchcast/Core/NotchcastCore.swift", "BatteryModule.shared.repairAtLaunch()",
     "registrants.flatMap { $0.register() }", "let services = NotchcastServices(core: core, preferences: preferences)",
     "if let tasks = TodoModule.shared { tasksSync.connect(to: tasks) }",
     "MonitorModule.shared.registerRemoteFanRoute(on: macLink.channel)",
     "MonitorModule.shared.fans.restore(preservingPreference: true, silently: true)"),
    ("Tinycast/Features/Archives/ArchiveModule+Registration.swift", "[.init(requires: [.archives], module: shared)]"),
    ("Tinycast/Features/AgentThreads/AgentThreadsModule.swift",
     *2 * ("isEnabled: { NotchcastPreferences.shared.isOn(.agentThreads) }",)),
    ("Tinycast/Features/Notchcast/Core/NotchcastCore.swift",
     "agents.devicesReady = { KatanaModule.shared.configure(index: $0); TreadmillCoordinator.shared.configure(index: $0) }",
     "FleetPanelModule.shared.transport = FleetMachLinkTransport(channel: macLink.channel)",
     "let modules = entries(core: core)"),
    ("Tinycast/Features/Notchcast/Core/NotchcastCore+Modules.swift", "agents.configure(core)",
     "if agents.configured { agentMCPServer.configure(index: agents.index) }"),
    ("Tinycast/Features/AgentBridge/UI/AgentBridgeModule.swift", "try AgentBuiltInActions.register(in: index, core: core)",
     "devicesReady(index)", "configured = true"),
    (APP_SETTINGS, "var extensionsEnabled: Bool { get { false } set { } }"),
    (APP_SETTINGS, "var appleShortcutsEnabled: Bool { get { false } set { } }"),
    (APP_SETTINGS, "var supportRemindersEnabled: Bool { get { false } set { } }"),
    (BACKUPS, 'SettingsRowTitle(.notchcastBackupSettingsFile, "Sync settings file")'),
    (BACKUPS, "get: { core.settings.settingsFileEnabled }"),
    (TREE.with_name("NotchcastGrantsSection.swift"), "grantStatuses.values[grant]"),
    ("Tinycast/Features/Notchcast/Settings/NotchcastGrant+Settings.swift",
     "@concurrent", "func readIsGranted() async -> Bool"),
    ("Tinycast/Features/Notchcast/Settings/Rows/CaptureSettingRows.swift", "Remove line breaks"),
    ("Tinycast/Features/Settings/SettingsSidebarView.swift", "SettingsSection.allCases.filter { !$0.tabs.isEmpty }"),
    ("Tinycast/Features/Settings/SettingsSearchCatalog.swift", "filter { !NotchcastHidden.tabs.contains($0.tab) }"),
    ("Tinycast/Features/Settings/SettingsCoordinator.swift", "showSettings(tab: .about)"),
    ("Tinycast/Features/Settings/SettingsDetailView.swift", "case .about: AboutView()"),
    ("Tinycast/Windows/About/AboutView.swift", "if NotchcastHidden.supportEnabled { support }"),
    ("Tinycast/Windows/About/AboutView.swift", "Released under AGPL-3.0"),
    ("Tinycast/App/AppDelegate.swift", "await NotchcastCore.stopForTermination()"),
    ("Tinycast/Features/AppleShortcuts/UI/AppleShortcutCoordinator.swift", "guard settings.appleShortcutsEnabled else"),
    ("Tinycast/Features/Extensions/Service/ExtensionManager.swift", "guard isEnabled, showsInLauncher else"),
    ("Tinycast/Features/Launcher/Model/CommandCatalog.swift",
     "filter { !NotchcastHidden.commands.contains($0.rawValue) }"),
    ("Tinycast/Features/Launcher/UI/LauncherCoordinator.swift",
     "guard !NotchcastHidden.commands.contains(id.rawValue) else { return }"),
    ("Tinycast/Features/Launcher/UI/LauncherCoordinator.swift", "guard core.settings.extensionsEnabled"),
    ("Tinycast/Features/Launcher/UI/AppActionsMenu.swift", "&& core.settings.extensionsEnabled"),
    ("Tinycast/Features/Launcher/Service/FallbackStore.swift", "NotchcastHidden.fallbacksEnabled &&"),
    ("Tinycast/Features/LauncherKeys/LauncherScreen+AliasSpace.swift", "guard core.settings.extensionsEnabled"),
    ("Tinycast/Features/Support/UI/SupportCoordinator.swift", "guard NotchcastHidden.supportEnabled else { return }"),
    ("Tinycast/Features/Support/Service/SupportReminderStore.swift",
     "guard NotchcastHidden.supportEnabled else { return }"),
    ("Tinycast/Features/Extensions/UI/ExtensionCoordinator.swift",
     "func showStoreInstall(_ install: ExtensionDeepLink.StoreInstall) { guard settings.extensionsEnabled else { return }"),
    ("Tinycast/Features/HotKeys/Service/HotKeyManager.swift",
     "NotchcastHidden.commands.contains(id.rawValue) { return nil }"),
    ("Tinycast/Features/HotKeys/Service/HotKeyManager.swift", "var boundExtensionCommandEntryIDs: [String] { []"),
    ("Tinycast/Palette/RootPaletteView.swift", "guard settings.extensionsEnabled, vm.mode"),
)
# Text that must stay out: a path or glob, then the needle.
ABSENT = (
    ("Tinycast/App/MenuBarItem.swift", "showSupport"),
    (BACKUPS, "settingsFileEnabled ="),
    (TREE.with_name("*.swift"), ".isGranted"),
)
# A module entry in any file that states one: its requires list, then the module it runs.
ENTRY = re.compile(r"\.init\(requires: \[(.*?)\](?:, requiresAny: .*?)?, module: (.+?)\)(?=[,\]]|$)", re.M)
MODULE_TYPE = re.compile(r"\b(?:class|extension) (\w+)\s*:[^{\n]*\bNotchcastModule\b")


def mask_literals(source):
    pattern = r'//[^\n]*|/\*.*?\*/|""".*?"""|"(?:\\.|[^"\\])*"'
    def mask(match):
        blank = re.sub(r"[^\n]", " ", match[0])
        return "0" + blank[1:] if match[0].startswith('"') else blank
    return re.sub(pattern, mask, source, flags=re.S)


def case_errors(code):
    tokens = [(match[0], code.count("\n", 0, match.start()) + 1)
              for match in re.finditer(r"[A-Za-z_]\w*|[^\s]", code)]
    errors = []
    scopes = []
    pending = None
    case_lines = set()
    for index, (token, line) in enumerate(tokens):
        if token in ("enum", "switch"):
            pending = {"kind": token, "name": tokens[index + 1][0], "cases": {}}
        elif token == "{":
            scopes.append(pending or {"kind": "block"})
            pending = None
        elif token == "}":
            if scopes:
                scopes.pop()
        elif token == "case":
            if line in case_lines:
                errors.append((line, "put each case declaration on its own line"))
            case_lines.add(line)
            if not scopes or scopes[-1]["kind"] not in ("enum", "switch"):
                continue
            scope = scopes[-1]
            end = index + 1
            names = []
            if scope["kind"] == "switch":
                while end < len(tokens) and tokens[end][0] not in (":", "{", "}", "case"):
                    end += 1
                pattern = tokens[index + 1:end]
                names = [(pattern[i + 1][0], pattern[i + 1][1])
                         for i in range(len(pattern) - 1) if pattern[i][0] == "."]
                if any(value == "," for value, _ in pattern):
                    errors.append((line, "multi-case arm; use one arm per feature"))
                if (end + 1 >= len(tokens) or tokens[end][0] != ":"
                        or tokens[end][1] != line or tokens[end + 1][1] != line):
                    errors.append((line, "keep each feature arm on one line"))
            else:
                while end < len(tokens) and re.fullmatch(r"[A-Za-z_]\w*", tokens[end][0]):
                    names.append(tokens[end])
                    end += 1
                    if end >= len(tokens) or tokens[end][0] != ",":
                        break
                    end += 1
                if len(names) > 1:
                    errors.append((line, "declare only one enum case per line"))
                if names and names[0][1] != line:
                    errors.append((line, "keep each enum case on one line"))
            for name, name_line in names:
                if name in scope["cases"]:
                    label = f".{name} in switch" if scope["kind"] == "switch" else f"{name} in {scope['name']}"
                    first = scope["cases"][name]
                    errors.append((name_line, f"repeated case {label} (first declared on line {first})"))
                else:
                    scope["cases"][name] = name_line
    return errors


PREFERENCES = Path("Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift")


def preference_errors(source):
    """Stored settings and init assignments: one line each, each name once."""
    errors = []
    lines = source.split("\n")
    code = mask_literals(source).split("\n")
    if sum(1 for line in code if re.match(r"\s*final class NotchcastPreferences\b", line)) != 1:
        errors.append((1, "expected one NotchcastPreferences class"))
    depth = 0
    in_class = in_init = False
    names = {}
    assigned = {}
    for number, (line, masked) in enumerate(zip(lines, code), 1):
        stripped = masked.strip()
        balance = sum(masked.count(c) for c in "{([") - sum(masked.count(c) for c in "})]")
        if depth == 0 and re.match(r"(?:@\w+\s+)*final class NotchcastPreferences\b", stripped):
            in_class = True
        elif in_class and depth == 1 and stripped.startswith("init("):
            in_init = True
        elif in_class and depth == 1 and re.match(r"(?:@\w+\s+)*(?:private\s+|fileprivate\s+)?(?:let|var)\s", stripped):
            if balance:
                errors.append((number, "keep each setting on one line"))
            name = re.search(r"\b(?:let|var)\s+(\w+)", stripped)[1]
            if name in names:
                errors.append((number, f"repeated setting {name} (first on line {names[name]})"))
            names.setdefault(name, number)
        elif in_init and depth == 2 and stripped and stripped != "}":
            if balance:
                errors.append((number, "keep each init statement on one line"))
            target = re.match(r"(?:self\.)?(\w+)\s*=[^=]", stripped)
            if target:
                if target[1] in assigned:
                    errors.append((number, f"repeated assignment {target[1]} (first on line {assigned[target[1]]})"))
                assigned.setdefault(target[1], number)
        depth += balance - (masked.count("(") + masked.count("[") - masked.count(")") - masked.count("]"))
        if depth <= 1:
            in_init = False
        if depth == 0:
            in_class = False
    return errors


def list_errors(source, identity):
    errors = []
    code = mask_literals(source).split("\n")
    names = {}
    entries = {}
    depth = 0
    for number, (line, masked) in enumerate(zip(source.split("\n"), code), 1):
        declared = re.match(r"\s*(?:private )?static (?:let|var) (\w+)", masked)
        if declared:
            name = declared[1]
            if name in names:
                errors.append((number, f"repeated static {name} (first declared on line {names[name]})"))
            names.setdefault(name, number)
        balance = sum(masked.count(c) for c in "([") - sum(masked.count(c) for c in ")]")
        if depth and masked.strip() != "]":
            if balance or not masked.rstrip().endswith(","):
                errors.append((number, "keep each list entry on one line, ending with a comma"))
            else:
                key = re.search(identity, line.strip())
                key = key[1] if key else line.strip()
                if key in entries:
                    errors.append((number, f"repeated entry {key} (first on line {entries[key]})"))
                entries.setdefault(key, number)
        if masked.rstrip().endswith("[") and balance == 1:
            depth = 1
        elif depth and masked.strip() == "]":
            depth = 0
    return errors


def upstream_folders(root):
    """Feature folders upstream ships at the merge base; none without an upstream ref."""
    def git(*args):
        result = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)
        return result.stdout.strip() if result.returncode == 0 else ""
    base = git("merge-base", "HEAD", "refs/remotes/upstream/main")
    if not base:
        print("note: no upstream/main ref; descriptors in upstream folders are not checked "
              "(git fetch upstream main)", file=sys.stderr)
    return {Path(path).name for path in git("ls-tree", "--name-only", base, "Tinycast/Features/").splitlines()} if base else set()


def descriptor_errors(root):
    """A described feature has no switch arm and one listed descriptor file in its own fork folder."""
    errors = []
    upstream = upstream_folders(root)
    described = {}
    for number, line in enumerate(mask_literals((root / DESCRIPTORS).read_text()).split("\n"), 1):
        entry = re.fullmatch(r"\s*\.(\w+): \.(\w+),", line)
        if entry:
            described.setdefault(entry[1], number)
            if entry[1] != entry[2]:
                errors.append((DESCRIPTORS, number, f".{entry[1]} must map to its own descriptor .{entry[1]}"))
    code = mask_literals((root / FEATURE).read_text())
    for number, line in enumerate(code.split("\n"), 1):
        arm = re.match(r"\s*case\s+([^:]*):", line)
        for name in re.findall(r"\.(\w+)", arm[1]) if arm else []:
            if name in described:
                errors.append((FEATURE, number, f".{name} has a descriptor; change it there, not in a switch arm"))
    enum = code.split("enum NotchcastFeature", 1)[-1].split("\n    var ", 1)[0]
    cases = re.findall(r"^    case (\w+)$", enum, re.M)
    sections = re.split(r"^    var (\w+)\b", code, flags=re.M)
    for member, body in zip(sections[1::2], sections[2::2]):
        if member in EXHAUSTIVE:
            number = code.count("\n", 0, code.index(f"    var {member}")) + 1
            arms = set(re.findall(r"^\s*case \.(\w+)", body, re.M))
            errors.extend((FEATURE, number, f".{name} needs a descriptor or a {member} arm")
                          for name in cases if name not in arms and name not in described)
    for path in sorted((root / "Tinycast/Features").rglob("*.swift")):
        relative = path.relative_to(root)
        source = path.read_text()
        if "Descriptor" not in source:
            continue
        code = mask_literals(source)
        declaration = DESCRIPTOR_DECLARATION.search(code)
        place = DESCRIPTOR_FILE.fullmatch(relative.as_posix())
        if declaration and not place:
            errors.append((relative, code.count("\n", 0, declaration.start()) + 1,
                           "declare a descriptor in Tinycast/Features/<its folder>/<Name>Descriptor.swift"))
        elif place:
            feature = place[1][:1].lower() + place[1][1:]
            names = re.findall(r"\bstatic let (\w+)\b", code)
            if not declaration or [name[:1].upper() + name[1:] for name in names] != [place[1]]:
                errors.append((relative, 1, f"declare exactly one descriptor, .{feature}"))
            elif feature not in described:
                errors.append((relative, 1, f"list .{feature}: .{feature}, in {DESCRIPTORS}"))
            if relative.parts[2] in upstream:
                errors.append((relative, 1, f"upstream ships Features/{relative.parts[2]}/; "
                                            "describe the feature from a fork folder of its own"))
    return errors


def registration_errors(root):
    """A registrant registers from <Type>+Registration.swift in its own fork folder, and keeps nothing in the hub."""
    errors = []
    upstream = upstream_folders(root)
    registrants = mask_literals((root / REGISTRANTS).read_text())
    listed = re.findall(r"^\s*(\w+)\.self,$", registrants, re.M)
    errors.extend((REGISTRANTS, number, "list one registrant per line")
                  for number, line in enumerate(registrants.split("\n"), 1) if len(re.findall(r"\.self\b", line)) > 1)
    for path in sorted((root / "Tinycast/Features").rglob("*.swift")):
        relative = path.relative_to(root)
        source = path.read_text()
        if "register" not in source:
            continue
        code = mask_literals(source)
        implementation = REGISTER.search(code)
        if not implementation:
            continue
        number = code.count("\n", 0, implementation.start()) + 1
        place = REGISTRATION_FILE.fullmatch(relative.as_posix())
        if not place:
            errors.append((relative, number, "implement register() in "
                                             "Tinycast/Features/<its folder>/<Type>+Registration.swift"))
        elif relative.parts[2] in upstream:
            errors.append((relative, number, f"upstream ships Features/{relative.parts[2]}/; "
                                             "register from a fork folder of its own"))
        elif place[1] not in listed:
            errors.append((relative, number, f"list {place[1]}.self, in {REGISTRANTS}"))
    hub = mask_literals((root / MODULES).read_text()).split("\n")
    for name in listed:
        held = re.compile(rf"\bstatic\s+(?:[\w()]+\s+)*(?:let|var)\s+\w+\s*[:=]\s*{name}\b|\bmodule:\s*{name}\b")
        errors.extend((MODULES, number, f"{name} registers itself; drop its static and entry here")
                      for number, line in enumerate(hub, 1) if held.search(line))
    return errors


def call_arguments(source, start):
    """The labelled arguments of the call whose `(` ends at start, as {label: value}; a value on several lines reads as one."""
    code = mask_literals(source)
    stated = {}
    depth, begin = 1, start
    for index in range(start, len(code)):
        depth += (code[index] in "([{") - (code[index] in ")]}")
        if depth == 0 or (depth == 1 and code[index] == ","):
            colon = code.find(":", begin, index)
            label, value = (code[begin:colon], source[colon + 1:index]) if colon >= 0 else (code[begin:index], "")
            stated[label.strip()] = re.sub(r"(?<=[\[(]) | (?=[\])])", "", " ".join(value.split()))
            begin = index + 1
        if depth == 0:
            break
    return stated


def feature_facts(root):
    """Each feature's facts as Swift text, from its descriptor or its switch arms, with its place in the settings tree."""
    errors = []
    source = (root / FEATURE).read_text()
    start = source.index("enum NotchcastFeature")
    facts = {case[1]: {"at": (FEATURE, source.count("\n", 0, start + case.start()) + 1)}
             for case in re.finditer(r"^    case (\w+)$", source[start:source.index("\n    var ", start)], re.M)}
    sections = re.split(r"^    var (\w+)\b", source, flags=re.M)
    for member, body in zip(sections[1::2], sections[2::2]):
        arms = dict(re.findall(r"^\s*case \.(\w+): (.+)$", body, re.M))
        default = re.search(r"^\s*default: (?!preconditionFailure)(.+)$|descriptor\?\.\w+ \?\? (.+)$", body, re.M)
        for name, known in facts.items():
            value = arms.get(name) or (default and (default[1] or default[2]))
            if value:
                known["group" if member == "settingsGroup" else member] = value
    fields = set(re.findall(r"^        let (\w+):", (root / DESCRIPTORS).read_text(), re.M))
    if not fields:
        errors.append((DESCRIPTORS, 1, "found no Descriptor field; declare each as `let <name>:` on its own line"))
    for path in sorted((root / "Tinycast/Features").rglob("*Descriptor.swift")):
        relative = path.relative_to(root)
        if not DESCRIPTOR_FILE.fullmatch(relative.as_posix()):
            continue
        text = path.read_text()
        declared = re.search(r"^\s*static let (\w+) = Self\($", text, re.M)
        if not declared or declared[1] not in facts:
            errors.append((relative, 1, "open the descriptor with `static let <feature> = Self(` at the end of a line"))
            continue
        stated = call_arguments(text, declared.end())
        number = text.count("\n", 0, declared.start()) + 1
        if fields - set(stated):
            errors.append((relative, number, f"state every descriptor field; found no {', '.join(sorted(fields - set(stated)))}"))
        facts[declared[1]].update(stated, at=(relative, number))
    unwired = re.search(r"\bstatic let unwired\b[^\[\n]*\[(.*?)\]", source, re.S)
    for name, known in facts.items():
        for fact, value in known.items():
            code = mask_literals(value) if fact != "at" else ""
            if any(code.count(opening) != code.count(closing) for opening, closing in ("()", "[]", "{}")):
                errors.append((*known["at"], f".{name} {fact} reads `{value}`; state the whole value on one line"))
        if "dependencies" in known:
            known["needsIsland"] = str("island" in re.findall(r"\.(\w+)", known["dependencies"])).lower()
        if unwired:
            known["wired"] = str(name not in re.findall(r"\.(\w+)", unwired[1])).lower()
    module = None
    for number, line in enumerate((root / TREE).read_text().split("\n"), 1):
        opened = re.match(r"\s*case \.(\w+): \[", line)
        module = f".{opened[1]}" if opened else module
        item = re.search(r"\.feature\(\.(\w+), settings: (\[.*?\])\)", line)
        if item and "module" in facts.get(item[1], {}):
            errors.append((TREE, number, f".{item[1]} is already in the settings tree; place a feature once"))
        elif item and module and item[1] in facts:
            facts[item[1]].update(module=module, settings=item[2])
    errors.extend((*known["at"], f".{name} has no place in the settings tree; add it to a group in {TREE}")
                  for name, known in facts.items() if "module" not in known)
    return facts, errors


def feature_errors(root):
    """The pinned facts hold, and every feature shows a localized title and subtitle."""
    facts, errors = feature_facts(root)
    for name, pins in PINS.items():
        known = facts.get(name, {"at": (FEATURE, 1)})
        errors.extend((*known["at"], f".{name} {fact} is {known.get(fact)}; the spec pins {value} (PINS in {Path(__file__).name})")
                      for fact, value in pins.items() if known.get(fact) != value)
    for when, equals, fact, value in CLASS_PINS:
        members = [(name, known) for name, known in facts.items() if known.get(when) == equals]
        if not members:
            errors.append((FEATURE, 1, f"no feature's {when} is {equals}; the class pin on {fact} holds nothing (CLASS_PINS)"))
        errors.extend((*known["at"], f".{name} {fact} is {known.get(fact)}; a feature whose {when} is {equals} keeps {value}")
                      for name, known in members if known.get(fact) != value)
    errors.extend((*known["at"], f".{name} needs backedUp: true or false, whether a settings backup carries its switch")
                  for name, known in facts.items() if known.get("backedUp") not in ("true", "false"))
    errors.extend((*known["at"], f".{name} needs a localized, non-empty {text}")
                  for name, known in facts.items() for text in ("title", "subtitle")
                  if not re.match(r'String\(localized: "[^"]', known.get(text, "")))
    return errors


def command_slugs(expression, source):
    """A literal slug, or the literals a same-file factory or assignment feeds the slug; else the expression itself."""
    if expression.startswith('"'):
        return [expression[1:-1]]
    name = re.escape(expression)
    factory = re.search(rf"\bfunc (\w+)\(\s*_ {name}:", source)
    return re.findall(rf'\b{factory[1]}\(\s*"([^"]+)"' if factory else rf'\b{name} = "([^"]+)"', source) or [expression]


def array_elements(code, opening):
    """The top-level elements of the array literal whose `[` is at code[opening]."""
    elements, item, depth = [], "", 0
    for character in code[opening + 1:]:
        if character in "([{":
            depth += 1
        elif character in ")]}":
            if depth == 0:
                break
            depth -= 1
        if character == "," and depth == 0:
            elements.append(item.strip())
            item = ""
        else:
            item += character
    elements.append(item.strip())
    return [element for element in elements if element]


def command_errors(root):
    """A command names its owner and keeps its slug; a command a type holds as a static is listed in the catalog."""
    errors = []
    declared = {}
    text = (root / CATALOG).read_text()
    catalog = set(re.findall(r"^\s+([\w.]+)(?:\[\d+\])?,$", text, re.M))
    indexed = {}
    for number, line in enumerate(text.split("\n"), 1):
        match = re.fullmatch(r"\s+([\w.]+)\[(\d+)\],", line)
        if match:
            indexed.setdefault((match[1], int(match[2])), number)
    arrays = {}
    for path in sorted((root / "Tinycast/Features").rglob("*.swift")):
        source = path.read_text()
        if "NotchcastCommand" not in source:
            continue
        relative = path.relative_to(root)
        code = mask_literals(source)
        for call in re.finditer(r"\bNotchcastCommand\(", code):
            depth, end = 1, call.end()
            while depth and end < len(code):
                depth += (code[end] == "(") - (code[end] == ")")
                end += 1
            number = code.count("\n", 0, call.start()) + 1
            slug = re.match(r'\s*slug:\s*("(?:\\.|[^"\\])*"|[\w.]+)', source[call.end():end])
            owner = re.search(r"\bfeature:\s*\.?([\w.]+)", code[call.end():end])
            if not slug or not owner:
                errors.append((relative, number, "a command states slug: first and names its owner, feature: .<feature>"))
                continue
            for name in command_slugs(slug[1], source):
                if name in declared:
                    errors.append((relative, number, f"repeated command slug {name} (first at {declared[name][0]}:{declared[name][1]})"))
                declared.setdefault(name, (relative, number, owner[1]))
        factories = set(re.findall(r"\bfunc (\w+)\([^{]*?\)\s*->\s*\[?NotchcastCommand\b", code)) | {"NotchcastCommand"}
        types = [(match.start(), match[1]) for match in re.finditer(
            r"^(?:@\w+\s+)*(?:final\s+)?(?:enum|extension|struct|class)\s+([\w.]+)", code, re.M)]
        for static in re.finditer(r"^(?![^\n=]*\bprivate\s)[^\n=]*\bstatic\s+(?:let|var)\s+(\w+)\s*(?::\s*NotchcastCommand\s*)?=\s*(\w+)\b", code, re.M):
            holders = [name for start, name in types if start < static.start()]
            if holders and static[2] in factories and f"{holders[-1]}.{static[1]}" not in catalog:
                errors.append((relative, code.count("\n", 0, static.start()) + 1, f"list {holders[-1]}.{static[1]}, in {CATALOG}"))
        for array in re.finditer(r"^(?![^\n=]*\bprivate\s)[^\n=]*\bstatic\s+(?:let|var)\s+(\w+)\s*:\s*\[NotchcastCommand\]\s*=\s*\[", code, re.M):
            holders = [name for start, name in types if start < array.start()]
            elements = array_elements(code, array.end() - 1)
            # Bare references add no command; each named static is checked where it is declared.
            if not holders or all(re.fullmatch(r"[\w.]+(?:\[\d+\])?", element) for element in elements):
                continue
            name = f"{holders[-1]}.{array[1]}"
            arrays[name] = len(elements)
            number = code.count("\n", 0, array.start()) + 1
            errors.extend((relative, number, f"list {name}[{index}], in {CATALOG}")
                          for index in range(len(elements)) if (name, index) not in indexed)
    errors.extend((CATALOG, number, f"{name}[{index}] is past the end of its {arrays[name]} elements")
                  for (name, index), number in indexed.items() if name in arrays and index >= arrays[name])
    listed = {entry: number for number, entry in enumerate((root / SLUGS).read_text().split("\n"), 1) if entry}
    lines = {f"{name} {owner}": (path, number) for name, (path, number, owner) in declared.items()}
    errors.extend((path, number, f"add the line `{entry}` to {SLUGS}")
                  for entry, (path, number) in lines.items() if entry not in listed)
    errors.extend((SLUGS, number, f"`{entry}` matches no command; a slug and its owner are persisted,"
                                  " so restore them, or drop this line with the command")
                  for entry, number in listed.items() if entry not in lines)
    return errors


def module_errors(root):
    """In any file a module runs in one entry, which requires the feature it is named after; a hub module runs in exactly one."""
    errors = []
    facts, _ = feature_facts(root)
    hub = mask_literals((root / MODULES).read_text())
    assigned = re.findall(r"^\s*(?:self\.)?(\w+) = (\w+)$", hub, re.M)
    holders = {local: name for name, local in assigned}
    types, ran = set(), {}
    for path in sorted((root / "Tinycast/Features").rglob("*.swift")):
        source = path.read_text()
        types.update(MODULE_TYPE.findall(source))
        if ".init(requires:" not in source:
            continue
        relative, code = path.relative_to(root), mask_literals(source)
        for entry in ENTRY.finditer(code):
            number, owner = code.count("\n", 0, entry.start()) + 1, holders.get(entry[2], entry[2])
            if entry[2] in ran.setdefault(relative, []):
                errors.append((relative, number, f"run {entry[2]} in one entry"))
            ran[relative].append(entry[2])
            if owner in facts and owner not in re.findall(r"\.(\w+)", entry[1]):
                errors.append((relative, number, f"the entry that runs {entry[2]} requires .{owner}"))
    entries = ran.get(MODULES, [])
    for static in re.finditer(r"\bstatic (?:private\(set\) )?var (\w+): (\w+Module)\?$", hub, re.M):
        locals_ = [local for name, local in assigned if name == static[1]]
        if len(locals_) != 1 or hub.count(f"{static[2]}(") > 1 or entries.count(locals_[0]) != 1:
            errors.append((MODULES, hub.count("\n", 0, static.start()) + 1,
                           f"build {static[2]} once, assign it to {static[1]} once and run that one in one entry"))
    statics = [static for static in re.finditer(r"\bstatic let (\w+) = (\w+)\b", hub)
               if static[2].endswith("Module") or static[2] in types]
    if not statics:
        errors.append((MODULES, 1, "found no module static; declare each as `static let <name> = <Type>(`"))
    errors.extend((MODULES, hub.count("\n", 0, static.start()) + 1, f"run {static[1]} in exactly one entry of this file")
                  for static in statics if sum(bool(re.match(rf"{static[1]}\b", module)) for module in entries) != 1)
    return errors


def source_errors(root):
    """Hook lines stay where the fork needs them, and every setting and backup anchor has its view."""
    errors = []
    for path, *needles in HOOKS:
        text, position = " ".join((root / path).read_text().split()), 0
        for needle in needles:
            found = text.find(needle, position)
            if found < 0:
                errors.append((path, 1, f"hook missing or out of order: {needle}"))
                break
            position = found + len(needle)
    for pattern, needle in ABSENT:
        paths = sorted(root.glob(str(pattern)))
        if not paths:
            errors.append((pattern, 1, f"found no file to keep {needle} out of (ABSENT)"))
        for path in paths:
            text = path.read_text()
            if needle in text:
                errors.append((path.relative_to(root), text.count("\n", 0, text.index(needle)) + 1, f"keep {needle} out of this file"))
    rows = "\n".join(path.read_text() for path in sorted((root / TREE.parent).glob("NotchcastSettingRows+*.swift")))
    settings = (root / SETTINGS).read_text()
    errors.extend((SETTINGS, line, message) for line, message in case_errors(mask_literals(settings)))
    cases = list(re.finditer(r"^    case (\w+)\b", settings, re.M))
    if not cases:
        errors.append((SETTINGS, 1, "found no setting; declare each as `case <name>` on its own line"))
    for case in cases:
        arms = rows.split(f"case .{case[1]}:")
        arm = re.split(r"case |default:", arms[1])[0] if len(arms) == 2 else ""
        if "SettingRow(" not in arm or "EmptyView" in arm:
            errors.append((SETTINGS, settings.count("\n", 0, case.start()) + 1,
                           f".{case[1]} needs exactly one arm that shows a row, in NotchcastSettingRows+*.swift"))
    search = (root / SEARCH).read_text()
    backups = (root / BACKUPS).read_text()
    anchors = list(re.finditer(r"\bstatic let (notchcastBackup\w+) = ", search))
    if not anchors:
        errors.append((SEARCH, 1, "found no backup anchor; declare each as `static let notchcastBackup<Name> = `"))
    errors.extend((SEARCH, search.count("\n", 0, anchor.start()) + 1, f"give .{anchor[1]} a SettingsSectionHeader in {BACKUPS}")
                  for anchor in anchors if f"SettingsSectionHeader(.{anchor[1]})" not in backups)
    return errors


def plist_errors(root):
    """Info.plist declares the archive types the code opens and the one Bonjour service it browses."""
    errors = []
    with (root / PLIST).open("rb") as file:
        plist = plistlib.load(file)
    formats = re.search(r"static let typeIdentifiers = \[(.*?)\]", (root / ARCHIVE_FORMATS).read_text(), re.S)
    archives = [kind for kind in plist.get("CFBundleDocumentTypes", []) if kind.get("CFBundleTypeName") == "Archives"]
    if (len(archives) != 1 or archives[0].get("LSHandlerRank") != "Alternate" or not formats
            or set(archives[0].get("LSItemContentTypes", [])) != set(re.findall(r'"([^"]+)"', formats[1]))):
        errors.append((PLIST, 1, "declare one Archives document type, ranked Alternate, listing ArchiveFormat.typeIdentifiers"))
    extensions = []
    for imported in plist.get("UTImportedTypeDeclarations", []):
        identifier = imported.get("UTTypeIdentifier", "")
        if not identifier.startswith("app.notchcast.") and identifier not in FOREIGN_TYPES:
            errors.append((PLIST, 1, f"imported type {identifier} is neither app.notchcast.* nor in FOREIGN_TYPES"))
        tags = imported.get("UTTypeTagSpecification", {}).get("public.filename-extension", [])
        extensions += tags if isinstance(tags, list) else []
    if "001" not in extensions:
        errors.append((PLIST, 1, "an imported type carries the split-archive extension 001"))
    service = re.search(r'static let serviceType = "([^"]+)"', (root / MACH_LINK).read_text())
    if not service or plist.get("NSBonjourServices") != [service[1]]:
        errors.append((PLIST, 1, "NSBonjourServices lists exactly MachLinkManager.serviceType"))
    if plist.get("NSLocalNetworkUsageDescription") != LOCAL_NETWORK:
        errors.append((PLIST, 1, f"NSLocalNetworkUsageDescription reads: {LOCAL_NETWORK}"))
    return errors


def fact_errors(root):
    """The spec facts harnesses used to restate from source text; a file a rule cannot read fails that rule."""
    errors = []
    for rule in (feature_errors, command_errors, module_errors, source_errors, plist_errors):
        try:
            errors.extend(f"{path}:{line}: {message}" for path, line, message in rule(root))
        except (OSError, ValueError) as error:
            errors.append(f"{rule.__name__}: {error}")
    return errors


def check(root):
    errors = []
    declarations = {"NotchcastFeature": [], "SettingsGroup": []}
    for path in (FEATURE, GROUPS):
        try:
            source = (root / path).read_text()
        except OSError as error:
            errors.append(f"{path}:1: {error}")
            continue
        code = mask_literals(source)
        for name in declarations:
            for match in re.finditer(rf"\benum\s+{name}\b", code):
                declarations[name].append((path, code.count("\n", 0, match.start()) + 1))
        errors.extend(f"{path}:{line}: {message}" for line, message in case_errors(code))
    for path, identity in LISTS.items():
        try:
            source = (root / path).read_text()
        except OSError as error:
            errors.append(f"{path}:1: {error}")
            continue
        errors.extend(f"{path}:{line}: {message}" for line, message in list_errors(source, identity))
    try:
        source = (root / PREFERENCES).read_text()
    except OSError as error:
        errors.append(f"{PREFERENCES}:1: {error}")
    else:
        errors.extend(f"{PREFERENCES}:{line}: {message}" for line, message in preference_errors(source))
    try:
        errors.extend(f"{path}:{line}: {message}" for path, line, message in descriptor_errors(root))
    except OSError as error:
        errors.append(f"{DESCRIPTORS}:1: {error}")
    try:
        errors.extend(f"{path}:{line}: {message}" for path, line, message in registration_errors(root))
    except OSError as error:
        errors.append(f"{REGISTRANTS}:1: {error}")
    for name, locations in declarations.items():
        if len(locations) != 1:
            path, number = locations[-1] if locations else (FEATURE, 1)
            errors.append(f"{path}:{number}: expected one {name} enum, found {len(locations)}")
    return errors


def main():
    if len(sys.argv) > 2:
        print(f"usage: {sys.argv[0]} [repository-root]", file=sys.stderr)
        return 2
    root = Path(sys.argv[1]) if len(sys.argv) == 2 else ROOT
    errors = check(root) + fact_errors(root)
    if subprocess.run([sys.executable, str(ROOT / "notchcast/check-switch-paths.py"), str(root)]).returncode:
        errors.append("switch user paths failed")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("PASS: feature cases, switch arms, modules, search entries, commands and settings use one line each, with no repeats;"
          " described features keep no arm and their descriptor in their own folder;"
          " registrants register from their own folder and leave the hub;"
          " pinned facts, command slugs and owners, module entries, setting rows, hooks and Info.plist hold")
    return 0


if __name__ == "__main__":
    sys.exit(main())
