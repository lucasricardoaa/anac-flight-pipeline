# ADR-01: Orquestrador de Pipelines — Apache Airflow 2.8 com TaskFlow API

## Status

Proposta

> _Esta decisão foi tomada durante a fase de planejamento — nenhuma fase do projeto foi implementada. O status será revisado para `Aceita` após implementação e validação em ambiente real._

---

## Contexto

### O problema de orquestração

O pipeline de dados da ANAC precisa executar uma sequência de etapas com dependências explícitas: download dos CSVs mensais, criação do cluster Dataproc, submissão dos jobs PySpark para as camadas Bronze, Silver e Gold, destruição do cluster e notificação de status. Essa sequência tem três requisitos operacionais que eliminam soluções triviais:

- **Retry automático**: falhas transitórias em chamadas à API do GCP não devem interromper o pipeline permanentemente.
- **Dependência entre tasks**: a destruição do cluster deve ocorrer mesmo quando um job PySpark falha — o contrário gera cluster órfão e consumo acidental de créditos GCP.
- **Backfill**: reprocessar meses históricos da ANAC sem scripts externos é um requisito funcional do projeto.

Cron com Python puro não atende nenhum dos três. Qualquer ferramenta de orquestração real atende todos.

### O critério de desempate entre orquestradores

Com os requisitos operacionais básicos satisfeitos por qualquer orquestrador moderno, o critério de desempate veio do objetivo declarado do projeto (documentado na ADR-00): aprendizado orientado ao mercado de vagas de Engenheiro de Dados Pleno no Brasil.

O mapeamento do mercado de vagas no momento da decisão mostrava convergência em torno de Apache Airflow em ambientes enterprise. Prefect e Dagster aparecem em JDs, mas com frequência significativamente menor. Para um portfólio construído com objetivo de sinalização para recrutadores e engenheiros avaliando candidatos Pleno, a escolha do orquestrador não é puramente técnica — é também estratégica.

### Detalhe sobre qual Airflow

A decisão não é apenas "usar Airflow" — é usar Airflow 2.8 com **TaskFlow API exclusivamente**. Essa distinção importa.

O Airflow tem dois estilos de autoria de DAGs que coexistem na documentação e em tutoriais:

1. **API legada**: instanciação explícita de operadores como objetos Python, encadeamento com `>>` fora de funções, passagem de dados via XCom manual com `xcom_push` / `xcom_pull`.
2. **TaskFlow API**: `@dag` para declarar o DAG, `@task` para declarar tasks como funções Python decoradas, passagem de dados entre tasks via retorno de função — XCom gerenciado implicitamente pelo framework.

Este projeto usa exclusivamente a TaskFlow API. O código de DAGs resultante é mais legível, tem menos boilerplate e demonstra conhecimento da API moderna do Airflow — não do Airflow como era operado em 2018. Essa distinção aparece em entrevistas técnicas para vagas Pleno como critério de avaliação real.

---

## Decisão

**Apache Airflow 2.8, usando exclusivamente a TaskFlow API com decorators Python nativos.**

O DAG principal do projeto é declarado com `@dag`. Cada etapa do pipeline — download, criação do cluster, submissão de jobs Spark por camada, destruição do cluster — é declarada com `@task` ou com operadores nativos do GCP (`DataprocCreateClusterOperator`, `DataprocSubmitJobOperator`, `DataprocDeleteClusterOperator`). A passagem de dados entre tasks Python usa retorno de função, com XCom gerenciado implicitamente pelo Airflow.

A task de destruição do cluster usa `trigger_rule='all_done'` para garantir execução independente do status das tasks anteriores. Esse mecanismo é o ponto central da estratégia de proteção contra cluster órfão — detalhada na ADR-04.

---

## Alternativas consideradas

### Prefect

**O que é**: framework de orquestração de workflows em Python com API mais pythônica que o Airflow, UI nativa superior, e observabilidade melhor por padrão — logs estruturados, rastreamento de runs, histórico de execuções com menos configuração.

**Por que foi rejeitado**: menor presença em vagas enterprise no Brasil no momento da decisão. O objetivo de portfólio pesa diretamente aqui: se o objetivo fosse construir um pipeline de produção com mínimo overhead operacional, Prefect seria uma alternativa técnica legítima. Como o objetivo inclui sinalização para o mercado de vagas, o critério de prevalência em JDs é determinante. Prefect perde nesse critério específico.

### Dagster

**O que é**: orquestrador com asset-based orchestration, onde o modelo central são os assets de dados (não tasks ou flows). Data lineage nativo sem configuração adicional. `@asset` e `@op` como primitivas. Tecnicamente mais sofisticado que Airflow para pipelines orientados a dados — observabilidade, rastreabilidade e separação entre lógica de negócio e orquestração são superiores.

