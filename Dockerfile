FROM apache/airflow:2.8.0

USER airflow

# Instala o provider Google com versão compatível com Airflow 2.8.0 (ADR-01, ADR-06)
COPY requirements.txt /opt/airflow/requirements.txt
RUN pip install --no-cache-dir -r /opt/airflow/requirements.txt
