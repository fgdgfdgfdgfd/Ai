#!/bin/bash

# 🚀 ПОЛНАЯ УСТАНОВКА OLLAMA + DOCKER + OPEN WEBUI (32GB диск)

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

echo -e "${PURPLE}🚀 ПОЛНАЯ УСТАНОВКА: Ollama + Docker + Open WebUI${NC}"
echo -e "${PURPLE}====================================================${NC}"
echo "📅 $(date)"
echo ""

# ===============================================
# 1. ПРОВЕРКА СИСТЕМЫ
# ===============================================

log "📊 Проверяем систему..."

# Проверка места на диске
available=$(df / | awk 'NR==2 {print $4}')
available_gb=$((available / 1024 / 1024))
if [ $available_gb -lt 12 ]; then
    error "Недостаточно места! Доступно: ${available_gb}GB, нужно минимум 12GB"
    exit 1
fi
log "✅ Места на диске: ${available_gb}GB - достаточно"

# Проверка архитектуры
ARCH=$(uname -m)
log "Архитектура: $ARCH"

# ===============================================
# 2. УСТАНОВКА ЗАВИСИМОСТЕЙ
# ===============================================

log "📦 Обновляем систему и устанавливаем зависимости..."
sudo apt update -qq
sudo apt install -y curl wget apt-transport-https ca-certificates gnupg lsb-release software-properties-common

# ===============================================
# 3. УСТАНОВКА DOCKER (если нет)
# ===============================================

log "🐳 Проверяем Docker..."

if ! command -v docker &> /dev/null; then
    log "📦 Docker не найден. Загружаем и устанавливаем Docker..."
    
    # Удаляем старые версии
    sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Устанавливаем Docker через официальный скрипт
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh
    
    # Добавляем пользователя в группу docker
    sudo usermod -aG docker $USER
    
    # ИСПРАВЛЕНИЕ: Убираем newgrp, так как он создает subshell
    log "⚠️ Для применения прав docker потребуется перелогиниться после установки"
    
    log "✅ Docker установлен"
else
    warn "Docker уже установлен"
    docker --version
fi

# Проверяем что Docker работает
if sudo systemctl is-active --quiet docker; then
    log "✅ Docker сервис активен"
else
    sudo systemctl start docker
    sudo systemctl enable docker
    log "✅ Docker сервис запущен"
fi

# Проверка работы Docker
log "🔍 Тестируем Docker..."
if sudo docker run --rm hello-world > /dev/null 2>&1; then
    log "✅ Docker работает корректно"
else
    error "❌ Docker не работает"
    exit 1
fi

# ===============================================
# 4. УСТАНОВКА DOCKER COMPOSE
# ===============================================

log "📦 Проверяем Docker Compose..."

if ! docker compose version > /dev/null 2>&1; then
    log "📦 Устанавливаем Docker Compose Plugin..."
    sudo apt update
    sudo apt install -y docker-compose-plugin
fi

log "✅ Docker Compose установлен"
docker compose version 2>/dev/null || true

# ===============================================
# 5. УСТАНОВКА OLLAMA (всегда устанавливаем свежую версию)
# ===============================================

log "🦙 Устанавливаем Ollama..."

# Всегда устанавливаем/обновляем Ollama
log "📦 Загружаем и устанавливаем последнюю версию Ollama..."
curl -fsSL https://ollama.com/install.sh | sh

# Проверка установки Ollama
if command -v ollama &> /dev/null; then
    log "✅ Ollama успешно установлена"
else
    error "❌ Ошибка установки Ollama"
    exit 1
fi

# Запуск Ollama сервера
log "🚀 Запускаем Ollama сервер..."

# Убиваем старые процессы
sudo pkill -f "ollama serve" 2>/dev/null || true
sleep 3

# Создаем systemd сервис для Ollama
log "⚙️ Создаем systemd сервис для Ollama..."
sudo tee /etc/systemd/system/ollama.service > /dev/null <<EOF
[Unit]
Description=Ollama Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
Group=$USER
ExecStart=/usr/local/bin/ollama serve
Environment="HOME=$HOME"
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
Environment="OLLAMA_HOST=0.0.0.0:11434"
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
KillMode=mixed
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ollama.service
sudo systemctl start ollama.service

