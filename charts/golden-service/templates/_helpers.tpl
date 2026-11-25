{{- define "golden.name" -}}
{{- required "nameOverride is required" .Values.nameOverride -}}
{{- end -}}
{{- define "golden.labels" -}}
app.kubernetes.io/name: {{ include "golden.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
team: {{ .Values.team | quote }}
{{- end -}}
{{- define "golden.selector" -}}
app.kubernetes.io/name: {{ include "golden.name" . }}
{{- end -}}
