{{/*
Expand the name of the chart.
*/}}
{{- define "esim-common.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "esim-common.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "esim-common.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "esim-common.labels" -}}
helm.sh/chart: {{ include "esim-common.chart" . }}
{{ include "esim-common.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.global.labels }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "esim-common.selectorLabels" -}}
app.kubernetes.io/name: {{ include "esim-common.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common deployment template
*/}}
{{- define "esim-common.deployment" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.name }}{{- if .Values.global.environment }}-{{ .Values.global.environment }}{{- end }}
  namespace: {{ .Values.global.namespace }}
  labels:
    app: {{ .Values.name }}
    {{- include "esim-common.labels" . | nindent 4 }}
    {{- if .Values.global.istio.enabled }}
    {{- with .Values.global.istio.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- end }}
  annotations:
    {{- if .Values.global.annotations }}
    {{- range $key, $value := .Values.global.annotations }}
    {{ $key }}: {{ tpl $value $ | quote }}
    {{- end }}
    {{- end }}
spec:
  replicas: {{ .Values.replicas | default 1 }}
  revisionHistoryLimit: 3
  selector:
    matchLabels:
      app: {{ .Values.name }}
  template:
    metadata:
      labels:
        app: {{ .Values.name }}
        intent: {{ .Values.name }}
        app.kubernetes.io/instance: observability
        app.kubernetes.io/name: grafana
        {{- include "esim-common.labels" . | nindent 8 }}
        {{- if .Values.global.istio.enabled }}
        {{- with .Values.global.istio.labels }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
        {{- end }}
      annotations:
        reloader.stakater.com/auto: "true"
        configmap.reloader.stakater.com/reload: "{{ .Values.configMapName }}{{- if and .Values.global.configMapSuffix .Values.global.environment }}-{{ .Values.global.environment }}{{- end }}"
        prometheus.io/path: /v1/esim/actuator/prometheus
        prometheus.io/port: "{{ .Values.service.targetPort }}"
        prometheus.io/scheme: http
        prometheus.io/scrape: "true"
        {{- if .Values.global.annotations }}
        {{- range $key, $value := .Values.global.annotations }}
        {{ $key }}: {{ tpl $value $ | quote }}
        {{- end }}
        {{- end }}
        {{- if .Values.global.istio.enabled }}
        {{- with .Values.global.istio.annotations }}
        {{- range $key, $value := . }}
        {{ $key }}: {{ $value | quote }}
        {{- end }}
        {{- end }}
        {{- end }}
    spec:
      {{- include "esim-common.initContainers" . | nindent 6 }}
      {{- if .Values.global.csiVolumes.enabled }}
      serviceAccountName: {{ .Values.global.serviceAccountName }}
      {{- end }}
      {{- if .Values.terminationGracePeriodSeconds }}
      terminationGracePeriodSeconds: {{ .Values.terminationGracePeriodSeconds }}
      {{- end }}
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 1
              podAffinityTerm:
                labelSelector:
                  matchLabels:
                    intent: {{ .Values.name }}
                topologyKey: kubernetes.io/hostname
      nodeSelector:
        {{- toYaml .Values.global.nodeSelector | nindent 8 }}
        {{- if .Values.global.istio.enabled }}
        istio: {{ .Values.global.istio.labels.istio }}
        {{- end }}
      {{- if .Values.global.tolerations.enabled }}
      {{- if .Values.tolerations }}
      tolerations:
        {{- toYaml .Values.tolerations | nindent 8 }}
      {{- end }}
      {{- end }}
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: {{ .Values.name }}
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: {{ .Values.name }}
      containers:
        - name: {{ .Values.name }}{{- if .Values.global.environment }}-{{ .Values.global.environment }}{{- end }}
          image: {{ .Values.global.imageRegistry }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}
          ports:
            - name: http
              containerPort: {{ .Values.service.targetPort }}
              protocol: TCP
            {{- if .Values.metricsPort }}
            - name: http-metrics
              containerPort: {{ .Values.metricsPort }}
              protocol: TCP
            {{- end }}
          {{- if .Values.probes.enabled }}
          startupProbe:
            {{- toYaml .Values.probes.startup | nindent 12 }}
          livenessProbe:
            {{- toYaml .Values.probes.liveness | nindent 12 }}
          readinessProbe:
            {{- toYaml .Values.probes.readiness | nindent 12 }}
          {{- end }}
          envFrom:
            - configMapRef:
                name: {{ .Values.configMapName }}{{- if and .Values.global.configMapSuffix .Values.global.environment }}-{{ .Values.global.environment }}{{- end }}
          env:
            - name: AWS_REGION
              value: {{ .Values.global.awsRegion }}
            {{- if .Values.config.springConfigLocation }}
            - name: SPRING_CONFIG_LOCATION
              value: {{ .Values.config.springConfigLocation }}
            {{- end }}
            {{- if .Values.global.csiVolumes.enabled }}
            - name: PGSQL_PASS
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.global.secretName }}
                  key: PGSQL_PASS
            {{- end }}
          volumeMounts:
            {{- if .Values.global.csiVolumes.enabled }}
            - name: secrets-store
              mountPath: "/mnt/secrets-store"
              readOnly: true
            {{- end }}
            {{- if .Values.envJsonMount.enabled }}
            - name: config-volume
              mountPath: {{ .Values.envJsonMount.path | default "/usr/share/nginx/html/env.json" }}
              subPath: env.json
            {{- end }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
      volumes:
        {{- if .Values.global.csiVolumes.enabled }}
        - name: secrets-store
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
              secretProviderClass: {{ .Values.global.secretProviderClass }}
        {{- end }}
        {{- if .Values.envJsonMount.enabled }}
        - name: config-volume
          configMap:
            name: {{ .Values.configMapName }}{{- if and .Values.global.configMapSuffix .Values.global.environment }}-{{ .Values.global.environment }}{{- end }}
        {{- end }}
{{- end }}

{{/*
Init containers template
*/}}
{{- define "esim-common.initContainers" -}}
{{- if .Values.global.initContainers.enabled }}
initContainers:
  - name: image-validator
    image: {{ .Values.global.imageRegistry }}/tools:cosign
    imagePullPolicy: Always
    env:
      - name: HOME
        value: /tmp
      - name: KMS_KEY_ARN
        value: {{ .Values.global.kmsKeyArn | quote }}
      - name: IMAGE_URI
        value: "{{ .Values.global.imageRegistry }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}"
      - name: AWS_REGION
        value: {{ .Values.global.awsRegion }}
      - name: AWS_DEFAULT_REGION
        value: {{ .Values.global.awsRegion }}
      - name: AWS_ACCESS_KEY_ID
        valueFrom:
          secretKeyRef:
            name: aws-creds
            key: AWS_ACCESS_KEY_ID
      - name: AWS_SECRET_ACCESS_KEY
        valueFrom:
          secretKeyRef:
            name: aws-creds
            key: AWS_SECRET_ACCESS_KEY
    command:
      - /bin/sh
      - -c
      - |
        echo "Logging into ECR..."
        aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin {{ .Values.global.imageRegistry }}
        echo "Verifying image ${IMAGE_URI} with key ${KMS_KEY_ARN}"
        REPO=$(echo "$IMAGE_URI" | cut -d'/' -f2 | cut -d':' -f1)
        TAG=$(echo "$IMAGE_URI" | cut -d':' -f2)
        REGION=$(echo "$IMAGE_URI" | cut -d'.' -f4)
        ACCOUNT=$(echo "$IMAGE_URI" | cut -d'.' -f1)
        DIGEST=$(aws ecr describe-images \
          --repository-name "$REPO" \
          --image-ids imageTag="$TAG" \
          --region "$REGION" \
          --query 'imageDetails[0].imageDigest' \
          --output text)
        IMAGE_REF="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/${REPO}@${DIGEST}"
        cosign verify --key awskms:///${KMS_KEY_ARN} ${IMAGE_REF} || exit 1
{{- end }}
{{- end }}

{{/*
Service template
*/}}
{{- define "esim-common.service" -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ .Values.name }}-service
  namespace: {{ .Values.global.namespace }}
  labels:
    app: {{ .Values.name }}
    {{- include "esim-common.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type | default "ClusterIP" }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
      protocol: TCP
      name: http
  selector:
    app: {{ .Values.name }}
{{- end }}

{{/*
ConfigMap template
*/}}
{{- define "esim-common.configMap" -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Values.configMapName }}{{- if and .Values.global.configMapSuffix .Values.global.environment }}-{{ .Values.global.environment }}{{- end }}
  namespace: {{ .Values.global.namespace }}
data:
  {{- range $key, $value := .Values.config.data }}
  {{ $key }}: {{ $value | quote }}
  {{- end }}
{{- end }}