# Ждем запуска Ollama
log "⏳ Ждем запуска Ollama API..."
for i in {1..60}; do
    if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
        log "✅ Ollama API запущен и отвечает"
        break
    fi
    if [ $i -eq 60 ]; then
        error "❌ Ollama API не запустился за 60 секунд"
        sudo systemctl status ollama.service --no-pager
        exit 1
    fi
    echo -n "."
    sleep 1
done
echo ""

# ===============================================
# 6. ЗАГРУЗКА МОДЕЛЕЙ
# ===============================================

log "🧠 Загружаем оптимизированные модели..."

# Массив моделей для 32GB диска
MODELS=(
    "qwen2:0.5b"           # 352MB - сверхбыстрая
    "llama3.2:1b"          # 1.3GB - качественная малая
    "deepseek-coder:1.3b"  # 1.3GB - для программирования
    "phi3:mini"            # 2.3GB - Microsoft малая
)

total=${#MODELS[@]}
current=0

for model in "${MODELS[@]}"; do
    current=$((current + 1))
    log "📥 [$current/$total] Загружаем модель: $model"
    
    # Проверяем есть ли место
    available=$(df / | awk 'NR==2 {print $4}')
    available_gb=$((available / 1024 / 1024))
    if [ $available_gb -lt 3 ]; then
        warn "❌ Мало места для $model (осталось ${available_gb}GB), пропускаем"
        continue
    fi
    
    # Проверяем не установлена ли уже
    model_name="${model%%:*}"
    if ollama list 2>/dev/null | grep -q "^$model_name"; then
        warn "⚠️ Модель $model уже установлена, пропускаем"
        continue
    fi
    
    # Загружаем модель с таймаутом и перенаправлением stderr
    if timeout 1200 ollama pull "$model" 2>&1; then
        log "✅ Модель $model успешно загружена"
    else
        error "❌ Ошибка загрузки $model (таймаут или сеть)"
        continue
    fi
    
    info "📊 Прогресс: $current/$total моделей обработано"
    sleep 2
done

log "🎉 Загрузка моделей завершена!"

# ===============================================
# 7. УСТАНОВКА OPEN WEBUI
# ===============================================

log "🌐 Устанавливаем Open WebUI..."

# Останавливаем и удаляем старые контейнеры
log "🔄 Очищаем старые установки Open WebUI..."
sudo docker stop open-webui 2>/dev/null || true
sudo docker rm open-webui 2>/dev/null || true
sudo docker stop ollama-webui 2>/dev/null || true
sudo docker rm ollama-webui 2>/dev/null || true

# Создаем том для данных
log "📁 Создаем том для данных WebUI..."
sudo docker volume create open-webui 2>/dev/null || true

# Запускаем Open WebUI
log "🚀 Запускаем Open WebUI контейнер..."

# Генерируем секретный ключ
WEBUI_SECRET_KEY=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)

# Запускаем с --init для правильной обработки сигналов
sudo docker run -d \
    --name open-webui \
    --restart unless-stopped \
    --init \
    -p 3000:8080 \
    --add-host=host.docker.internal:host-gateway \
    -v open-webui:/app/backend/data \
    -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
    -e WEBUI_SECRET_KEY="$WEBUI_SECRET_KEY" \
    -e DEFAULT_USER_ROLE=admin \
    ghcr.io/open-webui/open-webui:main

# Ждем запуска WebUI
log "⏳ Ждем запуска Open WebUI..."
for i in {1..60}; do
    if curl -s http://localhost:3000 >/dev/null 2>&1; then
        log "✅ Open WebUI запущен и доступен"
        break
    fi
    if [ $i -eq 60 ]; then
        error "❌ Open WebUI не запустился за 60 секунд"
        sudo docker logs open-webui --tail 50
        exit 1
    fi
    echo -n "."
    sleep 2
done
echo ""

# Проверка контейнера
if sudo docker ps | grep -q "open-webui"; then
    log "✅ Open WebUI контейнер работает"
else
    error "❌ Open WebUI контейнер не запустился"
    sudo docker logs open-webui --tail 50
    exit 1
