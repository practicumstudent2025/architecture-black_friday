# MongoDB Sharding Setup

Этот проект реализует архитектуру шардирования MongoDB с двумя шардами для повышения производительности.

## Архитектура

- **Config Server**: Хранит метаданные о шардах
- **MongoDB Router (mongos)**: Маршрутизирует запросы к шардам
- **Shard 1**: Первый шард для части данных
- **Shard 2**: Второй шард для части данных
- **FastAPI Application**: Подключается к MongoDB через Router

## Запуск системы

```bash
# Запуск всех сервисов
docker compose up -d

# Проверка статуса контейнеров
docker compose ps
```

## Инициализация шардирования

### Шаг 1: Инициализация Config Server

```bash
# Инициализация replica set для Config Server
docker compose exec -T config1 mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [
    { _id: 0, host: "config1:27017" }
  ]
})
EOF
```

### Шаг 2: Инициализация Shard 1

```bash
# Инициализация replica set для Shard 1
docker compose exec -T shard1 mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: "shard1ReplSet",
  members: [
    { _id: 0, host: "shard1:27017" }
  ]
})
EOF
```

### Шаг 3: Инициализация Shard 2

```bash
# Инициализация replica set для Shard 2
docker compose exec -T shard2 mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: "shard2ReplSet",
  members: [
    { _id: 0, host: "shard2:27017" }
  ]
})
EOF
```

### Шаг 4: Добавление шардов в кластер

```bash
# Добавление Shard 1 в кластер
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1ReplSet/shard1:27017")
EOF

# Добавление Shard 2 в кластер
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard2ReplSet/shard2:27017")
EOF
```

### Шаг 5: Включение шардирования для базы данных

```bash
# Включение шардирования для базы данных somedb
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb")
EOF
```

### Шаг 6: Настройка шардирования для коллекции

```bash
# Настройка шардирования для коллекции helloDoc по полю _id
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.shardCollection("somedb.helloDoc", { "_id": "hashed" })
EOF
```

## Заполнение данными

### Создание тестовых данных

```bash
# Создание 1000 документов в коллекции helloDoc
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
for (let i = 1; i <= 1000; i++) {
  db.helloDoc.insertOne({
    _id: i,
    name: "Document " + i,
    value: Math.random() * 100,
    timestamp: new Date()
  })
}
EOF
```

## Проверка шардирования

### Проверка статуса кластера

```bash
# Проверка статуса шардирования
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status()
EOF
```

### Проверка распределения данных

```bash
# Проверка количества документов в Shard 1
docker compose exec -T shard1 mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

# Проверка количества документов в Shard 2
docker compose exec -T shard2 mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

### Проверка через Router

```bash
# Проверка общего количества документов через Router
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

## Тестирование приложения

### Запуск FastAPI приложения

```bash
# Приложение доступно по адресу: http://localhost:8080
curl http://localhost:8080/health
```

### Доступные эндпоинты

- `GET /health` - Проверка состояния приложения
- `GET /users` - Получение списка пользователей
- `POST /users` - Создание нового пользователя

## Мониторинг

### Проверка логов

```bash
# Логи всех сервисов
docker compose logs

# Логи конкретного сервиса
docker compose logs mongos
docker compose logs shard1
docker compose logs shard2
```

### Проверка производительности

```bash
# Статистика по шардам
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.getBalancerState()
sh.isBalancerRunning()
EOF
```

## Остановка системы

```bash
# Остановка всех сервисов
docker compose down

# Остановка с удалением volumes (ВНИМАНИЕ: удалит все данные!)
docker compose down -v
```

## Полезные команды

### Подключение к MongoDB

```bash
# Подключение к Router (mongos)
docker compose exec -it mongos mongosh --port 27017

# Подключение к Config Server
docker compose exec -it config1 mongosh --port 27017

# Подключение к Shard 1
docker compose exec -it shard1 mongosh --port 27017

# Подключение к Shard 2
docker compose exec -it shard2 mongosh --port 27017
```

### Проверка replica sets

```bash
# Проверка статуса Config Server replica set
docker compose exec -T config1 mongosh --port 27017 --quiet <<EOF
rs.status()
EOF

# Проверка статуса Shard 1 replica set
docker compose exec -T shard1 mongosh --port 27017 --quiet <<EOF
rs.status()
EOF

# Проверка статуса Shard 2 replica set
docker compose exec -T shard2 mongosh --port 27017 --quiet <<EOF
rs.status()
EOF
```

## Troubleshooting

### Если шарды не добавляются

1. Убедитесь, что replica sets инициализированы
2. Проверьте, что mongos может подключиться к шардам
3. Проверьте логи: `docker compose logs mongos`

### Если данные не распределяются

1. Убедитесь, что шардирование включено для базы данных
2. Проверьте, что коллекция зашардирована
3. Проверьте статус балансировщика

### Если приложение не подключается

1. Убедитесь, что mongos запущен и доступен
2. Проверьте переменные окружения в compose.yaml
3. Проверьте логи приложения: `docker compose logs pymongo_api`