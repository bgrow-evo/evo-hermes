# Azure Container Apps Deployment Attempt - Summary

⚠️ **SUPERSEDED**: This July 1 attempt (Azure Disk / Premium NFS) was abandoned. The working solution is in [HERMES_ACA_STANDARD_STORAGE_PLAN.md](HERMES_ACA_STANDARD_STORAGE_PLAN.md) — uses `aca-hermes-nfs` with `EmptyDir` + Standard Azure Files rsync backing.

**Date:** July 1, 2026
**Objective:** Deploy Hermes Teams bot to Azure Container Apps (ACA) in Playground subscription
**Status:** BLOCKED - Platform incompatibility

---

## Objective

Deploy the `evo_photo/hermes-docker` project to Azure Container Apps to replace ngrok tunneling for the Teams Studio bot. The deployment should:
- Migrate local volume data (`C:\Users\bgrow\.hermes`) to Azure storage
- Build and push Docker image to Azure Container Registry (ACR)
- Deploy container app with persistent volume
- Update Teams bot endpoint to use ACA URL
- Expose Teams bot on port 3979

---

## What Was Attempted

### 1. Azure Platform Initialization
**Script:** `Initialize-HermesPlatform.ps1`
- Created resource group: `rg-hermes-sbx`
- Created ACR: `acrhermessbx`
- Created storage account: `sthermessbxwu2`
- Created Azure File share: `hermes-data`
- Created ACA environment: `aca-env-hermes-sbx-wu2`

**Status:** ✅ Completed successfully

### 2. Volume Migration
**Script:** `Migrate-HermesVolume.ps1`
- Migrated local `C:\Users\bgrow\.hermes` to Azure Files
- Excluded locked files and unnecessary directories
- Used Azure Storage account key authentication

**Status:** ✅ Completed successfully

### 3. Docker Image Build
**Script:** `Build-HermesImage.ps1`
- Built custom Hermes image with Teams SDK pre-installed
- Pushed to ACR with both specific tag and `latest`
- Fixed image tagging issue (both tags now pushed)

**Status:** ✅ Completed successfully

### 4. Container App Deployment
**Script:** `Deploy-HermesAzure.ps1`
- Used two-phase deployment approach:
  - Phase 1: `az containerapp create` with CLI flags
  - Phase 2: `az rest PATCH` to add volume mount
- Added environment variables: `HERMES_DASHBOARD=1`, dashboard auth, `HERMES_PROFILE=studio`, `HERMES_SKIP_CHOWN=true`

**Status:** ❌ Failed due to platform incompatibility

---

## What Failed

### Issue 1: Container Unhealthy - fd_chmod Errors
**Symptoms:**
- Container revisions showing `Unhealthy` status
- Logs showing: `fd_chmod: Operation not permitted` on `/opt/data` files
- Example error: `ERROR: [Errno 1] Operation not permitted: '/opt/data/config.yaml.bak-20260701T223840Z'`

**Root Cause:**
- Hermes uses s6-overlay init system which requires Unix file permissions (chown/chmod)
- Azure Files (SMB protocol) doesn't support Unix file permission operations
- The init script attempts to fix ownership of `/opt/data` to the `hermes` user (UID 10000)
- `HERMES_SKIP_CHOWN=true` environment variable didn't prevent these operations

**Attempted Fixes:**
- Added `HERMES_SKIP_CHOWN=true` env var - didn't work
- Deleted `logs/` directory from Azure Files - container still tried to chown config files
- Copied studio profile config to default location - didn't resolve chmod issue

### Issue 2: Container Exits Without TTY
**Symptoms:**
- When volume mount was removed for testing, container logs showed "Goodbye!" and shutdown
- Logs: `Warning: Input is not a terminal (fd=0).` followed by `Goodbye!`

**Root Cause:**
- Hermes is designed for interactive use (requires TTY)
- Without explicit daemon command, it exits when no terminal detected

**Attempted Fix:**
- Added `--command "gateway" "run"` to container app
- **Result:** Container provisioning failed with `ContainerAppImageRequired` error

### Issue 3: Azure Disk Not Supported on ACA
**Attempted Solution:**
- Created Azure Disk (`hermes-data-disk`) which supports Unix file permissions
- Attempted to register with ACA environment

**Root Cause:**
- Azure Container Apps only supports Azure Files storage
- Azure Disk (which supports Unix permissions) is not available on ACA platform
- This is a fundamental platform limitation

---

## Root Cause Analysis

The deployment is blocked by three fundamental incompatibilities:

1. **Azure Files doesn't support Unix permissions**
   - Hermes's s6-overlay init system requires `chown`/`chmod` operations
   - Azure Files (SMB) cannot perform these operations
   - No environment variable can disable this behavior

