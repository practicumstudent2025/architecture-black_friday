#!/bin/bash

###
# Скрипт инициализации MongoDB шардирования и репликации
###

echo "🚀 Начинаем инициализацию MongoDB шардирования и репликации..."

# Проверяем, что все контейнеры запущены
echo "📋 Проверяем статус контейнеров..."
docker compose ps

echo ""
echo "⏳ Ожидание 10 секунд для полной инициализации MongoDB..."
sleep 10

# 1. Инициализация Config Server Replica Set
echo ""
echo "🔧 1. Инициализация Config Server Replica Set..."
docker compose exec -T config1 mongosh --port 27017 --quiet <<EOF
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

# 2. Инициализация Shard 1 Replica Set
echo ""
echo "🔧 2. Инициализация Shard 1 Replica Set (3 реплики)..."
docker compose exec -T shard1-primary mongosh --port 27017 --quiet <<EOF
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

# 3. Инициализация Shard 2 Replica Set
echo ""
echo "🔧 3. Инициализация Shard 2 Replica Set (3 реплики)..."
docker compose exec -T shard2-primary mongosh --port 27017 --quiet <<EOF
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

# Ожидание синхронизации реплик
echo ""
echo "⏳ Ожидание 15 секунд для синхронизации реплик..."
sleep 15

# 4. Добавление шардов к mongos
echo ""
echo "🔧 4. Добавление шардов к mongos..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1ReplSet/shard1-primary:27017")
sh.addShard("shard2ReplSet/shard2-primary:27017")
EOF

if [ $? -eq 0 ]; then
    echo "✅ Шарды добавлены к mongos успешно"
else
    echo "❌ Ошибка добавления шардов к mongos"
    exit 1
fi

# 5. Включение шардирования для базы данных и коллекции
echo ""
echo "🔧 5. Включение шардирования для базы данных и коллекции..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { "_id": "hashed" })
EOF

if [ $? -eq 0 ]; then
    echo "✅ Шардирование включено успешно"
else
    echo "❌ Ошибка включения шардирования"
    exit 1
fi

# 6. Проверка статуса шардирования
echo ""
echo "🔍 6. Проверка статуса шардирования..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status()
EOF

echo ""
echo "🎉 Инициализация MongoDB шардирования и репликации завершена!"
echo ""
echo "📊 Следующие шаги:"
echo "   1. Запустите скрипт заполнения данными: ./scripts/mongo-init.sh"
echo "   2. Проверьте работу приложения: http://localhost:8080"
echo "   3. Протестируйте кеширование: curl http://localhost:8080/helloDoc/users"
