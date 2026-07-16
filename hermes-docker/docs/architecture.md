# Hermes install - architecture

Mermaid diagram of the evo-hermes deployment: one container (Azure Container Apps in
production, docker compose for local dev), two gateways, the `studio` profile, and
external systems.

Teams connectivity is the **teams_graph** adapter: Hermes polls and posts as the
licensed user `hermes-ai@evo.com` via delegated Microsoft Graph. Outbound HTTPS only —
no bot registration, no tunnel, no inbound webhook. Blue = studio profile components.
Pink = external systems. The studio cron fires daily at 06:00 UTC, runs the
`studio-daily-pipeline` skill, reads the playbook, sources from vendor DAMs / Google
Sheets, processes images to 1500x1500 JPGs via `evo-image-processing`, zips PIM-ready
output to the outbox, and delivers results to the "Studio Photo" group chat.

```mermaid
flowchart TB
    subgraph EXT["External systems"]
        TEAMS["MS Teams chats<br/>(Hermes acts as hermes-ai@evo.com)"]
        GRAPH["Microsoft Graph<br/>delegated: Chat.ReadWrite / ChannelMessage.Send"]
        OPENAI["OpenAI Codex OAuth (gpt-5.6-terra)"]
        GSHEET["Google Sheets - Daily Report"]
        DAM["Vendor DAMs<br/>Arc'teryx Aprimo / Amer / Mervin / Sunski"]
        FS["evo fileserver (SMB, VPN)"]
        PIM["PIM (human uploads ZIP)"]
    end

    subgraph AZ["Azure (rg-hermes-sbx) - production"]
        ACR["acrhermessbx<br/>hermes:&lt;tag&gt; image"]
        subgraph ACA["Container App: aca-hermes-nfs"]
            PROXY["aca-proxy :8080<br/>ingress + health endpoints"]
            S6["s6-overlay (PID 1) - supervises"]
            subgraph GW["gateways"]
                GDEF["default gateway<br/>teams_graph: DMs + Hermes Admin chat"]
                GSTU["studio gateway (profile)<br/>teams_graph: Studio Photo chat<br/>cron scheduler"]
            end
            SYNC["aca-sync<br/>60s snapshot live -> share"]
        end
        SHARE["Azure Files: sthermessbxwu2/hermes-data<br/>SINGLE SOURCE OF TRUTH for /opt/data<br/>config, skills, playbook, sessions,<br/>pairing, Graph token cache, outbox"]
    end

    subgraph SPROF["profile: studio (on the share)"]
        SCFG["config.yaml<br/>platforms.teams_graph / model gpt-5.6-terra"]
        JOB["cron: studio-daily-pipeline<br/>0 6 * * * (UTC), dry-run, deliver=teams_graph"]
        SK1["skills/studio-daily-pipeline<br/>(orchestrator)"]
        SK2["skills/evo-image-processing<br/>process_images.py / package_zip.py"]
        PB["playbook/<br/>workflows / standards / guardrails"]
        OUTBOX["outbox/studio/&lt;date&gt;/<br/>ZIP + MANIFEST.md (+ blob links)"]
    end

    ACR --> ACA
    SHARE <-->|restore on boot / snapshot 60s| SYNC
    S6 --> PROXY & GDEF & GSTU & SYNC

    GDEF & GSTU <-->|poll ~3s + post inline| GRAPH <--> TEAMS
    GDEF -.LLM.-> OPENAI
    GSTU -.LLM.-> OPENAI

    GSTU -- loads --> SCFG & JOB
    JOB -- runs --> SK1
    SK1 -- reads --> PB
    SK1 -- calls --> SK2

    SK1 -->|1 refresh| GSHEET
    SK1 -->|2 source imgs| DAM
    SK1 -.blocked: VPN.-> FS
    SK2 -->|3 process + 4 package| OUTBOX
    OUTBOX -->|human uploads| PIM
    JOB -->|results| TEAMS

    classDef ext fill:#fde,stroke:#b59;
    classDef studio fill:#def,stroke:#369;
    class TEAMS,GRAPH,OPENAI,GSHEET,DAM,FS,PIM ext;
    class SCFG,JOB,SK1,SK2,PB,OUTBOX,GSTU studio;
```

Local dev (`install.ps1` + docker compose) runs the same image with `~/.hermes`
bind-mounted as `/opt/data`. Because teams_graph polls outbound, a local instance can
chat on Teams with no tunnel — but never run local and ACA against the same chats or
the same data directory at once.

Retired: the Bot Framework / Teams-app path (Azure Bot registrations, ngrok tunnels,
`/api/messages` webhooks, app manifest). Scripts preserved in `archive/`.
