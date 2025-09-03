#!/bin/bash

# Renklendirme için ANSI kodları
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Konfigürasyon
GPU_COUNT=${1:-1}  # İlk parametre olarak GPU sayısı, varsayılan 1
TIMEOUT_MODEL_LOADING=300  # 5 dakika (300 saniye)
TIMEOUT_EARNING=300  # 5 dakika (300 saniye)
MIN_EARNING_THRESHOLD=20  # Minimum kabul edilebilir coin miktarı
LOG_FILE="/tmp/wai_monitor_$.log"
TAIL_PID=""  # tail process ID

# GPU komutunu belirle
if [ "$GPU_COUNT" -eq 1 ]; then
    WAI_COMMAND="wai run"
    echo -e "${BLUE}[INFO] 1 GPU sistemi algılandı. Komut: $WAI_COMMAND${NC}"
elif [ "$GPU_COUNT" -eq 6 ]; then
    WAI_COMMAND="wai run --gpus 0 1 2 3 4 5"
    echo -e "${BLUE}[INFO] 6 GPU sistemi algılandı. Komut: $WAI_COMMAND${NC}"
else
    WAI_COMMAND="wai run --gpus"
    for ((i=0; i<$GPU_COUNT; i++)); do
        WAI_COMMAND="$WAI_COMMAND $i"
    done
    echo -e "${BLUE}[INFO] $GPU_COUNT GPU sistemi için komut: $WAI_COMMAND${NC}"
fi

# Temizlik fonksiyonu
cleanup() {
    echo -e "\n${YELLOW}[INFO] Script sonlandırılıyor...${NC}"
    
    # Tail process'ini durdur
    if [ ! -z "$TAIL_PID" ] && ps -p $TAIL_PID > /dev/null 2>&1; then
        kill -KILL $TAIL_PID 2>/dev/null
        TAIL_PID=""
    fi
    
    # Sadece bu script'in başlattığı WAI PID'i ve ilgili process'leri durdur
    if [ ! -z "$WAI_PID" ] && ps -p $WAI_PID > /dev/null 2>&1; then
        echo -e "${YELLOW}[INFO] WAI process durduruluyor (PID: $WAI_PID)...${NC}"
        
        # Alt process'leri bul
        WAI_CHILDREN=$(pgrep -P $WAI_PID)
        
        # ML client process'lerini bul
        ML_PIDS=$(ps aux | grep -E "wombo.*ml-clients" | grep -v grep | awk '{print $2}' | grep -v "^$\$")
        
        # Önce SIGINT gönder
        kill -INT $WAI_PID 2>/dev/null
        
        if [ ! -z "$WAI_CHILDREN" ]; then
            for child in $WAI_CHILDREN; do
                kill -INT $child 2>/dev/null
            done
        fi
        
        # 5 saniye bekle
        for i in {1..5}; do
            if ! ps -p $WAI_PID > /dev/null 2>&1; then
                echo -e "${GREEN}[INFO] WAI process başarıyla durduruldu${NC}"
                break
            fi
            sleep 1
        done
        
        # Hala çalışıyorsa SIGTERM gönder
        if ps -p $WAI_PID > /dev/null 2>&1; then
            echo -e "${YELLOW}[WARNING] SIGTERM gönderiliyor...${NC}"
            kill -TERM $WAI_PID 2>/dev/null
            if [ ! -z "$WAI_CHILDREN" ]; then
                for child in $WAI_CHILDREN; do
                    kill -TERM $child 2>/dev/null
                done
            fi
            sleep 2
        fi
        
        # Hala çalışıyorsa SIGKILL gönder
        if ps -p $WAI_PID > /dev/null 2>&1; then
            echo -e "${RED}[WARNING] WAI ve alt process'ler zorla kapatılıyor...${NC}"
            kill -KILL $WAI_PID 2>/dev/null
            if [ ! -z "$WAI_CHILDREN" ]; then
                for child in $WAI_CHILDREN; do
                    kill -KILL $child 2>/dev/null
                done
            fi
        fi
        
        # ML process'lerini temizle
        if [ ! -z "$ML_PIDS" ]; then
            echo -e "${YELLOW}[INFO] ML client process'leri temizleniyor...${NC}"
            for mlpid in $ML_PIDS; do
                if ps -p $mlpid > /dev/null 2>&1; then
                    kill -KILL $mlpid 2>/dev/null
                fi
            done
        fi
        
        wait $WAI_PID 2>/dev/null
    fi
    
    # Temp dosyasını sil
    rm -f $LOG_FILE
    
    echo -e "${GREEN}[INFO] Temizlik tamamlandı${NC}"
    exit 0
}

