# Power Automate — post studio outbox ZIPs to Teams

The studio pipeline writes PIM-ready ZIPs (and a `MANIFEST.md` + contact-sheet PNGs)
to the outbox:

```
~/.hermes/outbox/studio/<YYYY-MM-DD>/<Brand>_pim-ready.zip   (host: C:\Users\<you>\.hermes\outbox\studio\...)
~/.hermes/outbox/studio/<YYYY-MM-DD>/MANIFEST.md
~/.hermes/outbox/studio/<YYYY-MM-DD>/<Brand>_contact-sheet.png
```

The Hermes Teams bot can't attach `.zip` files (Bot Framework adapter sends
attachments as text-only). This flow bridges that gap: **watch the outbox → drop the
ZIP into a Teams channel's Files → post a message announcing it.**

> Files "in a Teams channel" actually live in that channel's SharePoint document
> library. Uploading there makes the file appear under the channel's **Files** tab.
> 1:1 chats don't have a shared library, so target a **channel** for file delivery.

---

## Decide the trigger (how the cloud sees a local file)

The outbox is a local Docker volume on the host, so the cloud can't see it directly.
Two ways to bridge it — pick one:

### Option A (recommended, no extra license): OneDrive sync
1. Create a synced folder, e.g. `OneDrive - evo\HermesStudioOutbox\`.
2. Make the studio pipeline also drop ZIPs there. Easiest: a scheduled "publish" copy
   on the host (Task Scheduler, every 5 min):
   ```powershell
   # publish-studio-outbox.ps1
   $src = "$env:USERPROFILE\.hermes\outbox\studio"
   $dst = "$env:OneDrive\HermesStudioOutbox"
   robocopy $src $dst /E /XO /NJH /NJS /NDL | Out-Null
   ```
   (or point `package_zip.py --out` straight at the OneDrive path when you run live.)
3. Trigger: **OneDrive for Business → When a file is created** (standard connector),
   Folder = `/HermesStudioOutbox`, `includeSubfolders = Yes`.

### Option B (faithful, premium): on-prem File System connector
Watches the real outbox with no copies, but needs the **on-premises data gateway**
installed on the host + the **File System** premium connector.
1. Install the on-prem data gateway (signed in as the evo account); name it e.g.
   `hermes-host`.
2. Create a File System connection: Root folder `C:\Users\<you>\.hermes\outbox\studio`,
   using the gateway.
3. Trigger: **File System → When a file is created**, `Folder = \`, include subfolders.

The rest of the flow is identical after the trigger; it just uses different "get file
content" actions (OneDrive vs File System).

---

## Flow steps

**Name:** `Studio outbox → Teams`

### 1. Trigger
Per Option A or B above. Output you'll use downstream:
- File name → `triggerOutputs()?['headers']?['x-ms-file-name']` (File System) or the
  OneDrive trigger's **File name** dynamic content.
- File path / identifier → the trigger's **File identifier** / **Full path**.

### 2. Condition — only PIM ZIPs
Add a **Condition**:
- `File name` **ends with** `_pim-ready.zip`  → if false, **Terminate** (Succeeded).

This skips the MANIFEST/PNG files (handled below) and any temp files.

### 3. (Optional) Skip dry-run packages
While testing, the pipeline still writes real ZIPs with `DRY_RUN` on. To avoid posting
test runs to a live channel, do one of:
- Point this whole flow at a **#studio-test** channel until you go live, **or**
- Read the sibling `MANIFEST.md` (same date folder) and add a Condition
  `contains(manifestText, 'DRY-RUN')` → Terminate when true.

### 4. Get file content
- Option A: **OneDrive for Business → Get file content** (File = trigger File id).
- Option B: **File System → Get file content** (File = trigger File path).

### 5. Upload into the Teams channel's Files
Use **SharePoint → Create file** (the channel's site backs the Files tab):
- **Site Address:** the team's SharePoint site (Teams → channel → Files → Open in
  SharePoint → copy the site URL).
- **Folder Path:** `/Shared Documents/<ChannelName>/Studio` (create a `Studio` subfolder
  once so uploads are tidy).
- **File Name:** `File name` (dynamic) — e.g. `ArcTeryx_pim-ready.zip`.
- **File Content:** **File content** from step 4.

Capture the created file's **Link to item** (output of Create file) for the message.

### 6. Announce in the channel
Use **Microsoft Teams → Post message in a chat or channel**:
- **Post as:** Flow bot (or User).
- **Post in:** Channel → pick the Team + channel.
- **Message** (HTML):
  ```
  📦 <b>PIM-ready package available</b><br/>
  File: <b>@{triggerOutputs's File name}</b><br/>
  <a href="@{outputs('Create_file')?['body/{Link}']}">Open in Files</a><br/>
  Source: studio daily pipeline · @{utcNow()}<br/>
  ⚠️ Review the proposed image order in MANIFEST.md before uploading to PIM.
  ```

### 7. (Optional) Post the MANIFEST text + contact sheet
Add a parallel branch (or a second flow) triggered on `MANIFEST.md` / `*_contact-sheet.png`:
- For `MANIFEST.md`: **Get file content** → **Post message** with the manifest body
  inside `<pre>…</pre>` so formatting survives.
- For `*_contact-sheet.png`: upload via SharePoint **Create file** to the same Files
  folder; the image renders inline when opened. (The Hermes bot already posts the
  manifest text + contact sheet into the chat directly, so this branch is only needed
  if you want them in the channel Files too.)

---

## Notes

- **Dedupe / re-runs:** the pipeline overwrites a day's ZIP if re-run. The OneDrive
  "file created" trigger fires on create; for overwrites use **When a file is created
  or modified**. Guard against double-posts with a Condition on file size > 0 or a
  short delay.
- **Large files:** SharePoint connector handles up to ~250 MB; vendor batches are well
  under that. OneDrive/SharePoint sync must finish before the trigger sees a complete
  file — `robocopy /XO` only copies finished files, which avoids partial-upload races.
- **Permissions:** the connection account needs write access to the channel's
  SharePoint library and rights to post in the channel.
- **Go-live checklist:** (1) `docker exec hermes rm -f /opt/data/profiles/studio/DRY_RUN`
  to allow live writes, (2) switch this flow from #studio-test to the real channel,
  (3) confirm the studio Teams bot is wired (`teams-bot-setup-studio.ps1`).
