# Cronograma de Implementação — ANAC Flight Pipeline

## Status geral

| Fase | Descrição | Status |
|------|-----------|--------|
| 0 | Decisões arquiteturais (ADRs) | Concluída |
| 1 | Provisionamento de infraestrutura (Terraform) | Pendente |
| 2 | Deployment do Airflow (VM + Docker Compose) | Pendente |
| 3 | Ingestão de dados (download CSVs ANAC) | Pendente |
| 4 | Camada Bronze (PySpark) | Pendente |
| 5 | Camada Silver (PySpark) | Pendente |
| 6 | Camada Gold (PySpark) | Pendente |
| 7 | Qualidade de dados (assertions PySpark) | Pendente |
| 8 | DAG completo (Airflow + cluster efêmero) | Pendente |
| 9 | Testes e validação end-to-end | Pendente |
| 10 | Documentação e polish de portfólio | Pendente |

---

## Detalhamento por fase

### Fase 1 — Provisionamento de infraestrutura (Terraform)

**ADRs de referência:** ADR-08, ADR-06, ADR-03

**Pré-requisitos:** Resolver os 4 pontos `[VERIFICAR]` da ADR-08 antes de escrever código:
- Backend do Terraform state (local ou GCS)
- Mecanismo de autenticação CI/CD
- Escopo de integração CI/CD
- VPC default ou dedicada

**Recursos a provisionar:**
- VM Compute Engine e2-medium (host do Airflow)
- 3 buckets GCS: `bronze/`, `silver/`, `gold/`
- Service accounts + roles IAM (Airflow, Dataproc)
- Firewall rules para a VM
- Secret Manager secrets (conexões Airflow)
- Configuração base do Dataproc (sem criar cluster — efêmero via DAG)

**Entregável:** `terraform apply` bem-sucedido provisionando toda a infraestrutura persistente do projeto.

---

### Fase 2 — Deployment do Airflow (VM + Docker Compose)

**ADRs de referência:** ADR-06, ADR-01

**Pré-requisitos:** VM provisionada (Fase 1)

**Entregas:**
- `docker-compose.yml` com Airflow 2.8 (webserver, scheduler, LocalExecutor)
- Script de bootstrap (instalação do Docker na VM)
- Airflow acessível via IP externo da VM
- Variáveis de ambiente e conexões GCP configuradas

**Entregável:** Airflow UI acessível, DAG de exemplo rodando com sucesso.

---

### Fase 3 — Ingestão de dados (download CSVs ANAC)

**ADRs de referência:** ADR-07 (Bronze como fonte da verdade imutável)

**Pré-requisitos:** Airflow operacional (Fase 2), bucket Bronze criado (Fase 1)

**Entregas:**
- Script Python de download dos CSVs mensais do portal da ANAC
- Upload para o bucket Bronze no GCS
- Task Airflow para orquestrar o download

**Entregável:** Arquivos CSV históricos disponíveis no bucket Bronze.

---

### Fase 4 — Camada Bronze (PySpark)

**ADRs de referência:** ADR-07, ADR-02, ADR-03

**Pré-requisitos:** Dados no bucket Bronze (Fase 3), cluster Dataproc configurável

**Entregas:**
- Job PySpark de ingestão Bronze: lê CSV → escreve Delta Lake com `schema enforcement`
- Configuração do SparkSession com `delta-spark` e `gcs-connector-hadoop3`
- Validação da combinação de versões Dataproc 2.2 / delta-spark `[VERIFICAR #1]`

**Entregável:** Tabela Delta na camada Bronze com dados históricos da ANAC.

---

### Fase 5 — Camada Silver (PySpark)

**ADRs de referência:** ADR-07, ADR-02, ADR-05

**Pré-requisitos:** Bronze operacional (Fase 4)

**Entregas:**
- Job PySpark de transformação Silver: limpeza, padronização, tipagem correta
- Definição dos campos obrigatórios para promoção Bronze → Silver `[VERIFICAR #6]`
- Remoção de registros inválidos com log de rejeições

**Entregável:** Tabela Delta na camada Silver com dados limpos e validados.

---

### Fase 6 — Camada Gold (PySpark)

**ADRs de referência:** ADR-07, ADR-02

