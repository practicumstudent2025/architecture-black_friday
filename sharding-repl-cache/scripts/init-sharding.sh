#!/bin/bash

###
# Скрипт инициализации MongoDB шардирования и репликации
###

echo "🚀 Начинаем инициализацию MongoDB шардирования и репликации..."

# Проверяем, что все контейнеры запущены
echo "📋 Проверяем статус контейнеров..."
docker compose ps

# Функция проверки готовности MongoDB
wait_for_mongodb() {
    local container_name=$1
    local max_attempts=30
    local attempt=1
    
    echo "⏳ Ожидание готовности MongoDB в контейнере $container_name..."
    
    while [ $attempt -le $max_attempts ]; do
        if docker compose exec -T $container_name mongosh --eval "db.runCommand('ping')" >/dev/null 2>&1; then
            echo "✅ MongoDB в $container_name готов к работе"
            return 0
        fi
        
        echo "   Попытка $attempt/$max_attempts - MongoDB еще не готов, ждем 2 секунды..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo "❌ MongoDB в $container_name не готов после $max_attempts попыток"
    return 1
}

echo ""
echo "⏳ Ожидание готовности всех MongoDB контейнеров..."

# 1. Инициализация Config Server Replica Set
echo ""
echo "🔧 1. Инициализация Config Server Replica Set..."
wait_for_mongodb "config1"

# Проверяем, не инициализирован ли уже Config Server
CONFIG_STATUS=$(docker compose exec -T config1 mongosh --quiet --eval "rs.status().ok" 2>/dev/null || echo "0")
if [ "$CONFIG_STATUS" = "1" ]; then
    echo "✅ Config Server уже инициализирован"
else
    docker compose exec -T config1 mongosh --quiet <<EOF
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [{ _id: 0, host: "config1:27017" }]
})
EOF

    if [ $? -eq 0 ]; then
        echo "✅ Config Server инициализирован успешно"
    else
        echo "❌ Ошибка инициализации Config Server"
        exit 1
    fi
fi

# 2. Инициализация Shard 1 Replica Set
echo ""
echo "🔧 2. Инициализация Shard 1 Replica Set (3 реплики)..."
wait_for_mongodb "shard1-primary"

# Проверяем, не инициализирован ли уже Shard 1
SHARD1_STATUS=$(docker compose exec -T shard1-primary mongosh --quiet --eval "rs.status().ok" 2>/dev/null || echo "0")
if [ "$SHARD1_STATUS" = "1" ]; then
    echo "✅ Shard 1 уже инициализирован"
else
    docker compose exec -T shard1-primary mongosh --quiet <<EOF
rs.initiate({
  _id: "shard1ReplSet",
  members: [
    { _id: 0, host: "shard1-primary:27017" },
    { _id: 1, host: "shard1-secondary1:27017" },
    { _id: 2, host: "shard1-secondary2:27017" }
  ]
})
EOF

    if [ $? -eq 0 ]; then
        echo "✅ Shard 1 инициализирован успешно"
    else
        echo "❌ Ошибка инициализации Shard 1"
        exit 1
    fi
fi

# 3. Инициализация Shard 2 Replica Set
echo ""
echo "🔧 3. Инициализация Shard 2 Replica Set (3 реплики)..."
wait_for_mongodb "shard2-primary"

# Проверяем, не инициализирован ли уже Shard 2
SHARD2_STATUS=$(docker compose exec -T shard2-primary mongosh --quiet --eval "rs.status().ok" 2>/dev/null || echo "0")
if [ "$SHARD2_STATUS" = "1" ]; then
    echo "✅ Shard 2 уже инициализирован"
else
    docker compose exec -T shard2-primary mongosh --quiet <<EOF
rs.initiate({
  _id: "shard2ReplSet",
  members: [
    { _id: 0, host: "shard2-primary:27017" },
    { _id: 1, host: "shard2-secondary1:27017" },
    { _id: 2, host: "shard2-secondary2:27017" }
  ]
})
EOF

    if [ $? -eq 0 ]; then
        echo "✅ Shard 2 инициализирован успешно"
    else
        echo "❌ Ошибка инициализации Shard 2"
        exit 1
    fi
fi

# Ожидание синхронизации реплик
echo ""
echo "⏳ Ожидание 15 секунд для синхронизации реплик..."
sleep 15

# 4. Добавление шардов к mongos
echo ""
echo "🔧 4. Добавление шардов к mongos..."
wait_for_mongodb "mongos"

# Проверяем, добавлены ли уже шарды
SHARD_COUNT=$(docker compose exec -T mongos mongosh --quiet --eval "sh.status().shards.length" 2>/dev/null || echo "0")
if [ "$SHARD_COUNT" -ge 2 ]; then
    echo "✅ Шарды уже добавлены к mongos"
else
    docker compose exec -T mongos mongosh --quiet <<EOF
sh.addShard("shard1ReplSet/shard1-primary:27017")
sh.addShard("shard2ReplSet/shard2-primary:27017")
EOF

    if [ $? -eq 0 ]; then
        echo "✅ Шарды добавлены к mongos успешно"
    else
        echo "❌ Ошибка добавления шардов к mongos"
        exit 1
    fi
fi

# 5. Включение шардирования для базы данных и коллекции
echo ""
echo "🔧 5. Включение шардирования для базы данных и коллекции..."

# Проверяем, включено ли уже шардирование
SHARDING_ENABLED=$(docker compose exec -T mongos mongosh --quiet --eval "sh.status().databases.find(d => d._id === 'somedb') ? 1 : 0" 2>/dev/null || echo "0")
if [ "$SHARDING_ENABLED" = "1" ]; then
    echo "✅ Шардирование уже включено для базы somedb"
else
    docker compose exec -T mongos mongosh --quiet <<EOF
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { "_id": "hashed" })
EOF

    if [ $? -eq 0 ]; then
        echo "✅ Шардирование включено успешно"
    else
        echo "❌ Ошибка включения шардирования"
        exit 1
    fi
fi

# 6. Проверка статуса шардирования
echo ""
echo "🔍 6. Проверка статуса шардирования..."
docker compose exec -T mongos mongosh --quiet <<EOF
sh.status()
EOF

echo ""
echo "🎉 Инициализация MongoDB шардирования и репликации завершена!"
echo ""
echo "📊 Следующие шаги:"
echo "   1. Запустите скрипт заполнения данными: ./scripts/mongo-init.sh"
echo "   2. Проверьте работу приложения: http://localhost:8080"
echo "   3. Протестируйте кеширование: curl http://localhost:8080/helloDoc/users"
