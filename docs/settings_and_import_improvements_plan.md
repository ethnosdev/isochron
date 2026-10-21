# Settings & Media Import Improvements Plan

This plan outlines the updates to project settings, media import flows, fragment ID generation, and language alignment information based on our interactive design review.

---

## 1. Scope & Objectives

| Item | Problem / Requirement | Solution |
| :--- | :--- | :--- |
| **1. Collaborator Name** | Unused across the app; unnecessary clutter in settings. | Completely remove Collaborator Name from `ProjectSettingsView` and `UserSettingsService`. |
| **2. Media Copy During Import** | "Copy imported media into project folder" is only configured in settings after import, and toggling it does not affect existing files. | 1. Add "Copy media into project folder" directly into the import flows (`TrackPairingWizard` and `NewProjectDialog`).<br>2. When toggled ON in Project Settings, prompt the user with an option to **consolidate** existing external media files into the project. |
| **3. Custom Prefix Removal** | Custom Prefix fails to update preview for USFM codes (e.g. `MRK`) and is confusing to configure. | Remove Custom Prefix entirely from the UI, project model, and ID generation logic. The ID preview will reflect the selected ID style and track name directly. |
| **4. Language Code Guidance** | Users do not know when the 3-letter language code is necessary or which languages have custom alignment/romanization rules. | Add an info button next to the Language Code field that opens a sheet explaining when the code is needed, listing the languages with custom `uroman` rules, and linking to the official documentation. |

---

## 2. Detailed Technical Plan

### Area 1: Remove Unused Collaborator Name

1. **User Settings Service** (`isochron_flutter/lib/services/user_settings_service.dart`):
   - Remove `static const String _keyCollaboratorName = 'collaborator_name';`.
   - Remove `collaboratorName` getter and `setCollaboratorName(String name)` setter.

2. **Project Settings View** (`isochron_flutter/lib/ui/workspace/views/project_settings_view.dart`):
   - Remove `_collaboratorNameController`.
   - Remove the Collaborator Name input row under "App Preferences".

---

### Area 2: Media Copy Integration & Consolidation

1. **New Project Dialog** (`isochron_flutter/lib/ui/workspace/components/new_project_dialog.dart`):
   - Add a checkbox: `Copy imported media into project folder` (defaults to `false`, or respects global preference).
   - Pass `copyMediaIntoProject` in `NewProjectResult`.
   - In `WorkspaceManager.createProject`, initialize `Project.copyMediaIntoProject` from this result.

2. **Track Pairing Wizard** (`isochron_flutter/lib/ui/workspace/components/track_pairing_wizard.dart`):
   - Add a checkbox at the footer of the wizard: `Copy media into project folder (for project portability)`.
   - Pre-fill with `project.copyMediaIntoProject`.
   - Include `bool copyMediaIntoProject` in `WizardResult`.
   - When importing paired rows, update `project.copyMediaIntoProject` and perform copy if selected.

3. **Media Consolidation Logic** (`isochron_flutter/lib/ui/workspace/workspace_manager.dart`):
   - Implement `Future<int> consolidateExternalMedia()`:
     - Iterates over all collections and tracks in the project.
     - For tracks with absolute external paths (or files outside the project directory), copies them into `collections/<collection>/audio/` and `collections/<collection>/text/`.
     - Updates the track's `audioPath` and `textPath` to relative basenames and saves the collection metadata.
     - Returns the count of consolidated files.

4. **Project Settings Prompt** (`isochron_flutter/lib/ui/workspace/views/project_settings_view.dart`):
   - When the user checks "Copy imported media into project folder" (turning it from `false` to `true`):
     - Check if any current tracks have external file paths.
     - If so, display a modal dialog:
       > **Consolidate Project Media?**
       >
       > You have existing tracks referencing files outside the project folder. Would you like to copy them into the project folder now to make the project fully portable?
       >
       > `[Copy Existing Files]` `[Only Apply to Future Imports]`
     - If `Copy Existing Files` is selected, invoke `consolidateExternalMedia()` and show a success notification.

---

### Area 3: Remove Custom Prefix

