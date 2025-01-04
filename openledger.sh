#!/bin/bash

echo "-----------------------------------------------------------------------------"
curl -s https://raw.githubusercontent.com/BidyutRoy2/BidyutRoy2/main/logo.sh | bash
echo "-----------------------------------------------------------------------------"

# Docker kurulumunu kontrol et ve gerekirse kur
if ! command -v docker &> /dev/null; then
    echo "Docker kurulu değil. Kuruluyor..."
    sudo apt update
    sudo apt install -y ca-certificates curl gnupg lsb-release
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo systemctl enable docker
    sudo systemctl start docker
fi

# Docker grubuna kullanıcı ekle
sudo usermod -aG docker $USER

# Çalışma dizini oluştur
mkdir -p ~/openledger-docker
cd ~/openledger-docker

# Dockerfile oluştur
cat > Dockerfile << 'EOL'
FROM ubuntu:22.04

# Temel sistem paketlerini yükle
RUN apt-get update && apt-get install -y \
    wget \
    unzip \
    libasound2 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libgbm1 \
    libgtk-3-0 \
    libnspr4 \
    libnss3 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libxshmfence1 \
    libxss1 \
    libxtst6 \
    xvfb \
    dbus \
    && rm -rf /var/lib/apt/lists/*

# Openledger kurulumu
WORKDIR /app
RUN wget https://cdn.openledger.xyz/openledger-node-1.0.0-linux.zip \
    && unzip openledger-node-1.0.0-linux.zip \
    && dpkg -i openledger-node-1.0.0.deb \
    && rm openledger-node-1.0.0-linux.zip openledger-node-1.0.0.deb

# Xvfb ve dbus başlatma scripti
RUN echo '#!/bin/bash\n\
Xvfb :99 -screen 0 1024x768x16 &\n\
export DISPLAY=:99\n\
sleep 2\n\
mkdir -p /var/run/dbus\n\
dbus-daemon --system --fork\n\
dbus-daemon --session --fork\n\
openledger-node --no-sandbox --disable-gpu --disable-software-rasterizer' > /app/start.sh \
    && chmod +x /app/start.sh

EXPOSE 4005

CMD ["/app/start.sh"]
EOL

# Docker Compose dosyası oluştur
cat > docker-compose.yml << 'EOL'
version: '3.8'
services:
  openledger:
    build: .
    container_name: openledger
    restart: unless-stopped
    ports:
      - "4005:4005"
    volumes:
      - .//app/data
    environment:
      - DISPLAY=:99
    cap_add:
      - SYS_ADMIN
    security_opt:
      - seccomp=unconfined
EOL

# Docker container'ı oluştur ve başlat
echo "Docker container oluşturuluyor ve başlatılıyor..."
sudo docker-compose up --build -d

# Container durumunu kontrol et
echo "Container durumu kontrol ediliyor..."
sudo docker ps
sudo docker logs openledger

echo "Kurulum tamamlandı! Container loglarını görmek için:"
echo "sudo docker logs -f openledger"
echo "Container'ı yeniden başlatmak için:"
echo "sudo docker-compose restart"
echo "Container'ı durdurmak için:"
echo "sudo docker-compose down"

# Kullanıcıya container'ın çalışıp çalışmadığını kontrol etmesi için bilgi ver
echo "Openledger'a http://localhost:4005 adresinden erişebilirsiniz."