2. **Azure Container Apps only supports Azure Files**
   - Azure Disk (which supports Unix permissions) is not available on ACA
   - This is a platform limitation, not a configuration issue

3. **Hermes requires explicit daemon mode**
   - Without TTY, Hermes exits
   - Adding `gateway run` command caused ACA provisioning failures
   - ACA's command handling appears incompatible with Hermes's requirements

---

## Current State

**Azure Resources Created:**
- Resource Group: `rg-hermes-sbx`
- ACR: `acrhermessbx.azurecr.io`
- Storage Account: `sthermessbxwu2` with File Share `hermes-data`
- ACA Environment: `aca-env-hermes-sbx-wu2`
- Azure Disk: `hermes-data-disk` (unused, created as workaround attempt)

**Docker Image:**
- Built and pushed: `acrhermessbx.azurecr.io/hermes:3d3ccf7`
- Also tagged as `latest`

**Container App:**
- Created but unhealthy: `aca-hermes`
- FQDN: `aca-hermes.ambitiouspebble-c98356fa.westus2.azurecontainerapps.io`
- Current status: Deleted (for cleanup)

---

## Recommended Solution

Deploy to **Azure Kubernetes Service (AKS)** instead of Azure Container Apps.

**Why AKS works:**
- Supports Azure Disk volumes with full Unix file system support
- Allows proper daemon service configuration with explicit commands
- Supports custom entrypoints and init systems
- Provides full Kubernetes control for complex workloads

**Implementation Steps:**
1. Create AKS cluster in Playground subscription
2. Create Azure Disk for persistent storage (10GB Standard_LRS)
3. Create Kubernetes PersistentVolumeClaim using Azure Disk
4. Deploy Hermes as Kubernetes Deployment with:
   - Azure Disk PVC mounted to `/opt/data`
   - Explicit command: `["gateway", "run"]`
   - Environment variables for dashboard and Teams
5. Configure Kubernetes Ingress for Teams bot endpoint (port 3979)
6. Update Teams bot endpoint to AKS ingress URL

**Alternative Options:**
- **Azure VM with Docker:** Run Hermes on a VM with local disk storage
- **Azure Container Instances (ACI):** Limited volume support, may have similar issues
- **Different hosting platform:** Consider platforms that support full Linux containers with persistent block storage

---

## Files Modified

1. **`scripts/azure/Deploy-HermesAzure.ps1`**
   - Added `HERMES_PROFILE=studio` and `HERMES_SKIP_CHOWN=true` env vars
   - Implemented two-phase deployment (CLI create + az rest PATCH)
   - Attempted to add `gateway run` command (later removed due to failures)

2. **`scripts/azure/Build-HermesImage.ps1`**
   - Modified to push both specific tag and `latest` to ACR
   - Fixed image tagging consistency issue

3. **`scripts/azure/Verify-HermesAzure.ps1`**
   - Fixed PowerShell parsing errors (replaced non-ASCII em-dashes)

---

## Key Learnings

1. **Azure Container Apps limitations:**
   - Only supports Azure Files (SMB), not Azure Disk
   - Azure Files doesn't support Unix file permissions
   - Not suitable for workloads requiring chown/chmod operations

2. **Hermes requirements:**
   - Requires Unix file system with permission support
   - Designed for interactive use or explicit daemon mode
   - s6-overlay init system is not configurable to skip permission operations

3. **Platform selection matters:**
   - Serverless platforms (ACA) have trade-offs
   - Full Kubernetes (AKS) provides more control for complex workloads
   - Always verify platform capabilities before committing to deployment

---

## Next Steps for Teammate

If you want to continue with Azure deployment:

1. **AKS Deployment Path:**
   - Review AKS pricing and resource requirements
   - Create AKS cluster deployment script
   - Migrate Azure Files data to Azure Disk
   - Create Kubernetes manifests (Deployment, PVC, Ingress)
   - Test deployment in Playground subscription

2. **Alternative Path:**
   - Consider keeping Hermes on local machine with ngrok
   - Evaluate other hosting platforms (DigitalOcean, AWS ECS with EBS, etc.)
   - Assess if Hermes can be modified to work without Unix permissions (upstream change)

3. **Cleanup (if abandoning ACA):**
   - Delete resource group: `az group delete --name rg-hermes-sbx --yes`
   - This will remove all created resources

---

## Contact

For questions about this deployment attempt, refer to:
- Original issue context in conversation history
- Hermes documentation: https://github.com/nousresearch/hermes
- Azure Container Apps documentation: https://learn.microsoft.com/azure/container-apps/