1. **Project Settings View** (`isochron_flutter/lib/ui/workspace/views/project_settings_view.dart`):
   - Remove `_prefixController`, `_prefix`, and the "Book Number / Custom Prefix" input section.
   - Retain the **ID Style** dropdown (`USFM 8-Digit` vs `Track Name + Number`).
   - Simplify the **Live Preview Box** to call:
     ```dart
     IdGenerator.generatePreview(
       style: _idStyle,
       trackName: sampleTrackName,
     );
     ```

2. **ID Generator** (`isochron_flutter/lib/utils/id_generator.dart`):
   - Remove `customPrefix` parameter from `generateId` and `generatePreview`.
   - Remove unused prefix parsing branches.

3. **Project Model** (`isochron_flutter/lib/ui/models/project_model.dart`):
   - Mark `defaultIdPrefix` as deprecated or remove field while maintaining backwards compatibility when reading older project files (ignore key if present).

4. **Workspace Manager & App Manager**:
   - Remove `customPrefix: project!.defaultIdPrefix` references in:
     - `isochron_flutter/lib/ui/app_manager.dart`
     - `isochron_flutter/lib/ui/workspace/workspace_manager.dart`

---

### Area 4: Language Code Information Sheet

1. **Info Button in Project Settings** (`isochron_flutter/lib/ui/workspace/views/project_settings_view.dart`):
   - Next to `"Language Code (ISO 639-3):"`, add an info icon button (`CupertinoIcons.info_circle`).
   - Clicking the button opens `LanguageCodeInfoSheet`.

2. **Language Code Info Sheet** (`isochron_flutter/lib/ui/workspace/components/language_code_info_dialog.dart`):
   - Explain how MMS Alignment works with `uroman`:
     - Text written in the Latin alphabet (English, Spanish, French, Indonesian, Swahili, etc.) or simple scripts works automatically without a language code.
     - The language code is only required when `uroman` has language-specific transliteration rules.
   - List the 22 languages and scripts where ISO 639-3 code makes a difference:
     - **Middle Eastern / Arabic Script**: Arabic (`ara`), Persian (`fas`), Pashto (`pus`), Uyghur (`uig`), Yiddish (`yid`)
     - **Cyrillic Script**: Russian (`rus`), Ukrainian (`ukr`), Belarusian (`bel`), Bulgarian (`bul`), Macedonian (`mkd`), Serbian (`srp`), Kazakh (`kaz`), Kyrgyz (`kir`), Ossetic (`oss`)
     - **Greek Script**: Modern Greek (`ell`), Ancient Greek (`grc`), Pontic Greek (`pnt`)
     - **Latin / European Specifics**: German (`deu` - for umlauts/ligatures), Latvian (`lav`), Lithuanian (`lit`), Turkish (`tur`)
     - **South Asian (Schwa Preservation)**: Sanskrit (`san`), Assamese (`asm`), Bengali (`ben`), Gujarati (`guj`), Kashmiri (`kas`), Punjabi (`pan`)
   - Include a clickable link / button to view the official documentation at `https://github.com/isi-nlp/uroman`.

---

## 3. Verification Plan

### Automated Tests
1. Run all unit and widget tests:
   ```bash
   flutter test
   ```
2. Verify static analysis:
   ```bash
   dart analyze
   ```
3. Update existing tests referencing `defaultIdPrefix`, `collaboratorName`, or `generateId`.

### Manual Testing
1. **Settings Verification**:
   - Open Settings; verify Collaborator Name and Custom Prefix fields are gone.
   - Verify ID generation preview works cleanly with track name and ID style.
2. **Consolidation & Media Copy**:
   - Create a project with external media files.
   - Turn on "Copy imported media into project folder" in Settings. Verify the consolidation prompt appears and copies files to `<projectDir>/collections/<col>/audio` and `text`.
   - Create a new project and import tracks via Track Pairing Wizard; verify the media copy checkbox is present and functional.
3. **Language Code Info**:
   - In Settings, click the info icon next to Language Code.
   - Verify modal opens, displays the list of supported languages, and provides the external link.
