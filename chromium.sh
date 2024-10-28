#!/bin/bash
mkdir -p chromium && cd chromium && cat <<EOF > docker-compose.yaml
services:
  chromium:
    image: lscr.io/linuxserver/chromium:latest
    container_name: chromium
    security_opt:
      - seccomp:unconfined #optional
    environment:
      - CUSTOM_USER=randomkullanıcıadı
      - PASSWORD=random
      - PUID=1000
      - PGID=1000
      - TZ=Europe/London
      - CHROME_CLI=
    volumes:
      - /root/chromium/config:/config
    ports:
      - 3010:3000 
      - 3011:3001
    shm_size: "1gb"
    restart: unless-stopped
EOF
docker compose up -d
