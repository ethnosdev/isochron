# Team Collaboration Guide: Serverless Cloud Sync

Isochron supports multi-user team collaboration on shared cloud storage (Google Drive, Dropbox, OneDrive, iCloud Drive, or local network NAS drives) **without requiring a dedicated server, database, or Git knowledge**.

This architecture is specially designed for large, multi-book projects (such as Bible audio alignment across 66 books and 1,189 chapters, totaling thousands of audio and timing files).

---

## 🚀 How It Works

Traditional tools often store the entire project's state in a single monolithic file. When multiple people edit simultaneously, they overwrite each other's work or create sync conflicts.

Isochron solves this with **Chapter-Level Isolation & Live Sync**:
1. **Isolated Files**: Each track's timing data (`_timing.json`), manual pins (`-pins.json`), and active claim status (`.claim.json`) are stored as independent sidecar files.
2. **Targeted Saves**: Saving an edit in chapter 1 touches *only* chapter 1's files and its parent collection. It never writes to or re-saves other collections.
3. **Machine-Independent Paths**: Project files do not store hardcoded machine paths (e.g., `/Users/alice/` vs `/Users/bob/`). You can open the same project from any collaborator's Mac.
4. **Soft Claims (Locking)**: When you open a track in the Studio Editor, Isochron automatically claims it for you. Other team members see your initials in their sidebar tree and can only open that track in Read-Only mode.
5. **Live Directory Watcher**: As your cloud drive syncs files in the background, Isochron detects remote changes in real time and refreshes track statuses, review badges, and claim initials without needing to restart the app.

---

## 🛠️ Step-by-Step Setup

### Step 1: Set Your Collaborator Name (Each Teammate)

Before starting, each team member should set their name so colleagues know who is working on each chapter:

1. Open Isochron.
2. Open any project or create a temporary one to access the sidebar.
3. In the left sidebar, click the **Settings** (gear) icon at the bottom.
4. Under **App Preferences**, find the **Collaborator Name** field.
5. Enter your name (e.g., `Alice Smith` or `Bob J`).
6. Press **Tab** or click outside to save. Isochron remembers this setting across all projects.

*(If you don't set a name, Isochron defaults to your Mac user account name).*

---

### Step 2: Share the Project on Cloud Storage

1. **Project Creator**:
   * Create a new project in Isochron or move an existing project folder into your shared cloud storage (e.g., `Google Drive/Shared drives/Bible Project/`).
   * Verify that **"Copy Media into Project"** is checked in Project Settings so that audio and text files are bundled together inside the shared folder.
2. **Share Permissions**:
   * Grant your team members **Editor** (read & write) access to the shared folder in Google Drive / Dropbox.
3. **Team Members**:
   * Install Google Drive for Desktop (or Dropbox / OneDrive) so the shared folder appears as a local folder in macOS Finder.
   * Open Isochron, click **Open Existing Project**, navigate to the shared cloud folder in Finder, and select `project.json`.

---

## 👥 Daily Team Workflow

### 1. Finding & Claiming a Chapter
* In the left sidebar tree, look through the collections (e.g., Genesis, Exodus, Matthew).
* Tracks that are currently free show their standard status icons (e.g., Pending, Done, Reviewed).
* **Double-click** any unassigned track to open it in the **Studio Editor**.
* Isochron automatically creates a lightweight claim file (`alignments/<track>.claim.json`).

### 2. Live Presence in the Sidebar
* While you are working on a track, your initials (e.g., `[AS]`) will appear next to that track in everyone's sidebar tree.
* Hovering over the badge shows a tooltip: `In progress by Alice Smith`.
* Teammates know at a glance which chapters are currently being aligned or reviewed.

### 3. Read-Only Protection
* If you open a track that is currently claimed by a teammate, the Studio Editor opens in **Read-Only Mode**.
* A clear banner appears at the top:  
  `Viewing Chapter 01 (Read-Only: in progress by Bob Jones)`
* All destructive operations (saving, nudging markers, toggling pins, capturing timing) are disabled to prevent overwriting your colleague's in-progress work.

### 4. Taking Over a Claim (Override)
If a teammate stepped away, left for vacation, or forgot to close a track:
1. Open the track in read-only mode.
2. Click the **Take Over Claim** button on the top banner.
3. Isochron reassigns the claim to you and unlocks the editor for editing.

### 5. Releasing Claims & Saving
* When you finish adjusting a track, press **Cmd + S** to save.
* When you switch to another track, navigate away, or close the project, your claim is **automatically released** and the badge disappears from your teammates' screens.

### 6. Live Status Updates
* When a collaborator marks a track as **Reviewed** or runs an alignment, Isochron's background watcher detects the updated files synced by your cloud provider.
* The sidebar icons update dynamically without interrupting whatever you are doing in the editor.

---

## 💡 Best Practices & Tips

1. **Keep Cloud Sync Active**: Ensure Google Drive for Desktop or Dropbox is actively running and has finished syncing before shutting your laptop.
2. **Offline Work**: If working on an airplane or without internet, you can still edit tracks locally. However, other teammates won't see your claim until your computer reconnects and syncs.
3. **Audio File Storage**: Always enable **"Copy Media into Project"** in Project Settings. This guarantees that all audio and text files are stored within the project directory so every teammate has immediate access.
4. **Debouncing**: Cloud storage clients sometimes sync files in bursts. Isochron debounces filesystem events by 300ms so the interface remains smooth and responsive during large sync batches.

---

## ❓ Troubleshooting

### My teammate's changes aren't showing up yet
* Check the Google Drive or Dropbox menu bar icon to verify files have finished uploading on their computer and downloading on yours.
* You can also click anywhere in the sidebar or switch views to force an instant refresh.

### A track is stuck with a claim badge for someone who is offline
* Double-click the track to open it in the Studio Editor.
* Click **Take Over Claim** on the top warning banner. The old claim will be replaced with yours.

### Can two people run alignments at the same time?
* **Yes!** Collaborators can run batch alignments or manual alignments on different chapters simultaneously without any conflicts.
