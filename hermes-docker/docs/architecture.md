# Hermes install — architecture

Mermaid diagram of the evo-hermes Docker install: container, both gateways, the
`studio` profile (skills, cron, playbook), tools, and external systems.

Blue = studio profile components · pink = external systems. Two gateways run under
one s6 instance in a single container. The studio cron fires daily, runs the
`studio-daily-pipeline` skill, which reads the bundled playbook, sources from vendor
DAMs / Google Sheets, processes images to 1500² JPGs via `evo-image-processing`, zips
PIM-ready output to the outbox, and a human uploads the ZIP to PIM. Solid arrows =
work flow, dotted = LLM call / blocked human gate.

```mermaid
flowchart TB
    subgraph EXT["External systems"]
        TEAMS["MS Teams / Azure Bot"]
        OPENAI["OpenAI API (gpt-5.5)"]
        GSHEET["Google Sheets — Daily Report"]
        DAM["Vendor DAMs<br/>Arc'teryx Aprimo · Amer · Mervin · Sunski"]
        FS["evo fileserver (SMB, VPN)"]
        PIM["PIM (human uploads ZIP)"]
    end

    subgraph HOST["Host — Windows 11 + Docker Desktop"]
        NGROK["ngrok tunnel → :3978"]
        subgraph REPO["repo: hermes-docker/ (evo-hermes)"]
            DF["Dockerfile<br/>+ apt: imagemagick, libvips, webp, zip"]
            COMPOSE["docker-compose.yml"]
            INSTALL["install.ps1<br/>(builds img + deploys studio)"]
            SCAFFOLD["profiles/studio/ scaffold<br/>SOUL · config.overrides · skills · .env.example"]
        end
        subgraph VOL["~/.hermes  (bind mount → /opt/data)"]
            HENV[".env (OPENAI key, Teams creds)"]
            HCFG["config.yaml"]
            OUTBOX["outbox/studio/&lt;date&gt;/<br/>ZIP + MANIFEST.md"]
            subgraph SPROF["profiles/studio/ (HERMES_HOME)"]
                SSOUL["SOUL.md"]
                SCFG["config.yaml<br/>terminal.backend=local · cwd=work<br/>cron_mode=allow · max_turns=300"]
                SENV[".env — vendor DAM creds + OPENAI"]
                WORK["work/ (daily folders)"]
                subgraph SCRON["cron/jobs.json"]
                    JOB["studio-daily · 0 6 * * *<br/>skill=studio-daily-pipeline · deliver=local"]
                end
                subgraph SSK["skills/"]
                    SK1["studio-daily-pipeline<br/>(orchestrator)"]
                    SK2["evo-image-processing<br/>process_images.py · package_zip.py"]
                    SKB["bundled: google-workspace,<br/>github, productivity, creative…"]
                end
                PB["playbook/ (distilled)<br/>workflows 01–04 · standards · guardrails"]
            end
        end
    end

    subgraph CT["Docker container: hermes (hermes-evo:latest)"]
        S6["s6-overlay (PID 1) — supervises"]
        subgraph GW["gateways"]
            GDEF["default gateway :8642<br/>+ Teams adapter :3978"]
            GSTU["studio gateway (profile)<br/>cron scheduler"]
        end
        DASH["dashboard :9119"]
        TOOLS["image tools in image<br/>Pillow · imagemagick · libvips · webp · zip"]
        subgraph TS["toolsets (cli)"]
            T1["terminal (local)"]
            T2["browser"]
            T3["file · web · vision"]
            T4["skills · memory · messaging · cron"]
        end
    end

    %% wiring
    INSTALL --> DF & COMPOSE & SCAFFOLD
    INSTALL -- "deploy: create profile, copy scaffold + playbook, set config, cron, start gw" --> SPROF
    COMPOSE --> CT
    VOL <-->|bind mount| CT
    S6 --> GDEF & GSTU & DASH

    TEAMS <--> NGROK --> GDEF
    GDEF <--> DASH
    GSTU -- loads --> JOB & SSOUL & SCFG & SENV
    JOB -- runs --> SK1
    SK1 -- reads --> PB
    SK1 -- calls --> SK2
    SK2 -- uses --> TOOLS
    GSTU --> TS
    GSTU -.LLM.-> OPENAI

    %% daily pipeline
    SK1 -->|1 refresh| GSHEET
    SK1 -->|2 source imgs| DAM
    SK1 -.blocked: VPN.-> FS
    SK2 -->|3 process 1500² JPG| WORK
    SK2 -->|4 package| OUTBOX
    OUTBOX -->|human uploads| PIM

    classDef ext fill:#fde,stroke:#b59;
    classDef studio fill:#def,stroke:#369;
    class TEAMS,OPENAI,GSHEET,DAM,FS,PIM ext;
    class SSOUL,SCFG,SENV,WORK,JOB,SK1,SK2,SKB,PB,GSTU studio;
```
