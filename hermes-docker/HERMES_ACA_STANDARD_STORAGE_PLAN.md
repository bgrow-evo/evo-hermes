# Hermes ACA Deployment Plan: Standard Storage Without Premium NFS

## Goal

Host `C:\Users\bgrow\Projects\evo_photo\hermes-docker` on Azure Container Apps while avoiding Premium NFS storage.

Target design:

- Use Standard Azure Files SMB for durable `.hermes` data.
- Do not mount SMB directly at `/opt/data`.
- Run Hermes against local POSIX-compatible container storage at `/opt/data`.
- Sync durable data between `/opt/data` and the SMB share.
- Keep one replica only.
- Preserve Teams bot behavior on port `3979`.

## Why The Prior SMB Mount Failed

The first ACA attempt mounted Standard Azure Files SMB directly to `/opt/data`.

Hermes and s6-overlay treat `/opt/data` as a Linux home/data root. Startup and logging try operations such as `chmod`, `chown`, and SQLite locking. Azure Files SMB is persistent and cheap, but it is not a normal Linux filesystem for those operations. Logs showed:

```text
Operation not permitted
s6-log: fatal: unable to fd_chmod ...
```

The Jira Analytics app can use Azure Files SMB directly because its entrypoint tolerates failed `chown`, keeps `maxReplicas = 1`, and avoids multi-process SQLite contention. Hermes is more sensitive because the init/logging layer touches permissions under `/opt/data` continuously.

## Recommended Architecture

Use Standard Azure Files as a backing store, not as the live filesystem.

```text
Azure Files SMB share
  stHermes.../hermes-data
        |
        | startup restore
        v
/opt/data inside container
  EmptyDir or container writable layer
  POSIX-compatible for chmod/chown/logging/SQLite
        |
        | periodic + shutdown snapshot
        v
Azure Files SMB share
```

### Mounts

| Path | Backing | Purpose |
|---|---|---|
| `/mnt/hermes-persist` | Standard Azure Files SMB | Durable `.hermes` store |
| `/opt/data` | ACA `EmptyDir` or writable container filesystem | Live Hermes runtime data |

Do not mount Azure Files at `/opt/data`.

## Current Resources To Reuse

Reuse:

- `rg-hermes-sbx`
- `acrhermessbx`
- `sthermessbxwu2` Standard_LRS storage account
- `sthermessbxwu2/hermes-data` SMB share with copied `.hermes` data
- `aca-env-hermes-nfs-sbx-wu2` for now, even though NFS will not be used
- `aca-hermes-nfs` can be repurposed or replaced with cleaner name later

Retire only after Standard-storage design is verified:

- `sthermesnfswu2` Premium_LRS NFS storage account
- NFS storage registration on ACA env
- NFS-specific app revision

## Container Changes

Add a small wrapper entrypoint to the image, for example:

```text
/usr/local/bin/hermes-aca-entrypoint
```

Responsibilities:

1. Create `/opt/data` and `/mnt/hermes-persist`.
2. Restore durable data from `/mnt/hermes-persist` into `/opt/data`.
3. Fix ownership and permissions only on `/opt/data`.
4. Start Hermes with explicit daemon args:

   ```bash
   gateway run
   ```

5. Run a background snapshot loop from `/opt/data` back to `/mnt/hermes-persist`.
6. Trap `SIGTERM`, stop Hermes cleanly, run final snapshot, exit.

Keep dashboard disabled at first:

```text
HERMES_DASHBOARD=0
HERMES_PROFILE=studio
```

Enable dashboard later only after `dashboard.basic_auth` is configured in `config.yaml`.

## Sync Rules

Use `rsync` if available; otherwise install it in the image.

Restore on startup:

```bash
rsync -a --delete \
  --exclude '.cache/' \
  --exclude '__pycache__/' \
  --exclude '*.lock' \
  --exclude '*.pid' \
  --exclude 'logs/gateways/' \
  /mnt/hermes-persist/ /opt/data/
```

Snapshot back periodically:

```bash
rsync -a --delete \
  --exclude '.cache/' \
  --exclude '__pycache__/' \
  --exclude '*.lock' \
  --exclude '*.pid' \
  --exclude 'logs/gateways/' \
  /opt/data/ /mnt/hermes-persist/
```

SQLite files need special care. Preferred approach:

- Do not blindly copy live `state.db`, `kanban.db`, or profile `state.db` while Hermes is writing.
- Use a small Python helper that runs SQLite `VACUUM INTO` or `.backup` to a temp file, then atomically moves the backup into `/mnt/hermes-persist`.
- Exclude `*.db-wal` and `*.db-shm` from ordinary rsync.

