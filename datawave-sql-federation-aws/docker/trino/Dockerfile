# Author: Sunil Poricha - Cloud SRE - Technical Assessment 2026
#
# Custom Trino image: base Trino + Ranger authorization plugin + our audit
# event listener config baked in. Catalog properties are mounted at runtime
# via Kubernetes ConfigMap/Secret, NOT baked into the image (12-factor / no
# secrets in images).

FROM trinodb/trino:451

LABEL maintainer="Sunil Poricha - Cloud SRE - Technical Assessment 2026"
LABEL description="DataWave SQL Federation - Trino engine with Ranger + audit event listener"

USER root

# Ranger authorizer plugin for Trino (fine-grained, policy-based access control)
COPY plugins/ranger-trino-plugin/ /usr/lib/trino/plugin/ranger/

# Audit event listener config - ships query events to Elasticsearch/OpenSearch
COPY etc/event-listener.properties /etc/trino/event-listener.properties

# Drop back to the non-root trino user shipped in the base image
USER trino

HEALTHCHECK --interval=15s --timeout=5s --start-period=60s --retries=5 \
  CMD curl -sf http://localhost:8080/v1/info || exit 1
