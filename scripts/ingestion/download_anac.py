"""
download_anac.py — faz o download do Dados_Estatisticos.csv do portal ANAC
e envia para o bucket Bronze no GCS.

Pode ser executado de forma autônoma:
    python scripts/ingestion/download_anac.py --partition 2024/01

Ou chamado programaticamente por uma task Airflow:
    from ingestion.download_anac import download_and_upload
    download_and_upload(partition="2024/01")
"""

import argparse
import logging
import os

import requests
from google.cloud import storage

logger = logging.getLogger(__name__)

ANAC_CSV_URL = (
    "https://sistemas.anac.gov.br/dadosabertos/"
    "Voos%20e%20opera%C3%A7%C3%B5es%20a%C3%A9reas/"
    "Dados%20Estat%C3%ADsticos%20do%20Transporte%20A%C3%A9reo/"
    "Dados_Estatisticos.csv"
)

_PROJECT_ID = os.getenv("GCP_PROJECT_ID", "anac-flight-pipeline")
BRONZE_BUCKET = f"{_PROJECT_ID}-bronze"
BLOB_PREFIX = "raw"

# Tamanho do chunk para streaming do download (8 MB)
_DOWNLOAD_CHUNK_BYTES = 8 * 1024 * 1024

_REQUEST_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (compatible; anac-flight-pipeline/1.0; "
        "+https://github.com/lucasricardoaa/anac-flight-pipeline)"
    )
}


def download_and_upload(partition: str) -> str:
    """
    Faz o download de Dados_Estatisticos.csv da ANAC e envia ao bucket Bronze.

    O arquivo é armazenado em:
        gs://<BRONZE_BUCKET>/raw/<partition>/Dados_Estatisticos.csv

    O particionamento por data de ingestão preserva o histórico de snapshots
    mensais do arquivo (que a ANAC atualiza mensalmente), respeitando o
    princípio de imutabilidade da camada Bronze (ADR-07).

    Args:
        partition: partição de data no formato "YYYY/MM", ex: "2024/01"

    Returns:
        URI GCS do blob enviado, ex: "gs://anac-flight-pipeline-bronze/raw/2024/01/Dados_Estatisticos.csv"

    Raises:
        requests.HTTPError: se o download falhar com erro HTTP
        google.cloud.exceptions.GoogleCloudError: se o upload para GCS falhar
    """
    blob_name = f"{BLOB_PREFIX}/{partition}/Dados_Estatisticos.csv"
    gcs_uri = f"gs://{BRONZE_BUCKET}/{blob_name}"

    client = storage.Client()
    bucket = client.bucket(BRONZE_BUCKET)
    blob = bucket.blob(blob_name)

    logger.info("Iniciando download: %s", ANAC_CSV_URL)
    logger.info("Destino: %s", gcs_uri)

    with requests.get(
        ANAC_CSV_URL,
        stream=True,
        timeout=600,
        headers=_REQUEST_HEADERS,
    ) as response:
        response.raise_for_status()

        content_length = response.headers.get("Content-Length")
        if content_length:
            logger.info(
                "Tamanho esperado: %.1f MB", int(content_length) / 1024 / 1024
            )

        # Streaming direto do HTTP para o GCS, sem buffer em memória.
        # response.raw é o objeto urllib3 bruto; decode_content=True
        # garante descompressão automática de respostas gzip.
        response.raw.decode_content = True
        blob.upload_from_file(
            response.raw,
            content_type="text/csv",
            timeout=600,
        )

    blob.reload()
    size_mb = blob.size / 1024 / 1024
    logger.info("Upload concluído: %s (%.1f MB)", gcs_uri, size_mb)
    return gcs_uri


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Download Dados_Estatisticos.csv da ANAC → GCS Bronze"
    )
    parser.add_argument(
        "--partition",
        required=True,
        metavar="YYYY/MM",
        help='Partição de data, ex: "2024/01"',
    )
    return parser.parse_args()


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    args = _parse_args()
    download_and_upload(partition=args.partition)
