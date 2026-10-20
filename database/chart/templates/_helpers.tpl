{{/* Names and labels shared by every template. */}}

{{- define "agents-database.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "agents-database.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "agents-database.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "agents-database.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "agents-database.selectorLabels" . }}
app.kubernetes.io/component: database
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "agents-database.selectorLabels" -}}
app.kubernetes.io/name: {{ include "agents-database.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
The name of the secret holding the credentials, required rather than defaulted:
a chart that invents a credential is a chart that ships one.
*/}}
{{- define "agents-database.secretName" -}}
{{- required "auth.existingSecret must name an existing secret holding the database credentials; this chart never generates one" .Values.auth.existingSecret -}}
{{- end -}}

{{/* The claim size, required so that an overlay cannot leave it unset. */}}
{{- define "agents-database.storageSize" -}}
{{- required "persistence.size must be set for this environment" .Values.persistence.size -}}
{{- end -}}