# CTRL+C için trap ayarla
trap cleanup SIGINT SIGTERM

# WAI process'ini başlat
start_wai() {
    echo -e "${GREEN}[INFO] WAI başlatılıyor: $WAI_COMMAND${NC}"
    echo -e "${GREEN}[INFO] Zaman: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    
    # WAI komutunu arka planda çalıştır ve çıktıyı log dosyasına yaz
    $WAI_COMMAND >> $LOG_FILE 2>&1 &
    WAI_PID=$!
    
    echo -e "${BLUE}[INFO] WAI Process ID: $WAI_PID${NC}"
    
    # Process'in başlaması için bekle
    sleep 2
    
    if ! ps -p $WAI_PID > /dev/null; then
        echo -e "${RED}[ERROR] WAI başlatılamadı!${NC}"
        return 1
    fi
    
    # Çıktıyı ekrana yönlendir (append mode ile)
    tail -F $LOG_FILE 2>/dev/null &
    TAIL_PID=$!
    
    return 0
}

# WAI process'ini durdur
stop_wai() {
    echo -e "${YELLOW}[INFO] WAI durduruluyor (PID: $WAI_PID)...${NC}"
    
    # Önce tail process'ini durdur
    if [ ! -z "$TAIL_PID" ] && ps -p $TAIL_PID > /dev/null 2>&1; then
        kill -KILL $TAIL_PID 2>/dev/null
        TAIL_PID=""
    fi
    
    # Process hala var mı kontrol et
    if ! ps -p $WAI_PID > /dev/null 2>&1; then
        echo -e "${GREEN}[INFO] WAI process zaten sonlanmış${NC}"
        return 0
    fi
    
    # WAI'nin tüm alt process'lerini bul
    WAI_CHILDREN=$(pgrep -P $WAI_PID)
    
    # ML client process'lerini de bul (wombo cache altındakiler)
    ML_PIDS=$(ps aux | grep -E "wombo.*ml-clients" | grep -v grep | awk '{print $2}' | grep -v "^$\$")
    
    echo -e "${YELLOW}[INFO] İlgili process'ler bulunuyor...${NC}"
    
    # Önce SIGINT (CTRL+C simülasyonu) gönder
    kill -INT $WAI_PID 2>/dev/null
    
    # Alt process'lere de SIGINT gönder
    if [ ! -z "$WAI_CHILDREN" ]; then
        for child in $WAI_CHILDREN; do
            kill -INT $child 2>/dev/null
        done
    fi
    
    # 5 saniye bekle
    for i in {1..5}; do
        if ! ps -p $WAI_PID > /dev/null 2>&1; then
            echo -e "${GREEN}[INFO] WAI başarıyla durduruldu${NC}"
            # ML process'lerini temizle
            if [ ! -z "$ML_PIDS" ]; then
                for mlpid in $ML_PIDS; do
                    if ps -p $mlpid > /dev/null 2>&1; then
                        kill -KILL $mlpid 2>/dev/null
                    fi
                done
            fi
            return 0
        fi
        sleep 1
    done
    
    # Hala çalışıyorsa SIGTERM gönder
    echo -e "${YELLOW}[WARNING] WAI normal yollarla kapanmadı, SIGTERM gönderiliyor...${NC}"
    kill -TERM $WAI_PID 2>/dev/null
    
    if [ ! -z "$WAI_CHILDREN" ]; then
        for child in $WAI_CHILDREN; do
            kill -TERM $child 2>/dev/null
        done
    fi
    
    # 3 saniye daha bekle
    for i in {1..3}; do
        if ! ps -p $WAI_PID > /dev/null 2>&1; then
            echo -e "${GREEN}[INFO] WAI SIGTERM ile durduruldu${NC}"
            # ML process'lerini temizle
            if [ ! -z "$ML_PIDS" ]; then
                for mlpid in $ML_PIDS; do
                    if ps -p $mlpid > /dev/null 2>&1; then
                        kill -KILL $mlpid 2>/dev/null
                    fi
                done
            fi
            return 0
        fi
        sleep 1
    done
    
    # Hala çalışıyorsa SIGKILL gönder
    echo -e "${RED}[WARNING] WAI ve ilgili process'ler zorla kapatılıyor...${NC}"
    
    # Ana process'i öldür
    kill -KILL $WAI_PID 2>/dev/null
    
    # Tüm alt process'leri öldür
    if [ ! -z "$WAI_CHILDREN" ]; then
        for child in $WAI_CHILDREN; do
            kill -KILL $child 2>/dev/null
        done
    fi
    
    # ML process'lerini kesinlikle temizle
    if [ ! -z "$ML_PIDS" ]; then
        echo -e "${YELLOW}[INFO] ML client process'leri temizleniyor...${NC}"
        for mlpid in $ML_PIDS; do
            if ps -p $mlpid > /dev/null 2>&1; then
                kill -KILL $mlpid 2>/dev/null
            fi
        done
    fi
    
    wait $WAI_PID 2>/dev/null
    
    echo -e "${GREEN}[INFO] WAI process ve tüm alt process'ler temizlendi${NC}"
    return 0
}

