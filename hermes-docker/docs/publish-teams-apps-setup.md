# Publish Hermes Teams apps to the org-wide app catalog

The two Hermes bots (`Hermes` / default profile, `Hermes Studio` / studio profile) are currently registered as **personal custom apps** via `teams app create`. This allows application admins and their teams to use them, but they cannot be installed into team channels via the standard "Add app" flow because they're not in the org-wide app catalog.

## What's blocking install into team channels

When you try to add "Hermes" to a team channel via **Add app** in Teams, the Teams UI only shows apps from the **org-wide app catalog** and org-default apps. The current sideloaded custom apps are personal only, so a request to add them fails with "Ask a team owner to add the app" (the team owner sees the same UI limitation, not a permission gap).

## Publishing to org-wide app catalog requires Global or Teams Service Admin role

The Microsoft Graph endpoint `POST /v1.0/appCatalogs/teamsApps` (used to publish an app from a zip package to the org catalog) requires one of these **tenant-level roles**:
- **Global Administrator**
- **Teams Service Administrator**

These are **tenant-level administrative roles**, not app-specific permissions. Even with Graph permissions like `AppCatalog.ReadWrite.All` granted on a service principal, the Graph API still rejects requests from accounts that do not hold one of the above tenant roles.

**Bill's current role (Application Administrator) is insufficient.** A Global Admin or Teams Service Admin must run the publish script.

## Temporary workaround: Install apps as team owner or admin

Until the catalog publishing step happens, you can manually install each bot into a specific team channel:

### Step 1: Install via the team's App Management (Manage team > Apps tab)

1. Open **Hermes POC** team
2. Go to **Settings** → **Apps and integrations** → **Manage apps** (or similar path depending on your Teams version)
3. Search for "Hermes" or "Hermes Studio"
4. When prompted with "Can't find <app>?", click "Manage your apps"
5. Copy the "Hermes" custom app's **install link** (`https://teams.microsoft.com/l/app/<appId>?installAppPackage=true...`)
6. Share that link with team owners to click and install

### Step 2: Publishing to org catalog (requires Teams admin)

Once you have Teams Service Admin or Global Admin permissions, run:

```powershell
# As a Teams Service Admin or Global Admin:
cd C:\Users\bgrow\Projects\evo_photo\hermes-docker
.\Publish-HermesTeamsApps.ps1
```

This will POST the current app packages to `/v1.0/appCatalogs/teamsApps` and create org-wide catalog entries. After that, anyone can use **Add app** in Teams to find and install "Hermes" and "Hermes Studio" normally.

## Manual catalog upload alternative

If the script approach hits permission issues even with admin role, the fallback is Teams Admin Center:

1. Go to **Teams Admin Center** → **Teams apps** → **Manage apps**
2. Click **Upload a new app** at the top
3. Select the app package zip (from `teams app package download <appId> -o out.zip`)
4. Review and approve

This is a one-time manual step per app; future endpoint/version updates would use the same script (or re-upload if the script continues to hit permission blocks).

## Access control (Part 3) — restricting who can install

The full plan calls for creating an Entra security group ("Hermes App Users") and scoping a custom Teams app permission policy to it, so only members of that group can find/install the Hermes apps. This requires two admin roles:

### Step 3a: Create the group (requires Groups Administrator or User Administrator role)

```powershell
# A user with Groups Admin or User Admin role should run:
cd C:\Users\bgrow\Projects\evo_photo\hermes-docker
.\Create-HermesAppUsersGroup.ps1
```

This creates the group, adds the current user as an initial member. Other members can be added later via:
- Entra admin center (Groups → Hermes App Users → Members)
- Command: `az ad group member add --group <groupId> --member-id <userId>`

If Bill doesn't have the required role, ask a Global Admin or Groups Administrator to run this script.

### Step 3b: Create app permission policy (requires Teams Service Admin or Global Admin role, MicrosoftTeams PowerShell module)

Once the group exists and is populated, a Teams admin can create a custom app permission policy scoped to it:

```powershell
# A user with Teams Service Admin or Global Admin role should run (interactive):
Install-Module MicrosoftTeams -Scope CurrentUser -Force
Connect-MicrosoftTeams
$groupId = "<Hermes App Users group ID from Step 3a>"
$policy = New-CsTeamsAppPermissionPolicy -Identity "HermesAppsOnly" `
  -DefaultCatalogApps "3146b701-6559-4671-b9d9-91e7508884b1", "521aaadb-ab96-4275-be9e-37bdb285ffc8"
New-CsGroupPolicyAssignment -GroupId $groupId -PolicyType TeamsAppPermission -PolicyName "HermesAppsOnly"
```

(Exact cmdlet names and syntax may vary by MicrosoftTeams module version; check with `Get-Command -Module MicrosoftTeams *AppPermission*` after installing.)

## Notes

- **App IDs** (AAD app IDs):
  - Hermes (default): `3146b701-6559-4671-b9d9-91e7508884b1`
  - Hermes Studio: `521aaadb-ab96-4275-be9e-37bdb285ffc8`
- **Current sideload install links** (Bill):
  - Default: https://teams.microsoft.com/l/app/3146b701-6559-4671-b9d9-91e7508884b1?installAppPackage=true&appTenantId=1c2caf71-5666-4b98-bffc-ae0da8c4a4db
  - Studio: https://teams.microsoft.com/l/app/521aaadb-ab96-4275-be9e-37bdb285ffc8?installAppPackage=true&appTenantId=1c2caf71-5666-4b98-bffc-ae0da8c4a4db