**Por que foi rejeitado**: curva de aprendizado maior e menor adoção no mercado brasileiro. O investimento de aprendizado necessário para operar Dagster com profundidade não retorna da mesma forma para o objetivo de portfólio Pleno no Brasil. Em um contexto diferente — time que já conhece Airflow e quer evoluir o stack — Dagster seria uma escolha defensável. Aqui, o custo de adoção não se justifica.

### Cron com Python puro

**O que é**: scripts Python agendados via cron do sistema operacional, sem dependências externas de orquestração.

**Por que foi rejeitado**: não passa no critério mínimo de autenticidade para um portfólio Pleno. Ausência de retry automático, sem modelagem de dependências entre tasks, sem backfill, sem histórico de execuções, sem monitoramento centralizado. Essas ausências não são compensadas pelo zero de overhead operacional — elas tornam o projeto indistinguível de um script de automação pessoal. O objetivo do portfólio requer demonstrar operação de pipeline com maturidade operacional real.

### Cloud Composer (Airflow gerenciado no GCP)

**O que é**: serviço gerenciado do GCP que provisiona e opera um ambiente Airflow sem overhead de infraestrutura.

**Por que foi rejeitado**: custo incompatível com o constraint de $300 em créditos GCP. Um ambiente Cloud Composer mínimo custa aproximadamente $300/mês — equivalente ao orçamento total do projeto. A estratégia de deployment adotada (Airflow em VM e2-medium com Docker Compose) é documentada na ADR-06.

---

## Consequências

### Positivas

- A TaskFlow API reduz boilerplate no código de DAGs: funções Python decoradas com `@task` são mais legíveis do que classes de Operator instanciadas explicitamente.
- Integração nativa com Dataproc via operadores mantidos pelo Google (`DataprocCreateClusterOperator`, `DataprocSubmitJobOperator`, `DataprocDeleteClusterOperator`) — sem necessidade de operadores customizados.
- `trigger_rule='all_done'` na task de destruição do cluster garante que o Dataproc é sempre destruído, independente de falhas em jobs Spark anteriores. Esse mecanismo é o núcleo da estratégia de proteção contra cluster órfão documentada na ADR-04.
- Backfill nativo para reprocessamento de meses históricos da ANAC sem scripts externos — `airflow dags backfill` com intervalos de data é suficiente.
- O portfolio demonstra conhecimento do Airflow moderno (TaskFlow API), não do Airflow legado — distinção relevante para avaliadores técnicos em vagas Pleno.

### Negativas

- Airflow tem overhead operacional maior que Prefect e Dagster para deploy, configuração e manutenção. O scheduler é stateful e exige banco de dados de metadados (PostgreSQL ou MySQL). No contexto desta projeto — VM e2-medium, Docker Compose, single-node — esse overhead é gerenciável, mas existe.
- O modo de alta disponibilidade do Airflow (HA com múltiplos schedulers) não é viável em VM single-node. A ausência de HA é um trade-off consciente documentado na ADR-06.
- A escolha do Airflow sobre Dagster significa abrir mão de asset-based orchestration e data lineage nativo. Esses recursos teriam valor técnico real no projeto — a rejeição do Dagster é puramente estratégica, não técnica.
- Tutoriais e documentação do Airflow misturam a API legada com a TaskFlow API sem sinalização clara. O risco de inconsistência no código (misturar os dois estilos inadvertidamente) requer atenção durante a implementação.

---

## Dependências

**Depende de**: ADR-00 — o objetivo de aprendizado orientado ao mercado e o público-alvo do portfólio são os fatores que determinam a escolha do Airflow sobre Prefect e Dagster. Sem esse contexto, a rejeição de alternativas tecnicamente superiores em alguns aspectos seria incompreensível.

**Esta ADR é dependência de**:

| ADR | Decisão dependente |
|-----|--------------------|
| ADR-04 | Ciclo de vida do cluster Dataproc — o mecanismo de `trigger_rule='all_done'` para proteção contra cluster órfão é uma consequência direta da escolha do Airflow como orquestrador |
| ADR-05 | Integração com qualidade de dados — as assertions de qualidade são executadas como tasks dentro do DAG Airflow |
| ADR-06 | Deployment do Airflow na VM e2-medium com Docker Compose — a estratégia de deployment é consequência direta da escolha do Airflow sobre Cloud Composer |

---

## Referências

- ADR-00: Contexto Global e Constraints do Projeto
- ADR-04: Ciclo de Vida do Cluster Dataproc (a ser criada)
- ADR-05: Qualidade de Dados (a ser criada)
- ADR-06: Deployment do Airflow (a ser criada)
- [Apache Airflow — TaskFlow API](https://airflow.apache.org/docs/apache-airflow/stable/tutorial/taskflow.html)
- [Apache Airflow — Trigger Rules](https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/dags.html#trigger-rules)
- [Google Cloud — Dataproc Operators for Airflow](https://airflow.apache.org/docs/apache-airflow-providers-google/stable/operators/cloud/dataproc.html)
