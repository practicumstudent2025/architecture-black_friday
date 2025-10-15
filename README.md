# MongoDB Sharding with Replication and Redis Caching Setup

## Архитектура

Данный проект реализует полную архитектуру MongoDB с шардированием, репликацией и Redis кешированием для максимальной производительности и отказоустойчивости:

- **Config Server**: Хранит метаданные шардирования (1 реплика)
- **MongoDB Router (mongos)**: Маршрутизирует запросы к шардам
- **Shard 1**: 3 реплики (1 primary + 2 secondary)
- **Shard 2**: 3 реплики (1 primary + 2 secondary)
- **Redis Cache**: Кеширование запросов для ускорения работы
- **FastAPI Application**: Подключается к mongos и Redis

## Запуск проекта

```bash
docker compose up -d
```

## Настройка репликации, шардирования и кеширования

### 1. Ожидание готовности сервисов

Дождитесь полного запуска всех контейнеров (включая Redis):

```bash
docker compose ps
```

Должно быть запущено 10 контейнеров:
- config1, mongos, pymongo_api
- shard1-primary, shard1-secondary1, shard1-secondary2
- shard2-primary, shard2-secondary1, shard2-secondary2
- redis

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

### Проверка кеширования Redis

**Статус Redis:**
```bash
docker compose exec redis redis-cli info stats | grep -E "(keyspace_hits|keyspace_misses)"
```

**Проверка кеширования через API:**
```bash
curl http://localhost:8080/
```

Должно показать `"cache_enabled": true`

### Проверка через API

```bash
curl http://localhost:8080/
curl http://localhost:8080/helloDoc/count
```

## Тестирование производительности кеширования

### Создание тестовых пользователей

```bash
curl -X POST http://localhost:8080/helloDoc/users -H "Content-Type: application/json" -d '{"name": "Test User 1", "age": 25}'
curl -X POST http://localhost:8080/helloDoc/users -H "Content-Type: application/json" -d '{"name": "Test User 2", "age": 30}'
```

### Тестирование скорости запросов

**Первый запрос (без кеша):**
```bash
time curl -s http://localhost:8080/helloDoc/users
```

**Повторные запросы (с кешем):**
```bash
time curl -s http://localhost:8080/helloDoc/users
time curl -s http://localhost:8080/helloDoc/users
```

**Ожидаемый результат:** Повторные запросы должны выполняться значительно быстрее (в 10-50 раз).

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

### Тестирование отказоустойчивости Redis

1. Остановите Redis:
```bash
docker compose stop redis
```

2. Проверьте, что приложение продолжает работать (без кеширования):
```bash
curl http://localhost:8080/
```

Должно показать `"cache_enabled": false`

3. Восстановите Redis:
```bash
docker compose start redis
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
sharding-repl-cache/
├── compose.yaml          # Конфигурация Docker Compose с Redis
├── README.md            # Данная инструкция
├── api_app/             # FastAPI приложение
│   ├── app.py
│   └── Dockerfile
└── scripts/             # Скрипты инициализации
    └── mongo-init.sh
```

## Преимущества архитектуры

1. **Шардирование**: Распределение данных по нескольким серверам для повышения производительности
2. **Репликация**: Обеспечение отказоустойчивости и доступности данных (6 реплик)
3. **Кеширование**: Ускорение запросов до 50x с помощью Redis
4. **Автоматический failover**: При отказе primary реплики, secondary автоматически становится primary
5. **Горизонтальное масштабирование**: Возможность добавления новых шардов и реплик
6. **Высокая производительность**: Комбинация всех трех технологий обеспечивает максимальную скорость и надежность

## API Endpoints

- `GET /` - Статус системы (включая информацию о кешировании)
- `GET /helloDoc/count` - Количество документов в коллекции
- `GET /helloDoc/users` - Список пользователей (с кешированием)
- `POST /helloDoc/users` - Создание нового пользователя
- `GET /helloDoc/users/{name}` - Получение пользователя по имени

## Мониторинг

### Статистика Redis
```bash
docker compose exec redis redis-cli info stats
```

### Статус MongoDB
```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status()
EOF
```

### Логи приложения
```bash
docker compose logs pymongo_api
```

### Логи Redis
```bash
docker compose logs redis
```