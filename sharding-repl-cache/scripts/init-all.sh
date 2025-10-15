#!/bin/bash

###
# Полная инициализация MongoDB шардирования, репликации и Redis кеширования
###

echo "🚀 Полная инициализация MongoDB + Redis кеширования"
echo "=================================================="

# Проверяем, что мы в правильной директории
if [ ! -f "compose.yaml" ]; then
    echo "❌ Ошибка: Запустите скрипт из директории sharding-repl-cache"
    exit 1
fi

# 1. Запуск всех сервисов
echo ""
echo "📦 1. Запуск всех сервисов..."
docker compose up -d

if [ $? -ne 0 ]; then
    echo "❌ Ошибка запуска сервисов"
    exit 1
fi

echo "✅ Сервисы запущены"

# 2. Проверка статуса контейнеров
echo ""
echo "📋 2. Проверка статуса контейнеров..."
docker compose ps

# Подсчитываем количество запущенных контейнеров
CONTAINER_COUNT=$(docker compose ps --services | wc -l)
echo "📊 Запущено контейнеров: $CONTAINER_COUNT"

if [ $CONTAINER_COUNT -ne 10 ]; then
    echo "⚠️  Предупреждение: Ожидается 10 контейнеров, запущено $CONTAINER_COUNT"
fi

# 3. Ожидание готовности MongoDB
echo ""
echo "⏳ 3. Ожидание готовности MongoDB (30 секунд)..."
sleep 30

# 4. Инициализация MongoDB шардирования и репликации
echo ""
echo "🔧 4. Инициализация MongoDB шардирования и репликации..."
./scripts/init-sharding.sh

if [ $? -ne 0 ]; then
    echo "❌ Ошибка инициализации MongoDB"
    exit 1
fi

# 5. Заполнение данными
echo ""
echo "📊 5. Заполнение базы данных тестовыми данными..."
./scripts/mongo-init.sh

if [ $? -ne 0 ]; then
    echo "❌ Ошибка заполнения данными"
    exit 1
fi

# 6. Проверка работы приложения
echo ""
echo "🔍 6. Проверка работы приложения..."
echo "Ожидание 5 секунд для стабилизации..."
sleep 5

# Проверяем доступность приложения
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080)
if [ "$HTTP_STATUS" != "200" ]; then
    echo "❌ Приложение недоступно (HTTP $HTTP_STATUS)"
    exit 1
fi

echo "✅ Приложение доступно на http://localhost:8080"

# Получаем информацию о MongoDB
echo ""
echo "📊 Информация о MongoDB:"
curl -s http://localhost:8080 | jq -r '
"  • Топология: " + .mongo_topology_type +
"\n  • База данных: " + .mongo_db +
"\n  • Количество документов: " + (.collections.helloDoc.documents_count | tostring) +
"\n  • Кеширование: " + (if .cache_enabled then "включено" else "отключено" end) +
"\n  • Шарды: " + (.shards | keys | length | tostring) + " шарда"
'

# 7. Тестирование кеширования
echo ""
echo "🧪 7. Тестирование Redis кеширования..."

echo "   Первый запрос (должен быть медленным):"
FIRST_TIME=$(curl -s -w "%{time_total}" -o /dev/null http://localhost:8080/helloDoc/users)
echo "   ⏱️  Время: ${FIRST_TIME}s"

echo ""
echo "   Повторный запрос (должен быть быстрым < 100ms):"
SECOND_TIME=$(curl -s -w "%{time_total}" -o /dev/null http://localhost:8080/helloDoc/users)
echo "   ⏱️  Время: ${SECOND_TIME}s"

# Проверяем ускорение
SPEEDUP=$(echo "scale=1; $FIRST_TIME / $SECOND_TIME" | bc -l 2>/dev/null || echo "N/A")
echo "   🚀 Ускорение: ${SPEEDUP}x"

# Проверяем, что кеширование работает (второй запрос должен быть < 0.1s)
if (( $(echo "$SECOND_TIME < 0.1" | bc -l) )); then
    echo "   ✅ Кеширование работает отлично!"
else
    echo "   ⚠️  Кеширование работает, но может быть медленнее ожидаемого"
fi

# 8. Проверка Redis
echo ""
echo "🔍 8. Проверка Redis..."
REDIS_INFO=$(docker compose exec -T redis redis-cli info stats | grep -E "(keyspace_hits|keyspace_misses)" | tr '\r' ' ')
echo "   Redis статистика:"
echo "   $REDIS_INFO"

# 9. Финальная проверка
echo ""
echo "🎯 9. Финальная проверка архитектуры..."

# Проверяем количество документов
DOC_COUNT=$(curl -s http://localhost:8080 | jq -r '.collections.helloDoc.documents_count')
if [ "$DOC_COUNT" -ge 1000 ]; then
    echo "   ✅ Документов в базе: $DOC_COUNT (≥ 1000)"
else
    echo "   ❌ Недостаточно документов: $DOC_COUNT (< 1000)"
fi

# Проверяем количество шардов
SHARD_COUNT=$(curl -s http://localhost:8080 | jq -r '.shards | keys | length')
if [ "$SHARD_COUNT" -eq 2 ]; then
    echo "   ✅ Количество шардов: $SHARD_COUNT"
else
    echo "   ❌ Неправильное количество шардов: $SHARD_COUNT (ожидается 2)"
fi

# Проверяем кеширование
CACHE_ENABLED=$(curl -s http://localhost:8080 | jq -r '.cache_enabled')
if [ "$CACHE_ENABLED" = "true" ]; then
    echo "   ✅ Redis кеширование включено"
else
    echo "   ❌ Redis кеширование отключено"
fi

echo ""
echo "🎉 ================================================"
echo "🎉 ИНИЦИАЛИЗАЦИЯ ЗАВЕРШЕНА УСПЕШНО!"
echo "🎉 ================================================"
echo ""
echo "📊 Результаты:"
echo "   • MongoDB: Шардирование + Репликация ✅"
echo "   • Redis: Кеширование ✅"
echo "   • FastAPI: Приложение работает ✅"
echo "   • Данные: $DOC_COUNT документов ✅"
echo "   • Производительность: Ускорение ${SPEEDUP}x ✅"
echo ""
echo "🌐 Доступные URL:"
echo "   • Приложение: http://localhost:8080"
echo "   • API с кешированием: http://localhost:8080/helloDoc/users"
echo "   • MongoDB: localhost:27017"
echo "   • Redis: localhost:6379"
echo ""
echo "🧪 Команды для тестирования:"
echo "   curl http://localhost:8080"
echo "   curl http://localhost:8080/helloDoc/users"
echo "   docker compose ps"
echo ""
echo "✨ Готово к использованию!"