# Log kontrolü ve yeniden başlatma
monitor_wai() {
    local last_model_loading_time=0
    local last_earning_time=$(date +%s)
    local last_earning_count=0
    local current_time
    local time_diff
    local cuda_error_detected=0
    local total_earned=0
    local session_start_coins=0
    local session_coins_set=0
    
    while true; do
        # Process hala çalışıyor mu kontrol et
        if ! ps -p $WAI_PID > /dev/null 2>&1; then
            echo -e "${RED}[ERROR] WAI process beklenmedik şekilde sonlandı! Yeniden başlatılıyor...${NC}"
            sleep 2
            return 1
        fi
        
        current_time=$(date +%s)
        
        # Son satırları kontrol et
        if [ -f "$LOG_FILE" ]; then
            # CUDA/Vulkan hatası kontrolü
            if grep -q "Unable to load NVIDIA GPU on CUDA" $LOG_FILE || grep -q "Falling back to Vulkan backend" $LOG_FILE; then
                if [ $cuda_error_detected -eq 0 ]; then
                    cuda_error_detected=1
                    echo -e "${RED}[ERROR] CUDA yüklenemedi, Vulkan'a geçildi! 10 saniye sonra yeniden başlatılıyor...${NC}"
                    sleep 10
                    return 1
                fi
            fi
            
            # Model loading kontrolü
            if grep -q "Model loading" $LOG_FILE && ! grep -q "Model loading completed" $LOG_FILE; then
                if [ $last_model_loading_time -eq 0 ]; then
                    last_model_loading_time=$current_time
                    echo -e "${YELLOW}[INFO] Model yükleniyor...${NC}"
                else
                    time_diff=$((current_time - last_model_loading_time))
                    if [ $time_diff -ge $TIMEOUT_MODEL_LOADING ]; then
                        echo -e "${RED}[WARNING] Model loading aşamasında $TIMEOUT_MODEL_LOADING saniyedir takılı! Yeniden başlatılıyor...${NC}"
                        return 1
                    fi
                fi
            elif grep -q "Model loading completed" $LOG_FILE; then
                if [ $last_model_loading_time -ne 0 ]; then
                    echo -e "${GREEN}[INFO] Model başarıyla yüklendi${NC}"
                    last_model_loading_time=0
                fi
            fi
            
            # İlk coin miktarını al (session başlangıcı)
            if [ $session_coins_set -eq 0 ]; then
                initial_coins_line=$(grep "You have" $LOG_FILE | head -1)
                if [ ! -z "$initial_coins_line" ]; then
                    session_start_coins=$(echo "$initial_coins_line" | sed -n 's/.*You have \([0-9]\+\) w\.ai coins.*/\1/p')
                    if [ ! -z "$session_start_coins" ]; then
                        session_coins_set=1
                        echo -e "${BLUE}[INFO] Başlangıç coin: $session_start_coins${NC}"
                    fi
                fi
            fi
            
            # Earning kontrolü - kaç tane earning mesajı var
            current_earning_count=$(grep -c "You earned" $LOG_FILE)
            
            # Yeni bir earning mesajı geldi mi?
            if [ "$current_earning_count" -gt "$last_earning_count" ]; then
                # Son earning mesajını al
                last_earning_line=$(grep "You earned" $LOG_FILE | tail -1)
                
                # "You earned XX w.ai coins" formatından XX'i çıkar
                earned_amount=$(echo "$last_earning_line" | sed -n 's/.*You earned \([0-9]\+\) w\.ai coin.*/\1/p')
                
                if [ ! -z "$earned_amount" ]; then
                    # Toplam kazancı güncelle
                    total_earned=$((total_earned + earned_amount))
                    echo -e "${GREEN}[SESSION] Bu oturumda toplam kazanç: $total_earned coin (Son: $earned_amount)${NC}"
                    
                    # YENİ earning gördük, zamanı SIFIRLA
                    last_earning_time=$current_time
                    last_earning_count=$current_earning_count
                    
                    # Düşük kazanç kontrolü
                    if [ "$earned_amount" -lt "$MIN_EARNING_THRESHOLD" ]; then
                        echo -e "${RED}[WARNING] Düşük kazanç tespit edildi ($earned_amount < $MIN_EARNING_THRESHOLD)! Yeniden başlatılıyor...${NC}"
                        return 1
                    fi
                fi
            fi
            
            # Earning timeout kontrolü
            time_diff=$((current_time - last_earning_time))
            if [ $time_diff -ge $TIMEOUT_EARNING ]; then
                echo -e "${RED}[WARNING] $TIMEOUT_EARNING saniyedir ($time_diff saniye) yeni kazanç yok! Yeniden başlatılıyor...${NC}"
                echo -e "${YELLOW}[DEBUG] Son earning zamanı: $(date -d @$last_earning_time '+%H:%M:%S')${NC}"
                echo -e "${YELLOW}[DEBUG] Şu anki zaman: $(date -d @$current_time '+%H:%M:%S')${NC}"
                return 1
            fi
        fi
        
        # 5 saniye bekle ve tekrar kontrol et
        sleep 5
    done
}

