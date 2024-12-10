## Пример реализации API Gateway на базе Istio, Gateway API.

### Маршуртизация
- gateway.yaml - создаст инстанс Envoy в istio-ingress
- httpRoute.yaml - основная маршрутизация
- serviceEntry.yaml - для маршрута ко внешнему сервису
- service.yaml

### circuit-breaker:
- destinationRule-circuit-breaker.yaml

### аудит:
- envoyFilter-accesslog.yaml
- telemetry.yaml

### Cache:
- envoyFilter-cache.yaml

### Rate-limit:
- envoyFilter-rate-limit.yaml

### Пример запросов
- узнать порт k8s.
для gatewayAPI:
`kubectl get svc/central-api-gateway-istio -n istio-ingress`
для istio ingress:
`kubectl get svc/istio-ingress -n istio-ingress`

- прописать в  hosts домены demo-gw.local, linux.local

- вызов
`curl -v demo-gw.local:31880/echo/v1/` 
cb: `for i in {1..10}; do curl -v demo-gw.local:30370/echo/v1/500; done`

#### Backend 
в качестве backend может выступать nginx с конфигурацией:
```
events {}

http {
    access_log /dev/stdout;
    error_log /dev/stderr warn;


    server {
        listen 80;

        location /echo{
            add_header Cache-Control "public, max-age=60";
            default_type text/plain;
            return 200 "Echo response\n";
        }
        location /echo/500{
            default_type text/plain;
            return 500 "Echo 500 response\n";
        }
    }
}
```

