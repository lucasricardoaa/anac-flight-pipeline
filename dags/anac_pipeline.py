"""
anac_pipeline.py — DAG principal do pipeline de dados ANAC.

Orquestra o pipeline batch mensal de ingestão e transformação de dados de
transporte aéreo doméstico brasileiro (ADR-01, ADR-07).

Estado atual (Fase 3):
    - ingest_anac_csv: download do CSV da ANAC → camada Bronze (GCS)

Próximas fases:
    - Fase 4: job PySpark Bronze (CSV → Delta Lake)
    - Fase 5: job PySpark Silver (limpeza e tipagem)
    - Fase 6: job PySpark Gold (agregações)
    - Fase 7: assertions de qualidade de dados (ADR-05)
    - Fase 8: cluster Dataproc efêmero (ADR-03, ADR-04)
"""

from datetime import datetime

from airflow.decorators import dag, task


@dag(
    dag_id="anac_pipeline",
    schedule="@monthly",
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["anac", "bronze", "ingestion"],
    doc_md=__doc__,
)
def anac_pipeline():
    @task()
    def ingest_anac_csv(**context) -> str:
        """
        Faz o download do Dados_Estatisticos.csv da ANAC e envia ao Bronze bucket.

        O arquivo é particionado por data de execução do DAG:
            gs://<BRONZE_BUCKET>/raw/YYYY/MM/Dados_Estatisticos.csv

        Returns:
            URI GCS do arquivo ingerido.
        """
        from ingestion.download_anac import download_and_upload

        execution_date = context["data_interval_start"]
        partition = execution_date.strftime("%Y/%m")
        return download_and_upload(partition=partition)

    ingest_anac_csv()


anac_pipeline()