# Ana döngü
main() {
    local restart_count=0
    
    # Script başlangıcında log dosyasını bir kez temizle
    > $LOG_FILE
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}   WAI GPU Monitor Script Başlatıldı    ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${BLUE}GPU Sayısı: $GPU_COUNT${NC}"
    echo -e "${BLUE}Min Kazanç Eşiği: $MIN_EARNING_THRESHOLD coin${NC}"
    echo -e "${BLUE}Model Loading Timeout: $TIMEOUT_MODEL_LOADING saniye${NC}"
    echo -e "${BLUE}Earning Timeout: $TIMEOUT_EARNING saniye${NC}"
    echo -e "${GREEN}========================================${NC}\n"
    
    while true; do
        # WAI'yi başlat
        if ! start_wai; then
            echo -e "${RED}[ERROR] WAI başlatılamadı, 10 saniye sonra tekrar denenecek...${NC}"
            sleep 10
            continue
        fi
        
        restart_count=$((restart_count + 1))
        if [ $restart_count -gt 1 ]; then
            echo -e "${YELLOW}[INFO] Toplam yeniden başlatma sayısı: $((restart_count - 1))${NC}"
        fi
        
        # Monitör et
        monitor_wai
        
        # Monitör fonksiyonu döndüyse, restart gerekiyor
        stop_wai
        
        echo -e "${YELLOW}[INFO] 5 saniye sonra yeniden başlatılacak...${NC}"
        echo -e "${YELLOW}========================================${NC}\n"
        sleep 5
    done
}

# Script'i başlat
main