Minimum DB list to handle:

- `/opt/data/state.db`
- `/opt/data/kanban.db`
- `/opt/data/profiles/studio/state.db`

## Azure Container App Shape

Set app config:

- `minReplicas = 1`
- `maxReplicas = 1`
- ingress external
- target port `3979`
- args or wrapper command must start `gateway run`

Volumes:

```yaml
template:
  containers:
  - name: hermes
    image: acrhermessbx.azurecr.io/hermes:<tag>
    env:
    - name: HERMES_DASHBOARD
      value: "0"
    - name: HERMES_PROFILE
      value: studio
    volumeMounts:
    - volumeName: hermes-live
      mountPath: /opt/data
    - volumeName: hermes-persist
      mountPath: /mnt/hermes-persist
  volumes:
  - name: hermes-live
    storageType: EmptyDir
  - name: hermes-persist
    storageType: AzureFile
    storageName: hermes-data
```

The `hermes-data` environment storage should point to the Standard Azure Files share:

```text
storage account: sthermessbxwu2
share: hermes-data
protocol: SMB / AzureFile
```

## Implementation Phases

### Phase 1: Validate Standard SMB As Backing Store

1. Build image with wrapper entrypoint and `rsync`.
2. Mount Standard Azure Files at `/mnt/hermes-persist`.
3. Mount `EmptyDir` at `/opt/data`.
4. Start app with `gateway run`.
5. Confirm logs no longer show `fd_chmod` or `Operation not permitted`.
6. Confirm Teams listener binds to `3979`.

Success criteria:

- Revision becomes healthy.
- Logs show Hermes gateway running.
- No permission spam.
- `/api/messages` responds enough for Teams webhook traffic.

### Phase 2: Prove Persistence

1. Send a test Teams message.
2. Confirm session/state changes appear in `/opt/data`.
3. Wait for snapshot loop.
4. Restart revision.
5. Confirm data restores from `/mnt/hermes-persist`.
6. Confirm auth/profile config survives restart.

Success criteria:

- State survives revision restart.
- Studio profile still enabled.
- Teams bot still uses existing app registration credentials.

### Phase 3: Make Deploy Scripts First-Class

Update Hermes scripts to match Jira Analytics pattern:

- `Initialize-HermesPlatform.ps1`
  - Create Standard_LRS StorageV2 account if missing.
  - Create Azure Files SMB share.
  - Register ACA env storage as `AzureFile`.

- `Migrate-HermesVolume.ps1`
  - Upload local `.hermes` to SMB share.
  - Exclude logs, locks, pids, caches, WAL/SHM files.

- `Deploy-HermesAzure.ps1`
  - Deploy image.
  - Configure two mounts:
    - `/opt/data` as `EmptyDir`
    - `/mnt/hermes-persist` as `AzureFile`
  - Set `args = gateway run` or wrapper entrypoint.
  - Keep single replica.

- `Verify-HermesDeploy.ps1`
  - Check revision health.
  - Tail logs for permission failures.
  - Check Teams endpoint URL.

### Phase 4: Remove Premium NFS

Only after Phase 2 passes:

1. Stop/delete NFS app revision if still present.
2. Delete `sthermesnfswu2`.
3. Remove NFS storage registration from ACA env.
4. Keep `sthermessbxwu2` as durable backing store.

## Risks And Mitigations

| Risk | Mitigation |
|---|---|
| Container crashes before final sync | Run frequent snapshot loop, for example every 60 seconds |
| SQLite copied mid-write | Use SQLite backup API, exclude WAL/SHM from rsync |
| Two replicas race on same data | Keep `maxReplicas = 1` |
| Azure Files SMB blocks chmod | Never run Hermes against SMB path directly |
| Large sync slows startup | Exclude caches/logs; consider sync manifest for hot files |
| Dashboard startup failure | Keep `HERMES_DASHBOARD=0` until config auth is set |

## Decision Points

1. Use current VNet-backed ACA env, or create a simpler non-VNet env once NFS is gone.
2. Keep `aca-hermes-nfs` name temporarily, or recreate as `aca-hermes`.
3. Snapshot interval: 60 seconds for safety, 5 minutes for lower churn.
4. Decide whether logs should persist. Recommendation: rely on ACA Log Analytics, not `.hermes/logs`.

## References

- Azure Container Apps supports `EmptyDir` ephemeral volumes and Azure Files volumes.
- Azure Files SMB is the Standard storage path similar to Jira Analytics.
- Azure Files NFS is POSIX-friendly but requires custom VNet and is the path we want to avoid unless the Standard backing-store design fails.