**Pré-requisitos:** Silver operacional (Fase 5)

**Entregas:**
- Job PySpark de agregação Gold: métricas de negócio (rotas, companhias, ocupação)
- Definição do modelo dimensional da camada Gold

**Entregável:** Tabela Delta na camada Gold pronta para consumo analítico.

---

### Fase 7 — Qualidade de dados (assertions PySpark)

**ADRs de referência:** ADR-05, ADR-07

**Pré-requisitos:** Silver e Gold operacionais (Fases 5 e 6)

**Entregas:**
- Assertions Bronze → Silver: campos obrigatórios, domínios de validação `[VERIFICAR #6]`
- Assertions Silver → Gold: contagem de registros (limiar 30%) `[VERIFICAR #7, #9]`
- Cada assertion como task independente no DAG

**Entregável:** Pipeline com qualidade de dados integrada, falha explícita em dado inválido.

---

### Fase 8 — DAG completo (Airflow + cluster efêmero)

**ADRs de referência:** ADR-01, ADR-04, ADR-03

**Pré-requisitos:** Todas as Fases 3–7 concluídas

**Entregas:**
- DAG completo com TaskFlow API
- `DataprocCreateClusterOperator` → jobs Bronze/Silver/Gold → assertions → `DataprocDeleteClusterOperator`
- `trigger_rule='all_done'` na task de destruição do cluster (proteção Camada 1)
- `lifecycle_config.auto_delete_ttl` configurado (proteção Camada 2) `[VERIFICAR #4]`
- Calibração do TTL após primeiras execuções

**Entregável:** Pipeline end-to-end executando via DAG com cluster efêmero.

---

### Fase 9 — Testes e validação end-to-end

**Pré-requisitos:** DAG completo (Fase 8)

**Entregas:**
- Execução completa do pipeline com dataset real
- Validação dos custos reais vs. estimativas das ADRs `[VERIFICAR #3, #5, #8]`
- Teste de resiliência: simulação de falha de job Spark → verificar destruição do cluster
- Calibração do limiar de 30% das assertions `[VERIFICAR #7, #9]`
- Resolução de todos os itens `[VERIFICAR]` remanescentes

**Entregável:** Pipeline validado em execução real, ADRs atualizadas de `Proposta` → `Aceita`.

---

### Fase 10 — Documentação e polish de portfólio

**Pré-requisitos:** Fase 9 concluída

**Entregas:**
- README principal do repositório
- Diagrama de arquitetura (referenciando as ADRs)
- Instruções de reprodução do ambiente (`terraform apply` → Airflow → execução do DAG)
- Atualização do status das ADRs para `Aceita`
- Remoção ou resolução de todos os `[VERIFICAR]` do checklist na ADR-00

**Entregável:** Repositório público pronto para apresentação em processos seletivos.

---

## Dependências entre fases

```
Fase 0 (ADRs) ✓
└── Fase 1 (Terraform)
    └── Fase 2 (Airflow)
        └── Fase 3 (Ingestão)
            └── Fase 4 (Bronze)
                └── Fase 5 (Silver)
                    ├── Fase 6 (Gold)
                    └── Fase 7 (Assertions)
                        └── Fase 8 (DAG completo)
                            └── Fase 9 (Validação)
                                └── Fase 10 (Portfólio)
```

## Itens `[VERIFICAR]` por fase de resolução

| Item | Fase de resolução |
|------|------------------|
| #14, #15, #16, #13 (ADR-08: decisões Terraform) | Antes da Fase 1 |
| #1, #2 (ADR-02: versões Dataproc/delta-spark) | Fase 4 |
| #6 (ADR-05: campos obrigatórios CSV ANAC) | Fase 5 |
| #7, #9 (ADR-05/07: limiar 30% assertions) | Fase 7 → calibrar na Fase 9 |
| #4 (ADR-04: TTL do cluster) | Fase 8 → calibrar na Fase 9 |
| #3, #5, #8 (ADR-03/04/06: preços GCP) | Fase 9 |
| #10, #11, #12 (ADR-08: bootstrap, IAM, lifecycle rules) | Fase 1 |
| #17 (ADR-08: .gitignore tfstate) | Fase 1 |
