#!/bin/bash

# Устанавливаем переменные для авторизации и адреса реестра
REGISTRY_URL="https://registry.local:443"
AUTH="Authorization: Basic $(echo -n 'admin:admin' | base64)"

# Получаем список репозиториев
REPOS=$(curl -s -H "$AUTH" "$REGISTRY_URL/v2/_catalog" | jq -r '.repositories[]')
echo "found $REPOS"

# Перебираем все репозитории
for REPO in $REPOS; do
  # Получаем список тегов для каждого репозитория
  TAGS=$(curl -s -H "$AUTH" "$REGISTRY_URL/v2/$REPO/tags/list" | jq -r '.tags[]')
  echo "tags: $TAGS"

  # Перебираем все теги для каждого репозитория
  for TAG in $TAGS; do
    # Получаем digest для каждого тега
    DIGEST=$(curl -s -I -H "$AUTH" "$REGISTRY_URL/v2/$REPO/manifests/$TAG" | grep Docker-Content-Digest | awk '{print $2}' | tr -d '\r')
    echo "tag $TAG digests: $DIGEST"

    # Удаляем манифест по digest
    curl -s -X DELETE -H "$AUTH" "$REGISTRY_URL/v2/$REPO/manifests/$DIGEST"
  done
done

# Запускаем команду garbage collection для очистки блобов
curl -X POST -H "$AUTH" "$REGISTRY_URL/admin/garbage-collect"