fi

# ===============================================
# 8. СОЗДАНИЕ СКРИПТОВ УПРАВЛЕНИЯ
# ===============================================

log "📋 Создаем скрипты управления..."

# Скрипт мониторинга
cat > "$HOME/monitor.sh" << 'MONITOR_EOF'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

while true; do
    clear
    echo -e "${BLUE}🚀 OLLAMA + OPEN WEBUI MONITOR${NC}"
    echo "======================================"
    echo "⏰ $(date)"
    echo ""
    
    echo -e "${YELLOW}📊 СИСТЕМА:${NC}"
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}' 2>/dev/null || echo "N/A")
    echo "CPU: ${CPU_USAGE}%"
    echo "RAM: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
    echo "ДИСК: $(df -h / | awk '/\// {print $3 "/" $2 " (" $5 ")"}')"
    echo ""
    
    echo -e "${YELLOW}🔧 СЕРВИСЫ:${NC}"
    if systemctl is-active --quiet ollama 2>/dev/null; then
        echo -e "Ollama: ${GREEN}✅ РАБОТАЕТ${NC}"
    else
        echo -e "Ollama: ${RED}❌ НЕ РАБОТАЕТ${NC}"
    fi
    
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^open-webui$"; then
        echo -e "Open WebUI: ${GREEN}✅ РАБОТАЕТ${NC}"
    else
        echo -e "Open WebUI: ${RED}❌ НЕ РАБОТАЕТ${NC}"
    fi
    
    if systemctl is-active --quiet docker 2>/dev/null; then
        echo -e "Docker: ${GREEN}✅ РАБОТАЕТ${NC}"
    else
        echo -e "Docker: ${RED}❌ НЕ РАБОТАЕТ${NC}"
    fi
    echo ""
    
    echo -e "${YELLOW}🧠 МОДЕЛИ:${NC}"
    if command -v ollama &> /dev/null; then
        MODEL_COUNT=$(ollama list 2>/dev/null | tail -n +2 | wc -l)
        echo "Загружено: $MODEL_COUNT моделей"
        ollama list 2>/dev/null | tail -n +2 | awk '{print "  • " $1}' | head -5
    else
        echo "Ollama не установлена"
    fi
    echo ""
    
    echo -e "${YELLOW}🌐 ДОСТУП:${NC}"
    echo "Open WebUI: http://localhost:3000"
    echo "Ollama API: http://localhost:11434"
    
    # Проверка доступности
    if curl -s http://localhost:3000 >/dev/null 2>&1; then
        echo -e "WebUI статус: ${GREEN}✅ Доступен${NC}"
    else
        echo -e "WebUI статус: ${RED}❌ Недоступен${NC}"
    fi
    
    if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo -e "API статус: ${GREEN}✅ Доступен${NC}"
    else
        echo -e "API статус: ${RED}❌ Недоступен${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}⚙️ УПРАВЛЕНИЕ:${NC}"
    echo "Ctrl+C - выход из мониторинга"
    echo "sudo systemctl restart ollama - перезапуск Ollama"
    echo "docker restart open-webui - перезапуск WebUI"
    
    sleep 30
done
MONITOR_EOF

chmod +x "$HOME/monitor.sh"

# Скрипт управления сервисами
cat > "$HOME/manage.sh" << 'MANAGE_EOF'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        🚀 OLLAMA + WEBUI MANAGER     ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo "1) 📊 Показать статус"
    echo "2) ▶️  Запустить все сервисы"
    echo "3) ⏹️  Остановить все сервисы"
    echo "4) 🔄 Перезапустить все сервисы"
    echo "5) 🧠 Список моделей"
    echo "6) ➕ Добавить модель"
    echo "7) 🗑️  Удалить модель"
    echo "8) 📊 Запустить мониторинг"
    echo "9) 📋 Показать логи"
    echo "0) ❌ Выход"
    echo ""
    echo -n "Выберите опцию [0-9]: "
}

