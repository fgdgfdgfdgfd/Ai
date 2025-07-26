#!/bin/bash

# Проверяем, установлен ли Docker
if ! command -v docker &> /dev/null; then
  echo "Docker не установлен. Пожалуйста, установите Docker перед запуском."
  exit 1
fi

# Запускаем контейнер с моделью
docker run --rm -d \
  --name ollama-model \
  -p 5000:5000 \
  ollama/ollama:latest

# Ожидаем несколько секунд, чтобы контейнер успел запуститься
sleep 5

# Проверяем, доступна ли модель
curl -s http://localhost:5000/health | grep "OK" &> /dev/null
if [ $? -eq 0 ]; then
  echo "Модель успешно запущена и доступна по адресу http://localhost:5000"
else
  echo "Не удалось запустить модель. Пожалуйста, проверьте логи контейнера."
  exit 1
fi
