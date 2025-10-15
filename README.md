# MongoDB Sharding with Replication Setup

## Архитектура

Данный проект реализует MongoDB шардирование с репликацией для повышения производительности и отказоустойчивости:

- **Config Server**: Хранит метаданные шардирования (1 реплика)
- **MongoDB Router (mongos)**: Маршрутизирует запросы к шардам
- **Shard 1**: 3 реплики (1 primary + 2 secondary)
- **Shard 2**: 3 реплики (1 primary + 2 secondary)
- **FastAPI Application**: Подключается к mongos

## Запуск проекта

```bash
docker compose up -d
```

## Настройка репликации и шардирования

### 1. Ожидание готовности сервисов

Дождитесь полного запуска всех контейнеров:

```bash
docker compose ps
```

### 2. Инициализация Config Server Replica Set

```bash
docker compose exec -T config1 mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [{ _id: 0, host: "config1:27017" }]
})
EOF
```

### 3. Инициализация Shard 1 Replica Set (3 реплики)

```bash
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
```

### 4. Инициализация Shard 2 Replica Set (3 реплики)

```bash
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
```

### 5. Проверка статуса репликации Shard 1

```bash
docker compose exec -T shard1-primary mongosh --port 27017 --quiet <<EOF
rs.status()
EOF
```

### 6. Проверка статуса репликации Shard 2

```bash
docker compose exec -T shard2-primary mongosh --port 27017 --quiet <<EOF
rs.status()
EOF
```

### 7. Добавление шардов в кластер через mongos

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1ReplSet/shard1-primary:27017")
sh.addShard("shard2ReplSet/shard2-primary:27017")
EOF
```

### 8. Включение шардирования для базы данных `somedb`

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb")
EOF
```

### 9. Настройка шардирования для коллекции `helloDoc`

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.shardCollection("somedb.helloDoc", { "_id": "hashed" })
EOF
```

### 10. Создание тестовых данных (1000 документов)

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
for (let i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({
    _id: i,
    name: "User " + i,
    age: Math.floor(Math.random() * 50) + 20
  });
}
EOF
```

## Проверка работы системы

### Проверка статуса шардирования

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status()
EOF
```

### Проверка количества документов в каждом шарде

**Shard 1 (Primary):**
```bash
docker compose exec -T shard1-primary mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

**Shard 2 (Primary):**
```bash
docker compose exec -T shard2-primary mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

**Общее количество через mongos:**
```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

### Проверка репликации

**Проверка репликации Shard 1:**
```bash
docker compose exec -T shard1-secondary1 mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

**Проверка репликации Shard 2:**
```bash
docker compose exec -T shard2-secondary1 mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

### Проверка через API

```bash
curl http://localhost:8080/
curl http://localhost:8080/helloDoc/count
```

## Отказоустойчивость

### Тестирование отказоустойчивости Shard 1

1. Остановите primary реплику Shard 1:
```bash
docker compose stop shard1-primary
```

2. Проверьте, что одна из secondary реплик стала primary:
```bash
docker compose exec -T shard1-secondary1 mongosh --port 27017 --quiet <<EOF
rs.status()
EOF
```

3. Восстановите остановленную реплику:
```bash
docker compose start shard1-primary
```

### Тестирование отказоустойчивости Shard 2

1. Остановите primary реплику Shard 2:
```bash
docker compose stop shard2-primary
```

2. Проверьте, что одна из secondary реплик стала primary:
```bash
docker compose exec -T shard2-secondary1 mongosh --port 27017 --quiet <<EOF
rs.status()
EOF
```

3. Восстановите остановленную реплику:
```bash
docker compose start shard2-primary
```

## Остановка проекта

```bash
docker compose down
```

## Очистка данных

```bash
docker compose down -v
```

## Структура проекта

```
mongo-sharding-repl/
├── compose.yaml          # Конфигурация Docker Compose
├── README.md            # Данная инструкция
├── api_app/             # FastAPI приложение
│   ├── app.py
│   └── Dockerfile
└── scripts/             # Скрипты инициализации
    └── mongo-init.sh
```

## Преимущества архитектуры

1. **Шардирование**: Распределение данных по нескольким серверам для повышения производительности
2. **Репликация**: Обеспечение отказоустойчивости и доступности данных
3. **Автоматический failover**: При отказе primary реплики, secondary автоматически становится primary
4. **Горизонтальное масштабирование**: Возможность добавления новых шардов и реплик