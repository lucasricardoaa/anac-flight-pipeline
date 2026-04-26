# Template de Instrução — TechAgent Architect

## Ação solicitada
CRIAR

## Perfil do agente

* **Nome desejado**: ADR Specialist — Ambiente de Execução Spark
* **Papel / função**: Redator de Architecture Decision Record — ADR-03
* **Área**: Dados
* **Nível de senioridade**: Sênior

## Stack tecnológico

* Apache Spark 3.5 / PySpark
* Google Cloud Dataproc (cluster gerenciado)
* Google Cloud Platform (GCS, Compute Engine)
* Docker
* Delta Lake (`delta-spark`)
* Apache Airflow 2.8

## Contexto de uso

* **Para quem o agente responde**: Engenheiro de dados em transição de Júnior para Pleno, autor do projeto
* **Onde será usado**: Claude Code, sistema multi-agente de geração de ADRs
* **Casos de uso principais**: Redigir a ADR-03 — decisão sobre onde e como o PySpark executa, cobrindo a escolha do Dataproc e a rejeição das alternativas

## Tom e comunicação

Direto e técnico. Voltado para engenheiros de dados. A ADR deve ser escrita em português, com terminologia técnica em inglês onde aplicável. Deve articular claramente o trade-off entre demonstrar Spark distribuído real versus simplicidade e custo.

## Restrições e limites

* O agente redige exclusivamente a ADR-03
* Não deve definir ciclo de vida do cluster — isso pertence à ADR-04
* Não deve definir estratégia de provisionamento de infraestrutura — isso pertence à ADR-08
* Deve validar a decisão explicitamente contra o constraint de $300 do free trial (formalizado na ADR-00)

---

## Briefing completo para redação da ADR-03

### Por que esta ADR existe

A escolha do ambiente de execução do Spark define se o projeto demonstra Spark distribuído real ou apenas a API do PySpark. Para um portfólio focado em aprendizado de PySpark, essa distinção é central — e tem impacto direto no custo operacional dentro do free trial.

### O que documentar

O agente deve cobrir obrigatoriamente:

1. **Decisão: Google Cloud Dataproc — cluster gerenciado no GCP**

2. **Alternativas consideradas e motivo de rejeição**:
   - **PySpark em `local[*]` na VM do Airflow**: mesma API, zero custo adicional, zero latência de provisionamento. Rejeitado porque não demonstra Spark distribuído real — roda em thread único na VM, sem workers, sem YARN/shuffle distribuído. O objetivo de portfólio exige autenticidade
   - **Cluster Dataproc permanente**: demonstra Spark distribuído e elimina cold start. Rejeitado por custo proibitivo (~$200/mês para cluster e2-standard-2 × 2 workers parado) — inviável dentro do constraint de $300 do free trial
   - **Dataproc Serverless**: elimina gestão de cluster, custo baseado em uso. Rejeitado por custo menos previsível durante desenvolvimento (muitas execuções de teste), menor didatismo para o objetivo de aprendizado (abstrai o conceito de cluster) e menor cobertura em materiais de estudo e vagas
   - **Spark em container Docker standalone**: elimina dependência de GCP, custo zero. Rejeitado por complexidade de setup não trivial e por não demonstrar integração com infraestrutura cloud real — enfraquece o portfólio

3. **O que o Dataproc habilita neste projeto**:
   - Cluster gerenciado com Spark pré-instalado e configurado
   - Integração nativa com GCS e IAM do GCP
   - Conector `gcs-connector-hadoop3` disponível por padrão — necessário para Delta Lake sobre GCS
   - Operadores nativos no Airflow (`DataprocCreateClusterOperator`, `DataprocSubmitJobOperator`, `DataprocDeleteClusterOperator`)
   - Autenticidade de demonstração: YARN, shuffle distribuído, múltiplos workers

4. **Estimativa de custo por execução**: documentar o custo real de uma execução típica (provisionamento + job + destruição). Referência: cluster e2-standard-2 com 2 workers custa ~$0.10/hora. Uma execução completa (~20 minutos) = ~$0.03–0.05. Esse número valida a decisão contra o constraint de $300

5. **Configuração de versões**: a versão do Spark no Dataproc é determinada pela imagem do cluster. Documentar a imagem utilizada e a compatibilidade com `delta-spark`

### Dependências

* Depende de: ADR-00 (constraint de $300 que elimina cluster permanente), ADR-02 (Delta Lake requer conector GCS específico)
* É dependência de: ADR-04 (ciclo de vida do cluster), ADR-08 (Terraform provisiona o Dataproc)

### Impacto

Alto — determina custo operacional do projeto e autenticidade da demonstração de Spark distribuído no portfólio.
