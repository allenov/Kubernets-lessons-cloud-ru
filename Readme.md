# Evolution Artifact Registry

Сервис Artifact Registry позволяет хранить и распространять артефакты: Docker-образы, Helm-чарты, Deb-пакеты, RPM-пакеты и Generic-файлы.
Отдельного типа реестров для Helm нет, однако начиная Helm 3.8+ OCI-совместимые, то есть их можно хранить в рамках Docker реестров.

### Базовое использование

 Для того, чтобы начать использовать Docker-реестр воспользуйтесь [Быстрым стартом](https://cloud.ru/docs/artifact-registry-evolution/ug/topics/quickstart)
1) Создайте Docker-реестр
2) Создайте себе пару ключей доступа от личного аккаунта или от сервисного аккаунта
3) Пройдите аутентификацию для вашего нового реестра

```bash
docker login <you_registry>.cr.cloud.ru -u <key_id> -p <key_secret>
```

теперь соберем наше тестовое приложение c эндпойнтом /hello

```bash
docker build --platform linux/amd64 -t <you_registry>.cr.cloud.ru/hello_server .
```

и запушим его

```bash
docker push <you_registry>.cr.cloud.ru/hello_server   
```

Теперь поднимем в kubernetes-кластере под с нашим приложением.
Для этого сначала создадим namespace, а далее секреты для нашего docker-реестра

```bash
kubectl create namespace hello-app
```

```bash
kubectl create secret docker-registry my-registry-secret \
  --docker-server=<you_registry>.cr.cloud.ru \
  --docker-username=myuser \
  --docker-password=mypasword \
  --namespace=hello-app
```

Затем создадим под с нашим приложением:

```bash
kubectl run hello-app \
  --image=<you_registry>.cr.cloud.ru/hello_server:latest \
  --restart=Never \
  --namespace=hello-app \
  --image-pull-secrets=my-registry-secret
```

```bash
kubectl run hello-app \
  --image=<you_registry>.cr.cloud.ru/hello_server:latest \
  --restart=Never \
  --namespace=hello-app \
  --overrides='
{
  "apiVersion": "v1",
  "spec": {
    "imagePullSecrets": [
      {
        "name": "my-registry-secret"
      }
    ]
  }
}'
```
Проверяем, что образ успешно спуллился и под поднялся

```bash
kubectl get pods --namespace hello-app
```

После завершения работы удалим namespace

```bash
kubectl delete namespace hello-app
```

### Работа с helm

Helm — пакетный менеджер для Kubernetes.
Зачем нужен:
- Упрощает деплой сложных приложений
- Шаблонизирует YAML-манифесты
- Версионирует релизы
- Позволяет откатывать изменения
- Хранит чарты в репозиториях

Создадим helm-чарт для нашего приложения 
```bash
mkdir -p helm

helm create helm/hello-app
```

Удалим стандартные шаблоны и values
```helm
# Удаляем стандартные шаблоны, которые нам не нужны
rm -rf helm/templates/*
rm helm/values.yaml
```

Минимальные чарты сделаем с таким содержимым

helm/Chart.yaml
```yaml
apiVersion: v2
name: hello-app
description: A simple Go Hello application Helm chart
type: application
version: 0.1.0
appVersion: "1.0.0"
```

helm/values.yaml
```bash
name: hello-app

# Образ
image:
  repository: <you_registry>.cr.cloud.ru/hello_server
  tag: latest
  pullPolicy: IfNotPresent

# Креды для registry
registry:
  createSecret: true
  name: registry-creds
  server: <you_registry>.cr.cloud.ru
  username: ""
  password: ""
  email: ""

# Порты
service:
  port: 8080
  targetPort: 8080

# Ресурсы
resources:
  limits:
    cpu: 100m
    memory: 128Mi
  requests:
    cpu: 50m
    memory: 64Mi

replicaCount: 1
```

helm/templates/secret.yaml
```yaml
{{- if .Values.registry.createSecret }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ .Values.registry.name }}
type: kubernetes.io/dockerconfigjson
stringData:
  .dockerconfigjson: |
    {
      "auths": {
        "{{ .Values.registry.server }}": {
          "auth": "{{ printf "%s:%s" .Values.registry.username .Values.registry.password | b64enc }}"
        }
      }
    }
  {{- end }}
```

helm/templates/deployment.yaml
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-{{ .Values.name }}
  labels:
    app: {{ .Release.Name }}-{{ .Values.name }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .Release.Name }}-{{ .Values.name }}
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}-{{ .Values.name }}
    spec:
      {{- if .Values.registry.createSecret }}
      imagePullSecrets:
          - name: {{ .Values.registry.name }}
      {{- end }}
      containers:
        - name: {{ .Values.name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.service.targetPort }}
          resources:
            limits:
              cpu: {{ .Values.resources.limits.cpu }}
              memory: {{ .Values.resources.limits.memory }}
            requests:
              cpu: {{ .Values.resources.requests.cpu }}
              memory: {{ .Values.resources.requests.memory }}
```

helm/templates/service.yaml
```bash
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-{{ .Values.name }}
  labels:
    app: {{ .Release.Name }}-{{ .Values.name }}
spec:
  type: ClusterIP
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
      protocol: TCP
  selector:
    app: {{ .Release.Name }}-{{ .Values.name }}
```

И наконец применим наш helm-чарт

```bash
helm install api helm \       
  --namespace hello-app \
  --create-namespace \
  --set registry.username=... \
  --set registry.password=...
  ```

убедитесь, что правки применились в кластере и под действительно создался. 
Теперь упакуем наш helm-чарт в tgz и запушим в реестр

```bash
helm package helm
```
эта команда создаст файл hello-app-0.1.0.tgz


запушим наш helm-чарт
```bash
helm push hello-app-0.1.0.tgz oci://<you_registry>.cr.cloud.ru/hello-app-helm   
```

убедитесь в веб-интерфейсе, что этот артефакт появился