status_check() {
    echo -e "${BLUE}📊 СТАТУС СИСТЕМЫ${NC}"
    echo "=================="
    
    if systemctl is-active --quiet ollama 2>/dev/null; then
        echo -e "Ollama: ${GREEN}✅ РАБОТАЕТ${NC}"
    else
        echo -e "Ollama: ${RED}❌ НЕ РАБОТАЕТ${NC}"
    fi
    
    if docker ps 2>/dev/null | grep -q "open-webui"; then
        echo -e "WebUI: ${GREEN}✅ РАБОТАЕТ${NC}"
    else
        echo -e "WebUI: ${RED}❌ НЕ РАБОТАЕТ${NC}"
    fi
    
    echo ""
    echo "🌐 Доступ:"
    echo "WebUI: http://localhost:3000"
    echo "API: http://localhost:11434"
    
    echo ""
    echo "📊 Ресурсы:"
    echo "RAM: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
    echo "Диск: $(df -h / | awk '/\// {print $3 "/" $2 " (" $5 ")"}')"
}

start_services() {
    echo -e "${GREEN}▶️ Запуск сервисов...${NC}"
    sudo systemctl start ollama 2>/dev/null
    sudo docker start open-webui 2>/dev/null
    echo "Сервисы запущены"
}

stop_services() {
    echo -e "${RED}⏹️ Остановка сервисов...${NC}"
    sudo systemctl stop ollama 2>/dev/null
    sudo docker stop open-webui 2>/dev/null
    echo "Сервисы остановлены"
}

restart_services() {
    echo -e "${YELLOW}🔄 Перезапуск сервисов...${NC}"
    sudo systemctl restart ollama 2>/dev/null
    sudo docker restart open-webui 2>/dev/null
    sleep 10
    echo "Сервисы перезапущены"
}

while true; do
    show_menu
    read -r choice
    
    case $choice in
        1) status_check; read -p "Нажмите Enter для продолжения..."; ;;
        2) start_services; read -p "Нажмите Enter для продолжения..."; ;;
        3) stop_services; read -p "Нажмите Enter для продолжения..."; ;;
        4) restart_services; read -p "Нажмите Enter для продолжения..."; ;;
        5) ollama list 2>/dev/null || echo "Ollama не запущена"; read -p "Нажмите Enter для продолжения..."; ;;
        6)
            echo -n "Введите название модели для установки: "
            read -r model_name
            if [ -n "$model_name" ]; then
                ollama pull "$model_name" 2>&1
            fi
            read -p "Нажмите Enter для продолжения..."
            ;;
        7)
            ollama list 2>/dev/null || echo "Ollama не запущена"
            echo -n "Введите название модели для удаления: "
            read -r model_name
            if [ -n "$model_name" ]; then
                ollama rm "$model_name" 2>/dev/null || echo "Ошибка удаления"
            fi
            read -p "Нажмите Enter для продолжения..."
            ;;
        8) ~/monitor.sh ;;
        9)
            echo "Выберите логи:"
            echo "1) Ollama"
            echo "2) Open WebUI"
            read -r log_choice
            case $log_choice in
                1) sudo journalctl -u ollama.service -f ;;
                2) sudo docker logs -f open-webui 2>/dev/null || echo "Контейнер не найден" ;;
            esac
            ;;
        0) echo "Выход..."; exit 0 ;;
        *) echo -e "${RED}Неверный выбор!${NC}"; sleep 1 ;;
    esac
done
MANAGE_EOF

chmod +x "$HOME/manage.sh"

# Скрипт автообновления
cat > "$HOME/update.sh" << 'UPDATE_EOF'
#!/bin/bash

echo "🔄 Обновление системы..."

# Обновляем Ollama
echo "📦 Обновляем Ollama..."
curl -fsSL https://ollama.com/install.sh | sh

# Обновляем Open WebUI
echo "🌐 Обновляем Open WebUI..."
sudo docker pull ghcr.io/open-webui/open-webui:main
sudo docker stop open-webui 2>/dev/null
sudo docker rm open-webui 2>/dev/null

# Генерируем новый секретный ключ
WEBUI_SECRET_KEY=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)

sudo docker run -d \
    --name open-webui \
    --restart unless-stopped \
    --init \
    -p 3000:8080 \
    --add-host=host.docker.internal:host-gateway \
    -v open-webui:/app/backend/data \
    -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
    -e WEBUI_SECRET_KEY="$WEBUI_SECRET_KEY" \
    ghcr.io/open-webui/open-webui:main

echo "✅ Обновление завершено!"
UPDATE_EOF

chmod +x "$HOME/update.sh"

# ===============================================
# 9. НАСТРОЙКА АВТОЗАПУСКА
# ===============================================

log "⚙️ Настраиваем автозапуск контейнера..."

# Создаем systemd сервис для автозапуска контейнера
sudo tee /etc/systemd/system/open-webui.service > /dev/null <<EOF
[Unit]
Description=Open WebUI Container
Requires=docker.service
After=docker.service ollama.service
Wants=ollama.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker start open-webui
ExecStop=/usr/bin/docker stop open-webui
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable open-webui.service 2>/dev/null || true

# ===============================================
# 10. ФИНАЛЬНЫЕ ПРОВЕРКИ
# ===============================================

log "🔍 Выполняем финальные проверки..."

# Проверка Ollama API
if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
    log "✅ Ollama API доступен"
else
    error "❌ Ollama API недоступен"
fi

# Проверка Open WebUI
if curl -s http://localhost:3000 >/dev/null 2>&1; then
    log "✅ Open WebUI доступен"
else
    error "❌ Open WebUI недоступен"
fi

# Показ установленных моделей
log "📋 Установленные модели:"
ollama list 2>/dev/null || warn "Не удалось получить список моделей"

# Показ использования ресурсов
log "📊 Использование ресурсов:"
echo "RAM: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
echo "Диск: $(df -h / | awk '/\// {print $3 "/" $2 " (" $5 ")"}')"

# ===============================================
# 11. ЗАВЕРШЕНИЕ
# ===============================================

echo ""
echo -e "${PURPLE}🎉 УСТАНОВКА ПОЛНОСТЬЮ ЗАВЕРШЕНА!${NC}"
echo -e "${PURPLE}=================================${NC}"
echo ""
echo -e "${GREEN}✅ Ollama установлена и запущена${NC}"
echo -e "${GREEN}✅ Docker установлен и настроен${NC}"
echo -e "${GREEN}✅ Open WebUI запущен${NC}"
echo -e "${GREEN}✅ Модели загружены${NC}"
echo -e "${GREEN}✅ Автозапуск настроен${NC}"
echo -e "${GREEN}✅ Скрипты управления созданы${NC}"
echo ""
echo -e "${BLUE}🌐 ДОСТУП К СЕРВИСАМ:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🖥️  Open WebUI:    http://localhost:3000"
echo "🔗 Ollama API:    http://localhost:11434"
echo "📊 Мониторинг:    ~/monitor.sh"
echo "⚙️  Управление:    ~/manage.sh"
echo "🔄 Обновление:    ~/update.sh"
echo ""
echo -e "${BLUE}🔧 ОСНОВНЫЕ КОМАНДЫ:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━"
echo "ollama run qwen2:0.5b              # Запуск чата в терминале"
echo "ollama list                        # Список моделей"
echo "sudo systemctl status ollama       # Статус Ollama"
echo "docker logs open-webui             # Логи WebUI"
echo "./manage.sh                        # Панель управления"
echo "./monitor.sh                       # Мониторинг системы"
echo ""
echo -e "${BLUE}💡 ПОЛЕЗНАЯ ИНФОРМАЦИЯ:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━"
echo "• При первом входе в WebUI создайте аккаунт администратора"
echo "• Все данные WebUI сохраняются в Docker volume 'open-webui'"
echo "• Для добавления новых моделей используйте: ollama pull model_name"
echo "• Логи находятся в: journalctl -u ollama и docker logs"
echo "• Перезагрузка не влияет на работу - все запустится автоматически"
echo ""
log "🚀 Система готова к работе! Откройте http://localhost:3000 в браузере"

# Показать статус сервисов
echo ""
echo -e "${YELLOW}📊 ТЕКУЩИЙ СТАТУС:${NC}"
sudo systemctl status ollama.service --no-pager -l 2>/dev/null || true
echo ""
sudo docker ps --filter name=open-webui 2>/dev/null || true

echo ""
log "🎯 Установка завершена успешно!" 
